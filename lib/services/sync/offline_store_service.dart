// lib/services/sync/offline_store_service.dart
// Письма на телефоне: что хранится заранее и что очищается.
//
// Модель (решение владельца 11.10.2026, по образцу Nine: «Email download
// size» + «Days to sync», вложения — отдельно):
//   · ТЕКСТ письма — HTML с оформлением, таблицами, стилями — хранится для
//     всех писем периода синхронизации ящика: письма открываются сразу и
//     без сети, поиск идёт по тексту (поисковый индекс обновляется). Размер
//     ограничивает режим загрузки: «до 50 / 100 / 500 КБ» считает текст с
//     оформлением и встроенные картинки, вложения не считаются; письмо
//     крупнее — при открытии.
//   · ВСТРОЕННЫЕ КАРТИНКИ (подписи, схемы в тексте) — заранее только для
//     свежих писем (Настройки → Почта → «Картинки в письмах»: 3 дня, неделя
//     — по умолчанию, 2 недели, месяц); у писем старше — удаляются с
//     телефона несколько раз в сутки и загружаются снова при открытии.
//     Рабочая неделя открывается быстро, память не забивается.
//   · ВЛОЖЕНИЯ — по режиму загрузки («с вложениями» — заранее, иначе по
//     нажатию), как раньше.
//   · Удалённые письма, «Корзина» и «Спам» — ничего не загружается, файлы
//     и картинки таких писем удаляются из кэша.
// Работа — после каждой синхронизации ящика, в фоне, порциями, с паузой
// между письмами; запись в базу — пачками. Тексты маленькие и грузятся по
// любой сети (как сама синхронизация); сбой связи — до следующего раза.
//
// 1.5.6 — нагрузка на процессор и плавность (замечания 11.10.2026):
//   · письма без текста ищутся по длине поля (octet_length), а не сравнением
//     текста: раньше каждый проход читал и расшифровывал тексты всех писем;
//   · ActiveSync — тексты пачками по 8 писем в одном запросе ItemOperations,
//     картинки письма — тоже одним запросом;
//   · запись в базу «тихая» (лента не перечитывается на каждую пачку),
//     поисковый индекс — одной транзакцией на пачку;
//   · картинки уже проверенных писем не перепроверяются, HTML читается
//     только у новых кандидатов;
//   · папки, отключённые в «Синхронизации папок» (и «Вся почта» Gmail), не
//     докачиваются;
//   · открытие письма приостанавливает докачку на несколько секунд;
//   · проход, которому нечего делать, повторяется не чаще раза в 2 минуты.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/platform_diagnostics.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/security/mail_body_processor.dart';
import '../../core/utils/text_safe.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../mail/attachment_cache_service.dart';
import '../mail/engine/mail_engine_service.dart';
import '../background/work_scheduler.dart';
import '../mail/imap/imap_service.dart';

final offlineStoreProvider = Provider<OfflineStoreService>((ref) => OfflineStoreService(ref));

/// Сколько писем с текстом на телефоне и сколько ещё ждут загрузки.
typedef OfflineStats = ({int stored, int waiting});

class OfflineStoreService {
  final Ref _ref;
  OfflineStoreService(this._ref);

  /// «Картинки в письмах»: сколько дней хранить встроенные картинки.
  static const imagesPrefKey = 'offline_images_days';
  static const defaultImageDays = 7;
  static const imageChoices = [3, 7, 14, 30];

  int get imageDays => _ref.read(sharedPrefsProvider).getInt(imagesPrefKey) ?? defaultImageDays;

  /// Ограничение размера письма (текст и встроенные картинки) по режиму
  /// загрузки; null — без ограничения, 0 — заранее не загружать.
  static int? bodyLimit(EmailFetchMode m) => switch (m) {
        EmailFetchMode.headersOnly => 0,
        EmailFetchMode.partial50k => 50 * 1024,
        EmailFetchMode.partial100k => 100 * 1024,
        EmailFetchMode.partial500k => 500 * 1024,
        EmailFetchMode.noAttachments || EmailFetchMode.full => null,
      };

  /// loadedLevel: 1 — письмо больше ограничения режима, заранее не грузится.
  static const _levelTooBig = 1;
  static const _levelBody = AppDatabase.levelIndexed;

  final Set<String> _running = {};

  /// Письма, для которых сервер не отдал текста (пустые, удалены на
  /// сервере): не спрашивать снова каждые несколько минут.
  final Map<String, DateTime> _noBody = {};
  static const _noBodyRetry = Duration(hours: 12);

  /// Писем за один проход (остальные — со следующей синхронизацией).
  static const _maxBodies = 300;

  /// Писем ActiveSync в одном запросе ItemOperations.
  static const _easBatch = 8;
  static const _maxInlineBytes = 3 * 1024 * 1024;
  static const _inlineBudget = 40 * 1024 * 1024;
  static const _maxRun = Duration(minutes: 6);

  /// Очистка картинок старых писем и кэша удалённых — не чаще этого.
  static const _cleanupEvery = Duration(hours: 4);

  /// Проход, которому нечего было делать, — не чаще этого (синхронизация
  /// по push бывает раз в несколько секунд).
  static const _idleEvery = Duration(minutes: 2);
  final Map<String, DateTime> _idleAt = {};

  /// Письма, картинки которых уже на телефоне (или получить их нельзя): в
  /// следующих проходах их HTML не читается.
  final Set<String> _imagesDone = {};

  bool get _online => _ref.read(connectivityServiceProvider).isConnected;

  // ─────────────────────────── нагрузка ───────────────────────────

  /// Сколько работы позволить проходу — по состоянию телефона (1.5.7,
  /// замечание 11.10.2026 о батарее и процессоре):
  ///   · приложение открыто или телефон заряжается — полный проход;
  ///   · свёрнуто, на батарее — только свежая почта (2 дня, до 40 писем,
  ///     до минуты): пришедшее письмо откроется без сети, а старое докачается,
  ///     когда приложение откроют или поставят на зарядку;
  ///   · режим энергосбережения или заряд меньше 20 % — только письма за
  ///     сутки (до 15), картинки заранее не загружаются.
  Future<_Budget> _budget() async {
    var open = false;
    try {
      // В фоновом изоляте (WorkManager) окна нет — считается «свёрнуто».
      open = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } catch (_) {}
    Map<String, dynamic> d = const {};
    try {
      d = await PlatformDiagnostics.collect(light: true);
    } catch (_) {}
    final charging = d['charging'] == true;
    final pct = d['batteryPct'] is int ? d['batteryPct'] as int : 100;
    final saver = d['powerSaveMode'] == true || d['lowPowerMode'] == true;
    if (!charging && (saver || pct < 20)) {
      return _Budget(_maxBodiesLow, const Duration(seconds: 30), DateTime.now().subtract(const Duration(days: 1)),
          images: false, label: 'экономия заряда');
    }
    if (open || charging) return const _Budget(_maxBodies, _maxRun, null, images: true, label: 'полный');
    return _Budget(_maxBodiesBg, const Duration(minutes: 1), DateTime.now().subtract(const Duration(days: 2)),
        images: true, label: 'в фоне');
  }

  static const _maxBodiesBg = 40;
  static const _maxBodiesLow = 15;

  // ─────────────────────────── пауза ───────────────────────────

  /// Приложение открыли: отложенная в фоне докачка — при следующей
  /// синхронизации, без ожидания двухминутной паузы.
  void wake() => _idleAt.clear();

  /// Открыто письмо: докачка ждёт несколько секунд — соединение с сервером
  /// и процессор нужны открытому письму (его тексту, картинкам). С 1.5.9 —
  /// общая пауза планировщика: заодно синхронизация идёт по одной папке.
  void hold([Duration d = const Duration(seconds: 4)]) => WorkScheduler.instance.hold(d);

  Future<void> _waitHold() => WorkScheduler.instance.whenNotHolding();

  // ─────────────────────────── проход ───────────────────────────

  /// Докачать тексты и картинки ящика, убрать лишнее из кэша (в фоне,
  /// один проход на ящик одновременно).
  Future<void> run(AccountModel account) async {
    final idle = _idleAt[account.id];
    if (idle != null && DateTime.now().difference(idle) < _idleEvery) return;
    if (!_running.add(account.id)) return;
    try {
      await _cleanup(account);
      final budget = await _budget();
      // Тексты, сохранённые при открытии письма, — в поиск и превью (без
      // сети и при любом режиме загрузки).
      final indexed = await _catchUpIndex(account, budget);
      final limit = bodyLimit(_ref.read(settingsProvider).emailFetchMode);
      if (limit == 0 || !_online) return;
      final started = DateTime.now();
      final bodies = await _bodies(account, started, limit, budget);
      final images = budget.images
          ? await _inlineImages(account, started, limit, budget)
          : (done: 0, candidates: 0);
      if (bodies.done > 0 || images.done > 0) {
        AppLogger.info('Письма на телефоне ${account.email}: текстов ${bodies.done}, '
            'картинок ${images.done} (${budget.label})');
      }
      // Нечего делать или работа отложена до открытия / зарядки — следующий
      // проход не раньше чем через 2 минуты.
      if ((bodies.candidates == 0 && images.candidates == 0 && !indexed.more) || budget.since != null) {
        _idleAt[account.id] = DateTime.now();
      } else {
        _idleAt.remove(account.id);
      }
    } catch (e) {
      AppLogger.debug('Письма на телефоне ${account.email}: $e');
    } finally {
      _running.remove(account.id);
    }
  }

  /// Самая ранняя дата писем ящика (период синхронизации); null — все.
  DateTime? _syncCutoff(AccountModel a) =>
      a.syncDays > 0 ? DateTime.now().subtract(Duration(days: a.syncDays)) : null;

  static const _skipTypes = [FolderType.trash, FolderType.junk, FolderType.outbox];

  /// Папки, письма которых заранее не загружаются: «Корзина», «Спам»,
  /// «Исходящие» и папки, выключенные в синхронизации (у Gmail это «Вся
  /// почта» и «Помеченные» — копии писем из других папок: их тексты
  /// качались вторично).
  Future<List<String>> _skipFolders(AppDatabase db, String accountId) async {
    final rows = await (db.select(db.folders)
          ..where((f) =>
              f.accountId.equals(accountId) &
              (f.type.isIn([for (final t in _skipTypes) t.index]) | f.isSynced.equals(false))))
        .get();
    return [for (final r in rows) r.id];
  }

  /// [_skipFolders] для текстов: у ActiveSync — и результаты поиска на
  /// сервере (это не письма папок ящика).
  Future<List<String>> _skipForBodies(AppDatabase db, AccountModel account) async {
    final skip = await _skipFolders(db, account.id);
    if (account.usesEas) skip.add(MailEngineService.easSearchFolderId);
    return skip;
  }

  /// Отбор писем ящика, которым нужен текст (те же условия — для счётчика
  /// «На телефоне»).
  Future<SimpleSelectStatement<$EmailsTable, Email>> _needBodyQuery(
      AppDatabase db, AccountModel account, int? limit) async {
    final skip = await _skipForBodies(db, account);
    final hasBody = await db.hasBodySql();
    final cutoff = _syncCutoff(account);
    final q = db.select(db.emails)
      ..where((e) => e.accountId.equals(account.id) & CustomExpression<bool>('NOT $hasBody'));
    // С ограничением размера крупные письма, уже отмеченные, не повторяются.
    if (limit != null) q.where((e) => e.loadedLevel.equals(_levelTooBig).not());
    if (skip.isNotEmpty) q.where((e) => e.folderId.isNotIn(skip));
    if (cutoff != null) q.where((e) => e.receivedAt.isBiggerOrEqualValue(cutoff));
    return q;
  }

  // ─────────────────────────── тексты ───────────────────────────

  Future<({int done, int candidates})> _bodies(
      AccountModel account, DateTime started, int? limit, _Budget budget) async {
    final db = _ref.read(databaseProvider);
    final q = await _needBodyQuery(db, account, limit);
    final since = budget.since;
    if (since != null) q.where((e) => e.receivedAt.isBiggerOrEqualValue(since));
    q
      ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
      ..limit(budget.maxBodies);
    final now = DateTime.now();
    final rows = [
      for (final r in await q.get())
        if (!(now.difference(_noBody['${account.id}|${r.id}'] ?? DateTime(0)) < _noBodyRetry)) r,
    ];
    if (rows.isEmpty) return (done: 0, candidates: 0);
    var done = 0;
    var failures = 0;
    // Запись в базу — пачками и без оповещения списков (см. storeBodiesQuietly).
    final pending = <Email, _BodyUpdate>{};
    // Новые превью: лента узнаёт о них не чаще раза в 15 с и в конце прохода.
    var previews = 0;
    var shownAt = DateTime.now();
    void showPreviews({bool force = false}) {
      if (previews == 0 || (!force && DateTime.now().difference(shownAt) < const Duration(seconds: 15))) return;
      previews = 0;
      shownAt = DateTime.now();
      db.notifyUpdates({TableUpdate.onTable(db.emails, kind: UpdateKind.update)});
    }

    Future<void> flush() async {
      if (pending.isEmpty) return;
      final items = Map.of(pending);
      pending.clear();
      final plain = await _plainOf(items);
      // Превью с переносами строк (1.6.31): у EWS и IMAP превью при
      // синхронизации — одной строкой (с сервера); с полным текстом письма
      // оно заменяется многострочным для настройки «строк в ленте».
      final multi = await MailBodyProcessor.previewAll({
        for (final e in items.entries)
          if (!e.value.tooBig) e.key.id: (plain: e.value.plain, html: e.value.html),
      });
      final rows = <String, Map<String, Object?>>{};
      for (final e in items.entries) {
        final cols = {...e.value.columns()};
        final mp = multi[e.key.id];
        final empty = (e.key.bodyPreview ?? '').trim().isEmpty;
        if (mp != null && (empty || (mp.contains('\n') && mp != e.key.bodyPreview))) {
          cols['body_preview'] = mp;
          previews++;
        } else if (empty) {
          // Превью для ленты, если его не было: IMAP при синхронизации получает
          // только заголовки, а лента (1.5.8) читает строки без текстов.
          final p = previewOf(plain[e.key.id]);
          if (p != null) {
            cols['body_preview'] = p;
            previews++;
          }
        }
        rows[e.key.id] = cols;
      }
      await db.storeBodiesQuietly(account.id, rows);
      await _reindex(db, account.id, items, plain);
      showPreviews();
    }

    void accept(Email r, _BodyUpdate? u) {
      if (u == null) {
        _noBody['${account.id}|${r.id}'] = DateTime.now();
        return;
      }
      pending[r] = u;
      if (u.html != null || u.plain != null) done++;
    }

    try {
      if (account.usesEas) {
        // ActiveSync: пачками в одном запросе.
        final list = rows;
        for (var i = 0; i < list.length; i += _easBatch) {
          if (DateTime.now().difference(started) > budget.maxRun || !_online) break;
          await _waitHold();
          final chunk = list.sublist(i, i + _easBatch > list.length ? list.length : i + _easBatch);
          try {
            final got = await _ref.read(mailEngineServiceProvider).fetchFullBodiesEas(
                account, [for (final r in chunk) (folderId: r.folderId, serverId: r.id)]);
            for (final r in chunk) {
              final b = got[r.id];
              accept(r, b == null ? null : _update(b.bodyHtml, b.bodyPlain, null, limit));
            }
            failures = 0;
          } catch (e) {
            AppLogger.debug('Письма на телефоне: тексты ActiveSync — $e');
            if (++failures >= 2) break; // связь пропала — до следующей синхронизации
          }
          await flush();
          // Не забирать соединение у действий пользователя.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      } else {
        // IMAP и EWS — по письму. Разбор письма IMAP (MIME) идёт в главном
        // потоке, поэтому за проход — не больше 120 писем и пауза побольше:
        // докачка не должна мешать ленте.
        var n = 0;
        for (final r in rows) {
          if (DateTime.now().difference(started) > budget.maxRun || !_online || ++n > 120) break;
          await _waitHold();
          try {
            accept(r, await _fetchBody(account, r, limit));
            if (pending.length >= 10) await flush();
            failures = 0;
          } catch (e) {
            AppLogger.debug('Письма на телефоне: текст ${r.id}: $e');
            if (++failures >= 3) break; // связь пропала — до следующей синхронизации
          }
          // Не забирать соединение и процессор у действий пользователя.
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } finally {
      await flush();
      showPreviews(force: true);
    }
    return (done: done, candidates: rows.length);
  }

  /// Текст письма для записи в базу (null — сервер не отдал). Больше
  /// ограничения — только отметка «крупное».
  static _BodyUpdate? _update(String? html, String? plain, EmailModel? full, int? limit) {
    if ((html ?? '').isEmpty && (plain ?? '').isEmpty) return null;
    if (limit != null) {
      final size = utf8.encode(html ?? '').length + utf8.encode(plain ?? '').length;
      if (size > limit) return const _BodyUpdate.tooBig();
    }
    return _BodyUpdate(
      html: html,
      plain: plain,
      attachmentsJson: (full == null || full.attachments.isEmpty)
          ? null
          : jsonEncode(full.attachments.map((a) => a.toMap()).toList()),
      authResults: (full?.authResults ?? '').isEmpty ? null : full!.authResults,
      listUnsubscribe: full?.listUnsubscribe,
    );
  }

  /// Полный текст письма с сервера (IMAP, EWS).
  Future<_BodyUpdate?> _fetchBody(AccountModel account, Email r, int? limit) async {
    EmailModel? full;
    if (account.usesEws || account.isExchange) {
      full = await _ref.read(mailEngineServiceProvider).fetchEmailDetailEws(account, r.id);
    } else {
      final uid = int.tryParse(r.id.split(':').last) ?? 0;
      if (uid <= 0) return null;
      full = await _ref
          .read(imapServiceProvider)
          .getEmailDetail(account, folderId: r.folderId, uid: uid, fetchMode: EmailFetchMode.noAttachments);
    }
    return _update(full?.bodyHtml, full?.bodyPlain, full, limit);
  }

  /// Доиндексация: тексты, сохранённые не этим сервисом (открытие письма,
  /// старые версии), не попадали в поисковый индекс — письмо не находилось по
  /// словам из текста, — и не давали превью ленте. Уровень 0 с текстом →
  /// индекс, превью, уровень 2. Пачкой, по бюджету прохода; после разовой
  /// разметки уже проиндексированного (MaintenanceService), иначе первый
  /// проход переиндексировал бы тексты, пришедшие с синхронизацией ActiveSync.
  Future<({int done, bool more})> _catchUpIndex(AccountModel account, _Budget budget) async {
    if (!(_ref.read(sharedPrefsProvider).getBool(indexMarkedPrefKey) ?? false)) {
      return (done: 0, more: false);
    }
    final db = _ref.read(databaseProvider);
    final max = budget.maxBodies < 100 ? budget.maxBodies : 100;
    try {
      final hasBody = await db.hasBodySql();
      // Свои черновики и исходящие меняются, пока их пишут, — не сюда.
      final skip = [...await _skipForBodies(db, account), 'drafts', 'outbox'];
      // Уровень не 2: 0 — сохранён при открытии, 1 — «крупное» письмо,
      // которое потом открыли.
      final q = db.select(db.emails)
        ..where((e) =>
            e.accountId.equals(account.id) &
            e.loadedLevel.equals(_levelBody).not() &
            CustomExpression<bool>(hasBody))
        ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
        ..limit(max);
      q.where((e) => e.folderId.isNotIn(skip));
      final rows = await q.get();
      if (rows.isEmpty) return (done: 0, more: false);
      final items = <Email, _BodyUpdate>{
        for (final r in rows) r: _BodyUpdate(html: r.bodyHtml, plain: r.bodyPlain),
      };
      final plain = await _plainOf(items);
      final cols = <String, Map<String, Object?>>{};
      for (final r in rows) {
        final p = (r.bodyPreview ?? '').trim().isEmpty ? previewOf(plain[r.id]) : null;
        cols[r.id] = {'loaded_level': _levelBody, if (p != null) 'body_preview': p};
      }
      await db.storeBodiesQuietly(account.id, cols);
      await _reindex(db, account.id, items, plain);
      AppLogger.debug('Письма на телефоне ${account.email}: в поиск добавлено ${rows.length}');
      return (done: rows.length, more: rows.length >= max);
    } catch (e) {
      AppLogger.debug('Письма на телефоне: доиндексация — $e');
      return (done: 0, more: false);
    }
  }

  /// Разметка уже проиндексированных текстов выполнена (MaintenanceService).
  static const indexMarkedPrefKey = 'db_bodies_indexed_v1';

  /// Текст загруженных писем для поиска и превью (id → текст): готовый
  /// text/plain или текст из HTML — пачкой в изоляте.
  static Future<Map<String, String>> _plainOf(Map<Email, _BodyUpdate> items) async {
    final out = <String, String>{};
    final htmls = <String, String>{};
    for (final e in items.entries) {
      final u = e.value;
      if (u.tooBig) continue;
      final p = u.plain;
      if (p != null && p.isNotEmpty) {
        out[e.key.id] = p;
      } else if ((u.html ?? '').isNotEmpty) {
        htmls[e.key.id] = u.html!;
      }
    }
    if (htmls.isNotEmpty) {
      try {
        out.addAll(await MailBodyProcessor.htmlToPlainAll(htmls));
      } catch (e) {
        AppLogger.debug('Письма на телефоне: текст из HTML — $e');
      }
    }
    return out;
  }

  /// Поиск по тексту: загруженные письма — в поисковый индекс (раньше в нём
  /// было только начало письма из синхронизации). Одной транзакцией.
  Future<void> _reindex(
      AppDatabase db, String accountId, Map<Email, _BodyUpdate> items, Map<String, String> plain) async {
    try {
      final batch = <({String emailId, String subject, String fromText, String body})>[];
      for (final e in items.entries) {
        if (e.value.tooBig) continue;
        final r = e.key;
        final body = plain[r.id] ?? '';
        if (body.isEmpty) continue;
        batch.add((
          emailId: r.id,
          subject: r.subject,
          fromText: '${r.fromName ?? ''} ${r.fromEmail}',
          body: body.length > 20000 ? body.substring(0, 20000) : body,
        ));
      }
      await db.indexEmailFtsBatch(accountId, batch);
    } catch (e) {
      AppLogger.debug('Письма на телефоне: поисковый индекс — $e');
    }
  }

  // ─────────────────────────── картинки ───────────────────────────

  /// Встроенные картинки письма, на которые ссылается текст (cid).
  static List<EmailAttachment> _inlineOf(Email r) {
    final html = (r.bodyHtml ?? '').toLowerCase();
    if (!html.contains('cid:') || r.attachmentsJson == null) return const [];
    return _inlineOfLower(html, r.attachmentsJson!);
  }

  static List<EmailAttachment> _inlineOfLower(String lowerHtml, String attachmentsJson) {
    try {
      return [
        for (final m in (jsonDecode(attachmentsJson) as List).whereType<Map>())
          EmailAttachment.fromMap(Map<String, dynamic>.from(m)),
      ].where((a) {
        // Запасные картинки Outlook (.wmz/.emz) не показываются — не качаем.
        if (a.isVmlPreview) return false;
        var cid = (a.contentId ?? '').trim().toLowerCase();
        if (cid.isEmpty) return false;
        if (cid.startsWith('<') && cid.endsWith('>')) cid = cid.substring(1, cid.length - 1);
        return lowerHtml.contains('cid:$cid');
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Встроенные картинки свежих писем — в кэш вложений.
  Future<({int done, int candidates})> _inlineImages(
      AccountModel account, DateTime started, int? limit, _Budget budget) async {
    final db = _ref.read(databaseProvider);
    final cache = _ref.read(attachmentCacheProvider);
    await cache.ensureLoaded();
    final skip = await _skipFolders(db, account.id);
    var since = DateTime.now().subtract(Duration(days: imageDays));
    final bs = budget.since;
    if (bs != null && bs.isAfter(since)) since = bs;
    // Кандидаты — по списку вложений (маленькая колонка), без чтения HTML.
    final id = db.emails.id;
    final q = db.selectOnly(db.emails)
      ..addColumns([id])
      ..where(db.emails.accountId.equals(account.id) &
          db.emails.attachmentsJson.like('%contentId%') &
          db.emails.receivedAt.isBiggerOrEqualValue(since))
      ..orderBy([OrderingTerm(expression: db.emails.receivedAt, mode: OrderingMode.desc)])
      ..limit(300);
    if (skip.isNotEmpty) q.where(db.emails.folderId.isNotIn(skip));
    final ids = [
      for (final r in await q.get())
        if (!_imagesDone.contains('${account.id}|${r.read(id)}')) r.read(id)!,
    ];
    if (ids.isEmpty) return (done: 0, candidates: 0);
    var done = 0;
    var bytesTotal = 0;
    var failures = 0;
    try {
      // Сначала — без HTML, по списку вложений: письма, у которых все
      // встроенные картинки (Content-ID) уже на телефоне, отмечаются сразу.
      // После перезапуска приложения проход раньше перечитывал HTML до 300
      // писем, чтобы убедиться, что докачивать нечего (аудит 11.10.2026).
      final pre = <String>[];
      for (var i = 0; i < ids.length; i += 200) {
        final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
        final e = db.emails;
        final light = await (db.selectOnly(e)
              ..addColumns([e.id, e.attachmentsJson])
              ..where(e.accountId.equals(account.id) & e.id.isIn(chunk)))
            .get();
        for (final r in light) {
          final eid = r.read(e.id)!;
          var allCached = true;
          try {
            for (final m in (jsonDecode(r.read(e.attachmentsJson) ?? '[]') as List).whereType<Map>()) {
              final a = EmailAttachment.fromMap(Map<String, dynamic>.from(m));
              if ((a.contentId ?? '').trim().isEmpty || a.isVmlPreview || a.size > _maxInlineBytes) continue;
              if (!cache.has(MailEngineService.attachmentCacheKey(account.id, eid, a.id))) {
                allCached = false;
                break;
              }
            }
          } catch (_) {
            allCached = false;
          }
          if (allCached) {
            _imagesDone.add('${account.id}|$eid');
          } else {
            pre.add(eid);
          }
        }
      }
      ids
        ..clear()
        ..addAll(pre);
      // HTML — только у писем, где картинок на телефоне ещё нет, порциями.
      for (var i = 0; i < ids.length; i += 20) {
        if (DateTime.now().difference(started) > budget.maxRun || bytesTotal > _inlineBudget || !_online) break;
        final chunk = ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20);
        final rows = await (db.select(db.emails)
              ..where((e) => e.accountId.equals(account.id) & e.id.isIn(chunk))
              ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)]))
            .get();
        for (final r in rows) {
          if (DateTime.now().difference(started) > budget.maxRun || bytesTotal > _inlineBudget || !_online) break;
          final doneKey = '${account.id}|${r.id}';
          final atts = _inlineOf(r);
          // Ограничение режима — на текст и картинки вместе (вложения не в счёт).
          var letter = limit == null ? 0 : utf8.encode(r.bodyHtml ?? '').length;
          final need = <EmailAttachment>[];
          for (final a in atts) {
            if (a.size > _maxInlineBytes) continue;
            if (limit != null && letter + a.size > limit) break;
            final key = MailEngineService.attachmentCacheKey(account.id, r.id, a.id);
            if (cache.has(key)) {
              letter += a.size;
              continue;
            }
            need.add(a);
            letter += a.size;
          }
          if (need.isEmpty) {
            _imagesDone.add(doneKey);
            continue;
          }
          await _waitHold();
          try {
            // ActiveSync — одним запросом на письмо, остальные — по очереди.
            final got = await _ref
                .read(mailEngineServiceProvider)
                .getAttachmentsBytes(account, [for (final a in need) a.id], emailId: r.id);
            for (final a in need) {
              final b = got[a.id];
              if (b == null) continue;
              await cache.put(MailEngineService.attachmentCacheKey(account.id, r.id, a.id), a.name, b,
                  keepUntil: r.receivedAt.add(Duration(days: imageDays)), deferPersist: true);
              bytesTotal += b.length;
              done++;
            }
            // Чего сервер не отдал, не спрашиваем снова до перезапуска.
            _imagesDone.add(doneKey);
            failures = 0;
          } catch (e) {
            AppLogger.debug('Письма на телефоне: картинки ${r.id}: $e');
            if (++failures >= 3) return (done: done, candidates: ids.length);
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    } finally {
      await cache.flush();
    }
    return (done: done, candidates: ids.length);
  }

  // ─────────────────────────── счётчик ───────────────────────────

  /// «Текст на телефоне: N писем · ждут загрузки: M» — по всем ящикам и по
  /// тем же правилам, что и докачка: только период синхронизации, без
  /// «Корзины», «Спама», выключенных папок и писем крупнее ограничения
  /// режима. Раньше счёт шёл по всем письмам базы — с письмами старше
  /// периода и копиями «Вся почта» Gmail, которые не докачиваются.
  Future<OfflineStats> stats(List<AccountModel> accounts) async {
    final db = _ref.read(databaseProvider);
    final limit = bodyLimit(_ref.read(settingsProvider).emailFetchMode);
    final hasBody = await db.hasBodySql();
    var stored = 0;
    var waiting = 0;
    for (final a in accounts.where((a) => a.isActive)) {
      final skip = await _skipForBodies(db, a);
      final cutoff = _syncCutoff(a);
      Future<int> count(bool withBody) async {
        final n = db.emails.id.count();
        final q = db.selectOnly(db.emails)
          ..addColumns([n])
          ..where(db.emails.accountId.equals(a.id) &
              CustomExpression<bool>(withBody ? hasBody : 'NOT $hasBody'));
        if (!withBody && limit != null) q.where(db.emails.loadedLevel.equals(_levelTooBig).not());
        if (skip.isNotEmpty) q.where(db.emails.folderId.isNotIn(skip));
        if (cutoff != null) q.where(db.emails.receivedAt.isBiggerOrEqualValue(cutoff));
        return (await q.map((r) => r.read(n)).getSingle()) ?? 0;
      }

      stored += await count(true);
      waiting += await count(false);
    }
    return (stored: stored, waiting: waiting);
  }

  // ─────────────────────────── очистка ───────────────────────────

  /// Несколько раз в сутки: картинки писем старше срока «Картинки в
  /// письмах» и всё, что в кэше от удалённых писем, «Корзины» и «Спама».
  /// Тексты писем остаются (они нужны для поиска и занимают мало места).
  Future<void> _cleanup(AccountModel account) async {
    final prefs = _ref.read(sharedPrefsProvider);
    final key = 'offline_cleanup_${account.id}';
    final now = DateTime.now();
    if (now.millisecondsSinceEpoch - (prefs.getInt(key) ?? 0) < _cleanupEvery.inMilliseconds) return;
    await prefs.setInt(key, now.millisecondsSinceEpoch);
    try {
      final removed = await cleanupCache(account.id, olderThan: now.subtract(Duration(days: imageDays)));
      if (removed > 0) AppLogger.info('Письма на телефоне ${account.email}: из кэша убрано $removed файлов');
    } catch (e) {
      AppLogger.debug('Письма на телефоне: очистка — $e');
    }
  }

  /// Убрать из кэша ящика: файлы и картинки писем, которых больше нет
  /// (удалены здесь, на сервере или автоочисткой), писем в «Корзине» и
  /// «Спаме», и встроенные картинки писем старше [olderThan]. Вложения,
  /// которые открывали, у живых писем остаются (их чистит сам кэш по
  /// давности и объёму). Возвращает число убранных записей.
  Future<int> cleanupCache(String accountId, {required DateTime olderThan}) async {
    final db = _ref.read(databaseProvider);
    final cache = _ref.read(attachmentCacheProvider);
    await cache.ensureLoaded();
    final prefix = '$accountId|';
    // Ключ: «аккаунт|письмо|вложение»; id вложения — после последней «|».
    final byEmail = <String, List<String>>{};
    for (final k in cache.keys) {
      if (!k.startsWith(prefix)) continue;
      final rest = k.substring(prefix.length);
      final sep = rest.lastIndexOf('|');
      if (sep <= 0) continue;
      byEmail.putIfAbsent(rest.substring(0, sep), () => []).add(k);
    }
    if (byEmail.isEmpty) return 0;
    final drop = <String>[];
    final trash = await (db.select(db.folders)
          ..where((f) =>
              f.accountId.equals(accountId) & f.type.isIn([FolderType.trash.index, FolderType.junk.index])))
        .get();
    final skip = {for (final r in trash) r.id};
    final ids = byEmail.keys.toList();
    for (var i = 0; i < ids.length; i += 200) {
      final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      // Без тел: папка и дата — из лёгких колонок, HTML — только у писем
      // старше срока (чтобы найти их встроенные картинки).
      final c = db.emails;
      final rows = await (db.selectOnly(c)
            ..addColumns([c.id, c.folderId, c.receivedAt])
            ..where(c.accountId.equals(accountId) & c.id.isIn(chunk)))
          .get();
      final found = <String, ({String folderId, DateTime receivedAt})>{
        for (final r in rows) r.read(c.id)!: (folderId: r.read(c.folderId)!, receivedAt: r.read(c.receivedAt)!),
      };
      final old = <String>[];
      for (final id in chunk) {
        final r = found[id];
        if (r == null || skip.contains(r.folderId)) {
          drop.addAll(byEmail[id]!);
          continue;
        }
        if (r.receivedAt.isBefore(olderThan)) old.add(id);
      }
      if (old.isEmpty) continue;
      final full = await (db.select(db.emails)
            ..where((e) => e.accountId.equals(accountId) & e.id.isIn(old)))
          .get();
      for (final r in full) {
        // Только встроенные картинки — открытые вложения не трогаем.
        for (final a in _inlineOf(r)) {
          final k = MailEngineService.attachmentCacheKey(accountId, r.id, a.id);
          if (byEmail[r.id]!.contains(k)) drop.add(k);
        }
        _imagesDone.remove('$accountId|${r.id}');
      }
    }
    if (drop.isEmpty) return 0;
    return cache.removeKeys(drop);
  }
}

/// Сколько работы позволено проходу (см. OfflineStoreService._budget).
class _Budget {
  final int maxBodies;
  final Duration maxRun;

  /// Только письма не старше (null — весь период синхронизации).
  final DateTime? since;
  final bool images;
  final String label;
  const _Budget(this.maxBodies, this.maxRun, this.since, {required this.images, required this.label});
}

/// Что записать в строку письма после загрузки текста.
class _BodyUpdate {
  final String? html;
  final String? plain;
  final String? attachmentsJson;
  final String? authResults;
  final String? listUnsubscribe;

  /// Письмо больше ограничения режима — только отметка.
  final bool tooBig;

  const _BodyUpdate({this.html, this.plain, this.attachmentsJson, this.authResults, this.listUnsubscribe})
      : tooBig = false;

  const _BodyUpdate.tooBig()
      : html = null,
        plain = null,
        attachmentsJson = null,
        authResults = null,
        listUnsubscribe = null,
        tooBig = true;

  /// Колонки для AppDatabase.storeBodiesQuietly.
  Map<String, Object?> columns() {
    if (tooBig) return const {'loaded_level': OfflineStoreService._levelTooBig};
    return {
      'body_html': html,
      'body_plain': plain,
      'loaded_level': OfflineStoreService._levelBody,
      'cached_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (authResults != null) 'auth_results': authResults,
      if (listUnsubscribe != null) 'list_unsubscribe': listUnsubscribe,
    };
  }
}

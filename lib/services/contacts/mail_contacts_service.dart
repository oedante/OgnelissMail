// lib/services/contacts/mail_contacts_service.dart
// Контакты из переписки: кто пишет вам и кому пишете вы. Как «Другие
// контакты» в Gmail и «Недавние» в Outlook — без ручного добавления.
//
//  · Каждое новое письмо: отправитель входящего (+1), получатели
//    отправленного (+3 — тем, кому пишете сами, место выше в подсказках).
//  · Если человек уже есть в контактах (Exchange, Google, телефон) — у его
//    карточки растёт счётчик переписки (interaction_count) и дата последнего
//    письма. Раньше эти поля были, но никто их не заполнял, и подсказки
//    адресатов не учитывали, с кем вы общаетесь.
//  · Иначе — карточка «из переписки» (source = fromMail, id «mail:<адрес>»,
//    без ящика), видна в подсказках и в разделе «Из переписки».
//  · Для рабочих ящиков (ActiveSync) фото людей подтягивается из адресной
//    книги организации — понемногу, не чаще раза в неделю на человека.
//  · Один раз на ящик — заполнение по уже загруженной почте.
//
// Служебные адреса (noreply, mailer-daemon, рассылки) не собираются.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/contact_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../mail/engine/mail_engine_service.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../core/utils/mail_domains.dart';

final mailContactsServiceProvider = Provider<MailContactsService>((ref) => MailContactsService(ref));

class MailContactsService {
  final Ref _ref;
  MailContactsService(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  /// id карточки «из переписки».
  static String idFor(String email) => 'mail:${email.toLowerCase()}';

  static final _automated = RegExp(
      r'^(no-?reply|do-?not-?reply|donotreply|mailer-daemon|postmaster|bounces?|'
      r'notifications?|notify|news(letter)?|digest|unsubscribe|robot|daemon)([+._-].*)?@',
      caseSensitive: false);

  static bool isPersonAddress(String email) {
    final e = email.trim();
    if (e.isEmpty || !e.contains('@') || e.length > 254) return false;
    if (_automated.hasMatch(e)) return false;
    // Идентификаторы рассылочных сервисов: bounce+abc123@…, длинные хеши.
    final local = e.substring(0, e.indexOf('@'));
    if (local.length > 40 && RegExp(r'[0-9a-f]{16,}', caseSensitive: false).hasMatch(local)) return false;
    return true;
  }

  /// Учесть новые письма папки. [sent] — папка «Отправленные».
  Future<void> harvest(AccountModel account, List<EmailModel> emails, {required bool sent}) async {
    if (emails.isEmpty) return;
    final own = account.email.toLowerCase();
    final shared = account.sharedMailboxEmail?.toLowerCase();
    final stats = <String, _Stat>{};
    void add(EmailAddress a, int weight, DateTime at) {
      final key = a.email.trim().toLowerCase();
      if (key == own || key == shared || !isPersonAddress(key)) return;
      final s = stats.putIfAbsent(key, () => _Stat(a.email.trim()));
      s.count += weight;
      if (s.last == null || at.isAfter(s.last!)) s.last = at;
      final n = a.displayName?.trim();
      if (n != null && n.isNotEmpty && !n.contains('\uFFFD') && n.toLowerCase() != key && (s.name == null || s.name!.length < n.length)) {
        s.name = n;
      }
    }

    for (final e in emails) {
      if (e.isDraft) continue;
      final at = e.sentAt ?? e.receivedAt;
      if (sent || e.from.email.toLowerCase() == own) {
        for (final a in [...e.to, ...e.cc]) {
          add(a, 3, at);
        }
      } else {
        add(e.from, 1, at);
      }
    }
    if (stats.isEmpty) return;
    await _apply(stats);
  }

  Future<void> _apply(Map<String, _Stat> stats) async {
    final db = _db;
    final keys = stats.keys.toList();
    await db.transaction(() async {
      for (var i = 0; i < keys.length; i += 300) {
        final part = keys.sublist(i, i + 300 > keys.length ? keys.length : i + 300);
        final placeholders = List.filled(part.length, '?').join(',');
        final rows = await db.customSelect(
          'SELECT id, account_id, lower(email) AS e, source, display_name, interaction_count, last_interaction '
          'FROM contacts WHERE lower(email) IN ($placeholders)',
          variables: [for (final k in part) Variable.withString(k)],
        ).get();
        final byEmail = <String, List<QueryRow>>{};
        for (final r in rows) {
          (byEmail[r.read<String>('e')] ??= []).add(r);
        }
        for (final k in part) {
          final s = stats[k]!;
          final existing = byEmail[k] ?? const <QueryRow>[];
          final real = existing.where((r) => r.read<int>('source') != ContactSource.fromMail.index).toList();
          if (real.isNotEmpty) {
            // Человек уже в контактах — растёт счётчик переписки.
            for (final r in real) {
              await db.customStatement(
                'UPDATE contacts SET interaction_count = interaction_count + ?, '
                'last_interaction = CASE WHEN last_interaction IS NULL OR last_interaction < ? THEN ? ELSE last_interaction END '
                'WHERE id = ? AND account_id IS ?',
                [s.count, _sec(s.last), _sec(s.last), r.read<String>('id'), r.readNullable<String>('account_id')],
              );
            }
            // Карточка «из переписки» больше не нужна. Её фото (из адресной
            // книги организации) переносится в карточки без фото — иначе
            // портрет человека «слетал», когда он появлялся в контактах
            // Exchange или телефона, и ждал нового запроса (1.6.32).
            await db.customUpdate(
              'UPDATE contacts SET avatar_url = (SELECT avatar_url FROM contacts WHERE id = ? AND account_id IS NULL) '
              "WHERE lower(email) = ? AND id <> ? AND (avatar_url IS NULL OR avatar_url = '') "
              "AND EXISTS (SELECT 1 FROM contacts WHERE id = ? AND account_id IS NULL AND avatar_url IS NOT NULL AND avatar_url <> '')",
              variables: [
                Variable.withString(idFor(k)),
                Variable.withString(k),
                Variable.withString(idFor(k)),
                Variable.withString(idFor(k)),
              ],
              updates: {db.contacts},
              updateKind: UpdateKind.update,
            );
            await (db.delete(db.contacts)..where((c) => c.id.equals(idFor(k)) & c.accountId.isNull())).go();
            continue;
          }
          final mine = existing.where((r) => r.read<String>('id') == idFor(k)).firstOrNull;
          if (mine != null) {
            final oldName = mine.read<String>('display_name');
            await (db.update(db.contacts)..where((c) => c.id.equals(idFor(k)) & c.accountId.isNull())).write(
              ContactsCompanion(
                interactionCount: Value(mine.read<int>('interaction_count') + s.count),
                lastInteraction: Value(s.last),
                // Имя: самое полное из встреченных (в письмах его часто нет).
                displayName: (s.name != null && (oldName.isEmpty || oldName.contains('@') || oldName.contains('\uFFFD')))
                    ? Value(s.name!)
                    : const Value.absent(),
              ),
            );
          } else {
            final name = s.name ?? '';
            final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
            await db.into(db.contacts).insert(ContactsCompanion.insert(
                  id: idFor(k),
                  accountId: const Value(null),
                  email: s.email,
                  displayName: name,
                  firstName: Value(parts.length >= 2 ? parts[1] : (parts.length == 1 ? parts[0] : null)),
                  lastName: Value(parts.length >= 2 ? parts[0] : null),
                  source: Value(ContactSource.fromMail.index),
                  interactionCount: Value(s.count),
                  lastInteraction: Value(s.last),
                ));
          }
        }
      }
    });
  }

  /// Время в формате столбца drift (секунды Unix) для сравнения в SQL.
  static int _sec(DateTime? d) => ((d ?? DateTime.now()).millisecondsSinceEpoch / 1000).floor();

  /// Один раз на ящик: заполнить по уже загруженной почте.
  Future<void> backfillOnce(AccountModel account, {String? sentFolderId}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'mail_contacts_backfill:${account.id}';
    if (prefs.getBool(key) == true) return;
    try {
      final db = _db;
      final own = account.email.toLowerCase();
      final stats = <String, _Stat>{};
      // Отправители входящих.
      final senders = await db.customSelect(
        'SELECT from_email AS e, MAX(from_name) AS n, COUNT(*) AS c, MAX(received_at) AS t '
        'FROM emails WHERE account_id = ? AND is_draft = 0 GROUP BY lower(from_email)',
        variables: [Variable.withString(account.id)],
      ).get();
      for (final r in senders) {
        final e = (r.readNullable<String>('e') ?? '').trim();
        final k = e.toLowerCase();
        if (k == own || !isPersonAddress(k)) continue;
        final s = stats.putIfAbsent(k, () => _Stat(e));
        s.count += r.read<int>('c');
        final n = r.readNullable<String>('n');
        if (n != null && !n.contains('\uFFFD')) s.name ??= n;
        final t = r.readNullable<int>('t');
        if (t != null) s.last = DateTime.fromMillisecondsSinceEpoch(t * 1000);
      }
      // Адресаты своих писем (отправленные) — с весом 3.
      if (sentFolderId != null) {
        final sent = await db.customSelect(
          'SELECT to_recipients AS t, cc_json AS c, received_at AS d FROM emails '
          'WHERE account_id = ? AND folder_id = ? ORDER BY received_at DESC LIMIT 2000',
          variables: [Variable.withString(account.id), Variable.withString(sentFolderId)],
        ).get();
        for (final r in sent) {
          final d = r.readNullable<int>('d');
          final at = d == null ? null : DateTime.fromMillisecondsSinceEpoch(d * 1000);
          for (final col in ['t', 'c']) {
            final raw = r.readNullable<String>(col);
            if (raw == null || raw.isEmpty) continue;
            try {
              for (final m in (jsonDecode(raw) as List).whereType<Map>()) {
                final a = EmailAddress.fromMap(Map<String, dynamic>.from(m));
                final k = a.email.trim().toLowerCase();
                if (k == own || !isPersonAddress(k)) continue;
                final s = stats.putIfAbsent(k, () => _Stat(a.email.trim()));
                s.count += 3;
                if (at != null && (s.last == null || at.isAfter(s.last!))) s.last = at;
                final n = a.displayName?.trim();
                if (n != null && n.isNotEmpty && !n.contains('\uFFFD') && s.name == null) s.name = n;
              }
            } catch (_) {}
          }
        }
      }
      if (stats.isNotEmpty) await _apply(stats);
      await prefs.setBool(key, true);
      AppLogger.info('Контакты из переписки ${account.email}: ${stats.length}');
    } catch (e) {
      AppLogger.warning('Контакты из переписки: $e');
    }
  }

  static const _publicDomains = kPublicMailDomains;

  // ── Фото по запросу: контакты, видимые на экране ──
  //
  // Фоновый проход берёт только частых собеседников (по числу писем), а у
  // личных контактов Exchange их число — 0: во вкладке «Контакты» фото не
  // появлялись, хотя в ленте у тех же людей были (замечание 09.10.2026).
  // Теперь строка контакта без фото просит его здесь: по одному запросу за
  // раз, адрес — не чаще раза за запуск и раза в неделю при «нет фото».
  final Set<String> _photoAsked = {};
  final List<String> _photoQueue = [];
  bool _photoBusy = false;

  /// Ящик с адресной книгой организации: ActiveSync или EWS (1.6.49 — и
  /// EWS: фото в высоком качестве через GetUserPhoto). Общие ящики — нет:
  /// у них та же книга, что у основного.
  static bool _hasDirectory(AccountModel a) => !a.isSharedMailbox && (a.usesEas || a.usesEws);

  void requestPhoto(String email, {String? accountId}) {
    final e = email.trim().toLowerCase();
    if (!e.contains('@') || _photoAsked.contains(e)) return;
    if (_publicDomains.contains(e.split('@').last)) return;
    // Адресная книга организации есть только у ящиков Exchange (ActiveSync);
    // без них очередь копилась бы зря — теперь просит и лента писем.
    if (!_ref.read(accountsProvider).any(_hasDirectory)) return;
    _photoAsked.add(e);
    _photoQueue.add(accountId == null ? e : '$e\n$accountId');
    if (!_photoBusy) unawaited(_drainPhotos());
  }

  Future<void> _drainPhotos() async {
    _photoBusy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final tried = await _loadTried(prefs);
      final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
      final engine = _ref.read(mailEngineServiceProvider);
      var changed = false;
      var asked = 0, found = 0;
      while (_photoQueue.isNotEmpty) {
        final item = _photoQueue.removeAt(0).split('\n');
        final email = item.first;
        if ((tried[email] ?? 0) > weekAgo) continue;
        final accounts = _ref.read(accountsProvider).where(_hasDirectory).toList();
        if (accounts.isEmpty) {
          _photoQueue.clear();
          break;
        }
        final acc = (item.length > 1 ? accounts.where((a) => a.id == item[1]).firstOrNull : null) ??
            accounts.where((a) => a.email.split('@').last.toLowerCase() == email.split('@').last).firstOrNull ??
            accounts.first;
        try {
          asked++;
          final photo = await engine.lookupGalPhoto(acc, email);
          if (photo == null) {
            // «Нет фото» — повтор не раньше чем через неделю. Найденное не
            // помечается: если фото потом пропадёт из базы (контакт
            // перезаписан синхронизацией), его спросят снова при показе.
            tried[email] = DateTime.now().millisecondsSinceEpoch;
            changed = true;
            continue;
          }
          found++;
          // customUpdate с updates: — иначе списки контактов (watch) не
          // узнают о новом фото до следующей записи в таблицу.
          await _db.customUpdate(
            "UPDATE contacts SET avatar_url = ? WHERE lower(email) = ? AND (avatar_url IS NULL OR avatar_url = '')",
            variables: [Variable.withString(photo), Variable.withString(email)],
            updates: {_db.contacts},
            updateKind: UpdateKind.update,
          );
        } catch (e) {
          AppLogger.debug('Фото контакта: $e');
          // Нет связи — этот и оставшиеся адреса спросим при следующем показе.
          _photoAsked.remove(email);
          for (final q in _photoQueue) {
            _photoAsked.remove(q.split('\n').first);
          }
          _photoQueue.clear();
          break;
        }
      }
      if (changed) await prefs.setString(_triedKey, jsonEncode(tried));
      if (asked > 0) AppLogger.info('Фото контактов по запросу: спрошено $asked, найдено $found');
    } finally {
      _photoBusy = false;
    }
  }

  static const _triedKey = 'gal_photo_tried';

  /// Адреса, у которых недавно не нашлось фото. В 1.5.12 список очищается
  /// один раз: раньше в него попадали и найденные фото, и если фото потом
  /// пропадало из базы, его не спрашивали неделю — «в контактах нет фото,
  /// раньше были» (12.10.2026).
  Future<Map<String, int>> _loadTried(SharedPreferences prefs) async {
    const resetKey = 'gal_photo_tried_reset_1512';
    if (prefs.getBool(resetKey) != true) {
      await prefs.remove(_triedKey);
      await prefs.setBool(resetKey, true);
      return {};
    }
    final tried = <String, int>{};
    try {
      final raw = prefs.getString(_triedKey);
      if (raw != null) (jsonDecode(raw) as Map).forEach((k, v) => tried['$k'] = (v as num).toInt());
    } catch (_) {}
    return tried;
  }

  /// Обновить фото коллег из адресной книги организации заново (1.6.32,
  /// «у некоторых пользователей слетают портреты»): список «фото не найдено»
  /// сбрасывается, фото запрашиваются для всех собеседников (не только без
  /// фото), найденное записывается поверх. Личные фото, загруженные в
  /// контакт Exchange вручную, не заменяются. Не больше [limit] запросов;
  /// [onProgress] — сколько сделано из скольких. Своё фото и карточка —
  /// тоже заново.
  Future<({int asked, int found})> refreshAllPhotos(AccountModel account,
      {int limit = 400, void Function(int done, int total)? onProgress}) async {
    if (!_hasDirectory(account)) return (asked: 0, found: 0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_triedKey);
    _photoAsked.clear();
    final engine = _ref.read(mailEngineServiceProvider);
    try {
      await engine.refreshSelfCard(account, force: true);
    } catch (e) {
      AppLogger.debug('Своя карточка: $e');
    }
    final seen = <String>{};
    final emails = <String>[];
    for (final r in await _db.customSelect(
      "SELECT email FROM contacts WHERE email LIKE '%@%' ORDER BY interaction_count DESC LIMIT ?",
      variables: [Variable.withInt(limit * 3)],
    ).get()) {
      final e = r.read<String>('email').trim().toLowerCase();
      if (_publicDomains.contains(e.split('@').last) || !seen.add(e)) continue;
      emails.add(e);
      if (emails.length >= limit) break;
    }
    var asked = 0;
    var found = 0;
    onProgress?.call(0, emails.length);
    for (final email in emails) {
      asked++;
      try {
        final photo = await engine.lookupGalPhoto(account, email);
        if (photo != null) {
          found++;
          await _db.customUpdate(
            'UPDATE contacts SET avatar_url = ? WHERE lower(email) = ? '
            "AND (avatar_url IS NULL OR avatar_url = '' OR source <> ?)",
            variables: [
              Variable.withString(photo),
              Variable.withString(email),
              Variable.withInt(ContactSource.personal.index),
            ],
            updates: {_db.contacts},
            updateKind: UpdateKind.update,
          );
        }
      } catch (e) {
        AppLogger.warning('Фото из адресной книги: обновление прервано — $e');
        break; // нет связи с сервером — остальное в следующий раз
      }
      onProgress?.call(asked, emails.length);
    }
    AppLogger.info('Фото из адресной книги обновлены: спрошено $asked, найдено $found (${account.email})');
    return (asked: asked, found: found);
  }

  /// Фото частых собеседников из адресной книги организации (ActiveSync GAL).
  /// За проход — не больше [limit] запросов; неудачные адреса повторяются не
  /// раньше чем через неделю.
  Future<void> fetchPhotos(AccountModel account, {int limit = 20}) async {
    if (!_hasDirectory(account)) return;
    final prefs = await SharedPreferences.getInstance();
    final tried = await _loadTried(prefs);
    final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final domain = account.email.contains('@') ? account.email.split('@').last.toLowerCase() : '';
    if (domain.isEmpty) return;
    final db = _db;
    // Собеседники без фото — по частоте переписки. Не только домен ящика:
    // в группе компаний адресная книга общая (acmegroup.example, acme.example,
    // artxs.ru…), и коллеги с соседних доменов раньше оставались без фото.
    // Публичные почтовые сервисы в адресной книге организации искать незачем.
    final rows = (await db.customSelect(
      "SELECT email FROM contacts WHERE (avatar_url IS NULL OR avatar_url = '') "
      "AND email LIKE '%@%' ORDER BY interaction_count DESC LIMIT 120",
    ).get())
        .where((r) => !_publicDomains.contains(r.read<String>('email').split('@').last.toLowerCase()))
        .toList();
    final engine = _ref.read(mailEngineServiceProvider);
    var asked = 0;
    for (final r in rows) {
      if (asked >= limit) break;
      final email = r.read<String>('email').toLowerCase();
      if ((tried[email] ?? 0) > weekAgo) continue;
      asked++;
      try {
        final photo = await engine.lookupGalPhoto(account, email);
        if (photo == null) {
          tried[email] = DateTime.now().millisecondsSinceEpoch;
          continue;
        }
        await db.customUpdate(
          "UPDATE contacts SET avatar_url = ? WHERE lower(email) = ? AND (avatar_url IS NULL OR avatar_url = '')",
          variables: [Variable.withString(photo), Variable.withString(email)],
          updates: {db.contacts},
          updateKind: UpdateKind.update,
        );
      } catch (e) {
        AppLogger.debug('Фото из адресной книги: $e');
        // Сбой связи — не «нет фото»: этот адрес повторим в следующий раз.
        break; // сервер недоступен — в следующий раз
      }
    }
    // Не копим бесконечно.
    if (tried.length > 2000) {
      final sorted = tried.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      tried
        ..clear()
        ..addEntries(sorted.take(1500));
    }
    await prefs.setString(_triedKey, jsonEncode(tried));
    if (asked > 0) AppLogger.info('Фото из адресной книги: запрошено $asked');
    await _upgradePhotos(account, limit: limit);
  }

  static const _hiTriedKey = 'gal_photo_hr_tried';

  /// Мелкие фото (миниатюры ActiveSync 96×96, до 1.6.49) — заменить фото в
  /// высоком качестве (EWS GetUserPhoto), понемногу за проход. Личные фото
  /// контактов не трогаются. Адрес, у которого высокого качества нет, —
  /// повтор не раньше чем через 30 дней.
  Future<void> _upgradePhotos(AccountModel account, {int limit = 20}) async {
    final engine = _ref.read(mailEngineServiceProvider);
    final prefs = await SharedPreferences.getInstance();
    final tried = <String, int>{};
    try {
      final raw = prefs.getString(_hiTriedKey);
      if (raw != null) (jsonDecode(raw) as Map).forEach((k, v) => tried['$k'] = (v as num).toInt());
    } catch (_) {}
    final monthAgo = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    // data URI короче ~10 тыс. знаков — меньше 7,5 КБ JPEG: миниатюра.
    final rows = await _db.customSelect(
      'SELECT lower(email) AS e, MAX(interaction_count) AS ic FROM contacts '
      "WHERE avatar_url LIKE 'data:%' AND LENGTH(avatar_url) < 10000 AND source <> ? "
      "AND email LIKE '%@%' GROUP BY lower(email) ORDER BY ic DESC LIMIT 200",
      variables: [Variable.withInt(ContactSource.personal.index)],
    ).get();
    var asked = 0, found = 0;
    for (final r in rows) {
      if (asked >= limit) break;
      final email = r.read<String>('e');
      if (_publicDomains.contains(email.split('@').last) || (tried[email] ?? 0) > monthAgo) continue;
      asked++;
      try {
        final photo = await engine.lookupHiResPhoto(account, email);
        if (photo == null || photo.length < 10000) {
          tried[email] = DateTime.now().millisecondsSinceEpoch;
          continue;
        }
        found++;
        await _db.customUpdate(
          'UPDATE contacts SET avatar_url = ? WHERE lower(email) = ? AND source <> ?',
          variables: [
            Variable.withString(photo),
            Variable.withString(email),
            Variable.withInt(ContactSource.personal.index),
          ],
          updates: {_db.contacts},
          updateKind: UpdateKind.update,
        );
      } catch (e) {
        AppLogger.debug('Фото в высоком качестве: $e');
        break; // нет связи — в следующий раз
      }
    }
    if (tried.length > 3000) {
      final sorted = tried.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      tried
        ..clear()
        ..addEntries(sorted.take(2000));
    }
    await prefs.setString(_hiTriedKey, jsonEncode(tried));
    if (asked > 0) AppLogger.info('Фото в высоком качестве: спрошено $asked, заменено $found');
  }
}

class _Stat {
  final String email;
  String? name;
  int count = 0;
  DateTime? last;
  _Stat(this.email);
}

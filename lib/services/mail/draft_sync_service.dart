// lib/services/mail/draft_sync_service.dart
// Черновики — на сервер. Раньше черновик жил только на телефоне: его не было
// видно в Outlook и веб-почте, а после переустановки он терялся.
//
// Как устроено:
//  · экран письма сохраняет черновик локально (автосохранение, folder_id
//    'drafts'); при закрытии экрана черновик выгружается в серверную папку
//    «Черновики» и локальная копия удаляется — дальше он живёт как обычное
//    письмо этой папки (синхронизация, правка, отправка);
//  · черновик, открытый из серверной папки и изменённый, заменяет собой
//    прежнюю серверную копию (она удаляется после выгрузки новой);
//  · без сети черновик остаётся локальным и выгружается при следующей
//    синхронизации.
//
// Протоколы: IMAP (APPEND с флагом \Draft), EWS (CreateItem SaveOnly) и
// ActiveSync 16 (Sync Add в «Черновики» в общей цепочке SyncKey). На
// ActiveSync ниже 16 сервер черновики не принимает — они остаются на
// устройстве.
//
// 1.7.2+111 — файлы черновика (`DraftFiles`) уходят на сервер вместе с ним:
// IMAP — multipart/mixed, EWS — CreateAttachment, ActiveSync 16 —
// AirSyncBase Add. Не скачанные вложения (пересылка, черновик из Outlook)
// скачиваются перед выгрузкой; не скачались или файлы больше лимита ящика —
// черновик остаётся на телефоне (прежняя серверная копия не удаляется).
// [completeServerDraft] догружает черновик из серверной папки перед
// правкой: у EWS список писем не несёт ни адресатов, ни текста, ни файлов —
// черновик открывался пустым, а после правки пустая версия заменяла
// настоящую.
//
// 2.6.8 (просьба владельца 22.11.2026, IMAP и Exchange):
//  · черновик выгружается и во время правки ([uploadWhileEditing]): после
//    автосохранения, «Сохранить» и при сворачивании приложения. Каждая
//    версия заменяет прежнюю серверную копию; итоговая при закрытии окна
//    не выгружается второй раз, если та же версия уже на сервере;
//  · черновик ответа несёт заголовки In-Reply-To и References (IMAP и EWS):
//    встаёт в беседу в веб-почте и в программе на другом устройстве, а
//    отправленный оттуда — в переписку получателя. ActiveSync таких полей у
//    черновика не принимает.

import '../../core/utils/text_safe.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;
import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' as me show GatewaySizeRejected;
import 'package:shared_preferences/shared_preferences.dart' show SharedPreferences;

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/compose/providers/attachment_limit_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../features/settings/providers/settings_provider.dart' show EmailFetchMode;
import '../sync/sync_service.dart';
import 'attachment_cache_service.dart' show attachmentCacheProvider;
import 'draft_autosave_service.dart' show DraftData;
import 'draft_files.dart';
import 'email_actions_service.dart';
import 'engine/mail_engine_service.dart';
import 'ews/ews_service.dart';
import 'imap/imap_service.dart';

final draftSyncServiceProvider = Provider<DraftSyncService>((ref) => DraftSyncService(ref));

class DraftSyncService {
  final Ref _ref;
  DraftSyncService(this._ref);

  /// Черновики, открытые сейчас в окне письма: их не выгружаем — правка идёт.
  static final Set<String> editing = {};

  /// То же для фоновой синхронизации (1.7.2+111): отметка в настройках —
  /// фоновый изолят не видит [editing] и выгружал черновик, пока окно письма
  /// было открыто, а затем удалял его файлы с телефона. Отметка старше суток
  /// не считается (приложение закрыли, не закрыв письмо).
  static const _editingKey = 'draft_editing';

  void beginEdit(String id) {
    editing.add(id);
    unawaited(_writeEditing((m) => m[id] = DateTime.now().millisecondsSinceEpoch));
  }

  void endEdit(String id) {
    editing.remove(id);
    unawaited(_writeEditing((m) => m.remove(id)));
  }

  Future<void> _writeEditing(void Function(Map<String, int> m) change) async {
    try {
      final prefs = _ref.read(sharedPrefsProvider);
      final m = _readEditing(prefs.getString(_editingKey));
      change(m);
      await prefs.setString(_editingKey, jsonEncode(m));
    } catch (_) {}
  }

  static Map<String, int> _readEditing(String? raw) {
    if (raw == null) return {};
    try {
      final old = DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch;
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          if (e.value is int && (e.value as int) > old) e.key as String: e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  /// Последняя неудачная попытка по черновику: повтор не чаще раза в 15 мин.
  static final Map<String, DateTime> _failedAt = {};

  /// То же для выгрузки во время правки (2.6.8): повтор не чаще раза в 2 мин.
  static final Map<String, DateTime> _interimFailedAt = {};

  /// Черновики, которые шлюз перед Exchange не пропустил по размеру
  /// (1.7.2+114): id → время сохранения черновика. Пока черновик тот же —
  /// не выгружаем.
  static final Map<String, DateTime> _tooBig = {};

  static const _replacesKey = 'draft_replaces';

  /// Черновик открыт из серверной папки: после выгрузки новой версии
  /// прежняя копия удаляется. Связь хранится, пока черновик не выгружен.
  /// Версия, выгруженная во время правки (2.6.8), — такая же связь, с
  /// отпечатком содержимого (sig) и, у IMAP, Message-ID копии (mid).
  Future<void> rememberReplace(String localId, ({String id, String folderId}) server) =>
      _writeReplace(localId, {'id': server.id, 'folderId': server.folderId});

  Future<void> _writeReplace(String localId, Map<String, String> copy) async {
    final prefs = _ref.read(sharedPrefsProvider);
    final m = _readReplaces();
    m[localId] = copy;
    await prefs.setString(_replacesKey, jsonEncode(m));
  }

  Future<void> forget(String localId) async {
    final m = _readReplaces();
    if (m.remove(localId) != null) {
      await _ref.read(sharedPrefsProvider).setString(_replacesKey, jsonEncode(m));
    }
  }

  Map<String, Map<String, String>> _readReplaces() => _parseReplaces(_ref.read(sharedPrefsProvider));

  static Map<String, Map<String, String>> _parseReplaces(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_replacesKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry(k as String, Map<String, String>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  /// Серверные копии, которые заменит свой черновик из [rows] (его строка
  /// на устройстве ещё есть: правка идёт или выгрузка не удалась) —
  /// «ящик|id». В списке показывается он, а не копия: выгруженная во время
  /// правки версия (2.6.8) иначе стояла бы в «Черновиках» вторым письмом.
  static Set<String> shadowed(SharedPreferences prefs, Iterable<Email> rows) {
    final local = [for (final r in rows) if (r.folderId == 'drafts') r];
    if (local.isEmpty) return const {};
    final m = _parseReplaces(prefs);
    if (m.isEmpty) return const {};
    return {
      for (final r in local)
        if ((m[r.id]?['id'] ?? '').isNotEmpty) '${r.accountId}|${m[r.id]!['id']}',
    };
  }

  /// Умеет ли ящик хранить черновики на сервере.
  static bool supports(AccountModel a) => a.usesEas || a.usesEws || a.isImap || a.isOAuth;

  /// Выгрузить локальный черновик. true — выгружен (локальная копия удалена).
  /// Версия, выгруженная во время правки (2.6.8), заменяется этой; такая же
  /// версия уже на сервере — второй раз не выгружается.
  Future<bool> upload(String localId, String accountId) async {
    if (editing.contains(localId)) return false;
    final r = await _one(localId, () => _upload(localId, accountId, interim: false));
    return r.done;
  }

  /// Выгрузить черновик, не закрывая окно письма (2.6.8, просьба владельца
  /// 22.11.2026: черновик сразу виден на другом устройстве и в веб-почте и
  /// не пропадает, если приложение закроют). Окно письма зовёт после
  /// автосохранения (раз в 30 с при правке), после «Сохранить» и при
  /// сворачивании приложения. Локальная копия остаётся (правка идёт);
  /// выгруженная версия заменяет прежнюю серверную копию и сама будет
  /// заменена следующей или итоговой при закрытии окна.
  ///
  /// Не выгружается: та же версия, что уже на сервере; черновик с не
  /// скачанными файлами (пересылка, файлы черновика из папки) — их пришлось
  /// бы качать на каждую выгрузку; с файлами больше [interimFilesMax] —
  /// только при сворачивании ([force]), не каждые 30 с.
  ///
  /// Возвращает id серверной копии, которую заменила выгрузка (null — не
  /// выгружали или заменять было нечего): окно письма, открытое из папки
  /// «Черновики», так узнаёт, что прежней копии больше нет.
  Future<String?> uploadWhileEditing(String localId, String accountId, {bool force = false}) async {
    final r = await _one(localId, () => _upload(localId, accountId, interim: true, force: force));
    return r.dropped;
  }

  /// Файлы черновика больше этого — во время правки выгружается только при
  /// сворачивании приложения: иначе мегабайты уходили бы каждые 30 с.
  static const interimFilesMax = 2 * 1024 * 1024;

  /// Выгрузки и удаления копий одного черновика — по одной (2.6.8):
  /// выгрузка во время правки и итоговая при закрытии окна (или удаление
  /// копий после отправки) не идут вместе — иначе вторая не знала бы о
  /// копии, созданной первой, и на сервере оставалось две.
  static final Map<String, Future<void>> _queue = {};

  Future<T> _one<T>(String localId, Future<T> Function() body) {
    final next = (_queue[localId] ?? Future<void>.value()).then((_) => body());
    final tail = next.then<void>((_) {}, onError: (Object _) {});
    _queue[localId] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_queue[localId], tail)) _queue.remove(localId);
    }));
    return next;
  }

  /// Копии, уже удалённые с сервера этим устройством: окно письма могло не
  /// успеть узнать, что открытой из папки копии больше нет.
  static final Set<String> _dropped = {};

  static const _none = (done: false, dropped: null);

  Future<({bool done, String? dropped})> _upload(String localId, String accountId,
      {required bool interim, bool force = false}) async {
    final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (account == null || !supports(account)) return _none;
    // Неудачи итоговой выгрузки и выгрузок во время правки — порознь:
    // сбой во время набора не откладывает выгрузку при закрытии окна.
    final failures = interim ? _interimFailedAt : _failedAt;
    final failed = failures[localId];
    if (failed != null &&
        DateTime.now().difference(failed) < (interim ? const Duration(minutes: 2) : const Duration(minutes: 15))) {
      return _none;
    }
    final db = _ref.read(databaseProvider);
    final row = await (db.select(db.emails)
          ..where((e) => e.id.equals(localId) & e.accountId.equals(accountId) & e.folderId.equals('drafts')))
        .getSingleOrNull();
    if (row == null) return _none;
    // Этот же черновик шлюз уже не пропустил по размеру: тот же запрос в
    // несколько мегабайт каждые 15 минут ни к чему — ждём, пока его поправят.
    if (_tooBig[localId] == row.receivedAt) return _none;

    final to = _addrs(row.toRecipients);
    final cc = _addrs(row.ccJson);
    final bcc = _addrs(row.bccJson);
    final body = row.bodyPlain ?? '';
    final html = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(body)
        ? body
        : '<div>${_esc(body).replaceAll('\n', '<br>')}</div>';

    final sig = contentSig(row);
    final before = _readReplaces()[localId];
    if (before != null && before['sig'] == sig) {
      // Эта версия уже на сервере (выгружена во время правки).
      if (interim) return _none;
      await _settle(account, db, row, html, before);
      return (done: true, dropped: null);
    }

    // Файлы черновика: больше лимита ящика — сервер письмо не примет,
    // черновик остаётся на телефоне (повтор через 15 минут был бы тем же).
    final files = await DraftFiles.load(row.attachmentsJson) ?? const <DraftFile>[];
    final total = files.fold<int>(0, (s, f) => s + f.size);
    if (interim && (files.any((f) => f.isRemote) || (!force && total > interimFilesMax))) return _none;
    final serverLimit = _ref.read(attachmentLimitProvider).limitFor(account.id);
    if (files.isNotEmpty && serverLimit != null && total > serverLimit) {
      if (interim) return _none;
      _failedAt[localId] = DateTime.now();
      AppLogger.info('Черновик с файлами на ${(total / 1048576).toStringAsFixed(1)} МБ больше лимита ящика — '
          'остаётся на устройстве');
      return _none;
    }
    final List<({String name, String? contentType, Uint8List bytes})> attachments;
    try {
      attachments = await _readFiles(files);
    } catch (e) {
      failures[localId] = DateTime.now();
      AppLogger.warning('Черновик: файлы не прочитаны или не скачаны (останется на устройстве): $e');
      return _none;
    }

    // Ответ — с заголовками цепочки (2.6.8): черновик встаёт в беседу в
    // веб-почте и в программе на другом устройстве, а отправленный оттуда —
    // в переписку получателя. ActiveSync таких полей у черновика не знает.
    final thread = account.usesEas ? null : await _threadOf(db, row);

    ({String folderId, String id, List<EmailAttachment>? files})? easDraft;
    final Map<String, String> copy;
    try {
      if (account.usesEas) {
        easDraft = await _ref.read(mailEngineServiceProvider).saveDraftEas(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, attachments: attachments);
        if (easDraft == null) return _none; // AS ниже 16 — черновик остаётся на устройстве
        copy = {
          'id': easDraft.id,
          'folderId': easDraft.folderId,
          if (easDraft.files != null) 'files': jsonEncode([for (final a in easDraft.files!) a.toMap()]),
        };
      } else if (account.usesEws) {
        final id = await _ref.read(ewsServiceProvider).saveDraft(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, thread: thread, attachments: attachments);
        copy = {'id': id ?? '', 'folderId': 'drafts'};
      } else {
        final mid = '<draft.${localId.hashCode.abs()}.${DateTime.now().millisecondsSinceEpoch}'
            '@${account.email.split('@').last}>';
        final saved = await _ref.read(imapServiceProvider).saveDraft(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, messageId: mid, thread: thread,
            attachments: attachments);
        if (saved == null) return _none; // папки «Черновики» на сервере нет
        copy = {'id': saved.uid == null ? '' : '${saved.path}:${saved.uid}', 'folderId': saved.path, 'mid': mid};
      }
    } catch (e) {
      failures[localId] = DateTime.now();
      if (e is me.GatewaySizeRejected) _tooBig[localId] = row.receivedAt;
      AppLogger.warning(interim
          ? 'Черновик во время правки не выгружен (повтор позже): $e'
          : 'Черновик не выгружен на сервер (останется на устройстве): $e');
      return _none;
    }
    failures.remove(localId);
    if (attachments.isNotEmpty && !interim) {
      AppLogger.info('Черновик выгружен на сервер с файлами: ${attachments.length}');
    }

    // Прежняя серверная копия: черновик открывали из серверной папки или
    // уже выгружали во время правки.
    String? dropped;
    if (before != null) {
      await _drop(account, before, hard: true);
      dropped = before['id'];
    }

    if (interim) {
      await _writeReplace(localId, {...copy, 'sig': sig});
      return (done: true, dropped: dropped);
    }
    await forget(localId);

    // Локальная копия больше не нужна — черновик придёт с синхронизацией.
    await (db.delete(db.emails)
          ..where((e) => e.id.equals(localId) & e.accountId.equals(accountId)))
        .go();
    await DraftFiles.remove(localId);
    if (easDraft != null) {
      // ActiveSync не возвращает клиенту добавленный им элемент — строку
      // серверного черновика пишем сами (с его ServerId и списком файлов).
      await _insertEasRow(account, db, row, html, id: easDraft.id, folderId: easDraft.folderId, files: easDraft.files);
      if (easDraft.files != null) await _seedCache(account.id, easDraft.id, easDraft.files!, attachments);
    } else {
      unawaited(_refreshDrafts(account, db));
    }
    return (done: true, dropped: dropped);
  }

  /// Итоговая выгрузка, когда эта версия уже на сервере: локальная копия
  /// больше не нужна, связь с серверной копией — тоже.
  Future<void> _settle(AccountModel account, AppDatabase db, Email row, String html, Map<String, String> copy) async {
    await forget(row.id);
    await (db.delete(db.emails)
          ..where((e) => e.id.equals(row.id) & e.accountId.equals(row.accountId)))
        .go();
    await DraftFiles.remove(row.id);
    final id = copy['id'] ?? '';
    if (account.usesEas && id.isNotEmpty) {
      List<EmailAttachment>? files;
      try {
        final raw = copy['files'];
        if (raw != null) {
          files = [
            for (final m in (jsonDecode(raw) as List).whereType<Map>()) EmailAttachment.fromMap(Map<String, dynamic>.from(m)),
          ];
        }
      } catch (_) {}
      await _insertEasRow(account, db, row, html, id: id, folderId: copy['folderId'] ?? '', files: files);
    } else {
      unawaited(_refreshDrafts(account, db));
    }
  }

  /// Строка серверного черновика ActiveSync — по локальной.
  Future<void> _insertEasRow(AccountModel account, AppDatabase db, Email row, String html,
      {required String id, required String folderId, List<EmailAttachment>? files}) async {
    await db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
          id: id,
          accountId: account.id,
          folderId: folderId,
          fromEmail: account.email,
          fromName: Value(account.displayName),
          toRecipients: row.toRecipients,
          ccJson: Value(row.ccJson),
          bccJson: Value(row.bccJson),
          subject: row.subject,
          bodyHtml: Value(html),
          bodyPreview: Value(_preview(html)),
          // На какое письмо отвечает черновик (1.7.0) — сохраняем связь.
          parentId: Value(row.parentId),
          receivedAt: DateTime.now(),
          attachmentsJson: Value(files == null || files.isEmpty ? null : jsonEncode([for (final a in files) a.toMap()])),
          hasAttachments: Value((files ?? const []).isNotEmpty || row.hasAttachments),
          isDraft: const Value(true),
          isRead: const Value(true),
        ));
  }

  /// Заголовки ответа черновика: цепочка исходного письма (его References и
  /// Message-ID). Пересылка и новое письмо — без них.
  Future<({String inReplyTo, String references})?> _threadOf(AppDatabase db, Email row) async {
    final p = DraftData.parseParentRef(row.parentId);
    if (p == null || p.forward) return null;
    try {
      final orig = await db.getEmailById(p.emailId, accountId: p.accountId);
      final mid = orig?.internetMessageId?.trim();
      // У ActiveSync поле могло хранить ServerId — это не Message-ID.
      if (orig == null || mid == null || !mid.contains('@')) return null;
      final refs = orig.referencesStr?.trim() ?? '';
      return replyThreadHeaders(refs.isEmpty ? mid : '$refs $mid');
    } catch (_) {
      return null;
    }
  }

  /// Отпечаток содержимого черновика: адресаты, тема, текст, гриф, на что
  /// отвечает, файлы (по имени и размеру). Совпал с выгруженным — та же
  /// версия уже на сервере.
  @visibleForTesting
  static String contentSig(Email r) {
    final files = <String>[];
    try {
      for (final m in (jsonDecode(r.attachmentsJson ?? '[]') as List).whereType<Map>()) {
        files.add('${m['name']}|${m['size']}|${m['remoteEmail'] ?? ''}|${m['remoteEmail'] == null ? '' : m['id']}');
      }
    } catch (_) {
      files.add(r.attachmentsJson ?? '');
    }
    final text = [
      r.toRecipients,
      r.ccJson ?? '',
      r.bccJson ?? '',
      r.subject,
      r.bodyPlain ?? '',
      r.sensitivity ?? '',
      r.parentId ?? '',
      ...files,
    ].join('\u0000');
    return sha1.convert(utf8.encode(text)).toString();
  }

  /// Письмо отправлено, черновик удалён или стёрт: серверные копии, которые
  /// он заменял, больше не нужны (2.6.8 — и версия, выгруженная во время
  /// правки). Ждёт выгрузку, которая идёт сейчас. [original] — письмо из
  /// серверной папки, открытое в окне; [keep] — id писем, из которых
  /// отправка ещё берёт файлы. Выгруженная во время правки копия удаляется
  /// безвозвратно, остальные — как скажет [hard] (false — в корзину).
  Future<void> dropServerCopy(AccountModel account, String localId,
          {({String id, String folderId})? original, Set<String> keep = const {}, bool hard = true}) =>
      _one(localId, () async {
        final rec = _readReplaces()[localId];
        await forget(localId);
        if (rec != null && !keep.contains(rec['id']) && rec['id'] != original?.id) {
          await _drop(account, rec, hard: hard || rec['sig'] != null);
        }
        if (original != null && !keep.contains(original.id) && !_dropped.contains(original.id)) {
          await _drop(account, {'id': original.id, 'folderId': original.folderId}, hard: hard);
        }
      });

  /// Удалить серверную копию черновика. Без id (сервер IMAP без UIDPLUS не
  /// назвал UID) — по Message-ID копии.
  Future<void> _drop(AccountModel account, Map<String, String> copy, {required bool hard}) async {
    final id = copy['id'] ?? '';
    final mid = copy['mid'] ?? '';
    try {
      if (id.isNotEmpty) {
        if (_dropped.length > 200) _dropped.clear();
        _dropped.add(id);
        await _ref.read(emailActionsProvider).delete(account, id, copy['folderId'] ?? '', hard: hard);
      } else if (mid.isNotEmpty && !account.usesEas && !account.usesEws) {
        await _ref.read(imapServiceProvider).deleteDraftByMessageId(account, mid);
        final db = _ref.read(databaseProvider);
        await (db.delete(db.emails)
              ..where((e) =>
                  e.accountId.equals(account.id) & e.internetMessageId.equals(mid) & e.folderId.equals('drafts').not()))
            .go();
      }
    } catch (e) {
      AppLogger.warning('Прежняя копия черновика не удалена: $e');
    }
  }

  /// Байты файлов черновика: свои — с телефона, не скачанные — с сервера
  /// (от имени ящика, где лежит письмо с ними). Ошибка — исключение.
  Future<List<({String name, String? contentType, Uint8List bytes})>> _readFiles(List<DraftFile> files) async {
    final out = <({String name, String? contentType, Uint8List bytes})>[];
    for (final f in files) {
      final Uint8List bytes;
      if (f.isRemote) {
        final acc = _ref.read(accountsProvider).where((a) => a.id == f.remoteAccountId).firstOrNull;
        if (acc == null) throw StateError('нет ящика вложения «${f.name}»');
        bytes = await _ref
            .read(mailEngineServiceProvider)
            .getAttachmentBytes(acc, f.remoteId!, emailId: f.remoteEmailId);
        if (bytes.isEmpty) throw StateError('сервер вернул пустое вложение «${f.name}»');
      } else if (f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      } else if (f.bytes != null) {
        bytes = f.bytes!;
      } else {
        continue;
      }
      out.add((name: f.name, contentType: f.mimeType, bytes: bytes));
    }
    return out;
  }

  /// Файлы выгруженного черновика ActiveSync — в кэш вложений под его id:
  /// открытый снова, он не качает их с сервера. Сопоставление — по имени.
  Future<void> _seedCache(String accountId, String emailId, List<EmailAttachment> list,
      List<({String name, String? contentType, Uint8List bytes})> files) async {
    final cache = _ref.read(attachmentCacheProvider);
    if (!cache.isReady) return; // фоновый изолят: кэш не открыт
    final left = [...files];
    for (final a in list) {
      final i = left.indexWhere((f) => f.name == a.name);
      if (i < 0) continue;
      final f = left.removeAt(i);
      try {
        await cache.put(MailEngineService.attachmentCacheKey(accountId, emailId, a.id), a.name, f.bytes);
      } catch (_) {}
    }
  }

  /// Черновик из серверной папки перед правкой: недостающее (адресаты,
  /// текст, список файлов) — с сервера, в базу и в ответ. complete — всё на
  /// месте; false — догрузить не удалось (нет связи): новую версию такого
  /// черновика выгружать можно, но прежнюю удалять нельзя.
  Future<({Email row, bool complete})> completeServerDraft(AccountModel account, Email row) async {
    final noBody = (row.bodyHtml ?? '').isEmpty && (row.bodyPlain ?? '').isEmpty;
    final noFiles = row.hasAttachments && (row.attachmentsJson ?? '').length <= 2;
    final noTo = (row.toRecipients).length <= 2; // «» или «[]»
    final ews = account.usesEws || account.isExchange;
    if (!noBody && !noFiles && !(ews && noTo)) return (row: row, complete: true);
    final db = _ref.read(databaseProvider);
    try {
      var c = const EmailsCompanion();
      if (ews) {
        final full = await _ref
            .read(mailEngineServiceProvider)
            .fetchEmailDetailEws(account, row.id)
            .timeout(const Duration(seconds: 15));
        if (full == null) return (row: row, complete: false);
        String? addrs(List<EmailAddress> l) => l.isEmpty ? null : jsonEncode([for (final a in l) a.toMap()]);
        c = EmailsCompanion(
          bodyHtml: full.bodyHtml != null ? Value(full.bodyHtml) : const Value.absent(),
          bodyPlain: full.bodyPlain != null ? Value(full.bodyPlain) : const Value.absent(),
          attachmentsJson: full.attachments.isEmpty
              ? const Value.absent()
              : Value(jsonEncode([for (final a in full.attachments) a.toMap()])),
          toRecipients: addrs(full.to) != null ? Value(addrs(full.to)!) : const Value.absent(),
          ccJson: addrs(full.cc) != null ? Value(addrs(full.cc)) : const Value.absent(),
          bccJson: addrs(full.bcc) != null ? Value(addrs(full.bcc)) : const Value.absent(),
        );
      } else if (account.usesEas) {
        final engine = _ref.read(mailEngineServiceProvider);
        if (noBody) {
          final b = await engine
              .fetchFullBody(account, folderId: row.folderId, serverId: row.id)
              .timeout(const Duration(seconds: 15));
          c = c.copyWith(
            bodyHtml: b?.bodyHtml != null ? Value(b!.bodyHtml) : const Value.absent(),
            bodyPlain: b?.bodyPlain != null ? Value(b!.bodyPlain) : const Value.absent(),
          );
        }
        if (noFiles) {
          final list = await engine
              .fetchAttachmentList(account, folderId: row.folderId, emailId: row.id)
              .timeout(const Duration(seconds: 15));
          if (list != null && list.isNotEmpty) {
            c = c.copyWith(attachmentsJson: Value(jsonEncode([for (final a in list) a.toMap()])));
          }
        }
      } else {
        final uid = int.tryParse(row.id.split(':').last) ?? 0;
        if (uid <= 0) return (row: row, complete: false);
        final full = await _ref
            .read(imapServiceProvider)
            .getEmailDetail(account, folderId: row.folderId, uid: uid, fetchMode: EmailFetchMode.noAttachments)
            .timeout(const Duration(seconds: 15));
        if (full == null) return (row: row, complete: false);
        c = EmailsCompanion(
          bodyHtml: full.bodyHtml != null ? Value(full.bodyHtml) : const Value.absent(),
          bodyPlain: full.bodyPlain != null ? Value(full.bodyPlain) : const Value.absent(),
          attachmentsJson: full.attachments.isEmpty
              ? const Value.absent()
              : Value(jsonEncode([for (final a in full.attachments) a.toMap()])),
        );
      }
      await (db.update(db.emails)..where((e) => e.id.equals(row.id) & e.accountId.equals(row.accountId))).write(c);
      final fresh = await (db.select(db.emails)
            ..where((e) => e.id.equals(row.id) & e.accountId.equals(row.accountId)))
          .getSingleOrNull();
      final r = fresh ?? row;
      final ok = (r.bodyHtml ?? '').isNotEmpty || (r.bodyPlain ?? '').isNotEmpty || !noBody;
      return (row: r, complete: ok && !(r.hasAttachments && (r.attachmentsJson ?? '').length <= 2));
    } catch (e) {
      AppLogger.warning('Черновик с сервера не догружен: $e');
      return (row: row, complete: false);
    }
  }

  /// Выгрузить все локальные черновики (после восстановления связи).
  Future<void> uploadPending() async {
    final db = _ref.read(databaseProvider);
    final rows = await (db.select(db.emails)..where((e) => e.folderId.equals('drafts'))).get();
    // Открытые в окне письма (в том числе в другом изоляте) — не трогаем.
    final prefs = _ref.read(sharedPrefsProvider);
    try {
      await prefs.reload().timeout(const Duration(seconds: 5));
    } catch (_) {}
    final open = _readEditing(prefs.getString(_editingKey)).keys.toSet();
    // Фоновая синхронизация идёт в отдельном изоляте и не знает, какие
    // черновики открыты на экране: берём только не менявшиеся 15 минут
    // (открытое письмо автосохраняется каждые 30 с).
    final quiet = DateTime.now().subtract(const Duration(minutes: 15));
    for (final r in rows) {
      // «undosend_…» — письмо, отправку которого отменили (1.7.2+111: раньше
      // такое письмо оставалось только на телефоне).
      if (!r.id.startsWith('draft-') && !r.id.startsWith('undosend_')) continue;
      if (r.receivedAt.isAfter(quiet) || open.contains(r.id)) continue;
      await upload(r.id, r.accountId);
    }
    // Файлы черновиков, которых больше нет (удалён ящик, сбой).
    await DraftFiles.sweep({for (final r in rows) r.id});
  }

  /// Подтянуть папку «Черновики», чтобы выгруженный черновик сразу появился.
  Future<void> _refreshDrafts(AccountModel account, AppDatabase db) async {
    try {
      final f = await (db.select(db.folders)
            ..where((f) => f.accountId.equals(account.id) & f.type.equals(FolderType.drafts.index)))
          .get()
          .then((l) => l.firstOrNull);
      if (f == null) return;
      await _ref.read(syncServiceProvider).syncSingleFolder(
          account,
          FolderModel(
            id: f.id,
            accountId: f.accountId,
            displayName: f.displayName,
            type: FolderType.drafts,
            serverPath: f.serverPath,
          ));
    } catch (_) {}
  }

  static List<EmailAddress> _addrs(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [
        for (final m in (jsonDecode(json) as List).whereType<Map>())
          if ((m['email'] ?? '').toString().isNotEmpty)
            EmailAddress.fromMap(Map<String, dynamic>.from(m)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _preview(String html) {
    final t = html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cutSafe(t, 200);
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

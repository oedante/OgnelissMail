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

import '../../core/utils/text_safe.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' as me show GatewaySizeRejected;

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

  /// Черновики, которые шлюз перед Exchange не пропустил по размеру
  /// (1.7.2+114): id → время сохранения черновика. Пока черновик тот же —
  /// не выгружаем.
  static final Map<String, DateTime> _tooBig = {};

  static const _replacesKey = 'draft_replaces';

  /// Черновик открыт из серверной папки: после выгрузки новой версии
  /// прежняя копия удаляется. Связь хранится, пока черновик не выгружен.
  Future<void> rememberReplace(String localId, ({String id, String folderId}) server) async {
    final prefs = _ref.read(sharedPrefsProvider);
    final m = _readReplaces();
    m[localId] = {'id': server.id, 'folderId': server.folderId};
    await prefs.setString(_replacesKey, jsonEncode(m));
  }

  Future<void> forget(String localId) async {
    final m = _readReplaces();
    if (m.remove(localId) != null) {
      await _ref.read(sharedPrefsProvider).setString(_replacesKey, jsonEncode(m));
    }
  }

  /// Серверная копия, которую заменит черновик [localId] (открыт из
  /// серверной папки, ещё не выгружен).
  ({String id, String folderId})? replacesFor(String localId) {
    final m = _readReplaces()[localId];
    final id = m?['id'], folder = m?['folderId'];
    return id == null || folder == null ? null : (id: id, folderId: folder);
  }

  Map<String, Map<String, String>> _readReplaces() {
    try {
      final raw = _ref.read(sharedPrefsProvider).getString(_replacesKey);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map(
          (k, v) => MapEntry(k as String, Map<String, String>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  /// Умеет ли ящик хранить черновики на сервере.
  static bool supports(AccountModel a) => a.usesEas || a.usesEws || a.isImap || a.isOAuth;

  /// Выгрузить локальный черновик. true — выгружен (локальная копия удалена).
  Future<bool> upload(String localId, String accountId) async {
    if (editing.contains(localId)) return false;
    final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (account == null || !supports(account)) return false;
    final failed = _failedAt[localId];
    if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 15)) {
      return false;
    }
    final db = _ref.read(databaseProvider);
    final row = await (db.select(db.emails)
          ..where((e) => e.id.equals(localId) & e.accountId.equals(accountId) & e.folderId.equals('drafts')))
        .getSingleOrNull();
    if (row == null) return false;
    // Этот же черновик шлюз уже не пропустил по размеру: тот же запрос в
    // несколько мегабайт каждые 15 минут ни к чему — ждём, пока его поправят.
    if (_tooBig[localId] == row.receivedAt) return false;

    final to = _addrs(row.toRecipients);
    final cc = _addrs(row.ccJson);
    final bcc = _addrs(row.bccJson);
    final body = row.bodyPlain ?? '';
    final html = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(body)
        ? body
        : '<div>${_esc(body).replaceAll('\n', '<br>')}</div>';

    // Файлы черновика: больше лимита ящика — сервер письмо не примет,
    // черновик остаётся на телефоне (повтор через 15 минут был бы тем же).
    final files = await DraftFiles.load(row.attachmentsJson) ?? const <DraftFile>[];
    final total = files.fold<int>(0, (s, f) => s + f.size);
    if (files.isNotEmpty && total > _ref.read(attachmentLimitProvider).limitFor(account.id)) {
      _failedAt[localId] = DateTime.now();
      AppLogger.info('Черновик с файлами на ${(total / 1048576).toStringAsFixed(1)} МБ больше лимита ящика — '
          'остаётся на устройстве');
      return false;
    }
    final List<({String name, String? contentType, Uint8List bytes})> attachments;
    try {
      attachments = await _readFiles(files);
    } catch (e) {
      _failedAt[localId] = DateTime.now();
      AppLogger.warning('Черновик: файлы не прочитаны или не скачаны (останется на устройстве): $e');
      return false;
    }

    ({String folderId, String id, List<EmailAttachment>? files})? easDraft;
    try {
      if (account.usesEas) {
        easDraft = await _ref.read(mailEngineServiceProvider).saveDraftEas(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, attachments: attachments);
        if (easDraft == null) return false; // AS ниже 16 — черновик остаётся на устройстве
      } else if (account.usesEws) {
        await _ref.read(ewsServiceProvider).saveDraft(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, attachments: attachments);
      } else {
        final mid = '<draft.${localId.hashCode.abs()}.${DateTime.now().millisecondsSinceEpoch}'
            '@${account.email.split('@').last}>';
        final path = await _ref.read(imapServiceProvider).saveDraft(account,
            to: to, cc: cc, bcc: bcc, subject: row.subject, bodyHtml: html, messageId: mid,
            attachments: attachments);
        if (path == null) return false; // папки «Черновики» на сервере нет
      }
    } catch (e) {
      _failedAt[localId] = DateTime.now();
      if (e is me.GatewaySizeRejected) _tooBig[localId] = row.receivedAt;
      AppLogger.warning('Черновик не выгружен на сервер (останется на устройстве): $e');
      return false;
    }
    _failedAt.remove(localId);
    if (attachments.isNotEmpty) {
      AppLogger.info('Черновик выгружен на сервер с файлами: ${attachments.length}');
    }

    // Прежняя серверная копия (черновик открывали из серверной папки).
    final replaces = _readReplaces()[localId];
    if (replaces != null) {
      try {
        await _ref.read(emailActionsProvider)
            .delete(account, replaces['id']!, replaces['folderId']!, hard: true);
      } catch (e) {
        AppLogger.warning('Прежняя копия черновика не удалена: $e');
      }
      await forget(localId);
    }

    // Локальная копия больше не нужна — черновик придёт с синхронизацией.
    await (db.delete(db.emails)
          ..where((e) => e.id.equals(localId) & e.accountId.equals(accountId)))
        .go();
    await DraftFiles.remove(localId);
    if (easDraft != null) {
      // ActiveSync не возвращает клиенту добавленный им элемент — строку
      // серверного черновика пишем сами (с его ServerId и списком файлов).
      final list = easDraft.files;
      await db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
            id: easDraft.id,
            accountId: accountId,
            folderId: easDraft.folderId,
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
            attachmentsJson: Value(list == null || list.isEmpty ? null : jsonEncode([for (final a in list) a.toMap()])),
            hasAttachments: Value(attachments.isNotEmpty),
            isDraft: const Value(true),
            isRead: const Value(true),
          ));
      if (list != null) await _seedCache(account.id, easDraft.id, list, attachments);
    } else {
      unawaited(_refreshDrafts(account, db));
    }
    return true;
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

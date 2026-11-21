// lib/features/compose/compose_window.dart
//
// Новое письмо, ответ и пересылка — отдельным окном на компьютере (Windows,
// macOS), 2.5.4, просьба владельца 15.11.2026: «для десктопа нужен
// многооконный режим и подход работы как в Outlook».
//
// Как устроено (desktop_multi_window, как окно письма — message_window.dart):
//  · окно — свой движок Flutter. Плагины в нём регистрирует нативная часть
//    приложения: windows/runner/flutter_window.cpp (правит
//    scripts/build_windows.ps1 и сборка на GitHub) и
//    tool/desktop/macos/MainFlutterWindow.swift;
//  · окно открывает ту же базу — файл и ключ даёт главное окно (просьба
//    composeInit) — и показывает тот же редактор (ComposeScreen) со всеми
//    его возможностями. Настройки — копией в памяти: два окна, пишущие в
//    один файл настроек, затирали бы изменения друг друга;
//  · отправляет главное окно ([WindowSendService] → composeSend /
//    composeSendUndo): очередь «Исходящих», «Отправка через N с · Отменить»,
//    повторы без связи — там же, где у писем из главного окна;
//  · изменения базы в окне (черновик, отметка «отвечено») — главному окну
//    (composeDbChanged): лента и папки обновляются сразу;
//  · окно не открылось — редактор открывается в главном окне, как раньше;
//    в окне что-то не запустилось — кнопка «Открыть в главном окне».
// Ответ из области чтения рядом с лентой — там же, в ней (как в Outlook).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:drift/drift.dart' show TableUpdate, TableUpdateQuery;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../services/mail/draft_sync_service.dart';
import '../../services/mail/email_actions_service.dart';
import '../../services/mail/offline_send_service.dart';
import '../mail/message_window.dart';
import '../mail/providers/mail_providers.dart' show accountsProvider;

/// Что открыть в окне редактора: параметры адреса /compose.
class ComposeWindowArgs {
  final Map<String, String> query;
  const ComposeWindowArgs(this.query);

  Map<String, Object?> toJson() => {'kind': ComposeWindow.kind, 'query': query};

  /// null — это не окно редактора.
  static ComposeWindowArgs? fromJson(Object? json) {
    if (json is! Map || json['kind'] != ComposeWindow.kind) return null;
    final q = json['query'];
    return ComposeWindowArgs({
      if (q is Map)
        for (final e in q.entries)
          if (e.value != null) '${e.key}': '${e.value}',
    });
  }
}

/// Что окно получает от главного при запуске.
class ComposeWindowInit {
  final Map<String, Object> prefs;
  final String dbPath;
  final String? dbKey;
  const ComposeWindowInit({required this.prefs, required this.dbPath, this.dbKey});
}

abstract final class ComposeWindow {
  static const kind = 'ogneliss-compose';

  /// «Письма — в отдельном окне» (настройки «Почта → Открытие писем»).
  static const prefKey = 'compose_window_on';

  /// Параметр адреса /compose: открыть в этом окне, даже если включены окна
  /// (окно не открылось, просьба окна «Открыть в главном окне»).
  static const hereParam = 'here';

  /// Этот движок — окно редактора.
  static bool inWindow = false;

  /// Номер этого окна (в окне редактора).
  static String? windowId;

  /// Windows и macOS: плагины в окнах регистрирует нативная часть сборки.
  /// Linux — редактор в главном окне, как раньше.
  static bool get supported => !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  /// Открывать редактор отдельным окном: компьютер, не само окно редактора,
  /// настройка включена. По умолчанию выключено — пробная возможность
  /// (владелец 15.11.2026: «если многооконность нестабильная… экспериментом,
  /// выключенным по умолчанию»).
  static bool enabled(SharedPreferences prefs) => supported && !inWindow && (prefs.getBool(prefKey) ?? false);

  /// Главное окно: черновики, которые правятся в окнах редактора, — id
  /// черновика → окно (отметки «правится» из окон, [ComposeWindowHost]).
  static final editing = <String, String>{};

  /// Черновик [draftId] уже открыт в окне — поднять то окно. Второе окно
  /// с тем же черновиком писало бы его поверх первого.
  static Future<bool> focusDraft(String draftId) async {
    final ids = <String>{if (editing[draftId] case final w?) w};
    try {
      for (final w in await WindowController.getAll()) {
        Object? json;
        try {
          json = jsonDecode(w.arguments);
        } catch (_) {}
        if (ComposeWindowArgs.fromJson(json)?.query['draftId'] == draftId) ids.add(w.windowId);
      }
    } catch (_) {}
    for (final id in ids) {
      try {
        await WindowController.fromWindowId(id).invokeMethod<Object?>(focusMethod);
        return true;
      } catch (e) {
        // Окна уже нет.
        editing.removeWhere((_, w) => w == id);
      }
    }
    return false;
  }

  /// Просьба главного окна окну редактора: выйти на передний план.
  static const focusMethod = 'composeFocus';

  /// В main(): этот движок — окно редактора? Тогда — что открыть.
  static Future<ComposeWindowArgs?> argsOfThisEngine() async {
    if (!supported) return null;
    try {
      final c = await WindowController.fromCurrentEngine();
      if (c.arguments.isEmpty) return null;
      return ComposeWindowArgs.fromJson(jsonDecode(c.arguments));
    } catch (_) {
      return null;
    }
  }

  /// Окна, которые ещё не сообщили «показано» ([composeReady]).
  static final _pending = <String, Timer>{};

  /// Главное окно: открыть редактор [query] отдельным окном. false — окно
  /// не создалось (тогда редактор — в главном окне).
  static Future<bool> open(Map<String, String> query) async {
    final draft = query['draftId'];
    if (draft != null && await focusDraft(draft)) return true;
    try {
      final c = await WindowController.create(
          WindowConfiguration(arguments: jsonEncode(ComposeWindowArgs(query).toJson()), hiddenAtLaunch: true));
      // Окно показывает себя само, когда задаст размер и заголовок; не
      // сообщило за 6 с (сбой при запуске) — показать как есть: внутри
      // будет причина и «Открыть в главном окне».
      _pending[c.windowId] = Timer(const Duration(seconds: 6), () {
        _pending.remove(c.windowId);
        unawaited(c.show().catchError((Object _) {}));
      });
      return true;
    } catch (e) {
      AppLogger.warning('Окно редактора не создано — редактор в главном окне: $e');
      return false;
    }
  }

  /// Окно сообщило, что показано.
  static void ready(String windowId) => _pending.remove(windowId)?.cancel();

  /// Работа, которую окно должно закончить до закрытия (запись черновика
  /// при закрытии редактора). В главном окне — просто возвращает [f].
  static Future<T> track<T>(Future<T> f) {
    if (!inWindow) return f;
    _work.add(f);
    f.whenComplete(() => _work.remove(f)).ignore();
    return f;
  }

  static final _work = <Future<Object?>>{};

  /// Дождаться [track] (не дольше [timeout]).
  static Future<void> idle({Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (_work.isNotEmpty && DateTime.now().isBefore(deadline)) {
      try {
        await Future.wait(List.of(_work)).timeout(deadline.difference(DateTime.now()));
      } catch (_) {
        break;
      }
    }
  }

  // ── Окно редактора → главное окно ──

  /// Настройки, файл и ключ базы (главное окно).
  static Future<ComposeWindowInit> init() async {
    final r = await MessageWindow.request('composeInit', const {});
    if (r is! Map || r['dbPath'] is! String) throw StateError('главное окно не ответило: $r');
    return ComposeWindowInit(
      prefs: decodePrefs(r['prefs']),
      dbPath: r['dbPath'] as String,
      dbKey: r['dbKey'] as String?,
    );
  }

  /// Изменения базы в окне — главному окну (раз в 300 мс пачкой).
  static StreamSubscription<void> forwardDbChanges(AppDatabase db) {
    final tables = <String>{};
    Timer? flush;
    return db.tableUpdates(const TableUpdateQuery.any()).listen((updates) {
      for (final u in updates) {
        tables.add(u.table);
      }
      flush ??= Timer(const Duration(milliseconds: 300), () {
        flush = null;
        final names = tables.toList();
        tables.clear();
        unawaited(MessageWindow.ask('composeDbChanged', {'tables': names}));
      });
    });
  }

  /// Настройки копией: значения, которые передаёт канал (списки строк
  /// приходят списками объектов).
  @visibleForTesting
  static Map<String, Object> decodePrefs(Object? raw) {
    final out = <String, Object>{};
    if (raw is! Map) return out;
    for (final e in raw.entries) {
      final v = e.value;
      if (v is List) {
        out['${e.key}'] = [for (final x in v) '$x'];
      } else if (v is bool || v is int || v is double || v is String) {
        out['${e.key}'] = v as Object;
      }
    }
    return out;
  }
}

/// Главное окно: просьбы окон редактора (через канал окон писем,
/// message_window_host.dart).
abstract final class ComposeWindowHost {
  static bool handles(String method) => method.startsWith('compose');

  static Future<Object?> handle(ProviderContainer c, String method, Map<String, Object?> a) async {
    switch (method) {
      case 'composeInit':
        final path = AppDatabase.openedPath;
        if (path == null) throw StateError('база главного окна ещё не открыта');
        final prefs = c.read(sharedPrefsProvider);
        return {
          'prefs': {for (final k in prefs.getKeys()) k: prefs.get(k)},
          'dbPath': path,
          'dbKey': AppDatabase.openedKey,
        };
      case 'composeReady':
        ComposeWindow.ready('${a['windowId'] ?? ''}');
        return true;
      case 'composeDbChanged':
        final tables = [for (final t in (a['tables'] as List? ?? const [])) '$t'];
        if (tables.isNotEmpty) {
          c.read(databaseProvider).notifyUpdates({for (final t in tables) TableUpdate(t)});
        }
        return true;
      case 'composeSend':
        return send(c.read(offlineSendProvider), a);
      case 'composeDraft':
        return draft(c, a);
      case 'composeDelete':
        final account = c.read(accountsProvider).where((x) => x.id == '${a['accountId']}').firstOrNull;
        if (account == null) throw StateError('ящик не найден');
        await c.read(emailActionsProvider).delete(account, '${a['emailId']}', '${a['folderId']}', hard: a['hard'] == true);
        return true;
      case 'composeSendUndo':
        final id = await c.read(offlineSendProvider).scheduleUndoSend(
              accountId: '${a['accountId']}',
              fromEmail: '${a['fromEmail']}',
              to: SendCodec.addrs(a['to']),
              cc: SendCodec.addrs(a['cc']),
              bcc: SendCodec.addrs(a['bcc']),
              subject: '${a['subject'] ?? ''}',
              bodyHtml: '${a['bodyHtml'] ?? ''}',
              bodyPlain: a['bodyPlain'] as String?,
              inReplyTo: a['inReplyTo'] as String?,
              attachments: SendCodec.files(a['attachments']),
              importance: '${a['importance'] ?? 'Normal'}',
              sensitivity: '${a['sensitivity'] ?? 'Normal'}',
              window: Duration(milliseconds: (a['windowMs'] as num?)?.toInt() ?? 5000),
              remoteAttachments: SendCodec.remote(a['remote']),
              from: SendCodec.addr(a['from']),
              requestDeliveryReport: a['dsn'] == true,
              requestReadReceipt: a['mdn'] == true,
            );
        return {'outboxId': id};
    }
    return null;
  }

  /// Черновики окна редактора: отметка «правится» (фоновая выгрузка его не
  /// трогает), связь с серверной копией, выгрузка на сервер, догрузка
  /// черновика из серверной папки.
  static Future<Object?> draft(ProviderContainer c, Map<String, Object?> a) async {
    final s = c.read(draftSyncServiceProvider);
    final id = '${a['id'] ?? ''}';
    switch (a['op']) {
      case 'begin':
        s.beginEdit(id);
        if (a['window'] case final String w when w.isNotEmpty) ComposeWindow.editing[id] = w;
      case 'end':
        s.endEdit(id);
        if (ComposeWindow.editing[id] == a['window']) ComposeWindow.editing.remove(id);
      case 'replace':
        await s.rememberReplace(id, (id: '${a['server']}', folderId: '${a['folder']}'));
      case 'forget':
        await s.forget(id);
      case 'upload':
        // Окно закрывается — выгрузка идёт здесь, без ожидания.
        unawaited(s.upload(id, '${a['acc']}').catchError((Object _) => false));
      case 'complete':
        final account = c.read(accountsProvider).where((x) => x.id == '${a['acc']}').firstOrNull;
        final raw = a['row'];
        if (account == null || raw is! Map) return null;
        final r = await s.completeServerDraft(account, Email.fromJson(Map<String, dynamic>.from(raw)));
        return {'row': r.row.toJson(), 'complete': r.complete};
    }
    return true;
  }

  /// Отправка письма окна редактора. Ответ: {sent} или {error: too_large |
  /// failed}.
  @visibleForTesting
  static Future<Map<String, Object?>> send(OfflineSendService service, Map<String, Object?> a) async {
    try {
      final sent = await service.sendOrQueue(
        accountId: '${a['accountId']}',
        to: SendCodec.addrs(a['to']),
        cc: SendCodec.addrs(a['cc']),
        bcc: SendCodec.addrs(a['bcc']),
        subject: '${a['subject'] ?? ''}',
        bodyHtml: '${a['bodyHtml'] ?? ''}',
        inReplyTo: a['inReplyTo'] as String?,
        attachments: SendCodec.files(a['attachments']),
        importance: '${a['importance'] ?? 'Normal'}',
        sensitivity: '${a['sensitivity'] ?? 'Normal'}',
        remoteAttachments: SendCodec.remote(a['remote']),
        from: SendCodec.addr(a['from']),
        keepTooLarge: a['keepTooLarge'] == true,
        requestDeliveryReport: a['dsn'] == true,
        requestReadReceipt: a['mdn'] == true,
      );
      return {'sent': sent};
    } on MessageTooLargeException catch (e) {
      return {'error': 'too_large', 'size': e.sizeBytes, 'limit': e.limitBytes, 'gateway': e.gateway};
    } catch (e) {
      return {'error': 'failed', 'message': '$e'};
    }
  }
}

/// Письмо для канала окон: адреса, файлы, ссылки на не скачанные файлы.
abstract final class SendCodec {
  static Map<String, Object?> addrMap(EmailAddress a) => {'email': a.email, 'name': a.displayName};
  static List<Map<String, Object?>> addrList(List<EmailAddress> l) => [for (final a in l) addrMap(a)];

  static EmailAddress? addr(Object? m) {
    if (m is! Map) return null;
    final email = '${m['email'] ?? ''}';
    if (email.isEmpty) return null;
    return EmailAddress(email: email, displayName: m['name'] as String?);
  }

  static List<EmailAddress> addrs(Object? l) => [
        for (final m in (l as List? ?? const []))
          if (addr(m) case final a?) a,
      ];

  static List<Map<String, Object?>> fileList(List<({String name, String? contentType, Uint8List bytes})> l) =>
      [for (final f in l) {'name': f.name, 'type': f.contentType, 'bytes': f.bytes}];

  static List<({String name, String? contentType, Uint8List bytes})> files(Object? l) => [
        for (final m in (l as List? ?? const []))
          if (m is Map && m['bytes'] is Uint8List)
            (name: '${m['name'] ?? ''}', contentType: m['type'] as String?, bytes: m['bytes'] as Uint8List),
      ];

  static List<Map<String, Object?>> remoteList(List<RemoteAttachment> l) => [
        for (final r in l)
          {'acc': r.accountId, 'email': r.emailId, 'att': r.attachmentId, 'name': r.name, 'type': r.contentType},
      ];

  static List<RemoteAttachment> remote(Object? l) => [
        for (final m in (l as List? ?? const []))
          if (m is Map)
            (
              accountId: '${m['acc']}',
              emailId: '${m['email']}',
              attachmentId: '${m['att']}',
              name: '${m['name'] ?? ''}',
              contentType: m['type'] as String?,
            ),
      ];
}

/// Отправка в окне редактора: письмо уходит через главное окно (его
/// очередь «Исходящих», связь и учётные данные).
class WindowSendService extends OfflineSendService {
  WindowSendService(super.ref);

  @override
  Future<bool> sendOrQueue({
    required String accountId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool keepTooLarge = false,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
    bool showInConversation = true,
  }) async {
    final r = await MessageWindow.request('composeSend', {
      'accountId': accountId,
      'to': SendCodec.addrList(to),
      'cc': SendCodec.addrList(cc),
      'bcc': SendCodec.addrList(bcc),
      'subject': subject,
      'bodyHtml': bodyHtml,
      'inReplyTo': inReplyTo,
      'attachments': SendCodec.fileList(attachments),
      'importance': importance,
      'sensitivity': sensitivity,
      'remote': SendCodec.remoteList(remoteAttachments),
      'from': from == null ? null : SendCodec.addrMap(from),
      'keepTooLarge': keepTooLarge,
      'dsn': requestDeliveryReport,
      'mdn': requestReadReceipt,
    });
    return decodeSendResult(r);
  }

  /// Ответ главного окна на отправку: отправлено / в очереди или ошибка.
  @visibleForTesting
  static bool decodeSendResult(Object? r) {
    if (r is! Map) throw StateError('главное окно не ответило на отправку');
    switch (r['error']) {
      case 'too_large':
        throw MessageTooLargeException(
          sizeBytes: (r['size'] as num?)?.toInt(),
          limitBytes: (r['limit'] as num?)?.toInt(),
          gateway: r['gateway'] == true,
        );
      case 'failed':
        throw StateError('${r['message'] ?? 'отправка не удалась'}');
    }
    return r['sent'] == true;
  }

  @override
  Future<String> scheduleUndoSend({
    required String accountId,
    required String fromEmail,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? bodyPlain,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    required Duration window,
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
    bool showInConversation = true,
  }) async {
    final r = await MessageWindow.request('composeSendUndo', {
      'accountId': accountId,
      'fromEmail': fromEmail,
      'to': SendCodec.addrList(to),
      'cc': SendCodec.addrList(cc),
      'bcc': SendCodec.addrList(bcc),
      'subject': subject,
      'bodyHtml': bodyHtml,
      'bodyPlain': bodyPlain,
      'inReplyTo': inReplyTo,
      'attachments': SendCodec.fileList(attachments),
      'importance': importance,
      'sensitivity': sensitivity,
      'windowMs': window.inMilliseconds,
      'remote': SendCodec.remoteList(remoteAttachments),
      'from': from == null ? null : SendCodec.addrMap(from),
      'dsn': requestDeliveryReport,
      'mdn': requestReadReceipt,
    });
    if (r is! Map || r['outboxId'] is! String) throw StateError('главное окно не поставило письмо в очередь');
    return r['outboxId'] as String;
  }
}

/// Черновики в окне редактора: что меняет общее состояние или ходит на
/// сервер — через главное окно (его синхронизация видит отметку «правится»,
/// выгружает черновик своими соединениями).
class WindowDraftSyncService extends DraftSyncService {
  WindowDraftSyncService(super.ref);

  @override
  void beginEdit(String id) {
    super.beginEdit(id);
    unawaited(MessageWindow.ask('composeDraft', {'op': 'begin', 'id': id, 'window': ComposeWindow.windowId}));
  }

  @override
  void endEdit(String id) {
    super.endEdit(id);
    unawaited(MessageWindow.ask('composeDraft', {'op': 'end', 'id': id, 'window': ComposeWindow.windowId}));
  }

  @override
  Future<void> rememberReplace(String localId, ({String id, String folderId}) server) async {
    await super.rememberReplace(localId, server);
    await MessageWindow.ask('composeDraft', {'op': 'replace', 'id': localId, 'server': server.id, 'folder': server.folderId});
  }

  @override
  Future<void> forget(String localId) async {
    await super.forget(localId);
    await MessageWindow.ask('composeDraft', {'op': 'forget', 'id': localId});
  }

  @override
  Future<bool> upload(String localId, String accountId) async {
    await MessageWindow.ask('composeDraft', {'op': 'upload', 'id': localId, 'acc': accountId});
    return true;
  }

  @override
  Future<({Email row, bool complete})> completeServerDraft(AccountModel account, Email row) async {
    try {
      final r = await MessageWindow.request('composeDraft', {'op': 'complete', 'acc': account.id, 'row': row.toJson()});
      if (r is Map && r['row'] is Map) {
        return (row: Email.fromJson(Map<String, dynamic>.from(r['row'] as Map)), complete: r['complete'] == true);
      }
    } catch (e) {
      AppLogger.warning('Окно редактора: черновик с сервера не догружен — $e');
    }
    return (row: row, complete: false);
  }
}

/// Удаление в окне редактора (серверный черновик после отправки) — через
/// главное окно.
class WindowEmailActions extends EmailActionsService {
  WindowEmailActions(super.ref);

  @override
  Future<void> delete(AccountModel account, String emailId, String folderId, {bool hard = false}) async {
    final r = await MessageWindow.request(
        'composeDelete', {'accountId': account.id, 'emailId': emailId, 'folderId': folderId, 'hard': hard});
    if (r != true) throw StateError('главное окно не удалило письмо');
  }
}

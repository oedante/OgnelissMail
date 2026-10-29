// lib/services/mail/graph/graph_server_tools.dart
// Правила сервера и «Восстановить удалённые» у Exchange Online через
// Microsoft Graph (1.8.10): то же, что ews_server_tools.dart по EWS, — EWS
// в Exchange Online Microsoft отключает (см. graph_client.dart).
//
// Правила — /me/mailFolders/inbox/messageRules (MailboxSettings.ReadWrite):
// список, включить/выключить (PATCH isEnabled — правило не заменяется
// целиком, как в EWS), создать и удалить. Правила, которые Graph показывает
// только для чтения (созданы Outlook с условиями, которых Graph не знает),
// не меняются.
//
// Восстановить удалённые — папка recoverableitemsdeletions (Mail.ReadWrite):
// список писем и перенос во «Входящие».

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../ews/ews_server_tools.dart';
import '../sieve/sieve_rules.dart';
import 'graph_client.dart';

final graphServerToolsProvider = Provider<GraphServerTools>((ref) => GraphServerTools(ref.watch(graphClientProvider)));

class GraphServerTools implements ServerTools {
  final GraphClient _g;
  GraphServerTools(this._g);

  static const _rules = '/me/mailFolders/inbox/messageRules';

  /// Действия правила Graph → коды подписи (как у EWS).
  static const _actionMap = {
    'moveToFolder': 'move',
    'copyToFolder': 'copy',
    'delete': 'delete',
    'permanentDelete': 'delete',
    'forwardTo': 'forward',
    'forwardAsAttachmentTo': 'forward',
    'redirectTo': 'redirect',
    'markAsRead': 'read',
    'markImportance': 'importance',
    'assignCategories': 'category',
    'stopProcessingRules': 'stop',
  };

  @override
  Future<ServerRulesResult> getRules(AccountModel account) async {
    try {
      return ServerRulesResult(parseRules(await _g.list(account, _rules)));
    } catch (e) {
      AppLogger.warning('Graph: правила сервера — $e');
      return ServerRulesResult(const [], error: '$e');
    }
  }

  /// Список messageRules → правила, по порядку выполнения.
  static List<ServerRule> parseRules(List<Map<String, dynamic>> list) {
    final out = <ServerRule>[];
    for (final r in list) {
      final id = r['id'];
      if (id is! String || id.isEmpty) continue;
      final actions = <String>{};
      final a = r['actions'];
      if (a is Map) {
        for (final e in a.entries) {
          final v = e.value;
          final on = v == true || (v is String && v.isNotEmpty) || (v is List && v.isNotEmpty);
          final code = _actionMap[e.key];
          if (on && code != null) actions.add(code);
        }
      }
      out.add(ServerRule(
        id: id,
        name: '${r['displayName'] ?? ''}',
        enabled: r['isEnabled'] != false,
        priority: (r['sequence'] as num?)?.toInt() ?? 1,
        readOnly: r['isReadOnly'] == true,
        inError: r['hasError'] == true,
        actions: actions.toList(),
        raw: r,
      ));
    }
    out.sort((a, b) => a.priority.compareTo(b.priority));
    return out;
  }

  @override
  Future<String?> setEnabled(AccountModel account, ServerRule rule, bool enabled) async {
    if (rule.readOnly) return 'readOnly';
    return _run('isEnabled', () => _g.patch(account, '$_rules/${Uri.encodeComponent(rule.id)}', {'isEnabled': enabled}));
  }

  /// Новое правило [r] (одно условие, одно действие) → тело messageRule.
  static Map<String, Object> ruleBody(SieveRule r, int priority) {
    final v = r.value.trim();
    final exact = r.op == SieveOp.isExactly;
    List<Map<String, Object>> addresses(String a) => [
          {
            'emailAddress': {'address': a}
          }
        ];
    final conditions = <String, Object>{
      switch (r.field) {
        SieveField.from => exact ? 'fromAddresses' : 'senderContains',
        SieveField.to => exact ? 'sentToAddresses' : 'recipientContains',
        SieveField.subject => 'subjectContains',
        SieveField.any => 'bodyOrSubjectContains',
      }: (r.field == SieveField.from || r.field == SieveField.to) && exact ? addresses(v) : [v],
    };
    final actions = <String, Object>{
      if (r.action == SieveAction.delete) 'delete': true,
      if (r.action == SieveAction.markRead) 'markAsRead': true,
      if (r.action == SieveAction.move) 'moveToFolder': r.arg.trim(),
      if (r.action == SieveAction.forward) 'forwardTo': addresses(r.arg.trim()),
      if (r.stop || r.action == SieveAction.delete) 'stopProcessingRules': true,
    };
    final name = r.name.trim().isNotEmpty ? r.name.trim() : v;
    return {
      'displayName': name,
      'sequence': priority < 1 ? 1 : priority,
      'isEnabled': r.enabled,
      'conditions': conditions,
      'actions': actions,
    };
  }

  @override
  Future<String?> createRule(AccountModel account, SieveRule rule, {required int priority}) =>
      _run('create', () => _g.post(account, _rules, ruleBody(rule, priority)));

  @override
  Future<String?> deleteRule(AccountModel account, ServerRule rule) =>
      _run('delete', () => _g.delete(account, '$_rules/${Uri.encodeComponent(rule.id)}'));

  Future<String?> _run(String what, Future<Object?> Function() f) async {
    try {
      await f();
      AppLogger.info('Graph: правило сервера ($what) — готово');
      return null;
    } on GraphException catch (e) {
      AppLogger.warning('Graph: правило сервера ($what) — $e');
      return e.message.isNotEmpty ? '${e.code}: ${e.message}' : '$e';
    } catch (e) {
      AppLogger.warning('Graph: правило сервера ($what) — $e');
      return '$e';
    }
  }

  /// Папки ящика для «Переложить в папку» (id Graph — у ActiveSync свои):
  /// подпись — путь «Папка/Подпапка», без «Черновиков» и «Исходящих».
  @override
  Future<List<({String id, String label})>> ruleFolders(AccountModel account) async {
    final skip = <String>{};
    for (final name in const ['drafts', 'outbox']) {
      try {
        final f = await _g.get(account, '/me/mailFolders/$name', query: {r'$select': 'id'});
        if (f is Map && f['id'] is String) skip.add(f['id'] as String);
      } catch (_) {}
    }
    final out = <({String id, String label})>[];
    // Обход в ширину: верхний уровень и подпапки, не глубже 4 уровней и не
    // больше 300 папок.
    var level = <({String id, String path})>[];
    final top = await _g.list(account, '/me/mailFolders',
        query: {r'$select': 'id,displayName,childFolderCount', r'$top': '100'});
    for (final f in top) {
      final id = f['id'];
      if (id is! String) continue;
      final path = '${f['displayName'] ?? ''}';
      if (!skip.contains(id)) out.add((id: id, label: path));
      if ((f['childFolderCount'] as num? ?? 0) > 0) level.add((id: id, path: path));
    }
    for (var depth = 0; depth < 3 && level.isNotEmpty && out.length < 300; depth++) {
      final next = <({String id, String path})>[];
      for (final p in level) {
        final kids = await _g.list(account, '/me/mailFolders/${Uri.encodeComponent(p.id)}/childFolders',
            query: {r'$select': 'id,displayName,childFolderCount', r'$top': '100'}, maxPages: 2);
        for (final f in kids) {
          final id = f['id'];
          if (id is! String) continue;
          final path = '${p.path}/${f['displayName'] ?? ''}';
          if (!skip.contains(id)) out.add((id: id, label: path));
          if ((f['childFolderCount'] as num? ?? 0) > 0) next.add((id: id, path: path));
        }
      }
      level = next;
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  @override
  Future<List<RecoverableItem>> getRecoverable(AccountModel account, {int max = 100}) async {
    final list = await _g.list(account, '/me/mailFolders/recoverableitemsdeletions/messages',
        query: {
          r'$select': 'subject,from,receivedDateTime',
          r'$orderby': 'receivedDateTime desc',
          r'$top': '${max.clamp(1, 100)}',
        },
        maxPages: 1);
    return parseRecoverable(list);
  }

  static List<RecoverableItem> parseRecoverable(List<Map<String, dynamic>> list) => [
        for (final m in list)
          if (m['id'] case final String id when id.isNotEmpty)
            RecoverableItem(
              id: id,
              changeKey: '',
              subject: '${m['subject'] ?? ''}',
              from: () {
                final f = m['from'];
                final e = f is Map ? f['emailAddress'] : null;
                if (e is! Map) return '';
                final name = '${e['name'] ?? ''}'.trim();
                return name.isNotEmpty ? name : '${e['address'] ?? ''}'.trim();
              }(),
              received: DateTime.tryParse('${m['receivedDateTime'] ?? ''}')?.toLocal(),
              itemClass: '',
            ),
      ];

  /// Вернуть письма во «Входящие». Возвращает, сколько восстановлено.
  @override
  Future<int> restore(AccountModel account, List<RecoverableItem> items) async {
    var n = 0;
    for (final i in items) {
      try {
        await _g.post(account, '/me/messages/${Uri.encodeComponent(i.id)}/move', {'destinationId': 'inbox'});
        n++;
      } catch (e) {
        AppLogger.warning('Graph: письмо не восстановлено — $e');
      }
    }
    return n;
  }
}

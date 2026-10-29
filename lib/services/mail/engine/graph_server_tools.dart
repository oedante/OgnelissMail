// lib/services/mail/engine/graph_server_tools.dart
// Правила сервера и «Восстановить удалённые» у Exchange Online через
// Microsoft Graph — то же, что ews_server_tools.dart по EWS (EWS в Exchange
// Online Microsoft отключает). Запросы делает движок (me.GraphEngine,
// 1.8.11), здесь — перевод в модели экрана «Средства Exchange».
//
// Правила — список, включить/выключить (меняется только isEnabled — правило
// не заменяется целиком, как в EWS), создать и удалить. Правила, которые
// Graph показывает только для чтения (созданы Outlook с условиями, которых
// Graph не знает), не меняются.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../ews/ews_server_tools.dart';
import '../oauth/graph_tokens.dart';
import '../sieve/sieve_rules.dart';

final graphServerToolsProvider = Provider<GraphServerTools>((ref) => GraphServerTools(ref.watch(graphTokensProvider)));

class GraphServerTools implements ServerTools {
  final GraphTokens _tokens;
  GraphServerTools(this._tokens);

  me.GraphEngine _engine(AccountModel a) =>
      _tokens.engine(a) ?? (throw const me.GraphException(0, 'unavailable'));

  @override
  Future<ServerRulesResult> getRules(AccountModel account) async {
    try {
      return ServerRulesResult([for (final r in await _engine(account).rules()) ruleFromGraph(r)]);
    } catch (e) {
      AppLogger.warning('Graph: правила сервера — $e');
      return ServerRulesResult(const [], error: '$e');
    }
  }

  static ServerRule ruleFromGraph(me.GraphRule r) => ServerRule(
        id: r.id,
        name: r.name,
        enabled: r.enabled,
        priority: r.sequence,
        readOnly: r.readOnly,
        inError: r.hasError,
        actions: r.actions.toList(),
        raw: r,
      );

  /// Правило редактора (одно условие, одно действие) → правило Graph. null —
  /// такого действия у правил Graph нет (флажок).
  static me.GraphRuleSpec? specFromSieve(SieveRule r, int priority) {
    final action = switch (r.action) {
      SieveAction.move => me.GraphRuleAction.move,
      SieveAction.markRead => me.GraphRuleAction.markRead,
      SieveAction.delete => me.GraphRuleAction.delete,
      SieveAction.forward => me.GraphRuleAction.forward,
      SieveAction.flag => null,
    };
    if (action == null) return null;
    return me.GraphRuleSpec(
      name: r.name,
      field: switch (r.field) {
        SieveField.from => me.GraphRuleField.from,
        SieveField.to => me.GraphRuleField.to,
        SieveField.subject => me.GraphRuleField.subject,
        SieveField.any => me.GraphRuleField.any,
      },
      exact: r.op == SieveOp.isExactly,
      value: r.value,
      action: action,
      arg: r.arg,
      stop: r.stop,
      enabled: r.enabled,
      sequence: priority,
    );
  }

  @override
  Future<String?> setEnabled(AccountModel account, ServerRule rule, bool enabled) async {
    if (rule.readOnly) return 'readOnly';
    return _run('isEnabled', () => _engine(account).setRuleEnabled(rule.id, enabled));
  }

  @override
  Future<String?> createRule(AccountModel account, SieveRule rule, {required int priority}) async {
    final spec = specFromSieve(rule, priority);
    if (spec == null) return 'unsupported';
    return _run('create', () => _engine(account).createRule(spec));
  }

  @override
  Future<String?> deleteRule(AccountModel account, ServerRule rule) =>
      _run('delete', () => _engine(account).deleteRule(rule.id));

  Future<String?> _run(String what, Future<void> Function() f) async {
    try {
      await f();
      AppLogger.info('Graph: правило сервера ($what) — готово');
      return null;
    } on me.GraphException catch (e) {
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
  Future<List<({String id, String label})>> ruleFolders(AccountModel account) async =>
      [for (final f in await _engine(account).mailFolders()) (id: f.id, label: f.path)];

  @override
  Future<List<RecoverableItem>> getRecoverable(AccountModel account, {int max = 100}) async => [
        for (final m in await _engine(account).recoverableItems(max: max))
          RecoverableItem(id: m.id, changeKey: '', subject: m.subject, from: m.from, received: m.received, itemClass: ''),
      ];

  /// Вернуть письма во «Входящие». Возвращает, сколько восстановлено.
  @override
  Future<int> restore(AccountModel account, List<RecoverableItem> items) =>
      _engine(account).restoreToInbox([for (final i in items) i.id]);
}

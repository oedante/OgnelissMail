// lib/services/rules/auto_rules_service.dart
import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/shared_prefs_provider.dart';

final autoRulesProvider = StateNotifierProvider<AutoRulesNotifier, List<AutoRule>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return AutoRulesNotifier(prefs);
});

// ── Enums ────────────────────────────────────────────────────────────────────

enum RuleConditionType {
  senderContains,
  senderEquals,
  subjectContains,
  bodyContains,
  hasAttachments,
  priorityHigh,
  sizeGreaterThan,
  recipientCount,
}

enum RuleConditionOp { contains, notContains, equals, startsWith, endsWith }

enum RuleActionType {
  moveTo,       // переместить в папку
  moveToFolder, // alias for UI compatibility
  addTag,       // добавить тег
  markAsRead,   // прочитать
  markFlagged,  // пометить
  setCategory,  // категория
  delete,       // удалить
  forward,      // переслать
  forwardTo,    // переслать на адрес
  autoReply,    // автоответ
  notify,       // уведомить
  playSound,    // звук
}

// ── Models ───────────────────────────────────────────────────────────────────

class RuleCondition {
  final RuleConditionType type;
  final String value;
  const RuleCondition({required this.type, this.value = ''});

  bool matches(EmailModel email) {
    final v = value.toLowerCase();
    switch (type) {
      case RuleConditionType.senderContains:
        return email.from.email.toLowerCase().contains(v) ||
               (email.from.displayName?.toLowerCase().contains(v) ?? false);
      case RuleConditionType.senderEquals:
        return email.from.email.toLowerCase() == v;
      case RuleConditionType.subjectContains:
        return email.subject.toLowerCase().contains(v);
      case RuleConditionType.bodyContains:
        return (email.bodyPlain ?? '').toLowerCase().contains(v);
      case RuleConditionType.hasAttachments:
        return email.hasAttachments;
      case RuleConditionType.priorityHigh:
        return email.priority == EmailPriority.high;
      case RuleConditionType.sizeGreaterThan:
        final size = int.tryParse(v) ?? 0;
        return (email.size ?? 0) > size;
      case RuleConditionType.recipientCount:
        final count = int.tryParse(v) ?? 0;
        return (email.to.length + email.cc.length) > count;
    }
  }

  Map<String, dynamic> toMap() => {'type': type.index, 'value': value};
  factory RuleCondition.fromMap(Map<String, dynamic> m) => RuleCondition(
    type: RuleConditionType.values[m['type'] ?? 0],
    value: m['value'] ?? '',
  );
}

class RuleAction {
  final RuleActionType type;
  final String value;
  const RuleAction({required this.type, this.value = ''});

  Map<String, dynamic> toMap() => {'type': type.index, 'value': value};
  factory RuleAction.fromMap(Map<String, dynamic> m) => RuleAction(
    type: RuleActionType.values[m['type'] ?? 0],
    value: m['value'] ?? '',
  );
}

/// Где выполняется правило: в приложении (клиент) или на сервере (Exchange
/// Inbox Rules). Серверные применяются ко всем клиентам и когда телефон выключен,
/// но поддерживают лишь часть условий/действий (см. `isServerCompatible`).
enum RuleExecution { client, server }

class AutoRule {
  final String id;
  final String name;
  final bool isEnabled;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;
  final bool stopProcessing;
  final int priority;
  final bool matchAll; // true = AND, false = OR
  final RuleExecution execution;
  /// Серверный RuleId (EWS), если правило заведено на сервере. Нужен для
  /// последующего изменения/удаления. null — ещё не синхронизировано.
  final String? serverRuleId;

  const AutoRule({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.conditions = const [],
    this.actions = const [],
    this.stopProcessing = false,
    this.priority = 0,
    this.matchAll = true,
    this.execution = RuleExecution.client,
    this.serverRuleId,
  });

  AutoRule copyWith({
    String? id, String? name, bool? isEnabled,
    List<RuleCondition>? conditions, List<RuleAction>? actions,
    bool? stopProcessing, int? priority, bool? matchAll,
    RuleExecution? execution, String? serverRuleId,
  }) => AutoRule(
    id: id ?? this.id,
    name: name ?? this.name,
    isEnabled: isEnabled ?? this.isEnabled,
    conditions: conditions ?? this.conditions,
    actions: actions ?? this.actions,
    stopProcessing: stopProcessing ?? this.stopProcessing,
    priority: priority ?? this.priority,
    matchAll: matchAll ?? this.matchAll,
    execution: execution ?? this.execution,
    serverRuleId: serverRuleId ?? this.serverRuleId,
  );

  /// Условия и действия, которые Exchange Inbox Rules умеет выполнять.
  static const _serverConditions = {
    RuleConditionType.senderContains,
    RuleConditionType.senderEquals,
    RuleConditionType.subjectContains,
    RuleConditionType.bodyContains,
    RuleConditionType.hasAttachments,
    RuleConditionType.priorityHigh,
    RuleConditionType.sizeGreaterThan,
  };
  static const _serverActions = {
    RuleActionType.moveTo,
    RuleActionType.moveToFolder,
    RuleActionType.markAsRead,
    RuleActionType.setCategory,
    RuleActionType.forwardTo,
    RuleActionType.delete,
  };

  /// Можно ли выполнить это правило на сервере (все условия и действия
  /// поддерживаются протоколом). Если false — правило должно остаться клиентским.
  bool get isServerCompatible =>
      conditions.isNotEmpty &&
      conditions.every((c) => _serverConditions.contains(c.type)) &&
      actions.isNotEmpty &&
      actions.every((a) => _serverActions.contains(a.type));

  bool matches(EmailModel email) {
    if (conditions.isEmpty) return false;
    return matchAll
        ? conditions.every((c) => c.matches(email))
        : conditions.any((c) => c.matches(email));
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'isEnabled': isEnabled,
    'conditions': conditions.map((c) => c.toMap()).toList(),
    'actions': actions.map((a) => a.toMap()).toList(),
    'stopProcessing': stopProcessing, 'priority': priority, 'matchAll': matchAll,
    'execution': execution.name,
    if (serverRuleId != null) 'serverRuleId': serverRuleId,
  };

  factory AutoRule.fromMap(Map<String, dynamic> m) => AutoRule(
    id: m['id'] ?? '',
    name: m['name'] ?? '',
    isEnabled: m['isEnabled'] ?? true,
    conditions: (m['conditions'] as List? ?? [])
        .map((c) => RuleCondition.fromMap(c as Map<String, dynamic>))
        .toList(),
    actions: (m['actions'] as List? ?? [])
        .map((a) => RuleAction.fromMap(a as Map<String, dynamic>))
        .toList(),
    stopProcessing: m['stopProcessing'] ?? false,
    priority: m['priority'] ?? 0,
    matchAll: m['matchAll'] ?? true,
    execution: (m['execution'] == 'server') ? RuleExecution.server : RuleExecution.client,
    serverRuleId: m['serverRuleId'] as String?,
  );
}

// ── Notifier ─────────────────────────────────────────────────────────────────

class AutoRulesNotifier extends StateNotifier<List<AutoRule>> {
  final SharedPreferences _prefs;
  static const _key = 'auto_rules';

  AutoRulesNotifier(this._prefs) : super([]) {
    _load();
  }

  void _load() {
    try {
      final raw = _prefs.getString(_key);
      if (raw == null) {
        // Первый запуск — заселяем набор правил по умолчанию.
        state = _defaultRules();
        _save();
        return;
      }
      final list = jsonDecode(raw) as List;
      state = list.map((m) => AutoRule.fromMap(m as Map<String, dynamic>)).toList();
    } catch (e) {
      AppLogger.warning('AutoRules load error: $e');
    }
  }

  /// Набор правил по умолчанию (безопасные: только теги/категории/флаг — без
  /// удаления и перемещения, чтобы не удивлять пользователя).
  static List<AutoRule> _defaultRules() => const [
    AutoRule(
      id: 'default_1c', name: 'Заявки 1С', priority: 0, matchAll: false,
      conditions: [
        RuleCondition(type: RuleConditionType.subjectContains, value: '1С'),
        RuleCondition(type: RuleConditionType.bodyContains, value: 'заявка'),
      ],
      actions: [RuleAction(type: RuleActionType.addTag, value: '1С')],
    ),
    AutoRule(
      id: 'default_finance', name: 'Финансы (счета и договоры)', priority: 1, matchAll: false,
      conditions: [
        RuleCondition(type: RuleConditionType.subjectContains, value: 'счёт'),
        RuleCondition(type: RuleConditionType.subjectContains, value: 'счет'),
        RuleCondition(type: RuleConditionType.subjectContains, value: 'договор'),
      ],
      actions: [RuleAction(type: RuleActionType.addTag, value: 'Финансы')],
    ),
    AutoRule(
      id: 'default_meetings', name: 'Совещания и встречи', priority: 2, matchAll: false,
      conditions: [
        RuleCondition(type: RuleConditionType.subjectContains, value: 'совещание'),
        RuleCondition(type: RuleConditionType.subjectContains, value: 'встреча'),
        RuleCondition(type: RuleConditionType.subjectContains, value: 'приглашение'),
      ],
      actions: [RuleAction(type: RuleActionType.addTag, value: 'Встречи')],
    ),
    AutoRule(
      id: 'default_newsletters', name: 'Рассылки', priority: 3, matchAll: false,
      conditions: [
        RuleCondition(type: RuleConditionType.bodyContains, value: 'отписаться'),
        RuleCondition(type: RuleConditionType.bodyContains, value: 'unsubscribe'),
        RuleCondition(type: RuleConditionType.subjectContains, value: 'рассылка'),
      ],
      actions: [RuleAction(type: RuleActionType.setCategory, value: 'Рассылки')],
    ),
    AutoRule(
      id: 'default_high_priority', name: 'Высокий приоритет → флаг', priority: 4,
      conditions: [RuleCondition(type: RuleConditionType.priorityHigh)],
      actions: [RuleAction(type: RuleActionType.markFlagged)],
    ),
  ];

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode(state.map((r) => r.toMap()).toList()));
  }

  void addRule(AutoRule rule) {
    state = [...state, rule];
    _save();
  }

  void updateRule(AutoRule rule) {
    state = state.map((r) => r.id == rule.id ? rule : r).toList();
    _save();
  }

  void toggleRule(String id) {
    state = state.map((r) => r.id == id ? r.copyWith(isEnabled: !r.isEnabled) : r).toList();
    _save();
  }

  void deleteRule(String id) {
    state = state.where((r) => r.id != id).toList();
    _save();
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    final item = list.removeAt(oldIndex);
    list.insert(newIndex < oldIndex ? newIndex : newIndex - 1, item);
    state = list;
    _save();
  }

  /// Экспорт всех правил в JSON-строку (для резервной копии / переноса).
  String exportJson() => jsonEncode(state.map((r) => r.toMap()).toList());

  /// Импорт правил из JSON. [replace] = true — заменить все правила,
  /// иначе — объединить (по id, импортируемые перекрывают существующие).
  /// Возвращает число импортированных правил; бросает FormatException при ошибке.
  Future<int> importJson(String json, {bool replace = true}) async {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      throw const FormatException('Ожидался JSON-массив правил');
    }
    final imported = decoded
        .map((m) => AutoRule.fromMap(m as Map<String, dynamic>))
        .toList();
    if (replace) {
      state = imported;
    } else {
      final byId = {for (final r in state) r.id: r};
      for (final r in imported) {
        byId[r.id] = r;
      }
      state = byId.values.toList();
    }
    await _save();
    return imported.length;
  }

  /// Сбросить правила к набору по умолчанию.
  Future<void> resetToDefaults() async {
    state = _defaultRules();
    await _save();
  }

  List<RuleAction> getMatchingActions(EmailModel email) {
    final result = <RuleAction>[];
    for (final rule in state) {
      if (!rule.isEnabled) continue;
      // Серверные правила выполняет сам Exchange — на клиенте их НЕ применяем,
      // иначе действие (перемещение и т.п.) сработало бы дважды.
      if (rule.execution == RuleExecution.server) continue;
      if (rule.matches(email)) {
        result.addAll(rule.actions);
        if (rule.stopProcessing) break;
      }
    }
    return result;
  }
}

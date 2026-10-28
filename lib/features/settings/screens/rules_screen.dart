// lib/features/settings/screens/rules_screen.dart
// Экран управления автоматическими правилами обработки писем.
// Список правил, вкл/выкл, создание, редактирование, удаление.
// Визуальный конструктор: ЕСЛИ [условие] → ТО [действие].

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/empty_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/rules/auto_rules_service.dart';
import '../../../services/mail/ews/ews_service.dart';
import '../../../services/mail/transport_capabilities.dart';
import '../../../features/mail/providers/mail_providers.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key, this.embedded = false, this.accountId});

  /// Аккаунт, для которого открыт экран (из экрана аккаунта); null — активный.
  final String? accountId;

  /// true — экран встроен во вкладку «Автоматизация» (без своего AppBar;
  /// действия показываются компактной строкой над списком).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rules = ref.watch(autoRulesProvider);

    final menu = PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'export') _exportRules(context, ref);
        if (v == 'import') _importRules(context, ref);
        if (v == 'reset') _resetRules(context, ref);
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'export', child: Text(l10n.tr('exportRules'))),
        PopupMenuItem(value: 'import', child: Text(l10n.tr('importRules'))),
        PopupMenuItem(value: 'reset', child: Text(l10n.tr('resetToDefaults'))),
      ],
    );

    final list = rules.isEmpty
        ? _buildEmptyState(theme, l10n)
        : ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: rules.length,
            onReorderItem: (oldIndex, newIndex) {
              HapticFeedback.mediumImpact();
              ref.read(autoRulesProvider.notifier).reorder(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final rule = rules[index];
              return _RuleTile(
                key: ValueKey(rule.id),
                rule: rule,
                onToggle: () {
                  ref.read(autoRulesProvider.notifier).toggleRule(rule.id);
                  HapticFeedback.selectionClick();
                },
                onEdit: () => _editRule(context, ref, rule),
                onDelete: () => _deleteRule(context, ref, rule),
              );
            },
          );

    return Scaffold(
      appBar: embedded
          ? null
          : AppBar(
              title: Text(l10n.tr('moduleRules')),
              actions: [
                IconButton(
                  tooltip: l10n.tr('rulesHelpTitle'),
                  icon: const Icon(AppIcons.help),
                  onPressed: () => _showHelp(context),
                ),
                menu,
              ],
            ),
      body: embedded
          ? Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                        tooltip: l10n.tr('rulesHelpTitle'),
                        icon: const Icon(AppIcons.help),
                        onPressed: () => _showHelp(context)),
                    menu,
                  ],
                ),
                Expanded(child: list),
              ],
            )
          : list,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_rules',
        onPressed: () => _createRule(context, ref),
        icon: const Icon(AppIcons.add),
        label: Text(l10n.tr('newRule')),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) =>
      EmptyState(icon: AppIcons.rule, title: l10n.tr('noRules'), message: l10n.tr('noRulesHint'));

  void _createRule(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RuleEditorScreen(
          serverRulesAvailable: _serverRulesAvailable(ref),
          onSave: (rule) async {
            final synced = await _syncServerRule(ref, rule);
            ref.read(autoRulesProvider.notifier).addRule(synced);
          },
        ),
      ),
    );
  }

  /// Доступны ли серверные правила для активного аккаунта (EWS с capability).
  bool _serverRulesAvailable(WidgetRef ref) {
    final acc = ref.read(accountOrActiveProvider(accountId));
    return acc != null && TransportCapabilities.forAccount(acc).serverRules;
  }

  /// Синхронизировать правило с сервером по его `execution`:
  ///  • server + совместимо + EWS-аккаунт → создать/обновить на сервере,
  ///    вернуть правило с проставленным `serverRuleId`;
  ///  • если правило перестало быть серверным, а на сервере копия была —
  ///    удалить её.
  /// При ошибке правило сохраняется как клиентское (деградация безопасна).
  Future<AutoRule> _syncServerRule(WidgetRef ref, AutoRule rule) async {
    final acc = ref.read(accountOrActiveProvider(accountId));
    final caps = acc == null ? null : TransportCapabilities.forAccount(acc);
    final ews = ref.read(ewsServiceProvider);

    // Правило клиентское (или сервер недоступен): снять серверную копию, если была.
    if (rule.execution != RuleExecution.server ||
        acc == null || caps == null || !caps.serverRules || !rule.isServerCompatible) {
      if (rule.serverRuleId != null && acc != null && caps != null && caps.serverRules) {
        await ews.deleteInboxRule(acc, rule.serverRuleId!);
      }
      return rule.execution == RuleExecution.server && !rule.isServerCompatible
          ? rule.copyWith(execution: RuleExecution.client, serverRuleId: null)
          : (rule.serverRuleId != null && rule.execution != RuleExecution.server
              ? rule.copyWith(serverRuleId: null)
              : rule);
    }

    // Серверное правило: создать или обновить.
    try {
      if (rule.serverRuleId == null) {
        final id = await ews.createInboxRule(acc, rule);
        return id == null ? rule : rule.copyWith(serverRuleId: id);
      } else {
        await ews.updateInboxRule(acc, rule);
        return rule;
      }
    } catch (_) {
      return rule; // клиентское применение продолжит работать
    }
  }

  void _editRule(BuildContext context, WidgetRef ref, AutoRule rule) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _RuleEditorScreen(
          existingRule: rule,
          serverRulesAvailable: _serverRulesAvailable(ref),
          onSave: (updated) async {
            final synced = await _syncServerRule(ref, updated);
            ref.read(autoRulesProvider.notifier).updateRule(synced);
          },
        ),
      ),
    );
  }

  void _deleteRule(BuildContext context, WidgetRef ref, AutoRule rule) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('deleteRuleQ')),
        content: Text('«${rule.name}» ${l10n.tr('ruleWillBeDeleted')}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.tr('cancel')),
          ),
          TextButton(
            onPressed: () async {
              // Если у правила есть серверная копия — снять её с сервера.
              if (rule.serverRuleId != null) {
                final acc = ref.read(accountOrActiveProvider(accountId));
                if (acc != null && TransportCapabilities.forAccount(acc).serverRules) {
                  await ref.read(ewsServiceProvider).deleteInboxRule(acc, rule.serverRuleId!);
                }
              }
              ref.read(autoRulesProvider.notifier).deleteRule(rule.id);
              if (ctx.mounted) Navigator.of(ctx).pop();
              unawaited(HapticFeedback.mediumImpact());
            },
            child: Text(l10n.tr('delete'),
                style: TextStyle(color: AppColors.errorText(context))),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('rulesHelpTitle')),
        content: SingleChildScrollView(
          child: Text(
            l10n.tr('rulesHelpBody'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.tr('gotIt')),
          ),
        ],
      ),
    );
  }

  void _exportRules(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final json = ref.read(autoRulesProvider.notifier).exportJson();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('exportRules')),
        content: SingleChildScrollView(
          child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close'))),
          FilledButton.icon(
            icon: const Icon(AppIcons.content_copy, size: 18),
            label: Text(l10n.tr('copy')),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              Navigator.pop(ctx);
              showInlineNotice(l10n.tr('rulesCopied'));
            },
          ),
        ],
      ),
    );
  }

  void _importRules(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final error = ValueNotifier<String?>(null);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('importRules')),
        content: ValueListenableBuilder<String?>(
          valueListenable: error,
          builder: (_, err, __) => TextField(
            controller: controller,
            maxLines: 8,
            onChanged: (_) => error.value = null,
            decoration: InputDecoration(
              hintText: l10n.tr('importRulesHint'),
              border: const OutlineInputBorder(),
              errorText: err,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () async {
              try {
                final n = await ref.read(autoRulesProvider.notifier).importJson(controller.text.trim());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                showInlineNotice('${l10n.tr('rulesImported')}: $n');
              } catch (_) {
                // Диалог остаётся открытым, ошибка — у поля.
                error.value = l10n.tr('invalidJson');
              }
            },
            child: Text(l10n.tr('import')),
          ),
        ],
      ),
    );
  }

  void _resetRules(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('resetRulesQ')),
        content: Text(l10n.tr('resetRulesConfirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(
            onPressed: () {
              ref.read(autoRulesProvider.notifier).resetToDefaults();
              Navigator.pop(ctx);
            },
            child: Text(l10n.tr('reset')),
          ),
        ],
      ),
    );
  }
}

/// Тайл правила в списке
class _RuleTile extends StatelessWidget {
  final AutoRule rule;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleTile({
    super.key,
    required this.rule,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
      child: ListTile(
        leading: Switch(
          value: rule.isEnabled,
          onChanged: (_) => onToggle(),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                rule.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: rule.isEnabled
                      ? null
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  decoration: rule.isEnabled ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (rule.execution == RuleExecution.server) ...[
              const SizedBox(width: 6),
              Icon(AppIcons.cloud_done,
                  size: 15, color: theme.colorScheme.primary),
            ],
          ],
        ),
        subtitle: Text(
          _buildDescription(l10n),
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (ctx) => [
            PopupMenuItem(value: 'edit', child: Text(l10n.tr('edit'))),
            PopupMenuItem(value: 'delete', child: Text(l10n.tr('delete'))),
          ],
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
        ),
        onTap: onEdit,
      ),
    );
  }

  String _buildDescription(AppLocalizations l10n) {
    final conditions = rule.conditions
        .map((c) => _conditionLabel(c.type, l10n))
        .join(rule.matchAll ? ' ${l10n.tr('andJoin')} ' : ' ${l10n.tr('orJoin')} ');
    final actions = rule.actions
        .map((a) => _actionLabel(a.type, l10n))
        .join(', ');
    return '${l10n.tr('ifWord')} $conditions → $actions';
  }

  String _conditionLabel(RuleConditionType type, AppLocalizations l10n) {
    switch (type) {
      case RuleConditionType.senderContains: return l10n.tr('condSenderContains');
      case RuleConditionType.senderEquals: return l10n.tr('condSenderEquals');
      case RuleConditionType.subjectContains: return l10n.tr('condSubjectContains');
      case RuleConditionType.bodyContains: return l10n.tr('condBodyContains');
      case RuleConditionType.hasAttachments: return l10n.tr('condHasAttachments');
      case RuleConditionType.priorityHigh: return l10n.tr('condPriorityHigh');
      case RuleConditionType.sizeGreaterThan: return l10n.tr('condSizeGreater');
      case RuleConditionType.recipientCount: return l10n.tr('condRecipientCount');
    }
  }

  String _actionLabel(RuleActionType type, AppLocalizations l10n) {
    switch (type) {
      case RuleActionType.moveTo: return l10n.tr('actMove');
      case RuleActionType.moveToFolder: return l10n.tr('actMove');
      case RuleActionType.addTag: return l10n.tr('actTag');
      case RuleActionType.markAsRead: return l10n.tr('actMarkRead');
      case RuleActionType.markFlagged: return l10n.tr('actFlag');
      case RuleActionType.delete: return l10n.tr('actDelete');
      case RuleActionType.autoReply: return l10n.tr('actAutoReply');
      case RuleActionType.notify: return l10n.tr('actNotify');
      case RuleActionType.setCategory: return l10n.tr('actCategory');
      case RuleActionType.forwardTo: return l10n.tr('actForward');
      case RuleActionType.forward: return l10n.tr('actForward');
      case RuleActionType.playSound: return l10n.tr('actSound');
    }
  }
}

/// Экран редактирования правила
class _RuleEditorScreen extends StatefulWidget {
  final AutoRule? existingRule;
  final bool serverRulesAvailable;
  final void Function(AutoRule rule) onSave;

  const _RuleEditorScreen({
    this.existingRule,
    this.serverRulesAvailable = false,
    required this.onSave,
  });

  @override
  State<_RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends State<_RuleEditorScreen> {
  late final TextEditingController _nameController;
  String? _nameError;
  // Подсказки у разделов вместо всплывающих сообщений (они отключены).
  bool _conditionsError = false;
  bool _actionsError = false;

  Widget _inlineError(String text) => Padding(
        padding: const EdgeInsets.only(left: Space.m, bottom: Space.s),
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
      );
  late bool _matchAll;
  late bool _stopProcessing;
  late bool _executeOnServer;
  late List<RuleCondition> _conditions;
  late List<RuleAction> _actions;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRule;
    _nameController = TextEditingController(text: r?.name ?? '');
    _matchAll = r?.matchAll ?? true;
    _stopProcessing = r?.stopProcessing ?? false;
    _executeOnServer = r?.execution == RuleExecution.server;
    _conditions = List.from(r?.conditions ?? []);
    _actions = List.from(r?.actions ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existingRule != null;

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(isEdit ? l10n.tr('editRule') : l10n.tr('newRule')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l10n.tr('save'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.all(Space.l),
        children: [
          // Название
          TextField(
            controller: _nameController,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            decoration: InputDecoration(
              labelText: l10n.tr('ruleName'),
              hintText: l10n.tr('ruleNameHint'),
              errorText: _nameError,
            ),
          ),

          // ── УСЛОВИЯ ── (полосой, как разделы настроек)
          SettingsSectionTitle(l10n.tr('ifWord')),
          Row(
            children: [
              const Spacer(),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, label: Text(l10n.tr('matchAll'))),
                  ButtonSegment(value: false, label: Text(l10n.tr('matchAny'))),
                ],
                selected: {_matchAll},
                onSelectionChanged: (v) =>
                    setState(() => _matchAll = v.first),
              ),
            ],
          ),
          const SizedBox(height: Space.s),

          ...List.generate(_conditions.length, (i) {
            return Card(
              child: ListTile(
                title: _buildConditionDropdown(i),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.tr('value'),
                      isDense: true,
                    ),
                    controller: TextEditingController(
                        text: _conditions[i].value),
                    onChanged: (v) {
                      _conditions[i] = RuleCondition(
                        type: _conditions[i].type,
                        value: v,
                      );
                    },
                  ),
                ),
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.remove_circle,
                      color: AppColors.errorRed),
                  onPressed: () =>
                      setState(() => _conditions.removeAt(i)),
                ),
              ),
            );
          }),

          TextButton.icon(
            onPressed: () {
              setState(() {
                _conditions.add(const RuleCondition(
                  type: RuleConditionType.senderContains,
                  value: '',
                ));
              });
            },
            icon: const Icon(AppIcons.add),
            label: Text(l10n.tr('addCondition')),
          ),
          if (_conditionsError && _conditions.isEmpty) _inlineError(l10n.tr('addAtLeastOneCondition')),


          // ── ДЕЙСТВИЯ ──
          SettingsSectionTitle(l10n.tr('thenWord')),

          ...List.generate(_actions.length, (i) {
            return Card(
              child: ListTile(
                title: _buildActionDropdown(i),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: l10n.tr('value'),
                      isDense: true,
                    ),
                    controller: TextEditingController(
                        text: _actions[i].value),
                    onChanged: (v) {
                      _actions[i] = RuleAction(
                        type: _actions[i].type,
                        value: v,
                      );
                    },
                  ),
                ),
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.remove_circle,
                      color: AppColors.errorRed),
                  onPressed: () =>
                      setState(() => _actions.removeAt(i)),
                ),
              ),
            );
          }),

          TextButton.icon(
            onPressed: () {
              setState(() {
                _actions.add(const RuleAction(
                  type: RuleActionType.addTag,
                  value: '',
                ));
              });
            },
            icon: const Icon(AppIcons.add),
            label: Text(l10n.tr('addAction')),
          ),
          if (_actionsError && _actions.isEmpty) _inlineError(l10n.tr('addAtLeastOneAction')),

          const SizedBox(height: Space.l),

          // Остановить обработку
          SwitchListTile(
            title: Text(l10n.tr('stopProcessing')),
            subtitle: Text(l10n.tr('stopProcessingDesc')),
            value: _stopProcessing,
            onChanged: (v) => setState(() => _stopProcessing = v),
          ),

          // ── Где выполнять: в приложении / на сервере ──
          // Доступно только для EWS-аккаунта и если все условия/действия
          // поддерживаются сервером (иначе правило обязано быть клиентским).
          Builder(builder: (context) {
            final compatible = AutoRule(
              id: 'probe', name: 'probe',
              conditions: _conditions, actions: _actions,
            ).isServerCompatible;
            final canServer = widget.serverRulesAvailable && compatible;
            if (!widget.serverRulesAvailable) {
              return const SizedBox.shrink();
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                SwitchListTile(
                  title: Text(l10n.tr('runOnServer')),
                  subtitle: Text(canServer
                      ? (l10n.tr('runOnServerDesc'))
                      : (l10n.tr('runOnServerUnavailable'))),
                  value: _executeOnServer && canServer,
                  onChanged: canServer
                      ? (v) => setState(() => _executeOnServer = v)
                      : null,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConditionDropdown(int index) {
    final l10n = AppLocalizations.of(context);
    return DropdownButton<RuleConditionType>(
      value: _conditions[index].type,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: RuleConditionType.values.map((type) {
        return DropdownMenuItem(
          value: type,
          child: Text(_conditionTypeLabel(type, l10n),
              style: Theme.of(context).textTheme.bodyMedium),
        );
      }).toList(),
      onChanged: (type) {
        if (type != null) {
          setState(() {
            _conditions[index] = RuleCondition(
              type: type,
              value: _conditions[index].value,
            );
          });
        }
      },
    );
  }

  Widget _buildActionDropdown(int index) {
    final l10n = AppLocalizations.of(context);
    return DropdownButton<RuleActionType>(
      value: _actions[index].type,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: RuleActionType.values.map((type) {
        return DropdownMenuItem(
          value: type,
          child: Text(_actionTypeLabel(type, l10n),
              style: Theme.of(context).textTheme.bodyMedium),
        );
      }).toList(),
      onChanged: (type) {
        if (type != null) {
          setState(() {
            _actions[index] = RuleAction(
              type: type,
              value: _actions[index].value,
            );
          });
        }
      },
    );
  }

  String _conditionTypeLabel(RuleConditionType type, AppLocalizations l10n) {
    switch (type) {
      case RuleConditionType.senderContains: return l10n.tr('condSenderContainsFull');
      case RuleConditionType.senderEquals: return l10n.tr('condSenderEqualsFull');
      case RuleConditionType.subjectContains: return l10n.tr('condSubjectContainsFull');
      case RuleConditionType.bodyContains: return l10n.tr('condBodyContainsFull');
      case RuleConditionType.hasAttachments: return l10n.tr('condHasAttachmentsFull');
      case RuleConditionType.priorityHigh: return l10n.tr('condPriorityHighFull');
      case RuleConditionType.sizeGreaterThan: return l10n.tr('condSizeGreaterFull');
      case RuleConditionType.recipientCount: return l10n.tr('condRecipientCountFull');
    }
  }

  String _actionTypeLabel(RuleActionType type, AppLocalizations l10n) {
    switch (type) {
      case RuleActionType.moveTo: return l10n.tr('actMoveToFolderFull');
      case RuleActionType.moveToFolder: return l10n.tr('actMoveToFolderFull');
      case RuleActionType.addTag: return l10n.tr('actAddTagFull');
      case RuleActionType.markAsRead: return l10n.tr('actMarkReadFull');
      case RuleActionType.markFlagged: return l10n.tr('actFlagFull');
      case RuleActionType.delete: return l10n.tr('delete');
      case RuleActionType.autoReply: return l10n.tr('actAutoReplyFull');
      case RuleActionType.notify: return l10n.tr('actNotifyFull');
      case RuleActionType.setCategory: return l10n.tr('actCategoryFull');
      case RuleActionType.forwardTo: return l10n.tr('actForwardToFull');
      case RuleActionType.forward: return l10n.tr('forward');
      case RuleActionType.playSound: return l10n.tr('actSoundFull');
    }
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = l10n.tr('enterRuleName'));
      return;
    }

    if (_conditions.isEmpty) {
      setState(() => _conditionsError = true);
      return;
    }

    if (_actions.isEmpty) {
      setState(() => _actionsError = true);
      return;
    }

    final rule = AutoRule(
      id: widget.existingRule?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      isEnabled: widget.existingRule?.isEnabled ?? true,
      conditions: _conditions,
      matchAll: _matchAll,
      actions: _actions,
      priority: widget.existingRule?.priority ?? 0,
      stopProcessing: _stopProcessing,
      execution: _executeOnServer ? RuleExecution.server : RuleExecution.client,
      serverRuleId: widget.existingRule?.serverRuleId,
    );

    widget.onSave(rule);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }
}

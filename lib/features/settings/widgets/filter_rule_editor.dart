// lib/features/settings/widgets/filter_rule_editor.dart
// Редактор правила фильтра на сервере (1.7.3): общий для Sieve (IMAP) и
// правил Exchange (EWS). Раньше был только у Sieve (sieve_rules_screen.dart);
// правила Exchange создавать было нельзя — только включать и выключать.
//
// Правило — SieveRule (поле, сравнение, значение, действие, папка или адрес,
// «остановить обработку»): у Exchange те же понятия. Какие действия есть —
// решает экран (у Exchange нет «Отметить флажком», у Sieve «переложить» и
// «прочитано» зависят от расширений сервера). Папки — список (id, подпись):
// путь Sieve или FolderId Exchange.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/sieve/sieve_rules.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;

/// Папка для «Переложить в папку»: [id] — то, что пишется в правило.
typedef FilterFolder = ({String id, String label});

/// Итог редактора: правило или «удалить».
class FilterRuleEditResult {
  final SieveRule? rule;
  final bool delete;
  const FilterRuleEditResult.save(SieveRule this.rule) : delete = false;
  const FilterRuleEditResult.remove()
      : rule = null,
        delete = true;
}

String filterActionLabel(SieveAction a, AppLocalizations l10n) => switch (a) {
      SieveAction.move => l10n.tr('sieveActMove'),
      SieveAction.markRead => l10n.tr('sieveActRead'),
      SieveAction.flag => l10n.tr('sieveActFlag'),
      SieveAction.delete => l10n.tr('sieveActDelete'),
      SieveAction.forward => l10n.tr('sieveActForward'),
    };

IconData filterActionIcon(SieveAction a) => switch (a) {
      SieveAction.move => AppIcons.drive_file_move,
      SieveAction.markRead => AppIcons.mark_email_read,
      SieveAction.flag => AppIcons.flag,
      SieveAction.delete => AppIcons.delete,
      SieveAction.forward => AppIcons.forward,
    };

String filterFieldLabel(SieveField f, AppLocalizations l10n) => switch (f) {
      SieveField.from => l10n.tr('sieveFieldFrom'),
      SieveField.to => l10n.tr('sieveFieldTo'),
      SieveField.subject => l10n.tr('sieveFieldSubject'),
      SieveField.any => l10n.tr('sieveFieldAny'),
    };

/// Открыть редактор. [canDelete] — показывать «Удалить правило» (только у
/// существующего). [subjectExact] — есть ли у темы «совпадает» (у Exchange
/// тема проверяется только на «содержит»).
Future<FilterRuleEditResult?> showFilterRuleEditor(
  BuildContext context, {
  SieveRule? initial,
  required List<FilterFolder> folders,
  required Set<SieveAction> actions,
  bool canDelete = true,
  bool subjectExact = true,
}) =>
    showAppSheet<FilterRuleEditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterRuleEditor(
        initial: initial,
        folders: folders,
        actions: actions,
        canDelete: canDelete && initial != null,
        subjectExact: subjectExact,
      ),
    );

class FilterRuleEditor extends StatefulWidget {
  final SieveRule? initial;
  final List<FilterFolder> folders;
  final Set<SieveAction> actions;
  final bool canDelete;
  final bool subjectExact;

  const FilterRuleEditor({
    super.key,
    this.initial,
    required this.folders,
    required this.actions,
    this.canDelete = false,
    this.subjectExact = true,
  });

  @override
  State<FilterRuleEditor> createState() => _FilterRuleEditorState();
}

class _FilterRuleEditorState extends State<FilterRuleEditor> {
  late SieveRule _r = widget.initial ??
      SieveRule(
        name: '',
        field: SieveField.from,
        value: '',
        action: widget.actions.contains(SieveAction.move) ? SieveAction.move : widget.actions.first,
      );
  late final _name = TextEditingController(text: _r.name);
  late final _value = TextEditingController(text: _r.value);
  late final _arg = TextEditingController(text: _r.action == SieveAction.forward ? _r.arg : '');
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _arg.dispose();
    super.dispose();
  }

  /// «Совпадает» — не у темы Exchange и не у «где угодно».
  bool get _exactAllowed =>
      _r.field != SieveField.any && (widget.subjectExact || _r.field != SieveField.subject);

  void _submit() {
    final r = _r.copyWith(
      name: _name.text.trim(),
      value: _value.text.trim(),
      op: _exactAllowed ? _r.op : SieveOp.contains,
      arg: _r.action == SieveAction.forward ? _arg.text.trim() : (_r.action == SieveAction.move ? _r.arg : ''),
    );
    if (!r.isValid) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(FilterRuleEditResult.save(r));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final folders = widget.folders;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.initial == null ? l10n.tr('sieveRuleNew') : l10n.tr('edit'),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.m),
            TextField(controller: _name, decoration: InputDecoration(labelText: l10n.tr('sieveRuleName'))),
            SettingsSectionTitle(l10n.tr('sieveIf')),
            DropdownButtonFormField<SieveField>(
              initialValue: _r.field,
              isExpanded: true,
              items: [
                for (final f in SieveField.values) DropdownMenuItem(value: f, child: Text(filterFieldLabel(f, l10n))),
              ],
              onChanged: (v) => setState(() => _r = _r.copyWith(field: v)),
            ),
            const SizedBox(height: Space.s),
            if (_exactAllowed)
              SegmentedButton<SieveOp>(
                segments: [
                  ButtonSegment(value: SieveOp.contains, label: Text(l10n.tr('sieveOpContains'))),
                  ButtonSegment(value: SieveOp.isExactly, label: Text(l10n.tr('sieveOpIs'))),
                ],
                selected: {_r.op},
                onSelectionChanged: (s) => setState(() => _r = _r.copyWith(op: s.first)),
              ),
            const SizedBox(height: Space.s),
            TextField(controller: _value, decoration: InputDecoration(labelText: l10n.tr('sieveValue'))),
            SettingsSectionTitle(l10n.tr('sieveThen')),
            DropdownButtonFormField<SieveAction>(
              initialValue: widget.actions.contains(_r.action) ? _r.action : null,
              isExpanded: true,
              items: [
                for (final a in SieveAction.values)
                  if (widget.actions.contains(a)) DropdownMenuItem(value: a, child: Text(filterActionLabel(a, l10n))),
              ],
              onChanged: (v) => setState(() => _r = _r.copyWith(action: v, arg: v == SieveAction.move ? _r.arg : '')),
            ),
            const SizedBox(height: Space.s),
            if (_r.action == SieveAction.move)
              DropdownButtonFormField<String>(
                initialValue: folders.any((f) => f.id == _r.arg) ? _r.arg : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.tr('sieveFolder')),
                items: [
                  for (final f in folders)
                    DropdownMenuItem(value: f.id, child: Text(f.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _r = _r.copyWith(arg: v ?? '')),
              ),
            if (_r.action == SieveAction.forward)
              TextField(
                controller: _arg,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: l10n.tr('sieveForwardTo')),
              ),
            if (_r.action == SieveAction.delete)
              Text(l10n.tr('sieveDeleteWarn'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.tr('sieveStop')),
              value: _r.stop || _r.action == SieveAction.delete,
              onChanged: _r.action == SieveAction.delete ? null : (v) => setState(() => _r = _r.copyWith(stop: v)),
            ),
            if (_invalid)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s),
                child: Text(l10n.tr('sieveInvalid'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            Row(children: [
              if (widget.canDelete)
                TextButton.icon(
                  icon: const Icon(AppIcons.delete),
                  label: Text(l10n.tr('sieveRuleDelete')),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: () => Navigator.of(context).pop(const FilterRuleEditResult.remove()),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.tr('cancel'))),
              const SizedBox(width: Space.s),
              FilledButton(onPressed: _submit, child: Text(l10n.tr('save'))),
            ]),
          ],
        ),
      ),
    );
  }
}

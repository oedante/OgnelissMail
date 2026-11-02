// lib/features/tasks/widgets/quick_task_sheet.dart
// Задача одной фразой (1.10.2, просьба владельца 02.11.2026: «Встреча одной
// фразой не подходит — лучше для задачи, потом открывать окно задачи с
// заполненными полями; встречи открывать как есть»).
//
// Поле и предпросмотр: название, срок, напоминание, важная, повтор
// (TaskQuickParser — тот же разбор, что у строки «Добавить» в задачах).
// «Далее» или Enter — карточка задачи (showTaskEditor) с заполненными
// полями: там можно поправить и сохранить. Сразу ничего не создаётся.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/task_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/app_sheet.dart';
import '../task_quick_parser.dart';
import 'task_editor_sheet.dart';

/// Открыть ввод задачи одной фразой. [day] — день, выбранный в календаре:
/// «в 15» встаёт на него. [due] — срок, если во фразе его нет (ячейка
/// времени в календаре); иначе — выбранный день или сегодня, чтобы задача
/// была видна в календаре, как раньше у «+».
Future<void> showQuickTaskSheet(BuildContext context, {DateTime? day, DateTime? due}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: QuickTaskPanel(
        day: day,
        due: due,
        onNext: (draft) {
          Navigator.of(ctx).pop();
          showTaskEditor(context, draft: draft);
        },
      ),
    ),
  );
}

class QuickTaskPanel extends StatefulWidget {
  final DateTime? day;

  /// Срок, если во фразе его нет (null — [day] или сегодня).
  final DateTime? due;

  /// Разобранная фраза — дальше, в карточку задачи.
  final void Function(ParsedTask draft) onNext;

  const QuickTaskPanel({super.key, this.day, this.due, required this.onNext});

  @override
  State<QuickTaskPanel> createState() => _QuickTaskPanelState();
}

class _QuickTaskPanelState extends State<QuickTaskPanel> {
  final _ctrl = TextEditingController();
  ParsedTask? _parsed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Опорный момент: выбранный день (не сегодня) — его начало, чтобы
  /// «в 15» встало на него.
  DateTime get _now {
    final now = DateTime.now();
    final d = widget.day;
    if (d == null || (d.year == now.year && d.month == now.month && d.day == now.day)) return now;
    return DateTime(d.year, d.month, d.day);
  }

  /// Срок по умолчанию, если во фразе его нет: выбранный день или сегодня.
  DateTime get _defaultDue {
    if (widget.due != null) return widget.due!;
    final d = widget.day ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }

  ParsedTask _draft() {
    final p = _ctrl.text.trim().isEmpty ? const ParsedTask(title: '') : TaskQuickParser.parse(_ctrl.text, now: _now);
    return p.due != null
        ? p
        : ParsedTask(
            title: p.title,
            due: _defaultDue,
            reminder: p.reminder,
            important: p.important,
            repeat: p.repeat,
          );
  }

  void _next() => widget.onNext(_draft());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final locale = l10n.localeCode;
    String fmt(DateTime d) => (d.hour == 0 && d.minute == 0)
        ? DateFormat('EEE, d MMM', locale).format(d)
        : DateFormat('EEE, d MMM, HH:mm', locale).format(d);
    final p = _parsed == null ? null : _draft();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tr('quickTaskTitle'), style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.s),
            TextField(
              key: const ValueKey('quickTaskField'),
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(hintText: l10n.tr('quickTaskHint')),
              onChanged: (v) => setState(() => _parsed = v.trim().isEmpty ? null : TaskQuickParser.parse(v, now: _now)),
              onSubmitted: (_) => _next(),
            ),
            const SizedBox(height: Space.m),
            // Предпросмотр: что будет в карточке задачи.
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: p == null
                  ? const SizedBox(width: double.infinity)
                  : Card(
                      key: const ValueKey('quickTaskPreview'),
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(AppIcons.task_alt, color: theme.colorScheme.primary),
                        title: Text(
                          p.title.isEmpty ? l10n.tr('newTask') : p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: p.title.isEmpty ? TextStyle(color: muted) : null,
                        ),
                        subtitle: Wrap(
                          spacing: Space.m,
                          runSpacing: Space.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (p.due != null) _Fact(icon: AppIcons.event, text: fmt(p.due!)),
                            if (p.reminder != null && p.reminder != p.due)
                              _Fact(icon: AppIcons.notifications, text: fmt(p.reminder!)),
                            if (p.important)
                              const Icon(AppIcons.star, size: 16, fill: 1, color: AppColors.brandAmber),
                            if (p.repeat != TaskRepeat.none) Icon(AppIcons.repeat, size: 16, color: muted),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: Space.m),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _next, child: Text(l10n.tr('next'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Fact({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.mutedText(context)),
          const SizedBox(width: Space.xs),
          Text(text),
        ],
      );
}

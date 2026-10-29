// lib/features/tasks/widgets/task_editor_sheet.dart
// Карточка задачи (напоминания): название, срок, напоминание, повтор,
// важность, подзадачи, заметки, теги, ящик, связанное письмо. Одна форма и
// для новой задачи, и для правки — как в Microsoft To Do. Раньше задачу
// можно было править только через меню долгого нажатия, по пункту за раз,
// а напоминания отдельно от срока не было вовсе.

import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/app_menu_button.dart';
import '../../../widgets/ui/wheel_pickers.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsGroup, SettingsSectionTitle;
import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart' show mailDetailPath;
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/task_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/tasks/task_actions_service.dart';
import '../../calendar/calendar_data.dart' show calendarScopeProvider, capitalize;
import '../task_contact_match.dart';
import '../task_quick_parser.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/tasks_screen.dart' show taskUndoBars;
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

/// Задача из письма: карточка задачи с названием из темы (без «Re:»,
/// «Fwd:»), сроком из темы («обновить до 17:00 10.10.2026» → 10.10, 17:00)
/// и ссылкой на письмо. Общая для письма, списка и бесед: в списке (долгое
/// нажатие, свайп) задача раньше создавалась молча — казалось, что кнопка не
/// работает (замечание 27.10.2026).
Future<void> showTaskEditorForEmail(BuildContext context, EmailModel email) {
  final l10n = AppLocalizations.of(context);
  final subject = email.subject
      .replaceFirst(RegExp(r'^\s*((re|fw|fwd|ответ|пересл)\s*:\s*)+', caseSensitive: false), '')
      .trim();
  final parsed = TaskQuickParser.parse(subject);
  return showTaskEditor(
    context,
    draft: ParsedTask(
      title: subject.isEmpty ? l10n.tr('noSubject') : subject,
      due: parsed.due,
      reminder: parsed.reminder,
    ),
    accountId: email.accountId,
    fromEmail: email,
  );
}

/// Открыть карточку задачи. [task] — правка; иначе новая (с черновиком из
/// быстрого ввода [draft]).
Future<void> showTaskEditor(
  BuildContext context, {
  TaskModel? task,
  ParsedTask? draft,
  String? accountId,
  EmailModel? fromEmail,
}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        // Почти на весь экран: кнопки и поля не уходят за край
        // (замечание 11.10.2026).
        initialChildSize: 0.92,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => TaskEditor(
          task: task,
          draft: draft,
          accountId: accountId,
          fromEmail: fromEmail,
          scrollController: scroll,
        ),
      ),
    ),
  );
}

class TaskEditor extends ConsumerStatefulWidget {
  final TaskModel? task;
  final ParsedTask? draft;
  final String? accountId;
  /// Новая задача из письма: ссылка на письмо и текст-описание.
  final EmailModel? fromEmail;
  final ScrollController? scrollController;
  /// Встроенный режим (правая панель на планшете): вызывается вместо
  /// закрытия листа после сохранения, удаления или перехода к письму.
  final VoidCallback? onDone;
  const TaskEditor({super.key, this.task, this.draft, this.accountId, this.fromEmail, this.scrollController, this.onDone});

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  final _subCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  DateTime? _due;
  DateTime? _reminder;
  int _repeat = TaskRepeat.none;
  bool _important = false;
  TaskPriority _priority = TaskPriority.normal;
  List<SubTask> _subs = [];
  List<String> _tags = [];
  String? _accountId;
  bool _done = false;
  bool _saving = false;
  ContactModel? _mention;
  Timer? _mentionTimer;

  bool get _isNew => widget.task == null;

  void _close() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    final d = widget.draft;
    _title = TextEditingController(text: t?.title ?? d?.title ?? '');
    _notes = TextEditingController(
        text: t?.description ??
            (widget.fromEmail == null
                ? ''
                : '${widget.fromEmail!.from.label}: ${widget.fromEmail!.subject}'));
    _due = t?.dueDate?.toLocal() ?? d?.due;
    _reminder = t?.reminderAt?.toLocal() ?? d?.reminder;
    _repeat = t?.repeatDays ?? d?.repeat ?? TaskRepeat.none;
    _important = t?.isFlagged ?? d?.important ?? false;
    _priority = t?.priority ?? TaskPriority.normal;
    _subs = [...?t?.subtasks];
    _tags = [...?t?.tags];
    _accountId = t?.accountId ?? widget.accountId;
    _done = t?.isDone ?? false;
    _title.addListener(_scheduleMention);
    _findMention();
  }

  /// Человек из названия («позвонить Смирнову Андрею») — кнопки связи.
  void _scheduleMention() {
    _mentionTimer?.cancel();
    _mentionTimer = Timer(const Duration(milliseconds: 400), _findMention);
  }

  Future<void> _findMention() async {
    final title = _title.text;
    try {
      final c = await findMentionedContact(ref.read(databaseProvider), title);
      if (mounted && title == _title.text) setState(() => _mention = c);
    } catch (_) {}
  }

  @override
  void dispose() {
    _mentionTimer?.cancel();
    _title.dispose();
    _notes.dispose();
    _subCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // ── Сохранение ──
  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    final actions = ref.read(taskActionsProvider);
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    try {
      if (_isNew) {
        final accountId = _accountId ?? ref.read(calendarScopeProvider).firstOrNull?.id;
        if (accountId == null) return;
        final id = await actions.create(
          accountId: accountId,
          title: title,
          description: notes,
          dueDate: _due,
          reminderAt: _reminder,
          repeat: _repeat,
          important: _important,
          priority: _priority,
        );
        final mail = widget.fromEmail;
        if (mail != null) {
          await actions.update(accountId, id, TasksCompanion(
            linkedEmailId: Value(mail.id),
            linkedEmailSubject: Value(mail.subject),
          ));
        }
        if (_subs.isNotEmpty || _tags.isNotEmpty) {
          await actions.update(accountId, id, TasksCompanion(
            subtasksJson: Value(_subs.isEmpty ? null : encodeSubtasks(_subs)),
            tagsStr: Value(_tags.isEmpty ? null : _tags.join(';')),
          ));
        }
      } else {
        final t = widget.task!;
        await actions.update(t.accountId, t.id, TasksCompanion(
          title: Value(title),
          description: Value(notes),
          dueDate: Value(_due),
          reminderAt: Value(_reminder),
          isRecurring: Value(_repeat != TaskRepeat.none),
          recurrenceDays: Value(_repeat == TaskRepeat.none ? null : _repeat),
          isFlagged: Value(_important),
          priority: Value(_priority.index),
          subtasksJson: Value(_subs.isEmpty ? null : encodeSubtasks(_subs)),
          tagsStr: Value(_tags.isEmpty ? null : _tags.join(';')),
        ));
        if (_done != t.isDone) await actions.setDone(t.accountId, t.id, _done);
      }
      unawaited(HapticFeedback.lightImpact());
      if (mounted) _close();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final t = widget.task;
    if (t == null) return;
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(taskActionsProvider);
    _close();
    final row = await actions.delete(t.accountId, t.id);
    if (row == null || !taskUndoBars) return;
    showInlineNotice(l10n.tr('taskDeleted'), actionLabel: l10n.tr('undo'), onAction: () => actions.restore(row));
  }

  // ── Выбор даты и времени ──
  Future<DateTime?> _pickDateTime({required DateTime initial, bool withTime = true}) async {
    final now = DateTime.now();
    // Барабаны: дата и время в одной шторке, с днём недели (10.10.2026).
    if (!withTime) {
      return showWheelDatePicker(context,
          initial: initial, first: DateTime(now.year - 2), last: DateTime(now.year + 10));
    }
    return showWheelDateTimePicker(context,
        initial: initial, first: DateTime(now.year - 2), last: DateTime(now.year + 10));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scope = ref.watch(calendarScopeProvider);
    final locale = l10n.localeCode;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    String dateLabel(DateTime d, {bool time = true}) {
      final day = DateTime(d.year, d.month, d.day);
      final hasTime = time && (d.hour != 0 || d.minute != 0);
      final t = hasTime ? ', ${DateFormat('HH:mm').format(d)}' : '';
      if (day == today) return '${l10n.tr('today')}$t';
      if (day == today.add(const Duration(days: 1))) return '${l10n.tr('tomorrow')}$t';
      return '${capitalize(DateFormat(d.year == now.year ? 'EEE, d MMM' : 'd MMM yyyy', locale).format(d))}$t';
    }

    // Кнопки «Сохранить»/«Удалить» — закреплены внизу шторки, над
    // клавиатурой: в конце длинного списка они уходили за край экрана.
    final actionsBar = Row(
      children: [
        if (!_isNew)
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(AppIcons.delete, color: theme.colorScheme.error),
            label: Text(l10n.delete, style: TextStyle(color: theme.colorScheme.error)),
          ),
        const Spacer(),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isNew ? l10n.tr('add') : l10n.tr('save')),
        ),
      ],
    );

    // Карточка задачи — строками в белых карточках по разделам, как
    // настройки и правка контакта (1.7.2+110, замечание владельца
    // 24.10.2026: «экраны создать встречу и задачу сильно отличаются —
    // сплошные серые»).
    return Column(children: [
      Expanded(child: ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.l),
      children: [
        // Название + выполнено + важная
        SettingsGroup(dividerIndent: Space.l, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isNew)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _RoundCheck(
                      value: _done,
                      color: theme.colorScheme.primary,
                      onChanged: () => setState(() => _done = !_done),
                    ),
                  ),
                if (!_isNew) const SizedBox(width: Space.m),
                Expanded(
                  child: TextField(
                    controller: _title,
                    autofocus: _isNew && (widget.draft == null || widget.draft!.title.isEmpty),
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: null,
                    style: theme.textTheme.titleLarge?.copyWith(
                      decoration: _done ? TextDecoration.lineThrough : null,
                    ),
                    decoration: InputDecoration(
                      hintText: l10n.tr('taskTitleHint'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.tr('important'),
                  icon: Icon(AppIcons.star, fill: _important ? 1 : 0,
                      color: _important ? AppColors.brandAmber : theme.hintColor),
                  onPressed: () => setState(() => _important = !_important),
                ),
              ],
            ),
          ),
          if (_mention != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, 0),
              child: _MentionRow(contact: _mention!),
            ),
        ]),

        // Разделы (1.6.2, замечание 13.10.2026: «непонятно, что за что
        // отвечает»): когда — срок, напоминание, повтор; важность; подзадачи;
        // дополнительно — заметки и теги.
        SettingsSectionTitle(l10n.tr('eventWhen')),
        SettingsGroup(children: [
          // Срок
          _Field(
            icon: AppIcons.event,
            label: _due == null ? l10n.tr('addDueDate') : '${l10n.tr('dueDate')}: ${dateLabel(_due!)}',
            active: _due != null,
            danger: _due != null && _due!.isBefore(_due!.hour == 0 && _due!.minute == 0 ? today : now) && !_done,
            onClear: _due == null ? null : () => setState(() => _due = null),
            onTap: () async {
              final d = await _pickDateTime(initial: _due ?? today, withTime: true);
              if (d != null) setState(() => _due = d);
            },
            chips: _due != null
                ? null
                : [
                    _Chip(l10n.tr('today'), () => setState(() => _due = today)),
                    _Chip(l10n.tr('tomorrow'), () => setState(() => _due = today.add(const Duration(days: 1)))),
                    _Chip(l10n.tr('nextWeek'), () {
                      // Следующий понедельник.
                      final add = (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7;
                      setState(() => _due = today.add(Duration(days: add)));
                    }),
                  ],
          ),

          // Напоминание
          _Field(
            icon: AppIcons.notifications,
            label: _reminder == null ? l10n.tr('remindMe') : '${l10n.tr('reminder')}: ${dateLabel(_reminder!)}',
            active: _reminder != null,
            danger: _reminder != null && _reminder!.isBefore(now) && !_done,
            onClear: _reminder == null ? null : () => setState(() => _reminder = null),
            onTap: () async {
              final base = _reminder ??
                  (_due != null && (_due!.hour != 0 || _due!.minute != 0)
                      ? _due!
                      : DateTime(now.year, now.month, now.day, now.hour + 1));
              final d = await _pickDateTime(initial: base);
              if (d != null) setState(() => _reminder = d);
            },
            // Есть срок — варианты от срока («в срок», «за час», «за день»):
            // раньше напоминания считались от текущего времени (замечание
            // 11.10.2026). Прошедшие варианты не показываются.
            chips: _reminder != null
                ? null
                : _due != null
                    ? _dueReminderChips(l10n, now)
                    : [
                        _Chip(l10n.tr('inOneHour'), () => setState(() => _reminder =
                            DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(hours: 1)))),
                        if (now.hour < 18)
                          _Chip(l10n.tr('thisEvening'), () => setState(() => _reminder = DateTime(now.year, now.month, now.day, 18))),
                        _Chip(l10n.tr('tomorrowMorning'), () => setState(() => _reminder = DateTime(now.year, now.month, now.day + 1, 9))),
                      ],
          ),

          // Повтор
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                icon: AppIcons.repeat,
                label: _repeat == TaskRepeat.none ? l10n.tr('repeat') : _repeatLabel(_repeat, l10n),
                active: _repeat != TaskRepeat.none,
                onClear: _repeat == TaskRepeat.none ? null : () => setState(() => _repeat = TaskRepeat.none),
                onTap: () async {
                  // Карточкой (1.8.8), как меню «⋮».
                  final v = await showChoiceSheet<int>(
                    context,
                    title: l10n.tr('repeat'),
                    selected: _repeat,
                    entries: [
                      for (final r in [TaskRepeat.none, ...TaskRepeat.all])
                        AppMenuEntry(value: r, label: r == TaskRepeat.none ? l10n.tr('none') : _repeatLabel(r, l10n)),
                    ],
                  );
                  if (v != null) setState(() => _repeat = v);
                },
              ),
              if (_repeat != TaskRepeat.none && _due == null && _reminder == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(_Field.textLeft, 0, Space.l, Space.s),
                  child: Text(l10n.tr('repeatNeedsDate'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ]),

        // Приоритет — с подписью: одна иконка у переключателя не
        // объясняла, что он меняет.
        SettingsSectionTitle(l10n.tr('priority')),
        SettingsGroup(children: [
          Padding(
            padding: const EdgeInsets.all(Space.m),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<TaskPriority>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: TaskPriority.low, label: Text(l10n.tr('priorityLow'))),
                  ButtonSegment(value: TaskPriority.normal, label: Text(l10n.tr('priorityNormal'))),
                  ButtonSegment(value: TaskPriority.high, label: Text(l10n.tr('priorityHigh'))),
                ],
                selected: {_priority == TaskPriority.urgent ? TaskPriority.high : _priority},
                onSelectionChanged: (s) => setState(() => _priority = s.first),
              ),
            ),
          ),
        ]),

        // Ящик (для новой задачи, если ящиков несколько)
        if (_isNew && scope.length > 1) ...[
          SettingsSectionTitle(l10n.tr('qcAccount')),
          SettingsGroup(children: [
            _AccountPicker(
              accounts: scope,
              selected: _accountId ?? scope.first.id,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          ]),
        ],

        // Подзадачи
        SettingsSectionTitle(l10n.tr('subtasks')),
        SettingsGroup(children: [
          if (_subs.isNotEmpty)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              // onReorderItem уже учитывает сдвиг индекса после удаления.
              onReorderItem: (a, b) => setState(() {
                final s = _subs.removeAt(a);
                _subs.insert(b, s);
              }),
              children: [
                for (var i = 0; i < _subs.length; i++)
                  ListTile(
                    key: ValueKey('sub_$i${_subs[i].title}'),
                    contentPadding: const EdgeInsets.only(left: Space.l, right: Space.s),
                    dense: true,
                    leading: _RoundCheck(
                      value: _subs[i].done,
                      size: 20,
                      color: theme.colorScheme.primary,
                      onChanged: () => setState(() => _subs[i] = _subs[i].copyWith(done: !_subs[i].done)),
                    ),
                    title: Text(_subs[i].title,
                        style: _subs[i].done
                            ? TextStyle(decoration: TextDecoration.lineThrough, color: theme.hintColor)
                            : null),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: l10n.tr('delete'),
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () => setState(() => _subs.removeAt(i)),
                        ),
                        ReorderableDragStartListener(index: i, child: const Icon(AppIcons.drag_indicator, size: 18)),
                      ],
                    ),
                  ),
              ],
            ),
          // «Добавить» — кнопкой справа (раньше только клавишей Enter).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _subCtrl,
              builder: (_, v, __) => TextField(
                controller: _subCtrl,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  prefixIcon: const Icon(AppIcons.add),
                  hintText: l10n.tr('newSubtask'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  suffixIcon: v.text.trim().isEmpty
                      ? null
                      : TextButton(onPressed: _addSubtask, child: Text(l10n.tr('add'))),
                ),
                onSubmitted: (_) => _addSubtask(),
              ),
            ),
          ),
        ]),

        SettingsSectionTitle(l10n.tr('eventMore')),
        SettingsGroup(children: [
          // Заметки
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs),
            child: TextField(
              controller: _notes,
              maxLines: null,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                prefixIcon: const Icon(AppIcons.notes),
                hintText: l10n.tr('taskNotesHint'),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),

          // Теги
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(AppIcons.label, color: theme.hintColor),
                const SizedBox(width: Space.s),
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _tagCtrl,
                    decoration: InputDecoration(
                      hintText: l10n.tr('addTag'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isEmpty || _tags.contains(t)) return;
                      setState(() {
                        _tags.add(t);
                        _tagCtrl.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Связанное письмо
          if (widget.task?.linkedEmailId != null)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              leading: const Icon(AppIcons.mail),
              title: Text(widget.task!.linkedEmailSubject ?? l10n.tr('openEmail'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(l10n.tr('openEmail')),
              onTap: () {
                final router = GoRouter.of(context);
                _close();
                router.push(mailDetailPath(widget.task!.linkedEmailId!, accountId: widget.task!.accountId));
              },
            ),
        ]),

        if (!_isNew)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
            child: Text(
              l10n.tr('taskCreatedOn').replaceAll(
                  '{date}', DateFormat('d MMMM yyyy', locale).format(widget.task!.createdAt.toLocal())),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),

      ],
      )),
      Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
            child: actionsBar,
          ),
        ),
      ),
    ]);
  }

  /// Напоминания от срока задачи.
  List<_Chip> _dueReminderChips(AppLocalizations l10n, DateTime now) {
    final due = _due!;
    final hasTime = due.hour != 0 || due.minute != 0;
    final options = <(String, DateTime)>[
      if (hasTime) (l10n.tr('atDueTime'), due),
      if (hasTime) (l10n.tr('remindHourBefore'), due.subtract(const Duration(hours: 1))),
      if (!hasTime) (l10n.tr('remindDueMorning'), DateTime(due.year, due.month, due.day, 9)),
      (l10n.tr('remindDayBefore'),
          hasTime ? due.subtract(const Duration(days: 1)) : DateTime(due.year, due.month, due.day - 1, 9)),
    ];
    return [
      for (final (label, at) in options)
        if (at.isAfter(now)) _Chip(label, () => setState(() => _reminder = at)),
    ];
  }

  void _addSubtask() {
    final t = _subCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _subs.add(SubTask(title: t));
      _subCtrl.clear();
    });
  }

  static String _repeatLabel(int r, AppLocalizations l10n) => switch (r) {
        TaskRepeat.daily => l10n.tr('recurDaily'),
        TaskRepeat.weekdays => l10n.tr('recurWeekdays'),
        TaskRepeat.weekly => l10n.tr('recurWeekly'),
        TaskRepeat.biweekly => l10n.tr('recurBiweekly'),
        TaskRepeat.monthly => l10n.tr('recurMonthly'),
        TaskRepeat.yearly => l10n.tr('recurYearly'),
        _ => l10n.tr('repeat'),
      };
}

/// Строка поля: значок, подпись (нажатие — выбор), крестик, быстрые варианты.
class _Field extends StatelessWidget {
  /// Начало текста строки в карточке: поле 16 · значок 24 · 16.
  static const textLeft = Space.l + Sizes.icon + Space.l;

  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final List<_Chip>? chips;
  const _Field({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.onClear,
    this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger
        ? theme.colorScheme.error
        : active
            ? theme.colorScheme.primary
            : theme.hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(Space.l, 10, onClear == null ? Space.l : Space.xs, 10),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: active || danger ? color : null,
                      fontWeight: active ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: AppLocalizations.of(context).tr('clear'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(AppIcons.close, size: 18),
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ),
        if (chips != null && chips!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(textLeft, 0, Space.l, Space.s),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final c in chips!)
                  ActionChip(
                    label: Text(c.label),
                    visualDensity: VisualDensity.compact,
                    onPressed: c.onTap,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Chip {
  final String label;
  final VoidCallback onTap;
  const _Chip(this.label, this.onTap);
}

/// Круглая отметка «выполнено» (как в Microsoft To Do / Google Tasks).
class _RoundCheck extends StatelessWidget {
  final bool value;
  final VoidCallback onChanged;
  final Color color;
  final double size;
  const _RoundCheck({required this.value, required this.onChanged, required this.color, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged();
      },
      radius: size,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: value ? color : Colors.transparent,
          border: Border.all(color: value ? color : Theme.of(context).hintColor, width: 2),
        ),
        child: value ? Icon(AppIcons.check, size: size * 0.7, color: Colors.white) : null,
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  final List<AccountModel> accounts;
  final String selected;
  final ValueChanged<String> onChanged;
  const _AccountPicker({required this.accounts, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
      child: Row(
        children: [
          Icon(AppIcons.inbox, color: theme.hintColor),
          const SizedBox(width: Space.l),
          Expanded(
            // Меню-карточка (1.8.8) вместо списка Material.
            child: AppSelectField<String>(
              value: accounts.any((a) => a.id == selected) ? selected : accounts.first.id,
              entries: [
                for (final a in accounts)
                  AppMenuEntry(value: a.id, label: a.email, icon: AppIcons.mail, iconColor: Color(a.colorValue)),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Публичная круглая отметка для списка задач.
class TaskRoundCheck extends StatelessWidget {
  final bool value;
  final VoidCallback onChanged;
  final Color color;
  const TaskRoundCheck({super.key, required this.value, required this.onChanged, required this.color});

  @override
  Widget build(BuildContext context) => _RoundCheck(value: value, onChanged: onChanged, color: color);
}


/// Упомянутый в задаче человек: имя, должность, «Позвонить», «Написать».
class _MentionRow extends StatelessWidget {
  final ContactModel contact;
  const _MentionRow({required this.contact});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final phone = (contact.phoneMobile ?? '').isNotEmpty ? contact.phoneMobile : contact.phoneWork;
    final name = contact.fullName.isNotEmpty ? contact.fullName : contact.displayName;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Row(children: [
        Icon(AppIcons.person, size: Sizes.iconInline, color: theme.colorScheme.primary),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            if ((contact.jobTitle ?? '').isNotEmpty || (phone ?? '').isNotEmpty)
              Text(
                [if ((contact.jobTitle ?? '').isNotEmpty) contact.jobTitle!, if ((phone ?? '').isNotEmpty) phone!].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
              ),
          ]),
        ),
        if ((phone ?? '').isNotEmpty)
          IconButton(
            tooltip: l10n.tr('call'),
            icon: const Icon(AppIcons.phone),
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone!.replaceAll(RegExp(r'[^0-9+,;]'), ''))),
          ),
        if (contact.email.isNotEmpty)
          IconButton(
            tooltip: l10n.tr('writeEmail'),
            icon: const Icon(AppIcons.mail),
            onPressed: () => context.push(Uri(path: '/compose', queryParameters: {'to': contact.email}).toString()),
          ),
      ]),
    );
  }
}

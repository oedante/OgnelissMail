// lib/features/assignments/project_editor.dart
// «Проект с этапами» (просьба владельца 12.11.2026): общая задача из этапов,
// как в Jira, Bitrix24 и MS Project. У этапа — исполнитель и соисполнители,
// контролирующий (принимает работу; по умолчанию — общий для проекта, без
// него — постановщик), наблюдатели, начало и срок, порядок («параллельно»
// или «после этапа N»), чек-лист и файлы. У проекта — описание, файлы
// (уходят всем участникам), наблюдатели. Проект можно сохранить шаблоном и
// создать из шаблона (сроки — от нового начала).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/platform/file_pick.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/text_safe.dart' show initialOf;
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/assignments/assignment_store.dart' show AssignmentFile, nextStageDates;
import '../../widgets/common/app_sheet.dart';
import '../../widgets/common/hero_email_transition.dart';
import '../../widgets/common/readable_width.dart';
import '../../widgets/ui/wheel_pickers.dart';
import '../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider;
import 'assignment_widgets.dart' show AssignmentAccountField, assignmentColumnWidth;

/// Открыть «Новый проект». true — проект создан.
Future<bool> showProjectEditor(BuildContext context, {String? accountId, String? title, String? description}) async {
  final ok = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
        builder: (_) => ProjectEditorScreen(accountId: accountId, title: title, description: description),
        fullscreenDialog: true),
  );
  return ok ?? false;
}

/// Выбрать файлы для поручения: у файла без пути (Android, content://) —
/// копия во временной папке.
Future<List<AssignmentFile>> pickAssignmentFiles() async {
  final out = <AssignmentFile>[];
  for (final f in await FilePick.files()) {
    var path = f.path;
    if (path == null) {
      final bytes = await f.readBytes();
      final dir = Directory('${(await getTemporaryDirectory()).path}/assignment_pick');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_${f.name}');
      await file.writeAsBytes(bytes, flush: true);
      path = file.path;
    }
    out.add(AssignmentFile(name: f.name, size: f.size, path: path));
  }
  return out;
}

String _size(int b) {
  if (b <= 0) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Человек — чипом с портретом.
Widget personChip(EmailAddress a, {VoidCallback? onDeleted, VoidCallback? onPressed}) {
  final avatar = HeroEmailAvatar(
    emailId: 'proj_${a.email}',
    initial: initialOf(a.label),
    color: HeroEmailAvatar.colorForEmail(a.email),
    radius: 12,
    hero: false,
    email: a.email,
  );
  if (onDeleted != null) return InputChip(avatar: avatar, label: Text(a.label), onDeleted: onDeleted);
  return ActionChip(avatar: avatar, label: Text(a.label), onPressed: onPressed);
}

class ProjectEditorScreen extends ConsumerStatefulWidget {
  final String? accountId;

  /// Начальные название и описание (переход из «Поручить»).
  final String? title;
  final String? description;
  const ProjectEditorScreen({super.key, this.accountId, this.title, this.description});

  @override
  ConsumerState<ProjectEditorScreen> createState() => _ProjectEditorScreenState();
}

class _ProjectEditorScreenState extends ConsumerState<ProjectEditorScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  ProjectDraft _d = ProjectDraft(start: _today());
  bool _sending = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Ящик, выбранный вручную (несколько ящиков).
  String? _accountId;

  AccountModel? get _account {
    final accounts = ref.read(accountsProvider);
    final id = _accountId ?? widget.accountId ?? ref.read(activeAccountProvider)?.id;
    return accounts.where((a) => a.id == id).firstOrNull ?? accounts.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _title.text = widget.title ?? '';
    _desc.text = widget.description ?? '';
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<List<EmailAddress>> _pick({Set<String> exclude = const {}}) async {
    final picked = await showPeoplePicker(context, account: _account, exclude: exclude);
    return [
      for (final c in picked)
        EmailAddress(email: c.email, displayName: c.displayName.trim().isEmpty ? null : c.displayName),
    ];
  }

  Future<void> _pickStart() async {
    final l10n = AppLocalizations.of(context);
    final d = await showWheelDatePicker(context, initial: _d.start ?? _today(), title: l10n.tr('projStart'));
    if (d != null) setState(() => _d.start = d);
  }

  Future<void> _editStage([int? index]) async {
    final res = await showStageEditor(context, ref, project: _d, index: index, account: _account);
    if (res == null) return;
    setState(() {
      if (index == null) {
        _d.stages.add(res);
      } else {
        _d.stages[index] = res;
      }
    });
  }

  void _removeStage(int i) {
    setState(() {
      _d.stages.removeAt(i);
      // Ссылки «после этапа» — на прежние номера.
      for (final s in _d.stages) {
        final a = s.after;
        if (a == null) continue;
        if (a == i) {
          s.after = null;
        } else if (a > i) {
          s.after = a - 1;
        }
      }
    });
  }

  Future<void> _fromTemplate() async {
    final l10n = AppLocalizations.of(context);
    final svc = ref.read(assignmentServiceProvider);
    final list = await svc.templates();
    if (!mounted) return;
    if (list.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(l10n.tr('projNoTemplates')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('ok')))],
        ),
      );
      return;
    }
    final chosen = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(l10n.tr('projFromTemplate'), style: Theme.of(ctx).textTheme.titleMedium)),
          for (final t in list)
            ListTile(
              leading: const Icon(AppIcons.content_copy),
              title: Text(t.name),
              onTap: () => Navigator.pop(ctx, t.id),
              trailing: IconButton(
                tooltip: l10n.delete,
                icon: const Icon(AppIcons.delete),
                onPressed: () {
                  unawaited(svc.deleteTemplate(t.id));
                  Navigator.pop(ctx);
                },
              ),
            ),
        ]),
      ),
    );
    final t = list.where((x) => x.id == chosen).firstOrNull;
    if (t == null || !mounted) return;
    final start = _d.start ?? _today();
    setState(() {
      _d = ProjectDraft.fromTemplateJson(t.payloadJson, start);
      _title.text = _d.title;
      _desc.text = _d.description;
    });
  }

  Future<void> _saveTemplate() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: _title.text.trim());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('projSaveTemplate')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.tr('projTemplateName')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    _d
      ..title = _title.text.trim()
      ..description = _desc.text.trim();
    await ref.read(assignmentServiceProvider).saveTemplate(name, _d);
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty &&
      _d.stages.isNotEmpty &&
      _d.stages.every((s) => s.title.trim().isNotEmpty && s.executor.email.contains('@'));

  Future<void> _send() async {
    final account = _account;
    if (account == null || !_ready || _sending) return;
    setState(() => _sending = true);
    _d
      ..title = _title.text.trim()
      ..description = _desc.text.trim();
    await ref.read(assignmentServiceProvider).createProject(account, _d);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('EEE, d MMM', l10n.localeCode);
    Widget label(String t, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: Space.l, bottom: Space.xs),
          child: Row(children: [
            Expanded(child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: muted))),
            ?trailing,
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('projNew')),
        actions: [
          IconButton(
            key: const ValueKey('proj_from_template'),
            tooltip: l10n.tr('projFromTemplate'),
            icon: const Icon(AppIcons.content_copy),
            onPressed: () => unawaited(_fromTemplate()),
          ),
          IconButton(
            tooltip: l10n.tr('projSaveTemplate'),
            icon: const Icon(AppIcons.save),
            onPressed: _d.stages.isEmpty ? null : () => unawaited(_saveTemplate()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: ReadableWidth(
          maxWidth: assignmentColumnWidth,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
            child: FilledButton.icon(
              key: const ValueKey('proj_send'),
              onPressed: _ready && !_sending ? () => unawaited(_send()) : null,
              icon: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.send, size: 18),
              label: Text(l10n.tr('projSend')),
            ),
          ),
        ),
      ),
      body: ReadableWidth(
          maxWidth: assignmentColumnWidth,
          fill: true,
          child: ListView(padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xl), children: [
        TextField(
          key: const ValueKey('proj_title'),
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: l10n.tr('projTitleHint')),
        ),
        const SizedBox(height: Space.m),
        TextField(
          controller: _desc,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(border: const OutlineInputBorder(), labelText: l10n.tr('projDescription')),
        ),
        // С какого ящика уйдут письма проекта.
        if (ref.watch(accountsProvider).length > 1 && _account != null) ...[
          const SizedBox(height: Space.m),
          AssignmentAccountField(
            accounts: ref.watch(accountsProvider),
            selected: _account!.id,
            onChanged: (id) => setState(() => _accountId = id),
          ),
        ],
        label(l10n.tr('projStart')),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: const Icon(AppIcons.event, size: 18),
            label: Text(_d.start == null ? l10n.tr('taskPickDate') : fmt.format(_d.start!)),
            onPressed: () => unawaited(_pickStart()),
          ),
        ),
        label(l10n.tr('projController')),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          if (_d.controller != null) personChip(_d.controller!, onDeleted: () => setState(() => _d.controller = null)),
          if (_d.controller == null)
            ActionChip(
              avatar: const Icon(AppIcons.person_add, size: 18),
              label: Text(l10n.tr('assignAddPeople')),
              onPressed: () async {
                final p = await _pick();
                if (p.isNotEmpty) setState(() => _d.controller = p.first);
              },
            ),
        ]),
        Text(l10n.tr('projControllerHint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        label(l10n.tr('projObservers')),
        Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
          for (final o in _d.observers) personChip(o, onDeleted: () => setState(() => _d.observers.remove(o))),
          ActionChip(
            avatar: const Icon(AppIcons.person_add, size: 18),
            label: Text(l10n.tr('assignAddPeople')),
            onPressed: () async {
              final p = await _pick(exclude: {for (final o in _d.observers) o.email.toLowerCase()});
              setState(() => _d.observers.addAll(p));
            },
          ),
        ]),
        label(l10n.tr('projFiles')),
        _FilesEditor(files: _d.files, onChanged: () => setState(() {})),
        label(
          '${l10n.tr('projStages')} · ${_d.stages.length}',
          trailing: TextButton.icon(
            key: const ValueKey('proj_add_stage'),
            onPressed: () => unawaited(_editStage()),
            icon: const Icon(AppIcons.add, size: 18),
            label: Text(l10n.tr('projAddStage')),
          ),
        ),
        if (_d.stages.isEmpty)
          Text(l10n.tr('projNeedStage'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        for (var i = 0; i < _d.stages.length; i++)
          _StageCard(
            index: i,
            stage: _d.stages[i],
            afterTitle: _d.stages[i].after == null ? null : _d.stages[_d.stages[i].after!].title,
            onTap: () => unawaited(_editStage(i)),
            onDelete: () => _removeStage(i),
          ),
      ])),
    );
  }
}

class _StageCard extends StatelessWidget {
  final int index;
  final StageDraft stage;
  final String? afterTitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _StageCard({required this.index, required this.stage, this.afterTitle, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('d MMM', l10n.localeCode);
    final dates = [
      if (stage.start != null) fmt.format(stage.start!),
      if (stage.due != null) fmt.format(stage.due!),
    ].join(' — ');
    final who = [
      stage.executor.label,
      if (stage.co.isNotEmpty) '+${stage.co.length}',
    ].join(' ');
    return Card(
      margin: const EdgeInsets.only(bottom: Space.s),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(radius: 14, child: Text('${index + 1}', style: theme.textTheme.labelMedium)),
        title: Text(stage.title.isEmpty ? l10n.tr('projStage') : stage.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            who,
            if (dates.isNotEmpty) dates,
            afterTitle == null ? l10n.tr('projParallel') : l10n.tr('projAfter').replaceAll('{title}', afterTitle!),
            if (stage.checklist.isNotEmpty) '☑ ${stage.checklist.length}',
            if (stage.files.isNotEmpty) '📎 ${stage.files.length}',
          ].join(' · '),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        trailing: IconButton(tooltip: l10n.tr('projDeleteStage'), icon: const Icon(AppIcons.delete), onPressed: onDelete),
      ),
    );
  }
}

/// Список файлов с «Добавить файлы» и удалением.
class _FilesEditor extends StatelessWidget {
  final List<AssignmentFile> files;
  final VoidCallback onChanged;
  const _FilesEditor({required this.files, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
      for (final f in files)
        InputChip(
          avatar: const Icon(AppIcons.attach_file, size: 18),
          label: Text([f.name, _size(f.size)].where((x) => x.isNotEmpty).join(' · ')),
          onDeleted: () {
            files.remove(f);
            onChanged();
          },
        ),
      ActionChip(
        avatar: const Icon(AppIcons.attach_file, size: 18),
        label: Text(l10n.tr('projAddFiles')),
        onPressed: () async {
          try {
            files.addAll(await pickAssignmentFiles());
          } catch (_) {}
          onChanged();
        },
      ),
    ]);
  }
}

/// Редактор этапа. [index] — изменить этап; null — новый.
Future<StageDraft?> showStageEditor(
  BuildContext context,
  WidgetRef ref, {
  required ProjectDraft project,
  int? index,
  AccountModel? account,
}) =>
    showAppSheet<StageDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StageSheet(project: project, index: index, account: account),
    );

class _StageSheet extends StatefulWidget {
  final ProjectDraft project;
  final int? index;
  final AccountModel? account;
  const _StageSheet({required this.project, this.index, this.account});

  @override
  State<_StageSheet> createState() => _StageSheetState();
}

class _StageSheetState extends State<_StageSheet> {
  late final StageDraft? _orig = widget.index == null ? null : widget.project.stages[widget.index!];
  late final _title = TextEditingController(text: _orig?.title ?? '');
  late final _desc = TextEditingController(text: _orig?.description ?? '');
  final _check = TextEditingController();
  EmailAddress? _executor;
  late final List<EmailAddress> _co = [...?_orig?.co];
  EmailAddress? _controller;
  late final List<EmailAddress> _observers = [...?_orig?.observers];
  DateTime? _start;
  DateTime? _due;
  int? _after;
  late final List<String> _checklist = [...?_orig?.checklist];
  late final List<AssignmentFile> _files = [...?_orig?.files];

  /// Номера этапов, после которых можно поставить этот (только раньше
  /// него в списке — без циклов).
  int get _limit => widget.index ?? widget.project.stages.length;

  @override
  void initState() {
    super.initState();
    final o = _orig;
    _executor = o?.executor;
    _controller = o?.controller;
    _start = o?.start;
    _due = o?.due;
    _after = o?.after;
    if (o == null) {
      // Новый этап — по умолчанию после предыдущего, той же длительности.
      final stages = widget.project.stages;
      final prev = stages.isEmpty ? null : stages.last;
      final d = nextStageDates(prev?.due, widget.project.start ?? DateTime.now());
      _start = d.start;
      _due = d.due;
      _after = stages.isEmpty ? null : stages.length - 1;
    }
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _check.dispose();
    super.dispose();
  }

  Future<List<EmailAddress>> _pick({Set<String> exclude = const {}}) async {
    final picked = await showPeoplePicker(context, account: widget.account, exclude: exclude);
    return [
      for (final c in picked)
        EmailAddress(email: c.email, displayName: c.displayName.trim().isEmpty ? null : c.displayName),
    ];
  }

  Future<void> _date(bool start) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final d = await showWheelDatePicker(context,
        initial: (start ? _start : _due) ?? DateTime(now.year, now.month, now.day),
        title: l10n.tr(start ? 'projStartDate' : 'projDueDate'));
    if (d == null) return;
    setState(() {
      if (start) {
        _start = d;
        if (_due != null && _due!.isBefore(d)) _due = d;
      } else {
        _due = d;
        if (_start != null && _start!.isAfter(d)) _start = d;
      }
    });
  }

  void _setAfter(int? a) {
    setState(() {
      _after = a;
      if (a == null) return;
      // После этапа — со дня после его срока, длительность — прежняя.
      final prev = widget.project.stages[a];
      if (prev.due == null) return;
      final len = (_start != null && _due != null) ? _due!.difference(_start!).inDays + 1 : 3;
      final d = nextStageDates(prev.due, prev.due!, days: len);
      _start = d.start;
      _due = d.due;
    });
  }

  bool get _ok => _title.text.trim().isNotEmpty && _executor != null;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final fmt = DateFormat('EEE, d MMM', l10n.localeCode);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
          child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
        );
    final stages = widget.project.stages;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              widget.index == null ? l10n.tr('projAddStage') : '${l10n.tr('projStage')} ${widget.index! + 1}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: Space.m),
            TextField(
              key: const ValueKey('stage_title'),
              controller: _title,
              autofocus: widget.index == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: l10n.tr('projStageTitleHint')),
            ),
            const SizedBox(height: Space.s),
            TextField(
              controller: _desc,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: l10n.tr('assignNote')),
            ),
            label(l10n.tr('projExecutor')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              if (_executor != null) personChip(_executor!, onDeleted: () => setState(() => _executor = null)),
              if (_executor == null)
                ActionChip(
                  key: const ValueKey('stage_executor'),
                  avatar: const Icon(AppIcons.person_add, size: 18),
                  label: Text(l10n.tr('assignAddPeople')),
                  onPressed: () async {
                    final p = await _pick();
                    if (p.isNotEmpty) setState(() => _executor = p.first);
                  },
                ),
            ]),
            label(l10n.tr('projCo')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              for (final c in _co) personChip(c, onDeleted: () => setState(() => _co.remove(c))),
              ActionChip(
                avatar: const Icon(AppIcons.person_add, size: 18),
                label: Text(l10n.tr('assignAddPeople')),
                onPressed: () async {
                  final p = await _pick(exclude: {for (final c in _co) c.email.toLowerCase()});
                  setState(() => _co.addAll(p));
                },
              ),
            ]),
            label(l10n.tr('projController')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              if (_controller != null) personChip(_controller!, onDeleted: () => setState(() => _controller = null)),
              if (_controller == null)
                ActionChip(
                  avatar: const Icon(AppIcons.person_add, size: 18),
                  label: Text(widget.project.controller == null
                      ? l10n.tr('assignAddPeople')
                      : widget.project.controller!.label),
                  onPressed: () async {
                    final p = await _pick();
                    if (p.isNotEmpty) setState(() => _controller = p.first);
                  },
                ),
            ]),
            label(l10n.tr('projObservers')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              for (final o in _observers) personChip(o, onDeleted: () => setState(() => _observers.remove(o))),
              ActionChip(
                avatar: const Icon(AppIcons.person_add, size: 18),
                label: Text(l10n.tr('assignAddPeople')),
                onPressed: () async {
                  final p = await _pick(exclude: {for (final o in _observers) o.email.toLowerCase()});
                  setState(() => _observers.addAll(p));
                },
              ),
            ]),
            label(l10n.tr('projOrder')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              ChoiceChip(
                label: Text(l10n.tr('projParallel')),
                selected: _after == null,
                onSelected: (_) => _setAfter(null),
              ),
              for (var i = 0; i < _limit && i < stages.length; i++)
                ChoiceChip(
                  label: Text(l10n.tr('projAfter').replaceAll('{title}', '${i + 1}. ${stages[i].title}')),
                  selected: _after == i,
                  onSelected: (_) => _setAfter(i),
                ),
            ]),
            label('${l10n.tr('projStartDate')} — ${l10n.tr('projDueDate')}'),
            Wrap(spacing: Space.xs, children: [
              ActionChip(
                avatar: const Icon(AppIcons.event, size: 18),
                label: Text(_start == null ? l10n.tr('projStartDate') : fmt.format(_start!)),
                onPressed: () => unawaited(_date(true)),
              ),
              ActionChip(
                avatar: const Icon(AppIcons.flag, size: 18),
                label: Text(_due == null ? l10n.tr('projDueDate') : fmt.format(_due!)),
                onPressed: () => unawaited(_date(false)),
              ),
            ]),
            label(l10n.tr('projChecklist')),
            for (var i = 0; i < _checklist.length; i++)
              Row(children: [
                const Icon(AppIcons.check_box_outline_blank, size: 18),
                const SizedBox(width: Space.s),
                Expanded(child: Text(_checklist[i])),
                IconButton(
                  icon: const Icon(AppIcons.close, size: 18),
                  onPressed: () => setState(() => _checklist.removeAt(i)),
                ),
              ]),
            TextField(
              controller: _check,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: l10n.tr('projAddCheck'),
                prefixIcon: const Icon(AppIcons.add),
                isDense: true,
              ),
              onSubmitted: (t) {
                if (t.trim().isEmpty) return;
                setState(() {
                  _checklist.add(t.trim());
                  _check.clear();
                });
              },
            ),
            label(l10n.tr('projStageFiles')),
            _FilesEditor(files: _files, onChanged: () => setState(() {})),
            const SizedBox(height: Space.l),
            FilledButton(
              key: const ValueKey('stage_ok'),
              onPressed: _ok
                  ? () {
                      final extra = _check.text.trim();
                      Navigator.pop(
                        context,
                        StageDraft(
                          title: _title.text.trim(),
                          description: _desc.text.trim(),
                          executor: _executor!,
                          co: _co,
                          controller: _controller,
                          observers: _observers,
                          start: _start,
                          due: _due,
                          after: _after,
                          checklist: [..._checklist, if (extra.isNotEmpty) extra],
                          files: _files,
                        ),
                      );
                    }
                  : null,
              child: Text(l10n.tr('done')),
            ),
          ]),
        ),
      ),
    );
  }
}

// lib/features/assignments/assign_sheet.dart
// «Поручить» (решения владельца 09.11.2026): из письма (меню письма), из
// календаря (срок — выбранный день) и из раздела «Поручения». Что сделать,
// исполнители (люди письма — подсказками, остальные — из контактов и
// адресной книги), срок одним нажатием, пояснение. Каждому исполнителю —
// своё поручение и своё письмо: у каждого свой статус.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/subject_prefix.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart';
import '../../services/mail/own_addresses.dart';
import '../../services/tasks/task_actions_service.dart' show TaskReschedule;
import '../../widgets/common/app_sheet.dart';
import '../../widgets/common/hero_email_transition.dart';
import '../../widgets/ui/wheel_pickers.dart';
import '../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider, emailModelFromRow;

/// Открыть «Поручить». [sourceEmailId] — письмо-основание; [due] — срок
/// (из календаря). true — поручение создано.
Future<bool> showAssignSheet(
  BuildContext context, {
  String? sourceEmailId,
  String? accountId,
  DateTime? due,
}) async {
  final ok = await showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AssignSheet(sourceEmailId: sourceEmailId, accountId: accountId, due: due),
  );
  return ok ?? false;
}

class _AssignSheet extends ConsumerStatefulWidget {
  final String? sourceEmailId;
  final String? accountId;
  final DateTime? due;
  const _AssignSheet({this.sourceEmailId, this.accountId, this.due});

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final List<EmailAddress> _to = [];
  List<EmailAddress> _suggest = const [];
  Email? _source;
  late DateTime? _due = widget.due;
  bool _sending = false;

  AccountModel? get _account {
    final accounts = ref.read(accountsProvider);
    final id = _source?.accountId ?? widget.accountId ?? ref.read(activeAccountProvider)?.id;
    return accounts.where((a) => a.id == id).firstOrNull ?? accounts.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    final id = widget.sourceEmailId;
    if (id != null) unawaited(_loadSource(id));
  }

  Future<void> _loadSource(String id) async {
    final row = await ref.read(databaseProvider).getEmailById(id, accountId: widget.accountId);
    if (row == null || !mounted) return;
    final account = ref.read(accountsProvider).where((a) => a.id == row.accountId).firstOrNull;
    final mine = account == null ? <String>{} : {for (final m in OwnAddresses.of(account)) m.toLowerCase()};
    final people = <String, EmailAddress>{};
    void add(String? email, String? name) {
      final e = (email ?? '').trim().toLowerCase();
      if (e.isEmpty || mine.contains(e) || people.containsKey(e)) return;
      people[e] = EmailAddress(email: e, displayName: (name ?? '').trim().isEmpty ? null : name!.trim());
    }

    final m = emailModelFromRow(row);
    add(m.from.email, m.from.displayName);
    for (final a in [...m.to, ...m.cc]) {
      add(a.email, a.displayName);
    }
    setState(() {
      _source = row;
      _suggest = people.values.take(8).toList();
      if (_title.text.isEmpty) _title.text = SubjectPrefix.strip(row.subject);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _add(EmailAddress a) {
    if (_to.any((x) => x.email.toLowerCase() == a.email.toLowerCase())) return;
    setState(() => _to.add(a));
  }

  Future<void> _pickPeople() async {
    final picked = await showPeoplePicker(context,
        account: _account, exclude: {for (final a in _to) a.email.toLowerCase()});
    for (final c in picked) {
      _add(EmailAddress(email: c.email, displayName: c.displayName.trim().isEmpty ? null : c.displayName));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = await showWheelDatePicker(context,
        initial: _due ?? today, first: today, title: AppLocalizations.of(context).tr('taskPickDate'));
    if (d != null) setState(() => _due = d);
  }

  Future<void> _submit() async {
    final account = _account;
    if (account == null || _to.isEmpty || _title.text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    await ref.read(assignmentServiceProvider).create(
          account: account,
          title: _title.text.trim(),
          description: _note.text,
          assignees: List.of(_to),
          due: _due,
          source: _source,
        );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = AppColors.mutedText(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final week = TaskReschedule.nextWeek(now);
    bool same(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;
    final custom = _due != null && !same(_due, today) && !same(_due, tomorrow) && !same(_due, week);
    final account = _account;
    final multi = ref.watch(accountsProvider).length > 1;
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: Space.m, bottom: Space.xs),
          child: Text(t, style: theme.textTheme.labelLarge?.copyWith(color: muted)),
        );
    Widget person(EmailAddress a, {bool chosen = false}) {
      final name = a.label;
      final avatar = HeroEmailAvatar(
        emailId: 'asg_pick_${a.email}',
        initial: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        color: HeroEmailAvatar.colorForEmail(a.email),
        radius: 12,
        hero: false,
        email: a.email,
      );
      return chosen
          ? InputChip(avatar: avatar, label: Text(name), onDeleted: () => setState(() => _to.remove(a)))
          : ActionChip(avatar: avatar, label: Text(name), onPressed: () => _add(a));
    }

    final suggest = [
      for (final a in _suggest)
        if (!_to.any((x) => x.email.toLowerCase() == a.email.toLowerCase())) a,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(AppIcons.assignment_ind, color: theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Text(l10n.tr('assignSheetTitle'), style: theme.textTheme.titleLarge),
            ]),
            if (_source != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  l10n.tr('assignFromMail').replaceAll('{subject}', _source!.subject),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
            label(l10n.tr('assignWhatHint')),
            TextField(
              controller: _title,
              autofocus: widget.sourceEmailId == null,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(border: const OutlineInputBorder(), hintText: l10n.tr('assignWhatHint')),
            ),
            label(l10n.tr('assignWho')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              for (final a in _to) person(a, chosen: true),
              ActionChip(
                avatar: const Icon(AppIcons.person_add, size: 18),
                label: Text(l10n.tr('assignAddPeople')),
                onPressed: () => unawaited(_pickPeople()),
              ),
            ]),
            if (suggest.isNotEmpty) ...[
              const SizedBox(height: Space.xs),
              Text(l10n.tr('assignSuggest'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              const SizedBox(height: Space.xs),
              Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [for (final a in suggest) person(a)]),
            ],
            label(l10n.tr('assignDueTitle')),
            Wrap(spacing: Space.xs, runSpacing: Space.xs, children: [
              ChoiceChip(
                  label: Text(l10n.tr('today')), selected: same(_due, today), onSelected: (_) => setState(() => _due = today)),
              ChoiceChip(
                  label: Text(l10n.tr('tomorrow')),
                  selected: same(_due, tomorrow),
                  onSelected: (_) => setState(() => _due = tomorrow)),
              ChoiceChip(
                  label: Text(l10n.tr('laterNextWeek')),
                  selected: same(_due, week),
                  onSelected: (_) => setState(() => _due = week)),
              ChoiceChip(
                label: Text(custom ? DateFormat('EEE, d MMM', l10n.localeCode).format(_due!) : l10n.tr('taskPickDate')),
                selected: custom,
                onSelected: (_) => unawaited(_pickDate()),
              ),
              ChoiceChip(
                  label: Text(l10n.tr('noDueDate')), selected: _due == null, onSelected: (_) => setState(() => _due = null)),
            ]),
            label(l10n.tr('assignNote')),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            const SizedBox(height: Space.s),
            Text(
              [
                l10n.tr('assignEachNote'),
                if (multi && account != null) l10n.tr('assignFromAccount').replaceAll('{email}', account.email),
              ].join(' '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: Space.m),
            FilledButton.icon(
              onPressed: _to.isEmpty || _title.text.trim().isEmpty || _sending ? null : () => unawaited(_submit()),
              icon: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.send, size: 18),
              label: Text(l10n.tr('assignSend')),
            ),
          ]),
        ),
      ),
    );
  }
}

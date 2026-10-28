// lib/features/contacts/screens/contact_groups_screen.dart
// Группы рассылки: свои именованные списки адресатов (хранятся на телефоне).
// Создать, переименовать, добавить и убрать участников, удалить, написать
// всей группе, переслать группу другому человеку файлом .vcf и принять
// присланную группу (импорт .vcf).
//
// Раньше группы можно было только сохранить из окна письма и удалить —
// ни просмотра, ни правки, ни передачи.

import '../../../core/utils/text_safe.dart';
import 'dart:convert';
import 'dart:io';

import '../../../core/platform/file_pick.dart' show FilePick, FileType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../compose/providers/distribution_groups_provider.dart';
import '../../compose/widgets/people_picker_sheet.dart';
import '../../mail/providers/mail_providers.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;
import '../../../core/theme/ogneliss_look.dart';

class ContactGroupsScreen extends ConsumerWidget {
  const ContactGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(distributionGroupsProvider);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('contactGroups')),
        actions: [
          IconButton(
            tooltip: l10n.tr('groupImport'),
            icon: const Icon(AppIcons.download),
            onPressed: () => importGroupFile(context, ref),
          ),
          IconButton(
            tooltip: l10n.tr('groupNew'),
            icon: const Icon(AppIcons.add),
            onPressed: () => _openEditor(context, null),
          ),
        ],
      )),
      body: groups.isEmpty
          ? EmptyState(
              icon: AppIcons.groups,
              title: l10n.tr('groupsEmpty'),
              message: l10n.tr('groupsEmptyHint'),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const RowDivider(indent: Space.l, endIndent: Space.l),
              itemBuilder: (_, i) {
                final g = groups[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(g.name.isEmpty ? '?' : initialOf(g.name))),
                  title: Text(g.name),
                  subtitle: Text(l10n.tr('groupMembersN').replaceAll('{n}', '${g.members.length}')),
                  onTap: () => _openEditor(context, g),
                  trailing: IconButton(
                    tooltip: l10n.tr('more'),
                    icon: const Icon(AppIcons.more_vert),
                    onPressed: () => _groupActions(context, ref, g),
                  ),
                );
              },
            ),
    );
  }

  void _openEditor(BuildContext context, DistributionGroup? g) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GroupEditor(group: g)));
  }

  Future<void> _groupActions(BuildContext context, WidgetRef ref, DistributionGroup g) async {
    final l10n = AppLocalizations.of(context);
    final a = await showActionSheet<String>(
      context,
      title: g.name,
      subtitle: l10n.tr('groupMembersN').replaceAll('{n}', '${g.members.length}'),
      leading: const Icon(AppIcons.groups),
      items: [
        ActionSheetItem(icon: AppIcons.edit, label: l10n.tr('compose'), value: 'write'),
        ActionSheetItem(icon: AppIcons.ios_share, label: l10n.tr('groupShare'), value: 'share'),
        ActionSheetItem(icon: AppIcons.edit_note, label: l10n.tr('edit'), value: 'edit'),
        ActionSheetItem(icon: AppIcons.delete, label: l10n.tr('delete'), value: 'delete', destructive: true),
      ],
    );
    if (a == null || !context.mounted) return;
    switch (a) {
      case 'write':
        writeToGroup(context, g);
      case 'share':
        await shareGroup(g);
      case 'edit':
        _openEditor(context, g);
      case 'delete':
        final ok = await confirmDestructive(context, title: l10n.tr('groupDelete'), message: g.name);
        if (ok) await ref.read(distributionGroupsProvider.notifier).deleteGroup(g.name);
    }
  }
}

/// Написать всей группе.
void writeToGroup(BuildContext context, DistributionGroup g) {
  context.push(Uri(path: '/compose', queryParameters: {
    'to': g.members.map((m) => m.email).join(','),
  }).toString());
}

// ── Передача группы файлом .vcf ──
//
// Формат — vCard 4.0: карточка группы (KIND:group, MEMBER:mailto:…) и
// карточки участников. Другой Ogneliss принимает её целиком как группу,
// Outlook и телефоны — как набор контактов.

String _esc(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\n', '\\n');

String groupToVcf(DistributionGroup g) {
  final b = StringBuffer()
    ..write('BEGIN:VCARD\r\nVERSION:4.0\r\nKIND:group\r\n')
    ..write('FN:${_esc(g.name)}\r\n');
  for (final m in g.members) {
    b.write('MEMBER:mailto:${m.email}\r\n');
  }
  b.write('END:VCARD\r\n');
  for (final m in g.members) {
    final name = (m.name ?? '').trim().isEmpty ? m.email : m.name!.trim();
    b
      ..write('BEGIN:VCARD\r\nVERSION:4.0\r\n')
      ..write('FN:${_esc(name)}\r\n')
      ..write('EMAIL;TYPE=work:${m.email}\r\n')
      ..write('END:VCARD\r\n');
  }
  return b.toString();
}

/// Разобрать группы из .vcf: карточки KIND:group; имена участников — из
/// карточек с тем же адресом. Файл без KIND:group — одна группа из всех
/// адресов файла, с именем [fallbackName].
List<DistributionGroup> groupsFromVcf(String text, {String fallbackName = 'Group'}) {
  final unfolded = text.replaceAll(RegExp(r'\r?\n[ \t]'), '');
  final cards = RegExp(r'BEGIN:VCARD(.*?)END:VCARD', dotAll: true, caseSensitive: false)
      .allMatches(unfolded)
      .map((m) => m.group(1)!)
      .toList();
  String? prop(String card, String name) {
    final m = RegExp('^$name(?:;[^:\\n]*)?:(.*)\$', multiLine: true, caseSensitive: false).firstMatch(card);
    return m?.group(1)?.trim().replaceAll('\\,', ',').replaceAll('\\;', ';').replaceAll('\\n', ' ');
  }

  final names = <String, String>{};
  final allEmails = <String>[];
  for (final c in cards) {
    if (RegExp(r'^KIND:group', multiLine: true, caseSensitive: false).hasMatch(c)) continue;
    final email = prop(c, 'EMAIL')?.toLowerCase();
    if (email == null || !email.contains('@')) continue;
    allEmails.add(email);
    final fn = prop(c, 'FN');
    if (fn != null && fn.isNotEmpty && fn.toLowerCase() != email) names[email] = fn;
  }
  final out = <DistributionGroup>[];
  for (final c in cards) {
    if (!RegExp(r'^KIND:group', multiLine: true, caseSensitive: false).hasMatch(c)) continue;
    final members = <GroupMember>[];
    for (final m in RegExp(r'^MEMBER(?:;[^:\n]*)?:(?:mailto:)?(.+)$', multiLine: true, caseSensitive: false)
        .allMatches(c)) {
      final e = m.group(1)!.trim().toLowerCase();
      if (e.contains('@') && !members.any((x) => x.email == e)) {
        members.add(GroupMember(email: e, name: names[e]));
      }
    }
    final name = prop(c, 'FN') ?? fallbackName;
    if (members.isNotEmpty) out.add(DistributionGroup(name: name, members: members));
  }
  if (out.isEmpty && allEmails.isNotEmpty) {
    out.add(DistributionGroup(
      name: fallbackName,
      members: [for (final e in {...allEmails}) GroupMember(email: e, name: names[e])],
    ));
  }
  return out;
}

Future<void> shareGroup(DistributionGroup g) async {
  final dir = await getTemporaryDirectory();
  final safe = g.name.replaceAll(RegExp(r'[^\wА-Яа-яЁё\- ]+'), '_').trim();
  final f = File('${dir.path}/${safe.isEmpty ? 'group' : safe}.vcf');
  await f.writeAsString(groupToVcf(g), encoding: utf8);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(f.path, mimeType: 'text/vcard', name: '${safe.isEmpty ? 'group' : safe}.vcf')],
    subject: g.name,
    text: '${g.name}: ${g.members.map((m) => m.email).join(', ')}',
  ));
}

/// Принять группу из файла .vcf (присланного письмом или сохранённого).
Future<void> importGroupFile(BuildContext context, WidgetRef ref) async {
  final file = await FilePick.file(type: FileType.custom, allowedExtensions: const ['vcf', 'vcard']);
  if (file == null) return;
  final bytes = await file.readBytes();
  final name = file.name.replaceAll(RegExp(r'\.(vcf|vcard)$', caseSensitive: false), '');
  final groups = groupsFromVcf(utf8.decode(bytes, allowMalformed: true), fallbackName: name);
  for (final g in groups) {
    await ref.read(distributionGroupsProvider.notifier).saveGroup(g.name, g.members);
  }
  if (!context.mounted || groups.isEmpty) return;
  if (groups.length == 1) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _GroupEditor(group: groups.first)));
  }
}

/// Новая группа для рассылки — из «Создать» в контактах.
void openGroupEditor(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _GroupEditor()));
}

// ── Правка группы ──

class _GroupEditor extends ConsumerStatefulWidget {
  final DistributionGroup? group;
  const _GroupEditor({this.group});

  @override
  ConsumerState<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends ConsumerState<_GroupEditor> {
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late List<GroupMember> _members = [...?widget.group?.members];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final picked = await showPeoplePicker(context,
        account: ref.read(activeAccountProvider),
        exclude: {for (final m in _members) m.email.toLowerCase()});
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final c in picked) {
        if (c.email.isEmpty || _members.any((m) => m.email.toLowerCase() == c.email.toLowerCase())) continue;
        _members = [..._members, GroupMember(email: c.email, name: c.displayName.isEmpty ? null : c.displayName)];
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.tr('groupNameRequired'));
      return;
    }
    if (_members.isEmpty) {
      setState(() => _error = l10n.tr('groupMembersRequired'));
      return;
    }
    final notifier = ref.read(distributionGroupsProvider.notifier);
    // Переименование — старая группа убирается.
    final old = widget.group?.name;
    if (old != null && old.toLowerCase() != name.toLowerCase()) await notifier.deleteGroup(old);
    await notifier.saveGroup(name, _members);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final current = DistributionGroup(name: _name.text.trim(), members: _members);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr(widget.group == null ? 'groupNew' : 'contactGroup')),
        actions: [
          if (widget.group != null) ...[
            IconButton(
              tooltip: l10n.tr('compose'),
              icon: const Icon(AppIcons.edit),
              onPressed: _members.isEmpty ? null : () => writeToGroup(context, current),
            ),
            IconButton(
              tooltip: l10n.tr('groupShare'),
              icon: const Icon(AppIcons.ios_share),
              onPressed: _members.isEmpty ? null : () => shareGroup(current),
            ),
          ],
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: FilledButton(onPressed: _save, child: Text(l10n.save)),
          ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xxl),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: l10n.tr('groupName'),
              prefixIcon: const Icon(AppIcons.groups),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          SettingsSectionTitle(
            l10n.tr('groupMembersN').replaceAll('{n}', '${_members.length}'),
            trailing: TextButton.icon(
              icon: const Icon(AppIcons.person_add, size: Sizes.iconInline),
              label: Text(l10n.tr('add')),
              onPressed: _add,
            ),
          ),
          for (final m in _members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(AppIcons.person),
              title: Text((m.name ?? '').trim().isEmpty ? m.email : m.name!),
              subtitle: (m.name ?? '').trim().isEmpty
                  ? null
                  : Text(m.email, style: TextStyle(color: AppColors.mutedText(context))),
              trailing: IconButton(
                tooltip: l10n.tr('delete'),
                icon: const Icon(AppIcons.close),
                onPressed: () => setState(() => _members = _members.where((x) => x != m).toList()),
              ),
            ),
          if (_members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.l),
              child: Text(l10n.tr('groupMembersRequired'),
                  style: TextStyle(color: AppColors.mutedText(context))),
            ),
        ],
      ),
    );
  }
}

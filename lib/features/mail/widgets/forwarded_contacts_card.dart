// lib/features/mail/widgets/forwarded_contacts_card.dart
//
// Присланные письмом контакты и группы контактов — к сохранению себе
// (просьба владельца 21.11.2026: «не обрабатываются пересылаемые контакты и
// группы контактов (нельзя сохранить себе)»). Источники: группа и контакт
// Outlook во вложенном письме (winmail.dat) и файл .vcf.
//
// Группа сохраняется в «Группы рассылки» (как принятая из .vcf), каждый
// участник и контакт — в адресную книгу через обычную форму контакта (там
// выбирается, в какой ящик).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/dav/vcard_parser.dart' show VCardData;
import '../../compose/providers/distribution_groups_provider.dart';
import '../../contacts/screens/contact_groups_screen.dart' show openGroupEditor;
import '../../contacts/widgets/contact_editor.dart' show showContactEditor;

class ForwardedContactsCard extends ConsumerStatefulWidget {
  const ForwardedContactsCard({super.key, this.groups = const [], this.contacts = const []});

  final List<DistributionGroup> groups;
  final List<VCardData> contacts;

  bool get isEmpty => groups.isEmpty && contacts.isEmpty;

  @override
  ConsumerState<ForwardedContactsCard> createState() => _ForwardedContactsCardState();
}

class _ForwardedContactsCardState extends ConsumerState<ForwardedContactsCard> {
  /// Сохранённые группы (по имени) — кнопка сменяется на «Открыть».
  final Set<String> _saved = {};

  /// Участников длинной группы показываем не всех сразу.
  final Set<String> _expanded = {};
  static const _collapsed = 8;

  Future<void> _saveGroup(DistributionGroup g) async {
    await ref.read(distributionGroupsProvider.notifier).saveGroup(g.name, g.members);
    if (mounted) setState(() => _saved.add(g.name));
  }

  void _openGroup(DistributionGroup g) {
    final saved = ref.read(distributionGroupsProvider).where((x) => x.name.toLowerCase() == g.name.toLowerCase());
    openGroupEditor(context, saved.isEmpty ? g : saved.first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final children = <Widget>[];

    for (final g in widget.groups) {
      final saved = _saved.contains(g.name);
      final all = _expanded.contains(g.name) || g.members.length <= _collapsed + 2;
      final shown = all ? g.members : g.members.take(_collapsed).toList();
      children.add(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(AppIcons.groups),
        title: Text(g.name, style: theme.textTheme.titleSmall),
        subtitle: Text('${l10n.tr('fwdContactGroup')} · ${l10n.tr('groupMembersN').replaceAll('{n}', '${g.members.length}')}'),
      ));
      for (final m in shown) {
        final name = (m.name ?? '').trim();
        children.add(ListTile(
          dense: true,
          contentPadding: const EdgeInsetsDirectional.only(start: Space.xl),
          title: Text(name.isEmpty ? m.email : name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: name.isEmpty ? null : Text(m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: l10n.tr('addContact'),
            icon: const Icon(AppIcons.person_add, size: 20),
            onPressed: () => showContactEditor(context, email: m.email, name: name.isEmpty ? null : name),
          ),
        ));
      }
      if (!all) {
        children.add(Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => setState(() => _expanded.add(g.name)),
            child: Text(l10n.tr('boardShowAll').replaceAll('{n}', '${g.members.length}')),
          ),
        ));
      }
      children.add(Padding(
        padding: const EdgeInsets.only(top: Space.xs, bottom: Space.s),
        child: Wrap(spacing: Space.s, runSpacing: Space.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (saved) ...[
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(AppIcons.check, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: Space.xs),
              Flexible(
                child: Text(l10n.tr('groupSaved').replaceAll('{name}', g.name),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            ]),
            TextButton(onPressed: () => _openGroup(g), child: Text(l10n.tr('snackOpen'))),
          ] else
            FilledButton.tonalIcon(
              onPressed: () => _saveGroup(g),
              icon: const Icon(AppIcons.group, size: 18),
              label: Text(l10n.tr('saveGroup')),
            ),
        ]),
      ));
    }

    for (final c in widget.contacts) {
      final lines = [
        if (c.email.isNotEmpty) c.email,
        if ((c.phoneMobile ?? '').isNotEmpty) c.phoneMobile!,
        if ((c.phoneWork ?? '').isNotEmpty) c.phoneWork!,
        [c.title, c.org].where((e) => (e ?? '').isNotEmpty).join(', '),
      ].where((e) => e.isNotEmpty).toList();
      children.add(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(AppIcons.person),
        title: Text(c.displayName, style: theme.textTheme.titleSmall),
        subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
      ));
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            onPressed: () => showContactEditor(context, card: c),
            icon: const Icon(AppIcons.person_add, size: 18),
            label: Text(l10n.tr('addContact')),
          ),
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.cardAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

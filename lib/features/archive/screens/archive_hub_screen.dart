// lib/features/archive/screens/archive_hub_screen.dart
// Весь архив Ogneliss (1.8.14, просьба владельца 29.10.2026): в архиве —
// несколько ящиков, папки у них разные и устроены по-разному. В меню
// теперь видно только архив выбранного ящика, а здесь — весь архив, как
// «Файлы» для вложений: поиск по всем письмам, сводка, каждый ящик со своими
// папками, встречами, задачами и контактами — и ящики, которых в приложении
// уже нет.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_db.dart';
import '../../../services/archive/archive_vault.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/help_hint.dart';
import '../../../widgets/ui/section_band.dart';
import '../archive_providers.dart';
import '../archive_sheets.dart';

class ArchiveHubScreen extends ConsumerStatefulWidget {
  const ArchiveHubScreen({super.key});

  @override
  ConsumerState<ArchiveHubScreen> createState() => _ArchiveHubScreenState();
}

class _ArchiveHubScreenState extends ConsumerState<ArchiveHubScreen> {
  final _search = TextEditingController();

  /// Свёрнутые ветки: папки (id) и ящики («a:id»).
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _find(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    unawaited(context.push('/archive/search?q=${Uri.encodeQueryComponent(t)}'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vault = ref.watch(archiveVaultProvider).value;
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: Text(l10n.tr('ognaArchive')),
          actions: [
            HelpButton(title: l10n.tr('archiveAll'), text: l10n.tr('archiveHubHelp')),
            IconButton(
              tooltip: l10n.tr('settings'),
              icon: const Icon(AppIcons.settings),
              onPressed: () => context.push('/settings/archive'),
            ),
          ],
        ),
      ),
      body: vault == null || !vault.exists
          ? _Note(icon: AppIcons.inventory_2, text: l10n.tr('archiveEmpty'))
          : !vault.isOpen
              ? _Note(
                  icon: AppIcons.lock,
                  text: l10n.tr('archiveLockedIntro'),
                  action: FilledButton.icon(
                    onPressed: () => showArchiveUnlockSheet(context),
                    icon: const Icon(AppIcons.lock_open),
                    label: Text(l10n.tr('archiveOpen')),
                  ),
                )
              : _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    final accounts = ref.watch(archiveAccountsProvider).value ?? const <ArchiveAccountInfo>[];
    final folders = ref.watch(archiveFoldersProvider).value ?? const <ArchiveFolder>[];
    final counts = ref.watch(archiveItemCountsProvider).value ?? const {};
    final stats = ref.watch(archiveStatsProvider).value;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
        child: TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(AppIcons.search),
            hintText: l10n.tr('archiveSearchHint'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _find,
        ),
      ),
      if (stats != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                l10n
                    .tr('archiveStatMail')
                    .replaceAll('{n}', AppDateFormat.number(context, stats.messages))
                    .replaceAll('{files}', AppDateFormat.number(context, stats.attachments))
                    .replaceAll('{size}', AppDateFormat.bytes(context, stats.attachmentBytes)),
                style: muted),
            if (stats.oldest != null && stats.newest != null)
              Text(
                  l10n
                      .tr('archiveStatPeriod')
                      .replaceAll('{from}', AppDateFormat.date(context, stats.oldest!))
                      .replaceAll('{to}', AppDateFormat.date(context, stats.newest!)),
                  style: muted),
          ]),
        ),
    ];

    for (final a in accounts) {
      final tree = ArchiveFolderTree.build(folders, a.id);
      final c = counts[a.id];
      if (tree.roots.isEmpty && (c == null || c.events + c.tasks + c.contacts == 0)) continue;
      final key = 'a:${a.id}';
      final open = !_collapsed.contains(key);
      children.add(InkWell(
        onTap: () => setState(() => open ? _collapsed.add(key) : _collapsed.remove(key)),
        child: SectionBand(
          title: a.label,
          count: a.messages,
          trailing: Icon(open ? AppIcons.expand_less : AppIcons.expand_more, size: 20, color: AppColors.mutedText(context)),
        ),
      ));
      if (!open) continue;
      if (a.label != a.email) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
          child: Text(a.email, style: muted),
        ));
      }
      for (final f in tree.roots) {
        children.addAll(_branch(tree, f, 0, l10n));
      }
      final q = '?accounts=${archiveAccountsQuery({a.id})}';
      if (c != null && c.events > 0) {
        children.add(_row(AppIcons.event, l10n.tr('archiveKindEvents'), c.events, () => context.push('/archive/items/events$q')));
      }
      if (c != null && c.tasks > 0) {
        children.add(_row(AppIcons.check_box, l10n.tr('archiveKindTasks'), c.tasks, () => context.push('/archive/items/tasks$q')));
      }
      if (c != null && c.contacts > 0) {
        children.add(
            _row(AppIcons.contacts, l10n.tr('archiveKindContacts'), c.contacts, () => context.push('/archive/items/contacts$q')));
      }
    }
    if (children.length <= 2 && (stats?.messages ?? 0) == 0) {
      children.add(_Note(icon: AppIcons.inventory_2, text: l10n.tr('archiveEmpty')));
    }
    children.add(const SizedBox(height: Space.xl));
    return ListView(children: children);
  }

  Iterable<Widget> _branch(ArchiveFolderTree tree, ArchiveFolder f, int depth, AppLocalizations l10n) sync* {
    final kids = tree.children[f.id] ?? const <ArchiveFolder>[];
    final key = '${f.id}';
    final open = !_collapsed.contains(key);
    yield _row(
      archiveFolderIcon(f),
      archiveFolderLabel(f, l10n),
      tree.branchCount[f.id] ?? f.count,
      () => context.push('/archive/folder/${f.id}'),
      depth: depth,
      expand: kids.isEmpty ? null : open,
      onExpand: () => setState(() => open ? _collapsed.add(key) : _collapsed.remove(key)),
    );
    if (!open) return;
    for (final c in kids) {
      yield* _branch(tree, c, depth + 1, l10n);
    }
  }

  Widget _row(IconData icon, String label, int count, VoidCallback onTap,
      {int depth = 0, bool? expand, VoidCallback? onExpand}) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.l + depth * Space.l, Space.s, Space.s, Space.s),
        child: Row(children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: Space.m),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyLarge)),
          if (count > 0) Text(AppDateFormat.number(context, count), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          SizedBox(
            width: 40,
            child: expand == null
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(expand ? AppIcons.expand_less : AppIcons.expand_more, size: 20, color: muted),
                    onPressed: onExpand,
                  ),
          ),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const _Note({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppColors.mutedText(context)),
          const SizedBox(height: Space.m),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: Space.l), action!],
        ]),
      ),
    );
  }
}

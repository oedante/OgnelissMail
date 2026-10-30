// lib/features/archive/screens/archive_hub_screen.dart
// Весь архив Ogneliss (1.8.12, замечание владельца 29.10.2026): в одном
// архиве — данные нескольких ящиков, и папки у них свои и по-разному
// устроены. В меню ящика остаётся только его архив, а весь архив — здесь,
// по аналогии с «Файлами»: ящики — отбором сверху, у каждого ящика — его
// папки, встречи, задачи и контакты.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_db.dart';
import '../../../services/archive/archive_vault.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/section_band.dart';
import '../archive_providers.dart';
import '../archive_sheets.dart' show showArchiveUnlockSheet;

class ArchiveHubScreen extends ConsumerStatefulWidget {
  const ArchiveHubScreen({super.key});

  @override
  ConsumerState<ArchiveHubScreen> createState() => _ArchiveHubScreenState();
}

class _ArchiveHubScreenState extends ConsumerState<ArchiveHubScreen> {
  /// Показан только этот ящик архива; null — все.
  String? _only;

  /// Свёрнутые папки (id папки архива).
  final Set<int> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vault = ref.watch(archiveVaultProvider).value;
    final accounts = ref.watch(archiveAccountsProvider).value ?? const <ArchiveAccountInfo>[];
    final stats = ref.watch(archiveStatsProvider).value;
    final subtitle = stats == null || stats.messages == 0 ? null : l10n.plural('archiveNMails', stats.messages);
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.tr('archiveWhole')),
            if (subtitle != null)
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
          ]),
          actions: [
            if (vault?.isOpen ?? false)
              IconButton(
                tooltip: l10n.tr('archiveSearchTitle'),
                icon: const Icon(AppIcons.search),
                onPressed: () => context.push('/archive/search'),
              ),
            IconButton(
              tooltip: l10n.tr('settings'),
              icon: const Icon(AppIcons.settings),
              onPressed: () => context.push('/settings/archive'),
            ),
          ],
        ),
      ),
      body: vault == null || !vault.exists
          ? _hint(context, l10n.tr('archiveEmptyDrawer'), () => context.push('/settings/archive'))
          : !vault.isOpen
              ? _hint(context, l10n.tr('archiveOpen'), () => showArchiveUnlockSheet(context), icon: AppIcons.lock)
              : _content(context, l10n, theme, accounts),
    );
  }

  Widget _hint(BuildContext context, String text, VoidCallback onTap, {IconData icon = AppIcons.inventory_2}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: FilledButton.tonalIcon(onPressed: onTap, icon: Icon(icon), label: Text(text)),
        ),
      );

  Widget _content(BuildContext context, AppLocalizations l10n, ThemeData theme, List<ArchiveAccountInfo> accounts) {
    final folders = ref.watch(archiveFoldersProvider).value ?? const <ArchiveFolder>[];
    final shown = [
      for (final a in accounts)
        if (!a.isEmpty && (_only == null || _only == a.id)) a,
    ];
    final rows = <Widget>[];
    for (final a in shown) {
      rows.add(SectionBand(title: a.label, count: a.messages));
      final tree = ArchiveFolderTree.build(folders, a.id);
      for (final f in tree.roots) {
        rows.addAll(_branch(context, l10n, tree, f, 0));
      }
      void item(String kind, IconData icon, String label, int n) {
        if (n <= 0) return;
        rows.add(ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(label),
          trailing: Text('$n', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
          onTap: () => context.push(Uri(path: '/archive/items/$kind', queryParameters: {'account': a.id}).toString()),
        ));
      }

      item('events', AppIcons.event, l10n.tr('archiveKindEvents'), a.events);
      item('tasks', AppIcons.check_box, l10n.tr('archiveKindTasks'), a.tasks);
      item('contacts', AppIcons.contacts, l10n.tr('archiveKindContacts'), a.contacts);
    }
    return Column(children: [
      if (accounts.where((a) => !a.isEmpty).length > 1) _chips(context, l10n, accounts),
      Expanded(
        child: rows.isEmpty
            ? Center(
                child: Text(l10n.tr('archiveFolderEmpty'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
              )
            : ListView(padding: const EdgeInsets.only(bottom: Space.l), children: rows),
      ),
    ]);
  }

  /// Отбор по ящикам: «Все ящики» и каждый ящик архива.
  Widget _chips(BuildContext context, AppLocalizations l10n, List<ArchiveAccountInfo> accounts) {
    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: Space.s),
          child: FilterChip(
            visualDensity: VisualDensity.compact,
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => onTap(),
            label: Text(label, overflow: TextOverflow.ellipsis),
          ),
        );
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
        children: [
          chip(l10n.tr('ruleAllAccounts'), _only == null, () => setState(() => _only = null)),
          for (final a in accounts)
            if (!a.isEmpty) chip(a.label, _only == a.id, () => setState(() => _only = _only == a.id ? null : a.id)),
        ],
      ),
    );
  }

  Iterable<Widget> _branch(
      BuildContext context, AppLocalizations l10n, ArchiveFolderTree tree, ArchiveFolder f, int depth) sync* {
    final theme = Theme.of(context);
    final kids = tree.children[f.id] ?? const <ArchiveFolder>[];
    final collapsed = _collapsed.contains(f.id);
    final n = tree.branchCount[f.id] ?? f.count;
    yield ListTile(
      contentPadding: EdgeInsetsDirectional.only(start: Space.l + depth * Space.l, end: Space.s),
      leading: Icon(archiveFolderIcon(f), color: theme.colorScheme.onSurfaceVariant),
      title: Text(archiveFolderLabel(f, l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (n > 0) Text('$n', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
        if (kids.isNotEmpty)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(collapsed ? AppIcons.expand_more : AppIcons.expand_less, size: 20),
            onPressed: () => setState(() => collapsed ? _collapsed.remove(f.id) : _collapsed.add(f.id)),
          )
        else
          const SizedBox(width: Space.xl),
      ]),
      onTap: () => context.push('/archive/folder/${f.id}'),
    );
    if (collapsed) return;
    for (final c in kids) {
      yield* _branch(context, l10n, tree, c, depth + 1);
    }
  }
}

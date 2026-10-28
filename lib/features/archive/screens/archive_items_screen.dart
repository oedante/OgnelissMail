// lib/features/archive/screens/archive_items_screen.dart
// Встречи, задачи и контакты в архиве Ogneliss (1.7.3) — списком, с
// поиском по названию. Подробности — шторкой (всё, что сохранено).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_db.dart';
import '../../../services/archive/archive_vault.dart';
import '../archive_providers.dart' show archiveRevisionProvider;
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';

/// Что показывать: events, tasks, contacts.
final _itemsProvider = FutureProvider.autoDispose.family<List<ArchiveItem>, String>((ref, kind) async {
  ref.watch(archiveRevisionProvider);
  final db = ref.watch(archiveDbProvider);
  if (db == null) return const [];
  return switch (kind) {
    'events' => db.events(),
    'tasks' => db.tasks(),
    _ => db.contacts(),
  };
});

class ArchiveItemsScreen extends ConsumerStatefulWidget {
  final String kind;
  const ArchiveItemsScreen({super.key, required this.kind});

  @override
  ConsumerState<ArchiveItemsScreen> createState() => _ArchiveItemsScreenState();
}

class _ArchiveItemsScreenState extends ConsumerState<ArchiveItemsScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) => switch (widget.kind) {
        'events' => l10n.tr('archiveKindEvents'),
        'tasks' => l10n.tr('archiveKindTasks'),
        _ => l10n.tr('archiveKindContacts'),
      };

  IconData get _icon => switch (widget.kind) {
        'events' => AppIcons.event,
        'tasks' => AppIcons.check_box,
        _ => AppIcons.person,
      };

  void _details(ArchiveItem it) {
    final l10n = AppLocalizations.of(context);
    Map<String, dynamic> data = const {};
    try {
      data = (jsonDecode(it.dataJson ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {}
    String? text(String k) {
      final v = data[k];
      if (v == null) return null;
      final s = '$v'.trim();
      return s.isEmpty ? null : s;
    }

    String? when(String k) {
      final v = data[k];
      if (v is! num) return null;
      return AppDateFormat.dateTime(context, DateTime.fromMillisecondsSinceEpoch(v.toInt()));
    }

    final rows = <(String, String)>[
      if (widget.kind == 'events') ...[
        if (when('startTime') != null) (l10n.tr('archiveItemStart'), when('startTime')!),
        if (when('endTime') != null) (l10n.tr('archiveItemEnd'), when('endTime')!),
        if (text('location') != null) (l10n.tr('location'), text('location')!),
        if (text('organizerEmail') != null) (l10n.tr('organizer'), text('organizerEmail')!),
        if (text('description') != null) (l10n.tr('description'), text('description')!),
      ],
      if (widget.kind == 'tasks') ...[
        if (when('dueDate') != null) (l10n.tr('archiveItemDue'), when('dueDate')!),
        if (when('completedAt') != null) (l10n.tr('archiveItemDone'), when('completedAt')!),
        if (text('description') != null) (l10n.tr('description'), text('description')!),
      ],
      if (widget.kind == 'contacts') ...[
        if (text('email') != null) ('E-mail', text('email')!),
        if (text('phoneMobile') != null) (l10n.tr('archiveItemMobile'), text('phoneMobile')!),
        if (text('phoneWork') != null) (l10n.tr('archiveItemWorkPhone'), text('phoneWork')!),
        if (text('company') != null) (l10n.tr('company'), text('company')!),
        if (text('jobTitle') != null) (l10n.tr('jobTitle'), text('jobTitle')!),
        if (text('notes') != null) (l10n.tr('notes'), text('notes')!),
      ],
    ];
    showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
            children: [
              Text(it.title.isEmpty ? l10n.tr('noSubject') : it.title, style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.s),
              for (final (k, v) in rows)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: theme.textTheme.labelMedium?.copyWith(color: AppColors.mutedText(ctx))),
                    SelectableText(v, style: theme.textTheme.bodyMedium),
                  ]),
                ),
              const SizedBox(height: Space.m),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(AppIcons.content_copy, size: 18),
                  label: Text(l10n.tr('copy')),
                  onPressed: () => Clipboard.setData(ClipboardData(
                      text: [it.title, for (final (k, v) in rows) '$k: $v'].join('\n'))),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = ref.watch(_itemsProvider(widget.kind));
    final q = _q.text.trim().toLowerCase();
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_title(l10n)),
            Text(l10n.tr('ognaArchive'),
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
          ]),
        ),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          final list = q.isEmpty
              ? all
              : [for (final i in all) if ('${i.title} ${i.subtitle}'.toLowerCase().contains(q)) i];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
              child: TextField(
                controller: _q,
                decoration: InputDecoration(
                  prefixIcon: const Icon(AppIcons.search),
                  hintText: l10n.search,
                  isDense: true,
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.tr('clear'),
                          icon: const Icon(AppIcons.close),
                          onPressed: () => setState(_q.clear),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(l10n.tr(q.isEmpty ? 'archiveFolderEmpty' : 'archiveSearchNothing'),
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final it = list[i];
                        final at = it.at;
                        final sub = [
                          if (at != null) AppDateFormat.dateTime(context, at),
                          if (it.subtitle.isNotEmpty) it.subtitle,
                        ].join(' · ');
                        return ListTile(
                          leading: Icon(_icon, color: theme.colorScheme.primary),
                          title: Text(it.title.isEmpty ? l10n.tr('noSubject') : it.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: sub.isEmpty ? null : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _details(it),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

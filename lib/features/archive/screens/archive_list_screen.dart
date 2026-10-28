// lib/features/archive/screens/archive_list_screen.dart
// Письма папки архива Ogneliss и поиск по архиву (1.7.3). Папка — из меню
// (раздел «Архив Ogneliss»), поиск — из поиска почты («В архиве Ogneliss:
// N») или кнопкой поиска здесь.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/avatar_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_db.dart';
import '../../../services/archive/archive_vault.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../archive_providers.dart';
import '../archive_sheets.dart';
import '../../../core/theme/ogneliss_look.dart';

class ArchiveListScreen extends ConsumerStatefulWidget {
  /// Папка архива; null — поиск по всему архиву.
  final int? folderId;
  final String? query;
  const ArchiveListScreen({super.key, this.folderId, this.query});

  @override
  ConsumerState<ArchiveListScreen> createState() => _ArchiveListScreenState();
}

class _ArchiveListScreenState extends ConsumerState<ArchiveListScreen> {
  static const _page = 100;

  late final _search = TextEditingController(text: widget.query ?? '');
  late bool _searching = widget.folderId == null;
  final _scroll = ScrollController();
  Timer? _debounce;

  List<ArchiveMessageHead> _items = const [];
  bool _loading = true;
  bool _more = false;
  int _seq = 0;
  int _revision = -1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_more && !_loading && _scroll.position.extentAfter < 600) unawaited(_load(append: true));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String get _q => _search.text.trim();

  Future<void> _load({bool append = false}) async {
    final db = ref.read(archiveDbProvider);
    final seq = ++_seq;
    if (db == null) {
      setState(() {
        _items = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      List<ArchiveMessageHead> got;
      if (_searching && _q.isNotEmpty) {
        got = await db.search(_q);
        _more = false;
      } else if (widget.folderId != null && !_searching) {
        got = await db.messages(widget.folderId!, limit: _page, offset: append ? _items.length : 0);
        _more = got.length == _page;
      } else {
        got = const [];
        _more = false;
      }
      if (!mounted || seq != _seq) return;
      setState(() => _items = append ? [..._items, ...got] : got);
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _items = const []);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _onQuery(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) unawaited(_load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vault = ref.watch(archiveVaultProvider).value;
    // Записали новое (архивация идёт) или открыли архив — перечитать.
    final rev = vault?.revision ?? 0;
    if (rev != _revision) {
      _revision = rev;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
    final folders = ref.watch(archiveFoldersProvider).value ?? const <ArchiveFolder>[];
    final folder = folders.where((f) => f.id == widget.folderId).firstOrNull;
    final title = folder == null ? l10n.tr('archiveSearchTitle') : archiveFolderLabel(folder, l10n);

    final locked = vault != null && !vault.isOpen;
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: _searching
              ? TextField(
                  controller: _search,
                  autofocus: (widget.query ?? '').isEmpty,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.tr('archiveSearchHint'),
                    border: InputBorder.none,
                  ),
                  onChanged: _onQuery,
                  onSubmitted: (_) => _load(),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    folder == null ? l10n.tr('ognaArchive') : '${l10n.tr('ognaArchive')} · ${folder.path.replaceAll('/', ' › ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
                  ),
                ]),
          actions: [
            if (widget.folderId != null)
              IconButton(
                tooltip: _searching ? l10n.tr('cancel') : l10n.search,
                icon: Icon(_searching ? AppIcons.close : AppIcons.search),
                onPressed: () {
                  setState(() {
                    _searching = !_searching;
                    if (!_searching) _search.clear();
                  });
                  unawaited(_load());
                },
              ),
          ],
        ),
      ),
      body: locked
          ? _Locked(onOpen: () => showArchiveUnlockSheet(context))
          : _body(l10n, theme),
    );
  }

  Widget _body(AppLocalizations l10n, ThemeData theme) {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      final text = _searching
          ? (_q.isEmpty ? l10n.tr('archiveSearchHint') : l10n.tr('archiveSearchNothing'))
          : l10n.tr('archiveFolderEmpty');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      itemCount: _items.length + (_more ? 1 : 0),
      separatorBuilder: (_, __) => RowDivider(indent: 72, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(Space.l),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        return ArchiveMessageTile(
          head: _items[i],
          showFolder: _searching,
          onTap: () async {
            await context.push('/archive/message/${_items[i].id}');
            // Прочитано, удалено из архива — список обновится по revision.
          },
        );
      },
    );
  }
}

class _Locked extends StatelessWidget {
  final VoidCallback onOpen;
  const _Locked({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.lock, size: 48, color: AppColors.mutedText(context)),
          const SizedBox(height: Space.m),
          Text(l10n.tr('archiveLockedIntro'), textAlign: TextAlign.center),
          const SizedBox(height: Space.l),
          FilledButton.icon(onPressed: onOpen, icon: const Icon(AppIcons.lock_open), label: Text(l10n.tr('archiveOpen'))),
        ]),
      ),
    );
  }
}

/// Строка письма архива: отправитель, тема, начало текста, дата.
class ArchiveMessageTile extends StatelessWidget {
  final ArchiveMessageHead head;
  final bool showFolder;
  final VoidCallback onTap;
  const ArchiveMessageTile({super.key, required this.head, required this.onTap, this.showFolder = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final from = head.fromLabel.isEmpty ? l10n.tr('noSender') : head.fromLabel;
    final unread = !head.isRead;
    final subject = head.subject.trim().isEmpty ? l10n.tr('noSubject') : head.subject.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HeroEmailAvatar(
            emailId: 'ogna_${head.id}',
            hero: false,
            radius: 20,
            initial: from.characters.first.toUpperCase(),
            color: Color(avatarColorValue(head.fromEmail.isEmpty ? from : head.fromEmail)),
            email: head.fromEmail,
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (head.hasAttachments) Icon(AppIcons.attach_file, size: 16, color: muted),
                const SizedBox(width: Space.xs),
                Text(AppDateFormat.listStamp(context, head.date), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ]),
              const SizedBox(height: 2),
              Text(subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: unread ? FontWeight.w600 : null)),
              if (head.preview.trim().isNotEmpty)
                Text(head.preview.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              if (showFolder && head.folderPath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(children: [
                    Icon(AppIcons.folder, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(head.folderPath.replaceAll('/', ' › '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                    ),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

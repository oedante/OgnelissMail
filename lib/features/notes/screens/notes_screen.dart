// lib/features/notes/screens/notes_screen.dart
// Экран списка заметок. Соответствует эталону (Apps → Notes):
// заголовок, поиск, пустое состояние «No Notes», синяя FAB «+».

import '../../../widgets/ui/section_band.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../widgets/navigation/app_bottom_bar.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/empty_state.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/database/app_database.dart';
import '../providers/notes_provider.dart';
import '../../settings/providers/module_settings_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../widgets/common/peek_card.dart';
import '../../../widgets/common/quick_long_press.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/adaptive_layout.dart' show Breakpoints;
import 'note_edit_screen.dart';
import '../../../core/theme/ogneliss_look.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  String _search = '';

  /// Заметка в панели справа (планшет, широкое окно): id (null — новая) и
  /// номер открытия — новый номер пересоздаёт редактор.
  ({String? id, int gen})? _pane;
  int _gen = 0;
  double _bodyWidth = 0;

  /// Открыть заметку: на широком экране — справа от списка, на телефоне —
  /// отдельным экраном (как раньше).
  void _open(String? id) {
    if (_bodyWidth >= Breakpoints.tablet) {
      setState(() => _pane = (id: id, gen: ++_gen));
      return;
    }
    context.push('/notes/edit', extra: id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notesAsync = ref.watch(notesProvider);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('notes')),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.search),
            tooltip: l10n.search,
            onPressed: () => _showSearch(context, l10n),
          ),
        ],
      )),
      body: LayoutBuilder(builder: (context, c) {
        _bodyWidth = c.maxWidth;
        final list = _listBody(notesAsync, theme, l10n);
        final pane = _pane;
        if (pane == null || c.maxWidth < Breakpoints.tablet) return list;
        return Row(children: [
          Expanded(child: list),
          VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
          SizedBox(
            width: (c.maxWidth * 0.5).clamp(360.0, 640.0),
            child: NoteEditScreen(
              key: ValueKey('note_pane_${pane.gen}'),
              noteId: pane.id,
              onDone: () => setState(() => _pane = null),
            ),
          ),
        ]);
      }),
      // На телефоне «Новая заметка» — в центре нижней панели.
      floatingActionButton: AppBottomBar.inUse(context)
          ? null
          : FloatingActionButton(
              tooltip: AppLocalizations.of(context).tr('newNote'),
              onPressed: () => _open(null),
              child: const Icon(AppIcons.add),
            ),
    );
  }

  Widget _listBody(AsyncValue<List<Note>> notesAsync, ThemeData theme, AppLocalizations l10n) {
    return notesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${l10n.tr('error')}: $e')),
        data: (notes) {
          final filtered = _search.isEmpty
              ? notes
              : notes.where((n) =>
                  n.title.toLowerCase().contains(_search) ||
                  n.body.toLowerCase().contains(_search)).toList();

          if (filtered.isEmpty) {
            return _buildEmptyState(theme, l10n);
          }

          // По времени правки — разделами-полосами, как в боковом меню
          // (10.10.2026): «Сегодня», «На этой неделе», «Раньше».
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final weekAgo = today.subtract(const Duration(days: 6));
          // Группы — по той же дате, по которой отсортирован список.
          final byModified = ref.watch(moduleSettingsProvider).notesSortByModified;
          String group(Note n) {
            final m = (byModified ? n.modifiedAt : n.createdAt).toLocal();
            if (!m.isBefore(today)) return l10n.tr('today');
            if (!m.isBefore(weekAgo)) return l10n.tr('thisWeek');
            return l10n.tr('notesEarlier');
          }
          final rows = <Widget>[];
          String? last;
          for (final n in filtered) {
            final g = group(n);
            if (g != last) {
              rows.add(SectionBand(title: g, count: filtered.where((x) => group(x) == g).length));
              last = g;
            } else {
              rows.add(const RowDivider(indent: Space.l, endIndent: Space.l));
            }
            rows.add(_noteTile(n, theme, l10n));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: rows,
          );
        },
      );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) =>
      EmptyState(icon: AppIcons.sticky_note_2, title: l10n.tr('noNotes'));

  Widget _noteTile(Note note, ThemeData theme, AppLocalizations l10n) {
    final title = note.title.trim().isNotEmpty
        ? note.title.trim()
        : (note.body.trim().split('\n').first.trim().isNotEmpty
            ? note.body.trim().split('\n').first.trim()
            : l10n.tr('untitled'));
    // Настройка «Предпросмотр текста» (раньше ни на что не влияла).
    final showPreview = ref.watch(moduleSettingsProvider).notesPreviewLines;
    final preview = showPreview ? note.body.replaceAll('\n', ' ').trim() : '';
    final modified = DateFormat('d MMM, HH:mm', l10n.localeCode)
        .format(note.modifiedAt.toLocal());

    // Удержание — карточка заметки с кнопками (1.7.0, как у писем, встреч и
    // контактов); раньше — шторка «Изменить / Удалить».
    return Builder(builder: (tileCtx) => QuickLongPress(
      onLongPress: () => _peek(tileCtx, note, title, l10n),
      pressEffect: true,
      child: ListTile(
      leading: CircleAvatar(
        backgroundColor: note.colorValue != null
            ? Color(note.colorValue!)
            : theme.colorScheme.primaryContainer,
        child: Icon(AppIcons.sticky_note_2,
            color: note.colorValue != null
                ? Colors.white
                : theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        preview.isEmpty ? modified : '$preview\n$modified',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: preview.isNotEmpty,
      selected: _pane?.id == note.id && _pane != null,
      onTap: () => _open(note.id),
    ),
    ));
  }

  /// Карточка заметки по удержанию: текст целиком (до 8 строк), кнопки —
  /// изменить, отправить письмом, поделиться, копировать; «Ещё» — по
  /// группам, с удалением.
  void _peek(BuildContext tileCtx, Note note, String title, AppLocalizations l10n) {
    unawaited(HapticFeedback.mediumImpact());
    final text = [if (note.title.trim().isNotEmpty) note.title.trim(), note.body.trim()]
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    void edit() => _open(note.id);
    void mail() => context.push(Uri(path: '/compose', queryParameters: {
          if (note.title.trim().isNotEmpty) 'subject': note.title.trim(),
          if (note.body.trim().isNotEmpty) 'body': note.body.trim(),
        }).toString());
    void share() => unawaited(SharePlus.instance.share(ShareParams(text: text, subject: title)));
    void copy() {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      unawaited(HapticFeedback.selectionClick());
    }

    unawaited(showPeekCard(
      context,
      anchor: peekAnchorOf(tileCtx),
      onOpen: edit,
      card: _NotePeekCard(note: note, title: title, locale: l10n.localeCode),
      moreLabel: l10n.tr('peekMore'),
      actions: [
        PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: edit),
        PeekAction(icon: AppIcons.mail, label: l10n.tr('noteByEmail'), onTap: mail),
        PeekAction(icon: AppIcons.share, label: l10n.tr('share'), onTap: share),
        PeekAction(icon: AppIcons.content_copy, label: l10n.tr('copy'), onTap: copy),
      ],
      more: [
        PeekGroup(title: l10n.tr('peekGroupNote'), items: [
          PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: edit),
          PeekAction(icon: AppIcons.content_copy, label: l10n.tr('copy'), onTap: copy),
        ]),
        PeekGroup(title: l10n.tr('peekGroupSend'), items: [
          PeekAction(icon: AppIcons.mail, label: l10n.tr('noteByEmail'), onTap: mail),
          PeekAction(icon: AppIcons.share, label: l10n.tr('share'), onTap: share),
        ]),
        PeekGroup(items: [
          PeekAction(
            icon: AppIcons.delete,
            label: l10n.delete,
            color: AppColors.errorText(context),
            onTap: () => unawaited(_delete(note)),
          ),
        ]),
      ],
    ));
  }

  Future<void> _delete(Note note) async {
    if (_pane?.id == note.id) setState(() => _pane = null);
    await ref.read(notesNotifierProvider).delete(note.id);
    unawaited(HapticFeedback.mediumImpact());
  }

  void _showSearch(BuildContext context, AppLocalizations l10n) {
    showSearch(
      context: context,
      delegate: _NotesSearchDelegate(
        onQuery: (q) => setState(() => _search = q.toLowerCase()),
        hint: l10n.search,
      ),
    );
  }
}

class _NotesSearchDelegate extends SearchDelegate<String> {
  final void Function(String) onQuery;
  final String hint;
  _NotesSearchDelegate({required this.onQuery, required this.hint});

  @override
  String get searchFieldLabel => hint;

  @override
  List<Widget> buildActions(BuildContext context) =>
      [IconButton(tooltip: AppLocalizations.of(context).tr('clear'), icon: const Icon(AppIcons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(tooltip: AppLocalizations.of(context).tr('back'), icon: const Icon(AppIcons.arrow_back), onPressed: () => close(context, query));

  @override
  Widget buildResults(BuildContext context) {
    onQuery(query);
    close(context, query);
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    onQuery(query);
    return const SizedBox.shrink();
  }
}

/// Содержимое карточки заметки по удержанию.
class _NotePeekCard extends StatelessWidget {
  final Note note;
  final String title;
  final String locale;
  const _NotePeekCard({required this.note, required this.title, required this.locale});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final body = note.body.trim();
    final accent = note.colorValue != null ? Color(note.colorValue!) : theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(AppIcons.sticky_note_2, size: Sizes.iconRow, color: accent),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(title,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
          ),
        ]),
        if (body.isNotEmpty && body != title) ...[
          const SizedBox(height: Space.s),
          Text(body, maxLines: 8, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Space.s),
        Text(DateFormat('d MMM yyyy, HH:mm', locale).format(note.modifiedAt.toLocal()),
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ]),
    );
  }
}

// lib/widgets/common/selection_toolbar.dart
// Toolbar для batch-операций при множественном выборе.
// Показывается вместо AppBar когда isSelectionMode = true.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../features/mail/providers/email_selection_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../services/mail/email_actions_service.dart';

class SelectionToolbar extends ConsumerWidget implements PreferredSizeWidget {
  const SelectionToolbar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(emailSelectionProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(emailSelectionProvider.notifier);

    return AppBar(
      backgroundColor: theme.colorScheme.primaryContainer,
      leading: IconButton(
        tooltip: l10n.tr('deselectAll'),
        icon: const Icon(AppIcons.close),
        onPressed: () {
          HapticFeedback.selectionClick();
          notifier.exitSelectionMode();
        },
      ),
      title: Text(
        '${selection.count} ${l10n.tr('selectedWord')}',
        style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
      ),
      actions: [
        // Выделить все
        IconButton(
          icon: const Icon(AppIcons.select_all),
          tooltip: l10n.tr('selectAll'),
          onPressed: () {
            HapticFeedback.selectionClick();
            final emails = ref.read(emailsProvider).emails;
            notifier.selectAll(emails);
          },
        ),
        // Прочитано
        IconButton(
          icon: const Icon(AppIcons.mark_email_read),
          tooltip: l10n.tr('markRead'),
          onPressed: () {
            HapticFeedback.selectionClick();
            _batchMarkRead(ref, notifier.getSelectedIds());
            notifier.exitSelectionMode();
          },
        ),
        // Флаг
        IconButton(
          icon: const Icon(AppIcons.flag),
          tooltip: l10n.tr('flag'),
          onPressed: () {
            HapticFeedback.selectionClick();
            _batchFlag(ref, notifier.getSelectedIds());
            notifier.exitSelectionMode();
          },
        ),
        // Переместить
        IconButton(
          icon: const Icon(AppIcons.drive_file_move),
          tooltip: l10n.tr('moveTo'),
          onPressed: () {
            HapticFeedback.selectionClick();
            // Показать выбор папки
            notifier.exitSelectionMode();
          },
        ),
        // Тег
        IconButton(
          icon: const Icon(AppIcons.label),
          tooltip: l10n.tr('addTag'),
          onPressed: () {
            HapticFeedback.selectionClick();
            notifier.exitSelectionMode();
          },
        ),
        // Удалить
        IconButton(
          icon: const Icon(AppIcons.delete),
          tooltip: l10n.delete,
          onPressed: () {
            HapticFeedback.heavyImpact();
            _batchDelete(ref, notifier.getSelectedIds());
            notifier.exitSelectionMode();
          },
        ),
      ],
    );
  }

  void _batchMarkRead(WidgetRef ref, List<String> ids) {
    final acc = ref.read(activeAccountProvider);
    if (acc == null || ids.isEmpty) return;
    final state = ref.read(emailsProvider);
    final folderId = state.emails.isNotEmpty ? state.emails.first.folderId : 'inbox';
    ref.read(emailActionsProvider).batchSetRead(acc, ids, folderId, true)
        .then((_) => ref.read(emailsProvider.notifier).refresh());
  }

  void _batchFlag(WidgetRef ref, List<String> ids) {
    final acc = ref.read(activeAccountProvider);
    if (acc == null || ids.isEmpty) return;
    final state = ref.read(emailsProvider);
    final folderId = state.emails.isNotEmpty ? state.emails.first.folderId : 'inbox';
    ref.read(emailActionsProvider).batchSetFlag(acc, ids, folderId, true)
        .then((_) => ref.read(emailsProvider.notifier).refresh());
  }

  void _batchDelete(WidgetRef ref, List<String> ids) {
    final acc = ref.read(activeAccountProvider);
    if (acc == null || ids.isEmpty) return;
    final state = ref.read(emailsProvider);
    final folderId = state.emails.isNotEmpty ? state.emails.first.folderId : 'inbox';
    ref.read(emailActionsProvider).batchDelete(acc, ids, folderId)
        .then((_) => ref.read(emailsProvider.notifier).refresh());
  }
}

// lib/features/mail/widgets/mail_drawer.dart
// Боковое меню:
// - Аватарки аккаунтов сверху (переключение)
// - Режим All Accounts (все в одной ленте)
// - Избранное: быстрые разделы (Все письма, Непрочитанные, С флагом, VIP,
//   Вложения — видимость настраивается) и избранные папки
// - Дерево папок: сворачиваемые ветки, у родителя — сумма непрочитанных
//   с подпапками
// - Добавить аккаунт
// - Контекстное меню на папках (очистить, переименовать)

import '../../../widgets/ui/section_band.dart';
import '../../../widgets/ui/theme_quick_switch.dart' show ThemeQuickSwitch;
import '../../../widgets/navigation/app_bottom_bar.dart' show AppBottomBar;
import '../../../core/utils/text_safe.dart';
import 'dart:async';
import '../../../core/theme/app_icons.dart';

import 'package:flutter/material.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/common/hero_email_transition.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:badges/badges.dart' as badges;
import 'package:drift/drift.dart' hide Column;

import '../../../core/theme/app_theme.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/utils/folder_subtree.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/providers/feature_flags_provider.dart';
import '../../../data/database/app_database.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/special_folders.dart';
import '../../../services/mail/transport_capabilities.dart';
import '../../../services/mail/folder_actions_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../services/sync/sync_service.dart';
import '../../../data/models/folder_model.dart';
import '../providers/mail_providers.dart';
import '../../../core/utils/folder_icons.dart';
import '../providers/startup_folder.dart';
import '../providers/drawer_prefs.dart';
import '../folder_order.dart';
import '../../settings/providers/account_groups_provider.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/help_hint.dart' show HelpButton;
import '../../../data/models/email_model.dart';
import '../../../services/mail/email_actions_service.dart' show emailActionsProvider;
import '../../../widgets/common/undo_manager.dart';
import '../../../services/archive/archive_db.dart' show ArchiveFolder, ArchiveAccountInfo;
import '../../../services/archive/archive_runner.dart' show archiveRunnerProvider;
import '../../../services/archive/archive_vault.dart' show archiveVaultProvider;
import '../../archive/archive_providers.dart';
import '../../archive/archive_sheets.dart' show ensureArchiveReady, showArchiveUnlockSheet;
import '../../../services/archive/archive_settings.dart' show archiveSettingsProvider;
import '../../../core/theme/ogneliss_look.dart';
import '../../settings/screens/folder_sync_settings_screen.dart' show folderNotifyOffProvider;
import '../../../services/notifications/account_notify_mode.dart' show FolderNotify;
import '../../../widgets/common/peek_card.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class MailDrawer extends ConsumerWidget {
  /// Панель на широком окне (1.6.28): стоит слева от ленты постоянно, а не
  /// выезжает; выбор папки её не закрывает.
  final bool docked;

  const MailDrawer({super.key, this.docked = false});

  /// Закрыть выдвижное меню после выбора (у постоянной панели — ничего).
  void _close(BuildContext context) {
    if (docked) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider);
    final activeAccount = ref.watch(activeAccountProvider);
    final foldersAsync = ref.watch(foldersProvider);
    final isAllAccounts = ref.watch(allAccountsModeProvider);
    final groups = ref.watch(accountGroupsProvider);
    final activeGroupId = ref.watch(activeGroupIdProvider);

    final content = SafeArea(
        // Постоянная панель стоит справа от боковой полосы разделов:
        // системный отступ слева у неё уже учтён.
        left: !docked,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Папки — сверху и прокручиваются; «Избранное» — внизу, над
            // ящиками, под большим пальцем: частые разделы не нужно искать
            // вверху экрана (09.10.2026).
            // Разделы меню — «Папки», «Избранное», «Аккаунты» — с полосой-
            // заголовком на более тёмной подложке: раньше всё сливалось в
            // один список (замечание 09.10.2026).
            _DrawerBand(
              title: l10n.tr('folders'),
              // Планшет и компьютер (1.6.40): значок закрепления — меню
              // постоянной панелью слева или выдвижным. На телефоне не нужен.
              trailing: AppBottomBar.inUse(context)
                  ? null
                  : IconButton(
                      tooltip: l10n.tr(docked ? 'drawerUnpin' : 'drawerPin'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(AppIcons.push_pin,
                          size: 20,
                          fill: docked ? 1 : 0,
                          color: docked ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      onPressed: () {
                        unawaited(ref.read(drawerPinnedProvider.notifier).set(!docked));
                        if (!docked) Navigator.of(context).pop();
                      },
                    ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ..._buildFolderSection(context, ref, l10n, theme, foldersAsync),
                  // Архив Ogneliss — разделом под папками ящика (1.7.3).
                  ..._buildArchiveSection(context, ref, l10n, theme),
                ],
              ),
            ),
            // ── Избранное ──
            _DrawerBand(
              shadowUp: true,
              title: l10n.tr('favorites'),
              trailing: IconButton(
                tooltip: l10n.tr('favoritesEdit'),
                visualDensity: VisualDensity.compact,
                icon: Icon(AppIcons.tune, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                onPressed: () => _showFavoritesEditor(context),
              ),
            ),
            // Длинное избранное (группы, разделы, папки) не вытесняет дерево
            // папок: не выше 40 % экрана, дальше прокрутка.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: _buildFavorites(context, ref, l10n, accounts.length, groups, activeGroupId, isAllAccounts),
              ),
            ),
            // «Добавить аккаунт» убран из меню: он есть в настройках
            // («Аккаунты»), а здесь занимал строку внизу (замечание 06.10.2026).
            // Ящики — ВНИЗУ, под большим пальцем (как частые кнопки в Ogneliss
            // Dialer): раньше ряд аватарок был в самом верху меню, и до него
            // приходилось тянуться через весь экран (09.10.2026).
            // Один ящик — панель ящиков не нужна (10.10.2026): выбирать не из
            // чего, а настройки доступны через «Ещё».
            if (accounts.length > 1) ...[
              _DrawerBand(shadowUp: true, title: l10n.tr('accounts')),
              // ── Имя + email ──
              if (activeAccount != null && !isAllAccounts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(activeAccount.displayName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                      Text(activeAccount.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),

              if (isAllAccounts)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: Text(
                    l10n.tr('allAccounts'),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.accent(context)),
                  ),
                ),

              // ── Аватарки аккаунтов ──
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                child: Row(
                  children: [
                    // Аватарки
                    ...accounts.take(4).map((account) {
                      final isActive = account.id == activeAccount?.id && !isAllAccounts;
                      // Непрочитанные этого ящика (1.7.3, замечание владельца
                      // 25.10.2026): на значке «Почта» — сумма по всем ящикам,
                      // а здесь видно, где сколько.
                      final unread = ref.watch(unifiedUnreadByKeyProvider(account.id)).value ?? 0;
                      return Padding(
                        // Шире, чем раньше: число непрочитанных выступает за
                        // портрет справа.
                        padding: const EdgeInsets.only(right: Space.m),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            // Выбрали конкретный ящик — выходим из группы:
                            // иначе действовали бы два правила отбора сразу.
                            ref.read(activeGroupIdProvider.notifier).state = null;
                            ref.read(allAccountsModeProvider.notifier).state = false;
                            ref.read(settingsProvider.notifier).setActiveAccountId(account.id);
                            _close(context);
                          },
                          // Долгое нажатие — настройки этого ящика (раньше ничего).
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _close(context);
                            context.push('/settings/account/${Uri.encodeComponent(account.id)}');
                          },
                          // Активный ящик — цветной в тонком кольце ЦВЕТА ЯЩИКА,
                          // остальные — в оттенках серого. Раньше кольцо было
                          // акцентным цветом темы (в монохромной теме — чёрным) и
                          // толще; при одном ящике выглядело тяжёлой чёрной рамкой.
                          // В «Хабе аккаунтов» цветные все.
                          child: _withUnread(
                            context,
                            unread,
                            Container(
                              padding: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isActive
                                      ? Color(account.colorValue).withValues(alpha: 0.85)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: (isActive || isAllAccounts)
                                  ? _drawerAvatar(account)
                                  : Opacity(
                                      opacity: 0.75,
                                      child: ColorFiltered(colorFilter: _greyscale, child: _drawerAvatar(account)),
                                    ),
                            ),
                          ),
                        ),
                      );
                    }),

                    if (accounts.length > 4)
                      GestureDetector(
                        // Показать все аккаунты (в ряду помещается 4).
                        onTap: () {
                          _close(context);
                          context.push('/settings/accounts');
                        },
                        // Непрочитанные ящиков, которые в ряд не поместились.
                        child: _withUnread(
                          context,
                          ref.watch(unifiedUnreadByKeyProvider(
                                  [for (final a in accounts.skip(4)) if (a.isActive) a.id].join(',')))
                              .value ??
                              0,
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(AppIcons.more_horiz, size: 20),
                          ),
                        ),
                      ),

                    const Spacer(),
                    IconButton(tooltip: l10n.tr('settings'), icon: const Icon(AppIcons.settings), onPressed: () {
                      _close(context);
                      context.push('/settings');
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    if (docked) {
      return Material(color: theme.colorScheme.surfaceContainerLow, child: content);
    }
    return Drawer(child: content);
  }

  // ════════════════════════ ИЗБРАННОЕ ════════════════════════

  /// Группы аккаунтов, быстрые разделы (видимость — в настройке избранного)
  /// и избранные папки активного ящика.
  List<Widget> _buildFavorites(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      int accountCount, List<AccountGroup> groups, String? activeGroupId, bool isAllAccounts) {
    final hidden = ref.watch(hiddenQuickItemsProvider);
    final activeAccount = ref.watch(activeAccountProvider);
    final unified = ref.watch(unifiedModeProvider);
    final folderId = ref.watch(selectedFolderIdProvider);
    final filter = ref.watch(mailFilterProvider);
    final inUnifiedView = unified && folderId == null;

    void openFilter(MailFilter f) {
      ref.read(mailFilterProvider.notifier).state = f;
      ref.read(unifiedModeProvider.notifier).state = true;
      ref.read(selectedFolderIdProvider.notifier).state = null;
      _close(context);
    }

    final out = <Widget>[];

    // Группы аккаунтов: между «одним ящиком» и «всеми сразу».
    // Показываем только если группы созданы — иначе лишний раздел.
    for (final g in groups) {
      out.add(_FolderTile(
        icon: AppIcons.folder_shared,
        label: g.name,
        isSelected: activeGroupId == g.id,
        onTap: () {
          // Группа задаёт область для ВСЕХ модулей сразу — почты,
          // календаря, контактов, задач, сводки. Режимы «один/все»
          // при этом сбрасываем, чтобы не было двух правил разом.
          ref.read(activeGroupIdProvider.notifier).state = g.id;
          ref.read(allAccountsModeProvider.notifier).state = false;
          ref.read(unifiedModeProvider.notifier).state = true;
          ref.read(selectedFolderIdProvider.notifier).state = null;
          ref.read(mailFilterProvider.notifier).state = MailFilter.none;
          _close(context);
        },
      ));
    }

    // Все аккаунты (сводная лента) — с общим числом непрочитанных: это то же
    // число, что на значке вкладки «Почта».
    if (accountCount > 1 && !hidden.contains(DrawerQuickItem.allAccounts)) {
      out.add(_FolderTile(
        icon: AppIcons.all_inbox,
        label: l10n.tr('allAccounts'),
        count: ref.watch(totalUnreadCountProvider),
        isSelected: isAllAccounts && inUnifiedView && filter == MailFilter.none,
        onTap: () {
          // Выход из группы: «все аккаунты» шире любой группы.
          ref.read(activeGroupIdProvider.notifier).state = null;
          ref.read(allAccountsModeProvider.notifier).state = true;
          ref.read(unifiedModeProvider.notifier).state = true;
          ref.read(selectedFolderIdProvider.notifier).state = null;
          ref.read(mailFilterProvider.notifier).state = MailFilter.none;
          _close(context);
        },
      ));
    }

    // Вся почта одного ящика — с её непрочитанными.
    if (!hidden.contains(DrawerQuickItem.allMail)) {
      out.add(_FolderTile(
        icon: AppIcons.all_inbox,
        label: l10n.allMail,
        count: activeAccount == null
            ? null
            : ref.watch(unifiedUnreadByKeyProvider(activeAccount.id)).value,
        isSelected: !isAllAccounts && inUnifiedView && filter == MailFilter.none,
        onTap: () {
          unawaited(ref.read(startupFolderProvider.notifier).rememberSelection(
              accountId: ref.read(activeAccountProvider)?.id));
          ref.read(activeGroupIdProvider.notifier).state = null;
          ref.read(allAccountsModeProvider.notifier).state = false;
          ref.read(unifiedModeProvider.notifier).state = true;
          ref.read(selectedFolderIdProvider.notifier).state = null;
          ref.read(mailFilterProvider.notifier).state = MailFilter.none;
          _close(context);
        },
      ));
    }

    final quick = [
      (DrawerQuickItem.unread, AppIcons.mark_email_unread, 'unread', MailFilter.unread),
      (DrawerQuickItem.flagged, AppIcons.flag, 'flagged', MailFilter.flagged),
      if (ref.watch(settingsProvider).mailControl)
        (DrawerQuickItem.control, AppIcons.task_alt, 'controlFilter', MailFilter.control),
      (DrawerQuickItem.later, AppIcons.watch_later, 'laterFilter', MailFilter.later),
      (DrawerQuickItem.vip, AppIcons.star, 'vip', MailFilter.vip),
      (DrawerQuickItem.attachments, AppIcons.attach_file, 'attachments', MailFilter.attachments),
    ];
    for (final (item, icon, key, f) in quick) {
      if (hidden.contains(item)) continue;
      out.add(_FolderTile(
        icon: icon,
        label: l10n.tr(key),
        isSelected: inUnifiedView && filter == f,
        onTap: () => openFilter(f),
      ));
    }

    // «Разобрать непрочитанные» — только из избранного, включается в его
    // настройке (решение владельца 11.10.2026).
    if (!hidden.contains(DrawerQuickItem.triage)) {
      out.add(_FolderTile(
        icon: AppIcons.playlist_add_check,
        label: l10n.tr('triageTitle'),
        isSelected: false,
        onTap: () {
          _close(context);
          context.push('/triage');
        },
      ));
    }

    // «Мой день» — из бывшего «Ещё» (1.6.40).
    // На планшете и компьютере «Мой день», «Файловый хаб» и «Настройки» —
    // в боковой полосе разделов: в меню их не дублируем.
    final phone = AppBottomBar.inUse(context);
    if (phone && ref.watch(settingsProvider).myDay && !hidden.contains(DrawerQuickItem.myDay)) {
      out.add(_FolderTile(
        icon: AppIcons.myDay,
        label: l10n.tr('myDay'),
        isSelected: false,
        onTap: () {
          _close(context);
          context.go('/my-day');
        },
      ));
    }

    // «Файловый хаб» — все вложения всех писем (просили вынести в Избранное).
    final flags = ref.watch(featureFlagsProvider);
    if (phone && flags.showFileHub && !hidden.contains(DrawerQuickItem.fileHub)) {
      out.add(_FolderTile(
        icon: AppIcons.folder_copy,
        label: l10n.tr('fileHub'),
        isSelected: false,
        onTap: () {
          _close(context);
          context.push('/attachment-hub');
        },
      ));
    }

    // «Заметки» (в нижней панели их нет) и «Задачи», если их вкладка скрыта.
    // Раньше — отдельный раздел «Разделы» между избранным и папками.
    if (flags.showNotes && !hidden.contains(DrawerQuickItem.notes)) {
      out.add(_FolderTile(
        icon: AppIcons.sticky_note_2,
        label: l10n.tr('notes'),
        onTap: () {
          _close(context);
          context.push('/notes');
        },
      ));
    }
    if (_tasksInMenu(context, ref) && !hidden.contains(DrawerQuickItem.tasks)) {
      out.add(_FolderTile(
        icon: AppIcons.check_box,
        label: l10n.tasksLabel,
        onTap: () {
          _close(context);
          context.push('/tasks');
        },
      ));
    }

    // Избранные папки активного ящика.
    final folders = ref.watch(foldersProvider).value ?? const <FolderModel>[];
    final favs = folders.where((f) => f.isFavorite).toList()
      ..sort((a, b) => _localizedFolderName(a, l10n).toLowerCase()
          .compareTo(_localizedFolderName(b, l10n).toLowerCase()));
    if (favs.isNotEmpty) {
      final local = activeAccount == null
          ? const <String, int>{}
          : ref.watch(folderUnreadProvider(activeAccount.id)).value ?? const <String, int>{};
      final tree = _FolderTreeData.build(folders, local);
      for (final f in favs) {
        out.add(_FolderTile(
          icon: f.type == FolderType.custom ? (folderIconOf(f) == AppIcons.folder ? AppIcons.folder_special : folderIconOf(f)) : folderTypeIcon(f.type),
          label: _localizedFolderName(f, l10n),
          count: _displayCount(f, tree),
          countColor: f.type == FolderType.trash ? AppColors.errorRed : null,
          isSelected: !unified && folderId == f.id,
          onTap: () => _openFolder(context, ref, f),
          muted: ref.watch(folderNotifyOffProvider).contains(FolderNotify.key(f.accountId, f.id)),
          onLongPressAt: (anchor) => _showFolderActions(context, ref, f, l10n, anchor: anchor),
        ));
      }
    }

    // «Настройки» и выбор темы — из бывшего «Ещё» (1.6.40); тему можно
    // убрать в настройке избранного.
    if (phone && !hidden.contains(DrawerQuickItem.settings)) {
      out.add(_FolderTile(
        icon: AppIcons.settings,
        label: l10n.tr('settings'),
        isSelected: false,
        onTap: () {
          _close(context);
          context.push('/settings');
        },
      ));
    }
    if (!hidden.contains(DrawerQuickItem.theme)) {
      out.add(const Padding(
        padding: EdgeInsets.only(top: Space.xs, bottom: Space.s),
        child: ThemeQuickSwitch(),
      ));
    }
    return out;
  }

  /// «Задачи» в меню: на телефоне — если задачи включены (вкладки у них
  /// нет, раньше были в «Ещё»); на планшете — если их вкладка скрыта.
  static bool _tasksInMenu(BuildContext context, WidgetRef ref) {
    final on = ref.watch(featureFlagsProvider).showTasksTab;
    return AppBottomBar.inUse(context) ? on : !on;
  }

  /// Настройка избранного: какие быстрые разделы показывать и какие папки
  /// держать под рукой. Изменения применяются сразу.
  void _showFavoritesEditor(BuildContext context) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _FavoritesEditor(),
    );
  }

  // ════════════════════════ ДЕРЕВО ПАПОК ════════════════════════

  /// Число у папки: для корзины — всего писем (как раньше), для остальных —
  /// непрочитанные вместе с подпапками.
  static int? _displayCount(FolderModel f, _FolderTreeData tree) {
    if (f.type == FolderType.trash) return f.totalCount > 0 ? f.totalCount : null;
    final n = tree.total[f.id] ?? 0;
    return n > 0 ? n : null;
  }

  List<Widget> _buildFolderSection(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      ThemeData theme, AsyncValue<List<FolderModel>> foldersAsync) {
    final account = ref.watch(activeAccountProvider);
    return foldersAsync.when(
      loading: () => const [Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))],
      error: (_, __) => [Padding(padding: const EdgeInsets.all(Space.xl), child: Center(child: Text(l10n.tr('errorLoading'))))],
      data: (folders) {
        // Ящик только подключён — список папок ещё загружается (он первый
        // в очереди синхронизации): подсказка вместо пустоты.
        if (folders.isEmpty) {
          return [
            Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(height: Space.m),
                Text(l10n.tr('foldersLoading'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
              ]),
            ),
          ];
        }
        final local = account == null
            ? const <String, int>{}
            : ref.watch(folderUnreadProvider(account.id)).value ?? const <String, int>{};
        final collapsed = ref.watch(collapsedFoldersProvider);
        // 1.6.10: свой порядок папок и скрытие несинхронизируемых.
        final hide = account != null && ref.watch(hideUnsyncedFoldersProvider).contains(account.id);
        final order = ref.watch(folderOrderProvider);
        final tree = _FolderTreeData.build(hide ? withoutUnsynced(folders) : folders, local,
            order: order, accountId: account?.id);
        final canManage = account != null && TransportCapabilities.forAccount(account).serverFolders;
        final unified = ref.watch(unifiedModeProvider);
        final selectedId = unified ? null : ref.watch(selectedFolderIdProvider);

        Iterable<Widget> branch(FolderModel f, int depth) sync* {
          final kids = tree.children[f.id] ?? const <FolderModel>[];
          final isCollapsed = collapsed.contains(CollapsedFoldersNotifier.key(f.accountId, f.id));
          final tile = _FolderTile(
            icon: folderIconOf(f),
            label: _localizedFolderName(f, l10n),
            indent: depth,
            count: _displayCount(f, tree),
            countColor: f.type == FolderType.trash ? AppColors.errorRed : null,
            isSelected: selectedId == f.id,
            hasChildren: kids.isNotEmpty,
            expanded: !isCollapsed,
            onToggle: () => ref.read(collapsedFoldersProvider.notifier).toggle(f.accountId, f.id),
            onTap: () => _openFolder(context, ref, f),
            muted: ref.watch(folderNotifyOffProvider).contains(FolderNotify.key(f.accountId, f.id)),
            onLongPressAt: (anchor) => _showFolderActions(context, ref, f, l10n, anchor: anchor),
            // «Новая папка» — значком у «Входящих» (раньше строкой внизу меню).
            extra: canManage && depth == 0 && f.type == FolderType.inbox
                ? IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: l10n.tr('newFolder'),
                    icon: Icon(AppIcons.create_new_folder, size: 20, color: theme.colorScheme.primary),
                    onPressed: () => _createFolder(context, ref, l10n),
                  )
                : null,
          );
          // Постоянная панель (широкое окно): письмо из ленты можно
          // перетащить мышью на папку (1.6.28).
          yield docked ? _FolderDropTarget(folder: f, child: tile) : tile;
          if (isCollapsed) return;
          for (final c in kids) {
            yield* branch(c, depth + 1);
          }
        }

        // Одно дерево без разделов: системные папки, затем остальные корневые
        // (раньше — отдельный раздел «Папки» и строка «Создать папку» внизу),
        // или порядок, расставленный пользователем.
        return [
          for (final f in tree.roots) ...branch(f, 0),
          // «Рассылки» этого ящика — как папка в конце дерева, со значком
          // «?»: это не папка на сервере, а подборка по заголовку отписки
          // (10.10.2026; раньше — пункт «Ещё», общий для всех ящиков).
          if (account != null)
            _FolderTile(
              icon: AppIcons.campaign,
              label: l10n.tr('subscriptionsTitle'),
              extra: HelpButton(
                compact: true,
                title: l10n.tr('subscriptionsTitle'),
                text: l10n.tr('subscriptionsFolderHelp'),
              ),
              onTap: () {
                _close(context);
                context.push('/subscriptions?accountId=${Uri.encodeQueryComponent(account.id)}');
              },
            ),
          const SizedBox(height: Space.s),
        ];
      },
    );
  }

  // ════════════════════════ АРХИВ OGNELISS ════════════════════════

  /// Подключённый архив Ogneliss (1.7.3, просьба владельца 25.10.2026:
  /// «как раздел „Папки“, но архив»): папки архива по ящикам со структурой
  /// как в ящике, встречи, задачи и контакты. Закрытый архив — строкой
  /// «Открыть архив»; архива нет — раздела нет.
  List<Widget> _buildArchiveSection(BuildContext context, WidgetRef ref, AppLocalizations l10n, ThemeData theme) {
    final vault = ref.watch(archiveVaultProvider).value;
    if (vault == null || !vault.exists) return const [];
    // Шторку открываем от навигатора: выдвижное меню к тому времени закрыто.
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final running = ref.watch(archiveRunnerProvider.select((s) => s.running));
    final band = SectionBand(
      title: l10n.tr('ognaArchive'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.s),
            child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (vault.isOpen)
          IconButton(
            tooltip: l10n.tr('archiveSearchTitle'),
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.search, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            onPressed: () {
              _close(context);
              // Поиск по письмам выбранного ящика (1.8.14); весь архив — в
              // окне «Весь архив».
              final a = ref.read(activeAccountProvider);
              final ids = a == null
                  ? const <String>{}
                  : archiveAccountsOf(a, ref.read(archiveAccountsProvider).value ?? const <ArchiveAccountInfo>[]);
              context.push(ids.isEmpty ? '/archive/search' : '/archive/search?accounts=${archiveAccountsQuery(ids)}');
            },
          ),
        IconButton(
          tooltip: l10n.tr('settings'),
          visualDensity: VisualDensity.compact,
          icon: Icon(AppIcons.settings, size: 20, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          onPressed: () {
            _close(context);
            context.push('/settings/archive');
          },
        ),
      ]),
    );
    if (!vault.isOpen) {
      return [
        band,
        _FolderTile(
          icon: AppIcons.lock,
          label: l10n.tr('archiveOpen'),
          onTap: () {
            _close(context);
            unawaited(showArchiveUnlockSheet(rootCtx));
          },
        ),
        const SizedBox(height: Space.s),
      ];
    }
    final folders = ref.watch(archiveFoldersProvider).value ?? const <ArchiveFolder>[];
    final accounts = ref.watch(archiveAccountsProvider).value ?? const <ArchiveAccountInfo>[];
    final stats = ref.watch(archiveStatsProvider).value;
    final counts = ref.watch(archiveItemCountsProvider).value ?? const {};
    final collapsed = ref.watch(collapsedFoldersProvider);
    // Только архив выбранного ящика (1.8.14, просьба владельца 29.10.2026:
    // в архиве несколько ящиков, папки у них разные и устроены по-разному).
    // Весь архив — отдельным окном, как «Файлы».
    final active = ref.watch(activeAccountProvider);
    final mine = active == null ? const <String>{} : archiveAccountsOf(active, accounts);
    final shown = [for (final a in accounts) if (mine.contains(a.id)) a];
    final tiles = <Widget>[
      band,
      _FolderTile(
        icon: AppIcons.inventory_2,
        label: l10n.tr('archiveAll'),
        onTap: () {
          _close(context);
          context.push('/archive');
        },
      ),
    ];

    Iterable<Widget> branch(ArchiveFolderTree tree, ArchiveFolder f, int depth) sync* {
      final kids = tree.children[f.id] ?? const <ArchiveFolder>[];
      final key = CollapsedFoldersNotifier.key('ogna:${f.accountId}', '${f.id}');
      final isCollapsed = collapsed.contains(key);
      yield _FolderTile(
        icon: archiveFolderIcon(f),
        label: archiveFolderLabel(f, l10n),
        indent: depth,
        hasChildren: kids.isNotEmpty,
        expanded: !isCollapsed,
        onToggle: () => ref.read(collapsedFoldersProvider.notifier).toggle('ogna:${f.accountId}', '${f.id}'),
        onTap: () {
          _close(context);
          context.push('/archive/folder/${f.id}');
        },
      );
      if (isCollapsed) return;
      for (final c in kids) {
        yield* branch(tree, c, depth + 1);
      }
    }

    // Тот же ящик в архиве под двумя id (копия с другого устройства) — у
    // каждого своя ветка с адресом.
    final multi = shown.length > 1;
    for (final a in shown) {
      final tree = ArchiveFolderTree.build(folders, a.id);
      if (tree.roots.isEmpty) continue;
      var depth = 0;
      if (multi) {
        final isCollapsed = collapsed.contains(CollapsedFoldersNotifier.key('ogna:${a.id}', ''));
        tiles.add(_FolderTile(
          icon: AppIcons.alternate_email,
          label: '${a.label} (${a.messages})',
          hasChildren: true,
          expanded: !isCollapsed,
          onToggle: () => ref.read(collapsedFoldersProvider.notifier).toggle('ogna:${a.id}', ''),
          onTap: () => ref.read(collapsedFoldersProvider.notifier).toggle('ogna:${a.id}', ''),
        ));
        if (isCollapsed) continue;
        depth = 1;
      }
      for (final f in tree.roots) {
        tiles.addAll(branch(tree, f, depth));
      }
    }
    var events = 0, tasks = 0, contacts = 0;
    for (final id in mine) {
      final c = counts[id];
      if (c == null) continue;
      events += c.events;
      tasks += c.tasks;
      contacts += c.contacts;
    }
    final only = mine.isEmpty ? '' : '?accounts=${archiveAccountsQuery(mine)}';
    void open(String kind) {
      _close(context);
      context.push('/archive/items/$kind$only');
    }

    if (events > 0) {
      tiles.add(_FolderTile(icon: AppIcons.event, label: l10n.tr('archiveKindEvents'), onTap: () => open('events')));
    }
    if (tasks > 0) {
      tiles.add(_FolderTile(icon: AppIcons.check_box, label: l10n.tr('archiveKindTasks'), onTap: () => open('tasks')));
    }
    if (contacts > 0) {
      tiles.add(
          _FolderTile(icon: AppIcons.contacts, label: l10n.tr('archiveKindContacts'), onTap: () => open('contacts')));
    }
    final empty = (stats?.messages ?? 0) == 0 && (stats?.events ?? 0) + (stats?.tasks ?? 0) + (stats?.contacts ?? 0) == 0;
    if (empty) {
      // Архив пуст: подсказка, как в него положить.
      tiles
        ..removeLast()
        ..add(_FolderTile(
          icon: AppIcons.inventory_2,
          label: l10n.tr('archiveEmptyDrawer'),
          onTap: () {
            _close(context);
            context.push('/settings/archive');
          },
        ));
    }
    tiles.add(const SizedBox(height: Space.s));
    return tiles;
  }

  /// Добавить папку в избранное или убрать из него (folders.is_favorite).
  static Future<void> setFolderFavorite(WidgetRef ref, FolderModel folder, bool value) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.folders)
          ..where((f) => f.id.equals(folder.id) & f.accountId.equals(folder.accountId)))
        .write(FoldersCompanion(isFavorite: Value(value)));
  }

  static bool _canManage(WidgetRef ref) {
    final a = ref.read(activeAccountProvider);
    return a != null && TransportCapabilities.forAccount(a).serverFolders;
  }

  /// Действия с папкой по удержанию (1.8.0, просьба владельца 26.10.2026) —
  /// карточкой над строкой с размытым фоном, как у контакта и письма:
  /// «Все прочитано», уведомления о письмах папки, избранное; «Ещё» —
  /// новая подпапка, переместить, переименовать, порядок, очистить, удалить.
  void _showFolderActions(BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n,
      {Rect? anchor}) {
    HapticFeedback.mediumImpact();
    final theme = Theme.of(context);
    final canNotify = !FolderNotify.neverTypes.contains(folder.type);
    final muted = ref.read(folderNotifyOffProvider).contains(FolderNotify.key(folder.accountId, folder.id));
    final manage = _canManage(ref);
    Future<void> toggleNotify() async {
      final all = ref.read(accountFoldersProvider(folder.accountId)).value ?? const <FolderModel>[];
      List<String> below(String id) => [
            for (final c in all.where((x) => x.parentId == id)) ...[c.id, ...below(c.id)],
          ];
      await ref.read(folderNotifyOffProvider.notifier).set(folder.accountId, [folder.id, ...below(folder.id)], muted);
    }

    unawaited(showPeekCard(
      context,
      anchor: anchor,
      onOpen: () => _openFolder(context, ref, folder),
      card: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Row(children: [
          Icon(folderIconOf(folder), color: theme.colorScheme.primary),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_localizedFolderName(folder, l10n),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              if (canNotify)
                Text(l10n.tr(muted ? 'folderNotifyOff' : 'folderNotifyOn'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
      actions: [
        PeekAction(
          icon: AppIcons.mark_email_read,
          label: l10n.tr('markAllRead'),
          onTap: () => unawaited(_markFolderRead(context, ref, folder, l10n)),
        ),
        if (canNotify)
          PeekAction(
            icon: muted ? AppIcons.notifications_active : AppIcons.notifications_off,
            label: l10n.tr(muted ? 'folderNotifyTurnOn' : 'folderNotifyTurnOff'),
            onTap: () => unawaited(toggleNotify()),
          ),
        PeekAction(
          icon: AppIcons.star,
          filled: folder.isFavorite,
          color: folder.isFavorite ? AppColors.brandAmber : null,
          label: l10n.tr(folder.isFavorite ? 'removeFromFavorites' : 'addToFavorites'),
          onTap: () => unawaited(setFolderFavorite(ref, folder, !folder.isFavorite)),
        ),
      ],
      moreLabel: l10n.tr('peekMore'),
      more: [
        PeekGroup(title: l10n.tr('peekGroupFolder'), items: [
          if (manage)
            PeekAction(
              icon: AppIcons.create_new_folder,
              label: l10n.tr('newSubfolder'),
              onTap: () => _createFolder(context, ref, l10n, parent: folder),
            ),
          if (!folder.isSystem && manage)
            PeekAction(
              icon: AppIcons.drive_file_move,
              label: l10n.tr('moveFolder'),
              onTap: () => _moveFolder(context, ref, folder, l10n),
            ),
          if (!folder.isSystem)
            PeekAction(
              icon: AppIcons.edit,
              label: l10n.tr('rename'),
              onTap: () => _renameFolder(context, ref, folder, l10n),
            ),
          // Порядок папок в меню (1.6.10) — только вид на телефоне.
          PeekAction(
            icon: AppIcons.swap_vert,
            label: l10n.tr('folderReorder'),
            onTap: () => _reorderFolders(context, ref, folder),
          ),
          // Папка целиком, с подпапками, — в архив Ogneliss (1.8.8).
          PeekAction(
            icon: AppIcons.inventory_2,
            label: l10n.tr('folderToOgna'),
            onTap: () => unawaited(_folderToOgna(context, ref, folder, l10n)),
          ),
        ]),
        PeekGroup(items: [
          if (folder.type == FolderType.trash || folder.type == FolderType.junk)
            PeekAction(
              icon: AppIcons.delete_sweep,
              label: folder.type == FolderType.trash ? l10n.tr('emptyTrash') : l10n.tr('clearJunk'),
              color: AppColors.errorText(context),
              onTap: () => unawaited(_emptyFolder(context, ref, folder, l10n)),
            ),
          if (!folder.isSystem)
            PeekAction(
              icon: AppIcons.delete,
              label: l10n.delete,
              color: AppColors.errorText(context),
              onTap: () => _deleteFolder(context, ref, folder, l10n),
            ),
        ]),
      ],
    ));
  }

  /// Порядок папок одного уровня с [folder] (1.6.10): перетаскиванием за
  /// ручку, «По умолчанию» — системные по порядку ящика, свои по алфавиту.
  void _reorderFolders(BuildContext context, WidgetRef ref, FolderModel folder) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FolderOrderSheet(accountId: folder.accountId, parentId: folder.parentId),
    );
  }

  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// Число непрочитанных на портрете ящика (1.7.3) — как на значке «Почта»
  /// внизу: красный кружок справа сверху, больше 99 — «99+».
  static Widget _withUnread(BuildContext context, int count, Widget child) {
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: count > 0 ? AppLocalizations.of(context).tr('unreadCountA11y').replaceAll('{n}', label) : null,
      child: badges.Badge(
        showBadge: count > 0,
        position: badges.BadgePosition.topEnd(top: -6, end: -10),
        badgeContent: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.errorRed, padding: EdgeInsets.all(Space.xs)),
        child: child,
      ),
    );
  }

  static Widget _drawerAvatar(AccountModel account) => HeroEmailAvatar(
        emailId: 'drawer/${account.id}',
        radius: 20,
        color: Color(account.colorValue),
        initial: account.displayName.isNotEmpty ? initialOf(account.displayName) : '?',
        hero: false,
        email: account.email,
        photo: account.avatarUrl,
      );

  static AccountModel? _accountOf(WidgetRef ref, FolderModel f) =>
      ref.read(accountsProvider).where((a) => a.id == f.accountId).firstOrNull;

  /// «Пометить всё прочитанным» — все письма папки из базы, не только
  /// загруженные в список. Раньше пункт меню ничего не делал.
  Future<void> _markFolderRead(
      BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final account = _accountOf(ref, folder);
    if (account == null) return;
    final n = await ref.read(folderActionsProvider).markAllRead(account, folder);
    showInlineNotice(l10n.tr('markedReadN').replaceAll('{n}', '$n'));
    unawaited(ref.read(emailsProvider.notifier).refresh());
  }

  /// «Папку в архив Ogneliss» (1.8.8): папка с подпапками и всеми письмами —
  /// в архив на устройстве, структура как в ящике. Архива нет — сначала
  /// создать, закрыт — открыть паролем.
  Future<void> _folderToOgna(
      BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final account = _accountOf(ref, folder);
    if (account == null) return;
    if (!await ensureArchiveReady(context, ref) || !context.mounted) return;
    final deletes = ref.read(archiveSettingsProvider).deleteFromServer;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('folderToOgna')),
        content: Text('${l10n.tr('folderToOgnaBody').replaceAll('{folder}', _localizedFolderName(folder, l10n))}\n\n'
            '${l10n.tr(deletes ? 'archiveRunDeletes' : 'archiveRunCopies')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('archiveRunStart'))),
        ],
      ),
    );
    if (ok != true) return;
    showInlineNotice(l10n.tr('folderToOgnaStarted'));
    final r = await ref.read(archiveRunnerProvider.notifier).archiveFolder(account, folder.id);
    if (r.errorKey != null && r.mails == 0) {
      showInlineError(l10n.tr(r.errorKey!));
      return;
    }
    var text = l10n.plural('archiveNMails', r.mails);
    if (r.failed > 0) text += ' · ${l10n.tr('archiveFailedN').replaceAll('{n}', '${r.failed}')}';
    showInlineNotice(text);
    if (r.deleted > 0) unawaited(ref.read(emailsProvider.notifier).refresh());
  }

  /// Очистить корзину или спам — с подтверждением, безвозвратно.
  Future<void> _emptyFolder(
      BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final account = _accountOf(ref, folder);
    if (account == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(folder.type == FolderType.trash ? l10n.emptyTrashTitle : l10n.tr('clearJunk')),
        content: Text(l10n.tr(account.isMsExchange ? 'emptyTrashBodyExchange' : 'emptyTrashBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.emptyAction)),
        ],
      ),
    );
    if (ok != true) return;
    final (done, total) = await ref.read(folderActionsProvider).emptyFolder(account, folder);
    if (done < total) {
      showInlineError('${l10n.error}: ${total - done}');
    }
    unawaited(ref.read(emailsProvider.notifier).refresh());
  }

  /// Создать папку: диалог → сервер → ресинк списка папок → обновление UI.
  /// IMAP: id папки — её путь; после переименования или переноса он
  /// меняется, и прежняя строка в базе (с письмами) становится лишней.
  static bool _pathIds(AccountModel a) => !a.usesEas && !(a.usesEws || a.isExchange);

  /// Убрать из базы папку и её подпапки (с письмами) — IMAP после переноса
  /// или переименования: письма придут заново в папку с новым путём.
  static Future<void> _dropLocalSubtree(WidgetRef ref, String accountId, String path) async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.folders)..where((f) => f.accountId.equals(accountId))).get();
    final ids = [
      for (final r in rows)
        if (r.id == path || r.id.startsWith('$path/') || r.id.startsWith('$path.')) r.id,
    ];
    if (ids.isEmpty) return;
    await (db.delete(db.emails)..where((e) => e.accountId.equals(accountId) & e.folderId.isIn(ids))).go();
    await (db.delete(db.folders)..where((f) => f.accountId.equals(accountId) & f.id.isIn(ids))).go();
  }

  /// Убрать из базы папку и все её подпапки (по родителю; у IMAP — и по
  /// пути) вместе с письмами. Только этого ящика: id папки («INBOX», «5»)
  /// совпадает у разных ящиков.
  static Future<void> _dropLocalTree(WidgetRef ref, String accountId, String rootId) async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.folders)..where((f) => f.accountId.equals(accountId))).get();
    final list = folderSubtreeIds({for (final r in rows) r.id: r.parentId}, rootId).toList();
    await (db.delete(db.emails)..where((e) => e.accountId.equals(accountId) & e.folderId.isIn(list))).go();
    await (db.delete(db.folders)..where((f) => f.accountId.equals(accountId) & f.id.isIn(list))).go();
  }

  /// Выбор родительской папки: '' — корень ящика, null — отмена.
  /// [exclude] — папка, которую переносят (её и подпапки выбрать нельзя).
  static Future<String?> _pickParent(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      {required String title, FolderModel? exclude, String? current}) {
    final folders = ref.read(foldersProvider).value ?? const <FolderModel>[];
    final tree = _FolderTreeData.build(folders, const {},
        order: ref.read(folderOrderProvider), accountId: ref.read(activeAccountProvider)?.id);
    final rows = <(FolderModel, int)>[];
    void walk(FolderModel f, int depth) {
      if (exclude != null && f.id == exclude.id) return; // и всё поддерево
      rows.add((f, depth));
      for (final c in tree.children[f.id] ?? const <FolderModel>[]) {
        walk(c, depth + 1);
      }
    }
    for (final r in tree.roots) {
      walk(r, 0);
    }
    // Карточкой по центру (1.8.8), как меню «⋮»: дерево папок отступами,
    // текущее место — с галочкой.
    return showAnchoredMenu<String>(
      context,
      anchor: null,
      selected: current ?? '',
      header: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      entries: [
        AppMenuEntry(value: '', label: l10n.tr('folderRoot'), icon: AppIcons.account_tree),
        for (final (f, depth) in rows)
          AppMenuEntry(value: f.id, label: _localizedFolderName(f, l10n), icon: folderIconOf(f), indent: depth),
      ],
    );
  }

  /// Новая папка: имя и где создать — в корне ящика или внутри другой папки
  /// ([parent] — сразу внутри неё, «Новая подпапка» из меню папки).
  Future<void> _createFolder(BuildContext context, WidgetRef ref, AppLocalizations l10n,
      {FolderModel? parent}) async {
    final controller = TextEditingController();
    final folders = ref.read(foldersProvider).value ?? const <FolderModel>[];
    String parentId = parent?.id ?? '';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final p = folders.where((f) => f.id == parentId).firstOrNull;
          return AlertDialog(
            title: Text(l10n.tr('newFolder')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.tr('folderName')),
                ),
                const SizedBox(height: Space.m),
                Text(l10n.tr('folderParent'), style: Theme.of(ctx).textTheme.labelMedium),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(p == null ? AppIcons.account_tree : folderIconOf(p)),
                  title: Text(p == null ? l10n.tr('folderRoot') : _localizedFolderName(p, l10n)),
                  trailing: const Icon(AppIcons.chevron_right),
                  onTap: () async {
                    final picked = await _pickParent(ctx, ref, l10n,
                        title: l10n.tr('folderParent'), current: parentId);
                    if (picked != null) setLocal(() => parentId = picked);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop((controller.text.trim(), parentId)),
                child: Text(l10n.tr('create')),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || result.$1.isEmpty) return;
    if (!context.mounted) return; // меню закрыли, пока был открыт диалог

    final account = ref.read(activeAccountProvider);
    if (account == null) return;
    try {
      final ok = await ref.read(mailEngineServiceProvider)
          .createFolder(account, result.$1, parentId: result.$2.isEmpty ? null : result.$2);
      if (!ok) {
        showInlineError(l10n.tr('folderCreateFailed'));
        return;
      }
      // Подтягиваем актуальный список папок с сервера (с новым server-id).
      await ref.read(syncServiceProvider).refreshFolders(account);
      ref.invalidate(foldersProvider);
    } catch (e) {
      AppLogger.warning('Создание папки: $e');
      showInlineError('${l10n.error}: $e');
    }
  }

  /// Переместить папку внутрь другой или в корень ящика.
  Future<void> _moveFolder(BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final target = await _pickParent(context, ref, l10n,
        title: l10n.tr('moveFolderTo'), exclude: folder, current: folder.parentId ?? '');
    if (target == null || target == (folder.parentId ?? '')) return;
    if (!context.mounted) return;
    final account = ref.read(activeAccountProvider);
    if (account == null) return;
    try {
      final ok = await ref.read(mailEngineServiceProvider).moveFolder(account,
          folderId: folder.id, displayName: folder.displayName, newParentId: target.isEmpty ? null : target);
      if (!ok) {
        showInlineError(l10n.tr('moveFolderFailed'));
        return;
      }
      final db = ref.read(databaseProvider);
      if (_pathIds(account)) {
        await _dropLocalSubtree(ref, account.id, folder.id);
      } else {
        await (db.update(db.folders)
              ..where((f) => f.id.equals(folder.id) & f.accountId.equals(account.id)))
            .write(FoldersCompanion(parentId: Value(target.isEmpty ? null : target)));
      }
      await ref.read(syncServiceProvider).refreshFolders(account);
      ref.invalidate(foldersProvider);
    } catch (e) {
      AppLogger.warning('Перенос папки: $e');
      showInlineError('${l10n.error}: $e');
    }
  }

  /// Переименовать папку: диалог → сервер (если поддерживается) → локальная БД.
  Future<void> _renameFolder(BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final controller = TextEditingController(text: folder.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('renameFolder')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.tr('folderName')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text(l10n.save)),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == folder.displayName) return;
    if (!context.mounted) return; // меню закрыли, пока был открыт диалог

    final account = ref.read(activeAccountProvider);
    try {
      if (account != null && TransportCapabilities.forAccount(account).serverFolders) {
        final ok = await ref.read(mailEngineServiceProvider).renameFolder(account, folderId: folder.id, newName: newName);
        if (!ok) {
          showInlineError(l10n.tr('renameRejected'));
          return;
        }
      }
      // Локально отражаем изменение. У IMAP меняется путь (id) — прежняя
      // строка убирается, новая приходит со списком папок сервера.
      final db = ref.read(databaseProvider);
      if (account != null && _pathIds(account)) {
        await _dropLocalSubtree(ref, account.id, folder.id);
        await ref.read(syncServiceProvider).refreshFolders(account);
      } else {
        // Только этого ящика: id папки («5») совпадает у разных ящиков.
        await (db.update(db.folders)
              ..where((f) => f.id.equals(folder.id) & f.accountId.equals(folder.accountId)))
            .write(FoldersCompanion(displayName: Value(newName)));
      }
      ref.invalidate(foldersProvider);
    } catch (e) {
      showInlineError('${l10n.error}: $e');
    }
  }

  /// Удалить папку: подтверждение → сервер (если поддерживается) → локальная БД.
  Future<void> _deleteFolder(BuildContext context, WidgetRef ref, FolderModel folder, AppLocalizations l10n) async {
    final confirmed = await confirmDestructive(context,
        title: l10n.tr('deleteFolderQ'),
        message: l10n.tr('deleteFolderWarn').replaceAll('{name}', folder.displayName));
    if (!confirmed) return;
    if (!context.mounted) return; // меню закрыли, пока был открыт диалог

    final account = ref.read(activeAccountProvider);
    try {
      if (account != null && TransportCapabilities.forAccount(account).serverFolders) {
        final ok = await ref.read(mailEngineServiceProvider).deleteFolder(account, folderId: folder.id);
        if (!ok) {
          showInlineError(l10n.tr('deleteRejected'));
          return;
        }
      }
      // Папка уходит из меню сразу — вместе с подпапками (1.8.0: раньше
      // подпапки удалённой папки оставались в базе и до следующей
      // синхронизации папок показывались в корне ящика).
      await _dropLocalTree(ref, folder.accountId, folder.id);
      ref.invalidate(foldersProvider);
      // Список папок с сервера — чтобы меню совпало с ним.
      if (account != null && TransportCapabilities.forAccount(account).serverFolders) {
        unawaited(ref.read(syncServiceProvider).refreshFolders(account).catchError((Object e) {
          AppLogger.warning('Папки после удаления: $e');
        }));
      }
    } catch (e) {
      showInlineError('${l10n.error}: $e');
    }
  }

  /// Открыть папку: выставить фильтры, закрыть меню. Если папка не
  /// синхронизирована (архив/пользовательская — по умолчанию не тянутся),
  /// запустить синхронизацию именно этой папки по требованию.
  void _openFolder(BuildContext context, WidgetRef ref, FolderModel folder) {
    unawaited(ref.read(startupFolderProvider.notifier)
        .rememberSelection(folderId: folder.id, accountId: folder.accountId));
    ref.read(allAccountsModeProvider.notifier).state = false;
    ref.read(unifiedModeProvider.notifier).state = false;
    ref.read(selectedFolderIdProvider.notifier).state = folder.id;
    ref.read(mailFilterProvider.notifier).state = MailFilter.none;
    _close(context);

    // ВАЖНО: открытие папки НЕ запускает синхронизацию. Письма показываются
    // сразу из БД — просмотр, поиск и действия не ждут сети (при плохой связи
    // или офлайне это критично). Загрузка происходит либо фоном по таймеру,
    // либо по свайпу вниз внутри папки (refresh() синкает именно эту папку,
    // даже если она отключена в настройках). Список сам подхватит новые письма
    // Список подписан на поток из БД (.watch()) — новые письма появятся сами,
    // по мере загрузки.
  }

  static String _localizedFolderName(FolderModel folder, AppLocalizations l10n) {
    // Маппинг по ТИПУ папки (надёжно), а не по точному имени с сервера —
    // сервер может отдавать 'Sent'/'Отправлено'/'Trash'/'Корзина'/'Bin' и т.п.
    switch (folder.type) {
      case FolderType.inbox:   return l10n.inbox;
      case FolderType.sent:    return l10n.tr('sent');
      case FolderType.drafts:  return l10n.tr('drafts');
      case FolderType.trash:   return l10n.tr('trash');
      // «Спам» и «Архив» — своим названием, только если у папки стандартное
      // имя на каком-нибудь языке: выбранная вручную «Старое» (1.7.2+106)
      // так и называется «Старое».
      case FolderType.junk:
        return SpecialFolders.typeByName(folder.displayName) == FolderType.junk ? l10n.tr('junk') : folder.displayName;
      case FolderType.archive:
        return SpecialFolders.typeByName(folder.displayName) == FolderType.archive
            ? l10n.tr('archive')
            : folder.displayName;
      case FolderType.outbox:  return l10n.tr('outbox');
      case FolderType.custom:  return folder.displayName; // пользовательская — как на сервере
    }
  }
}

/// Дерево папок: дети по родителю, корни и непрочитанные с подпапками.
/// Папка постоянной панели принимает письмо, перетащенное из ленты: письмо
/// переносится в неё с «Отменить», как при архивировании.
class _FolderDropTarget extends ConsumerWidget {
  final FolderModel folder;
  final Widget child;
  const _FolderDropTarget({required this.folder, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<EmailModel>(
      onWillAcceptWithDetails: (d) => d.data.accountId == folder.accountId && d.data.folderId != folder.id,
      onAcceptWithDetails: (d) => _move(context, ref, d.data),
      builder: (context, candidates, _) => candidates.isEmpty
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                border: Border.all(color: scheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: child,
            ),
    );
  }

  void _move(BuildContext context, WidgetRef ref, EmailModel e) {
    final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    if (account == null) return;
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    notifier.hideLocally(e);
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('emailMovedTo').replaceAll('{folder}', folder.displayName),
        execute: () => actions.moveTo(account, e.id, e.folderId, folder.id),
        undo: () async {},
        onUndo: () => notifier.unhideLocally(e),
        onSettled: () => notifier.unhideLocally(e),
      ),
    );
  }
}

class _FolderTreeData {
  final Map<String, List<FolderModel>> children;
  final List<FolderModel> roots;
  /// Непрочитанные папки вместе со всеми подпапками.
  final Map<String, int> total;

  _FolderTreeData(this.children, this.roots, this.total);

  /// [local] — непрочитанные по базе (folder_id → число).
  /// [order] — порядок, расставленный пользователем (folder_order.dart).
  factory _FolderTreeData.build(List<FolderModel> folders, Map<String, int> local,
      {Map<String, List<String>> order = const {}, String? accountId}) {
    final ids = {for (final f in folders) f.id};
    final children = <String, List<FolderModel>>{};
    final roots = <FolderModel>[];
    for (final f in folders) {
      final p = f.parentId;
      // Корень — без родителя или с родителем вне списка (служебный корень
      // ящика: «Top of Information Store», «0» у ActiveSync).
      if (p == null || p == f.id || !ids.contains(p)) {
        roots.add(f);
      } else {
        (children[p] ??= []).add(f);
      }
    }
    int byName(FolderModel a, FolderModel b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    List<String>? saved(String? parent) =>
        accountId == null ? null : order[FolderOrderNotifier.key(accountId, parent)];
    for (final e in children.entries) {
      e.value.sort(byName);
      // Копия: без сохранённого порядка applyFolderOrder вернёт тот же список.
      final ordered = [...applyFolderOrder(e.value, saved(e.key))];
      e.value
        ..clear()
        ..addAll(ordered);
    }
    // Системные корни — в порядке из базы (Входящие, Отправленные…),
    // пользовательские — по алфавиту; либо порядок пользователя.
    final system = roots.where((f) => f.isSystem).toList();
    final custom = roots.where((f) => !f.isSystem).toList()..sort(byName);
    final rootOrder = applyFolderOrder([...system, ...custom], saved(null));

    // Своё число папки: по базе — у синхронизируемых (совпадает со списком
    // писем и меняется сразу при прочтении), по серверу — у остальных
    // (их письма в базе есть не все). Черновики, исходящие и отправленные
    // непрочитанными не считаются.
    int own(FolderModel f) {
      if (const {FolderType.drafts, FolderType.outbox, FolderType.sent}.contains(f.type)) return 0;
      final l = local[f.id] ?? 0;
      return f.isSynced ? l : (f.unreadCount > l ? f.unreadCount : l);
    }

    final total = <String, int>{};
    final visiting = <String>{};
    int sum(FolderModel f) {
      final known = total[f.id];
      if (known != null) return known;
      if (!visiting.add(f.id)) return 0; // цикл в parentId — не зависаем
      var n = own(f);
      for (final c in children[f.id] ?? const <FolderModel>[]) {
        // Корзина и спам не добавляют свои непрочитанные к родителю.
        if (c.type == FolderType.trash || c.type == FolderType.junk) {
          sum(c);
          continue;
        }
        n += sum(c);
      }
      total[f.id] = n;
      return n;
    }
    for (final f in folders) {
      sum(f);
    }
    return _FolderTreeData(children, rootOrder, total);
  }
}

/// Тайл папки (и пункта избранного). У папки с подпапками — стрелка
/// свернуть/развернуть; нажатие на саму строку открывает папку.
class _FolderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final Color? countColor;
  final VoidCallback? onTap;
  final int indent;
  final bool isSelected;
  final bool hasChildren;
  final bool expanded;
  final VoidCallback? onToggle;
  /// Дополнительная кнопка перед числом (например, «Новая папка» у «Входящих»).
  final Widget? extra;

  /// Уведомления о письмах папки выключены — колокольчик перечёркнут (1.8.0).
  final bool muted;

  /// Удержание с местом строки на экране — карточка действий над строкой.
  final void Function(Rect? anchor)? onLongPressAt;

  const _FolderTile({
    this.muted = false,
    this.onLongPressAt,
    required this.icon,
    required this.label,
    this.count,
    this.countColor,
    this.onTap,
    this.indent = 0,
    this.isSelected = false,
    this.hasChildren = false,
    this.expanded = true,
    this.onToggle,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final n = count ?? 0;
    // Отступ ограничен: на 6-м уровне вложенности название уже не помещалось.
    final level = indent.clamp(0, 5);
    final inTree = onToggle != null;

    return Material(
      color: isSelected ? theme.colorScheme.secondaryContainer : Colors.transparent,
      child: ListTile(
        contentPadding: EdgeInsets.only(left: Space.l + level * 18.0, right: inTree ? Space.xs : Space.l),
        leading: Icon(icon, size: 22, color: isSelected ? theme.colorScheme.primary : null),
        title: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isSelected || (hasChildren && !expanded && n > 0) ? FontWeight.w600 : null,
            color: isSelected ? theme.colorScheme.primary : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (extra != null) extra!,
            if (muted)
              Padding(
                padding: const EdgeInsets.only(right: Space.xs),
                child: Semantics(
                  label: l10n.tr('folderNotifyOff'),
                  child: Icon(AppIcons.notifications_off, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            if (n > 0)
              Text(
                n > 9999 ? '9999+' : '$n',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: countColor ?? theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (inTree)
              hasChildren
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: expanded ? l10n.tr('collapse') : l10n.tr('expand'),
                      icon: Icon(expanded ? AppIcons.expand_less : AppIcons.expand_more, size: 20),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onToggle?.call();
                      },
                    )
                  // Место стрелки у листьев — чтобы числа стояли в одну колонку.
                  : const SizedBox(width: 40),
          ],
        ),
        dense: true,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        onLongPress: onLongPressAt != null ? () => onLongPressAt!(peekAnchorOf(context)) : null,
      ),
    );
  }
}

/// Настройка избранного (шторка из кнопки у заголовка «Избранное»).
class _FavoritesEditor extends ConsumerWidget {
  const _FavoritesEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hidden = ref.watch(hiddenQuickItemsProvider);
    final accountCount = ref.watch(accountsProvider).length;
    final folders = ref.watch(foldersProvider).value ?? const <FolderModel>[];
    final tree = _FolderTreeData.build(folders, const {});

    final phone = AppBottomBar.inUse(context);
    final quick = <(DrawerQuickItem, IconData, String)>[
      if (accountCount > 1) (DrawerQuickItem.allAccounts, AppIcons.all_inbox, l10n.tr('allAccounts')),
      (DrawerQuickItem.allMail, AppIcons.all_inbox, l10n.allMail),
      (DrawerQuickItem.unread, AppIcons.mark_email_unread, l10n.tr('unread')),
      (DrawerQuickItem.flagged, AppIcons.flag, l10n.tr('flagged')),
      if (ref.watch(settingsProvider).mailControl)
        (DrawerQuickItem.control, AppIcons.task_alt, l10n.tr('controlFilter')),
      (DrawerQuickItem.later, AppIcons.watch_later, l10n.tr('laterFilter')),
      (DrawerQuickItem.vip, AppIcons.star, l10n.tr('vip')),
      (DrawerQuickItem.attachments, AppIcons.attach_file, l10n.tr('attachments')),
      (DrawerQuickItem.triage, AppIcons.playlist_add_check, l10n.tr('triageTitle')),
      if (phone && ref.watch(featureFlagsProvider).showFileHub)
        (DrawerQuickItem.fileHub, AppIcons.folder_copy, l10n.tr('fileHub')),
      if (ref.watch(featureFlagsProvider).showNotes)
        (DrawerQuickItem.notes, AppIcons.sticky_note_2, l10n.tr('notes')),
      if (MailDrawer._tasksInMenu(context, ref))
        (DrawerQuickItem.tasks, AppIcons.check_box, l10n.tasksLabel),
      if (phone && ref.watch(settingsProvider).myDay) (DrawerQuickItem.myDay, AppIcons.myDay, l10n.tr('myDay')),
      if (phone) (DrawerQuickItem.settings, AppIcons.settings, l10n.tr('settings')),
      (DrawerQuickItem.theme, AppIcons.dark_mode, l10n.tr('drawerThemeSwitch')),
    ];

    Iterable<Widget> folderRows(FolderModel f, int depth) sync* {
      yield ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: Space.l + depth.clamp(0, 5) * 18.0, right: Space.s),
        leading: Icon(folderIconOf(f), size: 22),
        title: Text(MailDrawer._localizedFolderName(f, l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          tooltip: f.isFavorite ? l10n.tr('removeFromFavorites') : l10n.tr('addToFavorites'),
          icon: Icon(AppIcons.star, fill: f.isFavorite ? 1 : 0,
              color: f.isFavorite ? theme.colorScheme.primary : null),
          onPressed: () => MailDrawer.setFolderFavorite(ref, f, !f.isFavorite),
        ),
        onTap: () => MailDrawer.setFolderFavorite(ref, f, !f.isFavorite),
      );
      for (final c in tree.children[f.id] ?? const <FolderModel>[]) {
        yield* folderRows(c, depth + 1);
      }
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Text(l10n.tr('favoritesEdit'), style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
            child: Text(l10n.tr('favoritesQuick'),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
          ),
          for (final (item, icon, label) in quick)
            SwitchListTile(
              dense: true,
              secondary: Icon(icon),
              title: Text(label),
              value: !hidden.contains(item),
              onChanged: (v) => ref.read(hiddenQuickItemsProvider.notifier).setVisible(item, v),
            ),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.xs),
            child: Text(l10n.tr('favoritesFolders'),
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Text(l10n.tr('favoritesFoldersHint'), style: theme.textTheme.bodySmall),
          ),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.tr('noFoldersYet')),
            ),
          for (final f in tree.roots) ...folderRows(f, 0),
          const SizedBox(height: Space.l),
        ],
      ),
    );
  }
}

/// Заголовок раздела меню: с 1.8.0 — синяя подпись (в высоком контрасте —
/// полоса на более тёмной подложке с тенью): разделы видны сразу, не
/// сливаются в один список.
class _DrawerBand extends StatelessWidget {
  final String title;
  final Widget? trailing;

  /// Тень вверх (полоса над прокручиваемым списком — «Избранное»,
  /// «Аккаунты») или вниз («Папки» над деревом папок). Постоянная (1.6.40,
  /// владельцу понравилась тень, которая раньше появлялась только иногда).
  final bool shadowUp;
  const _DrawerBand({required this.title, this.trailing, this.shadowUp = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // «Воздушный» вид (1.8.0, как Ogneliss Dialer): подпись раздела без
    // полосы и тени; над разделами под прокручиваемым деревом папок
    // («Избранное», «Аккаунты») — тонкая линия, граница частей меню.
    if (!OgnelissLook.of(context).outlined) {
      final band = SectionBand(title: title, trailing: trailing);
      if (!shadowUp) return band;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Divider(height: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
        band,
      ]);
    }
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
          blurRadius: 6,
          offset: Offset(0, shadowUp ? -2 : 2),
        ),
      ]),
      child: SectionBand(title: title, trailing: trailing),
    );
  }
}

/// Расстановка папок одного уровня (1.6.10).
class _FolderOrderSheet extends ConsumerWidget {
  final String accountId;
  final String? parentId;
  const _FolderOrderSheet({required this.accountId, required this.parentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final folders = ref.watch(foldersProvider).value ?? const <FolderModel>[];
    final order = ref.watch(folderOrderProvider);
    final tree = _FolderTreeData.build(folders, const {}, order: order, accountId: accountId);
    final ids = {for (final f in folders) f.id};
    // Родитель вне списка (служебный корень ящика) — это корень дерева.
    final parent = parentId != null && ids.contains(parentId) ? parentId : null;
    final siblings = parent == null ? tree.roots : (tree.children[parent] ?? const <FolderModel>[]);
    final parentName = parent == null
        ? l10n.tr('folderRoot')
        : MailDrawer._localizedFolderName(folders.firstWhere((f) => f.id == parent), l10n);
    final custom = order.containsKey(FolderOrderNotifier.key(accountId, parent));
    final notifier = ref.read(folderOrderProvider.notifier);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
              child: Row(children: [
                Expanded(child: Text(l10n.tr('folderReorder'), style: theme.textTheme.titleMedium)),
                HelpButton(title: l10n.tr('folderReorder'), text: l10n.tr('folderReorderHint')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Text(parentName,
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: siblings.length,
                // onReorderItem появился в Flutter 3.41; pubspec допускает 3.38.
                // ignore: deprecated_member_use
                onReorder: (from, to) {
                  final list = [for (final f in siblings) f.id];
                  if (to > from) to -= 1;
                  final id = list.removeAt(from);
                  list.insert(to, id);
                  unawaited(notifier.set(accountId, parent, list));
                },
                itemBuilder: (ctx, i) {
                  final f = siblings[i];
                  return ListTile(
                    key: ValueKey(f.id),
                    leading: Icon(folderIconOf(f)),
                    title: Text(MailDrawer._localizedFolderName(f, l10n),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.all(Space.s),
                        child: Icon(AppIcons.drag_handle),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
              child: Row(children: [
                TextButton.icon(
                  onPressed: custom ? () => unawaited(notifier.reset(accountId, parent)) : null,
                  icon: const Icon(AppIcons.sort_by_alpha, size: 18),
                  label: Text(l10n.tr('folderOrderDefault')),
                ),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.tr('done'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

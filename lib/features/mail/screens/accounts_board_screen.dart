// lib/features/mail/screens/accounts_board_screen.dart
// «Сводка ящиков» (2.7.4; предложение пользователя с 4PDA 25.11.2026,
// решение владельца 26.11.2026: «давай попробуем»; отдельный раздел, как
// «Мой день», — на нижней панели, в меню и при запуске).
//
// Карточка на каждый ящик: портрет, название, когда обновлялось, сколько
// непрочитанных во «Входящих», три последних непрочитанных письма, папки,
// выбранные для сводки (с числом непрочитанных), «Исходящие» (если там
// что-то ждёт) и «Вся почта» ящика. Нажатие — «Входящие» или папка ящика в
// ленте; «Назад» из ленты — снова сводка, если она открывается при запуске
// («Настройки → Почта → Открывать при запуске»). Наверху — «Все ящики».

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_router.dart' show mailOpenPath;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/folder_icons.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/accounts/account_labels.dart' show accountLabelsProvider;
import '../../../services/sync/sync_service.dart' show syncServiceProvider;
import '../../../widgets/common/account_avatar.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../settings/providers/account_groups_provider.dart' show activeGroupIdProvider;
import '../../settings/providers/settings_provider.dart';
import '../providers/folder_names.dart';
import '../providers/mail_providers.dart';
import '../widgets/mail_freshness_line.dart';
import 'outbox_screen.dart' show OutboxItem, outboxItemsProvider, kOutboxFolderId;

/// Папки ящиков на сводке (кроме «Входящих» — они всегда): ящик → папки.
class BoardFoldersNotifier extends Notifier<Map<String, List<String>>> {
  static const prefKey = 'board_folders';

  @override
  Map<String, List<String>> build() {
    try {
      final raw = ref.read(sharedPrefsProvider).getString(prefKey);
      if (raw == null) return const {};
      final m = jsonDecode(raw) as Map;
      return {
        for (final e in m.entries)
          if (e.value is List) '${e.key}': [for (final v in e.value as List) '$v'],
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> set(String accountId, List<String> folderIds) async {
    state = {...state, accountId: List.unmodifiable(folderIds)};
    await ref.read(sharedPrefsProvider).setString(prefKey, jsonEncode(state));
  }
}

final boardFoldersProvider =
    NotifierProvider<BoardFoldersNotifier, Map<String, List<String>>>(BoardFoldersNotifier.new);

/// Непрочитанное письмо на карточке.
typedef BoardMail = ({String id, String from, String subject, DateTime at});

/// Последние непрочитанные письма папки (не больше трёх) — живой поток.
final boardUnreadProvider =
    StreamProvider.family<List<BoardMail>, ({String accountId, String folderId})>((ref, key) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        'SELECT id, from_name, from_email, subject, received_at FROM emails '
        'WHERE account_id = ? AND folder_id = ? AND is_read = 0 '
        'ORDER BY received_at DESC LIMIT 3',
        variables: [Variable.withString(key.accountId), Variable.withString(key.folderId)],
        readsFrom: {db.emails},
      )
      .watch()
      .map((rows) => [
            for (final r in rows)
              (
                id: r.read<String>('id'),
                from: (r.readNullable<String>('from_name') ?? '').trim().isNotEmpty
                    ? r.read<String>('from_name').trim()
                    : r.read<String>('from_email'),
                subject: r.read<String>('subject'),
                at: r.read<DateTime>('received_at'),
              ),
          ]);
});

/// Открыть ящик из сводки: «Входящие» или папку ([folderId]), «Всю почту»
/// ящика ([folderId] null) или все ящики сразу ([accountId] null).
Future<void> openFromBoard(BuildContext context, WidgetRef ref, {String? accountId, String? folderId}) async {
  ref.read(activeGroupIdProvider.notifier).state = null;
  ref.read(mailFilterProvider.notifier).state = MailFilter.none;
  // Сначала без папки: смена ящика с открытой папкой подбирает «такую же
  // папку» нового ящика (folder_follow.dart) — здесь папка выбрана явно.
  ref.read(selectedFolderIdProvider.notifier).state = null;
  ref.read(unifiedModeProvider.notifier).state = true;
  if (accountId == null) {
    ref.read(allAccountsModeProvider.notifier).state = true;
  } else {
    ref.read(allAccountsModeProvider.notifier).state = false;
    if (ref.read(activeAccountProvider)?.id != accountId) {
      await ref.read(settingsProvider.notifier).setActiveAccountId(accountId);
    }
    if (folderId != null) {
      ref.read(unifiedModeProvider.notifier).state = false;
      ref.read(selectedFolderIdProvider.notifier).state = folderId;
    }
  }
  if (context.mounted) context.go('/mail');
}

class AccountsBoardScreen extends ConsumerWidget {
  const AccountsBoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = [for (final a in ref.watch(accountsProvider)) if (a.isActive) a];
    final outbox = ref.watch(outboxItemsProvider).value ?? const <OutboxItem>[];
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('boardTitle')))),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncServiceProvider).syncAll(fresh: true),
        child: ListView(
          key: const ValueKey('board_list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            if (accounts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(child: Text(l10n.tr('noAccounts'))),
              ),
            if (accounts.length > 1) const _AllAccountsCard(),
            for (final a in accounts)
              _AccountCard(
                key: ValueKey('board_${a.id}'),
                account: a,
                outbox: [for (final o in outbox) if (o.accountId == a.id) o],
              ),
          ],
        ),
      ),
    );
  }
}

class _AllAccountsCard extends ConsumerWidget {
  const _AllAccountsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unread = ref.watch(totalUnreadCountProvider);
    return Card(
      key: const ValueKey('board_all'),
      margin: const EdgeInsets.only(bottom: Space.s),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(AppIcons.all_inbox),
        title: Text(l10n.tr('allAccounts'), style: theme.textTheme.titleMedium),
        trailing: _Count(unread),
        onTap: () => openFromBoard(context, ref),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  final AccountModel account;
  final List<OutboxItem> outbox;
  const _AccountCard({super.key, required this.account, required this.outbox});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final folders = ref.watch(accountFoldersProvider(account.id)).value ?? const <FolderModel>[];
    final unread = ref.watch(folderUnreadProvider(account.id)).value ?? const <String, int>{};
    final inbox = folders.where((f) => f.type == FolderType.inbox).firstOrNull;
    final chosen = ref.watch(boardFoldersProvider)[account.id] ?? const <String>[];
    final extra = [
      for (final id in chosen)
        if (folders.where((f) => f.id == id && f.id != inbox?.id).firstOrNull case final f?) f,
    ];
    final label = ref.watch(accountLabelsProvider)[account.id] ??
        (account.displayName.trim().isEmpty ? account.email : account.displayName.trim());
    final inboxUnread = inbox == null ? 0 : (unread[inbox.id] ?? 0);
    final mails = inbox == null
        ? const <BoardMail>[]
        : ref.watch(boardUnreadProvider((accountId: account.id, folderId: inbox.id))).value ?? const <BoardMail>[];
    final failed = outbox.where((o) => o.type == 'send_failed').length;
    final allUnread = ref.watch(unifiedUnreadByKeyProvider(account.id)).value;

    return Card(
      margin: const EdgeInsets.only(bottom: Space.s),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openFromBoard(context, ref, accountId: account.id, folderId: inbox?.id),
        onLongPress: () => _pickFolders(context, ref, folders, inbox, chosen),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.s),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                AccountAvatar(account: account, radius: 20),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    MailFreshnessLine(
                      accounts: [account],
                      warnColor: AppColors.warningText(context),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      tail: [if (label != account.email) TextSpan(text: account.email)],
                    ),
                  ]),
                ),
                _Count(inboxUnread),
                IconButton(
                  key: ValueKey('board_more_${account.id}'),
                  tooltip: l10n.tr('boardFolders'),
                  icon: const Icon(AppIcons.more_vert),
                  onPressed: () => _pickFolders(context, ref, folders, inbox, chosen),
                ),
              ]),
              const SizedBox(height: Space.xs),
              if (mails.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 52, bottom: Space.xs),
                  child: Text(l10n.tr('boardNoUnread'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                )
              else ...[
                for (final m in mails)
                  InkWell(
                    key: ValueKey('board_mail_${m.id}'),
                    onTap: () => context.push(mailOpenPath(context, m.id, accountId: account.id)),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 52, right: Space.s, top: Space.xxs, bottom: Space.xxs),
                      child: Row(children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: m.from, style: const TextStyle(fontWeight: FontWeight.w600)),
                              TextSpan(text: '  ${m.subject.trim().isEmpty ? '—' : m.subject.trim()}'),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        Text(AppDateFormat.time(context, m.at.toLocal()),
                            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                      ]),
                    ),
                  ),
                if (inboxUnread > mails.length)
                  Padding(
                    padding: const EdgeInsets.only(left: 52, top: Space.xxs),
                    child: Text(
                      l10n.tr('boardMoreUnread').replaceAll('{n}', '${inboxUnread - mails.length}'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
              ],
              const SizedBox(height: Space.s),
              Padding(
                padding: const EdgeInsets.only(left: 52 - Space.xs, right: Space.s),
                child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
                  for (final f in [?inbox, ...extra])
                    ActionChip(
                      key: ValueKey('board_folder_${f.id}'),
                      avatar: Icon(folderIconOf(f), size: Sizes.iconInline),
                      label: Text(_chipText(localizedFolderName(f, l10n), unread[f.id] ?? 0)),
                      onPressed: () => openFromBoard(context, ref, accountId: account.id, folderId: f.id),
                    ),
                  if (outbox.isNotEmpty)
                    ActionChip(
                      key: ValueKey('board_outbox_${account.id}'),
                      avatar: Icon(AppIcons.outbox,
                          size: Sizes.iconInline, color: failed > 0 ? AppColors.errorText(context) : null),
                      label: Text(_chipText(l10n.tr('outbox'), outbox.length),
                          style: failed > 0 ? TextStyle(color: AppColors.errorText(context)) : null),
                      onPressed: () => openFromBoard(context, ref, accountId: account.id, folderId: kOutboxFolderId),
                    ),
                  ActionChip(
                    key: ValueKey('board_allmail_${account.id}'),
                    avatar: const Icon(AppIcons.all_inbox, size: Sizes.iconInline),
                    label: Text(_chipText(l10n.allMail, allUnread ?? 0)),
                    onPressed: () => openFromBoard(context, ref, accountId: account.id),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _chipText(String name, int n) => n > 0 ? '$name  ${n > 999 ? '999+' : n}' : name;

  /// «Папки на сводке»: отметить папки ящика для карточки.
  Future<void> _pickFolders(BuildContext context, WidgetRef ref, List<FolderModel> folders, FolderModel? inbox,
      List<String> chosen) async {
    final l10n = AppLocalizations.of(context);
    final list = [
      for (final f in folders)
        if (f.id != inbox?.id && f.type != FolderType.outbox) f,
    ];
    final picked = {...chosen};
    final result = await showAppSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => Column(children: [
            ListTile(
              title: Text(l10n.tr('boardFolders'), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(l10n.tr('boardFoldersHint')),
              trailing: FilledButton(
                onPressed: () => Navigator.pop(ctx, [
                  for (final f in list)
                    if (picked.contains(f.id)) f.id,
                ]),
                child: Text(l10n.tr('done')),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(controller: scroll, children: [
                for (final f in list)
                  CheckboxListTile(
                    key: ValueKey('board_pick_${f.id}'),
                    value: picked.contains(f.id),
                    secondary: Icon(folderIconOf(f)),
                    title: Text(localizedFolderName(f, l10n)),
                    onChanged: (v) => setSheet(() => v == true ? picked.add(f.id) : picked.remove(f.id)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (result != null) unawaited(ref.read(boardFoldersProvider.notifier).set(account.id, result));
  }
}

/// Число непрочитанных — заметной меткой; ноль — пусто.
class _Count extends StatelessWidget {
  final int n;
  const _Count(this.n);

  @override
  Widget build(BuildContext context) {
    if (n <= 0) return const SizedBox(width: Space.s);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xxs),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Text(n > 999 ? '999+' : '$n',
          style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
    );
  }
}

/// Ящики строкой (2.7.4, просьба владельца 26.11.2026: внизу «Моего дня»,
/// у панели, — ящики кружками с отметкой о новых письмах): портрет, число
/// непрочитанных во «Входящих», название. Нажатие — «Входящие» ящика,
/// удержание — «Сводка ящиков». Ящиков нет — ничего.
class AccountsStrip extends ConsumerWidget {
  const AccountsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = [for (final a in ref.watch(accountsProvider)) if (a.isActive) a];
    if (accounts.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('accounts_strip'),
      color: theme.colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 76,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          children: [
            if (accounts.length > 1)
              _StripItem(
                key: const ValueKey('strip_all'),
                avatar: CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(AppIcons.all_inbox, color: theme.colorScheme.onSecondaryContainer),
                ),
                label: l10n.tr('allAccounts'),
                unread: ref.watch(totalUnreadCountProvider),
                onTap: () => openFromBoard(context, ref),
              ),
            for (final a in accounts) _AccountStripItem(key: ValueKey('strip_${a.id}'), account: a),
          ],
        ),
      ),
    );
  }
}

class _AccountStripItem extends ConsumerWidget {
  final AccountModel account;
  const _AccountStripItem({super.key, required this.account});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(accountFoldersProvider(account.id)).value ?? const <FolderModel>[];
    final inbox = folders.where((f) => f.type == FolderType.inbox).firstOrNull;
    final unread = inbox == null ? 0 : (ref.watch(folderUnreadProvider(account.id)).value?[inbox.id] ?? 0);
    final label = ref.watch(accountLabelsProvider)[account.id] ??
        (account.displayName.trim().isEmpty ? account.email : account.displayName.trim());
    return _StripItem(
      avatar: AccountAvatar(account: account, radius: 20),
      label: label,
      unread: unread,
      onTap: () => openFromBoard(context, ref, accountId: account.id, folderId: inbox?.id),
    );
  }
}

class _StripItem extends StatelessWidget {
  final Widget avatar;
  final String label;
  final int unread;
  final VoidCallback onTap;
  const _StripItem({super.key, required this.avatar, required this.label, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: unread > 0 ? '$label, $unread' : label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        onLongPress: () => context.go('/accounts'),
        child: SizedBox(
          width: 68,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              avatar,
              if (unread > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: scheme.surfaceContainerLow, width: 1.5),
                    ),
                    child: Text(unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onError, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
            ]),
            const SizedBox(height: Space.xxs),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }
}

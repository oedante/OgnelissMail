// lib/features/mail/widgets/sender_actions_sheet.dart
//
// «Заблокировать отправителя» и «Чистка» (1.10.x, просьба владельца
// 01.11.2026) — шторки из меню письма. Правила — sender_rules_service.dart;
// правило на сервере при блокировке — sender_block_server.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/server_filters.dart';
import '../../../services/rules/sender_rules_service.dart';
import '../../../widgets/common/app_sheet.dart';
import 'sender_block_server.dart';

String _domainOf(String email) {
  final e = email.toLowerCase().trim();
  final at = e.lastIndexOf('@');
  return at >= 0 ? e.substring(at + 1) : '';
}

/// Итог шторки блокировки.
typedef _BlockChoice = ({String pattern, bool moveExisting, bool onServer});

/// Заблокировать отправителя письма [email] (или разблокировать, если он
/// уже заблокирован). Возвращает сообщение для строки внизу экрана или null.
Future<String?> blockSender(BuildContext context, WidgetRef ref,
    {required AccountModel account, required EmailModel email}) async {
  final l10n = AppLocalizations.of(context);
  final rules = ref.read(senderRulesProvider.notifier);
  final from = email.from.email.toLowerCase().trim();
  if (from.isEmpty) return null;
  if (rules.blockFor(from, accountId: account.id) != null) {
    rules.unblock(from);
    return l10n.tr('senderUnblocked').replaceAll('{sender}', from);
  }
  final serverKind = ServerFilters.kindOf(account);
  final choice = await showAppSheet<_BlockChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _BlockSheet(
      email: from,
      name: email.from.displayName,
      domainAllowed: !publicMailDomains.contains(_domainOf(from)) && _domainOf(from).isNotEmpty,
      serverPossible: serverKind != ServerFilterKind.webOnly,
    ),
  );
  if (choice == null) return null;
  rules.add(choice.pattern, SenderAction.block);
  var moved = 0;
  if (choice.moveExisting) moved = await rules.moveAllToJunk(account, choice.pattern);
  var serverNote = '';
  if (choice.onServer && context.mounted) {
    final err = await blockOnServer(ref, account, choice.pattern);
    serverNote = err == null ? ' ${l10n.tr('senderBlockedServerOk')}' : ' ${l10n.tr('senderBlockedServerFailed')}';
  }
  final label = choice.pattern.contains('@') ? choice.pattern : '@${choice.pattern}';
  final base = moved > 0
      ? l10n.tr('senderBlockedMoved').replaceAll('{sender}', label).replaceAll('{n}', '$moved')
      : l10n.tr('senderBlocked').replaceAll('{sender}', label);
  return '$base$serverNote';
}

class _BlockSheet extends StatefulWidget {
  final String email;
  final String? name;
  final bool domainAllowed;
  final bool serverPossible;
  const _BlockSheet({required this.email, this.name, required this.domainAllowed, required this.serverPossible});

  @override
  State<_BlockSheet> createState() => _BlockSheetState();
}

class _BlockSheetState extends State<_BlockSheet> {
  bool _domain = false;
  bool _moveExisting = true;
  late bool _onServer = widget.serverPossible;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    final domain = _domainOf(widget.email);
    final who = (widget.name ?? '').trim().isNotEmpty ? '${widget.name!.trim()} · ${widget.email}' : widget.email;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(AppIcons.block, color: theme.colorScheme.error),
            const SizedBox(width: Space.m),
            Expanded(child: Text(l10n.tr('blockSenderTitle'), style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: Space.xs),
          Text(who, style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.s),
          Text(l10n.tr('blockSenderDesc'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: Space.s),
          if (widget.domainAllowed) ...[
            RadioGroup<bool>(
              groupValue: _domain,
              onChanged: (v) => setState(() => _domain = v ?? false),
              child: Column(children: [
                RadioListTile<bool>(
                  value: false,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.tr('blockOnlyAddress').replaceAll('{email}', widget.email)),
                ),
                RadioListTile<bool>(
                  value: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.tr('blockWholeDomain').replaceAll('{domain}', domain)),
                ),
              ]),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _moveExisting,
            onChanged: (v) => setState(() => _moveExisting = v),
            title: Text(l10n.tr('blockMoveExisting')),
          ),
          if (widget.serverPossible)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _onServer,
              onChanged: (v) => setState(() => _onServer = v),
              title: Text(l10n.tr('blockOnServer')),
              subtitle: Text(l10n.tr('blockOnServerDesc'), style: muted),
            ),
          const SizedBox(height: Space.m),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              minimumSize: const Size.fromHeight(Sizes.tapTarget),
            ),
            icon: const Icon(AppIcons.block),
            label: Text(l10n.tr('blockSenderAction')),
            onPressed: () => Navigator.of(context).pop((
              pattern: _domain ? domain : widget.email,
              moveExisting: _moveExisting,
              onServer: widget.serverPossible && _onServer,
            )),
          ),
        ],
      ),
    );
  }
}

/// «Чистка» по отправителю письма [email] (как Sweep в Outlook). Возвращает
/// сообщение для строки внизу экрана или null.
Future<String?> sweepSender(BuildContext context, WidgetRef ref,
    {required AccountModel account, required EmailModel email}) async {
  final l10n = AppLocalizations.of(context);
  final from = email.from.email.toLowerCase().trim();
  if (from.isEmpty) return null;
  final rules = ref.read(senderRulesProvider.notifier);
  final count = (await rules.mailsFrom(account, from)).length;
  if (!context.mounted) return null;
  final pick = await showAppSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SweepSheet(email: from, name: email.from.displayName, count: count),
  );
  if (pick == null) return null;
  switch (pick) {
    case 'all':
      final n = await rules.deleteAll(account, from);
      return l10n.tr('sweepDeleted').replaceAll('{n}', '$n');
    case 'allFuture':
      final n = await rules.deleteAll(account, from);
      rules.add(from, SenderAction.deleteFuture, accountId: account.id);
      return '${l10n.tr('sweepDeleted').replaceAll('{n}', '$n')} ${l10n.tr('sweepFutureOn')}';
    case 'latest':
      rules.add(from, SenderAction.keepLatest, accountId: account.id);
      final n = await rules.keepOnlyLatest(account, from);
      return l10n.tr('sweepKeepLatestOn').replaceAll('{n}', '$n');
    case 'older':
      rules.add(from, SenderAction.olderThan, days: 10, accountId: account.id);
      final n = await rules.deleteOlderThan(account, from, 10);
      return l10n.tr('sweepOlderOn').replaceAll('{days}', '10').replaceAll('{n}', '$n');
  }
  return null;
}

class _SweepSheet extends StatelessWidget {
  final String email;
  final String? name;
  final int count;
  const _SweepSheet({required this.email, this.name, required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    Widget row(IconData icon, String title, String? subtitle, String value, {Color? color}) => ListTile(
          minTileHeight: Sizes.tapTarget,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
          leading: Icon(icon, color: color),
          title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
          subtitle: subtitle == null ? null : Text(subtitle, style: muted),
          onTap: () => Navigator.of(context).pop(value),
        );
    final who = (name ?? '').trim().isNotEmpty ? '${name!.trim()} · $email' : email;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.tr('sweepTitle'), style: theme.textTheme.titleMedium),
                Text(who, style: muted, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(l10n.tr('sweepInInbox').replaceAll('{n}', '$count'), style: muted),
              ]),
            ),
            row(AppIcons.delete_sweep, l10n.tr('sweepDeleteAll'), null, 'all', color: theme.colorScheme.error),
            row(AppIcons.delete_sweep, l10n.tr('sweepDeleteAllFuture'), l10n.tr('sweepDeleteAllFutureDesc'), 'allFuture',
                color: theme.colorScheme.error),
            row(AppIcons.history, l10n.tr('sweepKeepLatest'), l10n.tr('sweepKeepLatestDesc'), 'latest'),
            row(AppIcons.cleaning_services, l10n.tr('sweepOlder10'), l10n.tr('sweepOlder10Desc'), 'older'),
          ],
        ),
      ),
    );
  }
}

/// Показать итог действия строкой внизу экрана.
void showSenderActionResult(BuildContext context, String? message) {
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}

/// Для меню письма: заблокирован ли отправитель (подпись пункта).
bool isSenderBlocked(WidgetRef ref, String fromEmail, String accountId) =>
    ref.read(senderRulesProvider.notifier).blockFor(fromEmail, accountId: accountId) != null;

/// Запустить без ожидания (меню закрывается сразу).
void runSenderAction(BuildContext context, Future<String?> Function() action) {
  unawaited(action().then((m) {
    if (context.mounted) showSenderActionResult(context, m);
  }));
}

// lib/features/mail/screens/subscriptions_screen.dart
// «Рассылки» (боковое меню → у папок ящика, значок «?» — пояснение; до
// 10.10.2026 — Ещё → «Рассылки»): отправители писем с заголовком
// List-Unsubscribe — сколько писем за 30 дней, когда было последнее, и
// «Отписаться» (те же варианты, что в письме: в одно нажатие — только при
// подтверждённом отправителе, страница отписки, письмо). Сначала самые
// частые. Данные — из телефона, без запросов к серверу. [accountId] — только
// этот ящик (из меню папок), без него — все ящики.

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/unsubscribe_service.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../core/utils/text_safe.dart';
import '../providers/mail_providers.dart';
import '../widgets/unsubscribe_banner.dart' show runUnsubscribe, isUnsubscribed;
import '../../../core/theme/ogneliss_look.dart';

class _Sub {
  final String accountId;
  final String sender;
  final String name;
  final int month;
  final int total;
  final DateTime last;
  final String lastId;
  const _Sub(this.accountId, this.sender, this.name, this.month, this.total, this.last, this.lastId);
}

final _subsProvider = FutureProvider.autoDispose.family<List<_Sub>, String?>((ref, accountId) async {
  final db = ref.watch(databaseProvider);
  final ids = [
    for (final a in ref.watch(accountsProvider))
      if (accountId == null || a.id == accountId) a.id,
  ];
  if (ids.isEmpty) return const [];
  final since = DateTime.now().subtract(const Duration(days: 30));
  final marks = List.filled(ids.length, '?').join(',');
  final rows = await db.customSelect(
    'SELECT account_id, LOWER(from_email) AS sender, MAX(from_name) AS name, COUNT(*) AS total, '
    'SUM(CASE WHEN received_at >= ? THEN 1 ELSE 0 END) AS month, MAX(received_at) AS last '
    'FROM emails WHERE list_unsubscribe IS NOT NULL AND account_id IN ($marks) '
    'GROUP BY account_id, LOWER(from_email) ORDER BY month DESC, last DESC LIMIT 300',
    variables: [Variable.withDateTime(since), for (final id in ids) Variable.withString(id)],
    readsFrom: {db.emails},
  ).get();
  final out = <_Sub>[];
  for (final r in rows) {
    final acc = r.read<String>('account_id');
    final sender = r.read<String>('sender');
    final last = r.read<DateTime>('last');
    // Последнее письмо отправителя — по нему отписка (в нём заголовок).
    final latest = await (db.select(db.emails)
          ..where((e) => e.accountId.equals(acc) & e.fromEmail.lower().equals(sender) & e.listUnsubscribe.isNotNull())
          ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
          ..limit(1))
        .getSingleOrNull();
    if (latest == null) continue;
    final info = ListUnsubscribe.parse(latest.listUnsubscribe);
    final name = info?.listName ?? (r.readNullable<String>('name') ?? '').trim();
    out.add(_Sub(acc, sender, name.isEmpty ? sender : fixUtf16(name), r.read<int>('month'), r.read<int>('total'), last,
        latest.id));
  }
  return out;
});

class SubscriptionsScreen extends ConsumerStatefulWidget {
  /// Только этот ящик; null — все.
  final String? accountId;
  const SubscriptionsScreen({super.key, this.accountId});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  final _busy = <String>{};
  final _failed = <String>{};

  Future<void> _unsubscribe(_Sub s) async {
    final acc = ref.read(accountsProvider).where((a) => a.id == s.accountId).firstOrNull;
    final row = await ref.read(databaseProvider).getEmailById(s.lastId, accountId: s.accountId);
    if (acc == null || row == null || !mounted) return;
    final email = emailModelFromRow(row);
    final info = ListUnsubscribe.parse(email.listUnsubscribe);
    if (info == null) return;
    final key = '${s.accountId}|${s.sender}';
    final r = await runUnsubscribe(context, ref, acc, email, info, onBusy: (b) {
      if (mounted) setState(() => b ? _busy.add(key) : _busy.remove(key));
    });
    if (!mounted || r == null) return;
    setState(() => r ? _failed.remove(key) : _failed.add(key));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final data = ref.watch(_subsProvider(widget.accountId));
    final account = widget.accountId == null
        ? null
        : ref.watch(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: account == null
              ? Text(l10n.tr('subscriptionsTitle'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(l10n.tr('subscriptionsTitle')),
                  Text(account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ]),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: AppIcons.unsubscribe,
              title: l10n.tr('noSubscriptionsFound'),
              message: l10n.tr('subscriptionsHint'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: Space.xl),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const RowDivider(indent: 72),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
                  child: Text(l10n.tr('subscriptionsHint'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                );
              }
              final s = list[i - 1];
              final key = '${s.accountId}|${s.sender}';
              final done = isUnsubscribed(ref, s.sender);
              final when = DateFormat('d MMM', l10n.localeCode).format(s.last.toLocal());
              return ListTile(
                leading: HeroEmailAvatar(
                  emailId: 'sub_$key',
                  initial: initialOf(s.name),
                  color: HeroEmailAvatar.colorForEmail(s.sender),
                  email: s.sender,
                  hero: false,
                ),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  _failed.contains(key)
                      ? l10n.tr('unsubscribeFailed')
                      : '${l10n.tr('subscriptionsMonth').replaceAll('{n}', '${s.month}')} · $when · ${s.sender}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _failed.contains(key) ? TextStyle(color: AppColors.errorText(context)) : null,
                ),
                trailing: _busy.contains(key)
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : done
                        ? Text(l10n.tr('unsubscribed'), style: theme.textTheme.labelLarge?.copyWith(color: muted))
                        : TextButton(onPressed: () => _unsubscribe(s), child: Text(l10n.tr('unsubscribe'))),
              );
            },
          );
        },
      ),
    );
  }
}

// lib/features/mail/widgets/scheduled_sends.dart
// Запланированные письма (1.6.49, как «Отложенные сообщения» в Telegram):
// строка над лентой «Запланировано: 2 · ближайшее завтра, 09:00», нажатие —
// шторка со списком: «Отправить сейчас», «Другое время», «Отменить».
// Раньше отложенное письмо было видно только в «Моём дне», а поменять время
// было нельзя вовсе.
//
// Письма лежат в очереди отправки (sync_queue, targetId «scheduled_…»):
// поток следит только за номером, ящиком и длиной строки, а полное
// содержимое (в нём и вложения base64) читается один раз на изменение.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Variable;

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../core/utils/send_later_presets.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/offline_send_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../widgets/ui/section_band.dart';
import '../../../widgets/ui/wheel_pickers.dart';
import '../providers/mail_providers.dart' show accountsProvider;
import 'later_sheet.dart' show laterWhenLabel;
import '../../../core/theme/ogneliss_look.dart';

class ScheduledSend {
  final int queueId;
  final String accountId;
  final DateTime at;
  final String subject;

  /// Кому: первый адресат и «+N».
  final String who;

  const ScheduledSend({
    required this.queueId,
    required this.accountId,
    required this.at,
    required this.subject,
    required this.who,
  });

  @override
  bool operator ==(Object other) =>
      other is ScheduledSend &&
      other.queueId == queueId &&
      other.accountId == accountId &&
      other.at == at &&
      other.subject == subject &&
      other.who == who;

  @override
  int get hashCode => Object.hash(queueId, accountId, at, subject, who);

  /// Разбор строки очереди; null — не отложенное письмо или битая строка.
  static ScheduledSend? fromPayload(int id, String accountId, String json) {
    try {
      final p = jsonDecode(json) as Map<String, dynamic>;
      final at = DateTime.tryParse(p['scheduledAt'] as String? ?? '');
      if (at == null) return null;
      final to = (p['to'] as List? ?? const []).whereType<Map>().toList();
      String name(Map m) {
        final d = (m['displayName'] as String?)?.trim() ?? '';
        return d.isNotEmpty ? d : (m['email'] as String? ?? '');
      }

      final first = to.isEmpty ? '' : name(to.first);
      return ScheduledSend(
        queueId: id,
        accountId: accountId,
        at: at.toLocal(),
        subject: (p['subject'] as String? ?? '').trim(),
        who: to.length > 1 ? '$first +${to.length - 1}' : first,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Отложенные письма всех ящиков, ближайшее первым.
final scheduledSendsProvider = StreamProvider.autoDispose<List<ScheduledSend>>((ref) {
  final db = ref.watch(databaseProvider);
  // Разобранные строки: номер → (длина содержимого, письмо). Содержимое
  // перечитывается, если сменилась длина или время меняли из приложения
  // (ScheduledSendsCache.dirty: 12:00 → 13:00 длину не меняет).
  final cache = <int, (int, ScheduledSend?)>{};
  return db
      .customSelect(
        'SELECT id, account_id, LENGTH(payload_json) AS len FROM sync_queue '
        "WHERE operation_type = 'send_email' AND target_id LIKE 'scheduled_%'",
        readsFrom: {db.syncQueue},
      )
      .watch()
      .asyncMap((rows) async {
        final out = <ScheduledSend>[];
        final seen = <int>{};
        for (final r in rows) {
          final id = r.read<int>('id');
          final len = r.read<int>('len');
          seen.add(id);
          final hit = cache[id];
          final dirty = ScheduledSendsCache.dirty.remove(id);
          if (hit == null || hit.$1 != len || dirty) {
            final p = await db
                .customSelect('SELECT payload_json FROM sync_queue WHERE id = ?', variables: [Variable.withInt(id)])
                .getSingleOrNull();
            cache[id] = (
              len,
              p == null ? null : ScheduledSend.fromPayload(id, r.read<String>('account_id'), p.read<String>('payload_json')),
            );
          }
          final s = cache[id]?.$2;
          if (s != null) out.add(s);
        }
        cache.removeWhere((k, _) => !seen.contains(k));
        out.sort((a, b) => a.at.compareTo(b.at));
        return out;
      })
      .distinct((a, b) => listEquals(a, b));
});

/// Строки, у которых время поменяли из приложения: поток перечитает их при
/// следующем изменении таблицы.
abstract final class ScheduledSendsCache {
  static final Set<int> dirty = {};
}

/// Строка над лентой: «Запланировано: N · ближайшее …».
class ScheduledSendStrip extends ConsumerWidget {
  const ScheduledSendStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(scheduledSendsProvider).value ?? const <ScheduledSend>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = list.first;
    return Padding(
      padding: const EdgeInsets.only(left: Space.l, top: Space.s, right: Space.l),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showScheduledSends(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(children: [
              Icon(AppIcons.schedule_send, size: Sizes.iconInline, color: scheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  l10n
                      .tr('schedStrip')
                      .replaceAll('{n}', '${list.length}')
                      .replaceAll('{when}', laterWhenLabel(next.at, l10n)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
              ),
              Icon(AppIcons.chevron_right, size: Sizes.iconInline, color: scheme.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Шторка со списком отложенных писем.
Future<void> showScheduledSends(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ScheduledSheet(),
    );

class _ScheduledSheet extends ConsumerWidget {
  const _ScheduledSheet();

  Future<void> _reschedule(BuildContext context, WidgetRef ref, ScheduledSend s) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final service = ref.read(offlineSendProvider);
    final picked = await showWheelDateTimePicker(
      context,
      initial: s.at.isAfter(now) ? s.at : now.add(const Duration(hours: 1)),
      first: now.add(const Duration(minutes: 5)),
      last: now.add(const Duration(days: 365)),
      title: l10n.tr('schedChange'),
      presets: [
        for (final p in SendLaterPresets.of(now))
          (l10n.tr(SendLaterPresets.labelKey(p)).replaceAll('{time}', AppDateFormat.time(context, p.at)), p.at),
      ],
    );
    if (picked == null) return;
    ScheduledSendsCache.dirty.add(s.queueId);
    if (!await service.rescheduleQueued(s.queueId, picked)) showInlineError(l10n.tr('schedGone'));
  }

  Future<void> _sendNow(WidgetRef ref, ScheduledSend s, AppLocalizations l10n) async {
    ScheduledSendsCache.dirty.add(s.queueId);
    if (!await ref.read(offlineSendProvider).rescheduleQueued(s.queueId, DateTime.now())) {
      showInlineError(l10n.tr('schedGone'));
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, ScheduledSend s) async {
    final l10n = AppLocalizations.of(context);
    final service = ref.read(offlineSendProvider);
    final ok = await confirmDestructive(context,
        title: l10n.tr('myDayDeferredCancelQ'),
        message: s.subject.isEmpty ? l10n.tr('noSubject') : s.subject,
        action: l10n.tr('myDayDeferredCancel'));
    if (!ok) return;
    if (!await service.cancelQueued(s.queueId)) showInlineError(l10n.tr('schedGone'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final list = ref.watch(scheduledSendsProvider).value ?? const <ScheduledSend>[];
    final accounts = ref.watch(accountsProvider);
    final many = accounts.length > 1;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionBand(title: l10n.tr('schedTitle')),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(l10n.tr('schedEmpty'), textAlign: TextAlign.center, style: TextStyle(color: muted)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: Space.l),
              itemCount: list.length,
              separatorBuilder: (_, __) => const RowDivider(indent: Space.l + Sizes.icon + Space.l),
              itemBuilder: (context, i) {
                final s = list[i];
                final box = many ? accounts.where((a) => a.id == s.accountId).firstOrNull?.email : null;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.xs),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(AppIcons.schedule_send, size: Sizes.icon, color: theme.colorScheme.primary),
                      const SizedBox(width: Space.l),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.subject.isEmpty ? l10n.tr('noSubject') : s.subject,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                          Text(
                            [
                              l10n.tr('myDayDeferredSends').replaceAll('{when}', laterWhenLabel(s.at, l10n)),
                              if (s.who.isNotEmpty) '${l10n.tr('to')}: ${s.who}',
                              if (box != null) box,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ]),
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(left: Sizes.icon + Space.m),
                      child: Wrap(spacing: Space.xs, children: [
                        TextButton.icon(
                          onPressed: () => unawaited(_sendNow(ref, s, l10n)),
                          icon: const Icon(AppIcons.send, size: Sizes.iconInline),
                          label: Text(l10n.tr('schedSendNow')),
                        ),
                        TextButton.icon(
                          onPressed: () => unawaited(_reschedule(context, ref, s)),
                          icon: const Icon(AppIcons.schedule, size: Sizes.iconInline),
                          label: Text(l10n.tr('schedChange')),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: AppColors.errorText(context)),
                          onPressed: () => unawaited(_cancel(context, ref, s)),
                          icon: const Icon(AppIcons.close, size: Sizes.iconInline),
                          label: Text(l10n.tr('myDayDeferredCancel')),
                        ),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}

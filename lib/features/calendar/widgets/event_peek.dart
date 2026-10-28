// lib/features/calendar/widgets/event_peek.dart
// Карточка встречи по удержанию (1.6.47, «как в Telegram», как у писем):
// цвет календаря, тема, когда, где, организатор; под карточкой — кнопки.
//   · Чужая встреча без моего ответа — «Принять», «Под вопросом»,
//     «Отклонить» (ответ сразу уходит организатору).
//   · Есть ссылка на онлайн-встречу — «Войти во встречу».
//   · Иначе — «Изменить», «Поделиться».
//   · «Ещё» — все действия по группам здесь же (1.6.49+95; раньше —
//     меню-шторка): «Встреча» (открыть, изменить, копия, поделиться),
//     «Ответ», удалить.
// Касание карточки — открыть встречу. Раньше удержание сразу открывало
// меню-шторку снизу.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../data/database/app_database.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/meeting_link_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/common/peek_card.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../calendar_event_actions.dart';

/// Показать карточку встречи у пальца (место строки календарю неизвестно).
Future<void> showEventPeek(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent e, {
  required Color color,
  required VoidCallback onOpen,
  required VoidCallback onDuplicate,
}) {
  final l10n = AppLocalizations.of(context);
  final account = ref.read(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
  final url = (e.onlineMeetingUrl ?? '').trim();
  final link = url.isNotEmpty ? url : MeetingLinkService.find(location: e.location, description: e.description)?.url;
  final org = (e.organizerEmail ?? '').trim();
  final master = MailEngineService.isOccurrenceId(e.id) ? e.id.substring(0, e.id.indexOf('#')) : e.id;
  final answered =
      account == null ? null : ref.read(sharedPrefsProvider).getString('evt_resp:${account.id}:$master');
  // Ответа ещё нет: сервер ставит такую встречу «под вопросом» (показ — 1),
  // пока на приглашение не ответят.
  final ask = account != null &&
      org.isNotEmpty &&
      !OwnAddresses.isMine(account, org) &&
      !e.isCancelled &&
      e.endTime.isAfter(DateTime.now()) &&
      ref.read(mailEngineServiceProvider).canRespondToEvent(account) &&
      answered == null &&
      e.showAs == 1;

  PeekAction answer(String response, IconData icon, String label, Color c) => PeekAction(
        icon: icon,
        label: label,
        color: c,
        onTap: () => unawaited(CalendarEventActions.respondNow(ref, account!, e, response, l10n)),
      );

  return showPeekCard(
    context,
    anchor: peekAnchorAtFinger(context),
    onOpen: onOpen,
    card: _EventCard(event: e, color: color, organizer: (account != null && OwnAddresses.isMine(account, org)) ? null : org),
    actions: [
      if (ask) ...[
        answer('accept', AppIcons.check, l10n.tr('accept'), AppColors.successText(context)),
        answer('tentative', AppIcons.help, l10n.tr('meetingTentative'), AppColors.accentOrangeText(context)),
        answer('decline', AppIcons.close, l10n.tr('decline'), AppColors.errorText(context)),
      ],
      if (link != null)
        PeekAction(
          icon: AppIcons.videocam,
          label: l10n.tr('peekJoin'),
          onTap: () => unawaited(_join(link, l10n)),
        ),
      if (!ask) ...[
        PeekAction(
          icon: AppIcons.edit,
          label: l10n.tr('peekEdit'),
          onTap: () => context.push('/create-event', extra: e),
        ),
        PeekAction(
          icon: AppIcons.share,
          label: l10n.tr('share'),
          onTap: () => unawaited(CalendarEventActions.share(context, e)),
        ),
      ],
    ],
    moreLabel: l10n.tr('peekMore'),
    more: [
      PeekGroup(title: l10n.tr('peekGroupEvent'), items: [
        PeekAction(icon: AppIcons.open_in_full, label: l10n.tr('ntfOpen'), onTap: onOpen),
        PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: () => context.push('/create-event', extra: e)),
        PeekAction(icon: AppIcons.copy_all, label: l10n.tr('duplicateEvent'), onTap: onDuplicate),
        PeekAction(icon: AppIcons.share, label: l10n.tr('share'), onTap: () => unawaited(CalendarEventActions.share(context, e))),
        if (link != null)
          PeekAction(icon: AppIcons.videocam, label: l10n.tr('peekJoin'), onTap: () => unawaited(_join(link, l10n))),
      ]),
      if (ask)
        PeekGroup(title: l10n.tr('peekGroupAnswer'), items: [
          answer('accept', AppIcons.check, l10n.tr('accept'), AppColors.successText(context)),
          answer('tentative', AppIcons.help, l10n.tr('meetingTentative'), AppColors.accentOrangeText(context)),
          answer('decline', AppIcons.close, l10n.tr('decline'), AppColors.errorText(context)),
        ]),
      PeekGroup(items: [
        PeekAction(
          icon: AppIcons.delete,
          label: l10n.delete,
          color: AppColors.errorText(context),
          onTap: () => unawaited(CalendarEventActions.delete(context, ref, e)),
        ),
      ]),
    ],
  );
}

Future<void> _join(String link, AppLocalizations l10n) async {
  final uri = Uri.tryParse(link);
  var ok = false;
  if (uri != null) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok) showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', link));
}

class _EventCard extends StatelessWidget {
  final CalendarEvent event;
  final Color color;

  /// Организатор (не я) — строкой; null — не показывать.
  final String? organizer;

  const _EventCard({required this.event, required this.color, this.organizer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final e = event;
    final s = e.startTime.toLocal();
    final end = e.endTime.toLocal();
    final sameDay = s.year == end.year && s.month == end.month && s.day == end.day;
    final when = e.isAllDay
        ? '${AppDateFormat.dayMonth(context, s)} · ${l10n.tr('allDay')}'
        : sameDay
            ? '${AppDateFormat.dayMonthTime(context, s)}–${AppDateFormat.time(context, end)}'
            : '${AppDateFormat.dayMonthTime(context, s)} – ${AppDateFormat.dayMonthTime(context, end)}';
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(text,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ),
          ]),
        );
    final where = (e.location ?? '').trim();
    final org = (organizer ?? '').trim();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 6, color: color),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(e.title.trim().isEmpty ? l10n.tr('noSubject') : e.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: e.isCancelled ? TextDecoration.lineThrough : null,
                  )),
              if (e.isCancelled) line(AppIcons.event_busy, l10n.tr('meetingCanceled')),
              line(AppIcons.schedule, when),
              if (where.isNotEmpty) line(AppIcons.place, where),
              if (org.isNotEmpty) line(AppIcons.person, org),
            ]),
          ),
        ),
      ]),
    );
  }
}

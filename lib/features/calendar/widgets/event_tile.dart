// lib/features/calendar/widgets/event_tile.dart
// Карточка события в списках («Расписание», день под месяцем): цветная полоса
// ящика, время, тема, место, отметки (онлайн-встреча, повтор, участники).

import 'package:flutter/material.dart';
import '../../../widgets/common/quick_long_press.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/database/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/meeting_link_service.dart';
import '../calendar_data.dart';
import '../../contacts/person_names.dart' show personNamesProvider, fullPersonNameProvider, bestPersonName;

class EventTile extends StatelessWidget {
  final CalendarEvent event;
  /// День списка: у многодневного события показываем «весь день» или
  /// время начала/конца для этого дня.
  final DateTime day;
  final Color color;
  final bool isRussian;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const EventTile({
    super.key,
    required this.event,
    required this.day,
    required this.color,
    required this.isRussian,
    required this.now,
    required this.onTap,
    this.onLongPress,
  });

  String _timeLabel(AppLocalizations l10n) {
    final e = event;
    final s = e.startTime.toLocal();
    final en = e.endTime.toLocal();
    final hm = DateFormat('HH:mm');
    if (isTaskItem(e)) {
      return e.isAllDay
          ? l10n.tr('calDueToday')
          : l10n.tr('calDueAt').replaceAll('{time}', hm.format(s));
    }
    if (isMailItem(e)) return l10n.tr('calFollowUpAt').replaceAll('{time}', hm.format(s));
    if (isInviteItem(e)) {
      return '${l10n.tr('invitePendingOne')} · ${e.isAllDay ? l10n.tr('allDay') : '${hm.format(s)} – ${hm.format(en)}'}';
    }
    if (e.isAllDay) return l10n.tr('allDay');
    final d0 = CalendarViewUtils.dayOf(day);
    final d1 = DateTime(day.year, day.month, day.day + 1);
    final startsBefore = s.isBefore(d0);
    final endsAfter = en.isAfter(d1);
    if (startsBefore && endsAfter) return l10n.tr('allDay');
    if (startsBefore) return l10n.tr('calUntilTime').replaceAll('{time}', hm.format(en));
    if (endsAfter) return l10n.tr('calFromTime').replaceAll('{time}', hm.format(s));
    return '${hm.format(s)} – ${hm.format(en)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final e = event;
    final past = e.endTime.isBefore(now) && !e.isAllDay;
    final ongoing = !e.isAllDay && e.startTime.isBefore(now) && e.endTime.isAfter(now);
    final link = (e.onlineMeetingUrl ?? '').isNotEmpty
        ? e.onlineMeetingUrl
        : MeetingLinkService.find(location: e.location, description: e.description)?.url;
    final recurring = e.recurrence != 0 || e.id.contains('#');
    final tentative = e.showAs == 1;
    final pseudo = isTaskItem(e) || isMailItem(e) || isInviteItem(e);
    final people = (isTaskItem(e) || isMailItem(e))
        ? (organizer: null, organizerName: null, organizerEmail: null, count: 0)
        : attendeeSummary(e);

    final leadIcon = isTaskItem(e)
        ? AppIcons.task_alt
        : isMailItem(e)
            ? AppIcons.flag
            : isInviteItem(e)
                ? AppIcons.event_available
                : null;

    return Opacity(
      opacity: past ? 0.55 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        elevation: 0,
        // Задачи и письма со сроком — светлее и с контуром, встречи — заливкой.
        color: color.withValues(
            alpha: pseudo
                ? 0.05
                : (theme.brightness == Brightness.dark ? 0.22 : 0.12)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: ongoing
              ? BorderSide(color: color, width: 1.5)
              : (pseudo ? BorderSide(color: color.withValues(alpha: 0.5)) : BorderSide.none),
        ),
        clipBehavior: Clip.antiAlias,
        child: QuickLongPress(
          // Удержание — 250 мс, карточка встречи (1.6.47); палец можно
          // довести до кнопки карточки.
          onLongPress: onLongPress,
          tracker: HoldPointer.instance,
          pressEffect: true,
          child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: tentative ? null : color,
                    border: tentative ? Border.all(color: color, width: 1.5) : null,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, Space.s, 10, Space.s),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (leadIcon != null) ...[
                              Icon(leadIcon, size: 16, color: color),
                              const SizedBox(width: Space.xs),
                            ],
                            Expanded(
                              child: Text(
                                e.title.isEmpty ? l10n.tr('noSubject') : e.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (e.isPrivate)
                              Padding(
                                padding: const EdgeInsets.only(left: Space.xs),
                                child: Icon(AppIcons.lock, size: 14, color: theme.hintColor),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              _timeLabel(l10n),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ongoing ? color : null,
                              ),
                            ),
                            if (ongoing) ...[
                              const SizedBox(width: 6),
                              Text(l10n.tr('calNowSuffix'),
                                  style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
                            ],
                            if (recurring) ...[
                              const SizedBox(width: 6),
                              Icon(AppIcons.repeat, size: 13, color: theme.hintColor),
                            ],
                          ],
                        ),
                        // Организатор и число участников — без открытия встречи.
                        if (people.organizer != null || people.count > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(AppIcons.group, size: 14, color: theme.hintColor),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                // Организатор — полным ФИО из контактов, писем
                                // и адресной книги (1.6.4), а не логином.
                                child: Consumer(builder: (context, ref, _) {
                                  var organizer = people.organizer;
                                  final oe = people.organizerEmail;
                                  if (oe != null) {
                                    final names = ref.watch(personNamesProvider).value ?? const <String, String>{};
                                    final dir = ref
                                        .watch(fullPersonNameProvider((email: oe, accountId: e.accountId)))
                                        .value;
                                    organizer = bestPersonName(people.organizerName, [names[oe], dir]) ?? organizer;
                                  }
                                  return Text(
                                    [
                                      if (organizer != null) organizer,
                                      if (people.count > 0)
                                        l10n.plural('calAttendeesN', people.count),
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ],
                        if ((e.location ?? '').isNotEmpty || link != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(link != null ? AppIcons.videocam : AppIcons.place,
                                  size: 14, color: theme.hintColor),
                              const SizedBox(width: Space.xs),
                              Expanded(
                                child: Text(
                                  (e.location ?? '').isNotEmpty
                                      ? e.location!
                                      : (MeetingLinkService.platformOf(link!) ??
                                          l10n.tr('calOnlineMeeting')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                                ),
                              ),
                              // «Подключиться» прямо из списка — для ещё не
                              // закончившихся онлайн-встреч.
                              if (link != null && !past)
                                TextButton.icon(
                                  onPressed: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                                  icon: const Icon(AppIcons.videocam, size: 16),
                                  label: Text(l10n.tr('calJoin')),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                                    minimumSize: const Size(0, 32),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

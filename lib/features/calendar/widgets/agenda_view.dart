// lib/features/calendar/widgets/agenda_view.dart
// «Расписание» — лента событий по дням (как Schedule в Google Календаре и
// Agenda в Outlook): заголовки месяцев, дни с событиями, свободные
// промежутки одной строкой. Начинается с сегодняшнего дня; прошедшие и
// следующие периоды подгружаются кнопками.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../calendar_data.dart';
import 'event_tile.dart';

class AgendaView extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final List<CalendarEvent> events;
  final Map<String, Color> accountColors;
  final bool isRussian;
  final DateTime now;
  final void Function(CalendarEvent) onEventTap;
  final void Function(CalendarEvent)? onEventLongPress;
  final VoidCallback onLoadEarlier;
  final VoidCallback onLoadMore;
  final void Function(DateTime day)? onEmptyDayTap;
  final ScrollController? controller;

  const AgendaView({
    super.key,
    required this.from,
    required this.to,
    required this.events,
    required this.accountColors,
    required this.isRussian,
    required this.now,
    required this.onEventTap,
    required this.onLoadEarlier,
    required this.onLoadMore,
    this.onEventLongPress,
    this.onEmptyDayTap,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final items = _buildItems();
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Align(
            child: TextButton.icon(
              onPressed: onLoadEarlier,
              icon: const Icon(AppIcons.expand_less, size: 18),
              label: Text(l10n.tr('calShowEarlier')),
            ),
          );
        }
        if (i == items.length + 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s),
            child: Align(
              child: OutlinedButton.icon(
                onPressed: onLoadMore,
                icon: const Icon(AppIcons.expand_more, size: 18),
                label: Text(l10n.tr('calShowMore')),
              ),
            ),
          );
        }
        return _item(context, theme, items[i - 1]);
      },
    );
  }

  List<_AgendaItem> _buildItems() {
    final out = <_AgendaItem>[];
    final today = CalendarViewUtils.dayOf(now);
    var d = CalendarViewUtils.dayOf(from);
    final end = CalendarViewUtils.dayOf(to);
    int? lastMonth;
    DateTime? freeFrom;
    DateTime? freeTo;

    void flushFree() {
      if (freeFrom != null) {
        out.add(_AgendaItem.free(freeFrom!, freeTo!));
        freeFrom = null;
        freeTo = null;
      }
    }

    while (d.isBefore(end)) {
      final monthKey = d.year * 12 + d.month;
      if (monthKey != lastMonth) {
        flushFree();
        out.add(_AgendaItem.month(d));
        lastMonth = monthKey;
      }
      final dayEvents = CalendarViewUtils.eventsForDay(events, d);
      final isToday = CalendarViewUtils.sameDay(d, today);
      if (dayEvents.isEmpty && !isToday) {
        freeFrom ??= d;
        freeTo = d;
      } else {
        flushFree();
        out.add(_AgendaItem.day(d, dayEvents));
      }
      d = DateTime(d.year, d.month, d.day + 1);
    }
    flushFree();
    return out;
  }

  Widget _item(BuildContext context, ThemeData theme, _AgendaItem it) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeCode;
    switch (it.kind) {
      case _Kind.month:
        return Container(
          margin: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.xs),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            capitalize(DateFormat('LLLL yyyy', locale).format(it.date)),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        );
      case _Kind.free:
        final same = CalendarViewUtils.sameDay(it.date, it.until!);
        final label = same
            ? DateFormat('EEE, d MMM', locale).format(it.date)
            : '${DateFormat('d MMM', locale).format(it.date)} – ${DateFormat('d MMM', locale).format(it.until!)}';
        return InkWell(
          onTap: onEmptyDayTap == null ? null : () => onEmptyDayTap!(it.date),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 6, Space.l, 6),
            child: Text(
              '$label · ${l10n.tr('freeStatus')}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
        );
      case _Kind.day:
        return _dayGroup(context, theme, it.date, it.events!);
    }
  }

  Widget _dayGroup(BuildContext context, ThemeData theme, DateTime day, List<CalendarEvent> list) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeCode;
    final scheme = theme.colorScheme;
    final isToday = CalendarViewUtils.sameDay(day, now);
    final tomorrow = CalendarViewUtils.sameDay(day, now.add(const Duration(days: 1)));
    final weekday = isToday
        ? l10n.tr('today')
        : tomorrow
            ? l10n.tr('tomorrow')
            : capitalize(DateFormat('EEE', locale).format(day));

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: InkWell(
              onTap: onEmptyDayTap == null ? null : () => onEmptyDayTap!(day),
              child: Column(
                children: [
                  Text(
                    weekday,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isToday ? scheme.primary : theme.hintColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.only(top: 2),
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                        : null,
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isToday ? scheme.onPrimary : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        l10n.tr('calNothingPlanned'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                      ),
                    ),
                  for (final e in list)
                    EventTile(
                      event: e,
                      day: day,
                      color: eventColor(e, accountColors),
                      isRussian: isRussian,
                      now: now,
                      onTap: () => onEventTap(e),
                      onLongPress: onEventLongPress == null ? null : () => onEventLongPress!(e),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Kind { month, day, free }

class _AgendaItem {
  final _Kind kind;
  final DateTime date;
  final DateTime? until;
  final List<CalendarEvent>? events;
  _AgendaItem.month(this.date)
      : kind = _Kind.month,
        until = null,
        events = null;
  _AgendaItem.day(this.date, this.events)
      : kind = _Kind.day,
        until = null;
  _AgendaItem.free(this.date, this.until)
      : kind = _Kind.free,
        events = null;
}

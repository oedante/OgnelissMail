// lib/features/calendar/widgets/month_grid_view.dart
// Месяц: сетка 6 недель. Выбранный день подсвечен; ниже на экране — его
// расписание.
//
// В ячейке (1.5.11, замечание 12.10.2026: «месяц выглядит грязно из-за
// обрезанных событий — в ячейке всё равно не разберёшь, что там»): на
// телефоне — значки вместо обрезанных названий: событие на весь день или
// несколько дней — полоска цвета календаря, встреча — точка, задача —
// галочка, письмо со сроком — конверт, день рождения — торт; больше
// шести — «+N». Названия плашками — только в широкой ячейке (планшет,
// альбомная ориентация), где они читаются.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../calendar_data.dart';

class MonthGridView extends StatelessWidget {
  /// Любой день месяца.
  final DateTime month;
  final List<CalendarEvent> events;
  final int weekStartDay; // 1 = пн, 7 = вс
  final bool showWeekNumbers;
  final bool isRussian;
  final DateTime? selectedDay;
  final DateTime now;
  final Map<String, Color> accountColors;
  final void Function(DateTime) onDaySelected;
  final void Function(DateTime)? onDayDoubleTap;

  const MonthGridView({
    super.key,
    required this.month,
    required this.events,
    required this.weekStartDay,
    required this.showWeekNumbers,
    required this.isRussian,
    required this.selectedDay,
    required this.now,
    required this.accountColors,
    required this.onDaySelected,
    this.onDayDoubleTap,
  });

  /// Первый день сетки (может быть из прошлого месяца).
  static DateTime gridStart(DateTime month, int weekStartDay) =>
      CalendarViewUtils.weekStart(DateTime(month.year, month.month, 1), weekStartDay);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppLocalizations.of(context).localeCode;
    final start = gridStart(month, weekStartDay);

    final labels = [
      for (var i = 0; i < 7; i++)
        DateFormat('EEE', locale).format(start.add(Duration(days: i))).toUpperCase(),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              if (showWeekNumbers) const SizedBox(width: Space.xl),
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      labels[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < 6; row++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showWeekNumbers)
                        SizedBox(
                          width: 24,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${CalendarViewUtils.isoWeek(start.add(Duration(days: row * 7)))}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, fontSize: 10),
                            ),
                          ),
                        ),
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _cell(
                            context,
                            theme,
                            DateTime(start.year, start.month, start.day + row * 7 + col),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(BuildContext context, ThemeData theme, DateTime date) {
    final scheme = theme.colorScheme;
    final inMonth = date.month == month.month;
    final isToday = CalendarViewUtils.sameDay(date, now);
    final isSelected = selectedDay != null && CalendarViewUtils.sameDay(date, selectedDay!);
    final dayEvents = CalendarViewUtils.eventsForDay(events, date);
    final weekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

    return InkWell(
      onTap: () => onDaySelected(date),
      onDoubleTap: onDayDoubleTap == null ? null : () => onDayDoubleTap!(date),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary.withValues(alpha: 0.10) : null,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.25)),
            left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.12)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(2, 3, 2, 2),
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < _chipMinWidth) return _markersCell(theme, date, dayEvents, inMonth, isToday, isSelected, weekend);
          // Сколько плашек влезает под числом.
          const numberH = 24.0;
          const chipH = 15.0;
          final fit = ((box.maxHeight - numberH) / chipH).floor().clamp(0, 6);
          final showN = dayEvents.length > fit ? (fit - 1).clamp(0, 6) : dayEvents.length;
          // Прокрутка отключена — она лишь не даёт ячейке «переполниться» в
          // низкой строке (альбомная ориентация).
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                      : null,
                  child: Text(
                    '${date.day}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? scheme.onPrimary
                          : !inMonth
                              ? theme.hintColor.withValues(alpha: 0.45)
                              : (weekend ? theme.hintColor : null),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              for (final e in dayEvents.take(showN)) _chip(e, inMonth),
              if (dayEvents.length > showN)
                Text(
                  fit == 0 ? '•' : '+${dayEvents.length - showN}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
            ],
          ),
          );
        }),
      ),
    );
  }

  /// Ширина ячейки, с которой названия плашками ещё читаются.
  static const _chipMinWidth = 84.0;

  Widget _dayNumber(ThemeData theme, DateTime date, bool inMonth, bool isToday, bool isSelected, bool weekend) {
    final scheme = theme.colorScheme;
    return Center(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: isToday ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle) : null,
        child: Text(
          '${date.day}',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isToday
                ? scheme.onPrimary
                : !inMonth
                    ? theme.hintColor.withValues(alpha: 0.45)
                    : (weekend ? theme.hintColor : null),
          ),
        ),
      ),
    );
  }

  static final _birthday = RegExp(r'день рождени|birthday|geburtstag|anniversaire', caseSensitive: false);

  /// Ячейка телефона: число и значки событий.
  Widget _markersCell(ThemeData theme, DateTime date, List<CalendarEvent> dayEvents, bool inMonth, bool isToday,
      bool isSelected, bool weekend) {
    // Сначала дни целиком (полоски), затем остальное по времени.
    final long = <CalendarEvent>[];
    final short = <CalendarEvent>[];
    for (final e in dayEvents) {
      final allDay = isRealEvent(e) && (e.isAllDay || e.endTime.difference(e.startTime).inHours >= 24);
      (allDay && !_birthday.hasMatch(e.title) ? long : short).add(e);
    }
    const maxMarks = 6;
    final bars = long.take(2).toList();
    final marks = short.take(maxMarks).toList();
    final rest = dayEvents.length - bars.length - marks.length;
    return Opacity(
      opacity: inMonth ? 1 : 0.45,
      // Без переполнения в низкой строке (альбомная ориентация).
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dayNumber(theme, date, inMonth, isToday, isSelected, weekend),
          const SizedBox(height: 3),
          for (final e in bars)
            Container(
              height: 4,
              margin: const EdgeInsets.fromLTRB(2, 0, 2, 2),
              decoration: BoxDecoration(color: eventColor(e, accountColors), borderRadius: BorderRadius.circular(2)),
            ),
          if (marks.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 3,
              runSpacing: 2,
              children: [for (final e in marks) _marker(e)],
            ),
          if (rest > 0)
            Text(
              '+$rest',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, fontSize: 10, height: 1.2),
            ),
        ],
      ),
      ),
    );
  }

  Widget _marker(CalendarEvent e) {
    final c = eventColor(e, accountColors);
    IconData? icon;
    if (isTaskItem(e)) {
      icon = AppIcons.task_alt;
    } else if (isMailItem(e)) {
      icon = AppIcons.mail;
    } else if (isInviteItem(e)) {
      icon = AppIcons.event_available;
    } else if (_birthday.hasMatch(e.title)) {
      icon = AppIcons.cake;
    }
    if (icon != null) return Icon(icon, size: 11, color: c);
    return Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _chip(CalendarEvent e, bool inMonth) {
    final c = eventColor(e, accountColors);
    // Задачи и письма со сроком — контуром, встречи — заливкой.
    final outlined = isTaskItem(e) || isMailItem(e) || isInviteItem(e);
    final solid = !outlined && (e.isAllDay || e.endTime.difference(e.startTime).inHours >= 24);
    final bg = solid ? c : c.withValues(alpha: outlined ? 0.06 : 0.16);
    final fg = solid ? onColor(c) : c;
    return Opacity(
      opacity: inMonth ? 1 : 0.5,
      child: Container(
        height: 13,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(3),
          border: outlined ? Border.all(color: c.withValues(alpha: 0.7), width: 0.8) : null,
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          e.title,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: TextStyle(fontSize: 9.5, height: 1.1, color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// lib/features/calendar/widgets/time_grid_view.dart
// Сетка времени для видов «День», «3 дня», «Неделя» — как в Google Календаре
// и Outlook: часы слева, события блоками по времени, пересекающиеся встречи
// делят колонку, красная линия «сейчас», полоса «весь день» сверху.
// Нажатие на пустое место — новая встреча на это время.
//
// Шкала времени по периодам (1.5.11, замечание 12.10.2026: «неделя, три
// дня, день не помещаются в экран»): часы с событиями и рабочие часы
// (8–18) — полной высоты, пустые ночные и вечерние — свёрнуты до трети
// (с подписью только на границах и лёгкой заливкой). Высота часа
// подбирается так, чтобы день по возможности помещался в экран без
// прокрутки (не меньше 32 точек — иначе прокрутка, как раньше). Длинная
// встреча через ночь (больше 4 часов) ночь не разворачивает.

import 'package:flutter/material.dart';
import '../../../widgets/common/quick_long_press.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../l10n/app_localizations.dart';
import '../calendar_data.dart';

class TimeGridView extends StatefulWidget {
  /// Первый день.
  final DateTime start;

  /// Сколько дней показывать (1, 3, 7).
  final int days;
  final List<CalendarEvent> events;
  final Map<String, Color> accountColors;
  final bool isRussian;
  final DateTime now;
  final void Function(CalendarEvent) onEventTap;
  final void Function(CalendarEvent)? onEventLongPress;
  final void Function(DateTime slotStart) onSlotTap;
  final void Function(DateTime day)? onDayHeaderTap;

  /// Общая на все страницы прокрутка по вертикали: листаешь дни — время
  /// остаётся тем же. Меньше нуля — ещё не листали: открыть на часе до
  /// текущего времени.
  final ValueNotifier<double> scrollOffset;

  static const hourHeight = 56.0;
  static const gutter = 52.0;

  const TimeGridView({
    super.key,
    required this.start,
    required this.days,
    required this.events,
    required this.accountColors,
    required this.isRussian,
    required this.now,
    required this.onEventTap,
    required this.onSlotTap,
    required this.scrollOffset,
    this.onEventLongPress,
    this.onDayHeaderTap,
  });

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

/// Шкала времени дня: верх каждого часа (25 значений) и свёрнутые часы.
class _TimeScale {
  final List<double> top;
  final List<bool> folded;
  const _TimeScale(this.top, this.folded);

  double get height => top[24];

  double y(double minutes) {
    final m = minutes.clamp(0.0, 24 * 60.0);
    final h = (m ~/ 60).clamp(0, 23);
    return top[h] + (top[h + 1] - top[h]) * ((m - h * 60) / 60);
  }

  double minutesAt(double dy) {
    for (var h = 0; h < 24; h++) {
      if (dy < top[h + 1]) {
        final span = top[h + 1] - top[h];
        return h * 60 + (span <= 0 ? 0 : (dy - top[h]) / span * 60);
      }
    }
    return 24 * 60 - 1;
  }
}

class _TimeGridViewState extends State<TimeGridView> {
  ScrollController? _scroll;

  static const _workStart = 8, _workEnd = 18;
  static const _foldWeight = 0.33;
  static const _minUnit = 32.0, _maxUnit = 72.0;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  /// Шкала по событиям видимых дней и высоте экрана.
  _TimeScale _scaleFor(List<DateTime> days, double avail) {
    final busy = List<bool>.filled(24, false);
    for (var h = _workStart; h < _workEnd; h++) {
      busy[h] = true;
    }
    for (final d in days) {
      final d0 = CalendarViewUtils.dayOf(d);
      for (final it in TimedLayout.layoutDay(widget.events, d)) {
        final s = it.start.difference(d0).inMinutes;
        final e = it.end.difference(d0).inMinutes;
        final h0 = (s ~/ 60).clamp(0, 23);
        final h1 = ((e - 1) ~/ 60).clamp(0, 23);
        if (e - s <= 240) {
          for (var h = h0; h <= h1; h++) {
            busy[h] = true;
          }
        } else {
          // Длинное (через ночь) — только часы начала и конца.
          busy[h0] = true;
          busy[h1] = true;
        }
      }
    }
    final now = widget.now;
    if (days.any((d) => CalendarViewUtils.sameDay(d, now))) busy[now.hour] = true;
    final weights = [for (final b in busy) b ? 1.0 : _foldWeight];
    final sum = weights.fold<double>(0, (a, w) => a + w);
    final unit = avail.isFinite && avail > 0 ? (avail / sum).clamp(_minUnit, _maxUnit) : TimeGridView.hourHeight;
    final top = <double>[0];
    for (final w in weights) {
      top.add(top.last + w * unit);
    }
    return _TimeScale(top, [for (final b in busy) !b]);
  }

  List<DateTime> get _dayList => [
        for (var i = 0; i < widget.days; i++)
          DateTime(widget.start.year, widget.start.month, widget.start.day + i),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = _dayList;
    final allDay = [for (final d in days) TimedLayout.allDayFor(widget.events, d)];
    final hasAllDay = allDay.any((l) => l.isNotEmpty);

    return Column(
      children: [
        _header(theme, days),
        if (hasAllDay) _allDayStrip(theme, days, allDay),
        Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final scale = _scaleFor(days, box.maxHeight - 12);
            var c = _scroll;
            if (c == null) {
              final v = widget.scrollOffset.value;
              c = _scroll = ScrollController(
                  initialScrollOffset: v >= 0 ? v : scale.y(((widget.now.hour - 1).clamp(0, 23)) * 60.0));
              c.addListener(() => widget.scrollOffset.value = _scroll!.offset);
            }
            return SingleChildScrollView(
              controller: c,
              child: SizedBox(
                height: scale.height + 12,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hourGutter(theme, scale),
                    for (final d in days)
                      Expanded(child: _dayColumn(theme, d, scale)),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Шапка: день недели и число ──
  Widget _header(ThemeData theme, List<DateTime> days) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeCode;
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs, bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: TimeGridView.gutter,
            child: widget.days == 7
                ? Center(
                    child: Text(
                      l10n.tr('calWeekShort').replaceAll('{n}', '${CalendarViewUtils.isoWeek(days.first)}'),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                    ),
                  )
                : null,
          ),
          for (final d in days)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onDayHeaderTap == null ? null : () => widget.onDayHeaderTap!(d),
                child: Column(
                  children: [
                    Text(
                      DateFormat('EEE', locale).format(d).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: CalendarViewUtils.sameDay(d, widget.now) ? scheme.primary : theme.hintColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _dayNumber(theme, d),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayNumber(ThemeData theme, DateTime d) {
    final scheme = theme.colorScheme;
    final isToday = CalendarViewUtils.sameDay(d, widget.now);
    final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: isToday ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle) : null,
      child: Text(
        '${d.day}',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
          color: isToday ? scheme.onPrimary : (weekend ? theme.hintColor : null),
        ),
      ),
    );
  }

  // ── Полоса «весь день» ──
  Widget _allDayStrip(ThemeData theme, List<DateTime> days, List<List<CalendarEvent>> allDay) {
    const maxRows = 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: TimeGridView.gutter,
            child: Padding(
              padding: const EdgeInsets.only(top: 3, right: 6),
              child: Text(
                AppLocalizations.of(context).tr('calAllDayShort'),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, height: 1.1),
              ),
            ),
          ),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in allDay[i].take(allDay[i].length > maxRows ? maxRows - 1 : maxRows))
                      _allDayChip(theme, e),
                    if (allDay[i].length > maxRows)
                      InkWell(
                        onTap: widget.onDayHeaderTap == null ? null : () => widget.onDayHeaderTap!(days[i]),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('+${allDay[i].length - maxRows + 1}',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _allDayChip(ThemeData theme, CalendarEvent e) {
    final c = eventColor(e, widget.accountColors);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: c,
        borderRadius: BorderRadius.circular(4),
        child: QuickLongPress(
          onLongPress: widget.onEventLongPress == null ? null : () => widget.onEventLongPress!(e),
          tracker: HoldPointer.instance,
          child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => widget.onEventTap(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 2),
            child: Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: onColor(c), fontWeight: FontWeight.w600),
            ),
          ),
        )),
      ),
    );
  }

  // ── Часы слева ──
  Widget _hourGutter(ThemeData theme, _TimeScale scale) {
    // Подпись часа — если над ним или под ним час полной высоты (внутри
    // свёрнутого периода подписи слились бы).
    bool label(int h) => !scale.folded[h] || !scale.folded[h - 1];
    return SizedBox(
      width: TimeGridView.gutter,
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            if (label(h))
            Positioned(
              top: scale.top[h] - 7,
              right: 8,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor, fontSize: 10.5),
              ),
            ),
        ],
      ),
    );
  }

  // ── Колонка дня ──
  Widget _dayColumn(ThemeData theme, DateTime day, _TimeScale scale) {
    final layout = TimedLayout.layoutDay(widget.events, day);
    final isToday = CalendarViewUtils.sameDay(day, widget.now);
    final weekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Stack(
          children: [
            // Пустое место: нажатие — новая встреча на это время (по 30 мин).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final minutes = scale.minutesAt(d.localPosition.dy).floor();
                  final rounded = (minutes ~/ 30) * 30;
                  HapticFeedback.selectionClick();
                  widget.onSlotTap(DateTime(day.year, day.month, day.day, 0, rounded.clamp(0, 23 * 60 + 30)));
                },
                child: CustomPaint(
                  painter: _GridPainter(
                    scale: scale,
                    fold: theme.dividerColor.withValues(alpha: 0.06),
                    line: theme.dividerColor.withValues(alpha: 0.35),
                    halfLine: theme.dividerColor.withValues(alpha: 0.15),
                    shade: weekend || isToday
                        ? theme.colorScheme.primary.withValues(alpha: isToday ? 0.04 : 0.02)
                        : null,
                  ),
                ),
              ),
            ),
            for (final it in layout) _eventBlock(theme, it, w, scale),
            if (isToday) _nowLine(theme, scale),
          ],
        );
      },
    );
  }

  Widget _eventBlock(ThemeData theme, TimedLayout it, double width, _TimeScale scale) {
    final e = it.event;
    final day0 = CalendarViewUtils.dayOf(it.start);
    final top = scale.y(it.start.difference(day0).inMinutes.toDouble());
    final height = scale.y(it.end.difference(day0).inMinutes.toDouble()) - top - 2;
    final colW = width / it.columns;
    final left = it.column * colW;
    final c = eventColor(e, widget.accountColors);
    final past = it.end.isBefore(widget.now);
    // Задачи и письма со сроком — контуром, встречи — заливкой: с первого
    // взгляда видно, где встреча, а где дело (замечание 10.10.2026).
    final outlined = isTaskItem(e) || isMailItem(e) || isInviteItem(e);
    final bg = outlined
        ? Color.alphaBlend(c.withValues(alpha: past ? 0.08 : 0.16), theme.colorScheme.surface)
        : (past ? Color.alphaBlend(theme.colorScheme.surface.withValues(alpha: 0.45), c) : c);
    final fg = outlined ? theme.colorScheme.onSurface : onColor(bg);
    final tentative = e.showAs == 1;
    final time = DateFormat('HH:mm').format(e.startTime.toLocal());
    final icon = isTaskItem(e)
        ? AppIcons.task_alt
        : isMailItem(e)
            ? AppIcons.flag
            : isInviteItem(e)
                ? AppIcons.event_available
                : ((e.onlineMeetingUrl ?? '').isNotEmpty ? AppIcons.videocam : null);

    return Positioned(
      top: top + 1,
      left: left + 1,
      width: colW - 2,
      height: height < 18 ? 18 : height,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: outlined ? BorderSide(color: c, width: 1.2) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: QuickLongPress(
          onLongPress: widget.onEventLongPress == null ? null : () => widget.onEventLongPress!(e),
          tracker: HoldPointer.instance,
          child: InkWell(
          onTap: () => widget.onEventTap(e),
          child: Container(
            decoration: tentative
                ? BoxDecoration(
                    border: Border(left: BorderSide(color: fg.withValues(alpha: 0.7), width: 3)),
                  )
                : null,
            padding: const EdgeInsets.fromLTRB(5, 2, Space.xs, 2),
            child: LayoutBuilder(builder: (context, b) {
              final roomy = b.maxHeight >= 34;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 11, color: fg),
                        const SizedBox(width: 2),
                      ],
                      Expanded(
                        child: Text(
                          roomy ? e.title : '$time ${e.title}',
                          maxLines: roomy && b.maxHeight > 50 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            decoration: e.isCancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (roomy)
                    Text(
                      (e.location ?? '').isNotEmpty && b.maxHeight > 50
                          ? '$time · ${e.location}'
                          : time,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 10.5, height: 1.2),
                    ),
                ],
              );
            }),
          ),
        )),
      ),
    );
  }

  Widget _nowLine(ThemeData theme, _TimeScale scale) {
    final n = widget.now;
    final top = scale.y((n.hour * 60 + n.minute).toDouble());
    return Positioned(
      top: top - 5,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(color: AppColors.errorRed, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 2, color: AppColors.errorRed)),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final _TimeScale scale;
  final Color fold;
  final Color line;
  final Color halfLine;
  final Color? shade;
  _GridPainter({required this.scale, required this.fold, required this.line, required this.halfLine, this.shade});

  @override
  void paint(Canvas canvas, Size size) {
    if (shade != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = shade!);
    }
    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    final hp = Paint()
      ..color = halfLine
      ..strokeWidth = 1;
    // Свёрнутые часы — лёгкая заливка, без линий внутри периода.
    final fp = Paint()..color = fold;
    for (var h = 0; h < 24; h++) {
      if (scale.folded[h]) {
        canvas.drawRect(Rect.fromLTRB(0, scale.top[h], size.width, scale.top[h + 1]), fp);
      }
    }
    for (var h = 0; h <= 24; h++) {
      final y = scale.top[h];
      final inFold = h > 0 && h < 24 && scale.folded[h] && scale.folded[h - 1];
      if (!inFold) canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      if (h < 24 && !scale.folded[h]) {
        final y2 = (scale.top[h] + scale.top[h + 1]) / 2;
        canvas.drawLine(Offset(0, y2), Offset(size.width, y2), hp);
      }
    }
    // Разделитель колонок дней.
    canvas.drawLine(Offset.zero, Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      !identical(old.scale, scale) || old.line != line || old.halfLine != halfLine || old.shade != shade;
}

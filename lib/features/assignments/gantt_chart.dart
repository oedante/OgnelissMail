// lib/features/assignments/gantt_chart.dart
// Диаграмма Ганта проекта (просьба владельца 12.11.2026, как Timeline в
// Jira и MS Project): этапы строками, полоса — от начала до срока, заливка —
// доля выполненного, цвет — статус; просроченный этап — красной рамкой;
// линия «сегодня»; стрелки «после этапа» (окончание → начало). Названия
// этапов — слева и не уезжают; дни листаются вбок. Нажатие на строку —
// карточка этапа.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_store.dart' show PlanStage;

class GanttChart extends StatefulWidget {
  final List<PlanStage> stages;
  final DateTime today;
  final void Function(String stageId)? onTap;

  const GanttChart({super.key, required this.stages, required this.today, this.onTap});

  static const rowHeight = 40.0;
  static const headerHeight = 44.0;
  static const dayWidth = 30.0;

  @override
  State<GanttChart> createState() => _GanttChartState();
}

class _GanttChartState extends State<GanttChart> {
  final _scroll = ScrollController();
  bool _scrolledToToday = false;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  ({DateTime from, int days}) _range() {
    final dates = <DateTime>[
      _day(widget.today),
      for (final s in widget.stages) ...[if (s.start != null) _day(s.start!), if (s.due != null) _day(s.due!)],
    ];
    var from = dates.reduce((a, b) => a.isBefore(b) ? a : b).subtract(const Duration(days: 1));
    var to = dates.reduce((a, b) => a.isAfter(b) ? a : b).add(const Duration(days: 2));
    // Не меньше двух недель — диаграмма не сжимается в столбик.
    if (to.difference(from).inDays < 14) to = from.add(const Duration(days: 14));
    from = DateTime(from.year, from.month, from.day);
    return (from: from, days: to.difference(from).inDays + 1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final range = _range();
    final rows = widget.stages.length;
    final height = GanttChart.headerHeight + rows * GanttChart.rowHeight + Space.s;
    final width = range.days * GanttChart.dayWidth;
    if (!_scrolledToToday) {
      _scrolledToToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final x = _day(widget.today).difference(range.from).inDays * GanttChart.dayWidth - 2 * GanttChart.dayWidth;
        _scroll.jumpTo(x.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
    final names = SizedBox(
      width: 132,
      height: height,
      child: Column(children: [
        const SizedBox(height: GanttChart.headerHeight),
        for (var i = 0; i < rows; i++)
          InkWell(
            onTap: widget.onTap == null ? null : () => widget.onTap!(widget.stages[i].id),
            child: SizedBox(
              height: GanttChart.rowHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: Space.m, right: Space.xs),
                  child: Text('${i + 1}. ${widget.stages[i].title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),
      ]),
    );
    final chart = SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: GestureDetector(
        onTapUp: widget.onTap == null
            ? null
            : (d) {
                final i = ((d.localPosition.dy - GanttChart.headerHeight) / GanttChart.rowHeight).floor();
                if (i >= 0 && i < rows) widget.onTap!(widget.stages[i].id);
              },
        child: CustomPaint(
          size: Size(width, height),
          painter: _GanttPainter(
            stages: widget.stages,
            from: range.from,
            days: range.days,
            today: _day(widget.today),
            locale: l10n.localeCode,
            colors: _GanttColors.of(context),
            textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
          ),
        ),
      ),
    );
    return Semantics(
      label: l10n.tr('projPlan'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        names,
        Expanded(child: chart),
      ]),
    );
  }
}

class _GanttColors {
  final Color grid;
  final Color weekend;
  final Color text;
  final Color muted;
  final Color today;
  final Color open;
  final Color progress;
  final Color review;
  final Color done;
  final Color late;
  final Color waiting;
  final Color arrow;

  const _GanttColors({
    required this.grid,
    required this.weekend,
    required this.text,
    required this.muted,
    required this.today,
    required this.open,
    required this.progress,
    required this.review,
    required this.done,
    required this.late,
    required this.waiting,
    required this.arrow,
  });

  static _GanttColors of(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return _GanttColors(
      grid: s.outlineVariant.withValues(alpha: 0.5),
      weekend: s.onSurface.withValues(alpha: 0.04),
      text: s.onSurface,
      muted: AppColors.mutedText(context),
      today: AppColors.errorText(context),
      open: s.primary.withValues(alpha: 0.25),
      progress: s.primary,
      review: const Color(0xFFE0A100),
      done: AppColors.successText(context),
      late: AppColors.errorText(context),
      waiting: s.outline.withValues(alpha: 0.35),
      arrow: s.onSurfaceVariant,
    );
  }
}

class _GanttPainter extends CustomPainter {
  final List<PlanStage> stages;
  final DateTime from;
  final int days;
  final DateTime today;
  final String locale;
  final _GanttColors colors;
  final TextStyle textStyle;

  _GanttPainter({
    required this.stages,
    required this.from,
    required this.days,
    required this.today,
    required this.locale,
    required this.colors,
    required this.textStyle,
  });

  static const _done = 4;
  static const _review = 3;
  static const _cancelled = 6;

  double _x(DateTime d) =>
      DateTime(d.year, d.month, d.day).difference(from).inDays * GanttChart.dayWidth;

  void _text(Canvas c, String t, Offset at, {Color? color, bool bold = false, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: textStyle.copyWith(color: color ?? colors.muted, fontWeight: bold ? FontWeight.w700 : null)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 200);
    tp.paint(c, at);
  }

  ({Rect bar, PlanStage s})? _bar(int i) {
    final s = stages[i];
    final start = s.start ?? s.due;
    final end = s.due ?? s.start;
    if (start == null || end == null) return null;
    final top = GanttChart.headerHeight + i * GanttChart.rowHeight + 10;
    final x1 = _x(start) + 2;
    final x2 = _x(end) + GanttChart.dayWidth - 2;
    return (bar: Rect.fromLTRB(x1, top, math.max(x2, x1 + 6), top + GanttChart.rowHeight - 20), s: s);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    final weekend = Paint()..color = colors.weekend;
    final dayFmt = DateFormat('d', locale);
    final monFmt = DateFormat('LLL', locale);
    // Дни: выходные тоном, сетка, числа; месяц — у первого дня и в начале.
    for (var i = 0; i < days; i++) {
      final d = from.add(Duration(days: i));
      final x = i * GanttChart.dayWidth;
      if (d.weekday >= 6) {
        canvas.drawRect(Rect.fromLTWH(x, GanttChart.headerHeight, GanttChart.dayWidth, size.height), weekend);
      }
      canvas.drawLine(Offset(x, GanttChart.headerHeight - 4), Offset(x, size.height), grid);
      _text(canvas, dayFmt.format(d), Offset(x + 8, GanttChart.headerHeight - 20),
          color: d == today ? colors.today : colors.muted, bold: d == today);
      if (i == 0 || d.day == 1) {
        _text(canvas, monFmt.format(d), Offset(x + 4, 4), color: colors.text, bold: true, maxWidth: 90);
      }
    }
    canvas.drawLine(const Offset(0, GanttChart.headerHeight), Offset(size.width, GanttChart.headerHeight), grid);
    for (var r = 1; r <= stages.length; r++) {
      final y = GanttChart.headerHeight + r * GanttChart.rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid..color = colors.grid.withValues(alpha: 0.3));
    }

    // Стрелки «после этапа»: из конца предыдущего — в начало следующего.
    final bars = {for (var i = 0; i < stages.length; i++) stages[i].id: _bar(i)};
    final arrow = Paint()
      ..color = colors.arrow
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final s in stages) {
      final to = bars[s.id];
      final fromBar = s.after == null ? null : bars[s.after];
      if (to == null || fromBar == null) continue;
      final a = Offset(fromBar.bar.right, fromBar.bar.center.dy);
      final b = Offset(to.bar.left, to.bar.center.dy);
      final midX = math.max(a.dx + 6, b.dx - 8);
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(midX, a.dy)
        ..lineTo(midX, b.dy)
        ..lineTo(b.dx - 1, b.dy);
      canvas.drawPath(path, arrow);
      final head = Path()
        ..moveTo(b.dx - 1, b.dy)
        ..lineTo(b.dx - 6, b.dy - 4)
        ..lineTo(b.dx - 6, b.dy + 4)
        ..close();
      canvas.drawPath(head, Paint()..color = colors.arrow);
    }

    // Полосы этапов.
    for (var i = 0; i < stages.length; i++) {
      final b = _bar(i);
      if (b == null) continue;
      final s = b.s;
      final r = RRect.fromRectAndRadius(b.bar, const Radius.circular(5));
      final status = s.status;
      final late = status != _done && status != _cancelled && s.due != null && DateTime(s.due!.year, s.due!.month, s.due!.day).isBefore(today);
      final base = switch (status) {
        _done => colors.done.withValues(alpha: 0.35),
        _cancelled => colors.waiting,
        null => colors.waiting,
        _ => colors.open,
      };
      canvas.drawRRect(r, Paint()..color = base);
      final fill = (status == _done ? 1.0 : s.progress).clamp(0.0, 1.0);
      if (fill > 0) {
        final color = switch (status) {
          _done => colors.done,
          _review => colors.review,
          _ => colors.progress,
        };
        canvas.save();
        canvas.clipRRect(r);
        canvas.drawRect(Rect.fromLTWH(b.bar.left, b.bar.top, b.bar.width * fill, b.bar.height), Paint()..color = color);
        canvas.restore();
      }
      if (late) {
        canvas.drawRRect(
            r,
            Paint()
              ..color = colors.late
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      // Фактическое окончание принятого этапа — ромбом.
      final doneAt = s.doneAt;
      if (status == _done && doneAt != null) {
        final cx = _x(doneAt) + GanttChart.dayWidth / 2;
        final cy = b.bar.center.dy;
        final d = Path()
          ..moveTo(cx, cy - 6)
          ..lineTo(cx + 6, cy)
          ..lineTo(cx, cy + 6)
          ..lineTo(cx - 6, cy)
          ..close();
        canvas.drawPath(d, Paint()..color = colors.done);
      }
      final pct = '${(fill * 100).round()}%';
      if (b.bar.width > 34) {
        _text(canvas, pct, Offset(b.bar.left + 4, b.bar.top + 2),
            color: fill > 0.5 ? Colors.white : colors.text, maxWidth: b.bar.width - 6);
      }
    }

    // Сегодня — вертикальной линией.
    final tx = _x(today) + GanttChart.dayWidth / 2;
    if (tx >= 0 && tx <= size.width) {
      canvas.drawLine(
          Offset(tx, GanttChart.headerHeight - 6),
          Offset(tx, size.height),
          Paint()
            ..color = colors.today
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _GanttPainter old) =>
      old.stages != stages || old.from != from || old.days != days || old.today != today;
}

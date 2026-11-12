// lib/features/assignments/assignment_charts.dart
// Блоки сводки по поручениям (12.11.2026): плитки показателей, полоса
// статусов (доля каждого статуса), «по людям» (в работе, просрочено,
// выполнено) и «по неделям» (поставлено и выполнено). Виджетами, без
// библиотек графиков: у каждой отметки — подсказка по нажатию и подпись для
// чтения с экрана, у каждого графика — легенда и числа рядом.
//
// Правила вида — навык dataviz: тонкие отметки, 4px скругления, 2px зазор
// цвета фона между частями, легенда при двух рядах и больше, текст — цветом
// текста, а не цветом ряда. Цвета рядов «поставлено/выполнено» — первые два
// слота проверенной палитры (синий, оранжевый; свои шаги для тёмной темы).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../services/assignments/assignment_service.dart' show AssignmentStatus;
import '../../services/assignments/assignment_stats.dart';
import 'assignment_widgets.dart' show assignmentStatusColor, assignmentStatusLabel;

/// Ряды «поставлено» и «выполнено» (слоты 1 и 2 палитры).
Color chartSeries(BuildContext context, int slot) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (slot) {
    0 => dark ? const Color(0xFF3987E5) : const Color(0xFF2A78D6),
    _ => dark ? const Color(0xFFD95926) : const Color(0xFFEB6834),
  };
}

/// Карточка блока сводки: заголовок и содержимое.
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  const ChartCard({super.key, required this.title, this.subtitle, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing!,
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ),
          const SizedBox(height: Space.m),
          child,
        ]),
      ),
    );
  }
}

/// Плитка показателя: подпись, значение, пояснение.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Color? accent;
  final double? width;
  const StatTile({super.key, required this.label, required this.value, this.note, this.accent, this.width});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    return Semantics(
      label: '$label: $value${note == null ? '' : ', $note'}',
      excludeSemantics: true,
      child: Container(
        width: width,
        constraints: const BoxConstraints(minWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (accent != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              const SizedBox(width: Space.xs),
            ],
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          ]),
          if (note != null) Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ]),
      ),
    );
  }
}

/// Плитки показателей одинаковой ширины: две в ряд на телефоне, три и
/// больше — на широком экране.
class StatGrid extends StatelessWidget {
  final List<StatTile> tiles;
  const StatGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 900 ? 6 : (box.maxWidth >= 560 ? 3 : 2);
        final w = (box.maxWidth - (cols - 1) * Space.s) / cols;
        return Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final t in tiles)
            StatTile(label: t.label, value: t.value, note: t.note, accent: t.accent, width: w),
        ]);
      });
}

/// Доля в процентах, без дробей.
String percentText(double share) => '${(share * 100).round()}%';

/// Полоса статусов: каждая часть — своим блоком, доля внутри (если
/// помещается), ниже — легенда с числами.
class StatusSplitBar extends StatelessWidget {
  final Map<int, int> counts;
  const StatusSplitBar({super.key, required this.counts});

  static const order = [
    AssignmentStatus.open,
    AssignmentStatus.inProgress,
    AssignmentStatus.review,
    AssignmentStatus.done,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parts = [for (final s in order) if ((counts[s] ?? 0) > 0) (s, counts[s]!)];
    final total = parts.fold<int>(0, (a, p) => a + p.$2);
    if (total == 0) {
      return Text(l10n.tr('assignStatsNone'),
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)));
    }
    Color ink(Color fill) =>
        ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF111111);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 28,
        child: LayoutBuilder(builder: (context, box) {
          final gaps = (parts.length - 1) * 2.0;
          final w = box.maxWidth - gaps;
          return Row(children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Tooltip(
                message:
                    '${assignmentStatusLabel(parts[i].$1, l10n)}: ${parts[i].$2} (${percentText(parts[i].$2 / total)})',
                child: Container(
                  width: w * parts[i].$2 / total,
                  height: 28,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: assignmentStatusColor(parts[i].$1, context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  // Доля — только если помещается (иначе — в легенде).
                  child: w * parts[i].$2 / total >= 40
                      ? Text(percentText(parts[i].$2 / total),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: ink(assignmentStatusColor(parts[i].$1, context)), fontWeight: FontWeight.w600))
                      : null,
                ),
              ),
            ],
          ]);
        }),
      ),
      const SizedBox(height: Space.s),
      Wrap(spacing: Space.m, runSpacing: Space.xs, children: [
        for (final (s, n) in parts)
          _LegendDot(color: assignmentStatusColor(s, context), label: '${assignmentStatusLabel(s, l10n)} · $n'),
      ]),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// По людям: имя, числа и тонкая полоса «в работе / просрочено /
/// выполнено» (длина — от самого загруженного).
class PeopleBars extends StatelessWidget {
  final List<PersonStats> people;
  final int limit;
  const PeopleBars({super.key, required this.people, this.limit = 8});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    if (people.isEmpty) {
      return Text(l10n.tr('assignStatsNone'), style: theme.textTheme.bodySmall?.copyWith(color: muted));
    }
    final shown = people.take(limit).toList();
    final max = shown.fold<int>(1, (a, p) => (p.active + p.done) > a ? p.active + p.done : a);
    final cWork = assignmentStatusColor(AssignmentStatus.inProgress, context);
    final cLate = AppColors.errorText(context);
    final cDone = assignmentStatusColor(AssignmentStatus.done, context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Space.m, runSpacing: Space.xs, children: [
        _LegendDot(color: cWork, label: l10n.tr('assignStatsInWork')),
        _LegendDot(color: cLate, label: l10n.tr('overdue')),
        _LegendDot(color: cDone, label: l10n.tr('assignStatsDone')),
      ]),
      const SizedBox(height: Space.m),
      for (final p in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(p.name.isEmpty ? p.email : p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            LayoutBuilder(builder: (context, box) {
              final segs = [
                (p.active - p.overdue, cWork, l10n.tr('assignStatsInWork')),
                (p.overdue, cLate, l10n.tr('overdue')),
                (p.done, cDone, l10n.tr('assignStatsDone')),
              ].where((s) => s.$1 > 0).toList();
              final total = segs.fold<int>(0, (a, s) => a + s.$1);
              final width = box.maxWidth * total / max - (segs.length - 1) * 2;
              return Row(children: [
                for (var i = 0; i < segs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Tooltip(
                    message: '${p.name}: ${segs[i].$3} — ${segs[i].$1}',
                    child: Container(
                      width: (width * segs[i].$1 / total).clamp(2.0, box.maxWidth),
                      height: 8,
                      decoration: BoxDecoration(color: segs[i].$2, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                ],
              ]);
            }),
            const SizedBox(height: 2),
            Text(
              [
                if (p.active > 0) '${l10n.tr('assignStatsInWork').toLowerCase()} ${p.active}',
                if (p.overdue > 0) '${l10n.tr('overdue').toLowerCase()} ${p.overdue}',
                if (p.done > 0) '${l10n.tr('assignStatsDone').toLowerCase()} ${p.done}',
                if (p.onTimeShare != null) l10n.tr('assignStatsOnTimeShort').replaceAll('{p}', percentText(p.onTimeShare!)),
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ]),
        ),
      if (people.length > limit)
        Text(l10n.tr('assignStatsMorePeople').replaceAll('{n}', '${people.length - limit}'),
            style: theme.textTheme.bodySmall?.copyWith(color: muted)),
    ]);
  }
}

/// По неделям: поставлено и выполнено — парой столбиков на неделю.
class WeeklyColumns extends StatelessWidget {
  final List<WeekStats> weeks;
  const WeeklyColumns({super.key, required this.weeks});

  static const _plot = 120.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final max = weeks.fold<int>(0, (a, w) => [a, w.created, w.done].reduce((x, y) => x > y ? x : y));
    final c0 = chartSeries(context, 0), c1 = chartSeries(context, 1);
    final fmt = DateFormat('d.MM', l10n.localeCode);
    Widget bar(int n, Color c, String tip) => Tooltip(
          message: tip,
          child: Container(
            width: 10,
            height: max == 0 ? 0 : (_plot * n / max).clamp(n > 0 ? 3.0 : 0.0, _plot),
            decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Space.m, children: [
        _LegendDot(color: c0, label: l10n.tr('assignStatsCreated')),
        _LegendDot(color: c1, label: l10n.tr('assignStatsDone')),
      ]),
      const SizedBox(height: Space.s),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // Ось: наибольшее значение и ноль.
        SizedBox(
          height: _plot,
          width: 24,
          child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('$max', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
            Text('0', style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          ]),
        ),
        Expanded(
          child: Container(
            height: _plot,
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.dividerColor))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final w in weeks)
                Expanded(
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    bar(w.created, c0, '${fmt.format(w.start)}: ${l10n.tr('assignStatsCreated')} ${w.created}'),
                    const SizedBox(width: 2),
                    bar(w.done, c1, '${fmt.format(w.start)}: ${l10n.tr('assignStatsDone')} ${w.done}'),
                  ]),
                ),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Row(children: [
        const SizedBox(width: 24),
        for (final w in weeks)
          Expanded(
            child: Text(fmt.format(w.start),
                textAlign: TextAlign.center,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(color: muted, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ]),
    ]);
  }
}

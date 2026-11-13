// lib/services/assignments/assignment_report.dart
// Отчёт по поручениям файлом HTML (12.11.2026): уходит вложением в обычном
// письме, открывается в любом браузере и печатается в PDF. Как отчёты Jira
// и Битрикс24, но без сервера: показатели, по людям, просроченные, проекты
// с планом и фактом по этапам.

import 'dart:convert' show HtmlEscape, HtmlEscapeMode;

import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'assignment_codec.dart' show AssignmentStatus;
import 'assignment_service.dart' show planOf;
import 'assignment_stats.dart';
import 'assignment_store.dart';

const _esc = HtmlEscape(HtmlEscapeMode.element);
String _e(String s) => _esc.convert(s);

String _statusLabel(int s, AppLocalizations l10n) => l10n.tr(switch (s) {
      AssignmentStatus.inProgress => 'assignStInProgress',
      AssignmentStatus.review => 'assignStReview',
      AssignmentStatus.done => 'assignStDone',
      AssignmentStatus.cancelled => 'assignStCancelled',
      _ => 'assignStNew',
    });

String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

/// Отчёт: [title] — заголовок, [subtitle] — область (ящик, период).
/// [items] — поручения и этапы проектов (как в списке, со всеми этапами).
String assignmentReportHtml({
  required AppLocalizations l10n,
  required String title,
  required String subtitle,
  required AssignmentStats stats,
  required List<AssignmentView> items,
  required DateTime now,
}) {
  final day = DateFormat('d MMM yyyy', l10n.localeCode);
  final b = StringBuffer()
    ..write('<!doctype html><html><head><meta charset="utf-8"><title>${_e(title)}</title>'
        '<style>'
        'body{font-family:-apple-system,"Segoe UI",Roboto,Arial,sans-serif;color:#111;margin:24px;max-width:960px}'
        'h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:24px 0 8px}'
        '.sub{color:#555;margin:0 0 16px}'
        '.kpis{display:flex;flex-wrap:wrap;gap:12px}.kpi{background:#f3f4f6;border-radius:12px;padding:10px 14px;min-width:120px}'
        '.kpi span{display:block;color:#555;font-size:13px}.kpi b{font-size:22px}'
        'table{border-collapse:collapse;width:100%;margin:4px 0 8px}'
        'th,td{border-bottom:1px solid #e5e7eb;padding:6px 8px;text-align:left;font-size:14px;vertical-align:top}'
        'th{color:#555;font-weight:600}td.n{text-align:right;font-variant-numeric:tabular-nums}'
        '.late{color:#c62828;font-weight:600}.muted{color:#666}'
        '.bar{height:8px;border-radius:4px;background:#e5e7eb;overflow:hidden;width:160px}'
        '.bar i{display:block;height:8px;background:#2a78d6}'
        '@media print{body{margin:0}}'
        '</style></head><body>')
    ..write('<h1>${_e(title)}</h1><p class="sub">${_e(subtitle)} · ${_e(day.format(now))}</p>');

  // Показатели.
  String kpi(String label, String value) => '<div class="kpi"><span>${_e(label)}</span><b>${_e(value)}</b></div>';
  b.write('<div class="kpis">');
  b
    ..write(kpi(l10n.tr('assignStatsInWork'), '${stats.active}'))
    ..write(kpi(l10n.tr('overdue'), '${stats.overdue}'))
    ..write(kpi(l10n.tr('assignStReview'), '${stats.review}'))
    ..write(kpi(l10n.tr('assignStatsDonePeriod'), '${stats.done}'))
    ..write(kpi(l10n.tr('assignStatsOnTime'), _pct(stats.onTimeShare)))
    ..write(kpi(l10n.tr('assignStatsAvgDays'), stats.avgDays == null ? '—' : stats.avgDays!.toStringAsFixed(1)))
    ..write('</div>');

  // По людям.
  if (stats.people.isNotEmpty) {
    b.write('<h2>${_e(l10n.tr('assignStatsPeople'))}</h2><table><tr>'
          '<th>${_e(l10n.tr('assignStatsPerson'))}</th>'
          '<th>${_e(l10n.tr('assignStatsInWork'))}</th><th>${_e(l10n.tr('overdue'))}</th>'
          '<th>${_e(l10n.tr('assignStReview'))}</th><th>${_e(l10n.tr('assignStatsDone'))}</th>'
          '<th>${_e(l10n.tr('assignStatsOnTime'))}</th></tr>');
    for (final p in stats.people) {
      b.write('<tr><td>${_e(p.name.isEmpty ? p.email : p.name)}</td><td class="n">${p.active}</td>'
          '<td class="n${p.overdue > 0 ? ' late' : ''}">${p.overdue}</td><td class="n">${p.review}</td>'
          '<td class="n">${p.done}</td><td class="n">${_pct(p.onTimeShare)}</td></tr>');
    }
    b.write('</table>');
  }

  // Просроченные.
  final late = [for (final v in items) if (!v.isProject && v.overdue(now)) v]
    ..sort((a, c) => a.due!.compareTo(c.due!));
  if (late.isNotEmpty) {
    b.write('<h2>${_e(l10n.tr('overdue'))}</h2><table><tr>'
          '<th>${_e(l10n.tr('assignWhatHint'))}</th><th>${_e(l10n.tr('assignStatsPerson'))}</th>'
          '<th>${_e(l10n.tr('projDueDate'))}</th><th>${_e(l10n.tr('assignStatsLateDays'))}</th></tr>');
    for (final v in late) {
      final days = DateTime(now.year, now.month, now.day)
          .difference(DateTime(v.due!.year, v.due!.month, v.due!.day))
          .inDays;
      b.write('<tr><td>${_e(v.row.title)}</td><td>${_e(v.otherName)}</td><td>${_e(day.format(v.due!))}</td>'
          '<td class="n late">+$days</td></tr>');
    }
    b.write('</table>');
  }

  // Проекты: прогресс и план/факт по этапам.
  for (final p in [for (final v in items) if (v.isProject) v]) {
    final stages = items.childrenOf(p.id)..sort((a, c) => a.row.stageOrder.compareTo(c.row.stageOrder));
    if (stages.isEmpty) continue;
    final progress = projectProgress(planOf(stages));
    b
      ..write('<h2>${_e(l10n.tr('assignProjectSubject'))}: ${_e(p.row.title)}</h2>')
      ..write('<p class="muted">${_e(l10n.tr('projProgress').replaceAll('{p}', '${(progress * 100).round()}'))} '
          '<span class="bar" style="display:inline-block;vertical-align:middle"><i style="width:${(progress * 100).round()}%"></i></span></p>')
      ..write('<table><tr><th>#</th><th>${_e(l10n.tr('projStage'))}</th><th>${_e(l10n.tr('projExecutor'))}</th>'
          '<th>${_e(l10n.tr('projDueDate'))}</th><th>${_e(l10n.tr('assignStatsFact'))}</th>'
          '<th>${_e(l10n.tr('assignStatsDeviation'))}, ${_e(l10n.tr('assignStatsDaysUnit'))}</th><th>${_e(l10n.tr('assignStatus'))}</th></tr>');
    final facts = stageFacts(stages, now);
    for (var i = 0; i < facts.length; i++) {
      final f = facts[i];
      final dev = f.deviationDays;
      b.write('<tr><td class="n">${i + 1}</td><td>${_e(f.stage.row.title)}</td>'
          '<td>${_e(f.stage.assignee?.displayName ?? f.stage.assignee?.email ?? '')}</td>'
          '<td>${f.plannedDue == null ? '—' : _e(day.format(f.plannedDue!))}</td>'
          '<td>${f.doneAt == null ? '—' : _e(day.format(f.doneAt!))}</td>'
          '<td class="n${dev != null && dev > 0 ? ' late' : ''}">${dev == null ? '—' : (dev > 0 ? '+$dev' : '$dev')}</td>'
          '<td>${_e(_statusLabel(f.stage.status, l10n))}</td></tr>');
    }
    b.write('</table>');
  }

  b
    ..write('<p class="muted">${_e(l10n.tr('assignReportFooter'))}</p>')
    ..write('</body></html>');
  return b.toString();
}

/// Краткий текст отчёта для письма (сам отчёт — во вложении).
String assignmentReportText({required AppLocalizations l10n, required String title, required AssignmentStats stats}) =>
    [
      title,
      '',
      '${l10n.tr('assignStatsInWork')}: ${stats.active}',
      '${l10n.tr('overdue')}: ${stats.overdue}',
      '${l10n.tr('assignStReview')}: ${stats.review}',
      '${l10n.tr('assignStatsDonePeriod')}: ${stats.done}',
      '${l10n.tr('assignStatsOnTime')}: ${_pct(stats.onTimeShare)}',
      '',
      l10n.tr('assignReportAttached'),
    ].join('\n');

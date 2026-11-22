// lib/features/calendar/widgets/ics_events_view.dart
// Событие из файла .ics (22.11.2026, вопрос владельца «А приложение не может
// такое открывать?» — бронирование гостиницы файлом .ics): раньше вложение
// уходило в стороннюю программу, а на телефоне без календаря, который
// принимает файлы, не открывалось вовсе. Теперь — здесь: что, когда, где,
// описание и «В календарь» (встреча откроется заполненной, сохраняет
// пользователь). Тот же вид — у файла, присланного через «Поделиться».

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/dav/ical_parser.dart';
import '../../mail/widgets/meeting_invite_banner.dart' show inviteRecurrenceText;

/// «четверг, 17 декабря 2026, 16:00–18:00»; событие на несколько дней —
/// «17 дек., 16:00 – 18 дек., 08:30» (раньше конец показывался одним
/// временем, будто в тот же день); весь день — «… · Весь день».
String eventRangeText(DateTime start, DateTime? end, {required bool allDay, required AppLocalizations l10n,
    required String locale}) {
  final s = start.toLocal();
  final e = end?.toLocal();
  final day = DateFormat.yMMMMEEEEd(locale);
  if (allDay) {
    // Конец у события «весь день» — следующий день после последнего.
    final last = e?.subtract(const Duration(days: 1));
    if (last != null && DateUtils.dateOnly(last).isAfter(DateUtils.dateOnly(s))) {
      final short = DateFormat.MMMd(locale);
      return '${short.format(s)} – ${short.format(last)} · ${l10n.tr('allDay')}';
    }
    return '${day.format(s)} · ${l10n.tr('allDay')}';
  }
  final t = DateFormat.Hm(locale);
  if (e == null) return '${day.format(s)}, ${t.format(s)}';
  if (DateUtils.isSameDay(s, e)) return '${day.format(s)}, ${t.format(s)}–${t.format(e)}';
  final short = DateFormat.MMMEd(locale);
  return '${short.format(s)}, ${t.format(s)} – ${short.format(e)}, ${t.format(e)}';
}

/// Параметры окна «Новое событие» из события файла.
Map<String, Object?> createEventExtra(VEvent e, {String? fallbackTitle}) => {
      'start': e.start!.toLocal(),
      'end': (e.end ?? e.start!.add(Duration(hours: e.isAllDay ? 24 : 1))).toLocal(),
      'allDay': e.isAllDay,
      'location': e.location,
      'title': (e.summary ?? '').trim().isEmpty ? fallbackTitle : e.summary,
      'description': e.description,
    };

/// События файла .ics карточками.
class IcsEventsView extends StatelessWidget {
  final String ics;

  /// Название, если у события его нет (тема письма, имя файла).
  final String? fallbackTitle;

  const IcsEventsView({super.key, required this.ics, this.fallbackTitle});

  /// События с датой начала; отменённые — тоже (карточка скажет, что
  /// отменено, «В календарь» не будет).
  static List<VEvent> eventsOf(String ics) => [
        for (final e in ICalParser.parse(ics))
          if (e.start != null) e,
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final events = eventsOf(ics);
    if (events.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(l10n.tr('fileDamaged'), textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        for (final e in events) ...[
          _EventCard(event: e, fallbackTitle: fallbackTitle),
          const SizedBox(height: Space.m),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final VEvent event;
  final String? fallbackTitle;
  const _EventCard({required this.event, this.fallbackTitle});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loc = Localizations.localeOf(context).toString();
    final e = event;
    const color = AppColors.infoBlue;
    final title = (e.summary ?? '').trim().isNotEmpty ? e.summary!.trim() : (fallbackTitle ?? '');
    final repeat = inviteRecurrenceText(e.rrule, l10n, loc);
    final description = (e.description ?? '').trim();
    Widget line(IconData icon, String text, {bool selectable = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.s),
            Expanded(
              child: selectable
                  ? SelectableText(text, style: theme.textTheme.bodyMedium)
                  : Text(text, style: theme.textTheme.bodyMedium),
            ),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(AppIcons.event_available, size: 18, color: color),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(l10n.tr('icsEvent'),
                  style: const TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: Space.s),
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
          if (e.cancelled) line(AppIcons.event_busy, l10n.tr('meetingCanceled')),
          line(AppIcons.schedule, eventRangeText(e.start!, e.end, allDay: e.isAllDay, l10n: l10n, locale: loc)),
          if (repeat != null) line(AppIcons.repeat, repeat),
          if ((e.location ?? '').trim().isNotEmpty) line(AppIcons.place, e.location!.trim(), selectable: true),
          if ((e.organizerEmail ?? '').isNotEmpty) line(AppIcons.person, e.organizerEmail!),
          if (description.isNotEmpty) line(AppIcons.notes, description, selectable: true),
          if (!e.cancelled)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: OutlinedButton.icon(
                key: ValueKey('ics_add_${e.uid ?? e.start}'),
                icon: const Icon(AppIcons.event, size: 18),
                label: Text(l10n.tr('addToCalendar')),
                onPressed: () => context.push('/create-event', extra: createEventExtra(e, fallbackTitle: title)),
              ),
            ),
        ],
      ),
    );
  }
}

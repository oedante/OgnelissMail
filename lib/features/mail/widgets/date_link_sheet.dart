// lib/features/mail/widgets/date_link_sheet.dart
// Нажатие на дату в тексте письма (1.9.x, просьба владельца 31.10.2026, как
// у iOS): карточка с днём и временем и действиями — «Создать встречу»
// (редактор встречи с темой письма, временем и ссылкой на письмо, без
// участников), «Напоминание» (задача со сроком), «Копировать», «Показать в
// календаре» (этот день).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/utils/date_links.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;
import '../../../widgets/navigation/panel_requests.dart' show calendarDayRequestProvider;
import '../../../widgets/ui/action_sheet.dart';
import '../../calendar/screens/create_event_screen.dart' show defaultMeetingLength;
import '../../tasks/task_quick_parser.dart' show ParsedTask;
import '../../tasks/widgets/task_editor_sheet.dart' show showTaskEditor;

/// «пт, 6 нояб. · 15:00–16:00» — день и время даты из письма.
String dateLinkLabel(BuildContext context, DateLinkTarget t) {
  final loc = Localizations.localeOf(context).toLanguageTag();
  final day = DateFormat.yMMMEd(loc).format(t.from);
  if (t.allDay) return day;
  final hm = DateFormat.Hm(loc);
  final to = t.to;
  if (to == null) return '$day · ${hm.format(t.from)}';
  final same = to.year == t.from.year && to.month == t.from.month && to.day == t.from.day;
  return same
      ? '$day · ${hm.format(t.from)}–${hm.format(to)}'
      : '$day · ${hm.format(t.from)} – ${DateFormat.MMMEd(loc).add_Hm().format(to)}';
}

/// Тема письма без «Re:», «Fwd:».
String _subjectOf(EmailModel? email, AppLocalizations l10n) {
  final s = (email?.subject ?? '')
      .replaceFirst(RegExp(r'^\s*((re|fw|fwd|ответ|пересл)\s*:\s*)+', caseSensitive: false), '')
      .trim();
  return s.isEmpty ? l10n.tr('noSubject') : s;
}

Future<void> showDateLinkSheet(BuildContext context, DateLinkTarget t, {String? text, EmailModel? email}) async {
  final l10n = AppLocalizations.of(context);
  final label = dateLinkLabel(context, t);
  final shown = (text ?? '').trim();
  final pick = await showActionSheet<String>(
    context,
    title: label,
    subtitle: shown.isEmpty || shown == label ? null : '«$shown»',
    leading: const Icon(AppIcons.event),
    items: [
      ActionSheetItem(icon: AppIcons.event, label: l10n.tr('createMeeting'), value: 'event'),
      ActionSheetItem(icon: AppIcons.alarm, label: l10n.tr('reminder'), value: 'task'),
      ActionSheetItem(icon: AppIcons.content_copy, label: l10n.tr('copy'), value: 'copy'),
      ActionSheetItem(icon: AppIcons.calendar_month, label: l10n.tr('dateShowInCalendar'), value: 'calendar'),
    ],
  );
  if (pick == null || !context.mounted) return;
  final subject = _subjectOf(email, l10n);
  switch (pick) {
    case 'event':
      unawaited(
        context.push(
          '/create-event',
          extra: {
            'start': t.from,
            'end': t.allDay ? t.from : (t.to ?? t.from.add(defaultMeetingLength)),
            'allDay': t.allDay,
            'title': subject,
            if (email != null) ...{
              'description': '${l10n.tr('createdFromEmail')}: $subject\n${l10n.tr('from')}: ${email.from.label}',
              'linkedEmailId': email.id,
            },
          },
        ),
      );
    case 'task':
      unawaited(
        showTaskEditor(
          context,
          draft: ParsedTask(title: subject, due: t.from, reminder: t.allDay ? null : t.from),
          accountId: email?.accountId,
          fromEmail: email,
        ),
      );
    case 'copy':
      await Clipboard.setData(ClipboardData(text: shown.isEmpty ? label : shown));
      showInlineNotice(l10n.tr('copied'));
    case 'calendar':
      ProviderScope.containerOf(context, listen: false).read(calendarDayRequestProvider.notifier).state = DateTime(
        t.from.year,
        t.from.month,
        t.from.day,
      );
      context.go('/calendar');
  }
}

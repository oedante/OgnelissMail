// lib/features/settings/screens/calendar_settings_screen.dart
// Настройки модуля Календарь (как на эталонных экранах):
// вид по умолчанию, начало недели, номера недель, напоминание, отклонённые.

import '../../../widgets/ui/app_radio_tile.dart';
import '../widgets/feature_settings_sections.dart';
import 'dart:io' show Platform;
import '../../../core/theme/app_icons.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../services/device/device_calendar_sync.dart';
import '../../mail/providers/mail_providers.dart';
import '../providers/module_settings_provider.dart';
import '../../../core/permissions/app_permissions.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class CalendarSettingsScreen extends ConsumerWidget {
  const CalendarSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(moduleSettingsProvider);
    final n = ref.read(moduleSettingsProvider.notifier);

    String viewLabel(CalendarDefaultView v) {
      switch (v) {
        case CalendarDefaultView.day: return l10n.tr('viewDay');
        case CalendarDefaultView.threeDay: return l10n.tr('view3Days');
        case CalendarDefaultView.week: return l10n.tr('viewWeek');
        case CalendarDefaultView.month: return l10n.tr('viewMonth');
        case CalendarDefaultView.agenda: return l10n.tr('viewAgenda');
      }
    }

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('calendar')),
        actions: const [FaqButton(section: 'calendar')],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // «Мой день» и календарь — бывшие «Возможности» (1.6.1).
          const DayFeaturesSection(),
          SettingsSectionTitle(l10n.tr('display')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.view_module,
              title: l10n.tr('defaultView'),
              subtitle: viewLabel(s.calendarView),
              onTap: () => _pickView(context, ref, s.calendarView, viewLabel),
            ),
            SettingsItem(
              icon: AppIcons.today,
              title: l10n.tr('weekStartsOn'),
              subtitle: s.weekStartDay == 1 ? l10n.tr('monday') : l10n.tr('sunday'),
              onTap: () => n.setWeekStartDay(s.weekStartDay == 1 ? 7 : 1),
            ),
            SettingsSwitchItem(
              icon: AppIcons.format_list_numbered,
              title: l10n.tr('weekNumbers'),
              value: s.showWeekNumbers,
              onChanged: n.setShowWeekNumbers,
            ),
          ]),
          SettingsSectionTitle(l10n.tr('events')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.notifications,
              title: l10n.tr('defaultReminder'),
              subtitle: _reminderLabel(s.defaultReminderMinutes, l10n),
              onTap: () => _pickReminder(context, ref, s.defaultReminderMinutes, l10n),
            ),
            SettingsSwitchItem(
              icon: AppIcons.notifications_active,
              title: l10n.tr('eventFallbackReminder'),
              subtitle: l10n.tr('eventFallbackReminderDesc'),
              value: s.eventFallbackReminder,
              onChanged: (v) async {
                await n.setEventFallbackReminder(v);
                await ref.read(reminderSchedulerProvider).rescheduleAll();
              },
            ),
            if (!kIsWeb && Platform.isAndroid)
              SettingsSwitchItem(
                icon: AppIcons.alarm,
                title: l10n.tr('eventAlarmClock'),
                subtitle: l10n.tr('eventAlarmClockDesc'),
                value: s.eventAlarmClock,
                onChanged: (v) async {
                  await n.setEventAlarmClock(v);
                  await ref.read(reminderSchedulerProvider).rescheduleAll();
                },
              ),
          ]),
          // «Показывать отклонённые» убрано: ответ на приглашение у событий
          // не хранится, переключатель ни на что не влиял.
          const _DeviceCalendarExportSection(),
        ],
      ),
    );
  }

  String _reminderLabel(int min, AppLocalizations l10n) {
    if (min <= 0) return l10n.tr('none');
    if (min < 60) return '$min ${l10n.tr('minShort')}';
    return '${min ~/ 60} ${l10n.tr('hourShort')}';
  }

  void _pickView(BuildContext context, WidgetRef ref, CalendarDefaultView current,
      String Function(CalendarDefaultView) label) {
    showAppSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: CalendarDefaultView.values.map((v) => AppRadioTile<CalendarDefaultView>(
                title: Text(label(v)),
                value: v,
                groupValue: current,
                onChanged: (sel) {
                  ref.read(moduleSettingsProvider.notifier).setCalendarView(sel!);
                  Navigator.pop(ctx);
                },
              )).toList(),
        ),
      ),
    );
  }

  void _pickReminder(BuildContext context, WidgetRef ref, int current, AppLocalizations l10n) {
    const options = [0, 5, 10, 15, 30, 60, 1440];
    showAppSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((m) => AppRadioTile<int>(
                title: Text(m == 0
                    ? (l10n.tr('none'))
                    : m == 1440
                        ? (l10n.tr('oneDayBefore'))
                        : _label(m, l10n)),
                value: m,
                groupValue: current,
                onChanged: (sel) async {
                  Navigator.pop(ctx);
                  await ref.read(moduleSettingsProvider.notifier).setDefaultReminder(sel!);
                  // Напоминания встреч без своего — по новому умолчанию.
                  await ref.read(reminderSchedulerProvider).rescheduleAll();
                },
              )).toList(),
        ),
      ),
    );
  }

  String _label(int m, AppLocalizations l10n) => m < 60 ? '$m ${l10n.tr('minShort')}' : '${m ~/ 60} ${l10n.tr('hourShort')}';

}

/// Экспорт событий в системный календарь устройства. Раздел виден ТОЛЬКО если
/// реально подключён нативный канал (иначе экспорт молча вернул бы 0 — фикция).
class _DeviceCalendarExportSection extends ConsumerStatefulWidget {
  const _DeviceCalendarExportSection();

  @override
  ConsumerState<_DeviceCalendarExportSection> createState() => _DeviceCalendarExportSectionState();
}

class _DeviceCalendarExportSectionState extends ConsumerState<_DeviceCalendarExportSection> {
  late final Future<bool> _ready = ref.read(deviceCalendarSyncProvider).isChannelReady();
  bool _busy = false;

  Future<void> _export() async {
    if (!await AppPermissions.ensure(context, AppPermission.calendar)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final account = ref.read(activeAccountProvider);
    if (account == null) return;
    setState(() => _busy = true);
    final count = await ref.read(deviceCalendarSyncProvider).exportAllEvents(account.id);
    if (!mounted) return;
    setState(() => _busy = false);
    showInlineNotice(l10n.tr('exportedEventsN').replaceAll('{count}', '$count'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSectionTitle(l10n.tr('deviceCalendar')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.upload,
                title: l10n.tr('exportEventsToDevice'),
                subtitle: l10n.tr('exportEventsToDeviceDesc'),
                trailing: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onTap: _busy ? null : _export,
              ),
            ]),
          ],
        );
      },
    );
  }
}

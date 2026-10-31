// lib/features/calendar/widgets/quick_event_sheet.dart
// Встреча одной фразой (1.9.x, просьба владельца 31.10.2026), как в
// Fantastical: поле ввода и живой предпросмотр того, что получится
// (название, день и время, место). Enter или «Создать» — встреча сразу в
// календаре ящика; «Подробнее» — полный редактор, уже заполненный.
// Открывается из «Создать встречу» в календаре и из «+» / меню создания на
// телефоне, планшете и компьютере.

import 'dart:async';

import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/date_links.dart' show DateContext;
import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/event_reminders.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider;
import '../../settings/providers/module_settings_provider.dart';
import '../calendar_data.dart' show calendarEventsProvider;
import '../quick_event.dart';

/// Открыть ввод встречи одной фразой. [day] — день, выбранный в календаре:
/// фраза без дня («Созвон в 15») — на него.
Future<void> showQuickEventSheet(BuildContext context, {DateTime? day}) {
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: QuickEventPanel(day: day),
    ),
  );
}

class QuickEventPanel extends ConsumerStatefulWidget {
  final DateTime? day;

  /// Сохранение — для тестов (по умолчанию — в календарь ящика).
  final Future<bool> Function(QuickEvent e)? onCreate;

  const QuickEventPanel({super.key, this.day, this.onCreate});

  @override
  ConsumerState<QuickEventPanel> createState() => _QuickEventPanelState();
}

class _QuickEventPanelState extends ConsumerState<QuickEventPanel> {
  final _ctrl = TextEditingController();
  QuickEvent? _parsed;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Опорный момент: выбранный в календаре день (не сегодня) — его утро,
  /// чтобы «в 15» встало на него, а «завтра» считалось от него.
  DateTime get _now {
    final now = DateTime.now();
    final d = widget.day;
    if (d == null || (d.year == now.year && d.month == now.month && d.day == now.day)) return now;
    return DateTime(d.year, d.month, d.day, 0, 0);
  }

  QuickEvent? _parse(String v) => v.trim().isEmpty
      ? null
      : QuickEventParser.parse(
          v,
          now: _now,
          monthFirst: DateContext.deviceMonthFirst,
          length: const Duration(minutes: 30),
        );

  String _when(QuickEvent e, AppLocalizations l10n) {
    final loc = Localizations.localeOf(context).toLanguageTag();
    final day = DateFormat.MMMEd(loc).format(e.start);
    if (e.allDay) return day;
    final t = DateFormat.Hm(loc);
    final sameDay = e.end.year == e.start.year && e.end.month == e.start.month && e.end.day == e.start.day;
    return sameDay
        ? '$day · ${t.format(e.start)}–${t.format(e.end)}'
        : '$day · ${t.format(e.start)} – ${DateFormat.MMMEd(loc).add_Hm().format(e.end)}';
  }

  Future<void> _create() async {
    final e = _parsed;
    if (e == null || _saving) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    final title = e.title.isEmpty ? l10n.tr('newEvent') : e.title;
    final ok = await (widget.onCreate?.call(e) ?? _store(ref, l10n, e, title));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      unawaited(HapticFeedback.mediumImpact());
      showInlineNotice(l10n.tr('meetingCreated'));
      Navigator.of(context).pop();
    }
  }

  void _more() {
    final e = _parsed;
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(
      router.push(
        '/create-event',
        extra: {
          if (e != null && e.dated) 'start': e.start,
          if (e != null && e.dated) 'end': e.end,
          if (e != null && e.allDay) 'allDay': true,
          if (e != null && e.title.isNotEmpty) 'title': e.title,
          if (e?.location != null) 'location': e!.location,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final e = _parsed;
    final muted = AppColors.mutedText(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.tr('quickEventTitle'), style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.s),
            TextField(
              key: const ValueKey('quickEventField'),
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: l10n.tr('quickEventHint')),
              onChanged: (v) => setState(() => _parsed = _parse(v)),
              onSubmitted: (_) => unawaited(_create()),
            ),
            const SizedBox(height: Space.m),
            // Предпросмотр: что получится.
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              child: e == null
                  ? const SizedBox(width: double.infinity)
                  : Card(
                      key: const ValueKey('quickEventPreview'),
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(AppIcons.event, color: theme.colorScheme.primary),
                        title: Text(
                          e.title.isEmpty ? l10n.tr('newEvent') : e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: e.title.isEmpty ? TextStyle(color: muted) : null,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_when(e, l10n)),
                            if (e.location != null)
                              Row(
                                children: [
                                  Icon(AppIcons.place, size: 16, color: muted),
                                  const SizedBox(width: Space.xs),
                                  Expanded(child: Text(e.location!, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: Space.m),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _more, child: Text(l10n.tr('quickEventMore'))),
                const SizedBox(width: Space.s),
                FilledButton(
                  onPressed: e == null || _saving ? null : () => unawaited(_create()),
                  child: Text(l10n.tr('create')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ящик для новой встречи: выбранный в почте, если в его календарь можно
/// записать, иначе первый такой (как у редактора встречи).
AccountModel? _account(WidgetRef ref) {
  final engine = ref.read(mailEngineServiceProvider);
  final list = [
    for (final a in ref.read(accountsProvider))
      if (a.isActive && !a.isSharedMailbox && !a.isOnlineArchive) a,
  ];
  final active = ref.read(activeAccountProvider);
  if (list.isEmpty) return active;
  if (active != null && list.any((a) => a.id == active.id) && engine.canWriteCalendar(active)) return active;
  return list.where(engine.canWriteCalendar).firstOrNull ?? list.first;
}

/// Встреча — на сервере (Exchange, CalDAV) и в базе телефона; напоминание —
/// из настроек календаря. Тот же путь, что у «Сохранить» в редакторе
/// встречи, без участников и файлов.
Future<bool> _store(WidgetRef ref, AppLocalizations l10n, QuickEvent q, String title) async {
  final account = _account(ref);
  if (account == null) return false;
  try {
    final engine = ref.read(mailEngineServiceProvider);
    final def = ref.read(moduleSettingsProvider).defaultReminderMinutes;
    final reminders = def > 0 ? [def] : const <int>[];
    final start = q.allDay ? DateTime(q.start.year, q.start.month, q.start.day) : q.start;
    // Весь день — до полуночи после последнего дня (как хранит Exchange).
    final end = q.allDay ? DateTime(q.end.year, q.end.month, q.end.day + 1) : q.end;
    final event = CalendarEventModel(
      id: const Uuid().v4(),
      accountId: account.id,
      title: title,
      location: q.location,
      startTime: start,
      endTime: end,
      isAllDay: q.allDay,
      organizerEmail: account.email,
      colorValue: AppColors.primaryBlue.toARGB32(),
      reminders: [for (final m in EventReminders.normalize(reminders)) EventReminder(minutesBefore: m)],
      createdAt: DateTime.now(),
    );
    var localId = event.id;
    var serverCreated = false;
    final canWrite = engine.canWriteCalendar(account);
    if (canWrite) {
      final r = await engine.createEvent(account, event);
      serverCreated = r.created;
      if (r.id != null) {
        localId = r.id!;
      } else if (r.created) {
        unawaited(ref.read(syncServiceProvider).syncAll());
      } else {
        AppLogger.warning('Встреча одной фразой: сервер не создал событие — сохранено локально');
      }
    }
    if (!(serverCreated && localId == event.id)) {
      final db = ref.read(databaseProvider);
      final keepsAll = !canWrite || engine.keepsManyReminders(account);
      await db
          .into(db.calendarEvents)
          .insert(
            CalendarEventsCompanion.insert(
              id: localId,
              accountId: event.accountId,
              title: event.title,
              location: Value(event.location),
              startTime: event.startTime,
              endTime: event.endTime,
              isAllDay: Value(event.isAllDay),
              organizerEmail: Value(event.organizerEmail),
              colorValue: Value(event.colorValue),
              remindersJson: Value(EventReminders.encode(reminders, serverKeepsAll: keepsAll)),
              createdAt: event.createdAt,
            ),
            mode: InsertMode.insertOrReplace,
          );
      await ref.read(reminderSchedulerProvider).rescheduleAll();
    }
    ref.invalidate(calendarEventsProvider);
    return true;
  } catch (e) {
    AppLogger.warning('Встреча одной фразой: $e');
    showInlineError('${l10n.tr('error')}: $e');
    return false;
  }
}

// lib/features/calendar/calendar_event_actions.dart
// Действия над событием календаря, общие для всех экранов календаря:
// удаление (с учётом повторяющихся серий ActiveSync), участники, «Поделиться».
//
// Раньше эти пункты меню были в двух местах с разной логикой: удаление шло
// от имени АКТИВНОГО аккаунта (а не того, чьё событие — в режиме групп и
// «Все аккаунты» это другой ящик), а «Участники», «Напоминание», «Поделиться»
// просто закрывали меню.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../widgets/ui/confirm_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart' show EmailAddress;
import '../compose/widgets/people_picker_sheet.dart' show showPeoplePicker;
import '../../core/theme/app_icons.dart';
import '../../data/models/contact_model.dart' show ContactModel;
import '../../widgets/common/message_sheet.dart';
import '../../data/providers/database_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/mail/engine/mail_engine_service.dart';
import '../../services/mail/own_addresses.dart';
import '../../services/notifications/reminder_scheduler_service.dart';
import '../../services/sync/sync_service.dart' show syncServiceProvider;
import '../mail/providers/mail_providers.dart';
import '../../data/models/account_model.dart' show AccountModel;
import '../../data/providers/shared_prefs_provider.dart';
import '../../services/calendar/pending_invites.dart' show markInvitesForEvent;
import '../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class CalendarEventActions {
  /// Удалить событие на сервере и локально.
  ///
  /// Вхождение повторяющейся серии ActiveSync (id «eas_<ServerId>#<день>») на
  /// сервере отдельным элементом не существует — удаляется вся серия, о чём
  /// пользователь предупреждается. Серии EWS приходят развёрнутыми сервером,
  /// у каждого вхождения свой ItemId — там удаляется только вхождение.
  static Future<bool> delete(BuildContext context, WidgetRef ref, CalendarEvent event) async {
    final l10n = AppLocalizations.of(context);
    final account = ref.read(accountsProvider).where((a) => a.id == event.accountId).firstOrNull;
    final engine = ref.read(mailEngineServiceProvider);
    // CalDAV удаляет только это вхождение (EXDATE) — без предупреждения о серии.
    var single = account != null && engine.deletesSingleOccurrence(account);
    final original = (start: event.startTime, end: event.endTime, title: event.title);
    // Вхождение серии при доступном EWS (1.6.7): как в Outlook — «Только это
    // вхождение» или «Вся серия». Без EWS ActiveSync удаляет только серию.
    var wholeSeries = true;
    var asked = false;
    if (account != null && !single && engine.canManageMeetings(account)) {
      bool inSeries;
      try {
        inSeries = await engine.isSeriesOccurrence(account, event.id, event.recurrence);
      } catch (_) {
        inSeries = MailEngineService.isOccurrenceId(event.id);
      }
      if (inSeries) {
        if (!context.mounted) return false;
        final c = await askSeriesScope(context, delete: true);
        if (c == null) return false;
        wholeSeries = c;
        single = !c;
        asked = true;
      }
    }
    final isSeries = MailEngineService.isOccurrenceId(event.id) && !single;
    if (isSeries && !asked) {
      if (!context.mounted) return false;
      final ok = await confirmDestructive(context,
          title: l10n.tr('deleteSeriesTitle'), message: l10n.tr('deleteSeriesBody'));
      if (!ok) return false;
    }
    // Чужая встреча (организатор — не мы): как в Outlook, удалить = отклонить
    // и сообщить организатору, либо удалить молча (1.5.12).
    final org = (event.organizerEmail ?? '').trim();
    final invited = account != null &&
        org.isNotEmpty &&
        !OwnAddresses.isMine(account, org) &&
        engine.canWriteCalendar(account) &&
        (account.usesEas || account.usesEws || account.isExchange);
    // Своё событие или встреча, где мы организатор: спросить (1.6.4,
    // замечание 13.10.2026: случайное нажатие удаляло собрание — участникам
    // уходила отмена). Серию и чужую встречу спрашивают свои окна выше и ниже.
    if (!isSeries && !invited && !asked) {
      if (!context.mounted) return false;
      final withPeople = (event.attendeesJson ?? '').length > 4;
      final title = event.title.trim();
      final ok = await confirmDestructive(context,
          title: l10n.tr(withPeople ? 'deleteMeetingTitle' : 'deleteEventTitle'),
          message: l10n.tr(withPeople ? 'deleteMeetingBody' : 'deleteEventBody')
              .replaceAll('{t}', title.isEmpty ? l10n.tr('noSubject') : title));
      if (!ok) return false;
    }
    var decline = false;
    if (invited) {
      if (!context.mounted) return false;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.tr('meetingDeleteInvitedTitle')),
          content: Text(l10n.tr('meetingDeleteInvitedBody').replaceAll('{o}', org)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(l10n.tr('meetingDeleteSilently'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'decline'), child: Text(l10n.tr('meetingDeclineAndDelete'))),
          ],
        ),
      );
      if (choice == null || !context.mounted) return false;
      decline = choice == 'decline';
    }
    final db = ref.read(databaseProvider);
    try {
      if (account != null && engine.canWriteCalendar(account)) {
        var declined = false;
        if (decline) {
          try {
            declined = await engine.declineEvent(account, event.id, wholeSeries: wholeSeries, original: original);
          } catch (e) {
            AppLogger.warning('Отклонение встречи ${event.id}: $e');
          }
        }
        if (!declined) await engine.deleteEvent(account, event.id, wholeSeries: wholeSeries, original: original);
      }
      // Вся серия EWS: остальные вхождения уберёт ближайшая синхронизация.
      if (asked && wholeSeries) unawaited(ref.read(syncServiceProvider).syncAll());
      final masterId = isSeries ? event.id.substring(0, event.id.indexOf('#')) : event.id;
      if (single && MailEngineService.isOccurrenceId(event.id)) {
        await (db.delete(db.calendarEvents)
              ..where((e) => e.accountId.equals(event.accountId) & e.id.equals(event.id)))
            .go();
        try {
          await ref.read(reminderSchedulerProvider).rescheduleAll();
        } catch (_) {}
        return true;
      }
      await (db.delete(db.calendarEvents)
            ..where((e) =>
                e.accountId.equals(event.accountId) &
                (e.id.equals(masterId) | e.id.like('$masterId#%'))))
          .go();
      // Напоминание удалённой встречи снимается сразу, не дожидаясь синка.
      try {
        await ref.read(reminderSchedulerProvider).rescheduleAll();
      } catch (_) {}
      AppLogger.info(l10n.tr('deleted'));
      return true;
    } catch (e) {
      AppLogger.warning('Удаление события ${event.id}: $e');
      if (context.mounted) showInlineError('${l10n.error}: $e');
      return false;
    }
  }

  /// Можно ли переслать приглашение: через EWS сервером (как «Переслать» у
  /// собрания в Outlook) или письмом-приглашением, из которого встреча
  /// появилась (1.6.7).
  static bool canForwardInvite(WidgetRef ref, CalendarEvent event) {
    if ((event.attendeesJson ?? '').length <= 4 && (event.organizerEmail ?? '').isEmpty) return false;
    final account = ref.read(accountsProvider).where((a) => a.id == event.accountId).firstOrNull;
    if (account == null) return false;
    // ActiveSync пересылает встречу сам (SmartForward, 1.6.34).
    return ref.read(mailEngineServiceProvider).canManageMeetings(account) ||
        account.usesEas ||
        (event.linkedEmailId ?? '').isNotEmpty;
  }

  /// Переслать приглашение (1.6.7): выбрать людей, по желанию — пара слов
  /// от себя. Exchange отправляет им приглашение на ту же встречу, а
  /// организатор получает уведомление о пересылке. Без EWS — пересылка
  /// письма-приглашения через обычное «Переслать».
  static Future<void> forwardInvite(BuildContext context, WidgetRef ref, CalendarEvent event) async {
    final l10n = AppLocalizations.of(context);
    final account = ref.read(accountsProvider).where((a) => a.id == event.accountId).firstOrNull;
    if (account == null) return;
    final engine = ref.read(mailEngineServiceProvider);
    final linked = (event.linkedEmailId ?? '').trim();
    void viaMail() => context.push(
        '/compose?forwardFromId=${Uri.encodeComponent(linked)}&accountId=${Uri.encodeComponent(account.id)}');
    final viaEws = engine.canManageMeetings(account);
    if (!viaEws && !account.usesEas) {
      if (linked.isNotEmpty) viaMail();
      return;
    }
    final already = <String>{
      for (final a in (jsonDecodeList(event.attendeesJson)))
        if (a is Map && (a['email'] ?? '').toString().isNotEmpty) a['email'].toString().toLowerCase(),
    };
    List<SheetPerson> asPeople(List<ContactModel> list) => [
          for (final c in list) SheetPerson(c.email.trim(), c.displayName.isNotEmpty ? c.displayName : null),
        ];
    final picked = await showPeoplePicker(context, account: account, exclude: already);
    if (picked.isEmpty || !context.mounted) return;
    // Шторка в стиле приложения (1.6.38): кому — с портретами (убрать,
    // добавить ещё), текст, «Отправить».
    final s = event.startTime.toLocal();
    final when = DateFormat('EEE, d MMM, HH:mm', l10n.localeCode).format(s);
    final res = await showMessageSheet(
      context,
      title: l10n.tr('forwardInvite'),
      subtitle: '${event.title.trim().isEmpty ? l10n.tr('noSubject') : event.title.trim()} · $when',
      icon: AppIcons.forward,
      people: asPeople(picked),
      onAddPeople: (have) async => asPeople(
          await showPeoplePicker(context, account: account, exclude: {...already, ...have})),
      hint: l10n.tr('forwardInviteNote'),
      actionLabel: l10n.tr('send'),
    );
    if (res == null || res.people.isEmpty || !context.mounted) return;
    final note = res.text;
    var ok = false;
    try {
      final to = [
        for (final c in res.people) EmailAddress(email: c.email, displayName: c.name),
      ];
      ok = viaEws
          ? await engine.forwardMeeting(account, event.id,
              original: (start: event.startTime, end: event.endTime, title: event.title), to: to, note: note)
          : await engine.forwardMeetingEas(account, event.id, to: to, title: event.title, note: note);
    } catch (e) {
      AppLogger.warning('Пересылка приглашения ${event.id}: $e');
    }
    if (ok) {
      unawaited(HapticFeedback.lightImpact());
      showInlineNotice(l10n.tr('inviteForwarded'));
      return;
    }
    if (!context.mounted) return;
    // Сервер не переслал — предложить переслать письмо-приглашение.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('forwardInvite')),
        content: Text(l10n.tr(linked.isEmpty ? 'inviteForwardFailed' : 'inviteForwardFailedMail')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close'))),
          if (linked.isNotEmpty)
            FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  viaMail();
                },
                child: Text(l10n.tr('forwardInviteMail'))),
        ],
      ),
    );
  }

  static List<Object?> jsonDecodeList(String? raw) {
    if (raw == null || raw.length < 2) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  /// «Только это вхождение» (false) или «Вся серия» (true), null — отмена
  /// (1.6.7, как в Outlook при открытии и удалении вхождения серии).
  static Future<bool?> askSeriesScope(BuildContext context, {required bool delete}) {
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr(delete ? 'seriesDeleteTitle' : 'seriesEditTitle')),
        content: Text(l10n.tr('seriesScopeBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('seriesWhole'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('seriesThisOccurrence'))),
        ],
      ),
    );
  }

  /// Кому отправить обновление собрания, когда изменился состав
  /// участников (1.6.7, как «Отправить обновление» в Outlook): true —
  /// только добавленным и удалённым, false — всем, null — отмена.
  static Future<bool?> askUpdateRecipients(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    var onlyChanged = true;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.tr('sendUpdateTitle')),
          content: RadioGroup<bool>(
            groupValue: onlyChanged,
            onChanged: (v) => setState(() => onlyChanged = v ?? true),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero, value: true, title: Text(l10n.tr('sendUpdateChanged'))),
              RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero, value: false, title: Text(l10n.tr('sendUpdateAll'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, onlyChanged), child: Text(l10n.tr('send'))),
          ],
        ),
      ),
    );
  }

  /// Участники встречи (из синхронизированных данных).
  static Future<void> showParticipants(BuildContext context, CalendarEvent event) {
    final l10n = AppLocalizations.of(context);
    final people = <String>[];
    if ((event.organizerEmail ?? '').isNotEmpty) {
      people.add('${event.organizerEmail} (${l10n.tr('organizer')})');
    }
    try {
      final raw = event.attendeesJson;
      if (raw != null && raw.isNotEmpty) {
        for (final a in jsonDecode(raw) as List) {
          final m = a as Map<String, dynamic>;
          final email = (m['email'] ?? '').toString();
          final name = (m['displayName'] ?? m['name'] ?? '').toString();
          if (email.isNotEmpty) people.add(name.isNotEmpty ? '$name <$email>' : email);
        }
      }
    } catch (_) {}
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('participants')),
        content: people.isEmpty
            ? Text(l10n.tr('noParticipants'))
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final p in people) ListTile(dense: true, title: Text(p))],
                ),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('close')))],
      ),
    );
  }

  /// Ответить на чужую встречу сразу, без комментария (1.6.47: карточка
  /// встречи по удержанию). Как «Отправить ответ сейчас» на экране встречи:
  /// отклонённая уходит из календаря, принятая — «занят», под вопросом —
  /// «под вопросом»; письмо-приглашение — из «Ждут ответа». Сервисы берутся
  /// до ожидания: календарь могут закрыть, пока ответ идёт.
  static Future<bool> respondNow(WidgetRef ref, AccountModel account, CalendarEvent e, String response,
      AppLocalizations l10n) async {
    final engine = ref.read(mailEngineServiceProvider);
    final db = ref.read(databaseProvider);
    final prefs = ref.read(sharedPrefsProvider);
    final reminders = ref.read(reminderSchedulerProvider);
    try {
      final r = await engine.respondToEvent(account, e.id, response: response);
      if (!r.ok) {
        showInlineError(l10n.tr('couldNotSendResponse'));
        return false;
      }
      await markInvitesForEvent(db, accountId: e.accountId, title: e.title, start: e.startTime);
      final master = MailEngineService.isOccurrenceId(e.id) ? e.id.substring(0, e.id.indexOf('#')) : e.id;
      // Тот же ключ, что у экрана встречи: там сразу виден данный ответ.
      await prefs.setString('evt_resp:${account.id}:$master', response);
      if (response == 'decline') {
        try {
          await engine.deleteEventServer(account, master);
        } catch (_) {}
        await (db.delete(db.calendarEvents)
              ..where((x) => x.accountId.equals(e.accountId) & (x.id.equals(master) | x.id.like('$master#%'))))
            .go();
        try {
          await reminders.rescheduleAll();
        } catch (_) {}
      } else {
        await (db.update(db.calendarEvents)
              ..where((x) => x.accountId.equals(e.accountId) & (x.id.equals(master) | x.id.like('$master#%'))))
            .write(CalendarEventsCompanion(showAs: Value(response == 'accept' ? 2 : 1)));
      }
      unawaited(HapticFeedback.mediumImpact());
      return true;
    } catch (err) {
      showInlineError('${l10n.tr('couldNotSendResponse')}: $err');
      return false;
    }
  }

  /// Поделиться событием текстом (тема, время, место, ссылка).
  static Future<void> share(BuildContext context, CalendarEvent event) async {
    final l10n = AppLocalizations.of(context);
    final f = DateFormat('d MMMM yyyy, HH:mm', l10n.localeCode);
    final t = DateFormat('HH:mm');
    final b = StringBuffer(event.title)
      ..write('\n')
      ..write(event.isAllDay
          ? DateFormat('d MMMM yyyy', l10n.localeCode).format(event.startTime.toLocal())
          : '${f.format(event.startTime.toLocal())}–${t.format(event.endTime.toLocal())}');
    if ((event.location ?? '').isNotEmpty) b.write('\n${event.location}');
    if ((event.onlineMeetingUrl ?? '').isNotEmpty) b.write('\n${event.onlineMeetingUrl}');
    if ((event.description ?? '').isNotEmpty) b.write('\n\n${event.description}');
    await SharePlus.instance.share(ShareParams(text: b.toString(), subject: event.title));
  }
}

// lib/features/calendar/screens/event_details_screen.dart
// Встреча целиком: когда, где, кнопка «Подключиться», организатор и
// участники (с фото), напоминание (меняется прямо здесь), описание, ящик.
// Раньше по нажатию на встречу открывалось меню из четырёх пунктов, а
// подробностей посмотреть было негде.

import '../../contacts/person_names.dart' show personNamesProvider, fullPersonNameProvider, bestPersonName;
import '../../../widgets/ui/settings_group.dart';
import '../../../core/utils/text_safe.dart';
import 'dart:convert';
import '../../../core/theme/app_icons.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import '../../../widgets/common/message_sheet.dart' show showMessageSheet;
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_router.dart' show mailOpenPath;
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/meeting_link_service.dart';
import '../../../services/calendar/meeting_prep.dart';
import '../../../services/notifications/reminder_scheduler_service.dart';
import '../../../services/calendar/event_reminders.dart';
import '../widgets/reminder_list_editor.dart' show reminderLabel, showRemindersSheet;
import '../../../widgets/common/person_photo.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../mail/providers/mail_providers.dart';
import '../calendar_data.dart';
import '../meeting_replies.dart';
import '../../../services/mail/own_addresses.dart';
import '../calendar_event_actions.dart';
import '../../../data/models/account_model.dart';
import '../../../services/calendar/pending_invites.dart' show markInvitesForEvent;
import '../../../services/mail/engine/mail_engine_service.dart' show mailEngineServiceProvider, MailEngineService;
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../core/utils/avatar_colors.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

/// Событие по (id, аккаунт) — поток: правка или синхронизация обновляют экран.
final eventByIdProvider =
    StreamProvider.autoDispose.family<CalendarEvent?, (String, String)>((ref, key) {
  final db = ref.watch(databaseProvider);
  final q = db.select(db.calendarEvents)..where((e) => e.id.equals(key.$1));
  if (key.$2.isNotEmpty) q.where((e) => e.accountId.equals(key.$2));
  return q.watch().map((rows) => rows.isEmpty ? null : rows.first);
});

class EventDetailsScreen extends ConsumerWidget {
  final String eventId;
  final String accountId;
  /// Встроенный режим (правая панель календаря на планшете): кнопка
  /// «Закрыть» вместо «Назад», после удаления панель закрывается.
  final VoidCallback? onClose;
  const EventDetailsScreen({super.key, required this.eventId, required this.accountId, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(eventByIdProvider((eventId, accountId)));
    return async.when(
      loading: () => Scaffold(appBar: TextScaleCapBar(child: _bar(context)), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: TextScaleCapBar(child: _bar(context)), body: Center(child: Text('${l10n.error}: $e'))),
      data: (event) {
        if (event == null) {
          return Scaffold(
            appBar: TextScaleCapBar(child: _bar(context)),
            body: Center(child: Text(l10n.tr('eventNotFound'))),
          );
        }
        return _EventDetails(event: event, onClose: onClose);
      },
    );
  }

  AppBar _bar(BuildContext context) => onClose == null
      ? AppBar()
      : AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: const Icon(AppIcons.close),
            onPressed: onClose,
          ),
        );
}

class _EventDetails extends ConsumerWidget {
  final CalendarEvent event;
  final VoidCallback? onClose;
  const _EventDetails({required this.event, this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = l10n.localeCode;
    final e = event;
    final colors = ref.watch(accountColorsProvider);
    final color = eventColor(e, colors);
    final account = ref.watch(accountsProvider).where((a) => a.id == e.accountId).firstOrNull;
    final photos = ref.watch(personPhotosProvider).value ?? const <String, String>{};
    // Имена по адресу — из контактов и писем (1.6.2): организатор приходит
    // только адресом, и строка показывала почту вместо ФИО.
    final names = ref.watch(personNamesProvider).value ?? const <String, String>{};
    // 1.6.4: и имя из приглашения («Смирнов, Андрей») заменяется полным ФИО,
    // если оно известно, — в компании много однофамильцев.
    String? nameOf(String email, String? given) {
      final g = given?.trim();
      final low = email.toLowerCase();
      final own = account != null && account.email.toLowerCase() == low && account.displayName.trim().isNotEmpty
          ? account.displayName.trim()
          : null;
      final dir = ref.watch(fullPersonNameProvider((email: low, accountId: account?.id))).value;
      return bestPersonName(g, [names[low], own, dir]) ?? g;
    }

    final link = (e.onlineMeetingUrl ?? '').isNotEmpty
        ? MeetingLink(MeetingLinkService.platformOf(e.onlineMeetingUrl!) ?? '', e.onlineMeetingUrl!)
        : MeetingLinkService.find(location: e.location, description: e.description);
    final attendees = _attendees(e);
    // Ответы участников из писем-ответов (1.6.7): комментарии, предложенное
    // время и ответы, которые сервер ещё не отметил в копии собрания.
    final replies = attendees.isEmpty
        ? const <MeetingReply>[]
        : ref.watch(meetingRepliesProvider((accountId: e.accountId, eventId: e.id))).value ?? const <MeetingReply>[];
    final replyBy = {for (final r in replies) r.email.toLowerCase(): r};
    final org = (e.organizerEmail ?? '').trim();
    final iAmOrganizer = account != null && attendees.isNotEmpty &&
        (org.isEmpty || OwnAddresses.isMine(account, org));
    int statusOf(String email, int server) => server != 0 ? server : (replyBy[email.toLowerCase()]?.kind ?? 0);
    final s = e.startTime.toLocal();
    final en = e.endTime.toLocal();
    final now = DateTime.now();
    final recurring = e.recurrence != 0 || e.id.contains('#');

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        automaticallyImplyLeading: onClose == null,
        leading: onClose == null
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(AppIcons.close),
                onPressed: onClose,
              ),
        actions: [
          IconButton(
            tooltip: l10n.tr('edit'),
            icon: const Icon(AppIcons.edit),
            onPressed: () => context.push('/create-event', extra: e),
          ),
          IconButton(
            tooltip: l10n.tr('duplicateEvent'),
            icon: const Icon(AppIcons.copy_all),
            onPressed: () => context.push('/create-event', extra: {'duplicate': e}),
          ),
          // «Поделиться» у встречи с участниками (1.6.34, замечание
          // 18.10.2026): «Переслать приглашение» — настоящим приглашением
          // через сервер — или текстом, как раньше.
          IconButton(
            tooltip: l10n.tr('share'),
            icon: const Icon(AppIcons.share),
            onPressed: () async {
              if (!CalendarEventActions.canForwardInvite(ref, e)) {
                await CalendarEventActions.share(context, e);
                return;
              }
              final v = await showActionSheet<String>(
                context,
                title: e.title.isEmpty ? l10n.tr('noSubject') : e.title,
                items: [
                  ActionSheetItem(
                      icon: AppIcons.forward,
                      label: l10n.tr('forwardInvite'),
                      subtitle: l10n.tr('forwardInviteHint'),
                      value: 'fwd'),
                  ActionSheetItem(icon: AppIcons.share, label: l10n.tr('shareAsText'), value: 'text'),
                ],
              );
              if (!context.mounted) return;
              if (v == 'fwd') {
                await CalendarEventActions.forwardInvite(context, ref, e);
              } else if (v == 'text') {
                await CalendarEventActions.share(context, e);
              }
            },
          ),
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(AppIcons.delete),
            onPressed: () async {
              final ok = await CalendarEventActions.delete(context, ref, e);
              if (!ok || !context.mounted) return;
              if (onClose != null) {
                onClose!();
              } else {
                context.pop();
              }
            },
          ),
        ],
      )),
      // Разделы — белыми карточками с серыми полосами, как в настройках
      // (1.7.2+106, замечание владельца 24.10.2026: «очень серые, нет
      // группировки»): «Когда и где», «Календарь», «Участники», «Ответы»,
      // «К встрече», «Описание».
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xxl),
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 6, right: 14),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        e.title.isEmpty ? l10n.tr('noSubject') : e.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: e.isCancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (account != null && account.isSharedMailbox)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: SharedMailboxBadge(mailboxEmail: account.sharedMailboxEmail ?? account.email),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Когда и где
          SettingsSectionTitle(l10n.tr('eventGroupWhen')),
          SettingsGroup(children: [
            _Row(
              icon: AppIcons.schedule,
              title: capitalize(DateFormat('EEEE, d MMMM yyyy', locale).format(s)),
              subtitle: e.isAllDay
                  ? (en.difference(s).inDays > 1
                      ? '${l10n.tr('allDay')} · ${l10n.tr('untilDate').replaceAll('{date}', DateFormat('d MMMM', locale).format(en.subtract(const Duration(days: 1))))}'
                      : l10n.tr('allDay'))
                  : (CalendarViewUtils.sameDay(s, en)
                      ? '${DateFormat('HH:mm').format(s)} – ${DateFormat('HH:mm').format(en)} '
                          '(${CalendarViewUtils.durationLabel(en.difference(s), l10n)})'
                      : '${DateFormat('HH:mm').format(s)} – ${DateFormat('d MMM, HH:mm', locale).format(en)}'),
              trailing: _whenBadge(theme, l10n, s, en, now),
            ),
            if (recurring)
              _Row(
                icon: AppIcons.repeat,
                title: _recurrenceLabel(e.recurrence, l10n),
              ),
            // Подключиться
            if (link != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l + Sizes.icon + Space.l, Space.s, Space.l, Space.s),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    icon: const Icon(AppIcons.videocam),
                    label: Text(link.platform.isEmpty
                        ? l10n.tr('joinMeeting')
                        : l10n.tr('joinMeetingIn').replaceAll('{platform}', link.platform)),
                    onPressed: () => _launch(link.url),
                  ),
                ),
              ),
            // Где
            if ((e.location ?? '').isNotEmpty)
              _Row(
                icon: AppIcons.place,
                title: e.location!,
                onTap: () => _openMap(e.location!),
                onLongPress: () => _copy(context, l10n, e.location!),
              ),
            // Напоминание
            _ReminderRow(event: e),
          ]),

          // Календарь: ящик и статус, мой ответ, письмо-приглашение
          SettingsSectionTitle(l10n.tr('eventGroupCalendar')),
          SettingsGroup(children: [
            _Row(
              icon: AppIcons.calendar_today,
              title: account?.displayName.isNotEmpty == true ? account!.displayName : (account?.email ?? e.accountId),
              subtitle: [
                if (account != null && account.displayName.isNotEmpty) account.email,
                _showAsLabel(e.showAs, l10n),
                if (e.isPrivate) l10n.tr('privateEvent'),
              ].join(' · '),
              leadingColor: account != null ? Color(account.colorValue) : null,
            ),
            // Мой ответ на чужую встречу (1.6.34): принять, под вопросом,
            // отклонить, предложить новое время — прямо из календаря.
            if (account != null &&
                org.isNotEmpty &&
                !OwnAddresses.isMine(account, org) &&
                !e.isCancelled &&
                e.endTime.isAfter(now) &&
                ref.read(mailEngineServiceProvider).canRespondToEvent(account))
              _MyResponse(
                event: e,
                account: account,
                serverStatus: attendees
                        .where((a) => OwnAddresses.isMine(account, a.email))
                        .map((a) => a.response)
                        .firstOrNull ??
                    0,
              ),
            // Приглашение в почте
            if ((e.linkedEmailId ?? '').isNotEmpty)
              _Row(
                icon: AppIcons.mail,
                title: l10n.tr('openInvitation'),
                onTap: () => context.push(mailOpenPath(context, e.linkedEmailId!, accountId: e.accountId)),
              ),
          ]),

          // Организатор и участники
          if ((e.organizerEmail ?? '').isNotEmpty || attendees.isNotEmpty) ...[
            SettingsSectionTitle(
              l10n.tr('participants'),
              count: attendees.isEmpty ? null : attendees.length + 1,
              trailing: attendees.isEmpty
                  ? null
                  : TextButton.icon(
                icon: const Icon(AppIcons.mail, size: 18),
                label: Text(l10n.tr('emailAttendees')),
                onPressed: () {
                  final all = {
                    if ((e.organizerEmail ?? '').isNotEmpty) e.organizerEmail!,
                    for (final a in attendees) a.email,
                  }..removeWhere((x) => x.toLowerCase() == (account?.email.toLowerCase() ?? ''));
                  context.push(Uri(path: '/compose', queryParameters: {
                    'to': all.join(','),
                    if (account != null) 'accountId': account.id,
                  }).toString());
                },
              ),
            ),
            // Фото 36 + 12 — разделители с линии имён.
            SettingsGroup(dividerIndent: Space.l + 36 + Space.m, children: [
            if ((e.organizerEmail ?? '').isNotEmpty)
              _Person(
                email: e.organizerEmail!,
                name: nameOf(e.organizerEmail!,
                    attendees.where((a) => a.email.toLowerCase() == e.organizerEmail!.toLowerCase()).firstOrNull?.name),
                role: l10n.tr('organizer'),
                photo: photos[e.organizerEmail!.toLowerCase()],
                accountId: account?.id,
              ),
            for (final a in attendees)
              if (a.email.toLowerCase() != (e.organizerEmail ?? '').toLowerCase())
                _Person(
                  email: a.email,
                  name: nameOf(a.email, a.name),
                  role: a.required ? null : l10n.tr('optionalAttendee'),
                  photo: photos[a.email.toLowerCase()],
                  accountId: account?.id,
                  response: statusOf(a.email, a.response),
                ),
            ]),
          ],

          // Ответы на моё собрание: сводка, комментарии, предложения времени.
          if (iAmOrganizer)
            _RepliesSection(
              event: e,
              statuses: [
                for (final a in attendees)
                  if (a.email.toLowerCase() != org.toLowerCase() &&
                      !OwnAddresses.isMine(account, a.email))
                    statusOf(a.email, a.response),
              ],
              replies: replies,
              nameOf: (r) => nameOf(r.email, r.name) ?? r.email,
            ),

          // К встрече: письма по теме с участниками и вложения из них.
          _PrepSection(event: e),

          // Описание
          if ((e.description ?? '').trim().isNotEmpty) ...[
            SettingsSectionTitle(l10n.tr('description')),
            SettingsGroup(children: [
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: SelectableText(
                  _plain(e.description!),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget? _whenBadge(ThemeData theme, AppLocalizations l10n, DateTime s, DateTime en, DateTime now) {
    String? text;
    Color? c;
    if (now.isAfter(s) && now.isBefore(en) && !event.isAllDay) {
      text = l10n.tr('eventNow');
      c = theme.colorScheme.primary;
    } else if (s.isAfter(now) && s.difference(now).inMinutes < 60) {
      text = l10n.tr('eventInMinutes').replaceAll('{n}', '${s.difference(now).inMinutes + 1}');
      c = theme.colorScheme.tertiary;
    } else if (en.isBefore(now)) {
      text = l10n.tr('eventPast');
      c = theme.hintColor;
    }
    if (text == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 3),
      decoration: BoxDecoration(color: c!.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }

  static List<({String email, String? name, bool required, int response})> _attendees(CalendarEvent e) {
    final out = <({String email, String? name, bool required, int response})>[];
    try {
      final raw = e.attendeesJson;
      if (raw == null || raw.isEmpty) return out;
      for (final a in (jsonDecode(raw) as List).whereType<Map>()) {
        final email = (a['email'] ?? '').toString().trim();
        if (email.isEmpty) continue;
        final name = (a['displayName'] ?? a['name'])?.toString();
        out.add((
          email: email,
          name: (name == null || name.isEmpty) ? null : name,
          required: a['isRequired'] != false,
          response: (a['response'] as num?)?.toInt() ?? 0,
        ));
      }
    } catch (_) {}
    return out;
  }

  static String _plain(String s) {
    if (!s.contains('<')) return s.trim();
    return s
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _recurrenceLabel(int r, AppLocalizations l10n) => switch (r) {
        1 => l10n.tr('recurDaily'),
        2 => l10n.tr('recurWeekly'),
        3 => l10n.tr('recurBiweekly'),
        4 => l10n.tr('recurMonthly'),
        5 => l10n.tr('recurYearly'),
        _ => l10n.tr('recurringSeries'),
      };

  static String _showAsLabel(int v, AppLocalizations l10n) => switch (v) {
        0 => l10n.tr('freeStatus'),
        1 => l10n.tr('tentativeStatus'),
        3 => l10n.tr('outOfOfficeStatus'),
        _ => l10n.tr('busyStatus'),
      };

  static Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<void> _openMap(String place) async {
    // geo: открывает любое приложение карт; нет такого — Яндекс Карты в браузере.
    final geo = Uri.parse('geo:0,0?q=${Uri.encodeComponent(place)}');
    try {
      if (await launchUrl(geo, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await launchUrl(Uri.parse('https://yandex.ru/maps/?text=${Uri.encodeComponent(place)}'),
        mode: LaunchMode.externalApplication);
  }

  static void _copy(BuildContext context, AppLocalizations l10n, String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    showInlineNotice(l10n.tr('copied'), duration: const Duration(seconds: 2));
  }
}

/// Ответы участников моего собрания (1.6.7): сводка «приняли / под вопросом /
/// отклонили / нет ответа», комментарии из писем-ответов и предложения
/// нового времени с кнопками «Принять время» и «Ответить».
class _RepliesSection extends StatelessWidget {
  final CalendarEvent event;
  final List<int> statuses;
  final List<MeetingReply> replies;
  final String Function(MeetingReply) nameOf;
  const _RepliesSection({required this.event, required this.statuses, required this.replies, required this.nameOf});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sum = MeetingReplySummary.of(statuses);
    final loc = l10n.localeCode;
    String range(DateTime a, DateTime b) {
      final s = a.toLocal(), e = b.toLocal();
      final same = s.year == e.year && s.month == e.month && s.day == e.day;
      return same
          ? '${DateFormat('EEE, d MMM', loc).format(s)}, ${DateFormat.Hm(loc).format(s)}–${DateFormat.Hm(loc).format(e)}'
          : '${DateFormat('d MMM, HH:mm', loc).format(s)} – ${DateFormat('d MMM, HH:mm', loc).format(e)}';
    }

    Widget chip(IconData icon, Color c, String label, int n) => Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: Radii.chipAll),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: c),
            const SizedBox(width: Space.xs),
            Text('$label: $n', style: theme.textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
          ]),
        );
    final shown = [for (final r in replies) if (r.comment.isNotEmpty || r.hasProposal) r];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('meetingReplies')),
        SettingsGroup(dividerIndent: Space.l, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
          child: Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            chip(AppIcons.check_circle, AppColors.successGreen, l10n.tr('repliesAccepted'), sum.accepted),
            chip(AppIcons.help, AppColors.accentOrange, l10n.tr('repliesTentative'), sum.tentative),
            chip(AppIcons.cancel, AppColors.errorRed, l10n.tr('repliesDeclined'), sum.declined),
            chip(AppIcons.schedule, theme.hintColor, l10n.tr('repliesNone'), sum.none),
          ]),
        ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(
                    switch (r.kind) { 1 => AppIcons.check_circle, 2 => AppIcons.help, _ => AppIcons.cancel },
                    size: 18,
                    color: switch (r.kind) { 1 => AppColors.successGreen, 2 => AppColors.accentOrange, _ => AppColors.errorRed },
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(nameOf(r), style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(DateFormat('d MMM, HH:mm', loc).format(r.at.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                ]),
                if (r.comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xl + Space.xs, top: Space.xs),
                    child: Text(r.comment, style: theme.textTheme.bodyMedium),
                  ),
                if (r.hasProposal) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xl + Space.xs, top: Space.xs),
                    child: Text(l10n.tr('proposesTime').replaceAll('{t}', range(r.proposedStart!, r.proposedEnd!)),
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: Space.xl, top: Space.xs),
                    child: Wrap(spacing: Space.s, children: [
                      FilledButton.tonal(
                        // Правка собрания с предложенным временем: организатор
                        // проверяет и сохраняет — участники получают обновление.
                        onPressed: () => context.push('/create-event', extra: {
                          'edit': event,
                          'start': r.proposedStart!.toLocal(),
                          'end': r.proposedEnd!.toLocal(),
                        }),
                        child: Text(l10n.tr('acceptProposedTime')),
                      ),
                      TextButton(
                        // Отказ — ответом участнику: время остаётся прежним.
                        onPressed: () => context.push(Uri(path: '/compose', queryParameters: {
                          'replyToId': r.emailId,
                          'accountId': event.accountId,
                          'quick': l10n.tr('proposalDeclinedText'),
                        }).toString()),
                        child: Text(l10n.tr('declineProposedTime')),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

/// «К встрече»: письма по теме встречи с её участниками за 30 дней и
/// вложения из них (MeetingPrep). Нет подходящих писем или функция
/// выключена в «Экспериментальных» — раздела нет.
class _PrepSection extends ConsumerWidget {
  final CalendarEvent event;
  const _PrepSection({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(meetingPrepProvider(event)).value;
    if (prep == null || prep.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final locale = l10n.localeCode;
    void open(PrepCandidate m) => context.push(mailOpenPath(context, m.id, accountId: m.accountId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('meetingPrepTitle'), help: l10n.tr('meetingPrepHelp')),
        SettingsGroup(children: [
        for (final m in prep.mails)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
            // Значок 24 + 16 — текст с линии остальных строк карточки.
            horizontalTitleGap: Space.l,
            leading: Icon(m.attachments.any((a) => !a.isInline) ? AppIcons.attach_file : AppIcons.mail,
                color: theme.colorScheme.onSurfaceVariant),
            title: Text(m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${m.fromName} · ${DateFormat('d MMM', locale).format(m.receivedAt.toLocal())}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            onTap: () => open(m),
          ),
        if (prep.files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final f in prep.files)
                  ActionChip(
                    avatar: Icon(AppIcons.description, size: 16, color: theme.colorScheme.primary),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(f.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    tooltip: f.mail.subject,
                    onPressed: () => open(f.mail),
                  ),
              ],
            ),
          ),
        ]),
      ],
    );
  }
}

/// Строка «значок — текст» в стиле карточки события Google Календаря.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? leadingColor;
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.leadingColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        // Сетка карточки (1.7.2+106 — как строки настроек): поле 16 ·
        // значок 24 · 16 · текст — с линии кнопки «Подключиться» и
        // разделителей карточки.
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: Sizes.icon, color: leadingColor ?? theme.hintColor),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.bodyLarge),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.s), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Участник: фото (из контактов и адресной книги), имя, роль; нажатие — написать.
class _Person extends StatelessWidget {
  final String email;
  final String? name;
  final String? role;
  final String? photo;
  final String? accountId;

  /// Ответ на приглашение (0 — нет данных, 1 — принял, 2 — под вопросом,
  /// 3 — отклонил): значок на фото.
  final int response;
  const _Person({required this.email, this.name, this.role, this.photo, this.accountId, this.response = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (name ?? '').isNotEmpty ? name! : email;
    final img = photoImage(photo);
    final initials = label.trim().isEmpty ? '?' : initialOf(label.trim());
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
      // Фото 36 + 12 — имя с линии остальных строк карточки (16 + 48).
      horizontalTitleGap: Space.m,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          // Цвет кружка — из общей палитры (раньше — любой цвет из хэша
          // адреса, бывал кислотным), с 1.8.0 светлый с буквой оттенком.
          Builder(builder: (context) {
            final tones = avatarTones(context, Color(avatarColorValue(email)));
            return PhotoRing(child: CircleAvatar(
              radius: 18,
              backgroundColor: tones.fill,
              foregroundImage: img,
              onForegroundImageError: img == null ? null : (_, __) {},
              child: Text(initials, style: TextStyle(color: tones.letter, fontWeight: FontWeight.w600)),
            ));
          }),
          if (response != 0)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
                padding: const EdgeInsets.all(1),
                child: Icon(
                  switch (response) {
                    1 => AppIcons.check_circle,
                    2 => AppIcons.help,
                    _ => AppIcons.cancel,
                  },
                  size: 16,
                  color: switch (response) {
                    1 => AppColors.successGreen,
                    2 => AppColors.accentOrange,
                    _ => theme.colorScheme.error,
                  },
                ),
              ),
            ),
        ],
      ),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        role == null ? ((name ?? '').isNotEmpty ? email : '') : '$role${(name ?? '').isNotEmpty ? ' · $email' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      onTap: () => context.push(Uri(path: '/compose', queryParameters: {
        'to': email,
        if (accountId != null) 'accountId': accountId!,
      }).toString()),
    );
  }
}

/// Напоминания встречи: показывает действующие (свои или по умолчанию) и
/// меняет их (1.7.2+110 — несколько, шторкой со списком). Заданные здесь —
/// настройка этого телефона (EventReminders.encodePhoneOnly): на сервер не
/// уходят, синхронизация их не стирает. Изменить напоминание на сервере —
/// «Изменить» встречу.
class _ReminderRow extends ConsumerWidget {
  final CalendarEvent event;
  const _ReminderRow({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snap) {
        final own = ReminderSchedulerService.remindersOf(event.remindersJson);
        final effective = EventReminders.normalize(
            snap.hasData ? ReminderSchedulerService.remindersFor(event, snap.data!) : (own ?? const <int>[]));
        final text = effective.isEmpty ? l10n.tr('noReminder') : effective.map((m) => reminderLabel(m, l10n)).join(', ');
        return _Row(
          icon: AppIcons.notifications,
          title: text,
          subtitle: own == null && effective.isNotEmpty ? l10n.tr('reminderDefaultHint') : null,
          onTap: () => _pick(context, ref, l10n, effective),
        );
      },
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, AppLocalizations l10n, List<int> current) async {
    final picked = await showRemindersSheet(context, initial: current, note: l10n.tr('remindersPhoneNote'));
    if (picked == null) return;
    final db = ref.read(databaseProvider);
    // Пустой список — явно «без напоминаний» на этом телефоне (не путать с
    // «не задано», при котором действует напоминание по умолчанию).
    final json = EventReminders.encodePhoneOnly(picked);
    await (db.update(db.calendarEvents)
          ..where((x) => x.id.equals(event.id) & x.accountId.equals(event.accountId)))
        .write(CalendarEventsCompanion(remindersJson: Value(json)));
    await ref.read(reminderSchedulerProvider).rescheduleAll();
  }
}

/// «Ваш ответ» на чужую встречу (1.6.34). Как в письме-приглашении:
/// «Отправить ответ сейчас», «Изменить ответ перед отправкой» (комментарий),
/// «Не отправлять ответ» и для «Под вопросом» / «Отклонить» — «Предложить
/// новое время». Отклонённая встреча убирается из календаря.
class _MyResponse extends ConsumerStatefulWidget {
  final CalendarEvent event;
  final AccountModel account;
  /// Ответ, известный серверу (участник «я» в списке): 1 — принял,
  /// 2 — под вопросом, 3 — отклонил, 0 — нет.
  final int serverStatus;
  const _MyResponse({required this.event, required this.account, required this.serverStatus});

  @override
  ConsumerState<_MyResponse> createState() => _MyResponseState();
}

class _MyResponseState extends ConsumerState<_MyResponse> {
  bool _busy = false;
  String? _error;
  String? _local; // ответ, данный здесь (до синхронизации)
  String? _note;

  String get _prefsKey => 'evt_resp:${widget.account.id}:${MailEngineService.isOccurrenceId(widget.event.id) ? widget.event.id.substring(0, widget.event.id.indexOf('#')) : widget.event.id}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_prefsKey);
      if (v != null && mounted) setState(() => _local = v);
    });
  }

  String? get _current {
    if (_local != null) return _local;
    return switch (widget.serverStatus) { 1 => 'accept', 2 => 'tentative', 3 => 'decline', _ => null };
  }

  String _label(AppLocalizations l10n, String r) => switch (r) {
        'accept' => l10n.tr('accept'),
        'tentative' => l10n.tr('meetingTentative'),
        _ => l10n.tr('decline'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cur = _current;
    final series = MailEngineService.isOccurrenceId(widget.event.id) || widget.event.recurrence != 0;
    Widget btn(IconData icon, String r, Color color) {
      final on = cur == r;
      final style = on
          ? FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white)
          : OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color));
      final child = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(_label(l10n, r), overflow: TextOverflow.ellipsis)),
      ]);
      return on
          ? FilledButton(style: style, onPressed: _busy ? null : () => _choose(r), child: child)
          : OutlinedButton(style: style, onPressed: _busy ? null : () => _choose(r), child: child);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + Sizes.icon + Space.l, Space.m, Space.l, Space.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          cur == null
              ? l10n.tr('yourResponseNone')
              : l10n.tr(switch (cur) { 'accept' => 'youAccepted', 'tentative' => 'youTentative', _ => 'youDeclined' }),
          style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600, color: cur == null ? AppColors.accentOrange : null),
        ),
        if (series)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(l10n.tr('responseWholeSeries'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        const SizedBox(height: Space.s),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.xs),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
            btn(AppIcons.check, 'accept', AppColors.successGreen),
            btn(AppIcons.help, 'tentative', AppColors.accentOrange),
            btn(AppIcons.close, 'decline', AppColors.errorRed),
          ]),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(_note!, style: theme.textTheme.bodySmall),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.errorText(context))),
          ),
      ]),
    );
  }

  Future<void> _choose(String response) async {
    final l10n = AppLocalizations.of(context);
    // Карточкой (1.8.8), как меню «⋮»; какой ответ — заголовком.
    final choice = await showActionSheet<String>(
      context,
      title: _label(l10n, response),
      items: [
        ActionSheetItem(icon: AppIcons.send, label: l10n.tr('meetingRespondSendNow'), value: 'now'),
        ActionSheetItem(icon: AppIcons.edit, label: l10n.tr('meetingRespondEdit'), value: 'edit'),
        ActionSheetItem(icon: AppIcons.event_available, label: l10n.tr('meetingRespondDontSend'), value: 'none'),
        if (response != 'accept')
          ActionSheetItem(icon: AppIcons.schedule, label: l10n.tr('meetingProposeTime'), value: 'propose'),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'now':
        await _respond(response);
      case 'none':
        await _respond(response, send: false);
      case 'edit':
        final c = await _askComment(response);
        if (c != null) await _respond(response, comment: c);
      case 'propose':
        final t = await _pickTime();
        if (t == null || !mounted) return;
        final c = await _askComment(response);
        if (c == null || !mounted) return;
        final loc = l10n.localeCode;
        final when = '${DateFormat.yMMMMEEEEd(loc).format(t.start)}, '
            '${DateFormat.Hm(loc).format(t.start)}–${DateFormat.Hm(loc).format(t.end)}';
        final line = l10n.tr('meetingProposedText').replaceAll('{t}', when);
        await _respond(response,
            comment: c.trim().isEmpty ? line : '${c.trim()}\n\n$line', proposedStart: t.start, proposedEnd: t.end);
    }
  }

  Future<String?> _askComment(String response) async {
    final l10n = AppLocalizations.of(context);
    final res = await showMessageSheet(
      context,
      title: _label(l10n, response),
      subtitle: widget.event.title.trim().isEmpty ? null : widget.event.title.trim(),
      icon: switch (response) { 'accept' => AppIcons.check, 'tentative' => AppIcons.help, _ => AppIcons.close },
      iconColor: switch (response) {
        'accept' => AppColors.successGreen,
        'tentative' => AppColors.accentOrange,
        _ => AppColors.errorRed,
      },
      hint: l10n.tr('meetingCommentHint'),
      actionLabel: l10n.tr('send'),
    );
    return res?.text;
  }

  /// Новое время: день, начало и конец (по умолчанию — длительность встречи).
  Future<({DateTime start, DateTime end})?> _pickTime() async {
    final now = DateTime.now();
    final ms = widget.event.startTime.toLocal();
    final length = widget.event.endTime.difference(widget.event.startTime);
    final day = await showDatePicker(
      context: context,
      initialDate: ms.isBefore(now) ? now : ms,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (day == null || !mounted) return null;
    final st = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(ms));
    if (st == null || !mounted) return null;
    final start = DateTime(day.year, day.month, day.day, st.hour, st.minute);
    final suggested = start.add(length.isNegative || length == Duration.zero ? const Duration(hours: 1) : length);
    final et = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(suggested));
    if (et == null) return null;
    var end = DateTime(suggested.year, suggested.month, suggested.day, et.hour, et.minute);
    if (!end.isAfter(start)) end = DateTime(day.year, day.month, day.day, et.hour, et.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start: start, end: end);
  }

  Future<void> _respond(String response,
      {bool send = true, String? comment, DateTime? proposedStart, DateTime? proposedEnd}) async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.maybeOf(context);
    final e = widget.event;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final engine = ref.read(mailEngineServiceProvider);
      final text = (comment ?? '').trim();
      final r = await engine.respondToEvent(widget.account, e.id,
          response: response,
          send: send,
          comment: text.isEmpty ? null : text,
          proposedStart: proposedStart,
          proposedEnd: proposedEnd);
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _error = l10n.tr('couldNotSendResponse'));
        return;
      }
      final db = ref.read(databaseProvider);
      // Письмо-приглашение — из «Ждут ответа» сразу.
      await markInvitesForEvent(db, accountId: e.accountId, title: e.title, start: e.startTime);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, response);
      final master = MailEngineService.isOccurrenceId(e.id) ? e.id.substring(0, e.id.indexOf('#')) : e.id;
      if (response == 'decline') {
        // Отклонённая встреча из календаря уходит (как в Outlook).
        try {
          await engine.deleteEventServer(widget.account, master);
        } catch (_) {}
        await (db.delete(db.calendarEvents)
              ..where((x) => x.accountId.equals(e.accountId) & (x.id.equals(master) | x.id.like('$master#%'))))
            .go();
        try {
          await ref.read(reminderSchedulerProvider).rescheduleAll();
        } catch (_) {}
        showInlineNotice(l10n.tr(r.sent ? 'meetingDeclinedSent' : 'meetingDeclinedLocal'));
        if (router != null && router.canPop()) router.pop();
        return;
      }
      // Принято — «занят», под вопросом — «под вопросом»: сразу, до синка.
      await (db.update(db.calendarEvents)
            ..where((x) => x.accountId.equals(e.accountId) & (x.id.equals(master) | x.id.like('$master#%'))))
          .write(CalendarEventsCompanion(showAs: Value(response == 'accept' ? 2 : 1)));
      if (!mounted) return;
      setState(() {
        _local = response;
        _note = !r.sent
            ? l10n.tr('meetingNotSent')
            : (proposedStart != null && r.proposed ? l10n.tr('meetingProposalSent') : null);
      });
    } catch (err) {
      if (mounted) setState(() => _error = '${l10n.tr('couldNotSendResponse')}: $err');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// lib/features/mail/widgets/meeting_invite_banner.dart
// Баннер приглашения на встречу: «Принять / Под вопросом / Отклонить».
// Показывается, когда письмо похоже на приглашение И транспорт поддерживает
// ответ (EWS). Ответ уходит организатору, событие появляется в календаре
// сервера (подтянется синхронизацией). Определение — эвристика по данным письма.
//
// Как в Outlook (1.5.12): после выбора ответа — «Отправить ответ сейчас»,
// «Изменить ответ перед отправкой» (комментарий организатору), «Не
// отправлять ответ», а для «Под вопросом» и «Отклонить» — «Предложить новое
// время». Раньше ответ уходил сразу и всегда, без текста и без вариантов.

import 'dart:convert' show HtmlEscape;
import '../../../core/theme/app_icons.dart';

import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/common/message_sheet.dart' show showMessageSheet;
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/calendar/meeting_link_service.dart';
import '../../../services/calendar/pending_invites.dart' show markInviteAnswered;
import 'package:url_launcher/url_launcher.dart';
import '../../../services/calendar/imip_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/transport_capabilities.dart';
import '../../../services/mail/own_addresses.dart';
import '../providers/mail_providers.dart' show emailsProvider;
import '../../../data/database/app_database.dart' show CalendarEvent;
import '../../../data/providers/database_provider.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../widgets/common/inline_notice.dart' show showInlineError;

class MeetingInviteBanner extends ConsumerStatefulWidget {
  final AccountModel account;
  final EmailModel email;
  const MeetingInviteBanner({super.key, required this.account, required this.email});

  /// Похоже ли письмо на приглашение на встречу (эвристика).
  static bool isMeetingInvite(EmailModel email) {
    // ActiveSync сообщает о приглашении явно (Email:MeetingRequest).
    if (email.meeting != null) return true;
    for (final a in email.attachments) {
      final mime = a.mimeType.toLowerCase();
      final name = a.name.toLowerCase();
      if (mime.contains('calendar') || name.endsWith('.ics') || name.endsWith('.vcs')) return true;
    }
    final subject = email.subject.toLowerCase();
    // Оригинальный текст нужен для извлечения ссылки: в URL встреч (Teams,
    // Телемост) токены чувствительны к регистру — из lowercase-версии ссылка
    // получилась бы нерабочей.
    final bodyRaw = email.bodyPlain ?? email.bodyHtml ?? '';
    final body = bodyRaw.toLowerCase();
    const cues = ['приглашение на встречу', 'приглашение:', 'meeting invitation', 'invitation:'];
    if (cues.any(subject.contains)) return true;
    final hasWhen = body.contains('when:') || body.contains('когда:');
    final hasWhere = body.contains('where:') || body.contains('location:') || body.contains('место:');
    return hasWhen && hasWhere;
  }

  @override
  ConsumerState<MeetingInviteBanner> createState() => _MeetingInviteBannerState();
}

class _MeetingInviteBannerState extends ConsumerState<MeetingInviteBanner> {
  bool _busy = false;
  String? _responded;
  /// Пояснение к ответу: «не отправлялся», «предложено новое время».
  String? _note;
  /// Ошибка ответа — прямо в карточке: всплывающие сообщения отключены.
  String? _error;
  /// Приглашение из письма (iMIP) у ящиков не-Exchange: Gmail, Яндекс…
  Future<ImipInvite?>? _invite;

  bool get _imip => ImipService.supports(widget.account) && widget.email.meeting == null;

  @override
  void initState() {
    super.initState();
    // Вложение .ics читается у любого ящика (09.10.2026): у Exchange тоже
    // приходят события из внешних сервисов (билеты, вебинары, бронирования),
    // их можно добавить в свой календарь. Отвечать по почте (iMIP) — только
    // не-Exchange: у Exchange свои команды ответа.
    if (widget.email.meeting == null && ImipService.hasInvite(widget.email)) {
      _invite = ref.read(imipServiceProvider).load(widget.account, widget.email);
    }
  }

  /// Данные встречи из приглашения — в том же виде, что у Exchange.
  static EmailMeeting _meetingOf(ImipInvite i) => EmailMeeting(
        start: i.event.start,
        end: i.event.end,
        allDay: i.event.isAllDay,
        location: i.event.location,
        organizer: i.event.organizerEmail,
        responseRequested: i.isRequest,
        messageClass: i.isCancel ? 'IPM.Schedule.Meeting.Canceled' : 'IPM.Schedule.Meeting.Request',
      );

  @override
  Widget build(BuildContext context) {
    if (!MeetingInviteBanner.isMeetingInvite(widget.email)) return const SizedBox.shrink();
    final f = _invite;
    if (f == null) return _card(context, null);
    return FutureBuilder<ImipInvite?>(
      future: f,
      builder: (context, snap) => _card(context, snap.data),
    );
  }

  Widget _card(BuildContext context, ImipInvite? invite) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final meeting = widget.email.meeting ?? (invite == null ? null : _meetingOf(invite));
    // Ответ участника на моё собрание (1.6.7): что ответил и, если предложил
    // другое время, — «Принять время» / «Отклонить».
    if (meeting != null && meeting.responseKind != 0) {
      return _ReplyCard(account: widget.account, email: widget.email, meeting: meeting);
    }
    // Приглашение по почте (iMIP): отвечаем, если это запрос и организатор — не мы.
    // Своё приглашение (я организатор или отправитель — письмо из
    // «Отправленных» или «Всей почты») — отвечать на него нечего: раньше
    // кнопки «Принять/Отклонить» были и в своих встречах, и сервер отвечал
    // ошибкой. «Я» — любой адрес ящика, а не только адрес входа.
    final orgMatch = RegExp(r'[\w.+-]+@[\w.-]+').firstMatch(meeting?.organizer ?? '')?.group(0);
    final mine = OwnAddresses.isMine(widget.account, widget.email.from.email) ||
        OwnAddresses.isMine(widget.account, orgMatch) ||
        OwnAddresses.isMine(widget.account, invite?.event.organizerEmail);
    final imipCanRespond = _imip && invite != null && invite.isRequest && !mine;
    // Время и место показываем всегда (у приглашений ActiveSync тело часто
    // пустое), кнопки ответа — если транспорт умеет отвечать.
    // ActiveSync помечает приглашение явно (MeetingRequest) — без этой метки
    // отвечать не на что: эвристика срабатывала на ответах «RE:» с текстом
    // исходной встречи («When:/Where:»), и сервер отклонял MeetingResponse
    // («Не удалось отправить ответ», 05.10). Для остальных — эвристика, но
    // не на ответах и пересылках.
    final isReplyOrForward = RegExp(r'^\s*(re|fw|fwd|ответ|пересл)\s*:', caseSensitive: false)
        .hasMatch(widget.email.subject);
    final canRespond = imipCanRespond ||
        (!_imip &&
            !mine &&
            // .ics во вложении у Exchange — не приглашение сервера: отвечать
            // нечем, только «В календарь».
            invite == null &&
            TransportCapabilities.forAccount(widget.account).meetingResponse &&
            (meeting != null
                ? meeting.isRequest
                : !widget.account.usesEas && !isReplyOrForward));
    if (meeting == null && !canRespond) return const SizedBox.shrink();

    const color = AppColors.infoBlue;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.event_available, size: 18, color: color),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(l10n.tr(invite != null && !invite.isRequest && !invite.isCancel ? 'icsEvent' : 'meetingInvitation'),
                    style: const TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          if (meeting != null) ..._meetingDetails(context, meeting),
          // Событие из файла .ics, на которое не отвечают (рассылка события,
          // билет, вебинар; или ящик Exchange) — «В календарь»: встреча
          // откроется заполненной, сохраняет пользователь.
          if (invite != null && !imipCanRespond && !invite.isCancel && invite.event.start != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: OutlinedButton.icon(
                icon: const Icon(AppIcons.event, size: 18),
                label: Text(l10n.tr('addToCalendar')),
                onPressed: () => context.push('/create-event', extra: {
                  'start': invite.event.start!.toLocal(),
                  'end': (invite.event.end ?? invite.event.start!.add(const Duration(hours: 1))).toLocal(),
                  'location': invite.event.location,
                  'title': (invite.event.summary ?? '').trim().isEmpty ? widget.email.subject : invite.event.summary,
                  'description': invite.event.description,
                }),
              ),
            ),
          // Ссылка на онлайн-встречу: организаторы кладут её в «место
          // проведения» или в тело приглашения вперемешку с текстом. Раньше
          // пользователь искал её глазами и копировал вручную.
          Builder(builder: (ctx) {
            final link = MeetingLinkService.find(
                description: widget.email.bodyPlain ?? widget.email.bodyHtml ?? '');
            if (link == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: Space.s),
              child: FilledButton.icon(
                icon: const Icon(AppIcons.videocam, size: 18),
                label: Text('${l10n.tr('joinMeeting')} · ${link.platform}'),
                onPressed: () async {
                  final uri = Uri.tryParse(link.url);
                  if (uri == null) return;
                  try {
                    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (!ok) {
                      showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', link.url));
                    }
                  } catch (_) {
                    showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', link.url));
                  }
                },
              ),
            );
          }),
          if (!canRespond)
            const SizedBox.shrink()
          else if (_responded != null) ...[
            Text(_respondedText(ru),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.successText(context))),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_note!, style: Theme.of(context).textTheme.bodySmall),
              ),
          ]
          else if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Space.xs),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _btn(AppIcons.check, l10n.tr('accept'), 'accept', AppColors.successGreen, meeting, invite),
                _btn(AppIcons.help, l10n.tr('meetingTentative'), 'tentative', AppColors.accentOrange, meeting, invite),
                _btn(AppIcons.close, l10n.tr('decline'), 'decline', AppColors.errorRed, meeting, invite),
              ],
            ),
          if (_error != null && _responded == null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.errorText(context))),
            ),
        ],
      ),
    );
  }

  List<Widget> _meetingDetails(BuildContext context, EmailMeeting m) {
    final l10n = AppLocalizations.of(context);
    final loc = Localizations.localeOf(context).toString();
    String when() {
      final s = m.start;
      if (s == null) return '';
      final day = DateFormat.yMMMMEEEEd(loc).format(s);
      if (m.allDay) return '$day · ${l10n.tr('allDay')}';
      final t = DateFormat.Hm(loc);
      final e = m.end;
      return e == null ? '$day, ${t.format(s)}' : '$day, ${t.format(s)}–${t.format(e)}';
    }

    final style = Theme.of(context).textTheme.bodyMedium;
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: Space.s),
            Expanded(child: Text(text, style: style)),
          ]),
        );
    return [
      if (m.isCanceled) line(AppIcons.event_busy, l10n.tr('meetingCanceled')),
      if (m.start != null) line(AppIcons.schedule, when()),
      if (m.location != null) line(AppIcons.place, m.location!),
      if (m.organizer != null) line(AppIcons.person, m.organizer!),
    ];
  }

  String _respondedText(bool ru) {
    final l10n = AppLocalizations.of(context);
    switch (_responded) {
      case 'accept': return l10n.tr('youAccepted');
      case 'tentative': return l10n.tr('youTentative');
      default: return l10n.tr('youDeclined');
    }
  }

  Widget _btn(IconData icon, String label, String response, Color color, EmailMeeting? meeting, ImipInvite? invite) =>
      OutlinedButton.icon(
        onPressed: () => _choose(response, meeting, invite),
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
        icon: Icon(icon, size: 16),
        label: Text(label),
      );

  /// Варианты ответа, как в Outlook.
  Future<void> _choose(String response, EmailMeeting? meeting, ImipInvite? invite) async {
    final l10n = AppLocalizations.of(context);
    // Предложить время письмом (iMIP) не умеем — только Exchange.
    final canPropose = response != 'accept' && invite == null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Какой ответ выбран — заголовком (1.6.5: лист был без подписи).
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_responseLabel(l10n, response), style: Theme.of(ctx).textTheme.titleMedium),
              ),
            ),
            ListTile(
              leading: const Icon(AppIcons.send),
              title: Text(l10n.tr('meetingRespondSendNow')),
              onTap: () => Navigator.pop(ctx, 'now'),
            ),
            ListTile(
              leading: const Icon(AppIcons.edit),
              title: Text(l10n.tr('meetingRespondEdit')),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(AppIcons.event_available),
              title: Text(l10n.tr('meetingRespondDontSend')),
              onTap: () => Navigator.pop(ctx, 'none'),
            ),
            if (canPropose)
              ListTile(
                leading: const Icon(AppIcons.schedule),
                title: Text(l10n.tr('meetingProposeTime')),
                onTap: () => Navigator.pop(ctx, 'propose'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'now':
        await _respond(response);
      case 'none':
        await _respond(response, send: false);
      case 'edit':
        final comment = await _askComment(response);
        if (comment != null) await _respond(response, comment: comment);
      case 'propose':
        final t = await _pickTime(meeting);
        if (t == null || !mounted) return;
        final c = await _askComment(response);
        if (c == null || !mounted) return;
        // Время — и текстом: его увидит организатор, даже если сервер не
        // умеет передавать предложение полем встречи (Exchange 2010,
        // ActiveSync до 16.0).
        final line = l10n.tr('meetingProposedText').replaceAll('{t}', _fmtRange(t.start, t.end));
        await _respond(response,
            comment: c.trim().isEmpty ? line : '${c.trim()}\n\n$line', proposedStart: t.start, proposedEnd: t.end);
    }
  }

  String _fmtRange(DateTime s, DateTime e) {
    final loc = AppLocalizations.of(context).localeCode;
    final day = DateFormat.yMMMMEEEEd(loc).format(s);
    final t = DateFormat.Hm(loc);
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    return sameDay
        ? '$day, ${t.format(s)}–${t.format(e)}'
        : '$day, ${t.format(s)} – ${DateFormat.yMMMMEEEEd(loc).format(e)}, ${t.format(e)}';
  }

  String _responseLabel(AppLocalizations l10n, String response) => switch (response) {
        'accept' => l10n.tr('accept'),
        'tentative' => l10n.tr('meetingTentative'),
        _ => l10n.tr('decline'),
      };

  /// Комментарий организатору. null — отмена. Контроллер не освобождаем
  /// сразу: поле ещё видно, пока диалог закрывается.
  ///
  /// 1.6.5 (замечание 13.10.2026: «окно ответа очень странное»): был только
  /// серый прямоугольник поля без заголовка — непонятно, что это за окно и
  /// какой ответ уйдёт. Теперь заголовок — ответ, поле с рамкой и подписью.
  Future<String?> _askComment(String response) async {
    // Шторка в стиле приложения (1.6.38) вместо системного окна с полем в рамке.
    final l10n = AppLocalizations.of(context);
    final res = await showMessageSheet(
      context,
      title: _responseLabel(l10n, response),
      subtitle: widget.email.subject.trim().isEmpty ? null : widget.email.subject.trim(),
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
  Future<({DateTime start, DateTime end})?> _pickTime(EmailMeeting? meeting) async {
    final now = DateTime.now();
    final ms = meeting?.start;
    final me = meeting?.end;
    final from = ms ?? DateTime(now.year, now.month, now.day, now.hour + 1);
    final length = (ms != null && me != null) ? me.difference(ms) : const Duration(hours: 1);
    final day = await showDatePicker(
      context: context,
      initialDate: from.isBefore(now) ? now : from,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (day == null || !mounted) return null;
    final st = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(from));
    if (st == null || !mounted) return null;
    final start = DateTime(day.year, day.month, day.day, st.hour, st.minute);
    final suggestedEnd = start.add(length.isNegative || length == Duration.zero ? const Duration(hours: 1) : length);
    final et = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(suggestedEnd));
    if (et == null) return null;
    var end = DateTime(suggestedEnd.year, suggestedEnd.month, suggestedEnd.day, et.hour, et.minute);
    if (!end.isAfter(start)) end = DateTime(day.year, day.month, day.day, et.hour, et.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return (start: start, end: end);
  }

  Future<void> _respond(String response,
      {bool send = true, String? comment, DateTime? proposedStart, DateTime? proposedEnd}) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invite = _invite == null ? null : await _invite;
      final kind = switch (response) { 'accept' => 'Accept', 'tentative' => 'Tentative', _ => 'Decline' };
      final title = invite?.event.summary ?? widget.email.subject;
      final text = (comment ?? '').trim();
      final defaultBody = l10n.tr('imipBody$kind').replaceAll('{s}', title);
      final bool ok;
      var sent = send;
      var proposed = false;
      if (invite != null) {
        const esc = HtmlEscape();
        final body = text.isEmpty ? defaultBody : text;
        await ref.read(imipServiceProvider).respond(widget.account, widget.email, invite, response,
            subject: l10n.tr('imipSubj$kind').replaceAll('{s}', title),
            bodyHtml: '<p>${esc.convert(body).replaceAll('\n', '<br>')}</p>',
            send: send);
        ok = true;
      } else {
        final propose = proposedStart != null && proposedEnd != null;
        final r = await ref.read(mailEngineServiceProvider).respondToMeeting(
              widget.account,
              itemId: widget.email.id,
              response: response,
              folderId: widget.email.folderId,
              send: send,
              comment: text.isEmpty ? null : text,
              proposedStart: proposedStart,
              proposedEnd: proposedEnd,
              meeting: widget.email.meeting,
              title: title,
              mailSubject: l10n.tr(propose ? 'imipSubjPropose' : 'imipSubj$kind').replaceAll('{s}', title),
              mailBody: defaultBody,
            );
        ok = r.ok;
        sent = r.sent;
        // Время ушло полем встречи или хотя бы текстом ответа.
        proposed = propose && r.sent;
      }
      if (!mounted) return;
      if (ok) {
        setState(() {
          _responded = response;
          _note = !sent
              ? l10n.tr('meetingNotSent')
              : proposed
                  ? l10n.tr('meetingProposalSent')
                  : null;
        });
        // Из «Ждут ответа» в календаре и «Моём дне» — сразу (1.6.33).
        await markInviteAnswered(ref.read(databaseProvider),
            accountId: widget.email.accountId, emailId: widget.email.id);
        await ref.read(emailsProvider.notifier).refresh();
      } else {
        setState(() => _error = l10n.tr('couldNotSendResponse'));
        showInlineError(l10n.tr('couldNotSendResponse'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '${l10n.tr('couldNotSendResponse')}: $e');
        showInlineError('${l10n.error}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Письмо-ответ участника на собрание (1.6.7).
class _ReplyCard extends ConsumerWidget {
  final AccountModel account;
  final EmailModel email;
  final EmailMeeting meeting;
  const _ReplyCard({required this.account, required this.email, required this.meeting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final loc = l10n.localeCode;
    final kind = meeting.responseKind;
    final color = switch (kind) { 1 => AppColors.successGreen, 2 => AppColors.accentOrange, _ => AppColors.errorRed };
    final label = l10n.tr(switch (kind) { 1 => 'meetingReplyAccepted', 2 => 'meetingReplyTentative', _ => 'meetingReplyDeclined' });
    String range(DateTime a, DateTime b) {
      final s = a.toLocal(), e = b.toLocal();
      return '${DateFormat('EEE, d MMM', loc).format(s)}, ${DateFormat.Hm(loc).format(s)}–${DateFormat.Hm(loc).format(e)}';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(switch (kind) { 1 => AppIcons.check_circle, 2 => AppIcons.help, _ => AppIcons.cancel }, color: color, size: 20),
            const SizedBox(width: Space.s),
            Expanded(child: Text(label, style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700))),
          ]),
          if (meeting.start != null && meeting.end != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('${l10n.tr('meetingWhen')}: ${range(meeting.start!, meeting.end!)}', style: theme.textTheme.bodyMedium),
            ),
          if (meeting.hasProposal) ...[
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(l10n.tr('proposesTime').replaceAll('{t}', range(meeting.proposedStart!, meeting.proposedEnd!)),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: Space.s),
            Wrap(spacing: Space.s, children: [
              FilledButton.tonal(
                onPressed: () async {
                  final ev = await _findEvent(ref);
                  if (!context.mounted) return;
                  if (ev == null) {
                    await showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: Text(l10n.tr('meetingNotInCalendar')),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.ok))],
                      ),
                    );
                    return;
                  }
                  await context.push('/create-event', extra: {
                    'edit': ev,
                    'start': meeting.proposedStart!.toLocal(),
                    'end': meeting.proposedEnd!.toLocal(),
                  });
                },
                child: Text(l10n.tr('acceptProposedTime')),
              ),
              TextButton(
                onPressed: () => context.push(Uri(path: '/compose', queryParameters: {
                  'replyToId': email.id,
                  'accountId': account.id,
                  'quick': l10n.tr('proposalDeclinedText'),
                }).toString()),
                child: Text(l10n.tr('declineProposedTime')),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  /// Встреча в моём календаре, на которую пришёл ответ: то же начало.
  Future<CalendarEvent?> _findEvent(WidgetRef ref) async {
    final start = meeting.start;
    if (start == null) return null;
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.calendarEvents)
          ..where((e) =>
              e.accountId.equals(account.id) &
              e.startTime.isBetweenValues(start.subtract(const Duration(minutes: 1)), start.add(const Duration(minutes: 1)))))
        .get();
    if (rows.isEmpty) return null;
    final subj = email.subject.toLowerCase();
    return rows.where((r) => r.title.isNotEmpty && subj.contains(r.title.toLowerCase())).firstOrNull ?? rows.first;
  }
}

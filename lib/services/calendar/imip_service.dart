// lib/services/calendar/imip_service.dart
// Приглашения на встречу в обычной почте (iMIP, RFC 6047): Gmail, Яндекс,
// Mail.ru, Yahoo и любой IMAP-ящик. Exchange отвечает своими командами
// (MeetingResponse / AcceptItem) — здесь не используется.
//
// Ответ:
//  1. CalDAV-календарь ящика (Google, Яндекс, Mail.ru, Yahoo): событие уже
//     есть (Google сам добавляет приглашения) — меняется наш ответ, нет —
//     при «Принять»/«Под вопросом» добавляется из приглашения;
//  2. письмо организатору с METHOD:REPLY — его почта (Outlook, Google,
//     Яндекс) отмечает ответ у себя. Google, получивший ответ через свой
//     календарь, сообщает организатору сам — второе письмо не отправляется.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../mail/dav/dav_credentials.dart';
import '../mail/dav/dav_pim_service.dart';
import '../mail/dav/ical_parser.dart';
import '../mail/engine/mail_engine_service.dart';
import '../mail/oauth/oauth_proxy_client.dart';
import '../mail/transport/mail_transport.dart';

final imipServiceProvider = Provider<ImipService>((ref) => ImipService(ref));

class ImipInvite {
  final String ics;
  final String method;
  final VEvent event;
  const ImipInvite(this.ics, this.method, this.event);

  bool get isRequest => method.isEmpty || method == 'REQUEST';
  bool get isCancel => method == 'CANCEL';
}

class ImipService {
  final Ref _ref;
  ImipService(this._ref);

  static final Map<String, ImipInvite?> _cache = {};

  /// Подходит ли ящик: не Exchange (у него свои команды ответа).
  static bool supports(AccountModel account) => !account.usesEas && !account.usesEws && !account.isExchange;

  static EmailAttachment? _calendarPart(EmailModel email) {
    for (final a in email.attachments) {
      final mime = a.mimeType.toLowerCase();
      final name = a.name.toLowerCase();
      if (mime.contains('calendar') || name.endsWith('.ics')) return a;
    }
    return null;
  }

  static bool hasInvite(EmailModel email) => _calendarPart(email) != null;

  /// Приглашение из письма (часть text/calendar или вложение .ics).
  Future<ImipInvite?> load(AccountModel account, EmailModel email) async {
    final key = '${account.id}|${email.id}';
    if (_cache.containsKey(key)) return _cache[key];
    final part = _calendarPart(email);
    if (part == null) return null;
    try {
      final bytes = await _ref
          .read(mailEngineServiceProvider)
          .getAttachmentBytes(account, part.id, emailId: email.id);
      final text = utf8.decode(bytes, allowMalformed: true);
      final p = ICalITip.parse(text);
      final invite = p == null ? null : ImipInvite(text, p.method, p.event);
      _cache[key] = invite;
      return invite;
    } catch (e) {
      AppLogger.warning('Приглашение в письме не прочитано: $e');
      return null;
    }
  }

  static String partstatOf(String response) => switch (response) {
        'accept' => 'ACCEPTED',
        'tentative' => 'TENTATIVE',
        _ => 'DECLINED',
      };

  /// Ответить на приглашение. [subject] и [bodyHtml] — текст письма
  /// организатору на языке приложения. [send] = false — «Не отправлять
  /// ответ» (как в Outlook): меняется только календарь.
  Future<void> respond(AccountModel account, EmailModel email, ImipInvite invite, String response,
      {required String subject, required String bodyHtml, bool send = true}) async {
    final partstat = partstatOf(response);
    final name = account.displayName.isNotEmpty ? account.displayName : null;
    var calendarDone = false;
    if (DavPimService.isSupported(account)) {
      try {
        final storage = _ref.read(secureStorageProvider);
        final auth = await DavCredentials.authorization(account, storage, proxy: OAuthProxyClient(storage));
        if (auth != null) {
          calendarDone = await DavPimService().applyInvite(account, auth, invite.ics, partstat);
        }
      } catch (e) {
        AppLogger.warning('Приглашение: календарь не обновлён: $e');
      }
    }
    if (!send) {
      AppLogger.info('Приглашение: ответ ($partstat) без письма организатору');
      return;
    }
    if (calendarDone && DavPimService.providerOf(account) == 'google') {
      AppLogger.info('Приглашение: ответ записан в календарь Google (организатору сообщит Google)');
      return;
    }
    final organizer = invite.event.organizerEmail;
    if (organizer == null || organizer.isEmpty) {
      if (calendarDone) return;
      throw Exception('В приглашении нет адреса организатора');
    }
    final reply = ICalITip.reply(invite.ics, email: account.email, name: name, partstat: partstat);
    await _ref.read(mailTransportFactoryProvider).forAccount(account).send(
      account,
      to: [EmailAddress(email: organizer)],
      subject: subject,
      bodyHtml: bodyHtml,
      inReplyTo: email.internetMessageId,
      attachments: [
        (name: 'invite.ics', contentType: 'text/calendar; method=REPLY; charset=UTF-8', bytes: Uint8List.fromList(utf8.encode(reply))),
      ],
    );
    AppLogger.info('Приглашение: ответ ($partstat) отправлен организатору');
  }
}

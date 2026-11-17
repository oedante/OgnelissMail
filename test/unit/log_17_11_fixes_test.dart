// Исправления по журналу владельца 17.11.2026 (2.6.3): какие разрешения
// выдал Google, почему People API отказал, заголовок DMARC в журнале,
// календарь Google без повтора «все события за все годы» на тайм-аут.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/contacts/google_people_photos.dart';
import 'package:ogneliss/services/mail/dav/dav_client.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';
import 'package:ogneliss/widgets/common/bimi_avatar.dart';

void main() {
  test('вход Google: в журнале — какие разрешения не выданы', () {
    const req = [
      'openid', 'email', 'profile', 'https://mail.google.com/',
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/contacts.readonly',
    ];
    expect(
        DirectOAuth.grantedNote(req,
            'openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile '
            'https://mail.google.com/ https://www.googleapis.com/auth/calendar'),
        ' — не выданы: contacts.readonly');
    expect(
        DirectOAuth.grantedNote(req,
            'openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile '
            'https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/contacts.readonly'),
        ' — выданы все разрешения');
    expect(DirectOAuth.grantedNote(req, null), '');
  });

  test('People API: «не включён в проекте» отличается от «нет разрешения»', () {
    expect(
        GooglePeoplePhotos.isApiDisabled('{"error":{"code":403,"message":"People API has not been used in project 1 '
            'before or it is disabled.","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}'),
        isTrue);
    expect(
        GooglePeoplePhotos.isApiDisabled('{"error":{"code":403,"message":"Request had insufficient authentication '
            'scopes.","details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}'),
        isFalse);
  });

  test('заголовок Authentication-Results в журнале — без адресов и подписей', () {
    final s = BimiAvatar.maskAuthResults('mx.google.com;\r\n dkim=pass header.i=@email.example.com header.s=s1 '
        'header.b=AbCdEf123;\r\n spf=pass smtp.mailfrom="bounces+user=gmail.com@em1.example.com"; '
        'dmarc=pass header.from=example.com');
    expect(s, isNot(contains('user=gmail.com')));
    expect(s, isNot(contains('AbCdEf123')));
    expect(s, contains('***@em1.example.com'));
    expect(s, contains('dmarc=pass header.from=example.com'));
  });

  test('«Очистить корзину» IMAP: местный черновик — не команда серверу, письмо «папка:UID» — да', () {
    expect(MailEngineService.imapServerId('INBOX:123'), isTrue);
    expect(MailEngineService.imapServerId('[Gmail]/Корзина:7'), isTrue);
    expect(MailEngineService.imapServerId('draft-86064180-e999-48af-bf07-f8c5baf385a2'), isFalse);
    expect(MailEngineService.imapServerId('Trash:0'), isFalse);
  });

  group('календарь: запрос без диапазона дат', () {
    test('на тайм-аут — не повторяется (он ещё больше)', () async {
      var calls = 0;
      final c = MockClient((r) async {
        calls++;
        throw TimeoutException('slow');
      });
      final dav = DavClient('Bearer x', httpClient: c);
      final items = await dav.reportCalendarItems('https://dav.example/cal/',
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(items, isNull);
      expect(calls, 1);
      expect(dav.lastFailure, DavFailure.timeout);
    });

    test('сервер не принял диапазон (HTTP 400) — повтор без него', () async {
      final bodies = <String>[];
      final c = MockClient((r) async {
        bodies.add(r.body);
        if (r.body.contains('time-range')) return http.Response('bad', 400);
        return http.Response(
            '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/cal/1.ics</d:href>'
            '<d:propstat><d:prop><d:getetag>"1"</d:getetag><c:calendar-data>BEGIN:VCALENDAR\nEND:VCALENDAR</c:calendar-data>'
            '</d:prop></d:propstat></d:response></d:multistatus>',
            207);
      });
      final dav = DavClient('Bearer x', httpClient: c);
      final items = await dav.reportCalendarItems('https://dav.example/cal/',
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(bodies.length, 2);
      expect(items, hasLength(1));
      expect(dav.lastFailure, isNull);
    });
  });
}

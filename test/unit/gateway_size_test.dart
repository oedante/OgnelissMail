// test/unit/gateway_size_test.dart
// 1.7.2+114: письмо с вложениями, которое не пропустил шлюз перед Exchange
// (журнал владельца 25.10.2026: 403 со страницей шлюза на SendMail с фото,
// письмо без вложений через минуту ушло). Большой SendMail + 403 от шлюза —
// отдельная ошибка GatewaySizeRejected и без паузы на хост; разбор ошибок
// размера для отправки и очереди; текст для человека.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/offline_send_service.dart';

const _email = 'user@example.com';
const _server = 'gw-size.example.com';
const _device = 'TESTDEVICE0114';

AccountConfig _cfg() => const AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: _server,
      deviceId: _device,
      forceTransport: MailTransportKind.eas,
    );

String _session() => jsonEncode({
      'v': 1,
      'server': _server,
      'device': _device,
      'url': 'https://$_server/Microsoft-Server-ActiveSync',
      'host': _server,
      'proto': '14.1',
      'b64': false,
      'versions': ['14.1'],
      'cmds': ['Sync', 'FolderSync', 'Ping', 'SendMail'],
      'key': '1234567890',
      'at': DateTime.now().millisecondsSinceEpoch,
    });

const _gatewayPage = '<html><body>Forbidden Forbidden Datetime: 25/Oct/2026:07:41:47 +0000 IP: 192.0.2.1</body></html>';

void main() {
  setUp(() {
    EasEngine.saveSession = (_, __) {};
    EasEngine.loadSession = (email) => email == _email ? _session() : null;
  });

  tearDown(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  test('письмо с фото, 403 от шлюза — GatewaySizeRejected, хост не на паузе', () async {
    var sendBody = 0;
    final eng = EasEngine(httpClient: MockClient((req) async {
      if (req.url.toString().contains('SendMail')) {
        sendBody = req.bodyBytes.length;
        return http.Response(_gatewayPage, 403, headers: {'content-type': 'text/html'});
      }
      return http.Response('', 200);
    }));
    expect((await eng.connect(_cfg())).success, isTrue);
    final message = OutgoingMessage(
      to: const [MailAddress('colleague@example.com')],
      subject: 'Фото',
      bodyHtml: '<p>Фото во вложении</p>',
      attachments: [
        MailAttachment(id: 'p', name: 'IMG_0001.jpg', contentType: 'image/jpeg', bytes: Uint8List(400 * 1024)),
      ],
    );
    Object? error;
    try {
      await eng.send(message);
    } catch (e) {
      error = e;
    }
    expect(error, isA<GatewaySizeRejected>());
    expect((error as GatewaySizeRejected).bytes, greaterThan(400 * 1024), reason: 'размер письма (MIME, base64)');
    expect(sendBody, greaterThanOrEqualTo(EasEngine.bigBodyBytes));
    expect(EasEngine.wafPauseMinutesLeft(_server), 0, reason: 'отказ по размеру — не блокировка адреса');
  });

  test('ошибки размера: шлюз, лимит сервера, прочее', () {
    final g = OfflineSendService.tooLargeOf(const GatewaySizeRejected(5 * 1048576));
    expect(g, isNotNull);
    expect(g!.gateway, isTrue);
    expect(g.sizeBytes, 5 * 1048576);

    final s = OfflineSendService.tooLargeOf(Exception('Message size exceeds 25 MB'));
    expect(s?.gateway, isFalse);
    expect(s?.limitBytes, 25 * 1048576);

    // Обычный отказ и текст самой ошибки шлюза лимитом не считаются.
    expect(OfflineSendService.tooLargeOf(Exception('EAS SendMail: HTTP 403 (письмо не отправлено)')), isNull);
    expect(OfflineSendService.tooLargeOf(Exception(const GatewaySizeRejected(5 * 1048576).toString())), isNull);
  });

  test('текст для человека: размер письма и что сделать', () {
    final ru = AppLocalizations(const Locale('ru'));
    final gateway = OfflineSendService.tooLargeText(
        ru, const MessageTooLargeException(sizeBytes: 5 * 1048576 + 300 * 1024, gateway: true));
    expect(gateway, contains('5,3 МБ'));
    expect(gateway, contains('Сжать'));
    final server = OfflineSendService.tooLargeText(ru, const MessageTooLargeException(limitBytes: 10 * 1048576));
    expect(server, contains('10,0 МБ'));
    final en = OfflineSendService.tooLargeText(
        AppLocalizations(const Locale('en')), const MessageTooLargeException(sizeBytes: 3 * 1048576, gateway: true));
    expect(en, contains('3.0 MB'));
  });
}

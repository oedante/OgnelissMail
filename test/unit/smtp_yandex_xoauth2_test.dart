// Отправка с ящика Яндекса через OAuth (1.8.12, журнал владельца 30.10.2026
// 13:29): на «AUTH XOAUTH2» сервер отвечает голым «334», enough_mail падал
// на разборе (RangeError), вход висел до тайм-аута — письма не уходили.
// Сервер здесь — локальный, отвечает как smtp.yandex.ru.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show TolerantSmtpClient;

/// SMTP-сервер «как Яндекс»: голое «334» на AUTH XOAUTH2, затем 235.
Future<ServerSocket> _yandexLike(List<String> got) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) {
    s.write('220 smtp.yandex.ru ESMTP\r\n');
    var buf = '';
    s.listen((data) {
      buf += utf8.decode(data);
      while (buf.contains('\r\n')) {
        final i = buf.indexOf('\r\n');
        final line = buf.substring(0, i);
        buf = buf.substring(i + 2);
        got.add(line);
        if (line.startsWith('EHLO')) {
          s.write('250-smtp.yandex.ru\r\n250-8BITMIME\r\n250-AUTH LOGIN PLAIN XOAUTH2\r\n250 ENHANCEDSTATUSCODES\r\n');
        } else if (line == 'AUTH XOAUTH2') {
          s.write('334\r\n');
        } else if (line.startsWith('QUIT')) {
          s.write('221 2.0.0 Closing connection\r\n');
          s.destroy();
        } else if (got.length >= 2 && got[got.length - 2] == 'AUTH XOAUTH2') {
          final auth = utf8.decode(base64.decode(line));
          s.write(auth.contains('auth=Bearer token-1') ? '235 2.7.0 Accepted\r\n' : '535 5.7.8 Invalid\r\n');
        } else {
          s.write('502 5.5.2 Unknown\r\n');
        }
      }
    }, onError: (_) {});
  });
  return server;
}

void main() {
  test('голое «334» в ответе сервера — строка дополняется пробелом', () {
    expect(TolerantSmtpClient.normalize(['334', '334 abc', '250-SIZE', '']), ['334 ', '334 abc', '250-SIZE', '']);
  });

  test('вход XOAUTH2 на сервер «как Яндекс» проходит', () async {
    final got = <String>[];
    final server = await _yandexLike(got);
    addTearDown(server.close);
    final client = TolerantSmtpClient('test.local');
    await client.connectToServer('127.0.0.1', server.port, isSecure: false);
    await client.ehlo();
    final r = await client
        .authenticate('user@yandex.ru', 'token-1', AuthMechanism.xoauth2)
        .timeout(const Duration(seconds: 5));
    expect(r.code, 235);
    expect(got, contains('AUTH XOAUTH2'));
    await client.disconnect();
  });

  test('без исправления вход не завершается (то, что было в журнале)', () async {
    final got = <String>[];
    final server = await _yandexLike(got);
    addTearDown(server.close);
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final client = SmtpClient('test.local');
      await client.connectToServer('127.0.0.1', server.port, isSecure: false);
      await client.ehlo();
      await expectLater(
        client.authenticate('user@yandex.ru', 'token-1', AuthMechanism.xoauth2).timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()),
      );
      try {
        await client.disconnect();
      } catch (_) {}
    }, (e, _) => errors.add(e));
    expect(errors.whereType<RangeError>(), isNotEmpty);
  });
}

// test/unit/smtp_dsn_test.dart
// DSN при отправке (RFC 3461, 1.9.x, просьба владельца 31.10.2026): сервер
// объявил DSN — к MAIL FROM добавляются RET=HDRS ENVID, к RCPT TO — NOTIFY;
// не объявил — команды прежние. Сервер здесь — локальный.

import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show DsnRequest, TolerantSmtpClient;

/// SMTP-сервер: [dsn] — объявлять ли DSN в EHLO. Строки команд — в [got].
Future<ServerSocket> _server(List<String> got, {required bool dsn}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) {
    s.write('220 smtp.example.org ESMTP\r\n');
    var buf = '';
    var inData = false;
    s.listen((data) {
      buf += utf8.decode(data);
      while (buf.contains('\r\n')) {
        final i = buf.indexOf('\r\n');
        final line = buf.substring(0, i);
        buf = buf.substring(i + 2);
        if (inData) {
          if (line == '.') {
            inData = false;
            s.write('250 2.0.0 Ok: queued\r\n');
          }
          continue;
        }
        got.add(line);
        if (line.startsWith('EHLO')) {
          s.write('250-smtp.example.org\r\n250-8BITMIME\r\n${dsn ? '250-DSN\r\n' : ''}250 ENHANCEDSTATUSCODES\r\n');
        } else if (line.startsWith('MAIL FROM:') || line.startsWith('RCPT TO:')) {
          s.write('250 2.1.0 Ok\r\n');
        } else if (line == 'DATA') {
          inData = true;
          s.write('354 End data with <CR><LF>.<CR><LF>\r\n');
        } else if (line.startsWith('QUIT')) {
          s.write('221 2.0.0 Bye\r\n');
          s.destroy();
        } else {
          s.write('502 5.5.2 Unknown\r\n');
        }
      }
    }, onError: (_) {});
  });
  return server;
}

MimeMessage _message() {
  final b = MessageBuilder()
    ..from = [const MailAddress('Me', 'me@example.com')]
    ..to = [const MailAddress('', 'a@example.net'), const MailAddress('', 'b@example.net')]
    ..subject = 'Hello'
    ..text = 'MAIL FROM:<not-a-command@example.com>\r\nbody';
  return b.buildMimeMessage();
}

Future<List<String>> _send({required bool serverDsn, DsnRequest? dsn}) async {
  final got = <String>[];
  final server = await _server(got, dsn: serverDsn);
  final client = TolerantSmtpClient('test.local')..dsn = dsn;
  await client.connectToServer('127.0.0.1', server.port, isSecure: false);
  await client.ehlo();
  await client.sendMessage(_message()).timeout(const Duration(seconds: 5));
  expect(client.dsnUsed, serverDsn && dsn != null);
  expect(client.dataStarted, isTrue);
  await client.quit();
  await server.close();
  return got;
}

void main() {
  test('строки команд: параметры DSN, текст письма не меняется', () {
    const req = DsnRequest(envelopeId: 'abc+1=x@example.com');
    expect(TolerantSmtpClient.applyDsn('MAIL FROM:<me@example.com>', req),
        'MAIL FROM:<me@example.com> RET=HDRS ENVID=abc+2B1+3Dx@example.com');
    expect(TolerantSmtpClient.applyDsn('MAIL FROM:<me@example.com> BODY=8BITMIME', req),
        'MAIL FROM:<me@example.com> BODY=8BITMIME RET=HDRS ENVID=abc+2B1+3Dx@example.com');
    expect(TolerantSmtpClient.applyDsn('RCPT TO:<a@example.net>', req), 'RCPT TO:<a@example.net> NOTIFY=FAILURE,DELAY');
    expect(TolerantSmtpClient.applyDsn('RCPT TO:<a@example.net>', const DsnRequest(notifySuccess: true)),
        'RCPT TO:<a@example.net> NOTIFY=SUCCESS,FAILURE,DELAY');
    const data = 'Subject: x\r\n\r\nMAIL FROM:<me@example.com>\r\n.';
    expect(identical(TolerantSmtpClient.applyDsn(data, req), data), isTrue);
    expect(TolerantSmtpClient.applyDsn('DATA', req), 'DATA');
    expect(TolerantSmtpClient.xtext('a b'), 'a+20b');
  });

  test('сервер объявил DSN: MAIL FROM с RET и ENVID, каждый RCPT TO с NOTIFY', () async {
    final got = await _send(
        serverDsn: true, dsn: const DsnRequest(envelopeId: 'm1@example.com', notifySuccess: true));
    expect(got, contains('MAIL FROM:<me@example.com> RET=HDRS ENVID=m1@example.com'));
    expect(got, contains('RCPT TO:<a@example.net> NOTIFY=SUCCESS,FAILURE,DELAY'));
    expect(got, contains('RCPT TO:<b@example.net> NOTIFY=SUCCESS,FAILURE,DELAY'));
  });

  test('сервер без DSN: команды прежние', () async {
    final got = await _send(serverDsn: false, dsn: const DsnRequest(envelopeId: 'm1@example.com'));
    expect(got, contains('MAIL FROM:<me@example.com>'));
    expect(got, contains('RCPT TO:<a@example.net>'));
    expect(got.where((l) => l.contains('NOTIFY') || l.contains('RET=')), isEmpty);
  });

  test('без запроса DSN: команды прежние и при DSN у сервера', () async {
    final got = await _send(serverDsn: true);
    expect(got, contains('MAIL FROM:<me@example.com>'));
    expect(got.where((l) => l.contains('NOTIFY')), isEmpty);
  });
}

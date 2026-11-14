// test/unit/smtp_split_replies_test.dart
// Mercury (XAMPP) и другие серверы, которые шлют каждую строку ответа
// отдельным пакетом (жалоба пользователя 14.11.2026). enough_mail считал
// ответом всё, что пришло одним пакетом: многострочный ответ на EHLO
// распадался на несколько «ответов», клиент сбивался на один ответ и
// принимал «354 send data» за ответ на конец письма — письмо доходило, а в
// очереди висело с ошибкой «354 OK, send data». Ответ собирается по
// правилу SMTP: строки «250-…» — продолжение, «250 …» — последняя.
//
// EHLO с адресом IP: «EHLO 192.168.1.67» — неверно (RFC 5321, 4.1.3),
// Mercury отвечает «554 Invalid HELO format»; нужно «EHLO [192.168.1.67]».

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' show SmtpReplyFramer, TolerantSmtpClient;

/// Сервер как Mercury: EHLO с голым IP — 554. [lines] — каждая строка
/// ответа отдельным пакетом; иначе как у пользователя: первые две строки
/// ответа на EHLO одним пакетом, остальные следом, вход — с задержкой.
/// Команды — в [got], принятые письма — в [mails].
Future<ServerSocket> _mercury(List<String> got, List<String> mails, {bool lines = true, bool splitGreeting = false}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((s) {
    final out = StreamController<(Duration, String)>();
    unawaited(() async {
      await for (final (pause, text) in out.stream) {
        await Future<void>.delayed(pause);
        s.write(text);
        await s.flush();
      }
    }());
    const step = Duration(milliseconds: 15);
    // Ответ пакетами: [chunks] — строки каждого пакета.
    void send(List<List<String>> chunks, {Duration first = Duration.zero}) {
      for (var i = 0; i < chunks.length; i++) {
        out.add((i == 0 ? first : const Duration(milliseconds: 30), chunks[i].map((l) => '$l\r\n').join()));
      }
    }
    void reply(List<String> r, {List<List<String>>? asUser, Duration slow = Duration.zero}) {
      if (lines) {
        send([for (final l in r) [l]], first: step);
      } else {
        send(asUser ?? [r], first: slow);
      }
    }
    final greet = splitGreeting ? ['220-192.168.1.67 ESMTP server ready.', '220 Mercury/32 v4.91'] : ['220 192.168.1.67 ESMTP server ready.'];
    if (lines) {
      send([for (final l in greet) [l]]);
    } else {
      send([greet]);
    }
    var buf = '';
    StringBuffer? data;
    s.listen((chunk) {
      buf += utf8.decode(chunk);
      while (buf.contains('\r\n')) {
        final i = buf.indexOf('\r\n');
        final line = buf.substring(0, i);
        buf = buf.substring(i + 2);
        if (data != null) {
          if (line == '.') {
            mails.add(data.toString());
            data = null;
            reply(['250 Data received OK.']);
          } else {
            data!.writeln(line);
          }
          continue;
        }
        got.add(line);
        if (line.startsWith('EHLO ')) {
          final name = line.substring(5).trim();
          if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(name)) {
            reply(['554 Invalid HELO format']);
          } else {
            final r = [
              '250-192.168.1.67 Hello $name; ESMTPs are:',
              '250-TIME',
              '250-SIZE 0',
              '250-AUTH CRAM-MD5 PLAIN LOGIN',
              '250 HELP',
            ];
            reply(r, asUser: [r.sublist(0, 2), r.sublist(2)]);
          }
        } else if (line.startsWith('AUTH PLAIN')) {
          reply(['235 Authentication successful'], slow: const Duration(milliseconds: 60));
        } else if (line.startsWith('MAIL FROM:')) {
          reply(['250 Sender OK - send RCPTs.']);
        } else if (line.startsWith('RCPT TO:')) {
          reply(['250 Recipient OK - send RCPT or DATA.']);
        } else if (line == 'DATA') {
          data = StringBuffer();
          reply(['354 OK, send data, end with CRLF.CRLF']);
        } else if (line == 'QUIT') {
          reply(['221 Goodbye']);
        } else {
          reply(['500 Unknown command']);
        }
      }
    }, onError: (_) {}, onDone: () => out.close());
  });
  return server;
}

MimeMessage _message() => (MessageBuilder()
      ..from = [const MailAddress('Android', 'android@192.168.1.67')]
      ..to = [const MailAddress('', 'computer@192.168.1.67')]
      ..subject = 'RE: android@192.168.1.67;'
      ..text = 'Привет')
    .buildMimeMessage();

void main() {
  test('имя для EHLO: адрес IP — в квадратных скобках, домен — как есть', () {
    expect(TolerantSmtpClient.heloName('192.168.1.67'), '[192.168.1.67]');
    expect(TolerantSmtpClient.heloName('[192.168.1.67]'), '[192.168.1.67]');
    expect(TolerantSmtpClient.heloName('::1'), '[IPv6:::1]');
    expect(TolerantSmtpClient.heloName('corp.example'), 'corp.example');
    expect(TolerantSmtpClient.heloName('Corp.Example'), 'Corp.Example');
    expect(TolerantSmtpClient.heloName(''), 'localhost');
    expect(TolerantSmtpClient.heloName('bad name'), 'localhost');
  });

  test('сборка ответа: «250-» — продолжение, «250 » и «334» — конец', () {
    final r = SmtpReplyFramer();
    expect(r.add(['250-host Hello', '250-SIZE 0']), isEmpty);
    expect(r.add(['250 HELP', '235 OK', '334']), [
      ['250-host Hello', '250-SIZE 0', '250 HELP'],
      ['235 OK'],
      ['334'],
    ]);
  });

  for (final (lines, split) in [(false, false), (true, false), (true, true)]) {
    final name = lines ? 'строки ответа по одной${split ? ', приветствие из двух строк' : ''}' : 'как в журнале пользователя';
    test('Mercury: $name — письмо уходит один раз, без ошибки', () async {
      final got = <String>[];
      final mails = <String>[];
      final server = await _mercury(got, mails, lines: lines, splitGreeting: split);
      final client = TolerantSmtpClient('192.168.1.67');
      await client.connectToServer('127.0.0.1', server.port, isSecure: false);
      final ehlo = await client.ehlo().timeout(const Duration(seconds: 5));
      expect(ehlo.isOkStatus, isTrue);
      expect(client.serverInfo.supportsAuth(AuthMechanism.login), isTrue, reason: 'возможности — из всего ответа');
      await client.authenticate('android@192.168.1.67', 'secret', AuthMechanism.plain).timeout(const Duration(seconds: 5));
      final sent = await client.sendMessage(_message()).timeout(const Duration(seconds: 5));
      expect(sent.code, 250);
      expect(mails, hasLength(1));
      expect(got.first, 'EHLO [192.168.1.67]');
      await client.quit();
      await server.close();
    });
  }
}

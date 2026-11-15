// Подбор портов рабочей почты (2.6.0): только доступность сервера, без
// пароля; проверенный вариант не повторяется, SMTP ищется и на сервере IMAP.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart' show EncryptionType;
import 'package:ogneliss/services/mail/server_probe.dart';

/// Сервер на 127.0.0.1: на подключение пишет [hello], на строки отвечает
/// [answer] (null — молчит).
Future<ServerSocket> _server(String hello, String? Function(String line) answer) async {
  final ss = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  ss.listen((c) {
    c.add(utf8.encode(hello));
    c.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
      final a = answer(l);
      if (a != null) c.add(utf8.encode(a));
    }, onError: (_) {});
  });
  return ss;
}

void main() {
  test('IMAP: проверенный вариант пропускается, первый ответивший — результат', () async {
    final asked = <String>[];
    final r = await ServerProbe.imap('mail.corp.ru', tried: (993, EncryptionType.ssl), check: (h, p, e) async {
      asked.add('$h:$p:${e.name}');
      return p == 143;
    });
    expect(asked, ['mail.corp.ru:143:starttls']);
    expect(r, (host: 'mail.corp.ru', port: 143, encryption: EncryptionType.starttls));
  });

  test('SMTP: на сервере SMTP не ответил — ищем на сервере IMAP', () async {
    final asked = <String>[];
    final r = await ServerProbe.smtp('smtp.corp.ru', moreHosts: ['imap.corp.ru'], check: (h, p, e) async {
      asked.add('$h:$p');
      return h == 'imap.corp.ru' && p == 587;
    });
    expect(asked, ['smtp.corp.ru:465', 'smtp.corp.ru:587', 'smtp.corp.ru:25', 'imap.corp.ru:465', 'imap.corp.ru:587']);
    expect(r?.host, 'imap.corp.ru');
    expect(r?.encryption, EncryptionType.starttls);
  });

  test('никто не ответил — null; исключение проверки — как «не ответил»', () async {
    final r = await ServerProbe.imap('x.corp.ru', check: (h, p, e) async => throw const SocketException('нет'));
    expect(r, isNull);
  });

  test('IMAP без шифрования: приветствие «* OK» — сервер отвечает', () async {
    final ss = await _server('* OK IMAP4rev1 ready\r\n', (_) => null);
    addTearDown(ss.close);
    expect(await ServerProbe.checkImap('127.0.0.1', ss.port, EncryptionType.none), isTrue);
  });

  test('IMAP STARTTLS: сервер не принял STARTTLS — не подходит', () async {
    final ss = await _server('* OK ready\r\n', (l) => l.startsWith('a1 STARTTLS') ? 'a1 BAD unknown\r\n' : null);
    addTearDown(ss.close);
    expect(await ServerProbe.checkImap('127.0.0.1', ss.port, EncryptionType.starttls), isFalse);
  });

  test('SMTP: многострочное приветствие «220-… 220 …»', () async {
    final ss = await _server('220-mail.corp.ru ESMTP\r\n220 ready\r\n', (_) => null);
    addTearDown(ss.close);
    expect(await ServerProbe.checkSmtp('127.0.0.1', ss.port, EncryptionType.none), isTrue);
  });

  test('SMTP STARTTLS: нет поддержки — не подходит', () async {
    final ss = await _server('220 ready\r\n', (l) {
      if (l.startsWith('EHLO')) return '250-mail.corp.ru\r\n250 AUTH LOGIN\r\n';
      if (l.startsWith('STARTTLS')) return '502 not supported\r\n';
      return null;
    });
    addTearDown(ss.close);
    expect(await ServerProbe.checkSmtp('127.0.0.1', ss.port, EncryptionType.starttls), isFalse);
  });

  test('не тот протокол (HTTP) — не подходит', () async {
    final ss = await _server('HTTP/1.1 400 Bad Request\r\n\r\n', (_) => null);
    addTearDown(ss.close);
    expect(await ServerProbe.checkImap('127.0.0.1', ss.port, EncryptionType.none), isFalse);
    expect(await ServerProbe.checkSmtp('127.0.0.1', ss.port, EncryptionType.none), isFalse);
  });
}

// Журнал 18.11.2026 16:28 (Xiaomi, 2.5.3): адрес ящика в настройках
// «…@yamalspd.ru» вместо «…@yamalspg.ru». Вход по логину домена работал,
// почта приходила, а все 19 писем — SendMail Status 120: Exchange не
// отправляет письмо от адреса, которого у ящика нет. Теперь при Status 120
// приложение спрашивает у сервера адреса ящика (UserInformation) и, если
// адреса из настроек среди них нет, повторяет отправку от основного адреса
// ящика — и дальше отправляет от него сразу.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _email = 'a.ivanov@typo.example';
const _primary = 'a.ivanov@corp.example';
const _server = 'owner-from.example.com';
const _device = 'TESTDEVICE0120';

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
      'proto': '16.1',
      'b64': false,
      'versions': ['14.1', '16.0', '16.1'],
      'cmds': ['Sync', 'FolderSync', 'Ping', 'SendMail', 'Settings'],
      'key': '1234567890',
      'at': DateTime.now().millisecondsSinceEpoch,
    });

http.Response _wbxml(WbxmlElement root) => http.Response.bytes(
    WbxmlEncoder().encode(WbxmlDocument(root: root)), 200,
    headers: {'content-type': 'application/vnd.ms-sync.wbxml'});

http.Response _sendStatus(String status) {
  final root = WbxmlElement(name: 'SendMail', namespace: 'ComposeMail');
  root.addChild('Status', namespace: 'ComposeMail', text: status);
  return _wbxml(root);
}

http.Response _userInfo(List<String> addresses) {
  final root = WbxmlElement(name: 'Settings', namespace: 'Settings');
  root.addChild('Status', namespace: 'Settings', text: '1');
  final get = root.addChild('UserInformation', namespace: 'Settings')
    ..addChild('Status', namespace: 'Settings', text: '1');
  final acc = get
      .addChild('Get', namespace: 'Settings')
      .addChild('Accounts', namespace: 'Settings')
      .addChild('Account', namespace: 'Settings');
  acc.addChild('UserDisplayName', namespace: 'Settings', text: 'Иванов Алексей');
  final emails = acc.addChild('EmailAddresses', namespace: 'Settings');
  for (final (i, a) in addresses.indexed) {
    emails.addChild(i == 0 ? 'PrimarySmtpAddress' : 'SMTPAddress', namespace: 'Settings', text: a);
  }
  return _wbxml(root);
}

/// Адрес From из MIME запроса SendMail (тело — WBXML с MIME внутри).
String _fromOf(http.Request req) {
  final text = latin1.decode(req.bodyBytes);
  return RegExp(r'From: ([^\r\n]*)').firstMatch(text)?.group(1) ?? '';
}

void main() {
  setUp(() {
    EasEngine.debugResetOwnerFrom();
    EasEngine.saveSession = (_, __) {};
    EasEngine.loadSession = (email) => email == _email ? _session() : null;
  });

  tearDown(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
    EasEngine.debugResetOwnerFrom();
  });

  const message = OutgoingMessage(to: [MailAddress('colleague@corp.example')], subject: 'RE: КС', bodyHtml: '<p>Ок</p>');

  test('Status 120, адреса из настроек у ящика нет — повтор от основного адреса, дальше сразу от него', () async {
    final froms = <String>[];
    final clientIds = <String>[];
    var settings = 0;
    final eng = EasEngine(httpClient: MockClient((req) async {
      final q = req.url.query;
      if (q.contains('Cmd=Settings')) {
        settings++;
        return _userInfo([_primary, 'ivanov@corp.example']);
      }
      if (q.contains('Cmd=SendMail')) {
        final from = _fromOf(req);
        froms.add(from);
        clientIds.add(RegExp(r'snd[A-Za-z0-9_-]*').firstMatch(latin1.decode(req.bodyBytes))?.group(0) ?? '');
        return from.contains(_primary) ? http.Response('', 200) : _sendStatus('120');
      }
      return http.Response('', 200);
    }));
    expect((await eng.connect(_cfg())).success, isTrue);

    await eng.send(message);
    expect(froms, hasLength(2));
    expect(froms.first, contains(_email));
    expect(froms.last, contains(_primary));
    expect(clientIds.first, isNot(clientIds.last), reason: 'повтор — с другим ClientId, иначе Status 118');
    expect(settings, 1);

    // Следующее письмо — сразу от адреса с сервера, без отказа и без вопроса серверу.
    await eng.send(message);
    expect(froms, hasLength(3));
    expect(froms.last, contains(_primary));
    expect(settings, 1);
  });

  test('Status 120, адрес из настроек у ящика есть — ошибка как раньше, без повтора', () async {
    var sends = 0;
    final eng = EasEngine(httpClient: MockClient((req) async {
      final q = req.url.query;
      if (q.contains('Cmd=Settings')) return _userInfo([_email]);
      if (q.contains('Cmd=SendMail')) {
        sends++;
        return _sendStatus('120');
      }
      return http.Response('', 200);
    }));
    expect((await eng.connect(_cfg())).success, isTrue);
    await expectLater(eng.send(message), throwsA(predicate((e) => '$e'.contains('Status=120'))));
    expect(sends, 1);
  });

  test('отправка «от имени» (выбран отправитель) — без подмены адреса', () async {
    var sends = 0;
    final eng = EasEngine(httpClient: MockClient((req) async {
      if (req.url.query.contains('Cmd=SendMail')) {
        sends++;
        return _sendStatus('120');
      }
      return http.Response('', 200);
    }));
    expect((await eng.connect(_cfg())).success, isTrue);
    const onBehalf = OutgoingMessage(
        to: [MailAddress('colleague@corp.example')], subject: 'x', bodyHtml: '<p>x</p>',
        from: MailAddress('boss@corp.example'));
    await expectLater(eng.send(onBehalf), throwsA(isA<Exception>()));
    expect(sends, 1);
  });
}

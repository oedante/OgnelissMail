// Быстрое подключение Exchange (сеанс между запусками, 1.5.1): свежий сеанс
// подключает без единого запроса; устаревший, чужого сервера или телефона —
// полное подключение; 401 на первом запросе после восстановления — сеанс
// сбрасывается (иначе он жил бы до 12 часов после смены пароля).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _email = 'user@example.com';
const _server = 'mail.example.com';
const _device = 'TESTDEVICE0001';

AccountConfig _cfg({String server = _server, String device = _device}) => AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: server,
      deviceId: device,
      forceTransport: MailTransportKind.eas,
    );

String _session({Duration age = Duration.zero, String server = _server, String device = _device}) => jsonEncode({
      'v': 1,
      'server': server,
      'device': device,
      'url': 'https://$_server/Microsoft-Server-ActiveSync',
      'host': _server,
      'proto': '14.1',
      'b64': false,
      'versions': ['14.1'],
      'cmds': ['Sync', 'FolderSync', 'Ping'],
      'key': '1234567890',
      'at': DateTime.now().subtract(age).millisecondsSinceEpoch,
    });

void main() {
  late int calls;
  late Map<String, String?> saved;
  late int status;

  MockClient client() => MockClient((req) async {
        calls++;
        return http.Response('', status);
      });

  setUp(() {
    calls = 0;
    status = 401;
    saved = {};
    EasEngine.saveSession = (email, data) => saved[email] = data;
  });

  tearDown(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  test('свежий сеанс — подключение без запросов к серверу', () async {
    EasEngine.loadSession = (email) => email == _email ? _session() : null;
    final eng = EasEngine(httpClient: client());
    final r = await eng.connect(_cfg());
    expect(r.success, isTrue);
    expect(calls, 0);
  });

  for (final c in <String, String>{
    'старше 12 часов': _session(age: const Duration(hours: 13)),
    'другой сервер': _session(server: 'old.example.com'),
    'другой телефон (DeviceId)': _session(device: 'OTHERDEVICE'),
    'неизвестная версия формата': jsonEncode({'v': 2}),
    'испорченный JSON': '{oops',
  }.entries) {
    test('сеанс не используется: ${c.key}', () async {
      EasEngine.loadSession = (_) => c.value;
      final eng = EasEngine(httpClient: client());
      try {
        await eng.connect(_cfg()).timeout(const Duration(seconds: 30));
      } catch (_) {}
      expect(calls, greaterThan(0), reason: 'должно быть полное подключение');
    });
  }

  test('401 на первом запросе после восстановления — сеанс сброшен', () async {
    EasEngine.loadSession = (_) => _session();
    final eng = EasEngine(httpClient: client());
    expect((await eng.connect(_cfg())).success, isTrue);
    try {
      await eng.listFolders().timeout(const Duration(seconds: 30));
    } catch (_) {}
    expect(calls, greaterThan(0));
    expect(saved.containsKey(_email), isTrue);
    expect(saved[_email], isNull, reason: 'saveSession(email, null) — сеанс удалён');
  });
}

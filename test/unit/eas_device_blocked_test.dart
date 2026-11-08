// Блокировка в Exchange (план 08.11.2026 п. 1): устройство заблокировано
// (Status 129), предел числа устройств (177), ActiveSync отключён (126) —
// понятная ошибка подключения вместо пустого ящика, без Provision за
// Provision и без отката версии протокола.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';
import 'package:ogneliss/features/auth/providers/auth_provider.dart' show authErrorKindOf, AuthErrorKind;

const _email = 'user@example.com';

AccountConfig _cfg() => const AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: 'mail.example.com',
      deviceId: 'TESTDEVICE0001',
      forceTransport: MailTransportKind.eas,
    );

Uint8List _provisionStatus(String status) {
  final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
  root.addChild('Status', namespace: 'Provision', text: status);
  return WbxmlEncoder().encode(WbxmlDocument(root: root));
}

void main() {
  setUp(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  for (final (code, words) in [
    ('129', 'устройство заблокировано'),
    ('177', 'предел числа устройств'),
    ('126', 'отключена синхронизация'),
  ]) {
    test('Provision Status $code — понятная ошибка, один запрос, без отката на 14.1', () async {
      final versions = <String>[];
      final eng = EasEngine(
        httpClient: MockClient((req) async {
          if (req.method == 'OPTIONS') {
            return http.Response('', 200, headers: {
              'ms-asprotocolversions': '14.1,16.1',
              'ms-asprotocolcommands': 'Sync,FolderSync,Provision',
            });
          }
          versions.add(req.headers['MS-ASProtocolVersion'] ?? '');
          return http.Response.bytes(_provisionStatus(code), 200,
              headers: {'content-type': 'application/vnd.ms-sync.wbxml'});
        }),
      );
      final r = await eng.connect(_cfg());
      expect(r.success, isFalse);
      expect(r.error, startsWith('EAS Status $code: '));
      expect(r.error, contains(words));
      expect(versions.length, 1, reason: 'без повторного Provision и отката версии');
      // Пароль верный — это не «неверный пароль».
      expect(authErrorKindOf(r.error), AuthErrorKind.generic);
    });
  }
}

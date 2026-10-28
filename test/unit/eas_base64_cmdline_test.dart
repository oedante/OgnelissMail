// test/unit/eas_base64_cmdline_test.dart
// Base64-команда EAS (MS-ASHTTP §2.2.1.1.1.1) — как шлёт штатная Почта iPhone:
// один непрозрачный токен вместо ?Cmd=..&User=..&DeviceId=..&DeviceType=..
// По журналу iPhone 17.10.2026 анти-бот шлюз организации пропускает OPTIONS, но
// режет Provision в виде plain-query (403). Base64 — форма настоящего клиента.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';

void main() {
  test('Provision 16.1: раскладка байтов командной строки', () {
    final token = EasEngine.easBase64CommandLine(
      cmd: 'Provision', ver: '16.1', deviceId: 'ABC', deviceType: 'iPhone');
    // base64url без паддинга — только [A-Za-z0-9_-], как у Apple Mail.
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(token), isTrue);
    final bytes = base64Url.decode(token + '=' * ((4 - token.length % 4) % 4));
    var i = 0;
    expect(bytes[i++], 161); // 16.1 * 10
    expect(bytes[i++], easCommandCodes['Provision']); // код команды Provision
    expect(bytes[i++], 0x09); // Locale en-US LE
    expect(bytes[i++], 0x04);
    expect(bytes[i++], 3); // длина DeviceId «ABC»
    expect(utf8.decode(bytes.sublist(i, i + 3)), 'ABC'); i += 3;
    expect(bytes[i++], 0); // PolicyKey пуст → длина 0
    expect(bytes[i++], 6); // длина DeviceType «iPhone»
    expect(utf8.decode(bytes.sublist(i, i + 6)), 'iPhone');
  });

  test('PolicyKey кодируется 4 байтами LE', () {
    final token = EasEngine.easBase64CommandLine(
      cmd: 'Sync', ver: '16.1', deviceId: 'D', deviceType: 'iPhone', policyKey: '305419896');
    final bytes = base64Url.decode(token + '=' * ((4 - token.length % 4) % 4));
    // [ver][cmd][loc0][loc1][devLen=1][D][pkLen=4][pk LE…]
    const pkLenAt = 2 + 2 + 1 + 1;
    expect(bytes[pkLenAt], 4);
    final pk = bytes[pkLenAt + 1] |
        (bytes[pkLenAt + 2] << 8) |
        (bytes[pkLenAt + 3] << 16) |
        (bytes[pkLenAt + 4] << 24);
    expect(pk, 305419896); // 0x12345678
  });

  _cookieTests();
  _gatewayTests();

  test('easBase64Override проходит через copyWith', () {
    const base = AccountConfig(email: 'a@b.ru', easBase64Override: true);
    expect(base.withUserAgent('X').easBase64Override, isTrue);
    const none = AccountConfig(email: 'a@b.ru');
    expect(none.easBase64Override, isNull);
  });
}

// Разбор Set-Cookie (cookie jar): анти-бот шлюз ServicePipe ставит свой cookie
// на OPTIONS, Exchange — X-BackEndCookie; на POST нужны оба (журнал 17.10.2026).
void _cookieTests() {
  test('Set-Cookie: несколько cookie в одной строке, запятая в дате не делит', () {
    final parts = EasEngine.splitSetCookie(
        'X-BackEndCookie=abc123; expires=Wed, 09-Jun-2027 10:18:14 GMT; path=/; secure, '
        'sp=xyz789; path=/; HttpOnly');
    expect(parts.length, 2);
    expect(parts[0].startsWith('X-BackEndCookie=abc123'), isTrue);
    expect(parts[1].startsWith('sp=xyz789'), isTrue);
  });

  test('Set-Cookie: один cookie', () {
    final parts = EasEngine.splitSetCookie('A=1; path=/');
    expect(parts.length, 1);
    expect(parts.first, 'A=1; path=/');
  });
}

// 1.6.16: очистка адреса сервера и пауза анти-бот шлюза по ключу (EWS).
void _gatewayTests() {
  test('cleanServer: пробелы, хвостовой слэш, регистр хоста', () {
    expect(EasEngine.cleanServer(' cloud mail.Corp.example '), 'cloudmail.corp.example');
    expect(EasEngine.cleanServer('mail.example.com/'), 'mail.example.com');
    expect(EasEngine.cleanServer('https://Mail.example.com/EWS/Exchange.asmx'),
        'https://Mail.example.com/EWS/Exchange.asmx');
  });

  test('markWafBlocked: пауза по ключу EWS не задевает EAS того же хоста', () {
    expect(EasEngine.wafPauseMinutesLeft('ews:waf-test.example'), 0);
    EasEngine.markWafBlocked('ews:WAF-test.example');
    expect(EasEngine.wafPauseMinutesLeft('ews:waf-test.example'), greaterThan(0));
    expect(EasEngine.wafPauseMinutesLeft('waf-test.example'), 0);
  });
}

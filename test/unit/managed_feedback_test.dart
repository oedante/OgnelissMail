// Отчёт консоли MDM (Android Enterprise KeyedAppStates, 2.2.0): что
// приложение сообщает ИТ-службе о принятых настройках.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/managed_config.dart';
import 'package:ogneliss/services/security/managed_feedback.dart';

List<FeedbackState> _report(Map<Object?, Object?> raw, {bool pinSet = false, bool accountAdded = false}) =>
    managedFeedback(raw, ManagedPolicy.fromMap(raw), pinSet: pinSet, accountAdded: accountAdded);

FeedbackState? _of(List<FeedbackState> l, String key) => l.where((s) => s.key == key).firstOrNull;

void main() {
  test('верные настройки: только сведения, без ошибок', () {
    final raw = {
      'org_name': 'Ромашка',
      'account_email': 'ivanov@romashka.ru',
      'allowed_domains': 'romashka.ru',
      'require_app_lock': true,
      'min_pin_length': 6,
      'account_transport': 'eas',
      'block_share': 'yes',
    };
    final r = _report(raw, pinSet: true, accountAdded: true);
    expect(r.where((s) => s.severity == FeedbackSeverity.error), isEmpty, reason: '$r');
    final policy = _of(r, 'policy')!;
    expect(policy.message, contains('7 key'));
    expect(policy.data, 'account_email,account_transport,allowed_domains,block_share,min_pin_length,org_name,require_app_lock');
    expect(_of(r, 'account')!.data, 'added');
    expect(_of(r, 'app_lock')!.data, 'set');
    // Адреса в отчёте нет.
    expect(r.map((s) => '${s.message} ${s.data}').join(' '), isNot(contains('ivanov')));
  });

  test('ошибки настроек — по ключам', () {
    final r = _report({
      'min_pin_lenght': 6,
      'min_pin_length': 9,
      'pin_timeout_minutes': 'five',
      'account_transport': 'mapi',
      'account_protocol': 'pop3',
      'account_email': r'$EMAIL$',
      'account_locked': true,
      'block_copy': 'maybe',
      'imap_port': 70000,
      'trusted_ca_pem': '-----BEGIN CERTIFICATE-----\nnot base64\n-----END CERTIFICATE-----',
    });
    final errors = {for (final s in r.where((s) => s.severity == FeedbackSeverity.error)) s.key};
    expect(errors, {
      'unknown_keys',
      'min_pin_length',
      'pin_timeout_minutes',
      'account_transport',
      'account_protocol',
      'account_email',
      'account_locked',
      'block_copy',
      'imap_port',
      'trusted_ca_pem',
    });
    expect(_of(r, 'unknown_keys')!.data, 'min_pin_lenght');
    expect(_of(r, 'min_pin_length')!.message, contains('using 6'));
    expect(_of(r, 'account'), isNull, reason: 'адрес не распознан — ящика организации нет');
  });

  test('ящик вне allowed_domains и сертификаты организации', () {
    final root = File('assets/certs/russian_trusted_root_ca.pem').readAsStringSync();
    final r = _report({
      'account_email': 'ivanov@gmail.com',
      'allowed_domains': 'romashka.ru',
      'trusted_ca_pem': root,
    });
    expect(_of(r, 'allowed_domains')!.severity, FeedbackSeverity.error);
    final ca = _of(r, 'trusted_ca_pem')!;
    expect(ca.severity, FeedbackSeverity.info);
    expect(ca.message, contains('1'));
    expect(_of(r, 'account')!.data, 'missing');
    expect(_of(r, 'app_lock'), isNull, reason: 'PIN не требуется');
  });

  test('пределы KeyedAppState: ключ 100, текст и данные 1000 символов', () {
    final m = FeedbackState('k' * 150, FeedbackSeverity.error, 'm' * 1500, 'd' * 1200).toMap();
    expect((m['key']! as String).length, 100);
    expect((m['message']! as String).length, 1000);
    expect((m['data']! as String).length, 1000);
    expect(m['severity'], 2);
    expect(const FeedbackState('a', FeedbackSeverity.info, 'b').toMap(), {'key': 'a', 'severity': 1, 'message': 'b'});
  });
}

// Отказ обновления токена у провайдера при входе без сервера входа (1.6.9):
// понятный текст и «нужен повторный вход» вместо «проверьте сервер».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';

void main() {
  final google = DirectOAuth.fromMarker('google|111-old.apps.googleusercontent.com')!;

  test('invalid_client — нужен повторный вход, без упоминания сервера входа', () {
    final f = DirectOAuth.describeRefreshFailure(google, 401,
        '{"error":"invalid_client","error_description":"The OAuth client was not found."}',
        currentClientId: '222-new.apps.googleusercontent.com');
    expect(f.needsSignIn, isTrue);
    expect(f.text, contains('Google'));
    expect(f.text, contains('The OAuth client was not found.'));
    expect(f.text, contains('другой клиент'));
    expect(f.text, isNot(contains('прокси')));
  });

  test('invalid_grant — вход отозван', () {
    final f = DirectOAuth.describeRefreshFailure(google, 400, '{"error":"invalid_grant"}');
    expect(f.needsSignIn, isTrue);
  });

  test('сбой сервера — не требует входа', () {
    final f = DirectOAuth.describeRefreshFailure(google, 503, 'Service Unavailable');
    expect(f.needsSignIn, isFalse);
    expect(f.text, contains('503'));
  });

  test('Exchange Online — только рабочие учётные записи', () {
    final ex = DirectOAuth.fromMarker('exchange|abc')!;
    expect(ex.tokenEndpoint.path, contains('/organizations/'));
    final ms = DirectOAuth.fromMarker('microsoft|abc')!;
    expect(ms.tokenEndpoint.path, contains('/common/'));
  });
}

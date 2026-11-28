// Лимит размера письма — только названный сервером (2.7.5, просьба
// пользователей 27.11.2026: «снять лимит 25 МБ, ориентироваться на лимиты
// сервера»).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/providers/attachment_limit_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('лимита нет, пока сервер его не назвал; названный — запоминается', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AttachmentLimitStore(await SharedPreferences.getInstance());
    expect(store.limitFor('a1'), isNull);
    expect(store.isKnown('a1'), isFalse);
    final limit = AttachmentLimitStore.parseLimitFromError('552 5.3.4 Message size exceeds fixed maximum message size of 35 MB');
    expect(limit, 35 * 1024 * 1024);
    await store.setLimit('a1', limit!);
    expect(store.limitFor('a1'), 35 * 1024 * 1024);
    expect(store.isKnown('a1'), isTrue);
    expect(store.limitFor('a2'), isNull, reason: 'у другого ящика — свой');
  });
}

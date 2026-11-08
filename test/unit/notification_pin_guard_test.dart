// Кнопки уведомлений при заданном PIN (2.0.0, план 08.11.2026): действия с
// письмом и приглашением не выполняются без входа в приложение.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/notifications/notification_action_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('PIN задан — ответ, прочитано, удаление и приглашение заблокированы', () async {
    SharedPreferences.setMockInitialValues({NotificationPinGuard.pinSetKey: true});
    final p = await SharedPreferences.getInstance();
    for (final id in ['quick_reply', 'smart_reply_0', 'mark_read', 'delete', 'invite_accept', 'invite_decline']) {
      expect(NotificationPinGuard.blocks(id, p), isTrue, reason: id);
    }
    // Отложить напоминание и «Подключиться» (открывает приложение) — можно.
    for (final id in ['later_1h', 'later_tomorrow', 'join']) {
      expect(NotificationPinGuard.blocks(id, p), isFalse, reason: id);
    }
  });

  test('PIN не задан — кнопки работают', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    expect(NotificationPinGuard.pinSet(p), isFalse);
    expect(NotificationPinGuard.blocks('delete', p), isFalse);
  });

  test('ключ признака совпадает с PinLockNotifier', () {
    expect(NotificationPinGuard.pinSetKey, 'app_pin_set');
  });
}

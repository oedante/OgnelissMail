// Беседы без уведомлений (1.8.13, как «Без звука» у чата в Telegram).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/notifications/account_notify_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('выключить и включить уведомления беседы', () async {
    final p = await SharedPreferences.getInstance();
    expect(ConversationNotify.isMuted(p, 'a1', '<root@x>'), isFalse);
    await ConversationNotify.set(p, 'a1', '<root@x>', false);
    expect(ConversationNotify.isMuted(p, 'a1', '<root@x>'), isTrue);
    // Та же беседа в другом ящике — своя.
    expect(ConversationNotify.isMuted(p, 'a2', '<root@x>'), isFalse);
    expect(ConversationNotify.isMuted(p, 'a1', null), isFalse);
    await ConversationNotify.set(p, 'a1', '<root@x>', true);
    expect(ConversationNotify.isMuted(p, 'a1', '<root@x>'), isFalse);
  });

  test('удалённый ящик уходит из списка, список не растёт без конца', () async {
    final p = await SharedPreferences.getInstance();
    await ConversationNotify.set(p, 'a1', 'c1', false);
    await ConversationNotify.set(p, 'a2', 'c2', false);
    await ConversationNotify.forgetAccount(p, 'a1');
    expect(ConversationNotify.off(p), {'a2|c2'});
    for (var i = 0; i < 520; i++) {
      await ConversationNotify.set(p, 'a3', 'c$i', false);
    }
    expect(ConversationNotify.off(p).length, 500);
    expect(ConversationNotify.isMuted(p, 'a3', 'c519'), isTrue);
    expect(ConversationNotify.isMuted(p, 'a2', 'c2'), isFalse); // самая давняя — вытеснена
  });
}

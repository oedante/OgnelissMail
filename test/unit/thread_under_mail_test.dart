// Беседа под письмом (2.7.5, просьба владельца 28.11.2026): «всегда», «при
// открытии из уведомления» (по умолчанию — как было: не с экрана беседы),
// «никогда».
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/thread_under_mail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('когда беседа под письмом видна', () {
    expect(showThreadUnderMail(ThreadUnderMail.standalone, fromConversation: false), isTrue);
    expect(showThreadUnderMail(ThreadUnderMail.standalone, fromConversation: true), isFalse,
        reason: 'с экрана беседы — она уже позади');
    expect(showThreadUnderMail(ThreadUnderMail.always, fromConversation: true), isTrue);
    expect(showThreadUnderMail(ThreadUnderMail.never, fromConversation: false), isFalse);
  });

  test('по умолчанию — «при открытии из уведомления», выбор запоминается', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    expect(c.read(threadUnderMailProvider), ThreadUnderMail.standalone);
    await c.read(threadUnderMailProvider.notifier).set(ThreadUnderMail.always);
    c.dispose();
    c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    expect(c.read(threadUnderMailProvider), ThreadUnderMail.always);
    c.dispose();
  });
}

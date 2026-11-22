// 1.7.3: кнопки под письмом; с 2.6.9 по умолчанию — стандартно («Ответить»
// слева, решение владельца 22.11.2026), под правую руку — зеркально, свой
// порядок и сохранённый выбор запоминаются; вопрос перед удалением включён.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/drawer_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> make(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    return c;
  }

  test('по умолчанию — стандартно: «Ответить» слева', () async {
    final c = await make({});
    final order = c.read(mailBarOrderProvider);
    expect(order.first, MailBarAction.reply);
    expect(order.last, MailBarAction.more);
    expect(MailBarOrderNotifier.same(order, MailBarOrderNotifier.leftHand), isTrue);
    expect(c.read(confirmMailDeleteProvider), isTrue);
  });

  test('сохранённый выбор «под правую руку» остаётся', () async {
    final c = await make({
      'mail_bar_order': [for (final a in MailBarOrderNotifier.rightHand) a.name],
    });
    final order = c.read(mailBarOrderProvider);
    expect(order.last, MailBarAction.reply);
    expect(MailBarOrderNotifier.same(order, MailBarOrderNotifier.rightHand), isTrue);
  });

  test('под правую руку — зеркально', () {
    expect(MailBarOrderNotifier.leftHand, MailBarOrderNotifier.rightHand.reversed.toList());
  });

  test('свой порядок запоминается; лишние имена пропускаются, недостающие — в конец', () async {
    final c = await make({
      'mail_bar_order': ['delete', 'reply', 'bogus'],
    });
    final order = c.read(mailBarOrderProvider);
    expect(order.take(2).toList(), [MailBarAction.delete, MailBarAction.reply]);
    expect(order.toSet(), MailBarAction.values.toSet());
    expect(order.length, MailBarAction.values.length);
    // Перетаскивание: «Удалить» — после «Ответить».
    await c.read(mailBarOrderProvider.notifier).move(0, 2);
    expect(c.read(mailBarOrderProvider).take(2).toList(), [MailBarAction.reply, MailBarAction.delete]);
    expect(c.read(sharedPrefsProvider).getStringList('mail_bar_order')!.first, 'reply');
  });

  test('вопрос перед удалением выключается', () async {
    final c = await make({});
    await c.read(confirmMailDeleteProvider.notifier).set(false);
    expect(c.read(confirmMailDeleteProvider), isFalse);
    expect(c.read(sharedPrefsProvider).getBool('mail_confirm_delete'), isFalse);
  });
}

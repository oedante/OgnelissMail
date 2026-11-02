// Блокировка и чистка по отправителю (1.10.x): шаблоны, хранение, замена
// правил одного отправителя.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/rules/sender_rules_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('шаблон отправителя', () {
    SenderRule rule(String p) => SenderRule(id: 'x', pattern: p, action: SenderAction.block, createdAt: DateTime(2026));

    test('адрес — только он', () {
      final r = rule('news@shop.example');
      expect(r.matches('News@Shop.example'), isTrue);
      expect(r.matches('other@shop.example'), isFalse);
      expect(r.isDomain, isFalse);
      expect(r.label, 'news@shop.example');
    });

    test('домен — он и поддомены, но не похожие', () {
      final r = rule('shop.example');
      expect(r.matches('a@shop.example'), isTrue);
      expect(r.matches('b@mail.shop.example'), isTrue);
      expect(r.matches('c@notshop.example'), isFalse);
      expect(r.isDomain, isTrue);
      expect(r.label, '@shop.example');
    });
  });

  test('блокировка, разблокировка и хранение', () async {
    final c = await _container();
    final n = c.read(senderRulesProvider.notifier);
    n.add('@Spam.Example', SenderAction.block);
    expect(n.blockFor('x@spam.example'), isNotNull);
    expect(n.blockFor('x@ham.example'), isNull);
    // Повтор того же правила — не дубль.
    n.add('spam.example', SenderAction.block);
    expect(c.read(senderRulesProvider), hasLength(1));
    // Блокировка и чистка одного отправителя уживаются.
    n.add('spam.example', SenderAction.keepLatest, accountId: 'a1');
    expect(c.read(senderRulesProvider), hasLength(2));

    // Прочитать заново с диска (как фоновая проверка).
    final again = await _container({
      SenderRulesNotifier.key: (await SharedPreferences.getInstance()).getString(SenderRulesNotifier.key)!,
    });
    final rules = again.read(senderRulesProvider);
    expect(rules.map((r) => r.action), containsAll([SenderAction.block, SenderAction.keepLatest]));
    expect(rules.firstWhere((r) => r.action == SenderAction.keepLatest).accountId, 'a1');

    n.unblock('x@spam.example');
    expect(n.blockFor('x@spam.example'), isNull);
    expect(c.read(senderRulesProvider).single.action, SenderAction.keepLatest);
  });

  test('правило ящика — только для него', () async {
    final c = await _container();
    final n = c.read(senderRulesProvider.notifier);
    n.add('a@b.example', SenderAction.block, accountId: 'a1');
    expect(n.blockFor('a@b.example', accountId: 'a1'), isNotNull);
    expect(n.blockFor('a@b.example', accountId: 'a2'), isNull);
  });

  test('повреждённая запись не роняет список', () async {
    final c = await _container({
      SenderRulesNotifier.key: '[{"pattern":"ok@x.example","action":"olderThan","days":30},'
          '{"pattern":"","action":"block"},{"pattern":"y@x.example","action":"unknown"}]',
    });
    final rules = c.read(senderRulesProvider);
    expect(rules, hasLength(1));
    expect(rules.single.days, 30);
  });

  test('домены общих почтовых служб — блокировать только адрес', () {
    expect(publicMailDomains, containsAll(['gmail.com', 'yandex.ru', 'mail.ru', 'outlook.com']));
    expect(publicMailDomains.contains('acmegroup.example'), isFalse);
  });
}

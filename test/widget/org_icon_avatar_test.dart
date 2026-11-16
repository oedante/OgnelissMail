// Иконки организаций (2.6.1): в «Спаме» и у похожих на бренды доменов —
// только буква (просьба владельца 16.11.2026: «отключить у спама всегда»).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/bimi/org_icon.dart';
import 'package:ogneliss/widgets/common/bimi_avatar.dart';

const _auth = 'mail-nwsmtp-mxfront-1; dkim=pass header.d=sberbank.ru';

void main() {
  test('похожие на бренд, punycode и кириллица — без иконки; сам бренд и его поддомен — можно', () {
    expect(orgIconSuspiciousDomain('info@sberbank-secure.ru'), isTrue);
    expect(orgIconSuspiciousDomain('service@paypa1.com'), isTrue);
    expect(orgIconSuspiciousDomain('a@xn--80aswg.xn--p1ai'), isTrue);
    expect(orgIconSuspiciousDomain('a@сбербанк.рф'), isTrue);
    expect(orgIconSuspiciousDomain('info@sberbank.ru'), isFalse);
    expect(orgIconSuspiciousDomain('news@news.sberbank.ru'), isFalse);
    expect(orgIconSuspiciousDomain('shop@ozon.ru'), isFalse);
  });

  Future<void> pump(WidgetTester t, {required String folder, String email = 'info@sberbank.ru', Set<String>? junk}) async {
    var asked = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        junkFoldersProvider.overrideWith((ref) => Stream.value(junk ?? {'a1|spam'})),
        bimiOwnServersProvider.overrideWithValue({'yandex.net', 'yandex.ru'}),
        siteIconOwnServersProvider.overrideWithValue({'yandex.net', 'yandex.ru'}),
        orgIconProvider.overrideWith((ref, k) async {
          asked++;
          return (svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><rect width="1" height="1"/></svg>', png: null);
        }),
      ],
      child: MaterialApp(
        home: BimiAvatar(
          email: email,
          authResults: _auth,
          folder: (account: 'a1', folder: folder),
          radius: 20,
          fallback: const Text('S', key: Key('letter')),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    addTearDown(() => expect(asked, folder == 'spam' || email != 'info@sberbank.ru' ? 0 : greaterThan(0)));
  }

  testWidgets('«Входящие» — логотип', (t) async {
    await pump(t, folder: 'inbox');
    expect(find.byKey(const Key('letter')), findsNothing);
  });

  testWidgets('«Спам» — только буква и никаких запросов', (t) async {
    await pump(t, folder: 'spam');
    expect(find.byKey(const Key('letter')), findsOneWidget);
  });

  testWidgets('похожий на бренд домен — только буква', (t) async {
    await pump(t, folder: 'inbox', email: 'info@sberbank-secure.ru');
    expect(find.byKey(const Key('letter')), findsOneWidget);
  });
}

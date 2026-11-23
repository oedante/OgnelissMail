// Фото адресатов того же размера, что фото отправителя (2.7.2, замечание
// владельца 23.11.2026: «фото контакта и фото отправителя разные по
// размеру» — в редакторе письма и в полученном письме).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/features/compose/screens/compose_screen.dart' show recipientAvatarRadius;
import 'package:ogneliss/features/mail/widgets/mail_header.dart' show kMailFaceRadius;
import 'package:ogneliss/widgets/common/account_avatar.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';

void main() {
  testWidgets('редактор: фото адресата = фото ящика в строке «От» (с кольцом)', (t) async {
    final acc = AccountModel(
      id: 'a',
      type: AccountType.imap,
      email: 'me@example.com',
      displayName: 'Я',
      username: 'me@example.com',
      createdAt: DateTime(2026),
    );
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            AccountAvatar(key: const ValueKey('from'), account: acc),
            const HeroEmailAvatar(
              key: ValueKey('to'),
              emailId: 'x',
              initial: 'К',
              color: Colors.blue,
              email: 'k@example.com',
              radius: recipientAvatarRadius,
              hero: false,
            ),
          ]),
        ),
      ),
    ));
    await t.pump();
    final from = t.getSize(find.byKey(const ValueKey('from')));
    final to = t.getSize(find.byKey(const ValueKey('to')));
    expect(to, from);
  });

  test('полученное письмо: адресаты — радиусом отправителя', () {
    expect(kMailFaceRadius, 16);
    expect(recipientAvatarRadius, 16);
  });
}

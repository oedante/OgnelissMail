// Фото людей читаются из базы двумя столбцами — адрес и фото (план
// 08.11.2026 п. 3): карта та же, что и раньше, со строками целиком.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';

void main() {
  test('контакт и ящик с фото — в карте по адресу; ящик важнее контакта', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'Me@Example.com', displayName: 'Я', username: 'me',
          createdAt: DateTime(2026, 1, 1), avatarUrl: const Value('data:image/png;base64,QUFB')));
    await db.into(db.contacts).insert(ContactsCompanion.insert(
          id: 'c1', accountId: const Value('a1'), email: 'Boss@Example.com', displayName: 'Начальник',
          avatarUrl: const Value('data:image/png;base64,QkJC')));
    await db.into(db.contacts).insert(ContactsCompanion.insert(
          id: 'c2', accountId: const Value('a1'), email: 'me@example.com', displayName: 'Я (старое)',
          avatarUrl: const Value('data:image/png;base64,T0xE')));
    await db.into(db.contacts).insert(ContactsCompanion.insert(
          id: 'c3', accountId: const Value('a1'), email: 'nophoto@example.com', displayName: 'Без фото'));
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final sub = c.listen(personPhotosProvider, (_, __) {});
    addTearDown(sub.close);
    final map = await c.read(personPhotosProvider.future);
    expect(map['boss@example.com'], 'data:image/png;base64,QkJC');
    expect(map['me@example.com'], 'data:image/png;base64,QUFB');
    expect(map.containsKey('nophoto@example.com'), isFalse);
  });
}

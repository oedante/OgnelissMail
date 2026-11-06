// VIP из переписки (1.14.0, замечание владельца 06.11.2026: «не все контакты
// со звёздочкой добавляются в VIP»): собранные из писем адреса (без ящика)
// попадают в список, если они VIP или закреплены, — иначе, как раньше, нет.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/contacts/screens/contacts_screen.dart';

void main() {
  test('область: контакты ящика, VIP и закреплённые из переписки', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    Future<void> add(String id, String? acc, String email, String name) => db.into(db.contacts).insert(
        ContactsCompanion.insert(id: id, email: email, displayName: name, accountId: Value(acc)));
    await add('1', 'a1', 'colleague@yamalspg.ru', 'Коллега');
    await add('2', null, 'T.Vasilieva@yamalspg.ru', 'Васильева Тамара Александровна');
    await add('3', null, 'random@example.com', 'Из переписки');
    await add('4', null, 'pinned@example.com', 'Закреплённый');
    await add('5', 'a2', 'other@example.com', 'Другой ящик');

    final q = db.select(db.contacts)
      ..where((c) => contactsScopeFilter(c, ['a1'],
          vipLower: ['t.vasilieva@yamalspg.ru'], pinnedNoAccount: ['4']));
    final names = (await q.get()).map((c) => c.displayName).toSet();
    expect(names, {'Коллега', 'Васильева Тамара Александровна', 'Закреплённый'});
  });
}

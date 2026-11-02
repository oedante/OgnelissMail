// Разделы над буквами в «Контактах» (1.10.3, замечание владельца 03.11.2026:
// «открепление и закрепление контактов не обновляется»): закреплённые и VIP
// — разными разделами, закреплённый VIP — только в «Закреплённых»; после
// «Открепить» VIP переходит в раздел «VIP».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/contacts/contact_prefs.dart';

typedef _C = ({String key, String email, String name});

({List<_C> pinned, List<_C> vip}) _split(List<_C> all, Set<String> pins, Set<String> vip) => splitTopContacts<_C>(
      all,
      key: (c) => c.key,
      email: (c) => c.email,
      name: (c) => c.name,
      pinKeys: pins,
      vipEmails: vip,
    );

void main() {
  final all = <_C>[
    (key: 'a|1', email: 'a.tenishev@novatek.ru', name: 'Тенишев Андрей'),
    (key: 'a|2', email: 'r.ganiev@yamalspg.ru', name: 'Ганиев Руслан'),
    (key: 'a|3', email: 'yu.abramov@yamalspg.ru', name: 'Абрамов Юрий'),
    (key: 'b|1', email: 'A.Tenishev@novatek.ru', name: 'Тенишев (копия)'),
  ];

  test('закреплённый VIP — только в «Закреплённых»; остальные VIP — в «VIP»', () {
    final s = _split(all, {'a|1'}, {'a.tenishev@novatek.ru', 'r.ganiev@yamalspg.ru'});
    expect(s.pinned.map((c) => c.key), ['a|1']);
    // Копия того же адреса из другого ящика — тоже VIP (регистр не важен).
    expect(s.vip.map((c) => c.name), ['Ганиев Руслан', 'Тенишев (копия)']);
  });

  test('«Открепить» у VIP — контакт переходит в раздел «VIP»', () {
    final vip = {'a.tenishev@novatek.ru'};
    final before = _split(all, {'a|1'}, vip);
    final after = _split(all, {}, vip);
    expect(before.pinned.map((c) => c.key), contains('a|1'));
    expect(after.pinned, isEmpty);
    expect(after.vip.map((c) => c.key), containsAll(['a|1', 'b|1']));
  });

  test('закреплённый не-VIP — в «Закреплённых»; по алфавиту', () {
    final s = _split(all, {'a|3', 'a|1'}, {});
    expect(s.pinned.map((c) => c.name), ['Абрамов Юрий', 'Тенишев Андрей']);
    expect(s.vip, isEmpty);
  });
}

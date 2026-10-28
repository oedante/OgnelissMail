// test/unit/contact_groups_test.dart
// Группы рассылки: передача файлом .vcf и приём обратно.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/providers/distribution_groups_provider.dart';
import 'package:ogneliss/features/contacts/screens/contact_groups_screen.dart';

void main() {
  test('группа → .vcf → группа: имя, адреса и имена участников сохраняются', () {
    const g = DistributionGroup(name: 'Ремонты, ТЛ-4', members: [
      GroupMember(email: 'a@example.com', name: 'Никитин Юрий'),
      GroupMember(email: 'b@example.com'),
    ]);
    final vcf = groupToVcf(g);
    expect(vcf, contains('KIND:group'));
    expect(vcf, contains('MEMBER:mailto:a@example.com'));
    final back = groupsFromVcf(vcf).single;
    expect(back.name, 'Ремонты, ТЛ-4');
    expect(back.members.map((m) => m.email), ['a@example.com', 'b@example.com']);
    expect(back.members.first.name, 'Никитин Юрий');
    expect(back.members.last.name, isNull);
  });

  test('файл без KIND:group — одна группа из всех адресов, имя по файлу', () {
    const vcf = 'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Иван\r\nEMAIL:ivan@example.com\r\nEND:VCARD\r\n'
        'BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Пётр\r\nEMAIL;TYPE=work:petr@example.com\r\nEND:VCARD\r\n';
    final g = groupsFromVcf(vcf, fallbackName: 'Отдел').single;
    expect(g.name, 'Отдел');
    expect(g.members.length, 2);
    expect(g.members.first.name, 'Иван');
  });
}

// Данные коллег из адресной книги организации (1.8.0+118).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/contact_model.dart';
import 'package:ogneliss/services/contacts/colleague_directory.dart';

void main() {
  test('коллега — домен организации ящика или поддомен, не общедоступная почта', () {
    expect(isColleagueEmail('i.petrov@corp.example', 'me@corp.example'), isTrue);
    expect(isColleagueEmail('i.petrov@msk.corp.example', 'me@corp.example'), isTrue);
    expect(isColleagueEmail('I.Petrov@CORP.example', 'me@corp.example'), isTrue);
    expect(isColleagueEmail('friend@gmail.com', 'me@gmail.com'), isFalse);
    expect(isColleagueEmail('partner@other.example', 'me@corp.example'), isFalse);
    expect(isColleagueEmail('not-an-address', 'me@corp.example'), isFalse);
  });

  const entry = ContactModel(
    id: 'gal_1',
    email: 'I.Petrov@corp.example',
    displayName: 'Петров Иван',
    company: ' АО «Новое название» ',
    department: 'Отдел продаж',
    jobTitle: '',
    phoneWork: '+7 495 000-00-00',
  );

  test('из адресной книги берутся только непустые поля', () {
    final d = DirectoryOrg.of('i.petrov@corp.example', entry);
    expect(d.email, 'i.petrov@corp.example');
    expect(d.values, {
      'company': 'АО «Новое название»',
      'department': 'Отдел продаж',
      'phoneWork': '+7 495 000-00-00',
    });
    expect(d.pick('company', 'ООО «Старое»'), 'АО «Новое название»');
    // Должности в адресной книге нет — остаётся своя.
    expect(d.pick('jobTitle', 'Менеджер'), 'Менеджер');
  });

  test('сохраняется и читается обратно; испорченная строка — null', () {
    final d = DirectoryOrg.of('i.petrov@corp.example', entry);
    final back = DirectoryOrg.parse(d.toJson())!;
    expect(back.email, d.email);
    expect(back.values, d.values);
    expect(DirectoryOrg.parse(null), isNull);
    expect(DirectoryOrg.parse(''), isNull);
    expect(DirectoryOrg.parse('{'), isNull);
    expect(DirectoryOrg.parse('[1,2]'), isNull);
    // Чужие поля не попадают.
    expect(DirectoryOrg.parse('{"email":"a@b.c","v":{"company":"X","avatarUrl":"y"}}')!.values, {'company': 'X'});
  });

  test('адрес контакта сменился — прежняя сверка не подходит', () {
    final d = DirectoryOrg.of('i.petrov@corp.example', entry);
    expect(d.matches(' I.PETROV@corp.example '), isTrue);
    expect(d.matches('ivan.petrov@corp.example'), isFalse);
  });

  test('меняются только поля, где адресная книга знает другое', () {
    final d = DirectoryOrg.of('i.petrov@corp.example', entry);
    expect(
      d.changesFor({
        'company': 'ООО «Старое название»',
        'department': 'Отдел продаж',
        'jobTitle': 'Менеджер',
        'phoneWork': null,
      }),
      {'company': 'АО «Новое название»', 'phoneWork': '+7 495 000-00-00'},
    );
    expect(
      d.changesFor({'company': 'АО «Новое название»', 'department': 'Отдел продаж', 'phoneWork': '+7 495 000-00-00'}),
      isEmpty,
    );
  });
}

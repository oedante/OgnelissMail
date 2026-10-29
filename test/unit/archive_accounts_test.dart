// 1.8.14: в меню — архив только выбранного ящика (просьба владельца
// 29.10.2026). Ящик архива — тот же по id или по адресу: у копии архива с
// другого устройства id ящиков свои.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/features/archive/archive_providers.dart';
import 'package:ogneliss/services/archive/archive_db.dart';

void main() {
  final me = AccountModel(
    id: 'a1',
    type: AccountType.imap,
    email: 'Oleg@iCloud.com',
    displayName: 'Олег',
    username: 'oleg',
    createdAt: DateTime(2026),
  );

  test('свой ящик — по id и по адресу; чужие — нет', () {
    const all = [
      ArchiveAccountInfo('a1', 'oleg@icloud.com', ''),
      ArchiveAccountInfo('x9', 'oleg@icloud.com', 'с ноутбука'),
      ArchiveAccountInfo('a2', 'boss@corp.ru', ''),
    ];
    expect(archiveAccountsOf(me, all), {'a1', 'x9'});
  });

  test('ящики в адресе экрана', () {
    expect(archiveAccountsParam(null), isNull);
    expect(archiveAccountsParam(''), isNull);
    expect(archiveAccountsParam('a1,x9'), {'a1', 'x9'});
    expect(archiveAccountsQuery({'a1', 'x9'}), 'a1,x9');
  });
}

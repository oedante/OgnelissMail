// Звонок и SMS контактам с полным номером (2.7.5, просьба владельца
// 28.11.2026): SMS — только на полный номер (с кодом страны или города),
// звонок — на полный, если он есть; короткий внутренний — не для SMS.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/contacts/phone_actions.dart';

void main() {
  test('полный номер и короткий внутренний', () {
    expect(PhoneActions.isFull('+7 910 521-40-92'), isTrue);
    expect(PhoneActions.isFull('8 (3496) 39-397'), isTrue);
    expect(PhoneActions.isFull('+44 20 7946 0958'), isTrue);
    expect(PhoneActions.isFull('39-397'), isFalse);
    expect(PhoneActions.isFull('521-40-92'), isFalse);
    expect(PhoneActions.isFull(null), isFalse);
    expect(PhoneActions.isFull('39-397 доб. 1234567890'), isFalse, reason: 'добавочный — не часть номера');
  });

  test('добавочный не уходит в набор', () {
    expect(PhoneActions.clean('+7 (3496) 39-397 доб. 123'), '+7349639397');
    expect(PhoneActions.clean('+1 212 555 0100 ext. 12'), '+12125550100');
  });

  test('номер для звонка и SMS', () {
    expect(PhoneActions.callNumber(['39-397', '+7 967 666-05-12']), '+7 967 666-05-12');
    expect(PhoneActions.callNumber(['39-397', null]), '39-397', reason: 'полного нет — какой есть');
    expect(PhoneActions.callNumber([null, '']), isNull);
    expect(PhoneActions.smsNumber(mobile: '+7 967 666-05-12', work: '+7 910 521-40-92'), '+7 967 666-05-12');
    expect(PhoneActions.smsNumber(mobile: null, work: '+7 910 521-40-92'), '+7 910 521-40-92');
    expect(PhoneActions.smsNumber(mobile: '', work: '39-397'), isNull);
  });
}

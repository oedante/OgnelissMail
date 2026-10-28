// test/unit/department_unit_test.dart
// «Моё подразделение» (1.6.26): поле «Офис» в адресной книге ActiveSync —
// часто кабинет; шире ищем по началу поля до запятой или скобки.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';

void main() {
  test('начало поля «Офис»', () {
    expect(MailEngineService.widerUnit('РММ, к. 12 (3й этаж)'), 'РММ');
    expect(MailEngineService.widerUnit('АБК (2 этаж)'), 'АБК');
    expect(MailEngineService.widerUnit('Отдел ТОиР'), '');
    expect(MailEngineService.widerUnit('Р, к. 1'), '', reason: 'одна буква — слишком широко');
    expect(MailEngineService.widerUnit(', к. 5'), '');
  });
}

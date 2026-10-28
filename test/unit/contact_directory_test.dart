// Контакты из адресной книги (1.6.49): отчество из полного имени.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';

void main() {
  test('«Фамилия Имя Отчество» при известных имени и фамилии', () {
    expect(MailEngineService.middleFromDisplay('Захаров Олег Александрович', 'Олег', 'Захаров'), 'Александрович');
    expect(MailEngineService.middleFromDisplay('захаров олег александрович', 'Олег', 'Захаров'), 'александрович');
    // Порядок другой — не угадываем.
    expect(MailEngineService.middleFromDisplay('Олег Александрович Захаров', 'Олег', 'Захаров'), isNull);
  });

  test('без имени и фамилии — только похожее на отчество', () {
    expect(MailEngineService.middleFromDisplay('Белова Светлана Сергеевна', null, null), 'Сергеевна');
    expect(MailEngineService.middleFromDisplay('Отдел закупок Москва', null, null), isNull);
  });

  test('не три слова или адрес — нет', () {
    expect(MailEngineService.middleFromDisplay('Захаров Олег', 'Олег', 'Захаров'), isNull);
    expect(MailEngineService.middleFromDisplay('oleg@corp.ru x y', null, null), isNull);
    expect(MailEngineService.middleFromDisplay(null, null, null), isNull);
  });
}

// Цвет, важность и приватность встречи уходят на сервер (1.6.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/category_colors.dart';
import 'package:ogneliss/data/models/calendar_event_model.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/ews/ews_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  CalendarEventModel ev({EventPriority p = EventPriority.normal, bool private = false, int? color}) =>
      CalendarEventModel(
        id: 'E', accountId: 'acc', title: 'Планёрка',
        startTime: DateTime(2026, 10, 13, 10), endTime: DateTime(2026, 10, 13, 11),
        priority: p, isPrivate: private, colorValue: color, createdAt: DateTime(2026),
      );

  test('цвет → стандартная категория Outlook и обратно', () {
    final red = CategoryColors.presets.first.color.toARGB32();
    expect(CategoryColors.categoryFor(red, russian: true), 'Красная категория');
    expect(CategoryColors.categoryFor(red, russian: false), 'Red category');
    // Синхронизация вернёт тот же цвет — кружок в редакторе остаётся выбранным.
    expect(CategoryColors.valueOf(['Красная категория']), red);
    expect(CategoryColors.categoryFor(0xFF123456, russian: true), isNull);
  });

  test('EWS CreateItem: приватность, категория и важность', () {
    final xml = EwsXmlBuilder.buildCreateCalendarItem(
        ev(p: EventPriority.high, private: true), category: 'Красная категория');
    expect(xml, contains('<t:Sensitivity>Private</t:Sensitivity>'));
    expect(xml, contains('<t:Categories><t:String>Красная категория</t:String></t:Categories>'));
    expect(xml, contains('<t:Importance>High</t:Importance>'));
    // Порядок types.xsd: Subject, Sensitivity, Body, Categories, Importance.
    expect(xml.indexOf('<t:Sensitivity>'), lessThan(xml.indexOf('<t:Body')));
    expect(xml.indexOf('<t:Categories>'), greaterThan(xml.indexOf('<t:Body')));
    expect(xml.indexOf('<t:Importance>'), greaterThan(xml.indexOf('<t:Categories>')));
  });

  test('EWS UpdateItem: важность и снятие категории', () {
    final xml = EwsXmlBuilder.buildUpdateCalendarItem('E', 'CK', ev(p: EventPriority.low));
    expect(xml, contains('<t:Importance>Low</t:Importance>'));
    expect(xml, contains('<t:DeleteItemField><t:FieldURI FieldURI="item:Categories"/>'));
  });

  test('главный список категорий ящика (CategoryList): разбор и цвета', () async {
    const xml = '<?xml version="1.0"?><categories default="Красная категория" xmlns="CategoryList.xsd">'
        '<category name="Красная категория" color="0" keyboardShortcut="0"/>'
        '<category name="Лиловая категория" color="8"/>'
        '<category name="Праздники" color="9"/>'
        '<category name="Без цвета" color="-1"/>'
        '</categories>';
    final list = EwsService.parseCategoryListXml(xml);
    expect(list.map((c) => c.name), ['Красная категория', 'Лиловая категория', 'Праздники', 'Без цвета']);
    expect(list[2].color, 9);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await CategoryColors.save(prefs, list);
    // Категория «без цвета» не показывается.
    expect(CategoryColors.serverList.map((c) => c.name), ['Красная категория', 'Лиловая категория', 'Праздники']);
    final holiday = CategoryColors.outlookColor(9)!;
    expect(CategoryColors.of(['Праздники']), holiday);
    expect(CategoryColors.categoryFor(holiday.toARGB32(), russian: true), 'Праздники');
    // Список переживает перезапуск.
    CategoryColors.load(prefs);
    expect(CategoryColors.serverList.length, 3);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/greeting_helper.dart';
import 'package:ogneliss/services/mail/greeting_history.dart';

// Строки ru/en/de/fr загружает test/flutter_test_config.dart.
void main() {
  GreetingSet v(List<String> names, List<String> emails, {String lang = 'ru', Set<String> own = const {}}) =>
      GreetingHelper.variants(names: names, emails: emails, appLang: lang, ownDomains: own);

  group('варианты приветствия', () {
    test('ФИО — по имени-отчеству, короткое — без «Добрый день»', () {
      final s = v(['Кузнецов Максим Геннадьевич'], ['m.kuznetsov@example.com']);
      expect(s.full, 'Добрый день, Максим Геннадьевич,');
      expect(s.short, 'Максим Геннадьевич,');
      expect(s.hello, 'Добрый день!');
      expect(s.text(GreetingVariant.none), '');
    });

    test('несколько адресатов своей организации — «коллеги»', () {
      final s = v(['Иван Петров', ''], ['ivan@corp.example', 'maria@msk.corp.example'], own: {'corp.example'});
      expect(s.full, 'Добрый день, коллеги,');
      expect(s.short, 'Коллеги,');
    });

    test('есть адресат из другой организации — без «коллеги»', () {
      final s = v(['Иван Петров', 'Мария'], ['ivan@corp.example', 'maria@partner.example'], own: {'corp.example'});
      expect(s.full, 'Добрый день!');
      expect(s.short, '');
      // Короткого нет — вместо него полное.
      expect(s.text(GreetingVariant.short), 'Добрый день!');
    });

    test('свой ящик на общей почте — нескольким адресатам без «коллеги»', () {
      final s = v(['Иван', 'Мария'], ['ivan@gmail.com', 'maria@gmail.com'], own: {'gmail.com'});
      expect(s.full, 'Добрый день!');
    });

    test('домены неизвестны — «коллеги», как раньше', () {
      expect(v(['Иван Петров', ''], ['ivan@a.example', 'maria@b.example']).full, 'Добрый день, коллеги,');
    });

    test('только адрес и пустой список — без обращения', () {
      expect(v([''], ['a@b.ru']).full, 'Добрый день!');
      expect(v([], []).full, 'Добрый день!');
      expect(v([''], ['a@b.ru']).short, '');
    });

    test('язык приложения и язык имени', () {
      expect(v(['John Smith'], ['j@b.com'], lang: 'en').full, 'Hello John,');
      expect(v(['John Smith'], ['j@b.com'], lang: 'de').full, 'Guten Tag John,');
      expect(v(['John Smith'], ['j@b.com'], lang: 'fr').full, 'Bonjour John,');
      // Имя кириллицей при английском приложении — по-русски.
      final ru = v(['Петров Иван'], ['i@b.ru'], lang: 'en');
      expect(ru.lang, 'ru');
      expect(ru.full, 'Добрый день, Иван,');
      expect(v(['Иван', 'Мария'], ['i@c.example', 'm@c.example'], lang: 'en', own: {'c.example'}).short, 'Коллеги,');
    });

    test('выбор — без повторов, «без приветствия» последним', () {
      final s = v(['Иван', 'Мария'], ['i@x.example', 'm@y.example'], own: {'x.example'});
      final choices = s.choices.map((c) => c.$1).toList();
      expect(choices, [GreetingVariant.full, GreetingVariant.none]);
      final named = v(['Кузнецов Максим Геннадьевич'], ['m@corp.example']).choices.map((c) => c.$1).toList();
      expect(named, GreetingVariant.values);
    });

    test('образец для настроек', () {
      expect(GreetingHelper.sample('ru'), 'Добрый день, Имя Отчество,');
      expect(GreetingHelper.sample('en', withName: false), 'Hello,');
    });
  });

  group('имя для обращения', () {
    test('пояснение в скобках и «Фамилия Имя»', () {
      expect(GreetingHelper.addressOf(GreetingHelper.cleanName('Петров Иван (ОТК)')), 'Иван');
      expect(GreetingHelper.addressOf(GreetingHelper.cleanName('Smith, John')), 'John');
    });

    test('«Фамилия, Имя Отчество» из адресной книги', () {
      expect(GreetingHelper.addressOf(GreetingHelper.cleanName('Никитин, Юрий Николаевич')),
          'Юрий Николаевич');
    });

    test('язык приветствия по имени', () {
      expect(GreetingHelper.languageFor(['Петров Иван'], 'de'), 'ru');
      expect(GreetingHelper.languageFor(['John'], 'de'), 'de');
      expect(GreetingHelper.languageFor(['Петров Иван'], 'ru'), 'ru');
      expect(GreetingHelper.languageFor([], 'fr_FR'), 'fr');
    });
  });

  // Замечание владельца 14.11.2026: в письме поручения было «Ситников,
  // добрый день!» — одна фамилия. Разбор имени — PersonNameParts.
  group('обращение: имя и отчество в любом порядке, правила языков', () {
    String a(String n, [String lang = 'ru']) => GreetingHelper.addressOf(GreetingHelper.cleanName(n), lang: lang);

    test('русские ФИО', () {
      expect(a('Ситников Дмитрий'), 'Дмитрий');
      expect(a('Дмитрий Ситников'), 'Дмитрий');
      expect(a('Ситников Дмитрий Александрович'), 'Дмитрий Александрович');
      expect(a('Дмитрий Александрович Ситников'), 'Дмитрий Александрович');
      expect(a('Дмитрий Александрович'), 'Дмитрий Александрович');
      expect(a('Ситников, Дмитрий'), 'Дмитрий');
      expect(a('Ситников, Дмитрий Александрович'), 'Дмитрий Александрович');
      expect(a('Пашкевич Анна Сергеевна'), 'Анна Сергеевна', reason: 'фамилия тоже на «-вич»');
      expect(a('Анна Сергеевна Пашкевич'), 'Анна Сергеевна');
      expect(a('Анна Пашкевич'), 'Анна');
      expect(a('Мамедов Эльдар Рашидович'), 'Эльдар Рашидович');
      expect(a('СИТНИКОВ ДМИТРИЙ'), 'Дмитрий');
    });

    test('два слова: имя по списку и по окончанию фамилии', () {
      expect(a('Хабибуллина Зульфия'), 'Зульфия');
      expect(a('Ковалёва Марина'), 'Марина');
      expect(a('Ким Ирина'), 'Ирина', reason: 'Ким — фамилия');
      expect(a('Ли Виктор'), 'Виктор');
      expect(a('Гогия Нино'), 'Нино');
      expect(a('Абвгд Ежзик'), 'Абвгд Ежзик', reason: 'не ясно, где имя, — полное имя, а не фамилия');
    });

    test('одно слово, пусто, организация', () {
      expect(a('Дмитрий'), 'Дмитрий');
      expect(a(''), '');
      expect(a('Служба поддержки'), '');
      expect(a('ООО «Ромашка»'), '');
    });

    test('латиница: имя первым, транслитерация русских имён', () {
      expect(a('John Smith', 'en'), 'John');
      expect(a('Smith, John', 'en'), 'John');
      expect(a('Sitnikov Dmitry', 'en'), 'Dmitry');
      expect(a('Dmitriy Sitnikov', 'en'), 'Dmitriy');
      expect(a('Petrov Alexander', 'de'), 'Alexander');
      expect(a('Ivanova Natalia', 'fr'), 'Natalia');
      expect(a('Kuznetsov Sergei', 'en'), 'Sergei');
      expect(a('Sitnikov Dmitry Aleksandrovich'), 'Dmitry Aleksandrovich');
      expect(a('Sitnikov Dmitry Aleksandrovich', 'de'), 'Dmitry');
    });

    test('порядок «фамилия — имя»: венгерский, вьетнамский', () {
      expect(a('Szabó Péter', 'hu'), 'Péter');
      expect(a('Nguyễn Văn An', 'en'), 'An');
      expect(a('Trần Bình', 'vi'), 'Bình');
    });

    test('японский, корейский, китайский', () {
      expect(a('山田 太郎', 'ja'), '山田', reason: 'фамилия + 様');
      expect(a('山田太郎', 'ja'), '山田太郎');
      expect(a('Dmitry Sitnikov', 'ja'), 'Dmitry');
      expect(a('홍 길동', 'ko'), '홍길동');
      expect(a('王 伟', 'zh'), '王伟');
    });

    test('приветствие целиком; язык письма задан — по нему, а не по имени', () {
      expect(v(['Ситников Дмитрий Александрович'], ['s@corp.example']).full, 'Добрый день, Дмитрий Александрович,');
      expect(v(['Ситников Дмитрий'], ['s@corp.example']).full, 'Добрый день, Дмитрий,');
      final en = GreetingHelper.variants(names: ['Ситников Дмитрий'], emails: ['s@corp.example'], appLang: 'en', lang: 'en');
      expect(en.full, 'Hello Дмитрий,');
    });
  });

  test('Message-ID из References — со скобками и без', () {
    expect(GreetingHistory.messageIds('<a@b.c> <d@e.f>'), {'a@b.c', '<a@b.c>', 'd@e.f', '<d@e.f>'});
    expect(GreetingHistory.messageIds(null), isEmpty);
    expect(GreetingHistory.messageIds('5:12'), isEmpty);
  });
}

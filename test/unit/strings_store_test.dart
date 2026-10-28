// 1.7.3: строки интерфейса — файлами XML (формат strings.xml Android):
// экранирование, пробелы, множественное число по правилам языка, подмена
// английским.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/l10n/strings_store.dart';

void main() {
  group('разбор', () {
    test('экранирование Android и сущности XML', () {
      final s = StringsStore.parse('''<?xml version="1.0" encoding="utf-8"?>
<!-- комментарий <string name="x">не строка</string> -->
<resources>
    <string name="a">Don\\'t say \\"hi\\" &amp; &lt;go&gt;</string>
    <string name="b">Line 1\\nLine 2\\tTab \\\\ back</string>
    <string name="c">"  spaced  "</string>
    <string name="d">  collapsed
        text  </string>
    <string name="e">\\@user \\u00A9</string>
    <string name="empty"/>
</resources>''');
      expect(s.strings['a'], 'Don\'t say "hi" & <go>');
      expect(s.strings['b'], 'Line 1\nLine 2\tTab \\ back');
      expect(s.strings['c'], '  spaced  ');
      expect(s.strings['d'], 'collapsed text');
      expect(s.strings['e'], '@user ©');
      expect(s.strings['empty'], '');
      expect(s.strings.containsKey('x'), isFalse);
    });

    test('множественное число', () {
      final s = StringsStore.parse('''<resources>
  <plurals name="files">
    <item quantity="one">{n} файл</item>
    <item quantity="few">{n} файла</item>
    <item quantity="many">{n} файлов</item>
    <item quantity="other">{n} файла</item>
  </plurals>
</resources>''');
      final f = s.plurals['files']!;
      expect(StringsStore.pick('ru', f, 1), '{n} файл');
      expect(StringsStore.pick('ru', f, 3), '{n} файла');
      expect(StringsStore.pick('ru', f, 11), '{n} файлов');
      expect(StringsStore.pick('ru', f, 21), '{n} файл');
      expect(StringsStore.pick('ru', f, 112), '{n} файлов');
    });
  });

  group('правила CLDR', () {
    test('польский: 21 — many, 22 — few', () {
      expect(StringsStore.pluralCategory('pl', 1), 'one');
      expect(StringsStore.pluralCategory('pl', 21), 'many');
      expect(StringsStore.pluralCategory('pl', 22), 'few');
      expect(StringsStore.pluralCategory('pl', 12), 'many');
    });

    test('арабский, словенский, латышский, румынский', () {
      expect([0, 1, 2, 5, 11, 100].map((n) => StringsStore.pluralCategory('ar', n)),
          ['zero', 'one', 'two', 'few', 'many', 'other']);
      expect([1, 2, 3, 5, 101, 102].map((n) => StringsStore.pluralCategory('sl', n)),
          ['one', 'two', 'few', 'other', 'one', 'two']);
      expect([0, 1, 11, 21, 2].map((n) => StringsStore.pluralCategory('lv', n)), ['zero', 'one', 'zero', 'one', 'other']);
      expect([1, 0, 5, 19, 20, 101].map((n) => StringsStore.pluralCategory('ro', n)),
          ['one', 'few', 'few', 'few', 'other', 'few']);
    });

    test('французский и португальский: 0 — единственное', () {
      expect(StringsStore.pluralCategory('fr', 0), 'one');
      expect(StringsStore.pluralCategory('pt', 0), 'one');
      expect(StringsStore.pluralCategory('en', 0), 'other');
      expect(StringsStore.pluralCategory('ja', 1), 'other');
    });
  });

  group('AppLocalizations', () {
    test('строки и формы числа из файлов', () {
      final ru = AppLocalizations(const Locale('ru'));
      final en = AppLocalizations(const Locale('en'));
      expect(ru.tr('caTitle'), 'Центры сертификации');
      expect(en.tr('caTitle'), 'Certificate authorities');
      expect(ru.plural('attachmentsCountN', 5), '5 вложений');
      expect(ru.plural('attachmentsCountN', 22), '22 вложения');
      expect(en.plural('attachmentsCountN', 1), '1 attachment');
    });

    test('нет строки в языке — английская, нет и её — ключ', () {
      expect(AppLocalizations(const Locale('xx')).tr('caTitle'), 'Certificate authorities');
      expect(AppLocalizations(const Locale('ru')).tr('noSuchKey_123'), 'noSuchKey_123');
    });

    test('список языков — по файлам', () {
      expect(AppLocalizations.supportedCodes, containsAll(['ru', 'en', 'de', 'fr']));
      expect(AppLocalizations.languageOf('ru')?.name, 'Русский');
    });
  });
}

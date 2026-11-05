// Предпросмотр .txt и .md (1.14.0, просьба владельца 05.11.2026): кодировка
// по содержимому, читаемый текст, Markdown документом.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/html_sanitizer.dart';
import 'package:ogneliss/core/utils/charset_handler.dart';
import 'package:ogneliss/services/documents/text_doc_reader.dart';

const _ru = 'Добрый день! Высылаю отчёт за октябрь, прошу проверить цифры и ответить до пятницы.';

/// Байты [s] в однобайтовой кодировке [cp] (обратная таблица декодера).
Uint8List _encode(String s, String cp) {
  final back = <int, int>{};
  for (var b = 0x80; b < 0x100; b++) {
    final ch = cp == 'cp866' ? _cp866(b) : CharsetHandler.decode(Uint8List.fromList([b]), cp).codeUnitAt(0);
    back.putIfAbsent(ch, () => b);
  }
  return Uint8List.fromList([for (final c in s.codeUnits) c < 0x80 ? c : back[c]!]);
}

int _cp866(int b) {
  if (b >= 0x80 && b <= 0xAF) return 0x410 + (b - 0x80);
  if (b >= 0xE0 && b <= 0xEF) return 0x440 + (b - 0xE0);
  if (b == 0xF0) return 0x401;
  if (b == 0xF1) return 0x451;
  return -b; // остальное в тексте теста не встречается
}

void main() {
  group('кодировка', () {
    test('UTF-8, с меткой и без', () {
      expect(TextDocReader.decode(Uint8List.fromList(utf8.encode(_ru))), _ru);
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(_ru)]);
      expect(TextDocReader.decode(bom).replaceFirst('﻿', ''), _ru);
    });

    test('UTF-16 с меткой', () {
      final units = _ru.codeUnits;
      final b = BytesBuilder()..add([0xFF, 0xFE]);
      for (final u in units) {
        b.add([u & 0xFF, u >> 8]);
      }
      expect(TextDocReader.decode(b.toBytes()).replaceFirst('﻿', ''), _ru);
    });

    for (final cp in ['windows-1251', 'koi8-r', 'cp866']) {
      test('русский текст в $cp — при английском языке приложения', () {
        expect(TextDocReader.decode(_encode(_ru, cp), lang: 'en'), _ru);
      });
      test('русский текст в $cp — при русском языке приложения', () {
        expect(TextDocReader.decode(_encode(_ru, cp), lang: 'ru'), _ru);
      });
    }

    test('западный текст в Windows-1252 не становится кириллицей', () {
      const de = 'Viele Grüße aus München, schönes Wochenende!';
      final bytes = Uint8List.fromList(latin1.encode(de));
      expect(TextDocReader.decode(bytes, lang: 'en'), de);
      expect(TextDocReader.decode(bytes, lang: 'ru'), de, reason: 'и при русском языке приложения');
    });

    test('оценка: правильная кодировка выше неправильной', () {
      final good = TextDocReader.cyrillicScore(_ru);
      final koiAs1251 = TextDocReader.cyrillicScore(CharsetHandler.decode(_encode(_ru, 'koi8-r'), 'windows-1251'));
      expect(good, greaterThan(koiAs1251));
    });
  });

  group('простой текст', () {
    test('абзацы, переносы строк, отступы, ссылки, экранирование', () {
      final html = TextDocReader.plainHtml(
          'Привет!\nВторая строка.\n\n\n  Отступ и <script>x</script>\nСсылка: https://example.com/a?b=1&c=2.\n');
      expect(html, startsWith('<p>Привет!<br>Вторая строка.</p><p>'));
      expect(html, contains('&nbsp;&nbsp;Отступ'));
      expect(html, contains('&lt;script&gt;'));
      expect(html, isNot(contains('<script>')));
      expect(html, contains('<a href="https://example.com/a?b=1&amp;c=2">https://example.com/a?b=1&amp;c=2</a>.'));
    });

    test('таблица из пробелов — моноширинным блоком', () {
      const t = 'Товар        Кол-во   Цена\n'
          'Бумага A4       10    350\n'
          'Ручки           25     40\n'
          'Итого                 390\n';
      expect(TextDocReader.looksTabular(t), isTrue);
      expect(TextDocReader.plainHtml(t), startsWith('<pre>'));
      expect(TextDocReader.looksTabular('Обычное письмо.\nВторая строка.\n\nС уважением, Иван'), isFalse);
    });

    test('пустой файл — пустой документ', () {
      final doc = TextDocReader.read(Uint8List.fromList(utf8.encode('  \n\n ')), markdown: false);
      expect(doc.isEmpty, isTrue);
    });
  });

  group('Markdown', () {
    test('заголовки, выделение, списки, таблица, код, цитата', () {
      final html = TextDocReader.markdownHtml('''
# Отчёт

Текст **жирный**, *курсив*, ~~зачёркнутый~~ и `код`.

- первый
- второй

| Месяц | Сумма |
|-------|------:|
| Октябрь | 1 000 |

```dart
void main() {}
```

> Цитата
''');
      expect(html, contains('<h1'));
      expect(html, contains('Отчёт</h1>'));
      expect(html, contains('<strong>жирный</strong>'));
      expect(html, contains('<em>курсив</em>'));
      expect(html, contains('<del>зачёркнутый</del>'));
      expect(html, contains('<code>код</code>'));
      expect(html, contains('<li>первый</li>'));
      expect(html, contains('<table>'));
      expect(html, contains('<td'));
      expect(html, contains('<pre><code'));
      expect(html, contains('<blockquote>'));
    });

    test('списки задач — знаками, картинки из интернета — ссылкой', () {
      final html = TextDocReader.markdownHtml('- [x] готово\n- [ ] осталось\n\n![Схема](https://tracker.example/p.png)\n');
      expect(html, contains('☑ '));
      expect(html, contains('☐ '));
      expect(html, isNot(contains('<input')));
      expect(html, isNot(contains('<img')));
      expect(html, contains('<a href="https://tracker.example/p.png">🖼 Схема</a>'));
    });

    test('встроенная картинка data: остаётся', () {
      final html = TextDocReader.markdownHtml('![x](data:image/png;base64,iVBORw0KGgo=)');
      expect(html, contains('<img'));
    });

    test('HTML внутри Markdown проходит санитайзер', () {
      final html = HtmlSanitizer.sanitizeKeepingStyles(
          TextDocReader.markdownHtml('Текст <script>alert(1)</script> <a href="javascript:alert(1)">ссылка</a>'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('javascript:')));
      expect(html, contains('Текст'));
    });
  });

  group('файл', () {
    test('Markdown по расширению и типу; .txt — простым текстом', () {
      expect(TextDocReader.handles('README.md'), isTrue);
      expect(TextDocReader.handles('notes.markdown'), isTrue);
      expect(TextDocReader.handles('письмо.TXT'), isTrue);
      expect(TextDocReader.handles('log.log'), isFalse);
      expect(TextDocReader.isMarkdown('README', mimeType: 'text/markdown; charset=utf-8'), isTrue);
      expect(TextDocReader.isMarkdown('a.txt'), isFalse);
    });

    test('большой файл — начало и отметка «показано только начало»', () async {
      final dir = await Directory.systemTemp.createTemp('textdoc');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/big.txt');
      final line = '${'Строка текста ' * 8}\n';
      final sb = StringBuffer();
      while (sb.length < TextDocReader.maxBytes) {
        sb.write(line);
      }
      await f.writeAsString(sb.toString());
      final doc = await TextDocReader.readFile(f.path, 'big.txt');
      expect(doc.truncated, isTrue);
      expect(doc.html, contains('Строка текста'));
      expect(doc.html, isNot(contains('�')), reason: 'обрезанный знак UTF-8 не превращается в «�»');
    });

    test('Markdown из файла в Windows-1251', () async {
      final dir = await Directory.systemTemp.createTemp('textdoc');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/readme.md');
      await f.writeAsBytes(_encode('# Заголовок\n\nТекст абзаца по-русски, без ошибок кодировки.', 'windows-1251'));
      final doc = await TextDocReader.readFile(f.path, 'readme.md');
      expect(doc.html, contains('Заголовок</h1>'));
      expect(doc.html, contains('Текст абзаца по-русски'));
    });
  });
}

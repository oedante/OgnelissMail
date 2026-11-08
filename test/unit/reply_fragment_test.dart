// «Ответить с цитатой» (2.0.0, план 08.11.2026): в цитате — только
// выделенный фрагмент, с абзацами и переносами, экранированный.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/reply_builder.dart';

void main() {
  test('абзацы, переносы строк и экранирование', () {
    final html = ReplyBuilder.fragmentBody('Срок — пятница.\nБюджет <100>.\n\n  Второй абзац & вопрос  ');
    expect(html, '<p>Срок — пятница.<br>Бюджет &lt;100&gt;.</p><p>Второй абзац &amp; вопрос</p>');
  });

  test('пустой фрагмент — пустая цитата', () {
    expect(ReplyBuilder.fragmentBody('  \n\n '), '');
  });
}

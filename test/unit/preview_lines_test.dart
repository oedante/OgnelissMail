// test/unit/preview_lines_test.dart
// 1.6.31: строки превью — переносы письма сохраняются, пустые строки
// пропускаются (пример владельца).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/mail_body_processor.dart';
import 'package:ogneliss/core/utils/text_safe.dart';
import 'package:ogneliss/features/mail/widgets/preview_text.dart';

void main() {
  const letter = 'Добрый день, Олег Андреевич,\r\n\r\nХочу Вас уведомить....\n\n   \nПрилагаю документы...';

  test('две и три строки', () {
    expect(previewLinesOf(letter, 2), ['Добрый день, Олег Андреевич,', 'Хочу Вас уведомить....']);
    expect(previewLinesOf(letter, 3),
        ['Добрый день, Олег Андреевич,', 'Хочу Вас уведомить....', 'Прилагаю документы...']);
  });

  test('превью для базы — без пустых строк, с переносами', () {
    expect(multilinePreviewOf(letter),
        'Добрый день, Олег Андреевич,\nХочу Вас уведомить....\nПрилагаю документы...');
    expect(multilinePreviewOf(' \n\t '), isNull);
  });

  test('HTML Outlook: абзацы — строками, пустой абзац &nbsp; — пропуск', () {
    const html = '<html><head><style>p{}</style></head><body>'
        '<p class=MsoNormal>Добрый день,<o:p></o:p></p><p class=MsoNormal><o:p>&nbsp;</o:p></p>'
        '<p class=MsoNormal>Прошу ознакомиться<br>со статусами</p></body></html>';
    expect(multilinePreviewOf(MailBodyProcessor.htmlToPreviewText(html)),
        'Добрый день,\nПрошу ознакомиться\nсо статусами');
  });
}

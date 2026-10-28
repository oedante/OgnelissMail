// 1.8.0 (118): ответ и пересылка ActiveSync силами сервера (SmartReply,
// SmartForward) — сервер дописывает исходное письмо без шапки, поэтому
// шапку «От / Отправлено / Кому / Тема» под линией и пустую строку перед ней
// добавляет приложение (замечание 27.10.2026: письма сливались под подписью).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';

void main() {
  test('без шапки — текст как есть', () {
    expect(MailEngineService.withEasQuoteHeader('<div>Текст</div>', null), '<div>Текст</div>');
    expect(MailEngineService.withEasQuoteHeader('<div>Текст</div>', ''), '<div>Текст</div>');
  });

  test('шапка — после пустой строки, в самом конце', () {
    const header = '<div id="divRplyFwdMsg" style="border-top:solid #E1E1E1 1.0pt">От: Иван</div>';
    final r = MailEngineService.withEasQuoteHeader('<div>Текст</div><div>Подпись</div>', header);
    expect(r, '<div>Текст</div><div>Подпись</div><div><br></div>$header');
    expect(r.endsWith(header), isTrue);
  });
}

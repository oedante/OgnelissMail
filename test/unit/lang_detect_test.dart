// Определение языка без движка платформы (перевод на Windows, 2.2.0):
// алфавит, частые слова, свои буквы языка.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/translation/lang_detect.dart';

void main() {
  void sure(String text, String lang) {
    final r = detectLanguageHeuristic(text);
    expect(r?.lang, lang, reason: text);
    expect(r?.confident, isTrue, reason: text);
  }

  test('латиница: частые слова и буквы', () {
    sure('Hello Anna, thank you for the report. We will send the contract to you on Monday, please check it.', 'en');
    sure('Hallo Anna, vielen Dank für den Bericht. Wir schicken Ihnen den Vertrag am Montag, bitte prüfen Sie ihn.',
        'de');
    sure('Bonjour Anna, merci pour le rapport. Nous vous enverrons le contrat lundi, merci de le vérifier.', 'fr');
    sure('Hola Ana, gracias por el informe. Le enviaremos el contrato el lunes, por favor revíselo con su equipo.',
        'es');
    sure('Olá Ana, obrigado pelo relatório. Vamos enviar o contrato na segunda-feira, você pode verificar? Não é urgente.',
        'pt');
    sure('Ciao Anna, grazie per il rapporto. Ti mandiamo il contratto lunedì, per favore controllalo con il team.',
        'it');
    sure('Dzień dobry, dziękuję za raport. Umowę wyślemy w poniedziałek, proszę ją sprawdzić. Pozdrawiam serdecznie.',
        'pl');
    sure('Dobrý den, děkuji za zprávu. Smlouvu pošleme v pondělí, prosím zkontrolujte ji. Jsme připraveni.', 'cs');
    sure('Hallo Anna, bedankt voor het rapport. We sturen u het contract op maandag, het is niet dringend.', 'nl');
    sure('Hej Anna, tack för rapporten. Vi skickar avtalet till dig på måndag, det är inte bråttom.', 'sv');
  });

  test('кириллица: русский, украинский, болгарский', () {
    sure('Добрый день! Спасибо за отчёт, мы отправим договор в понедельник. Это не срочно.', 'ru');
    sure('Добрий день! Дякую за звіт, ми надішлемо договір у понеділок. Це не терміново, вітаю.', 'uk');
    sure('Здравейте! Благодаря за отчета, ще изпратим договора в понеделник. Това не е спешно.', 'bg');
  });

  test('свои алфавиты', () {
    sure('こんにちは。報告書をありがとうございます。月曜日に契約書をお送りします。', 'ja');
    sure('您好，感谢您的报告。我们将在星期一把合同发给您，请您查收确认。', 'zh');
    sure('안녕하세요. 보고서 감사합니다. 월요일에 계약서를 보내드리겠습니다.', 'ko');
    sure('مرحبا، شكرا على التقرير. سنرسل العقد يوم الاثنين، يرجى مراجعته.', 'ar');
    sure('سلام، از گزارش شما متشکرم. قرارداد را دوشنبه می‌فرستیم، لطفاً آن را بررسی کنید.', 'fa');
    sure('שלום, תודה על הדוח. נשלח את החוזה ביום שני, אנא בדקו אותו.', 'he');
    sure('Γεια σας, ευχαριστώ για την αναφορά. Θα στείλουμε τη σύμβαση τη Δευτέρα.', 'el');
    sure('สวัสดีครับ ขอบคุณสำหรับรายงาน เราจะส่งสัญญาให้ในวันจันทร์', 'th');
  });

  test('ссылки и адреса не считаются: русское письмо с английской ссылкой', () {
    sure('Посмотрите, пожалуйста, документ по ссылке https://example.com/the-best-report-for-you и напишите ivan@example.com',
        'ru');
  });

  test('короткий текст и два алфавита поровну — не уверен', () {
    expect(detectLanguageHeuristic('Ok')?.confident, isNot(true));
    expect(detectLanguageHeuristic('Привет')?.confident, isFalse);
    final mixed = detectLanguageHeuristic('Спасибо большое за помощь. Thank you very much for your help.');
    expect(mixed?.confident, isFalse);
    expect(detectLanguageHeuristic('12345 — 678'), isNull);
  });

  test('норвежский — код «no» (как у normalizeLang)', () {
    final r = detectLanguageHeuristic('Hei Anna, takk for rapporten. Vi sender avtalen til deg på mandag, det er ikke så viktig.');
    expect(r?.lang, 'no');
  });
}

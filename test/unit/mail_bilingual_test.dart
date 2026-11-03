// Перевод входящего письма (1.10.5, просьба владельца 03.11.2026: «при
// переводе тему письма тоже нужно переводить. И оставлять два варианта,
// если пользователь это выбирает»): тема без «RE:/FW:», «оставить оба» —
// тема второй строкой, текст — второй под линией; переписка (цитата) — после
// обоих ответов, и свёрнутое письмо показывает оба.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_splitter.dart';
import 'package:ogneliss/services/translation/translation_prefs.dart';
import 'package:ogneliss/services/translation/translation_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('тема: приставки ответа и пересылки не переводятся', () {
    expect(MailBilingual.splitSubject('RE: FW: Selected for the Hub'), ('RE: FW: ', 'Selected for the Hub'));
    expect(MailBilingual.splitSubject('Отв[2]: Пер: Документы'), ('Отв[2]: Пер: ', 'Документы'));
    expect(MailBilingual.splitSubject('Report'), ('', 'Report'));
    expect(MailBilingual.splitSubject('RE: '), ('RE: ', ''));
  });

  test('тема по режиму: заменить, сначала оригинал, сначала перевод', () {
    ({String main, String? second}) s(ComposeTranslateMode m, {String? tr = 'RE: Отобран для Hub'}) =>
        MailBilingual.subject(original: 'RE: Selected for the Hub', translated: tr, mode: m);
    expect(s(ComposeTranslateMode.replace), (main: 'RE: Отобран для Hub', second: null));
    expect(s(ComposeTranslateMode.originalFirst), (main: 'RE: Selected for the Hub', second: 'RE: Отобран для Hub'));
    expect(s(ComposeTranslateMode.translationFirst), (main: 'RE: Отобран для Hub', second: 'RE: Selected for the Hub'));
    // Тема не переводилась или перевод тот же — одна тема.
    expect(s(ComposeTranslateMode.originalFirst, tr: null), (main: 'RE: Selected for the Hub', second: null));
    expect(s(ComposeTranslateMode.originalFirst, tr: 'RE: Selected for the Hub').second, isNull);
  });

  test('простой текст: первый, линия с подписью, второй', () {
    expect(MailBilingual.plain('Hello\n', '\nПривет', 'Переведено: английский → русский'),
        'Hello\n\n——— Переведено: английский → русский ———\n\nПривет');
  });

  test('HTML: оба ответа до переписки, переписка — обе после', () {
    String mail(String reply, String from, String quote) => '<html><head><style>p{margin:0}</style></head><body>'
        '<p>$reply</p><div id="divRplyFwdMsg"><b>$from:</b> Ivan N<br><b>Sent:</b> Monday</div>'
        '<p>$quote</p></body></html>';
    final original = mail('Thank you!', 'From', 'Congrats! Your page is up.');
    final translated = mail('Спасибо!', 'От', 'Поздравляем! Ваша страница готова.');
    final out = MailBilingual.html(original, translated, 'Переведено: английский → русский');
    expect(out, contains('p{margin:0}'), reason: 'стили первого документа');
    final iThanks = out.indexOf('Thank you!');
    final iLabel = out.indexOf('Переведено: английский');
    final iSpasibo = out.indexOf('Спасибо!');
    final iCongrats = out.indexOf('Congrats!');
    final iPozdr = out.indexOf('Поздравляем!');
    expect(iThanks < iLabel && iLabel < iSpasibo && iSpasibo < iCongrats && iCongrats < iPozdr, isTrue);
    // Экран письма сворачивает переписку: в свёрнутом — оба ответа.
    final split = splitQuotedHtml(out);
    expect(split.hasQuote, isTrue);
    expect(split.reply, contains('Thank you!'));
    expect(split.reply, contains('Спасибо!'));
    expect(split.reply, isNot(contains('Congrats!')));
    expect(split.quoted, contains('Congrats!'));
    expect(split.quoted, contains('Поздравляем!'));
  });

  test('HTML без переписки: первый, линия, второй', () {
    final out = MailBilingual.html('<p>Hello</p>', '<p>Привет</p>', 'Язык письма: английский');
    expect(out.indexOf('Hello') < out.indexOf('Язык письма') && out.indexOf('Язык письма') < out.indexOf('Привет'),
        isTrue);
    expect(splitQuotedHtml(out).hasQuote, isFalse);
  });

  test('показ перевода по умолчанию — заменить текст', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    expect(TranslationMemory.readMode(p), ComposeTranslateMode.replace);
    expect(TranslationMemory.readMode(null), ComposeTranslateMode.replace);
    await TranslationMemory.setReadMode(p, ComposeTranslateMode.translationFirst);
    expect(TranslationMemory.readMode(p), ComposeTranslateMode.translationFirst);
  });
}

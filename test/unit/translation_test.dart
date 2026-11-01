// Перевод писем на устройстве (1.9.x): разбор HTML на куски и сборка,
// «оставить оба текста» в своём письме, выбор языков. Движок — подделка,
// без моделей ML Kit / Apple.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/translation/translation_languages.dart';
import 'package:ogneliss/services/translation/translation_text.dart';
import 'package:ogneliss/services/translation/translator.dart';

/// «Перевод» — текст заглавными буквами; считает вызовы.
class FakeTranslator implements Translator {
  final List<List<String>> calls = [];

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    calls.add(texts);
    return [for (final t in texts) t.toUpperCase()];
  }

  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> detectLanguage(String text) async => 'en';
  @override
  Future<List<String>> supportedLanguages() async => const ['en', 'ru', 'de'];
  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async => const {};
  @override
  Future<Set<String>?> downloadedModels() async => {'en'};
  @override
  Future<List<String>> missingModels(String from, String to) async => const [];
  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) async {}
  @override
  Future<void> deleteModel(String lang) async {}
  @override
  bool get googleAttribution => false;
  @override
  int? get modelSizeMb => null;
  @override
  bool get canManageModels => false;
}

void main() {
  group('HtmlTextSegments', () {
    test('переводит только текст, разметка и ссылки остаются', () {
      const html = '<div>Hello <a href="https://example.com/x?a=1&amp;b=2">world</a>!</div>'
          '<p style="color:red"> Second  line </p><img src="cid:1" alt="pic">';
      final s = HtmlTextSegments.parse(html);
      expect(s.texts, ['Hello', 'world', 'Second  line']);
      final out = s.rebuild(['Привет', 'мир', 'Вторая строка']);
      expect(out,
          '<div>Привет <a href="https://example.com/x?a=1&amp;b=2">мир</a>!</div>'
          '<p style="color:red"> Вторая строка </p><img src="cid:1" alt="pic">');
    });

    test('стили, скрипты, код и pre не трогаются', () {
      const html = '<style>p{color:red}</style><script>var a = "x";</script>'
          '<p>Text</p><pre>keep  this</pre><code>foo()</code><span translate="no">Brand</span>'
          '<span class="notranslate">Name</span>';
      final s = HtmlTextSegments.parse(html);
      expect(s.texts, ['Text']);
      final out = s.rebuild(['ТЕКСТ']);
      expect(out, contains('<style>p{color:red}</style>'));
      expect(out, contains('<script>var a = "x";</script>'));
      expect(out, contains('<pre>keep  this</pre>'));
      expect(out, contains('<code>foo()</code>'));
      expect(out, contains('<span translate="no">Brand</span>'));
      expect(out, contains('<p>ТЕКСТ</p>'));
    });

    test('полный документ остаётся документом, текст экранируется', () {
      const html = '<!DOCTYPE html><html><head><title>T</title></head><body><p>a &lt; b</p></body></html>';
      final s = HtmlTextSegments.parse(html);
      expect(s.texts, ['a < b']);
      final out = s.rebuild(['x < y & z']);
      expect(out, startsWith('<!DOCTYPE html>'));
      expect(out, contains('<title>T</title>'));
      expect(out, contains('<p>x &lt; y &amp; z</p>'));
    });

    test('числа, адреса и ссылки текстом не переводятся', () {
      final s = HtmlTextSegments.parse('<table><tr><td>2026</td><td>info@example.com</td><td>https://x.org/a</td><td>Total</td></tr></table>');
      expect(s.texts, ['Total']);
    });

    test('недостающий перевод — исходный текст', () {
      final s = HtmlTextSegments.parse('<p>One</p><p>Two</p>');
      expect(s.rebuild(['Раз']), '<p>Раз</p><p>Two</p>');
    });
  });

  group('PlainTextSegments', () {
    test('по строкам, знаки цитаты и пустые строки сохраняются', () {
      const text = 'Hello,\n\n> quoted line\n  indented \n42';
      final s = PlainTextSegments.parse(text);
      expect(s.texts, ['Hello,', 'quoted line', 'indented']);
      expect(s.rebuild(['Привет,', 'цитата', 'отступ']), 'Привет,\n\n> цитата\n  отступ \n42');
    });
  });

  group('translateHtml с подделкой движка', () {
    test('одинаковые куски переводятся один раз', () async {
      final t = FakeTranslator();
      final out = await translateHtml(t, '<p>more</p><p>more</p><p>end</p>', from: 'en', to: 'ru');
      expect(out, '<p>MORE</p><p>MORE</p><p>END</p>');
      expect(t.calls.single, ['more', 'end']);
    });

    test('частями по chunk', () async {
      final t = FakeTranslator();
      final r = await translateSegments(t, [for (var i = 0; i < 5; i++) 'w$i'], from: 'en', to: 'ru', chunk: 2);
      expect(r, ['W0', 'W1', 'W2', 'W3', 'W4']);
      expect(t.calls.length, 3);
    });
  });

  group('ComposeTranslation', () {
    const editor = '<div id="ogn-greeting">Добрый день,</div><div><br></div><div>Текст письма</div>'
        '<div><br></div><div><br></div><div id="ogn-signature">С уважением,<br>Отдел</div>'
        '<br><div id="divRplyFwdMsg">От: x</div><blockquote>старое</blockquote>';

    test('своё — до подписи, подпись и цитата — хвост', () {
      final s = ComposeTranslation.splitOwn(editor);
      expect(s.own, '<div id="ogn-greeting">Добрый день,</div><div><br></div><div>Текст письма</div>'
          '<div><br></div><div><br></div>');
      expect(s.tail, startsWith('<div id="ogn-signature">'));
      expect(s.tail, contains('divRplyFwdMsg'));
      expect(s.tail, contains('<blockquote>старое</blockquote>'));
    });

    test('цитата без подписи тоже отделяется', () {
      final s = ComposeTranslation.splitOwn('<div>Hi</div><div class="gmail_quote">old</div>');
      expect(s.own, '<div>Hi</div>');
      expect(s.tail, '<div class="gmail_quote">old</div>');
    });

    test('«Заменить текст» — перевод и хвост', () {
      final s = ComposeTranslation.splitOwn(editor);
      final out = ComposeTranslation.assemble(
          split: s,
          translated: '<div id="ogn-greeting">Good afternoon,</div><div><br></div><div>Text</div><div><br></div>',
          mode: ComposeTranslateMode.replace,
          label: 'English');
      expect(out, startsWith('<div id="ogn-greeting">Good afternoon,</div><div><br></div><div>Text</div>'
          '<div><br></div><div id="ogn-signature">'));
      expect(out, isNot(contains('<hr')));
    });

    test('«Оставить оба»: исходный, линия, язык, перевод, затем подпись', () async {
      final s = ComposeTranslation.splitOwn(editor);
      final tr = await translateHtml(FakeTranslator(), s.own, from: 'ru', to: 'en');
      final out = ComposeTranslation.assemble(
          split: s, translated: tr, mode: ComposeTranslateMode.originalFirst, label: 'English');
      final orig = out.indexOf('Текст письма');
      final hr = out.indexOf('<hr');
      final label = out.indexOf('>English</div>');
      final trans = out.indexOf('ТЕКСТ ПИСЬМА');
      final sig = out.indexOf('ogn-signature');
      expect(orig < hr && hr < label && label < trans && trans < sig, isTrue, reason: out);
      // Метка приветствия — одна (во второй копии убрана).
      expect('ogn-greeting'.allMatches(out).length, 1);
      // Пустые строки между текстом и линией убраны.
      expect(out, contains('Текст письма</div><div><br></div><hr'));
    });

    test('«Оставить оба», сначала перевод', () async {
      final s = ComposeTranslation.splitOwn('<div>Привет</div><div><br></div>');
      final out = ComposeTranslation.assemble(
          split: s, translated: '<div>Hello</div>', mode: ComposeTranslateMode.translationFirst, label: 'Русский');
      expect(out, '<div>Hello</div><div><br></div>'
          '<hr style="border:none;border-top:1px solid #d0d0d0;margin:8px 0;">'
          '<div style="font-size:11px;color:#888888;">Русский</div><div>Привет</div>');
    });

    test('простое поле: своё до подписи', () {
      const text = 'Привет\n\nТекст\n\n\n-- \nИмя';
      final s = ComposeTranslation.splitOwnPlain(text, '-- \nИмя');
      expect(s.own, 'Привет\n\nТекст\n\n\n');
      final out = ComposeTranslation.assemblePlain(
          split: s, translated: 'Hello\n\nText\n\n\n', mode: ComposeTranslateMode.originalFirst, label: 'English');
      expect(out, 'Привет\n\nТекст\n\n——— English ———\n\nHello\n\nText\n\n-- \nИмя');
    });
  });

  group('языки', () {
    test('normalizeLang', () {
      expect(normalizeLang('pt-BR'), 'pt');
      expect(normalizeLang('zh-Hans'), 'zh');
      expect(normalizeLang('nb'), 'no');
      expect(normalizeLang('iw'), 'he');
      expect(normalizeLang('und'), isNull);
      expect(normalizeLang('ru-Latn'), isNull);
      expect(normalizeLang('sr-Latn'), 'sr');
      expect(normalizeLang(''), isNull);
    });

    test('предлагать перевод входящего', () {
      const av = ['en', 'ru', 'de', 'no'];
      expect(shouldOfferTranslation(detected: 'en', appLang: 'ru', enabled: true, never: const [], available: av), isTrue);
      expect(shouldOfferTranslation(detected: 'ru', appLang: 'ru', enabled: true, never: const [], available: av), isFalse);
      expect(shouldOfferTranslation(detected: 'en', appLang: 'ru', enabled: false, never: const [], available: av), isFalse);
      expect(shouldOfferTranslation(detected: 'en', appLang: 'ru', enabled: true, never: const ['en'], available: av), isFalse);
      expect(shouldOfferTranslation(detected: 'ja', appLang: 'ru', enabled: true, never: const [], available: av), isFalse);
      expect(shouldOfferTranslation(detected: null, appLang: 'ru', enabled: true, never: const [], available: av), isFalse);
      // Язык приложения «nb» — тот же норвежский, что «no» у ML Kit.
      expect(shouldOfferTranslation(detected: 'no', appLang: 'nb', enabled: true, never: const [], available: av), isFalse);
    });

    test('порядок языков: собеседник, недавние, остальные по названию', () {
      final r = orderTargetLanguages(
        available: const ['ru', 'en', 'de', 'fr', 'es'],
        recent: const ['de', 'en', 'ru'],
        suggested: 'en',
        source: 'ru',
        names: const {'fr': 'Французский', 'es': 'Испанский'},
      );
      expect(r, ['en', 'de', 'es', 'fr']);
    });

    test('язык собеседника — только если он другой', () {
      expect(suggestRecipientLanguage(quoteLang: 'en-US', ownLang: 'ru'), 'en');
      expect(suggestRecipientLanguage(quoteLang: 'ru', ownLang: 'ru'), isNull);
      expect(suggestRecipientLanguage(quoteLang: null, ownLang: 'ru'), isNull);
    });

    test('недавние: первым, без повторов, не больше max', () {
      expect(pushRecent(const ['de', 'en', 'fr'], 'en', max: 3), ['en', 'de', 'fr']);
      expect(pushRecent(const ['de', 'en', 'fr'], 'es', max: 3), ['es', 'de', 'en']);
    });
  });
}

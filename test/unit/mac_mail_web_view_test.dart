// Mac: сложное письмо во встроенном окне браузера (12.11.2026). Само окно
// WKWebView в тестах не создать — проверяются настройки окна (запреты те же,
// что на телефоне) и высота.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mac_mail_web_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

void main() {
  test('настройки окна: без JavaScript и хранилищ, прокрутка — у окна', () {
    final s = MailHtmlView.macSettings(textScale: 1.25);
    expect(s.javaScriptEnabled, isFalse);
    expect(s.javaScriptCanOpenWindowsAutomatically, isFalse);
    expect(s.useShouldOverrideUrlLoading, isTrue);
    expect(s.incognito, isTrue);
    expect(s.cacheEnabled, isFalse);
    expect(s.allowFileAccess, isFalse);
    expect(s.allowFileAccessFromFileURLs, isFalse);
    expect(s.domStorageEnabled, isFalse);
    expect(s.disableVerticalScroll, isFalse);
    expect(s.verticalScrollBarEnabled, isTrue);
    expect(s.pageZoom, 1.25);
    // Настройки окна телефона этим не меняются.
    expect(MailHtmlView.macSettings(textScale: 9).pageZoom, 3.0);
  });

  test('адрес самого документа — не ссылка', () {
    expect(MailHtmlView.isLocalUrl(Uri.parse('about:blank')), isTrue);
    expect(MailHtmlView.isLocalUrl(Uri.parse('data:text/html,x')), isTrue);
    expect(MailHtmlView.isLocalUrl(Uri.parse('https://example.com/')), isFalse);
    expect(MailHtmlView.isLocalUrl(Uri.parse('mailto:a@example.com')), isFalse);
  });

  test('высота окна — по окну приложения, в разумных пределах', () {
    expect(macMailWebHeight(900), 640);
    expect(macMailWebHeight(400), 320);
    expect(macMailWebHeight(5000), 2000);
  });
}

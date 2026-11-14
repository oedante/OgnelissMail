// Компьютер: сложное письмо во встроенном окне браузера — Mac (12.11.2026),
// Windows (14.11.2026). Само окно WKWebView / WebView2 в тестах не создать —
// проверяются настройки окна (запреты те же, что на телефоне), высота и
// выбор «строкой или из файла» (у WebView2 документ строкой — до 2 МБ).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/desktop_mail_web_view.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

void main() {
  test('настройки окна: без JavaScript и хранилищ, прокрутка — у окна', () {
    final s = MailHtmlView.desktopSettings(textScale: 1.25);
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
    expect(MailHtmlView.desktopSettings(textScale: 9).pageZoom, 3.0);
  });

  test('адрес самого документа — не ссылка', () {
    expect(MailHtmlView.isLocalUrl(Uri.parse('about:blank')), isTrue);
    expect(MailHtmlView.isLocalUrl(Uri.parse('data:text/html,x')), isTrue);
    expect(MailHtmlView.isLocalUrl(Uri.parse('https://example.com/')), isFalse);
    expect(MailHtmlView.isLocalUrl(Uri.parse('mailto:a@example.com')), isFalse);
  });

  test('высота окна — по окну приложения, в разумных пределах', () {
    expect(desktopMailWebHeight(900), 640);
    expect(desktopMailWebHeight(400), 320);
    expect(desktopMailWebHeight(5000), 2000);
  });

  test('Windows: большое письмо — из файла, обычное — строкой; Mac — всегда строкой', () {
    final small = '<p>${'Привет, мир. ' * 1000}</p>';
    // Картинка внутри письма (data URI) — мегабайты.
    final big = '<img src="data:image/png;base64,${'A' * (2 * 1024 * 1024)}">';
    expect(desktopMailNeedsFile(small, windows: true), isFalse);
    expect(desktopMailNeedsFile(big, windows: true), isTrue);
    expect(desktopMailNeedsFile(big, windows: false), isFalse);
    // Кириллица — 2 байта UTF-8: 1 млн букв уже больше предела.
    expect(desktopMailNeedsFile('я' * 1000000, windows: true), isTrue);
    expect(desktopMailNeedsFile('a' * 1000000, windows: true), isFalse);
  });
}

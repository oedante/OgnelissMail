// Подготовка тела письма вне UI-изолята: результат тот же, что на месте.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/mail_body_processor.dart';
import 'package:ogneliss/services/security/tracker_blocker.dart';

void main() {
  const opts = TrackerBlockOptions(enabled: true, blockExternal: true);

  test('мелкое письмо: скрипт вырезан, внешняя картинка скрыта', () async {
    const html = '<p>Привет</p><script>alert(1)</script><img src="https://x.ru/a.png">';
    final r = await MailBodyProcessor.secure(html, keepStyles: true, options: opts);
    expect(r.html, isNot(contains('<script')));
    expect(r.html, isNot(contains('https://x.ru/a.png')));
    expect(r.externalBlocked, 1);
  });

  test('крупное письмо (через изолят) — тот же результат', () async {
    final big = '<p>${'текст ' * 8000}</p><img src="https://x.ru/a.png"><script>x()</script>';
    expect(big.length, greaterThan(MailBodyProcessor.isolateThreshold));
    final r = await MailBodyProcessor.secure(big, keepStyles: true, options: opts);
    expect(r.html, isNot(contains('<script')));
    expect(r.externalBlocked, 1);
  });

  test('доверенный отправитель: внешние картинки не скрываются', () async {
    const html = '<img src="https://x.ru/a.png">';
    final r = await MailBodyProcessor.secure(html,
        keepStyles: true, options: const TrackerBlockOptions(enabled: true, blockExternal: false));
    expect(r.html, contains('https://x.ru/a.png'));
  });

  test('HTML → текст для индекса', () async {
    final m = await MailBodyProcessor.htmlToPlainAll(
        {'1': '<style>p{}</style><p>Отчёт&nbsp;по <b>ТОиР</b></p>'});
    expect(m['1'], 'Отчёт по ТОиР');
  });
}

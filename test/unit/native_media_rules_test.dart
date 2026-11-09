// Письма с правилами @media — простым видом (2.2.0, план 08.11.2026 п. 5):
// раньше любое @media отправляло письмо в окно браузера. Блоки, скрытые вне
// @media (мобильная версия, «прехедер»), — по-прежнему в браузер.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';

String _mail(String css, [String body = '<p>Добрый день! Счёт во вложении.</p>']) =>
    '<html><head><style>$css</style></head><body>$body</body></html>';

void main() {
  test('CSS вне @-блоков: @media и @font-face — без содержимого', () {
    const css = '.a{color:red} @media screen and (max-width:600px){.b{display:none}.c{width:100%}} '
        '@font-face{font-family:X;src:url(x)} @import url(y); .d{margin:0}';
    final out = cssOutsideAtRules(css);
    expect(out, contains('.a{color:red}'));
    expect(out, contains('.d{margin:0}'));
    expect(out, isNot(contains('display:none')));
    expect(out, isNot(contains('font-family')));
    expect(out, isNot(contains('@import')));
  });

  test('адаптивные правила @media — простой показ', () {
    final r = buildNativeMailWhy(_mail('.wrap{width:600px} @media only screen and (max-width:600px){.wrap{width:100%!important}}'));
    expect(r.why, isNull);
    expect(r.mail, isNotNull);
  });

  test('скрыть на телефоне (display:none внутри @media) — простой показ, как на компьютере', () {
    final r = buildNativeMailWhy(_mail('@media (max-width:480px){.desk{display:none!important}}',
        '<p class="desk">Для компьютера</p><p>Текст</p>'));
    expect(r.mail, isNotNull);
  });

  test('мобильная версия скрыта вне @media — окно браузера', () {
    expect(buildNativeMailWhy(_mail('.mob{display:none} @media (max-width:480px){.mob{display:block!important}}')).why,
        'скрытые стилем блоки');
    expect(
        buildNativeMailWhy(_mail(
                '.mob{max-height:0;overflow:hidden} @media (max-width:480px){.mob{max-height:none!important}}'))
            .why,
        'скрытые стилем блоки (@media)');
  });

  test('без @media правила max-height — как раньше, простой показ', () {
    expect(buildNativeMailWhy(_mail('.note{max-height:0;overflow:hidden}')).mail, isNotNull);
  });
}

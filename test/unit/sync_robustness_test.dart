// 1.6.12: разбор HTML без квадратичного времени, User-Agent Почты iPhone.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/device/device_user_agent.dart';
import 'package:ogneliss/core/security/mail_body_processor.dart';

void main() {
  group('htmlToPlain', () {
    test('стили, скрипты, заголовок и комментарии убираются', () {
      const html = '<html><head><title>Рассылка</title><style>p{color:red}</style></head>'
          '<body><!--[if mso]>VML<![endif]--><p>Привет,&nbsp;<b>мир</b></p>'
          '<SCRIPT>alert(1)</SCRIPT><header>Шапка</header></body></html>';
      expect(MailBodyProcessor.htmlToPlain(html), 'Привет, мир Шапка');
    });

    test('незакрытый <style> и комментарий — до конца письма, без зависания', () {
      final big = StringBuffer('<p>Текст</p>');
      for (var i = 0; i < 20000; i++) {
        big.write('<style>x{} <!-- y ');
      }
      final sw = Stopwatch()..start();
      final out = MailBodyProcessor.htmlToPlain(big.toString());
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
      expect(out, 'Текст');
    });
  });

  test('User-Agent Почты iPhone из модели и сборки iOS', () {
    expect(DeviceUserAgent.appleMailUserAgent('iPhone15,2', 'Version 27.0.1 (Build 24A446)'),
        'Apple-iPhone15C2/2401.446');
    expect(DeviceUserAgent.appleMailUserAgent('iPhone14,5', 'Version 18.2 (Build 22C152)'),
        'Apple-iPhone14C5/2203.152');
  });
}

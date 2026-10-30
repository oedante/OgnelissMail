// Текст письма (1.8.12, замечания владельца 30.10.2026): «у нас очень мелкий
// шрифт» и «письмо можно бесконечно проматывать».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/widgets/common/ui_zoom.dart';

void main() {
  tearDown(() => UiZoom.current = 1.0);

  testWidgets('системный шрифт учитывается, масштаб интерфейса текст не уменьшает', (t) async {
    Future<double> at(double system, double zoom) async {
      UiZoom.current = zoom;
      late double out;
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(system)),
        child: Builder(builder: (c) {
          out = MailHtmlView.textScaleOf(c);
          return const SizedBox();
        }),
      ));
      return out;
    }

    // Телефон владельца: 360 dp, шрифт ×1,15, масштаб интерфейса 85 %.
    final s = await at(1.15, 0.85);
    expect(s, closeTo(1.35, 0.001));
    // На экране: 15 px × 1,35 × 0,85 ≈ 17 dp (было 14 × 1 × 0,85 ≈ 12).
    expect(15 * s * 0.85, greaterThan(16.5));
    expect(await at(1, 1), 1);
    // Шаг 0,05: у запасного окна и у экрана письма — одно и то же число.
    expect(await at(1.12, 1), 1.1);
  });

  test('высоты в долях окна — по содержимому', () {
    expect(MailHtmlDocument.noViewportHeights('min-height:100vh;color:red'), 'min-height:auto;color:red');
    expect(MailHtmlDocument.noViewportHeights('div{height: 100vh !important}'), 'div{height:auto}');
    expect(MailHtmlDocument.noViewportHeights('max-height:80vh;width:50vw'), 'max-height:80vh;width:50vw');
    expect(MailHtmlDocument.noViewportHeights('line-height:1.4'), 'line-height:1.4');
    final doc = MailHtmlDocument.build(
        '<style>.wrap{min-height:100vh}</style><div class="wrap" style="height:100dvh">Текст</div>',
        allowRemoteImages: false);
    expect(doc.html, isNot(contains('vh')));
  });
}

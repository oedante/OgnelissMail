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
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(system)),
          child: Builder(
            builder: (c) {
              out = MailHtmlView.textScaleOf(c);
              return const SizedBox();
            },
          ),
        ),
      );
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

  testWidgets('Android 14+: нелинейный системный шрифт тоже увеличивает текст письма', (t) async {
    late double out;
    await t.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: _NonLinear(1.3)),
        child: Builder(
          builder: (c) {
            out = MailHtmlView.textScaleOf(c);
            return const SizedBox();
          },
        ),
      ),
    );
    // Мелкий текст растёт на ×1,3, крупный (100 px) — не растёт: множитель
    // берётся на базовом размере письма (15 px), не на 100 px.
    expect(out, 1.3);
  });

  test('высоты в долях окна — по содержимому', () {
    expect(MailHtmlDocument.noViewportHeights('min-height:100vh;color:red'), 'min-height:auto;color:red');
    expect(MailHtmlDocument.noViewportHeights('div{height: 100vh !important}'), 'div{height:auto}');
    expect(MailHtmlDocument.noViewportHeights('max-height:80vh;width:50vw'), 'max-height:80vh;width:50vw');
    expect(MailHtmlDocument.noViewportHeights('line-height:1.4'), 'line-height:1.4');
    final doc = MailHtmlDocument.build(
      '<style>.wrap{min-height:100vh}</style><div class="wrap" style="height:100dvh">Текст</div>',
      allowRemoteImages: false,
    );
    expect(doc.html, isNot(contains('vh')));
  });

  test('«прилипающие» блоки — на своё место в тексте', () {
    expect(MailHtmlDocument.noFixedPosition('position:fixed;bottom:0'), 'position:static;bottom:0');
    expect(
      MailHtmlDocument.noFixedPosition('.b{position: -webkit-sticky !important; top:0}'),
      '.b{position:static; top:0}',
    );
    expect(MailHtmlDocument.noFixedPosition('position:relative'), 'position:relative');
    expect(MailHtmlDocument.noFixedPosition('table-layout:fixed'), 'table-layout:fixed');
    const plain = 'color:red;table-layout:fixed';
    expect(identical(MailHtmlDocument.layoutSafe(plain), plain), isTrue);
    final doc = MailHtmlDocument.build(
      '<style>.bar{position:sticky;top:0}</style><div class="bar">Меню</div>'
      '<div style="position:fixed;bottom:0;left:0">Подвал</div><p>Текст</p>',
      allowRemoteImages: false,
    );
    expect(doc.html, isNot(contains('sticky')));
    expect(doc.html, isNot(contains('position:fixed')));
    expect(doc.html, contains('style="position:static;bottom:0;left:0"'));
  });
}

/// Как системный шрифт Android 14+: мелкий текст увеличивается на [factor],
/// к 100 px увеличение сходит на нет.
class _NonLinear extends TextScaler {
  const _NonLinear(this.factor);
  final double factor;

  /// До 20 px — ×[factor], от 20 до 100 px множитель плавно сходит к 1.
  @override
  double scale(double fontSize) {
    final k = ((fontSize - 20) / 80).clamp(0.0, 1.0);
    return fontSize * (factor + (1 - factor) * k);
  }

  @override
  double get textScaleFactor => factor;
}

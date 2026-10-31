// integration_test/mail_view_test.dart
// Окно письма (MailHtmlView) на эмуляторе Android — без аккаунтов, с
// готовыми письмами (1.9.x, просьба владельца 31.10.2026: ловить до
// телефона то, что раньше видели только на нём, — капли выделения и касания
// не там, где текст, вписывание широких писем, пустое поле под письмом после
// «По ширине экрана», «Исходный масштаб» и «Обычный размер»).
//
// Проверяется:
//  · масштаб, который сообщает движок (onZoomScaleChanged), — 100 % или
//    ширина окна / ширина вёрстки;
//  · высота окна на экране письма — как у того же документа в окне высотой
//    1 px (запасное окно MailWebViewPool: документ там не бывает выше себя,
//    и его высота — высота письма); больше — пустое поле под письмом;
//  · касание по центру ссылки и картинки на экране попадает в них
//    (getHitTestResult: SRC_ANCHOR / IMAGE) — при масштабе интерфейса 1,0 и
//    0,85, когда окно рисуется без него (UiZoomUndo): от этого зависят и
//    капли выделения.
//
// Отдельно: flutter test integration_test/mail_view_test.dart -d <эмулятор>

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

import 'support/harness.dart';

void main() {
  ensureBinding();
  mailViewTests();
}

/// Цвет страницы письма в тестах (светлая тема).
const _page = Colors.white;

/// Обычное письмо: абзацы, цитата.
const _plainHtml = '''
<p>Добрый день!</p>
<p>Высылаю отчёт за октябрь. Основные цифры — в таблице ниже, подробности —
во вложении. Если что-то непонятно, позвоните мне.</p>
<table border="1" cellpadding="4"><tr><td>Отдел</td><td>План</td><td>Факт</td></tr>
<tr><td>Продажи</td><td>120</td><td>131</td></tr><tr><td>Склад</td><td>80</td><td>77</td></tr></table>
<p>Спасибо!</p>
<blockquote><p>Пришлите, пожалуйста, отчёт до пятницы.</p><p>— Коллега</p></blockquote>
<p>С уважением,<br>Отдел отчётности</p>
''';

/// Рассылка с вёрсткой 640 px (шире экрана телефона).
String _newsletterHtml() {
  final rows = StringBuffer();
  for (var i = 1; i <= 8; i++) {
    rows.write(
      '<tr><td width="200" style="padding:8px;background:#f2f4f8">Раздел $i</td>'
      '<td width="440" style="padding:8px">Новость номер $i: длинный текст рассылки, который в узкой '
      'колонке переносится на несколько строк, а в широкой — на одну-две.</td></tr>',
    );
  }
  return '<table width="640" cellpadding="0" cellspacing="0" style="width:640px">'
      '<tr><td colspan="2" style="height:120px;background:#1D4F91;color:#fff;font-size:28px;padding:16px">'
      'Новости месяца</td></tr>$rows'
      '<tr><td colspan="2" style="padding:16px;font-size:12px;color:#777">Вы получили это письмо, потому что '
      'подписались на рассылку.</td></tr></table>';
}

/// Письмо с картинкой и ссылками в известных местах (CSS-пиксели от
/// верха документа; у тела сверху поле 4 px — MailHtmlView._themed):
///  · ссылка 1 — слева, 240×80, верх 124;
///  · картинка 160×120 — справа, верх 264;
///  · ссылка 2 — справа, 200×60, верх 444.
/// Блоки фиксированной высоты — размер шрифта письма на них не влияет.
String _targetsHtml() {
  final image = img.Image(width: 160, height: 120);
  img.fill(image, color: img.ColorRgb8(200, 80, 40));
  final png = base64Encode(img.encodePng(image));
  return '''
<div style="height:120px;overflow:hidden;line-height:20px;margin:0">Письмо с картинкой и ссылками. Здесь обычный текст.</div>
<a href="$_link1" style="display:block;width:240px;height:80px;margin:0;line-height:80px;text-align:center;background:#e3ecf7">Открыть ссылку</a>
<div style="height:60px;overflow:hidden;margin:0">Текст между ссылкой и картинкой.</div>
<img src="data:image/png;base64,$png" width="160" height="120" alt="Картинка" style="display:block;margin:0 0 0 auto">
<div style="height:60px;overflow:hidden;margin:0">Текст под картинкой.</div>
<a href="$_link2" style="display:block;width:200px;height:60px;margin:0 0 0 auto;line-height:60px;text-align:center;background:#e3ecf7">Справа</a>
<div style="height:80px;overflow:hidden;margin:0">Конец письма.</div>
''';
}

const _link1 = 'https://example.com/ogneliss-link-left';
const _link2 = 'https://example.com/ogneliss-link-right';
const _bodyTop = 4.0;

/// События окна письма в тесте.
class _Probe {
  InAppWebViewController? controller;
  int loadStops = 0;
  final zooms = <double>[];
  ({double height, int? fitWidth, bool actualSize, bool pinched, bool ready})? layout;

  late final probe = MailHtmlViewProbe(
    onCreated: (c) => controller = c,
    onLoadStop: () => loadStops++,
    onZoomScaleChanged: (_, n) => zooms.add(n),
    onLayout: (l) => layout = l,
  );

  double get height => layout?.height ?? 0;
}

/// Экран письма в тесте: поля 16 dp, прокрутка по вертикали — как у экрана
/// письма; ширина окна — ширина экрана минус поля.
Widget _mailScreen(
  MailHtmlDocument doc, {
  required double textScale,
  VoidCallback? onShown,
  void Function(String url, String? text)? onLink,
}) {
  return Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MailHtmlView(
            document: doc,
            allowRemoteImages: false,
            textScale: textScale,
            pageColor: _page,
            onShown: onShown,
            onLink: onLink ?? (_, __) {},
          ),
        ),
      ),
    ),
  );
}

/// Высота документа на экране письма по окну высотой 1 px (запасное окно):
/// эталон для высоты окна письма. [fitWidth] — ширина вписывания.
Future<double> _referenceHeight(
  WidgetTester tester,
  MailHtmlDocument doc, {
  required double viewWidth,
  required int? fitWidth,
  required double textScale,
}) async {
  final html = MailHtmlView.composeHtml(
    doc,
    viewWidth: viewWidth,
    fitWidth: fitWidth,
    dark: false,
    pageColor: _page,
    textScale: textScale,
  );
  MailWebViewPool.enabled = true;
  try {
    await waitFor(
      tester,
      MailWebViewPool.ensureSpare(width: viewWidth, textScale: textScale),
      what: 'запасное окно создано',
    );
    unawaited(
      MailWebViewPool.preload(
        html,
        textScale: textScale,
        heightScale: fitWidth == null ? 1.0 : viewWidth / fitWidth,
        width: viewWidth,
      ),
    );
    await pumpUntil(
      tester,
      () => MailWebViewPool.debugMeasuredHeight != null,
      what: 'высота документа в запасном окне',
    );
    return MailWebViewPool.debugMeasuredHeight!;
  } finally {
    await MailWebViewPool.release();
    MailWebViewPool.enabled = false;
  }
}

/// Масштаб страницы в единицах экрана письма по последнему сообщению движка
/// (onZoomScaleChanged — в точках Android, с плотностью и масштабом
/// интерфейса, который окно применяет само) и по getZoomScale.
Future<({double? reported, double current})> _scales(WidgetTester tester, _Probe p) async {
  final dpr = tester.view.devicePixelRatio;
  final z = MailHtmlView.webZoom;
  final reported = p.zooms.isEmpty ? null : p.zooms.last / (dpr * z);
  final cur = (await p.controller!.getZoomScale()) ?? 1.0;
  return (reported: reported, current: cur / z);
}

void _expectScale(({double? reported, double current}) s, double expected, String what) {
  expect(s.current, closeTo(expected, expected * 0.03), reason: '$what: getZoomScale');
  if (s.reported != null) {
    expect(s.reported!, closeTo(expected, expected * 0.03), reason: '$what: onZoomScaleChanged');
  }
}

/// Высота окна — как у документа (допуск 4 % и 16 точек): больше — пустое
/// поле под письмом, меньше — обрезанный низ.
void _expectHeight(double actual, double expected, String what) {
  final tol = (expected * 0.04).clamp(16.0, double.infinity);
  expect(actual, closeTo(expected, tol), reason: '$what: высота окна $actual при высоте документа $expected');
}

Future<void> _settle(WidgetTester tester, _Probe p, String what) async {
  await waitStable(tester, () => p.height, what: '$what: высота');
}

Future<_Probe> _open(
  WidgetTester tester,
  MailHtmlDocument doc, {
  required double zoom,
  void Function(String url, String? text)? onLink,
}) async {
  final p = _Probe();
  MailHtmlView.debugProbe = p.probe;
  addTearDown(() => MailHtmlView.debugProbe = null);
  final shown = Completer<void>();
  await tester.pumpWidget(
    testApp(
      zoom: zoom,
      home: _mailScreen(
        doc,
        textScale: mailTextScaleFor(zoom),
        onShown: () {
          if (!shown.isCompleted) shown.complete();
        },
        onLink: onLink,
      ),
    ),
  );
  await waitFor(tester, shown.future, what: 'письмо показано (onShown)', timeout: const Duration(seconds: 30));
  expect(p.controller, isNotNull);
  await _settle(tester, p, 'открытие');
  return p;
}

void mailViewTests() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await loadStrings();
  });

  setUp(() {
    MailHtmlView.fitWide = false;
    MailWebViewPool.enabled = false;
  });

  tearDown(() async {
    setUiZoom(1.0);
    await MailWebViewPool.release();
  });

  for (final zoom in const [1.0, 0.85]) {
    group('Окно письма, масштаб интерфейса $zoom', () {
      testWidgets('обычное письмо: 100 %, высота по документу', (tester) async {
        setUiZoom(zoom);
        final ts = mailTextScaleFor(zoom);
        final doc = MailHtmlDocument.build(_plainHtml, allowRemoteImages: false);
        final p = await _open(tester, doc, zoom: zoom);
        final w = tester.getSize(find.byType(MailHtmlView)).width;
        expect(w, closeTo(screenWidth(tester) / zoom - 32, 1));
        // Не широкое — кнопки масштаба нет.
        expect(find.text(l10n.tr('mailFitToWidth')), findsNothing);
        expect(find.text(l10n.tr('mailActualSize')), findsNothing);
        _expectScale(await _scales(tester, p), 1.0, 'обычное письмо');
        final ref = await _referenceHeight(tester, doc, viewWidth: w, fitWidth: null, textScale: ts);
        _expectHeight(p.height, ref, 'обычное письмо');
      }, skip: !onAndroid);

      testWidgets('рассылка 640 px: «По ширине экрана», «Обычный размер», «Исходный масштаб» — без пустого поля', (
        tester,
      ) async {
        setUiZoom(zoom);
        final ts = mailTextScaleFor(zoom);
        final doc = MailHtmlDocument.build(_newsletterHtml(), allowRemoteImages: false);
        expect(doc.declaredWidth, 640);
        final p = await _open(tester, doc, zoom: zoom);
        final w = tester.getSize(find.byType(MailHtmlView)).width;
        final fit = w / 640;
        final refActual = await _referenceHeight(tester, doc, viewWidth: w, fitWidth: null, textScale: ts);
        final refFit = await _referenceHeight(tester, doc, viewWidth: w, fitWidth: 640, textScale: ts);
        expect(refFit, lessThan(refActual), reason: 'вписанное письмо ниже');

        // Открытие: обычный масштаб (fitWide выключено), кнопка «По ширине экрана».
        expect(p.layout!.actualSize, isTrue);
        _expectScale(await _scales(tester, p), 1.0, 'открытие');
        _expectHeight(p.height, refActual, 'открытие');

        // «По ширине экрана».
        var loads = p.loadStops;
        await tester.tap(find.text(l10n.tr('mailFitToWidth')));
        await pumpUntil(tester, () => p.loadStops > loads, what: 'документ перезагружен по ширине экрана');
        await _settle(tester, p, 'по ширине экрана');
        expect(p.layout!.fitWidth, 640);
        _expectScale(await _scales(tester, p), fit, 'по ширине экрана');
        _expectHeight(p.height, refFit, 'по ширине экрана');

        // Увеличение (как щипком; zoomBy — родной вызов WebView, без касаний)
        // → «Обычный размер».
        await p.controller!.zoomBy(zoomFactor: 1.6);
        await pumpUntil(tester, () => p.layout?.pinched ?? false, what: 'письмо увеличено, кнопка «Обычный размер»');
        await _settle(tester, p, 'увеличено');
        final zoomed = await _scales(tester, p);
        expect(zoomed.current, greaterThan(fit * 1.2));
        // Высота растёт ровно с масштабом.
        _expectHeight(p.height, refFit * zoomed.current / fit, 'увеличено');
        expect(find.text(l10n.tr('mailZoomReset')), findsOneWidget);

        loads = p.loadStops;
        await tester.tap(find.text(l10n.tr('mailZoomReset')));
        await pumpUntil(tester, () => p.loadStops > loads, what: 'документ перезагружен («Обычный размер»)');
        await _settle(tester, p, 'обычный размер');
        expect(p.layout!.pinched, isFalse);
        _expectScale(await _scales(tester, p), fit, 'обычный размер');
        _expectHeight(p.height, refFit, 'обычный размер');

        // «Исходный масштаб» — снова 100 %.
        loads = p.loadStops;
        await tester.tap(find.text(l10n.tr('mailActualSize')));
        await pumpUntil(tester, () => p.loadStops > loads, what: 'документ перезагружен в исходном масштабе');
        await _settle(tester, p, 'исходный масштаб');
        expect(p.layout!.actualSize, isTrue);
        _expectScale(await _scales(tester, p), 1.0, 'исходный масштаб');
        _expectHeight(p.height, refActual, 'исходный масштаб');
      }, skip: !onAndroid);

      testWidgets('касания попадают в ссылку и картинку (getHitTestResult)', (tester) async {
        setUiZoom(zoom);
        final links = <String>[];
        final doc = MailHtmlDocument.build(_targetsHtml(), allowRemoteImages: false);
        final p = await _open(tester, doc, zoom: zoom, onLink: (url, _) => links.add(url));
        final c = p.controller!;
        // Ширина документа в CSS-пикселях — ширина окна на экране письма
        // (письмо не широкое, масштаб 1); точек экрана на CSS-пиксель — по
        // месту окна на экране: так проверяется и пересчёт касаний под
        // масштаб интерфейса (UiZoomBox) и окно без него (UiZoomUndo).
        final cssWidth = tester.getSize(find.byType(MailHtmlView)).width;
        final rect = tester.getRect(find.byType(InAppWebView));
        final k = rect.width / cssWidth;
        expect(k, closeTo(zoom, 0.01));
        Offset at(double x, double y) => rect.topLeft + Offset(x, y) * k;

        Future<InAppWebViewHitTestResult?> hitAfterTap(Offset point, InAppWebViewHitTestResultType want) async {
          await tapAtGlobal(tester, point);
          return pollUntil<InAppWebViewHitTestResult?>(
            tester,
            c.getHitTestResult,
            (r) => r?.type == want,
            what: 'касание в $point → ${want.toNativeValue()}',
          );
        }

        // Текст — не ссылка и не картинка (касание не «прилипает» к
        // прошлому результату).
        await hitAfterTap(at(cssWidth / 2, _bodyTop + 60), InAppWebViewHitTestResultType.UNKNOWN_TYPE);

        // Ссылка слева вверху: тип и адрес, и приложение получило нажатие.
        final r1 = await hitAfterTap(at(120, _bodyTop + 120 + 40), InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE);
        expect(r1?.extra, _link1);
        await pumpUntil(tester, () => links.contains(_link1), what: 'onLink для левой ссылки');

        // Ссылка справа ниже: сдвиг касаний растёт вправо и вниз — здесь он
        // был бы заметен.
        final r2 = await hitAfterTap(
          at(cssWidth - 100, _bodyTop + 440 + 30),
          InAppWebViewHitTestResultType.SRC_ANCHOR_TYPE,
        );
        expect(r2?.extra, _link2);
        await pumpUntil(tester, () => links.contains(_link2), what: 'onLink для правой ссылки');

        // Картинка справа: тип IMAGE, и приложение открыло её на весь экран.
        await hitAfterTap(at(cssWidth - 80, _bodyTop + 260 + 60), InAppWebViewHitTestResultType.IMAGE_TYPE);
        final viewer = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PhotoView');
        await pumpUntil(tester, () => viewer.evaluate().isNotEmpty, what: 'картинка открыта на весь экран');
        Navigator.of(tester.element(viewer)).pop();
        await pumpUntil(tester, () => viewer.evaluate().isEmpty, what: 'просмотр картинки закрыт');
      }, skip: !onAndroid);
    });
  }
}

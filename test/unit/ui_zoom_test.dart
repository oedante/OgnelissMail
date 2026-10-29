// Масштаб интерфейса «Авто» (1.6.12).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/ui_zoom.dart';

void main() {
  test('Широкий экран и мелкий шрифт — без изменений (nubia 438 dp, ×0,85)', () {
    expect(UiZoom.auto(const Size(438, 973), 0.85), 1.0);
    expect(UiZoom.auto(const Size(412, 915), 1.0), 1.0);
  });

  test('Узкие телефоны — мельче, но не меньше 85 %', () {
    expect(UiZoom.auto(const Size(393, 852), 1.0), 0.95); // iPhone 15
    expect(UiZoom.auto(const Size(375, 667), 1.0), 0.91); // iPhone SE
    expect(UiZoom.auto(const Size(363, 792), 1.0), 0.88); // OnePlus из журнала
    expect(UiZoom.auto(const Size(320, 640), 1.0), 0.85);
  });

  test('Крупный шрифт учитывается наполовину; поворот не меняет масштаб', () {
    expect(UiZoom.auto(const Size(412, 915), 1.3), closeTo(0.86, 0.001));
    expect(UiZoom.auto(const Size(852, 393), 1.0), UiZoom.auto(const Size(393, 852), 1.0));
  });

  test('Планшет — без масштаба; ручной выбор важнее авто', () {
    expect(UiZoom.auto(const Size(800, 1280), 1.6), 1.0);
    expect(UiZoom.resolve(1.0, const Size(320, 640), 1.0), 1.0);
    expect(UiZoom.resolve(0.9, const Size(438, 973), 1.0), 0.9);
  });

  test('Данные экрана — в единицах масштаба', () {
    const mq = MediaQueryData(size: Size(360, 800), devicePixelRatio: 3, padding: EdgeInsets.only(top: 24));
    final z = UiZoom.scaleData(mq, 0.9);
    expect(z.size.width, closeTo(400, 0.01));
    expect(z.devicePixelRatio, closeTo(2.7, 0.001));
    expect(z.padding.top, closeTo(26.67, 0.01));
  });

  // Встроенное окно (WebView на Android) — в итоговом масштабе 1: иначе
  // системные ручки выделения уезжали от курсора (28.10.2026).
  testWidgets('UiZoomUndo: окно на том же месте, но без масштаба', (tester) async {
    const key = Key('native');
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: UiZoomBox(
        zoom: 0.85,
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 40, top: 100),
            child: SizedBox(
              width: 300,
              height: 200,
              child: UiZoomUndo(zoom: 0.85, child: Container(key: key)),
            ),
          ),
        ),
      ),
    ));
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    // Размер окна — «место × масштаб», на экране — то же место.
    expect(box.size.width, closeTo(255, 0.01));
    expect(box.size.height, closeTo(170, 0.01));
    final m = box.getTransformTo(null);
    expect(m.getMaxScaleOnAxis(), closeTo(1, 0.0001));
    final r = MatrixUtils.transformRect(m, Offset.zero & box.size);
    expect(r.left, closeTo(34, 0.01));
    expect(r.top, closeTo(85, 0.01));
    expect(r.width, closeTo(255, 0.01));
  });
}

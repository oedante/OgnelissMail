// Листание писем — намеренным жестом вбок (2.3.2, замечание владельца
// 11.11.2026: «свайп очень лёгкий — едва коснулся, уже письмо поехало»).
// На Android системный порог жеста — около 8 точек, и листание начиналось
// от малейшего сдвига пальца в сторону.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/paging_slop.dart';

void main() {
  test('порог листания: больше системного, но меньше порога окна письма (36)', () {
    expect(PagingSlop.slopFor(8), 20, reason: 'Android: 8 точек → 20');
    expect(PagingSlop.slopFor(null), 30, reason: 'стандартный порог Flutter 18 → не больше 30');
    expect(PagingSlop.slopFor(4), 20);
    expect(PagingSlop.maxSlop, lessThan(kPanSlop));
  });

  Widget app(PageController c, {required void Function(double?) pageSlop}) => MediaQuery(
        data: const MediaQueryData(size: Size(400, 800), gestureSettings: DeviceGestureSettings(touchSlop: 8)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: PagingSlop(
            child: PageView.builder(
              controller: c,
              itemCount: 3,
              itemBuilder: (context, i) => PagingSlop.page(
                context,
                Builder(builder: (inner) {
                  pageSlop(MediaQuery.gestureSettingsOf(inner).touchSlop);
                  return ListView(children: [for (var k = 0; k < 40; k++) SizedBox(height: 60, child: Text('$i-$k'))]);
                }),
              ),
            ),
          ),
        ),
      );

  testWidgets('лёгкий сдвиг вбок страницу не двигает, намеренный — листает', (tester) async {
    final c = PageController();
    addTearDown(c.dispose);
    double? inner;
    await tester.pumpWidget(app(c, pageSlop: (v) => inner = v));
    expect(inner, 8, reason: 'у прокрутки самой страницы порог системный');

    final g = await tester.startGesture(const Offset(300, 400));
    await g.moveBy(const Offset(-14, 0));
    await tester.pump();
    expect(c.position.pixels, 0, reason: '14 точек вбок — ещё не листание (раньше хватало 8)');
    // Жест начинается с места, где порог пройден: дальше страница идёт за пальцем.
    await g.moveBy(const Offset(-10, 0));
    await tester.pump();
    await g.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(c.position.pixels, greaterThan(0));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('прокрутка письма с небольшим уходом вбок остаётся прокруткой', (tester) async {
    final c = PageController();
    addTearDown(c.dispose);
    await tester.pumpWidget(app(c, pageSlop: (_) {}));
    final g = await tester.startGesture(const Offset(300, 400));
    // Палец идёт вниз и немного в сторону.
    for (var i = 0; i < 30; i++) {
      await g.moveBy(const Offset(-3, -6));
      await tester.pump();
    }
    expect(c.position.pixels, 0, reason: 'страница не поехала, хотя палец ушёл вбок на 90 точек');
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('0-0'), findsNothing, reason: 'письмо прокрутилось');
  });
}

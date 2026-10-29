// 1.8.0: тело письма увеличивается разведением двух пальцев и
// возвращается к обычному размеру; одним пальцем экран листается.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/pinch_zoom.dart';

Widget _host() => const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [
            SizedBox(height: 50),
            PinchZoom(
              resetLabel: 'Обычный размер',
              child: SizedBox(height: 100, child: Text('Таблица')),
            ),
            SizedBox(height: 1200),
          ]),
        ),
      ),
    );

void main() {
  testWidgets('щипок увеличивает, «Обычный размер» возвращает', (tester) async {
    await tester.pumpWidget(_host());
    final before = tester.getSize(find.byType(PinchZoom)).height;
    expect(before, 100);
    expect(find.text('Обычный размер'), findsNothing);

    final c = tester.getCenter(find.text('Таблица'));
    final a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
    await tester.pump();
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    // Пальцы разошлись втрое — письмо втрое выше, над ним — кнопка.
    expect(find.text('Обычный размер'), findsOneWidget);
    final zoomed = tester.getSize(find.byType(PinchZoom)).height;
    expect(zoomed, greaterThan(before * 2.5));

    await tester.tap(find.text('Обычный размер'));
    await tester.pumpAndSettle();
    expect(find.text('Обычный размер'), findsNothing);
    expect(tester.getSize(find.byType(PinchZoom)).height, before);
  });

  testWidgets('один палец — листание экрана, не масштаб', (tester) async {
    await tester.pumpWidget(_host());
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    await tester.drag(find.text('Таблица'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(find.text('Обычный размер'), findsNothing);
    expect(tester.getSize(find.byType(PinchZoom)).height, 100);
  });
}

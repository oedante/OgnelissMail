// Перелистывающиеся часы «Моего дня» (1.15.1, просьба владельца 07.11.2026).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/my_day/flip_clock.dart';

void main() {
  testWidgets('время — подписью; в начале минуты цифры перелистываются', (tester) async {
    final semantics = tester.ensureSemantics();
    var now = DateTime(2026, 11, 7, 10, 59, 58);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: FlipClock(clock: () => now)))));
    expect(find.bySemanticsLabel('10:59'), findsOneWidget);

    now = DateTime(2026, 11, 7, 11, 0, 0, 100);
    await tester.pump(const Duration(seconds: 3));
    // Посреди перелистывания — и прежние, и новые цифры на экране.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.bySemanticsLabel('11:00'), findsOneWidget);
    expect(find.text('9'), findsWidgets, reason: 'прежняя цифра ещё падает');
    await tester.pumpAndSettle();
    expect(find.text('9'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('«Уменьшить движение» — цифры меняются сразу', (tester) async {
    var now = DateTime(2026, 11, 7, 10, 59, 59);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: FlipClock(clock: () => now, reduceMotion: true)))));
    now = DateTime(2026, 11, 7, 11, 0, 0, 100);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('9'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('полоска карточки — ровно посередине (замечание владельца 09.11.2026)', (tester) async {
    final now = DateTime(2026, 11, 9, 8, 27);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: FlipClock(height: 60, clock: () => now)))));
    // Полоски — ColoredBox высотой 1 в каждой из четырёх карточек.
    final lines = find.byWidgetPredicate((w) => w is ColoredBox && w.child == null);
    final boxes = [
      for (final e in lines.evaluate())
        if (tester.getSize(find.byWidget(e.widget)).height == 1) tester.getRect(find.byWidget(e.widget)),
    ];
    expect(boxes, hasLength(4));
    final digit = tester.getRect(find.text('8'));
    final card = tester.getRect(find.ancestor(of: find.text('8'), matching: find.byType(Container)).first);
    for (final b in boxes.where((b) => b.left >= card.left && b.right <= card.right)) {
      expect(b.center.dy, closeTo(card.center.dy, 0.6), reason: 'середина карточки');
    }
    expect(digit.center.dy, closeTo(card.center.dy, 0.6), reason: 'цифра — тоже посередине');
  });
}

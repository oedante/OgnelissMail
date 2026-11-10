// Одно правило свайпов (2.2.0, решение владельца 09.11.2026): протянул до
// порога и отпустил — действие; два действия на стороне — по расстоянию
// (короткий — первое, длинный — второе), значок и подпись меняются, пока
// тянешь; не дотянул — строка возвращается. Результат и «Вернуть» — в
// swipe_done_test.
// Подсказка о свайпах — один раз.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/slidable_spring_back.dart';
import 'package:ogneliss/widgets/common/swipe_action_indicator.dart';
import 'package:ogneliss/widgets/common/swipe_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Строка как в ленте: одна панель, порог 0,4, второе действие с 0,7.
Widget _row(List<String> log, {GlobalKey? rowKey}) {
  final stage = SwipeStage();
  String chosen() => stage.position >= 0.7 ? 'delete' : 'read';
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 400,
        height: 72,
        child: Slidable(
          key: const ValueKey('row'),
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.28,
            dismissible: DismissiblePane(
              dismissThreshold: 0.4,
              closeOnCancel: true,
              confirmDismiss: () async {
                final a = chosen();
                stage.chosen = a;
                if (a == 'delete') return true;
                log.add(a);
                return false;
              },
              onDismissed: () => log.add(stage.chosen as String),
            ),
            children: [
              SlidableSpringBack(
                dismissThreshold: 0.4,
                stage: stage,
                child: CustomSlidableAction(
                  onPressed: (_) {},
                  padding: EdgeInsets.zero,
                  child: const SwipeActionIndicator(
                    icon: Icons.mark_email_read,
                    label: 'Прочитано',
                    color: Colors.blue,
                    fromStart: true,
                    atEdge: true,
                    extentRatio: 0.28,
                    armAt: 0.4,
                    second: SwipeStep(
                        icon: Icons.delete, label: 'Удалить', color: Colors.red, background: Colors.white, at: 0.7),
                  ),
                ),
              ),
            ],
          ),
          child: SizedBox(key: rowKey, width: 400, height: 72, child: const Text('Письмо')),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('значок и подпись: за краем — подпись первого, дальше 70 % — второе действие', (tester) async {
    final rowKey = GlobalKey();
    await tester.pumpWidget(_row([], rowKey: rowKey));
    final c = Slidable.of(rowKey.currentContext!)!;
    c.ratio = 0.2;
    await tester.pump();
    expect(find.byKey(const ValueKey('swipe_label')), findsNothing, reason: 'внутри панели — только значок');
    c.ratio = 0.4;
    await tester.pump();
    expect(find.text('Прочитано'), findsOneWidget);
    expect(find.byIcon(Icons.mark_email_read), findsOneWidget);
    c.ratio = 0.75;
    await tester.pump();
    expect(find.text('Удалить'), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('отпустили: до порога — назад, короткий — первое, длинный — второе', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_row(log));
    final row = find.text('Письмо');
    // Палец ведёт строку кадр за кадром, как на телефоне (панель действия
    // строится по ходу свайпа).
    Future<void> swipe(double dx) async {
      final g = await tester.startGesture(tester.getCenter(row) - const Offset(150, 0));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(dx / 10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      await g.up();
      await tester.pumpAndSettle();
    }

    await swipe(100); // 25 %
    expect(log, isEmpty);
    expect(tester.getTopLeft(row).dx, lessThan(1), reason: 'строка вернулась, кнопка не осталась открытой');

    await swipe(230); // ~55 %
    expect(log, ['read']);

    await swipe(330); // ~80 %
    expect(log, ['read', 'delete']);
  });

  testWidgets('подсказка: первая строка отъезжает и возвращается, второй раз — нет', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    SwipeHint.debugEnabled = true;
    SwipeHint.debugReset();
    addTearDown(() => SwipeHint.debugEnabled = null);
    final rowKey = GlobalKey();
    Widget app() => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 72,
              child: Slidable(
                key: const ValueKey('row'),
                startActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: 0.28,
                  children: [CustomSlidableAction(onPressed: (_) {}, child: const Icon(Icons.archive))],
                ),
                child: SwipeHint(
                  prefs: prefs,
                  start: true,
                  end: false,
                  child: SizedBox(key: rowKey, width: 400, height: 72, child: const Text('Письмо')),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 500));
    final c = Slidable.of(rowKey.currentContext!)!;
    expect(c.ratio, greaterThan(0.2), reason: 'строка отъехала');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(c.ratio, 0);
    expect(prefs.getBool(SwipeHint.prefKey), isTrue);

    SwipeHint.debugReset();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 1800));
    expect(Slidable.of(rowKey.currentContext!)!.ratio, 0, reason: 'второй раз подсказки нет');
  });
}

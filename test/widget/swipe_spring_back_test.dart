// Свайпы не застревают на середине (1.14.0, замечание владельца 05.11.2026:
// «Свайпы зависают на середине. И так у нескольких писем.»).
//
// Панель с одним действием устроена как в ленте (_buildActionPane):
// extentRatio 0,28, полный свайп — от 0,4. Раньше строка, отпущенная между
// ними (или до 0,28 быстрым движением), оставалась открытой.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/slidable_spring_back.dart';

const _w = 400.0;

class _Row {
  final GlobalKey key = GlobalKey();
  int fired = 0;
  int dismissed = 0;
}

Widget _singleRow(_Row r, String title, {bool removes = false}) => Slidable(
      key: ValueKey(title),
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.28,
        dismissible: DismissiblePane(
          dismissThreshold: 0.4,
          closeOnCancel: true,
          confirmDismiss: removes
              ? null
              : () async {
                  r.fired++;
                  return false;
                },
          onDismissed: () => r.dismissed++,
        ),
        children: [
          SlidableSpringBack(
            dismissThreshold: 0.4,
            child: CustomSlidableAction(onPressed: (_) => r.fired++, child: const Icon(Icons.done)),
          ),
        ],
      ),
      child: SizedBox(key: r.key, width: _w, height: 72, child: Text(title)),
    );

Widget _twoRow(_Row r, String title) => Slidable(
      key: ValueKey(title),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(onPressed: (_) {}, icon: Icons.done),
          SlidableAction(onPressed: (_) {}, icon: Icons.flag),
        ],
      ),
      child: SizedBox(key: r.key, width: _w, height: 72, child: Text(title)),
    );

Future<void> _host(WidgetTester tester, List<Widget> rows) async {
  await tester.binding.setSurfaceSize(const Size(_w, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SlidableAutoCloseBehavior(child: ListView(children: rows)),
    ),
  ));
}

double _ratio(_Row r) => Slidable.of(r.key.currentContext!)!.animation.value;

/// Протянуть строку на долю [to] ширины, подержать палец и отпустить.
Future<void> _dragHoldRelease(WidgetTester tester, String title, double to) async {
  final g = await tester.startGesture(tester.getCenter(find.text(title)));
  // Сначала — за порог распознавания жеста, потом — до нужного места.
  await g.moveBy(const Offset(30, 0));
  await tester.pump();
  await g.moveBy(Offset(_w * to, 0));
  await tester.pump();
  // Палец стоит — скорость при отпускании нулевая (StillGesture).
  await tester.pump(const Duration(milliseconds: 400));
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  test('сразу возвращается только строка, отпущенная до порога', () {
    expect(springsBackAt(0.15, 0.4), isTrue);
    expect(springsBackAt(0.33, 0.4), isTrue);
    expect(springsBackAt(0.45, 0.4), isFalse);
    expect(springsBackAt(0, 0.4), isFalse);
  });

  testWidgets('отпустили между панелью и порогом — строка возвращается, действие не выполняется', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо')]);
    final g = await tester.startGesture(tester.getCenter(find.text('Письмо')));
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(_w * 0.25, 0)); // 30 + 100 из 400 ≈ 0,33
    await tester.pump();
    final held = _ratio(r);
    expect(held, greaterThan(0.28));
    expect(held, lessThan(0.4));
    await tester.pump(const Duration(milliseconds: 400));
    await g.up();
    await tester.pumpAndSettle();
    expect(_ratio(r), 0, reason: 'раньше строка оставалась открытой на 28 %');
    expect(r.fired, 0);
    expect(r.dismissed, 0);
  });

  testWidgets('короткий свайп (меньше панели) — тоже назад', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо')]);
    await _dragHoldRelease(tester, 'Письмо', 0.15);
    expect(_ratio(r), 0);
    expect(r.fired, 0);
  });

  testWidgets('быстрый короткий свайп вперёд — назад, а не открытие', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо')]);
    await tester.timedDrag(find.text('Письмо'), const Offset(80, 0), const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(_ratio(r), 0);
    expect(r.fired, 0);
  });

  testWidgets('протянули за порог и вернули пальцем назад — строка на месте', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо')]);
    final g = await tester.startGesture(tester.getCenter(find.text('Письмо')));
    await g.moveBy(const Offset(30, 0));
    await tester.pump();
    await g.moveBy(const Offset(_w * 0.5, 0));
    await tester.pump();
    // Резко назад — отпускаем в движении к закрытию.
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(-12, 0), timeStamp: Duration(milliseconds: 500 + i * 8));
    }
    await g.up(timeStamp: const Duration(milliseconds: 545));
    await tester.pumpAndSettle();
    expect(_ratio(r), 0);
    expect(r.fired, 0);
    expect(r.dismissed, 0);
  });

  testWidgets('за порогом действие выполняется, строка возвращается', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо')]);
    await _dragHoldRelease(tester, 'Письмо', 0.5);
    expect(r.fired, 1);
    expect(_ratio(r), 0);
  });

  testWidgets('за порогом убирающее действие уводит строку', (tester) async {
    final r = _Row();
    await _host(tester, [_singleRow(r, 'Письмо', removes: true)]);
    await _dragHoldRelease(tester, 'Письмо', 0.5);
    expect(r.dismissed, 1);
  });

  testWidgets('две кнопки: открытой остаётся одна строка', (tester) async {
    final a = _Row(), b = _Row();
    await _host(tester, [_twoRow(a, 'Первое'), _twoRow(b, 'Второе')]);
    await _dragHoldRelease(tester, 'Первое', 0.4);
    expect(_ratio(a), closeTo(0.5, 0.001), reason: 'панель из двух кнопок ждёт выбора');
    await _dragHoldRelease(tester, 'Второе', 0.4);
    expect(_ratio(b), closeTo(0.5, 0.001));
    expect(_ratio(a), 0, reason: 'прежняя строка закрылась');
  });
}

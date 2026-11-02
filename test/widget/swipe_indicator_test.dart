// Свайп в ленте (1.10.3, просьба владельца 02.11.2026: «анимации свайпам, не
// сильно отвлекающие, в бизнес-стиле»): до порога значок контурный и без
// круга; за порогом — залитый, с мягким кругом цвета действия; значок при
// этом не сдвигается.

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/swipe_action_indicator.dart';

void main() {
  testWidgets('у порога значок заливается, круг проступает, место значка прежнее', (tester) async {
    final rowKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 72,
          child: Slidable(
            key: const ValueKey('row'),
            startActionPane: ActionPane(
              motion: const BehindMotion(),
              extentRatio: 0.28,
              // Как в ленте при одном действии: строку можно тянуть дальше
              // панели, до порога полного свайпа.
              dismissible: DismissiblePane(onDismissed: () {}, dismissThreshold: 0.6),
              children: [
                CustomSlidableAction(
                  onPressed: (_) {},
                  padding: EdgeInsets.zero,
                  child: const SwipeActionIndicator(
                    icon: Icons.archive,
                    label: 'В архив',
                    color: Colors.blue,
                    fromStart: true,
                    atEdge: true,
                    extentRatio: 0.28,
                    armAt: 0.4,
                  ),
                ),
              ],
            ),
            child: SizedBox(key: rowKey, width: 400, height: 72, child: const Text('Письмо')),
          ),
        ),
      ),
    ));
    final controller = Slidable.of(rowKey.currentContext!)!;

    Icon icon() => tester.widget<Icon>(find.byIcon(Icons.archive));
    controller.ratio = 0.2;
    await tester.pump();
    expect(icon().fill, 0);
    final before = tester.getCenter(find.byIcon(Icons.archive));

    controller.ratio = 0.4;
    await tester.pump();
    expect(icon().fill, closeTo(1, 0.001));
    final after = tester.getCenter(find.byIcon(Icons.archive));
    expect((after - before).dx.abs(), lessThan(0.5), reason: 'круг не сдвигает значок');
    expect(
      find.descendant(
        of: find.byType(SwipeActionIndicator),
        matching: find.byWidgetPredicate(
            (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle),
      ),
      findsOneWidget,
    );
  });
}

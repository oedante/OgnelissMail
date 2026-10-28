// test/widget/adaptive_layout_test.dart
// 1.6.28: деление «список + панель» — по ширине области; на широком окне
// панель есть и до выбора (подсказка), потомки узнают раскладку через
// AdaptiveLayout.isSplit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/adaptive_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host(double width, {bool show = false}) {
  bool? split;
  return MaterialApp(
    home: Center(
      child: SizedBox(
        width: width,
        height: 600,
        child: AdaptiveLayout(
          widthKey: 'test',
          showDetail: show,
          detailBody: show ? const Text('ПИСЬМО') : null,
          placeholder: const Text('ВЫБЕРИТЕ'),
          body: Builder(builder: (context) {
            split = AdaptiveLayout.splitOf(context);
            return Text('СПИСОК split=$split');
          }),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('узкая область — только список', (t) async {
    await t.pumpWidget(_host(500));
    expect(find.text('СПИСОК split=false'), findsOneWidget);
    expect(find.text('ВЫБЕРИТЕ'), findsNothing);
  });

  testWidgets('широкая — список и подсказка до выбора', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(1000));
    expect(find.text('СПИСОК split=true'), findsOneWidget);
    expect(find.text('ВЫБЕРИТЕ'), findsOneWidget);
  });

  testWidgets('широкая — выбранное письмо в панели', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(1000, show: true));
    expect(find.text('ПИСЬМО'), findsOneWidget);
    expect(find.text('ВЫБЕРИТЕ'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/text_scale_cap.dart';

void main() {
  Future<double> scaleUnder(WidgetTester tester, double system, Widget Function(Widget) wrap) async {
    late double seen;
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(system)),
      child: wrap(Builder(builder: (context) {
        seen = context.textScale;
        return const SizedBox();
      })),
    ));
    return seen;
  }

  testWidgets('TextScaleCap ограничивает масштаб сверху', (tester) async {
    expect(await scaleUnder(tester, 2.0, (c) => TextScaleCap(child: c)), TextScaleLimits.chrome);
    expect(await scaleUnder(tester, 2.0, (c) => TextScaleCap.grid(child: c)), TextScaleLimits.grid);
  });

  testWidgets('TextScaleCap не увеличивает обычный шрифт', (tester) async {
    expect(await scaleUnder(tester, 1.0, (c) => TextScaleCap(child: c)), 1.0);
    expect(await scaleUnder(tester, 0.9, (c) => TextScaleCap.compact(child: c)), 0.9);
  });

  testWidgets('isLargeText', (tester) async {
    late bool large;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
      child: Builder(builder: (context) {
        large = context.isLargeText;
        return const SizedBox();
      }),
    ));
    expect(large, isTrue);
  });
}

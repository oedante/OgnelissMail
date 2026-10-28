// test/widget/calendar_day_icon_test.dart
// 1.7.2+108: число на значке календаря — по центру листа (5/8 высоты,
// середина ширины), системный крупный шрифт его не увеличивает, цвет — как
// у значка; без числа в параметрах — сегодняшнее.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/calendar_day_icon.dart';

Widget _host(Widget icon, {double textScale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Center(
          child: IconTheme(
            data: const IconThemeData(size: 24, color: Color(0xFF445566)),
            child: icon,
          ),
        ),
      ),
    );

void main() {
  testWidgets('число — по центру листа значка', (t) async {
    await t.pumpWidget(_host(const CalendarDayIcon(day: 24)));
    final icon = t.getRect(find.byType(CalendarDayIcon));
    final number = t.getRect(find.text('24'));
    expect(icon.size, const Size(24, 24));
    expect(number.center.dx - icon.left, moreOrLessEquals(12, epsilon: 0.01));
    expect(number.center.dy - icon.top, moreOrLessEquals(15, epsilon: 0.01), reason: 'центр листа — 5/8 высоты');
    expect(number.top, greaterThanOrEqualTo(icon.top + 10), reason: 'не залезает на полосу с кольцами');
    expect(number.bottom, lessThanOrEqualTo(icon.top + 20), reason: 'не ложится на нижнюю рамку');
  });

  testWidgets('крупный системный шрифт число не увеличивает', (t) async {
    await t.pumpWidget(_host(const CalendarDayIcon(day: 31)));
    final normal = t.getSize(find.text('31'));
    await t.pumpWidget(_host(const CalendarDayIcon(day: 31), textScale: 2));
    expect(t.getSize(find.text('31')), normal);
  });

  testWidgets('цвет числа — как у значка', (t) async {
    await t.pumpWidget(_host(const CalendarDayIcon(day: 7)));
    final text = t.widget<Text>(find.text('7'));
    final icon = t.widget<Icon>(find.byType(Icon));
    expect(text.style?.color, const Color(0xFF445566));
    expect(icon.color, const Color(0xFF445566));
  });

  testWidgets('без числа — сегодняшнее', (t) async {
    await t.pumpWidget(_host(const CalendarDayIcon()));
    expect(find.text('${DateTime.now().day}'), findsOneWidget);
  });
}

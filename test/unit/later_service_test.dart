// test/unit/later_service_test.dart
// «Посмотреть позже»: быстрые сроки меню.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/later_service.dart';

Map<String, DateTime?> _opts(DateTime now) => {for (final o in LaterService.options(now)) o.key: o.at};

void main() {
  test('пятница 14:03: через час — 15:05, завтра и послезавтра — 9:00, неделя — понедельник', () {
    final o = _opts(DateTime(2026, 10, 9, 14, 3, 27));
    expect(o['laterIn1h'], DateTime(2026, 10, 9, 15, 5));
    expect(o['laterIn3h'], DateTime(2026, 10, 9, 17, 5));
    expect(o['laterTomorrow'], DateTime(2026, 10, 10, 9));
    expect(o['laterDayAfter'], DateTime(2026, 10, 11, 9));
    expect(o['laterNextWeek'], DateTime(2026, 10, 12, 9));
    expect(o.containsKey('laterNoDate'), isTrue);
    expect(o['laterNoDate'], isNull);
  });

  test('в понедельник «на следующей неделе» — через неделю; ровное время не сдвигается', () {
    final o = _opts(DateTime(2026, 10, 12, 10, 0));
    expect(o['laterNextWeek'], DateTime(2026, 10, 19, 9));
    expect(o['laterIn1h'], DateTime(2026, 10, 12, 11, 0));
  });

  test('конец месяца: завтра — 1-е число следующего', () {
    final o = _opts(DateTime(2026, 10, 31, 20, 0));
    expect(o['laterTomorrow'], DateTime(2026, 11, 1, 9));
  });
}

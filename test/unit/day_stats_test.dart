// «Мой день»: занятость, свободное окно, пересечения встреч (DayStats).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/my_day/day_stats.dart';

final _d = DateTime(2026, 10, 12);
DateTime _t(int h, [int m = 0]) => _d.add(Duration(hours: h, minutes: m));
DayMeeting _m(String id, int h1, int m1, int h2, int m2, {bool free = false}) =>
    DayMeeting(id: id, title: id, start: _t(h1, m1), end: _t(h2, m2), free: free);

void main() {
  final dayStart = _d, dayEnd = _d.add(const Duration(days: 1));

  test('занятость: пересечения сливаются, «свободен» не считается', () {
    final busy = DayStats.busy([
      _m('a', 9, 0, 10, 0),
      _m('b', 9, 30, 11, 0),
      _m('c', 13, 0, 14, 0),
      _m('free', 15, 0, 16, 0, free: true),
    ], dayStart: dayStart, dayEnd: dayEnd);
    expect(busy, [Span(_t(9), _t(11)), Span(_t(13), _t(14))]);
    expect(DayStats.meetingTime(busy), const Duration(hours: 3));
  });

  test('встреча со вчера обрезается началом дня', () {
    final busy = DayStats.busy([
      DayMeeting(id: 'x', title: 'x', start: _d.subtract(const Duration(hours: 2)), end: _t(1)),
    ], dayStart: dayStart, dayEnd: dayEnd);
    expect(busy.single, Span(_d, _t(1)));
  });

  group('ближайшее свободное окно', () {
    final busy = [Span(_t(9), _t(11)), Span(_t(11, 15), _t(12)), Span(_t(13), _t(17, 45))];

    test('окно короче 30 минут пропускается', () {
      expect(DayStats.nextFree(busy, from: _t(9, 30), until: _t(18)), Span(_t(12), _t(13)));
    });

    test('после последней встречи до конца дня — только если ≥ 30 минут', () {
      expect(DayStats.nextFree(busy, from: _t(13, 30), until: _t(18)), isNull);
      expect(DayStats.nextFree(busy, from: _t(13, 30), until: _t(18, 30)), Span(_t(17, 45), _t(18, 30)));
    });

    test('свободно прямо сейчас', () {
      expect(DayStats.nextFree(busy, from: _t(8), until: _t(18)), Span(_t(8), _t(9)));
    });

    test('рабочий день закончился — окна нет', () {
      expect(DayStats.nextFree(busy, from: _t(19), until: _t(18)), isNull);
    });
  });

  test('пересечения: взаимные, встык — не пересечение, «свободен» — нет', () {
    final c = DayStats.conflicts([
      _m('a', 10, 0, 11, 0),
      _m('b', 10, 30, 11, 30),
      _m('c', 11, 30, 12, 0), // встык с b
      _m('d', 10, 45, 11, 15, free: true),
    ]);
    expect(c.keys.toSet(), {'a', 'b'});
    expect(c['a'], ['b']);
    expect(c['b'], ['a']);
  });

  test('рабочие часы: окно через полночь — 9–18', () {
    expect(DayStats.workHours(_d, 7 * 60, 19 * 60), Span(_t(7), _t(19)));
    expect(DayStats.workHours(_d, 22 * 60, 6 * 60), Span(_t(9), _t(18)));
  });
}

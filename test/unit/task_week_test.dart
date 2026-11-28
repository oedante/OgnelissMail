// Задачи по неделям (4PDA, 28.11.2026): в субботу задачи на понедельник —
// «На следующей неделе», а не «На этой неделе».
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/tasks/screens/tasks_screen.dart' show weekEndAfter;

void main() {
  test('конец недели — по календарю', () {
    // Суббота 28.11.2026, неделя с понедельника — следующая с 30.11.
    expect(weekEndAfter(DateTime(2026, 11, 28), 1), DateTime(2026, 11, 30));
    // Понедельник 30.11 — неделя до следующего понедельника 7.12.
    expect(weekEndAfter(DateTime(2026, 11, 30), 1), DateTime(2026, 12, 7));
    // Воскресенье 29.11 с понедельника — следующая с 30.11 (завтра).
    expect(weekEndAfter(DateTime(2026, 11, 29), 1), DateTime(2026, 11, 30));
    // Неделя с воскресенья: суббота 28.11 — следующая с 29.11.
    expect(weekEndAfter(DateTime(2026, 11, 28), 0), DateTime(2026, 11, 29));
  });
}

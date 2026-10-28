// Сводка режима фокуса (1.5.1): задержанные письма копятся (не больше шести
// строк, свежие сверху) и забираются одним уведомлением; второй раз — пусто.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/focus_mode_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('пусто — нечего показывать', () async {
    final p = await SharedPreferences.getInstance();
    expect(await FocusDigest.take(p), isNull);
    await FocusDigest.hold(p, const []);
    expect(await FocusDigest.take(p), isNull);
  });

  test('копится между проверками, строк не больше шести', () async {
    final p = await SharedPreferences.getInstance();
    await FocusDigest.hold(p, ['a1', 'a2', 'a3']);
    await FocusDigest.hold(p, ['b1', 'b2', 'b3', 'b4']);
    final d = await FocusDigest.take(p);
    expect(d, isNotNull);
    expect(d!.count, 7, reason: 'число — все письма, а не только показанные строки');
    expect(d.lines.length, 6);
    // Последняя порция — сверху.
    expect(d.lines.take(4).toSet(), {'b1', 'b2', 'b3', 'b4'});
  });

  test('после показа сводка очищается', () async {
    final p = await SharedPreferences.getInstance();
    await FocusDigest.hold(p, ['x']);
    expect((await FocusDigest.take(p))!.count, 1);
    expect(await FocusDigest.take(p), isNull);
  });
}

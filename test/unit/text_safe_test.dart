// test/unit/text_safe_test.dart
// Обрезка и первая буква без разрыва эмодзи (журнал 09.10.2026: «string is
// not well-formed UTF-16»).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/text_safe.dart';

void main() {
  test('обрезка не разрывает эмодзи', () {
    const s = 'ab😀cd'; // 😀 — две единицы UTF-16 (индексы 2 и 3)
    expect(cutSafe(s, 3), 'ab');
    expect(cutSafe(s, 4), 'ab😀');
    expect(cutSafe(s, 100), s);
  });

  test('первая буква: эмодзи целиком, буква — заглавная, пусто — «?»', () {
    expect(initialOf('😀 Отдел'), '😀');
    expect(initialOf('  иван'), 'И');
    expect(initialOf(''), '?');
    expect(initialOf(null), '?');
    expect(initialOf('\uDC00x'), '?');
  });

  test('половинки без пары заменяются, целые пары остаются', () {
    expect(fixUtf16('ok😀'), 'ok😀');
    expect(fixUtf16('a\uD83D'), 'a�');
    expect(fixUtf16('\uDE00b'), '�b');
  });
}

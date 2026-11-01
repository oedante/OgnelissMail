// Замер открытия письма (OpenTrace): отметки последнего замера — для замеров
// скорости на эмуляторе (integration_test/perf_test.dart; 1.9.x, просьба
// владельца 31.10.2026).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/logging/open_trace.dart';

void main() {
  test('done() сохраняет этапы: первая отметка каждого, текст — последним', () {
    OpenTrace.start();
    OpenTrace.mark('окно');
    OpenTrace.mark('заранее: нет окна');
    OpenTrace.mark('загрузка');
    OpenTrace.mark('загрузка');
    OpenTrace.done();
    final m = OpenTrace.lastMarks;
    expect(m.keys, ['окно', 'заранее: нет окна', 'загрузка', 'текст']);
    expect(m.values.every((v) => v >= 0), isTrue);
    expect(m['текст']! >= m['окно']!, isTrue);
  });

  test('без нажатия (start) отметки не пишутся и прежний замер не меняется', () {
    OpenTrace.start();
    OpenTrace.mark('окно');
    OpenTrace.done();
    final before = OpenTrace.lastMarks;
    OpenTrace.mark('кадр');
    OpenTrace.done();
    expect(OpenTrace.lastMarks, same(before));
    OpenTrace.cancel();
  });
}

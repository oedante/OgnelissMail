// Перетаскивание в списках через onReorder (1.10.5): код собирается и во
// Flutter для ОС Аврора 3.41, где onReorderItem ещё нет.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/reorder_index.dart';

void main() {
  test('вниз — место после удаления на одно меньше, вверх — то же', () {
    // Как ReorderableListView.onReorder: [A,B,C], A в конец — (0, 3).
    final l = ['A', 'B', 'C'];
    final a = [...l];
    a.insert(reorderTarget(0, 3), a.removeAt(0));
    expect(a, ['B', 'C', 'A']);
    final b = [...l];
    b.insert(reorderTarget(2, 0), b.removeAt(2));
    expect(b, ['C', 'A', 'B']);
    final c = [...l];
    c.insert(reorderTarget(1, 1), c.removeAt(1));
    expect(c, l);
  });
}

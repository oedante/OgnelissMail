// 1.8.0: удалённая папка уходит из меню вместе с подпапками.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/folder_subtree.dart';

void main() {
  test('Exchange: потомки по родителю, соседи не задеты', () {
    final parentOf = <String, String?>{
      'inbox': null,
      'work': null,
      'w1': 'work',
      'w2': 'work',
      'w11': 'w1',
      'other': null,
    };
    expect(folderSubtreeIds(parentOf, 'work'), {'work', 'w1', 'w2', 'w11'});
    expect(folderSubtreeIds(parentOf, 'w1'), {'w1', 'w11'});
    expect(folderSubtreeIds(parentOf, 'other'), {'other'});
  });

  test('IMAP: потомки по пути', () {
    final parentOf = <String, String?>{
      'INBOX': null,
      'Работа': null,
      'Работа/2026': null,
      'Работа/2026/Отчёты': null,
      'Работы': null,
    };
    expect(folderSubtreeIds(parentOf, 'Работа'), {'Работа', 'Работа/2026', 'Работа/2026/Отчёты'});
  });
}

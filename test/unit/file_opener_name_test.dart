// Вложение открывается и пересылается под именем из письма (1.6.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/file_opener.dart';

void main() {
  test('имя файла: запрещённые символы заменяются, расширение сохраняется', () {
    expect(FileOpener.safeName('УВЕДОМЛЕНИЕ Хуснутдинова Ю.Р..pdf'), 'УВЕДОМЛЕНИЕ Хуснутдинова Ю.Р..pdf');
    expect(FileOpener.safeName('a/b:c*?.docx'), 'a_b_c__.docx');
    expect(FileOpener.safeName('  .hidden.txt '), 'hidden.txt');
    expect(FileOpener.safeName(''), '');
    final long = FileOpener.safeName('${'я' * 200}.pdf');
    expect(long.length, 120);
    expect(long.endsWith('.pdf'), isTrue);
  });
}

// Нагрузка синхронизации (2.6.8, журнал владельца 21.11.2026): заметки
// не читаются, если папка не изменилась. Папки почты — все выбранные в
// каждый проход, по расписанию ящика (правило владельца 22.11.2026).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  test('отпечаток папки заметок меняется с новым письмом и с удалением', () {
    final a = ImapService.notesSignature(exists: 12, uidNext: 40, uidValidity: 7, modSeq: 900);
    expect(ImapService.notesSignature(exists: 12, uidNext: 40, uidValidity: 7, modSeq: 900), a);
    expect(ImapService.notesSignature(exists: 13, uidNext: 41, uidValidity: 7, modSeq: 901), isNot(a));
    expect(ImapService.notesSignature(exists: 11, uidNext: 40, uidValidity: 7, modSeq: 900), isNot(a));
  });
}

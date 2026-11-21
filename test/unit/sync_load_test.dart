// Нагрузка синхронизации (2.6.8, журнал владельца 21.11.2026): в фоне —
// «Входящие» каждый раз, остальные папки IMAP — раз в 30 минут; заметки
// не читаются, если папка не изменилась.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/sync/sync_service.dart';

void main() {
  FolderModel folder(String id, FolderType type) =>
      FolderModel(id: id, accountId: 'a1', displayName: id, type: type);

  test('свёрнуто: «Входящие» — всегда, остальные — раз в 30 минут', () {
    final now = DateTime(2026, 11, 21, 22);
    final inbox = folder('INBOX', FolderType.inbox);
    final spam = folder('Spam', FolderType.junk);
    expect(SyncService.imapFolderDue(inbox, now.toIso8601String(), now), isTrue);
    expect(SyncService.imapFolderDue(spam, null, now), isTrue, reason: 'ещё не проверялась');
    expect(SyncService.imapFolderDue(spam, now.subtract(const Duration(minutes: 10)).toIso8601String(), now), isFalse);
    expect(SyncService.imapFolderDue(spam, now.subtract(const Duration(minutes: 31)).toIso8601String(), now), isTrue);
  });

  test('отпечаток папки заметок меняется с новым письмом и с удалением', () {
    final a = ImapService.notesSignature(exists: 12, uidNext: 40, uidValidity: 7, modSeq: 900);
    expect(ImapService.notesSignature(exists: 12, uidNext: 40, uidValidity: 7, modSeq: 900), a);
    expect(ImapService.notesSignature(exists: 13, uidNext: 41, uidValidity: 7, modSeq: 901), isNot(a));
    expect(ImapService.notesSignature(exists: 11, uidNext: 40, uidValidity: 7, modSeq: 900), isNot(a));
  });
}

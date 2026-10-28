// «Вся почта»: какие папки попадают в общую ленту по умолчанию.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';

void main() {
  test('входящие, отправленные, архив и свои папки — во «Всей почте»', () {
    // Отправленные — с 06.10.2026: лента показывает переписку целиком.
    for (final t in [
      FolderType.inbox, FolderType.sent, FolderType.archive, FolderType.custom,
    ]) {
      expect(FolderModel.unifiedByDefault(t), isTrue, reason: '$t');
    }
  });

  test('черновики, исходящие, корзина, спам — нет', () {
    for (final t in [
      FolderType.drafts, FolderType.outbox, FolderType.trash, FolderType.junk,
    ]) {
      expect(FolderModel.unifiedByDefault(t), isFalse, reason: '$t');
    }
  });
}

// Папки Яндекса (1.10.3, журнал владельца 02.11.2026): «Шаблоны»
// (Drafts|template) удалить нельзя — пунктов удаления и переименования у неё
// нет; отказ сервера — понятным текстом, без кода и номера запроса.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/mail/widgets/mail_drawer.dart' show serverRefusalText;

FolderModel _f(String path) => FolderModel(id: path, accountId: 'a', displayName: path, serverPath: path);

void main() {
  test('«Шаблоны» Яндекса защищены, обычные папки — нет', () {
    expect(_f('Drafts|template').isLocked, isTrue);
    expect(_f('Drafts|template').isServerProtected, isTrue);
    expect(_f('Drafts/template').isLocked, isFalse, reason: 'не Яндекс — своя папка пользователя');
    expect(_f('Work|template').isLocked, isFalse);
    expect(_f('Projects').isLocked, isFalse);
  });

  test('текст отказа сервера', () {
    expect(serverRefusalText('Сервер отклонил удаление', '[UNAVAILABLE] DELETE Backend error. sc=LFtoD10d2Os0_2026-11-02-19-18_'),
        'Сервер отклонил удаление: Backend error');
    expect(serverRefusalText('Сервер отклонил удаление', 'ImapException: [NOPERM] Permission denied'),
        'Сервер отклонил удаление: Permission denied');
    expect(serverRefusalText('Сервер отклонил удаление', '[CANNOT]'), 'Сервер отклонил удаление');
  });
}

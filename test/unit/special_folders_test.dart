// test/unit/special_folders_test.dart
// Папки «Архив» и «Спам» (1.7.2+106, lib/services/mail/special_folders.dart):
// распознавание по названию на разных языках, приоритет типа от сервера,
// ручной выбор.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/services/mail/special_folders.dart';

FolderModel _f(String id, String name, {FolderType type = FolderType.custom, String? parent, bool unified = true}) =>
    FolderModel(id: id, accountId: 'a', parentId: parent, displayName: name, type: type, showInUnified: unified);

FolderType _typeOf(List<FolderModel> list, String id) => list.firstWhere((f) => f.id == id).type;

void main() {
  group('названия', () {
    test('Exchange на разных языках', () {
      for (final n in ['Нежелательная почта', 'Junk Email', 'Junk E-mail', 'Junk-E-Mail', 'Courrier indésirable',
          'Posta indesiderata', 'Correo no deseado', 'Wiadomości-śmieci', 'Небажана пошта', '迷惑メール', 'Спам', 'Spam']) {
        expect(SpecialFolders.typeByName(n), FolderType.junk, reason: n);
      }
      for (final n in ['Архив', 'Archive', 'Archives', 'Archiv', 'Archivio', 'Archivo', 'Archief', 'Archiwum', 'Arşiv']) {
        expect(SpecialFolders.typeByName(n), FolderType.archive, reason: n);
      }
    });

    test('регистр, пробелы, дефисы и диакритика не важны', () {
      expect(SpecialFolders.typeByName('  junk email '), FolderType.junk);
      expect(SpecialFolders.typeByName('JUNK-EMAIL'), FolderType.junk);
      expect(SpecialFolders.typeByName('Courrier indesirable'), FolderType.junk);
      expect(SpecialFolders.typeByName('НЕЖЕЛАТЕЛЬНАЯ  ПОЧТА'), FolderType.junk);
      expect(SpecialFolders.typeByName('Arsiv'), FolderType.archive);
    });

    test('прочие названия — нет', () {
      for (final n in ['Входящие', 'Архив 2019', 'Проекты', 'Spam filter', 'Удалённые', '']) {
        expect(SpecialFolders.typeByName(n), isNull, reason: n);
      }
    });
  });

  group('apply', () {
    final eas = [
      _f('inbox', 'Входящие', type: FolderType.inbox),
      _f('del', 'Удаленные', type: FolderType.trash),
      _f('arch', 'Архив'),
      _f('junk', 'Нежелательная почта'),
      _f('proj', 'Проекты'),
      _f('projArch', 'Архив', parent: 'proj'),
    ];

    test('ActiveSync: «Архив» и «Нежелательная почта» верхнего уровня', () {
      final out = SpecialFolders.apply(eas);
      expect(_typeOf(out, 'arch'), FolderType.archive);
      expect(_typeOf(out, 'junk'), FolderType.junk);
      expect(_typeOf(out, 'projArch'), FolderType.custom, reason: 'подпапка проекта — не архив ящика');
      expect(out.firstWhere((f) => f.id == 'junk').showInUnified, isFalse, reason: 'спам — не во «Всей почте»');
      expect(out.firstWhere((f) => f.id == 'arch').showInUnified, isTrue);
      expect(out.length, eas.length);
      expect([for (final f in out) f.id], [for (final f in eas) f.id], reason: 'порядок не меняется');
    });

    test('тип от сервера главнее названия', () {
      final out = SpecialFolders.apply([
        _f('inbox', 'INBOX', type: FolderType.inbox),
        _f('j', 'Junk', type: FolderType.junk, unified: false),
        _f('s', 'Spam'),
      ]);
      expect(_typeOf(out, 'j'), FolderType.junk);
      expect(_typeOf(out, 's'), FolderType.custom);
    });

    test('папка прямо во «Входящих» (Dovecot INBOX.Archive)', () {
      final out = SpecialFolders.apply([
        _f('INBOX', 'INBOX', type: FolderType.inbox),
        _f('INBOX.Archive', 'Archive', parent: 'INBOX'),
        _f('INBOX.Spam', 'Spam', parent: 'INBOX'),
      ]);
      expect(_typeOf(out, 'INBOX.Archive'), FolderType.archive);
      expect(_typeOf(out, 'INBOX.Spam'), FolderType.junk);
    });

    test('ручной выбор: выбранная получает тип, прежняя теряет', () {
      final out = SpecialFolders.apply([
        ...eas,
        _f('old', 'Старое'),
      ], archiveId: 'old');
      expect(_typeOf(out, 'old'), FolderType.archive);
      expect(_typeOf(out, 'arch'), FolderType.custom, reason: 'по названию не распознаём, раз выбрано вручную');
      expect(_typeOf(out, 'junk'), FolderType.junk, reason: 'спам — по-прежнему автоматически');
    });

    test('ручной выбор снимает тип, данный сервером', () {
      final out = SpecialFolders.apply([
        _f('INBOX', 'INBOX', type: FolderType.inbox),
        _f('Junk', 'Junk', type: FolderType.junk, unified: false),
        _f('Filtered', 'Отфильтрованные'),
      ], junkId: 'Filtered');
      expect(_typeOf(out, 'Filtered'), FolderType.junk);
      expect(_typeOf(out, 'Junk'), FolderType.custom);
      expect(out.firstWhere((f) => f.id == 'Junk').showInUnified, isTrue, reason: 'бывший спам — снова во «Всей почте»');
    });

    test('системную папку выбрать нельзя; исчезнувшая — распознавание', () {
      final a = SpecialFolders.apply(eas, archiveId: 'inbox');
      expect(_typeOf(a, 'inbox'), FolderType.inbox);
      expect(_typeOf(a, 'arch'), FolderType.archive);
      final b = SpecialFolders.apply(eas, junkId: 'gone');
      expect(_typeOf(b, 'junk'), FolderType.junk);
    });

    test('одна папка не бывает и архивом, и спамом', () {
      final out = SpecialFolders.apply(eas, archiveId: 'proj', junkId: 'proj');
      expect(_typeOf(out, 'proj'), FolderType.archive);
      expect(_typeOf(out, 'junk'), FolderType.junk);
    });
  });
}

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
      for (final n in ['Входящие', 'Архив 2019', 'Проекты', 'Spam filter', 'Черновики 2', '']) {
        expect(SpecialFolders.typeByName(n), isNull, reason: n);
      }
    });

    test('черновики, отправленные, корзина (21.11.2026: «Drafts» у iCloud)', () {
      for (final n in ['Drafts', 'Черновики', 'Entwürfe', 'Brouillons']) {
        expect(SpecialFolders.typeByName(n), FolderType.drafts, reason: n);
      }
      for (final n in ['Sent Messages', 'Отправленные', 'Gesendet']) {
        expect(SpecialFolders.typeByName(n), FolderType.sent, reason: n);
      }
      for (final n in ['Deleted Messages', 'Удалённые', 'Корзина', 'Trash']) {
        expect(SpecialFolders.typeByName(n), FolderType.trash, reason: n);
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

  test('iCloud: «Drafts» без пометки сервера — черновики; помеченная сервером — главнее', () {
    final list = SpecialFolders.apply([
      _f('INBOX', 'INBOX', type: FolderType.inbox),
      _f('Drafts', 'Drafts'),
      _f('Sent', 'Sent Messages', type: FolderType.sent),
      _f('Old', 'Отправленные'),
      _f('Proj/Drafts', 'Drafts', parent: 'Proj'),
      _f('Proj', 'Proj'),
    ]);
    expect(_typeOf(list, 'Drafts'), FolderType.drafts);
    expect(_typeOf(list, 'Proj/Drafts'), FolderType.custom);
    expect(_typeOf(list, 'Old'), FolderType.custom);
  });

  // «Исходящие» на разных языках (2.6.8, замечание владельца 22.11.2026:
  // «папки на разных языках могут называться по-разному»): у ящика своя
  // папка — меню показывает в ней очередь отправки, без второй строки.
  group('«Исходящие»', () {
    test('названия на разных языках', () {
      for (final n in ['Outbox', 'Исходящие', 'Postausgang', "Boîte d'envoi", 'Boite denvoi', 'Bandeja de salida',
          'Posta in uscita', 'Caixa de Saída', 'Postvak UIT', 'Skrzynka nadawcza', 'Pošta k odeslání', 'Utkorgen',
          'Udbakke', 'Lähtevät', 'Giden Kutusu', 'Εξερχόμενα', '送信トレイ', '发件箱', '보낼 편지함', 'Вихідні']) {
        expect(SpecialFolders.typeByName(n), FolderType.outbox, reason: n);
      }
      for (final n in ['Outbox 2019', 'Исходящие клиентам', 'Отправленные']) {
        expect(SpecialFolders.typeByName(n), isNot(FolderType.outbox), reason: n);
      }
    });

    test('IMAP: папка верхнего уровня — «Исходящие», не во «Всей почте»; вложенная — нет', () {
      final out = SpecialFolders.apply([
        _f('INBOX', 'INBOX', type: FolderType.inbox),
        _f('Postausgang', 'Postausgang'),
        _f('Projekte', 'Projekte'),
        _f('Projekte/Postausgang', 'Postausgang', parent: 'Projekte'),
      ]);
      expect(_typeOf(out, 'Postausgang'), FolderType.outbox);
      expect(out.firstWhere((f) => f.id == 'Postausgang').showInUnified, isFalse);
      expect(_typeOf(out, 'Projekte/Postausgang'), FolderType.custom);
    });

    test('Exchange указал «Исходящие» сам — папка с таким же названием остаётся обычной', () {
      final out = SpecialFolders.apply([
        _f('AAMkOutbox', 'Исходящие', type: FolderType.outbox, unified: false),
        _f('AAMkOld', 'Outbox'),
      ]);
      expect(_typeOf(out, 'AAMkOutbox'), FolderType.outbox);
      expect(_typeOf(out, 'AAMkOld'), FolderType.custom);
    });

    test('больше языков у черновиков, отправленных, корзины', () {
      expect(SpecialFolders.typeByName('Wersje robocze'), FolderType.drafts);
      expect(SpecialFolders.typeByName('下書き'), FolderType.drafts);
      expect(SpecialFolders.typeByName('Elementos enviados'), FolderType.sent);
      expect(SpecialFolders.typeByName('보낸 편지함'), FolderType.sent);
      expect(SpecialFolders.typeByName('Gelöschte Objekte'), FolderType.trash);
      expect(SpecialFolders.typeByName('Papperskorgen'), FolderType.trash);
    });
  });
}

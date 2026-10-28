// test/unit/draft_files_test.dart
// 1.7.2+111: черновик хранит файлы письма (DraftFiles): копия в папке
// черновика, повторное сохранение не копирует заново, убранный файл
// удаляется, не скачанные вложения — ссылкой, «[]» — черновик без файлов.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/draft_autosave_service.dart';
import 'package:ogneliss/services/mail/draft_files.dart';

void main() {
  late Directory root;
  late Directory src;

  setUp(() {
    root = Directory.systemTemp.createTempSync('draft_files_root');
    src = Directory.systemTemp.createTempSync('draft_files_src');
    DraftFiles.debugRoot = root;
  });

  tearDown(() {
    DraftFiles.debugRoot = null;
    for (final d in [root, src]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  File srcFile(String name, List<int> bytes) => File('${src.path}/$name')..writeAsBytesSync(bytes);

  List<File> filesIn(String draftId) {
    final d = Directory('${root.path}/$draftId');
    return d.existsSync() ? d.listSync().whereType<File>().toList() : const [];
  }

  test('свой файл — копией в папку черновика, повторно не копируется', () async {
    final f = srcFile('Отчёт за май.pdf', [1, 2, 3, 4]);
    final json = await DraftFiles.store('draft-1', [
      DraftFile.local(name: 'Отчёт за май.pdf', size: 4, mimeType: 'application/pdf', path: f.path),
    ]);
    final list = jsonDecode(json) as List;
    expect(list, hasLength(1));
    expect((list.first as Map)['name'], 'Отчёт за май.pdf');
    expect((list.first as Map)['draftFile'], startsWith('draft-1/'));
    expect(filesIn('draft-1'), hasLength(1));

    // Тот же источник при следующем автосохранении — без новой копии.
    await DraftFiles.store('draft-1', [DraftFile.local(name: 'Отчёт за май.pdf', size: 4, path: f.path)]);
    expect(filesIn('draft-1'), hasLength(1));

    // Черновик открыли снова: файл — из папки черновика, исходника может уже не быть.
    f.deleteSync();
    final loaded = (await DraftFiles.load(json))!;
    expect(loaded, hasLength(1));
    expect(loaded.first.isRemote, isFalse);
    expect(loaded.first.path, startsWith('${root.path}/draft-1/'));
    expect(File(loaded.first.path!).readAsBytesSync(), [1, 2, 3, 4]);
    expect(loaded.first.mimeType, 'application/pdf');

    // Сохранили с путём из папки черновика — тоже без копии.
    await DraftFiles.store('draft-1', loaded);
    expect(filesIn('draft-1'), hasLength(1));
  });

  test('файл из памяти, убранный файл и ссылка на вложение сервера', () async {
    final a = srcFile('a.txt', utf8.encode('A'));
    final mem = Uint8List.fromList([9, 8, 7]);
    await DraftFiles.store('draft-2', [
      DraftFile.local(name: 'a.txt', size: 1, path: a.path),
      DraftFile.local(name: 'photo.jpg', size: 3, bytes: mem),
    ]);
    expect(filesIn('draft-2'), hasLength(2));

    final json = await DraftFiles.store('draft-2', [
      DraftFile.local(name: 'photo.jpg', size: 3, bytes: mem),
      const DraftFile.remote(
          name: 'Договор.docx', size: 2048, accountId: 'acc1', emailId: 'AAMk1', attachmentId: 'att-7'),
    ]);
    // a.txt убрали из письма — из папки тоже.
    expect(filesIn('draft-2'), hasLength(1));
    final loaded = (await DraftFiles.load(json))!;
    expect(loaded, hasLength(2));
    expect(File(loaded[0].path!).readAsBytesSync(), [9, 8, 7]);
    final r = loaded[1];
    expect(r.isRemote, isTrue);
    expect(r.remoteAccountId, 'acc1');
    expect(r.remoteEmailId, 'AAMk1');
    expect(r.remoteId, 'att-7');
    expect(r.size, 2048);
  });

  test('без файлов — «[]» и пустая папка убирается; удаление черновика', () async {
    final a = srcFile('a.txt', [1]);
    await DraftFiles.store('draft-3', [DraftFile.local(name: 'a.txt', size: 1, path: a.path)]);
    expect(Directory('${root.path}/draft-3').existsSync(), isTrue);
    final json = await DraftFiles.store('draft-3', const []);
    expect(json, '[]');
    expect(Directory('${root.path}/draft-3').existsSync(), isFalse);
    expect(await DraftFiles.load('[]'), isEmpty);
    // Черновик прежних версий: списка файлов нет.
    expect(await DraftFiles.load(null), isNull);

    await DraftFiles.store('undosend_17', [DraftFile.local(name: 'b.bin', size: 1, bytes: Uint8List(1))]);
    await DraftFiles.remove('undosend_17');
    expect(Directory('${root.path}/undosend_17').existsSync(), isFalse);
  });

  test('пропавший файл пропускается, список сервера не берётся за свой', () async {
    final json = jsonEncode([
      {'id': 'draft:x', 'name': 'x.pdf', 'size': 5, 'draftFile': 'draft-4/x.pdf'},
      {'id': 'AAMkAtt', 'name': 'server.pdf', 'mimeType': 'application/pdf', 'size': 10},
    ]);
    expect(await DraftFiles.load(json), isEmpty);
  });

  test('уборка не трогает живые и свежие папки', () async {
    await DraftFiles.store('draft-live', [DraftFile.local(name: 'a', size: 1, bytes: Uint8List(1))]);
    await DraftFiles.store('draft-fresh-orphan', [DraftFile.local(name: 'b', size: 1, bytes: Uint8List(1))]);
    await DraftFiles.sweep({'draft-live'});
    expect(Directory('${root.path}/draft-live').existsSync(), isTrue);
    // Папка без черновика, но моложе суток (письмо пишется сейчас) — остаётся.
    expect(Directory('${root.path}/draft-fresh-orphan').existsSync(), isTrue);
  });

  test('черновик с одними файлами не пустой', () {
    final d = DraftData(
      id: 'draft-5',
      accountId: 'a',
      savedAt: DateTime(2026, 10, 25),
      files: [DraftFile.local(name: 'a.pdf', size: 1, bytes: Uint8List(1))],
    );
    expect(d.isEmpty, isFalse);
    expect(DraftData(id: 'draft-6', accountId: 'a', savedAt: DateTime(2026)).isEmpty, isTrue);
  });
}

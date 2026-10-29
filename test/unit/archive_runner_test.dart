// Архивация целиком (29.10.2026, замечание владельца: «в архив ничего не
// отправить, структура папок не копируется — получилось только с
// контактами»): письма из базы приложения уходят в архив со структурой папок.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/archive/archive_container.dart';
import 'package:ogneliss/services/archive/archive_db.dart';
import 'package:ogneliss/services/archive/archive_runner.dart';
import 'package:ogneliss/services/archive/archive_vault.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault extends ArchiveVault {
  _Vault(this._fake);
  final ArchiveDb _fake;

  @override
  ArchiveDb? get db => _fake;

  @override
  Future<ArchiveVaultState> build() async => ArchiveVaultState(ArchiveStatus.open,
      header: ArchiveHeader(id: 't', name: '', created: DateTime(2026), app: 'test', keys: const {}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase app;
  late ArchiveDb adb;
  late ProviderContainer c;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      // Копией: удаление с сервера здесь не проверяется.
      'ogna_set_delete': false,
      'ogna_set_app': false,
    });
    final prefs = await SharedPreferences.getInstance();
    app = AppDatabase.forTesting(NativeDatabase.memory());
    adb = ArchiveDb(NativeDatabase.memory());
    await app.into(app.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    Future<void> folder(String id, String name, FolderType t, {String? parent}) =>
        app.into(app.folders).insert(FoldersCompanion.insert(
            id: id, accountId: 'a1', displayName: name, type: Value(t.index), parentId: Value(parent)));
    await folder('INBOX', 'Входящие', FolderType.inbox);
    await folder('INBOX/Work', 'Проекты', FolderType.custom, parent: 'INBOX');
    await folder('Sent', 'Отправленные', FolderType.sent);
    await folder('Trash', 'Удалённые', FolderType.trash);
    await folder('Trash/Old', 'Старое', FolderType.custom, parent: 'Trash');
    await folder('INBOX/Empty', 'Пустая', FolderType.custom, parent: 'INBOX');
    final now = DateTime.now();
    Future<void> mail(String id, String folderId, int daysAgo) => app.into(app.emails).insert(EmailsCompanion.insert(
          id: id,
          accountId: 'a1',
          folderId: folderId,
          fromEmail: 'anna@corp.example',
          toRecipients: '[{"email":"me@corp.example","displayName":"Я"}]',
          subject: 'Письмо $id',
          bodyPlain: Value('Текст письма $id'),
          receivedAt: now.subtract(Duration(days: daysAgo)),
          isRead: const Value(true),
        ));
    await mail('INBOX:1', 'INBOX', 300);
    await mail('INBOX/Work:2', 'INBOX/Work', 250);
    await mail('Sent:3', 'Sent', 400);
    await mail('INBOX:4', 'INBOX', 10); // свежее
    await mail('Trash:5', 'Trash', 300); // корзина не архивируется
    c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(app),
      sharedPrefsProvider.overrideWithValue(prefs),
      archiveVaultProvider.overrideWith(() => _Vault(adb)),
    ]);
    await c.read(archiveVaultProvider.future);
    // Ящики загружаются из базы в фоне.
    await c.read(accountsProvider.notifier).loaded;
  });

  tearDown(() async {
    c.dispose();
    await adb.close();
    await app.close();
  });

  test('письма старше срока — в архив, с папками как в ящике', () async {
    final r = await c.read(archiveRunnerProvider.notifier).run(months: 6);
    expect(r.errorKey, isNull);
    expect(r.mails, 3);
    expect(r.failed, 0);
    final paths = [for (final f in await adb.folders()) f.path];
    // Структура — как в ящике, и пустые папки тоже; корзина — нет.
    expect(paths, containsAll(['Входящие', 'Входящие/Проекты', 'Входящие/Пустая', 'Отправленные']));
    expect(paths.where((p) => p.startsWith('Удалённые')), isEmpty);
    expect((await adb.search('Текст')).length, 3);
  });

  test('папка целиком (1.8.8): с подпапками и всеми письмами, без проверки возраста', () async {
    final account = c.read(accountsProvider).single;
    final r = await c.read(archiveRunnerProvider.notifier).archiveFolder(account, 'INBOX');
    expect(r.errorKey, isNull);
    // Входящие (старое и свежее) и подпапка «Проекты»; «Отправленные» — нет.
    expect(r.mails, 3);
    final paths = [for (final f in await adb.folders()) f.path];
    expect(paths, containsAll(['Входящие', 'Входящие/Проекты', 'Входящие/Пустая']));
    expect(paths, isNot(contains('Отправленные')));
    // Повторно — без дублей.
    await c.read(archiveRunnerProvider.notifier).archiveFolder(account, 'INBOX');
    expect((await adb.search('Текст')).length, 3);
  });

  test('подпапки папки — папка первой, вся глубина', () async {
    final folders = await app.select(app.folders).get();
    expect([for (final f in ArchiveRunner.subtreeOf('INBOX', folders)) f.id],
        ['INBOX', 'INBOX/Work', 'INBOX/Empty']);
    expect([for (final f in ArchiveRunner.subtreeOf('Trash', folders)) f.id], ['Trash', 'Trash/Old']);
    expect(ArchiveRunner.subtreeOf('нет', folders), isEmpty);
  });

  test('письмо с сервера (MIME): тело, адресаты, вложение, картинка в тексте, важность', () async {
    const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    final mime = [
      'From: =?UTF-8?B?${base64.encode(utf8.encode('Анна Смирнова'))}?= <anna@corp.example>',
      'To: Ivan <ivan@corp.example>',
      'Cc: oleg@corp.example',
      'Subject: =?UTF-8?B?${base64.encode(utf8.encode('Смета за 2019 год'))}?=',
      'Date: Tue, 15 Jan 2019 10:30:00 +0300',
      'Message-ID: <old-1@corp.example>',
      'Importance: High',
      'MIME-Version: 1.0',
      'Content-Type: multipart/mixed; boundary="mix"',
      '',
      '--mix',
      'Content-Type: multipart/related; boundary="rel"',
      '',
      '--rel',
      'Content-Type: text/html; charset=utf-8',
      'Content-Transfer-Encoding: base64',
      '',
      base64.encode(utf8.encode('<p>Смета насосной станции</p><img src="cid:logo1">')),
      '--rel',
      'Content-Type: image/png',
      'Content-ID: <logo1>',
      'Content-Transfer-Encoding: base64',
      '',
      png,
      '--rel--',
      '--mix',
      'Content-Type: application/octet-stream; name="smeta.xlsx"',
      'Content-Disposition: attachment; filename="smeta.xlsx"',
      'Content-Transfer-Encoding: base64',
      '',
      base64.encode([1, 2, 3, 4]),
      '--mix--',
      '',
    ].join('\r\n');
    final input = await ArchiveRunner.inputFromMime(Uint8List.fromList(utf8.encode(mime)),
        accountId: 'a1', folderChain: const [(name: 'Входящие', type: 'inbox')], sourceId: 'INBOX:77');
    expect(input.subject, 'Смета за 2019 год');
    expect(input.fromName, 'Анна Смирнова');
    expect(input.fromEmail, 'anna@corp.example');
    expect([for (final a in input.to) a.email], ['ivan@corp.example']);
    expect([for (final a in input.cc) a.email], ['oleg@corp.example']);
    expect(input.messageId, '<old-1@corp.example>');
    expect(input.importance, 2);
    expect(input.date.toUtc(), DateTime.utc(2019, 1, 15, 7, 30));
    expect(input.bodyHtml, contains('cid:logo1'));
    expect(input.searchText, contains('Смета насосной станции'));
    final file = input.attachments.firstWhere((a) => !a.isInline);
    expect(file.name, 'smeta.xlsx');
    expect(file.bytes, [1, 2, 3, 4]);
    final inline = input.attachments.firstWhere((a) => a.isInline);
    expect(inline.contentId, 'logo1');
    expect(inline.mime, 'image/png');

    // В архив и обратно: картинка в тексте находится по cid.
    final id = await adb.addMessage(input);
    final m = await adb.message(id);
    expect(m!.attachments.length, 2);
    expect(m.attachments.where((a) => a.isInline).single.contentId, 'logo1');
  });

  test('дата поиска IMAP', () {
    expect(ImapService.imapSearchDate(DateTime(2026, 4, 9)), '9-Apr-2026');
    expect(ImapService.imapSearchDate(DateTime(2025, 12, 31)), '31-Dec-2025');
  });

  test('EWS: запрос писем до даты — по схеме (Restriction между страницей и сортировкой)', () {
    final xml = EwsXmlBuilder.buildFindItemIdsBefore(folderId: 'inbox', before: DateTime.utc(2025, 4, 29, 6));
    final order = ['IndexedPageItemView', 'Restriction', 'SortOrder', 'ParentFolderIds'].map(xml.indexOf).toList();
    expect(order, everyElement(greaterThan(0)));
    expect([...order]..sort(), order);
    expect(xml, contains('<t:Constant Value="2025-04-29T06:00:00Z"/>'));
    expect(xml, contains('<t:DistinguishedFolderId Id="inbox"/>'));
  });
}

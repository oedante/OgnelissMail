// Черновики на сервере во время правки и с заголовками ответа (2.6.8,
// просьба владельца 22.11.2026 — «и для IMAP, и для Exchange»).
//
// Раньше черновик уходил на сервер только при закрытии окна письма и без
// In-Reply-To/References: на другом устройстве его не было, пока письмо
// пишется, а ответ, отправленный оттуда, начинал новую переписку.
// Проверяется сервис выгрузки: каждая версия заменяет прежнюю серверную
// копию, та же версия второй раз не выгружается, после отправки копии не
// остаются, заголовки — цепочка исходного письма.

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/mail/draft_sync_service.dart';
import 'package:ogneliss/services/mail/email_actions_service.dart';
import 'package:ogneliss/services/mail/ews/ews_xml_builder.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_imap_server.dart';

class _Saved {
  _Saved(this.subject, this.messageId, this.thread);
  final String subject;
  final String messageId;
  final ({String inReplyTo, String references})? thread;
}

class _FakeImap extends ImapService {
  _FakeImap() : super(SecureStorageService());
  final saved = <_Saved>[];
  final deletedByMid = <String>[];
  bool uidPlus = true;
  var _uid = 0;

  @override
  Future<({String path, int? uid})?> saveDraft(
    AccountModel account, {
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    required String messageId,
    ({String inReplyTo, String references})? thread,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
  }) async {
    saved.add(_Saved(subject, messageId, thread));
    return (path: 'Drafts', uid: uidPlus ? ++_uid : null);
  }

  @override
  Future<void> deleteDraftByMessageId(AccountModel account, String messageId) async =>
      deletedByMid.add(messageId);
}

class _FakeActions extends EmailActionsService {
  _FakeActions(super.ref);
  final deleted = <({String id, String folderId, bool hard})>[];

  @override
  Future<void> delete(AccountModel account, String emailId, String folderId, {bool hard = false}) async =>
      deleted.add((id: emailId, folderId: folderId, hard: hard));
}

class _Accounts extends AccountsNotifier {
  _Accounts(AppDatabase db, this.list) : super(db, SecureStorageService());
  final List<AccountModel> list;
  void put() => state = list;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late ProviderContainer c;
  late _FakeImap imap;
  late _FakeActions actions;
  late DraftSyncService sync;

  final acc = AccountModel(
    id: 'a1',
    type: AccountType.imap,
    email: 'me@example.com',
    displayName: 'Me',
    username: 'me@example.com',
    imapServer: '127.0.0.1',
    createdAt: DateTime(2026),
  );

  Future<void> draft(String body, {String? parentId = 'r|a1|INBOX:7', String? files}) =>
      db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
            id: 'draft-1',
            accountId: 'a1',
            folderId: 'drafts',
            fromEmail: '',
            toRecipients: jsonEncode([
              {'email': 'anna@example.com', 'name': 'Anna'},
            ]),
            subject: 'Re: План',
            bodyPlain: Value(body),
            parentId: Value(parentId),
            attachmentsJson: Value(files),
            receivedAt: DateTime.now(),
            isDraft: const Value(true),
          ));

  Future<bool> localExists() async => (await db.getEmailById('draft-1', accountId: 'a1')) != null;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 0, email: 'me@example.com', displayName: 'Me', username: 'me', createdAt: DateTime(2026)));
    // Исходное письмо ответа: его Message-ID и цепочка.
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'INBOX:7',
          accountId: 'a1',
          folderId: 'INBOX',
          fromEmail: 'anna@example.com',
          toRecipients: '[]',
          subject: 'План',
          internetMessageId: const Value('<parent@example.com>'),
          referencesStr: const Value('<root@example.com>'),
          receivedAt: DateTime(2026, 11, 22, 9),
        ));
    imap = _FakeImap();
    late _Accounts accounts;
    c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      imapServiceProvider.overrideWithValue(imap),
      emailActionsProvider.overrideWith((ref) => actions = _FakeActions(ref)),
      accountsProvider.overrideWith((ref) => accounts = _Accounts(db, [acc])),
    ]);
    c.read(accountsProvider);
    await accounts.loaded;
    accounts.put();
    c.read(emailActionsProvider);
    sync = c.read(draftSyncServiceProvider);
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('во время правки: версия на сервере, локальная остаётся; та же — второй раз не выгружается', () async {
    await draft('<p>Начало</p>');
    expect(await sync.uploadWhileEditing('draft-1', 'a1'), isNull, reason: 'заменять пока нечего');
    expect(imap.saved, hasLength(1));
    expect(await localExists(), isTrue, reason: 'правка идёт');

    // Заголовки ответа — цепочка исходного письма.
    final t = imap.saved.single.thread!;
    expect(t.inReplyTo, '<parent@example.com>');
    expect(t.references, '<root@example.com> <parent@example.com>');

    expect(await sync.uploadWhileEditing('draft-1', 'a1'), isNull);
    expect(imap.saved, hasLength(1), reason: 'та же версия уже на сервере');
  });

  test('новая версия заменяет прежнюю копию; итоговая при закрытии — без повторной выгрузки', () async {
    await draft('<p>Начало</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    await draft('<p>Начало и продолжение</p>');
    expect(await sync.uploadWhileEditing('draft-1', 'a1'), 'Drafts:1');
    expect(imap.saved, hasLength(2));
    expect(actions.deleted.single, (id: 'Drafts:1', folderId: 'Drafts', hard: true));

    // Окно закрыли, ничего больше не меняя: на сервере уже эта версия.
    expect(await sync.upload('draft-1', 'a1'), isTrue);
    expect(imap.saved, hasLength(2), reason: 'второй раз не выгружается');
    expect(await localExists(), isFalse, reason: 'черновик живёт в серверной папке');
    expect(actions.deleted, hasLength(1), reason: 'выгруженная копия и есть черновик');
  });

  test('правка после выгрузки — итоговая версия заменяет выгруженную', () async {
    await draft('<p>Начало</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    await draft('<p>Итог</p>');
    expect(await sync.upload('draft-1', 'a1'), isTrue);
    expect(imap.saved, hasLength(2));
    expect(actions.deleted.single.id, 'Drafts:1');
    expect(await localExists(), isFalse);
  });

  test('выгрузка во время правки и при закрытии идут по одной — копий не две', () async {
    await draft('<p>Начало</p>');
    final a = sync.uploadWhileEditing('draft-1', 'a1');
    final b = sync.upload('draft-1', 'a1');
    await Future.wait([a, b]);
    expect(imap.saved, hasLength(1), reason: 'итоговая увидела выгруженную копию');
    expect(actions.deleted, isEmpty);
  });

  test('отправили: выгруженная во время правки копия удаляется безвозвратно', () async {
    await draft('<p>Начало</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    await sync.dropServerCopy(acc, 'draft-1');
    expect(actions.deleted.single, (id: 'Drafts:1', folderId: 'Drafts', hard: true));
    // Связь забыта: итоговой выгрузке заменять нечего.
    await draft('<p>Снова</p>');
    await sync.upload('draft-1', 'a1');
    expect(actions.deleted, hasLength(1));
  });

  test('«Удалить» открытый из папки черновик: он — в корзину, выгруженная версия — безвозвратно', () async {
    await sync.rememberReplace('draft-1', (id: 'Drafts:40', folderId: 'Drafts'));
    await draft('<p>Правка</p>');
    // Выгрузка заменила открытую из папки копию — окно узнаёт об этом.
    expect(await sync.uploadWhileEditing('draft-1', 'a1'), 'Drafts:40');
    await sync.dropServerCopy(acc, 'draft-1', original: (id: 'Drafts:40', folderId: 'Drafts'), hard: false);
    expect(actions.deleted, [
      (id: 'Drafts:40', folderId: 'Drafts', hard: true),
      (id: 'Drafts:1', folderId: 'Drafts', hard: true),
    ], reason: 'открытую копию уже заменили — второй раз её не трогаем');
  });

  test('файлы, которые отправка берёт с сервера, — письмо с ними не удаляется', () async {
    await sync.rememberReplace('draft-1', (id: 'Drafts:40', folderId: 'Drafts'));
    await sync.dropServerCopy(acc, 'draft-1',
        original: (id: 'Drafts:40', folderId: 'Drafts'), keep: {'Drafts:40'});
    expect(actions.deleted, isEmpty);
  });

  test('сервер без UIDPLUS: прежняя копия удаляется по Message-ID', () async {
    imap.uidPlus = false;
    await draft('<p>Начало</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    await draft('<p>Продолжение</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    expect(imap.deletedByMid, [imap.saved.first.messageId]);
    expect(actions.deleted, isEmpty);
  });

  test('пересылка и новое письмо — без заголовков ответа', () async {
    await draft('<p>Пересылаю</p>', parentId: 'f|a1|INBOX:7');
    await sync.uploadWhileEditing('draft-1', 'a1');
    expect(imap.saved.single.thread, isNull);
  });

  test('файлы не скачаны (пересылка) — во время правки не выгружается (только при закрытии окна)', () async {
    await draft('<p>Пересылаю</p>',
        parentId: 'f|a1|INBOX:7',
        files: jsonEncode([
          {'id': '2', 'name': 'отчёт.pdf', 'mimeType': 'application/pdf', 'size': 100, 'remoteAccount': 'a1', 'remoteEmail': 'INBOX:7'},
        ]));
    await sync.uploadWhileEditing('draft-1', 'a1', force: true);
    expect(imap.saved, isEmpty, reason: 'файл пришлось бы качать на каждую выгрузку');
  });

  test('отпечаток: меняется от текста, адресатов, файлов; не от времени сохранения', () async {
    await draft('<p>A</p>');
    final r1 = (await db.getEmailById('draft-1', accountId: 'a1'))!;
    final again = r1.copyWith(receivedAt: DateTime(2030));
    expect(DraftSyncService.contentSig(again), DraftSyncService.contentSig(r1));
    expect(DraftSyncService.contentSig(r1.copyWith(bodyPlain: const Value('<p>B</p>'))),
        isNot(DraftSyncService.contentSig(r1)));
    expect(DraftSyncService.contentSig(r1.copyWith(toRecipients: '[]')), isNot(DraftSyncService.contentSig(r1)));
    expect(
        DraftSyncService.contentSig(r1.copyWith(
            attachmentsJson: Value(jsonEncode([
          {'id': 'draft:x1', 'name': 'a.pdf', 'size': 5, 'draftFile': 'd/x1'},
        ])))),
        DraftSyncService.contentSig(r1.copyWith(
            attachmentsJson: Value(jsonEncode([
          {'id': 'draft:x2', 'name': 'a.pdf', 'size': 5, 'draftFile': 'd/x2'},
        ])))),
        reason: 'тот же файл под другим именем в папке черновика');
  });

  test('пока свой черновик на устройстве — его серверная копия в списке не повторяется', () async {
    await draft('<p>Начало</p>');
    await sync.uploadWhileEditing('draft-1', 'a1');
    final prefs = c.read(sharedPrefsProvider);
    final local = (await db.getEmailById('draft-1', accountId: 'a1'))!;
    final copy = local.copyWith(id: 'Drafts:1', folderId: 'Drafts');
    expect(DraftSyncService.shadowed(prefs, [local, copy]), {'a1|Drafts:1'});
    expect(DraftSyncService.shadowed(prefs, [copy]), isEmpty, reason: 'своего черновика нет — копия видна');

    await sync.upload('draft-1', 'a1');
    expect(DraftSyncService.shadowed(prefs, [local, copy]), isEmpty, reason: 'выгружен — связь забыта');
  });

  test('Exchange: InReplyTo до получателей, References после From — порядок схемы', () {
    final xml = EwsXmlBuilder.buildCreateDraft(
      to: const [EmailAddress(email: 'anna@example.com')],
      subject: 'Re: План',
      bodyContent: '<p>x</p>',
      inReplyTo: '<parent@example.com>',
      references: '<root@example.com> <parent@example.com>',
      sharedMailbox: 'team@example.com',
    );
    final inReply = xml.indexOf('<t:InReplyTo>&lt;parent@example.com&gt;</t:InReplyTo>');
    final to = xml.indexOf('<t:ToRecipients>');
    final from = xml.indexOf('<t:From>');
    final refs = xml.indexOf('<t:References>&lt;root@example.com&gt; &lt;parent@example.com&gt;</t:References>');
    expect(inReply, greaterThan(0));
    expect(inReply, lessThan(to));
    expect(from, greaterThan(to));
    expect(refs, greaterThan(from));
    expect(EwsXmlBuilder.buildCreateDraft(to: const [], subject: 's', bodyContent: 'b'), isNot(contains('References')));
  });

  group('IMAP на поддельном сервере', () {
    late FakeImapServer srv;
    late ImapService real;
    late FakeMailbox drafts;

    AccountModel account() => AccountModel(
          id: 'a9',
          type: AccountType.imap,
          email: 'me@example.com',
          displayName: 'Me',
          username: 'me@example.com',
          imapServer: '127.0.0.1',
          imapPort: srv.port,
          imapEncryption: EncryptionType.none,
          createdAt: DateTime(2026),
        );

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({'pwd_a9': 'secret'});
      real = ImapService(SecureStorageService());
      srv = FakeImapServer(caps: 'IMAP4rev1 UIDPLUS', capsAtLogin: true);
      srv.box('INBOX');
      drafts = srv.box('Drafts', listFlags: r'\Drafts');
      await srv.start();
    });

    tearDown(() async {
      real.dispose();
      await srv.close();
    });

    test('черновик ответа: In-Reply-To и References в письме, UID — из APPENDUID', () async {
      final r = await real.saveDraft(account(),
          to: const [EmailAddress(email: 'anna@example.com')],
          subject: 'Re: План',
          bodyHtml: '<p>Черновик</p>',
          messageId: '<draft.1@example.com>',
          thread: replyThreadHeaders('<root@example.com> <parent@example.com>'));
      expect(r, (path: 'Drafts', uid: 1));
      final text = drafts.messages.single.appended!;
      expect(text, contains('In-Reply-To: <parent@example.com>'));
      expect(text, contains('References: <root@example.com> <parent@example.com>'));
      expect(drafts.messages.single.messageId, '<draft.1@example.com>');
      expect(drafts.messages.single.flags, containsAll([r'\Draft', r'\Seen']));
    });
  });
}

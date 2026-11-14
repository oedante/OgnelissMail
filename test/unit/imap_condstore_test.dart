// test/unit/imap_condstore_test.dart
// Быстрая синхронизация IMAP по CONDSTORE/QRESYNC (RFC 7162; 1.9.x, просьба
// владельца 31.10.2026). Сервер — поддельный, по локальному сокету
// (fake_imap_server.dart): возможности задаются строкой CAPABILITY.
// Проверяется: флаги — только изменённые (CHANGEDSINCE), удалённые — по
// VANISHED, HIGHESTMODSEQ сохраняется, смена UIDVALIDITY и любой сбой —
// прежний полный способ, сервер без расширений — команды как раньше.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_imap_server.dart';

const _gmailLike = 'IMAP4rev1 IDLE CONDSTORE ESEARCH';
const _dovecotLike = 'IMAP4rev1 IDLE ENABLE CONDSTORE QRESYNC';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeImapServer srv;
  late ImapService imap;

  AccountModel account() => AccountModel(
        id: 'a1',
        type: AccountType.imap,
        email: 'me@example.com',
        displayName: 'Me',
        username: 'me@example.com',
        imapServer: '127.0.0.1',
        imapPort: srv.port,
        imapEncryption: EncryptionType.none,
        createdAt: DateTime(2026),
      );

  /// Состояние — через JSON, как между синхронизациями.
  ImapFolderState? stored(ImapFolderDelta d) => ImapFolderState.fromJson(jsonEncode(d.state.toJson()));

  Future<FakeMailbox> serve(String caps, {int count = 5, bool capsAtLogin = false}) async {
    srv = FakeImapServer(caps: caps, capsAtLogin: capsAtLogin);
    final box = srv.box('Archive');
    for (var i = 1; i <= count; i++) {
      box.add('Письмо $i');
    }
    await srv.start();
    return box;
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'pwd_a1': 'secret'});
    imap = ImapService(SecureStorageService());
  });

  tearDown(() async {
    imap.dispose();
    await srv.close();
  });

  Iterable<String> cmds(String prefix) => srv.commands.where((c) => c.startsWith(prefix));

  test('CONDSTORE (как Gmail): флаги — только изменённые, MODSEQ сохраняется', () async {
    final box = await serve(_gmailLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    expect(first.reset, isTrue);
    expect(first.added, hasLength(5));
    // До входа сервер назвал не всё — список возможностей запрошен после входа.
    expect(srv.commands, contains('CAPABILITY'));
    expect(srv.commands, contains('SELECT "Archive" (CONDSTORE)'));
    final s1 = stored(first)!;
    expect(s1.highestModSeq, box.highestModSeq);
    expect(s1.exists, 5);
    expect(s1.uidNext, 6);

    box.setFlags(2, {r'\Seen'});
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: s1, backfill: 0);
    expect(second.fast, isTrue);
    expect(second.flags.keys, [2]);
    expect(second.flags[2]!.read, isTrue);
    expect(srv.commands, contains('UID FETCH 1:5 (UID FLAGS) (CHANGEDSINCE ${s1.highestModSeq})'));
    expect(srv.commands, isNot(contains('UID FETCH 1:* (UID FLAGS)')), reason: 'флаги всего окна не нужны');
    expect(cmds('UID SEARCH'), isEmpty, reason: 'число писем и UIDNEXT прежние — удалений нет');
    expect(second.checkedFrom, isNull);
    final s2 = stored(second)!;
    expect(s2.highestModSeq, box.highestModSeq);

    // Ничего не менялось — один SELECT.
    srv.commands.clear();
    final third = await imap.syncFolderDelta(a, folderId: 'Archive', known: s2, backfill: 0);
    expect(third.flags, isEmpty);
    expect(third.added, isEmpty);
    expect(cmds('UID '), isEmpty);

    // Письмо удалено на другом устройстве — номера окна (ESEARCH), без флагов.
    box.expunge(4);
    srv.commands.clear();
    final fourth = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(third), backfill: 0);
    expect(srv.commands, contains('UID SEARCH RETURN (ALL) UID 1:5'));
    expect(fourth.present, {1, 2, 3, 5});
    expect(fourth.checkedFrom, 1);
    expect(fourth.checkedTo, 5);
    expect(stored(fourth)!.exists, 4);

    // Новое письмо: загружается, окно растёт.
    box.add('Новое');
    srv.commands.clear();
    final fifth = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(fourth), backfill: 0);
    expect(fifth.added.map((e) => e.id), ['Archive:6']);
    expect(fifth.state.maxUid, 6);
    expect(fifth.present, containsAll([1, 2, 3, 5, 6]));
  });

  test('QRESYNC (как Dovecot): изменения и удалённые — в ответе на SELECT', () async {
    final box = await serve(_dovecotLike, capsAtLogin: true);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    expect(srv.commands, contains('ENABLE QRESYNC'));
    expect(srv.commands, isNot(contains('CAPABILITY')), reason: 'возможности пришли в ответе на вход');
    final s1 = stored(first)!;

    box.setFlags(1, {r'\Flagged'});
    box.expunge(3);
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: s1, backfill: 0);
    expect(srv.commands, contains('SELECT "Archive" (QRESYNC (1000 ${s1.highestModSeq} 1:5))'));
    expect(second.fast, isTrue);
    expect(second.vanished, {3});
    expect(second.flags.keys, [1]);
    expect(second.flags[1]!.flagged, isTrue);
    expect(cmds('UID FETCH'), isEmpty);
    expect(cmds('UID SEARCH'), isEmpty);
    expect(stored(second)!.highestModSeq, box.highestModSeq);
  });

  test('смена UIDVALIDITY — папка загружается заново (полный способ)', () async {
    final box = await serve(_dovecotLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    box.uidValidity = 2000;
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(first), backfill: 0);
    expect(second.reset, isTrue);
    expect(second.fast, isFalse);
    expect(second.added, hasLength(5));
    expect(second.state.uidValidity, 2000);
    expect(cmds('SELECT'), hasLength(2));
  });

  test('сбой быстрого способа — полный способ для этой папки, без потери писем', () async {
    final box = await serve(_gmailLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    box.setFlags(5, {r'\Seen'});
    srv.failOn.add('CHANGEDSINCE');
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(first), backfill: 0);
    expect(second.fast, isFalse);
    expect(second.flags.keys, containsAll([1, 2, 3, 4, 5]));
    expect(second.flags[5]!.read, isTrue);
    expect(srv.commands, contains('UID FETCH 1:* (UID FLAGS)'));
    // До перезапуска — полным способом, без новых попыток.
    srv.commands.clear();
    await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(second), backfill: 0);
    expect(srv.commands.where((c) => c.contains('CHANGEDSINCE') || c.contains('CONDSTORE')), isEmpty);
    expect(srv.commands, contains('UID FETCH 1:* (UID FLAGS)'));
  });

  test('сбой SELECT с QRESYNC — полный способ', () async {
    final box = await serve(_dovecotLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    box.expunge(2);
    srv.failOn.add('(QRESYNC');
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(first), backfill: 0);
    expect(second.fast, isFalse);
    expect(second.present, {1, 3, 4, 5});
    expect(second.checkedFrom, 1);
  });

  test('история догружается или сверке больше суток — полный способ', () async {
    final box = await serve(_gmailLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    box.setFlags(1, {r'\Seen'});
    srv.commands.clear();
    final withBackfill = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(first), backfill: 100);
    expect(withBackfill.fast, isFalse);
    final s = stored(withBackfill)!;
    final old = ImapFolderState.fromJson(jsonEncode({
      ...s.toJson(),
      'f': DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch ~/ 1000,
    }));
    final daily = await imap.syncFolderDelta(a, folderId: 'Archive', known: old, backfill: 0);
    expect(daily.fast, isFalse);
    expect(daily.flags, hasLength(5));
    // После полной сверки — снова быстрым способом.
    final next = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(daily), backfill: 0);
    expect(next.fast, isTrue);
  });

  test('сервер без CONDSTORE — полный способ: SELECT и один запрос флагов (min:*)', () async {
    final box = await serve('IMAP4rev1 IDLE', capsAtLogin: true);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'Archive', backfill: 0);
    expect(srv.commands, [
      'LOGIN "me@example.com" "secret"',
      'LIST "" "%"',
      'SELECT "Archive"',
      'FETCH 1:5 (UID FLAGS INTERNALDATE ENVELOPE BODYSTRUCTURE RFC822.SIZE BODY.PEEK[HEADER.FIELDS (REFERENCES IN-REPLY-TO '
          'AUTHENTICATION-RESULTS LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST LIST-ID SENSITIVITY '
          'X-OGNELISS-CLASSIFICATION X-OGNELISS-HANDLING)])',
    ]);
    expect(first.state.toJson(), {'v': 1000, 'min': 1, 'max': 5});
    box.setFlags(2, {r'\Seen'});
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'Archive', known: stored(first), backfill: 0);
    expect(srv.commands, ['SELECT "Archive"', 'UID FETCH 1:* (UID FLAGS)']);
    expect(second.fast, isFalse);
    expect(second.flags, hasLength(5));
  });

  group('синхронизация папки целиком (SyncService)', () {
    late AppDatabase db;
    late ProviderContainer c;
    late SharedPreferences prefs;

    Future<void> init() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
          username: 'me@example.com', createdAt: DateTime(2026)));
      await db.into(db.folders).insert(FoldersCompanion.insert(
          id: 'Archive', accountId: 'a1', displayName: 'Archive', type: Value(FolderType.custom.index)));
      c = ProviderContainer(overrides: [
        imapServiceProvider.overrideWithValue(imap),
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
      ]);
    }

    tearDown(() async {
      c.dispose();
      await db.close();
    });

    Future<List<Email>> rows() =>
        (db.select(db.emails)..orderBy([(e) => OrderingTerm(expression: e.id)])).get();

    const folder = FolderModel(
        id: 'Archive', accountId: 'a1', displayName: 'Archive', type: FolderType.custom, serverPath: 'Archive');

    test('QRESYNC: удалённые на сервере убираются, флаги и MODSEQ сохраняются', () async {
      final box = await serve(_dovecotLike);
      await init();
      final sync = c.read(syncServiceProvider);
      final a = account();
      await sync.syncSingleFolder(a, folder);
      expect(await rows(), hasLength(5));

      box.setFlags(2, {r'\Seen', r'\Flagged'});
      box.expunge(4);
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      final r = await rows();
      expect(r.map((e) => e.id), ['Archive:1', 'Archive:2', 'Archive:3', 'Archive:5']);
      final two = r.firstWhere((e) => e.id == 'Archive:2');
      expect(two.isRead, isTrue);
      expect(two.isFlagged, isTrue);
      expect(srv.commands.where((c) => c.contains('QRESYNC (')), hasLength(1));
      expect(srv.commands, isNot(contains('UID FETCH 1:* (UID FLAGS)')));
      final st = ImapFolderState.fromJson(prefs.getString('imap_state:a1:Archive'))!;
      expect(st.highestModSeq, box.highestModSeq);
      expect(st.historyDone, isTrue);
    });

    test('локальная правка не отправлена — прежний MODSEQ, изменение не теряется', () async {
      final box = await serve(_gmailLike);
      await init();
      final sync = c.read(syncServiceProvider);
      final a = account();
      await sync.syncSingleFolder(a, folder);
      final s1 = ImapFolderState.fromJson(prefs.getString('imap_state:a1:Archive'))!;
      // Письмо 3 изменено в приложении (правка ещё не ушла), а на сервере
      // его отметили прочитанным с другого устройства.
      await (db.update(db.emails)..where((e) => e.id.equals('Archive:3')))
          .write(const EmailsCompanion(isLocallyModified: Value(true), isFlagged: Value(true)));
      box.setFlags(3, {r'\Seen'});
      await sync.syncSingleFolder(a, folder);
      final s2 = ImapFolderState.fromJson(prefs.getString('imap_state:a1:Archive'))!;
      expect(s2.highestModSeq, s1.highestModSeq, reason: 'изменение по письму 3 пока не применено');
      expect(s2.exists, isNull, reason: 'удаления проверятся заново');
      // Правка отправлена (или отменена) — изменение сервера доходит.
      await (db.update(db.emails)..where((e) => e.id.equals('Archive:3')))
          .write(const EmailsCompanion(isLocallyModified: Value(false)));
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      expect(srv.commands, contains('UID FETCH 1:5 (UID FLAGS) (CHANGEDSINCE ${s1.highestModSeq})'));
      final three = (await rows()).firstWhere((e) => e.id == 'Archive:3');
      expect(three.isRead, isTrue);
      expect(ImapFolderState.fromJson(prefs.getString('imap_state:a1:Archive'))!.highestModSeq, box.highestModSeq);
    });
  });
}

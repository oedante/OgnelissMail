// test/unit/imap_missing_mail_test.dart
// Письмо есть на сервере, а на устройстве его нет (2.3.2; журналы Яндекса
// 10–11.11.2026: письмо лежало во «Входящих», приложение показало его
// только после поиска; копии отправленных не появлялись в «Отправленных»).
//
// Сервер — поддельный (fake_imap_server.dart). Проверяется:
//  · UIDNEXT сервера отстал — новые письма загружаются (их называет сам
//    сервер в ответе на запрос флагов «min:*»);
//  · сервер пропустил письмо в общем ответе с новыми письмами — оно
//    догружается отдельным запросом, известный UID его «не перешагивает»;
//  · письмо стало видно позже с UID меньше уже известного — сверка папки
//    догружает его в следующем проходе;
//  · письмо, удалённое здесь (действие ждёт отправки), сверка не возвращает
//    (ImapReconcile.missing).

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
import 'package:ogneliss/services/mail/imap/imap_reconcile.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_imap_server.dart';

/// Как Яндекс: без CONDSTORE — каждый проход полным способом.
const _plain = 'IMAP4rev1 IDLE';
const _gmailLike = 'IMAP4rev1 IDLE CONDSTORE ESEARCH';

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

  ImapFolderState? stored(ImapFolderDelta d) => ImapFolderState.fromJson(jsonEncode(d.state.toJson()));

  Future<FakeMailbox> serve(String caps, {int count = 5}) async {
    srv = FakeImapServer(caps: caps, capsAtLogin: true);
    final box = srv.box('INBOX');
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

  List<int> uids(ImapFolderDelta d) =>
      [for (final e in d.added) int.parse(e.id.substring(e.id.lastIndexOf(':') + 1))]..sort();

  test('UIDNEXT сервера отстал — новое письмо всё равно загружается', () async {
    final box = await serve(_plain);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'INBOX', backfill: 0);
    expect(first.added, hasLength(5));
    // Письмо пришло, а UIDNEXT в ответе на SELECT прежний.
    box.reportedUidNext = box.uidNext;
    box.add('Новое');
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'INBOX', known: stored(first), backfill: 0);
    expect(uids(second), [6]);
    expect(second.state.maxUid, 6);
    expect(srv.commands.first, 'SELECT "INBOX"');
    expect(srv.commands[1], 'UID FETCH 1:* (UID FLAGS)', reason: 'новые UID называет сервер, а не UIDNEXT');
    // Ничего нового — один лёгкий запрос после SELECT, как и раньше.
    srv.commands.clear();
    final third = await imap.syncFolderDelta(a, folderId: 'INBOX', known: stored(second), backfill: 0);
    expect(third.added, isEmpty);
    expect(srv.commands, ['SELECT "INBOX"', 'UID FETCH 1:* (UID FLAGS)']);
  });

  test('сервер пропустил письмо в общем ответе — оно догружается отдельно', () async {
    final box = await serve(_plain);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'INBOX', backfill: 0);
    box
      ..add('Первое новое')
      ..add('Второе новое');
    box.skipInRange.add(6);
    final second = await imap.syncFolderDelta(a, folderId: 'INBOX', known: stored(first), backfill: 0);
    expect(uids(second), [6, 7], reason: 'письмо 6 не потерялось за письмом 7');
    expect(second.state.maxUid, 7);
  });

  test('то же при быстрой синхронизации (CONDSTORE): список новых — UID SEARCH', () async {
    final box = await serve(_gmailLike);
    final a = account();
    final first = await imap.syncFolderDelta(a, folderId: 'INBOX', backfill: 0);
    final s1 = stored(first)!;
    box
      ..add('Первое новое')
      ..add('Второе новое');
    box.skipInRange.add(6);
    srv.commands.clear();
    final second = await imap.syncFolderDelta(a, folderId: 'INBOX', known: s1, backfill: 0);
    expect(second.fast, isTrue);
    expect(uids(second), [6, 7]);
    expect(srv.commands.where((c) => c.startsWith('UID SEARCH RETURN (ALL) UID 6:*')), hasLength(1));
  });

  group('сверка папки (SyncService)', () {
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
          id: 'INBOX', accountId: 'a1', displayName: 'INBOX', type: Value(FolderType.custom.index)));
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

    Future<List<String>> ids() async =>
        [for (final e in await (db.select(db.emails)..orderBy([(e) => OrderingTerm(expression: e.id)])).get()) e.id];

    const folder =
        FolderModel(id: 'INBOX', accountId: 'a1', displayName: 'INBOX', type: FolderType.custom, serverPath: 'INBOX');

    test('письмо стало видно позже, с UID меньше известного, — догружается', () async {
      final box = await serve(_plain);
      await init();
      final sync = c.read(syncServiceProvider);
      final a = account();
      await sync.syncSingleFolder(a, folder);
      expect(await ids(), hasLength(5));

      // Письмо 6 получило UID, но серверу пока «не видно»; письмо 7 пришло
      // следом и загрузилось — известный UID ушёл за письмо 6.
      final late = box.add('Позднее')..hidden = true;
      box.add('Следующее');
      await sync.syncSingleFolder(a, folder);
      expect(await ids(), isNot(contains('INBOX:6')));
      expect(await ids(), contains('INBOX:7'));
      expect(ImapFolderState.fromJson(prefs.getString('imap_state:a1:INBOX'))!.maxUid, 7);

      // Сервер показал письмо 6 — сверка его догружает.
      late.hidden = false;
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      expect(await ids(), contains('INBOX:6'));
      expect(srv.commands.where((c) => c.startsWith('UID FETCH 6 (UID FLAGS INTERNALDATE ENVELOPE')), hasLength(1));

      // Всё на месте — лишних запросов нет.
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      expect(srv.commands, ['SELECT "INBOX"', 'UID FETCH 1:* (UID FLAGS)']);
    });

    test('даты загруженных раньше писем — один раз по времени прихода (14.11.2026)', () async {
      final box = await serve(_plain);
      await init();
      final sync = c.read(syncServiceProvider);
      final a = account();
      await sync.syncSingleFolder(a, folder);
      Future<DateTime> at(String id) async => (await db.getEmailById(id, accountId: 'a1'))!.receivedAt.toUtc();
      // Загружены по заголовку Date (26.10.2026 10:00 UTC) — как до исправления.
      expect(await at('INBOX:2'), DateTime.utc(2026, 10, 26, 10));
      // Сервер сообщает время прихода: письмо 2 пришло через 5 минут,
      // письмо 3 перенесено месяц спустя (остаётся дата письма).
      box.messages[1].internalDate = '26-Oct-2026 13:05:00 +0300';
      box.messages[2].internalDate = '26-Nov-2026 09:00:00 +0000';
      // Следующий проход исправляет даты; повторно время прихода не
      // запрашивается.
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      expect(await at('INBOX:2'), DateTime.utc(2026, 10, 26, 10, 5));
      expect(await at('INBOX:3'), DateTime.utc(2026, 10, 26, 10));
      expect(srv.commands.where((c) => c.contains('(UID INTERNALDATE)')), hasLength(1));
      srv.commands.clear();
      await sync.syncSingleFolder(a, folder);
      expect(srv.commands.where((c) => c.contains('(UID INTERNALDATE)')), isEmpty, reason: 'один раз на папку');
    });
  });

  group('ImapReconcile', () {
    test('только письма выше нижней границы, которых нет на устройстве', () {
      expect(
        ImapReconcile.missing(server: [1, 2, 3, 4, 5, 6, 7], local: {3, 4, 6, 7}, floor: 3),
        [5],
        reason: '1 и 2 — ниже первого письма на устройстве (история за срезом)',
      );
      expect(ImapReconcile.missing(server: [5, 6], local: const {}, floor: null), isEmpty,
          reason: 'на устройстве писем папки нет — сверять не с чем');
      expect(ImapReconcile.missing(server: [5, 6, 7, 8], local: {5}, floor: 5, pending: {6}, skipped: {7}), [8]);
      expect(ImapReconcile.missing(server: [for (var i = 1; i <= 200; i++) i], local: {1}, floor: 1, limit: 50),
          [for (var i = 200; i > 150; i--) i], reason: 'не больше 50 за проход, новые первыми');
    });

    test('пропуски: через неделю спрашиваем снова', () {
      final now = DateTime(2026, 11, 11, 12);
      final saved = ImapReconcile.writeSkipped(null, [7, 9], now);
      expect(ImapReconcile.readSkipped(saved, now), {7, 9});
      expect(ImapReconcile.readSkipped(saved, now.add(const Duration(days: 8))), isEmpty);
      final more = ImapReconcile.writeSkipped(saved, [11], now.add(const Duration(days: 8)));
      expect(more, hasLength(1), reason: 'устаревшие пропуски не хранятся');
    });
  });
}

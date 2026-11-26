// Отправка через «Исходящие» и плохая мобильная связь (2.7.4, 25.11.2026):
// окно письма закрывается сразу, письмо уходит из «Исходящих» в фоне;
// при временных сбоях — повторы сутки с растущей паузой; картинки цитаты,
// которых не было на телефоне, докачиваются перед отправкой; обрыв
// TLS-рукопожатия — не «ошибка сертификата», и папки дальше не перебираются.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/mail/offline_send_service.dart';
import 'package:ogneliss/services/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('пауза между попытками: 30 с, 1, 2, 4, 8 мин, дальше 10 мин', () {
    expect(OfflineSendService.retryDelay(0), Duration.zero);
    expect(OfflineSendService.retryDelay(1), const Duration(seconds: 30));
    expect(OfflineSendService.retryDelay(2), const Duration(minutes: 1));
    expect(OfflineSendService.retryDelay(3), const Duration(minutes: 2));
    expect(OfflineSendService.retryDelay(5), const Duration(minutes: 8));
    expect(OfflineSendService.retryDelay(6), const Duration(minutes: 10));
    expect(OfflineSendService.retryDelay(40), const Duration(minutes: 10));
    expect(OfflineSendService.transientRetryWindow, const Duration(hours: 24));
  });

  test('обрыв рукопожатия — нет подключения; ошибка в папке — нет', () {
    expect(SyncService.isConnectFailure(const HandshakeException('Connection terminated during handshake')), isTrue);
    expect(SyncService.isConnectFailure(const SocketException('Connection refused')), isTrue);
    expect(SyncService.isConnectFailure(Exception('SocketException: Failed host lookup: mail.example.test')), isTrue);
    expect(SyncService.isConnectFailure(Exception('NO [NONEXISTENT] Unknown mailbox')), isFalse);
    expect(SyncService.isConnectFailure(Exception('TimeoutException after 0:03:00')), isFalse);
  });

  test('IMAP: повтор подключения — только при обрыве рукопожатия, не при сертификате', () {
    expect(ImapService.isDroppedHandshake(const HandshakeException('Connection terminated during handshake')), isTrue);
    expect(
        ImapService.isDroppedHandshake(
            const HandshakeException('Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate)')),
        isFalse);
    expect(ImapService.isDroppedHandshake(const SocketException('Connection refused')), isFalse);
  });

  group('«Исходящие»', () {
    late AppDatabase db;
    late ProviderContainer container;

    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
      ]);
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
          username: 'me', createdAt: DateTime(2026)));
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('ответ без отсчёта — в очереди сразу, со ссылкой на картинки исходного письма', () async {
      final service = container.read(offlineSendProvider);
      await service.scheduleUndoSend(
        accountId: 'a1',
        fromEmail: 'me@example.com',
        to: const [EmailAddress(email: 'boss@example.com')],
        subject: 'RE: Отчёт',
        bodyHtml: '<p>Ок</p><blockquote><img src="cid:image001.png@01DB"></blockquote>',
        window: Duration.zero,
        quoteImages: (accountId: 'a1', emailId: 'orig1'),
      );
      final rows = await db.select(db.syncQueue).get();
      expect(rows, hasLength(1));
      final payload = jsonDecode(rows.single.payloadJson) as Map<String, dynamic>;
      expect(payload['quoteImages'], {'accountId': 'a1', 'emailId': 'orig1'});
      expect(payload['bodyHtml'], contains('cid:image001.png@01DB'));
    });

    // «Не забыть про „Черновики“» (владелец 25.11.2026): черновик с сервера,
    // чьи файлы ещё не скачаны, удаляется на сервере после отправки, а
    // вернувшееся из «Исходящих» письмо заменяет его при выгрузке.
    test('черновик с сервера: удалить после отправки; «Отменить» — заменит его при выгрузке', () async {
      final service = container.read(offlineSendProvider);
      final outboxId = await service.scheduleUndoSend(
        accountId: 'a1',
        fromEmail: 'me@example.com',
        to: const [EmailAddress(email: 'boss@example.com')],
        subject: 'Смета',
        bodyHtml: '<p>Смета во вложении</p>',
        window: const Duration(hours: 1),
        dropDraft: (accountId: 'a1', id: 'INBOX.Drafts:42', folderId: 'INBOX.Drafts'),
      );
      final row = (await db.select(db.syncQueue).get()).single;
      expect((jsonDecode(row.payloadJson) as Map)['dropDraft'],
          {'accountId': 'a1', 'id': 'INBOX.Drafts:42', 'folderId': 'INBOX.Drafts'});

      expect(await service.cancelUndoSend(outboxId), isTrue);
      final draft = await (db.select(db.emails)..where((e) => e.id.equals(outboxId))).getSingle();
      expect(draft.folderId, 'drafts');
      final replaces = jsonDecode(prefs.getString('draft_replaces')!) as Map;
      expect(replaces[outboxId], {'id': 'INBOX.Drafts:42', 'folderId': 'INBOX.Drafts'});
    });

    test('«Отправить сейчас» — сутки повторов заново', () {
      final created = DateTime(2026, 11, 20, 9);
      SyncQueueData op(Map<String, Object?> p) => SyncQueueData(
          id: 1,
          accountId: 'a1',
          operationType: 'send_email',
          targetId: 'outbox_1',
          payloadJson: jsonEncode(p),
          priority: 0,
          createdAt: created,
          retryCount: 3);
      expect(OfflineSendService.retryWindowStart(op({})), created);
      expect(OfflineSendService.retryWindowStart(op({'scheduledAt': '2026-11-21T08:00:00.000'})), DateTime(2026, 11, 21, 8));
      expect(
          OfflineSendService.retryWindowStart(
              op({'scheduledAt': '2026-11-21T08:00:00.000', 'retryFrom': '2026-11-25T18:30:00.000'})),
          DateTime(2026, 11, 25, 18, 30));
    });
  });
}

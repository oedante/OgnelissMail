// «На контроле» и «Позже» на всех устройствах (решения владельца
// 13.11.2026): IMAP — ключевые слова $OgnControl и $OgnLater без дат,
// Exchange — флажок «… · OGN-C/L» с датами.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show accountsProvider;
import 'package:ogneliss/services/mail/control_service.dart';
import 'package:ogneliss/services/mail/email_actions_service.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/mail/marks/mark_sync.dart';
import 'package:ogneliss/services/mail/marks/mark_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Imap extends ImapService {
  _Imap() : super(SecureStorageService());
  final calls = <String>[];
  bool keywords = true;

  @override
  Future<bool> setMarks(AccountModel account, {required String folderId, required String uid, bool? control, bool? later}) async {
    calls.add('$folderId:$uid c=$control l=$later');
    return keywords;
  }
}

class _Actions extends EmailActionsService {
  _Actions(super.ref, this.db);
  final AppDatabase db;
  @override
  Future<void> setLater(String emailId, String accountId, {required bool on, DateTime? at}) =>
      db.setLaterState(emailId, accountId, on ? 1 : 0, remindAt: on ? at : null);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  group('правила сверки', () {
    test('флаги IMAP: изменилось у себя — на сервер, на сервере — у себя', () {
      expect(MarkSync.planBits(local: 1, synced: null, remote: null), MarkAction.push);
      expect(MarkSync.planBits(local: 1, synced: 1, remote: 1), MarkAction.none);
      expect(MarkSync.planBits(local: 1, synced: 1, remote: 0), MarkAction.apply, reason: 'сняли на другом устройстве');
      expect(MarkSync.planBits(local: 0, synced: null, remote: 2), MarkAction.apply, reason: 'отложили на другом');
      expect(MarkSync.planBits(local: 3, synced: 1, remote: 0), MarkAction.push, reason: 'своё новее');
      expect(MarkSync.planBits(local: 1, synced: null, remote: 1), MarkAction.none);
    });

    test('флажок Exchange: текст, код и отметки по нему', () {
      const s = MarkState(c: 2, l: 1);
      final t = MarkFlag.text(s, control: 'На контроле', later: 'Посмотреть позже');
      expect(t, 'На контроле · OGN-CL');
      expect(MarkFlag.codeOf(t), 'CL');
      expect(MarkFlag.codeOf('Flag for follow up'), isNull, reason: 'флажок пользователя');
      expect(MarkFlag.codeOf('Посмотреть позже · OGN-L'), 'L');
      final due = DateTime(2026, 11, 20);
      final st = MarkFlag.stateOf('C', complete: false, due: due, local: MarkState.none, kind: 1);
      expect((st.c, st.l, st.due), (1, 0, due));
      expect(MarkFlag.stateOf('C', complete: true, local: const MarkState(c: 2), kind: 1).c, 3, reason: 'выполнено в Outlook');
      expect(MarkSync.planFlag(local: const MarkState(c: 1), synced: null, remote: st), MarkAction.push);
      expect(MarkSync.planFlag(local: MarkState.none, synced: null, remote: st), MarkAction.apply);
    });
  });

  group('служба', () {
    late AppDatabase db;
    late ProviderContainer c;
    late _Imap imap;
    final acc = AccountModel(id: 'a', type: AccountType.imap, email: 'me@corp.ru', displayName: 'Я', username: 'me@corp.ru', createdAt: DateTime(2026));

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a', type: AccountType.imap.index, email: acc.email, displayName: 'Я', username: acc.email, createdAt: DateTime(2026)));
      await db.into(db.folders).insert(
          FoldersCompanion.insert(id: 'INBOX', accountId: 'a', displayName: 'Входящие', type: Value(FolderType.inbox.index)));
      for (final (id, from) in [('INBOX:1', 'boss@corp.ru'), ('INBOX:2', 'me@corp.ru'), ('INBOX:3', 'x@corp.ru')]) {
        await db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a',
              folderId: 'INBOX',
              fromEmail: from,
              toRecipients: from == 'me@corp.ru' ? '[{"email":"boss@corp.ru"}]' : '[{"email":"me@corp.ru"}]',
              subject: 'Письмо $id',
              receivedAt: DateTime(2026, 11, 13),
            ));
      }
      imap = _Imap();
      c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        imapServiceProvider.overrideWithValue(imap),
        emailActionsProvider.overrideWith((ref) => _Actions(ref, db)),
      ]);
      c.read(accountsProvider);
      for (var i = 0; i < 50 && c.read(accountsProvider).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    Future<Email> row(String id) async => (await db.getEmailById(id, accountId: 'a'))!;

    test('отметки этого устройства уходят на сервер; второй раз — ничего', () async {
      final svc = c.read(markSyncProvider);
      await db.setControlState('INBOX:1', 'a', ControlState.mustReply, deadline: DateTime(2026, 11, 20));
      await db.setLaterState('INBOX:3', 'a', 1, remindAt: DateTime(2026, 11, 14, 9));
      await svc.pushLocal(acc);
      expect(imap.calls, containsAll(['INBOX:1 c=true l=null', 'INBOX:3 c=null l=true']));
      imap.calls.clear();
      await svc.pushLocal(acc);
      expect(imap.calls, isEmpty);
      // Сняли «На контроле» — флаг снимается.
      await db.setControlState('INBOX:1', 'a', ControlState.none);
      await svc.pushLocal(acc);
      expect(imap.calls, ['INBOX:1 c=false l=null']);
    });

    test('с сервера: отметки другого устройства — без дат; снятие — снимает здесь', () async {
      final svc = c.read(markSyncProvider);
      await svc.applyImap(acc, {'INBOX:1': 1, 'INBOX:2': 1, 'INBOX:3': 2});
      expect((await row('INBOX:1')).controlState, ControlState.mustReply, reason: 'входящее мне');
      expect((await row('INBOX:2')).controlState, ControlState.awaitingReply, reason: 'моё письмо');
      final later = await row('INBOX:3');
      expect((later.laterState, later.remindAt), (1, null));
      // На сервер это не уходит обратно.
      await svc.pushLocal(acc);
      expect(imap.calls, isEmpty);
      // На другом устройстве сняли «На контроле» с первого письма.
      await svc.applyImap(acc, {'INBOX:1': 0, 'INBOX:2': 1});
      expect((await row('INBOX:1')).controlState, ControlState.none);
      expect((await row('INBOX:2')).controlState, ControlState.awaitingReply);
    });

    test('своё срок «Позже» остаётся: с сервера приходит только «отложено»', () async {
      final svc = c.read(markSyncProvider);
      final at = DateTime(2026, 11, 14, 9);
      await db.setLaterState('INBOX:3', 'a', 1, remindAt: at);
      await svc.pushLocal(acc);
      await svc.applyImap(acc, {'INBOX:3': 2});
      expect((await row('INBOX:3')).remindAt, at);
    });

    test('сервер не хранит свои флаги — отметки остаются на устройстве, без повторов', () async {
      final svc = c.read(markSyncProvider);
      imap.keywords = false;
      await db.setControlState('INBOX:1', 'a', ControlState.mustReply);
      await db.setControlState('INBOX:2', 'a', ControlState.awaitingReply);
      await svc.pushLocal(acc);
      expect(imap.calls.length, 1);
      imap.calls.clear();
      await svc.pushLocal(acc);
      expect(imap.calls, isEmpty);
    });

    test('выключено — ничего не уходит и не приходит', () async {
      await c.read(sharedPrefsProvider).setBool(MarkSyncService.prefKey, false);
      final svc = c.read(markSyncProvider);
      await db.setControlState('INBOX:1', 'a', ControlState.mustReply);
      await svc.pushLocal(acc);
      await svc.applyImap(acc, {'INBOX:2': 1});
      expect(imap.calls, isEmpty);
      expect((await row('INBOX:2')).controlState, ControlState.none);
    });

    test('Exchange: наш флажок с сервера — отметки с датами, флажок пользователя — нет', () async {
      final svc = c.read(markSyncProvider);
      final due = DateTime(2026, 11, 20);
      final ours = await svc.applyEasFlag(
          'a',
          me.MailFlagChange(
              id: 'INBOX:1',
              folderId: 'INBOX',
              flagged: true,
              followUp: me.MailFollowUp(flagType: 'На контроле · OGN-C', due: due)));
      expect(ours, isTrue);
      final r = await row('INBOX:1');
      expect((r.controlState, r.followUpAt?.toLocal()), (ControlState.mustReply, due));
      final user = await svc.applyEasFlag('a',
          const me.MailFlagChange(id: 'INBOX:2', folderId: 'INBOX', flagged: true, followUp: me.MailFollowUp(flagType: 'Flag for follow up')));
      expect(user, isFalse);
      expect((await row('INBOX:2')).controlState, ControlState.none);
      // Флажок сняли в Outlook — отметка снимается.
      await svc.applyEasFlag('a', const me.MailFlagChange(id: 'INBOX:1', folderId: 'INBOX', flagged: false));
      expect((await row('INBOX:1')).controlState, ControlState.none);
    });
  });
}

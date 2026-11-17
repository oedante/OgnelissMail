// Исправления по журналу владельца 17.11.2026 (2.6.3): какие разрешения
// выдал Google, почему People API отказал, заголовок DMARC в журнале,
// календарь Google без повтора «все события за все годы» на тайм-аут.

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/contacts/google_people_photos.dart';
import 'package:ogneliss/services/mail/dav/dav_client.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/features/mail/widgets/mail_translation.dart';
import 'package:ogneliss/services/mail/oauth/direct_oauth.dart';
import 'package:ogneliss/services/sync/sync_service.dart';
import 'package:ogneliss/services/translation/translator.dart';
import 'package:ogneliss/widgets/common/bimi_avatar.dart';

/// Движок перевода, который язык не определяет («und» у ML Kit).
class _NoDetect implements Translator {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<String?> detectLanguage(String text) async => null;
  @override
  Future<LangDetection?> identifyLanguage(String text) async => null;
  @override
  Future<List<String>> supportedLanguages() async => const ['en', 'ru'];
  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async => const {};
  @override
  Future<Set<String>?> downloadedModels() async => null;
  @override
  Future<List<String>> missingModels(String from, String to) async => const [];
  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) async {}
  @override
  Future<void> deleteModel(String lang) async {}
  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async => texts;
  @override
  bool get googleAttribution => false;
  @override
  int? get modelSizeMb => null;
  @override
  bool get canManageModels => false;
}

void main() {
  test('перевод: движок не назвал язык, текст одним алфавитом — свой определитель', () async {
    const ru = 'Добрый день! Спасибо за отчёт, мы отправим договор в понедельник. '
        'Если будут вопросы по срокам, пишите, пожалуйста, мне или коллегам из отдела.';
    final r = await MailTranslationController.debugDetectLang(_NoDetect(), ru);
    expect(r?.lang, 'ru');
    expect(r?.confident, isTrue);
    expect(await MailTranslationController.debugDetectLang(_NoDetect(), '12345 ok'), isNull);
  });

  test('вход Google: в журнале — какие разрешения не выданы', () {
    const req = [
      'openid', 'email', 'profile', 'https://mail.google.com/',
      'https://www.googleapis.com/auth/calendar',
      'https://www.googleapis.com/auth/contacts.readonly',
    ];
    expect(
        DirectOAuth.grantedNote(req,
            'openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile '
            'https://mail.google.com/ https://www.googleapis.com/auth/calendar'),
        ' — не выданы: contacts.readonly');
    expect(
        DirectOAuth.grantedNote(req,
            'openid https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile '
            'https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/contacts.readonly'),
        ' — выданы все разрешения');
    expect(DirectOAuth.grantedNote(req, null), '');
  });

  test('People API: «не включён в проекте» отличается от «нет разрешения»', () {
    expect(
        GooglePeoplePhotos.isApiDisabled('{"error":{"code":403,"message":"People API has not been used in project 1 '
            'before or it is disabled.","status":"PERMISSION_DENIED","details":[{"reason":"SERVICE_DISABLED"}]}}'),
        isTrue);
    expect(
        GooglePeoplePhotos.isApiDisabled('{"error":{"code":403,"message":"Request had insufficient authentication '
            'scopes.","details":[{"reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT"}]}}'),
        isFalse);
  });

  test('заголовок Authentication-Results в журнале — без адресов и подписей', () {
    final s = BimiAvatar.maskAuthResults('mx.google.com;\r\n dkim=pass header.i=@email.example.com header.s=s1 '
        'header.b=AbCdEf123;\r\n spf=pass smtp.mailfrom="bounces+user=gmail.com@em1.example.com"; '
        'dmarc=pass header.from=example.com');
    expect(s, isNot(contains('user=gmail.com')));
    expect(s, isNot(contains('AbCdEf123')));
    expect(s, contains('***@em1.example.com'));
    expect(s, contains('dmarc=pass header.from=example.com'));
  });

  test('«Очистить корзину» IMAP: местный черновик — не команда серверу, письмо «папка:UID» — да', () {
    expect(MailEngineService.imapServerId('INBOX:123'), isTrue);
    expect(MailEngineService.imapServerId('[Gmail]/Корзина:7'), isTrue);
    expect(MailEngineService.imapServerId('draft-86064180-e999-48af-bf07-f8c5baf385a2'), isFalse);
    expect(MailEngineService.imapServerId('Trash:0'), isFalse);
  });

  test('IMAP: папку пересоздали (UIDVALIDITY) — отложенные действия по старым номерам отменены', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 1, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    for (final f in ['INBOX', 'Sent']) {
      await db.into(db.folders).insert(FoldersCompanion.insert(id: f, accountId: 'a1', displayName: f));
    }
    Future<void> mail(String id, String folder, {bool edited = false}) => db.into(db.emails).insert(EmailsCompanion.insert(
          id: id,
          accountId: 'a1',
          folderId: folder,
          fromEmail: 'anna@corp.example',
          toRecipients: '[]',
          subject: id,
          receivedAt: DateTime(2026, 11, 1),
          isLocallyModified: Value(edited),
        ));
    Future<void> op(String type, String target) => db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
        accountId: 'a1', operationType: type, targetId: target, payloadJson: '{}', createdAt: DateTime(2026, 11, 1)));
    await mail('INBOX:7', 'INBOX', edited: true);
    await mail('draft-1', 'INBOX', edited: true);
    await mail('Sent:7', 'Sent', edited: true);
    await op('delete', 'INBOX:7');
    await op('mark_read', 'INBOX:8');
    await op('delete', 'Sent:7');
    await op('send_email', 'outbox_1');

    expect(await SyncService.dropStaleImapOps(db, 'a1', 'INBOX'), 2);
    final left = await db.select(db.syncQueue).get();
    expect(left.map((o) => o.targetId), unorderedEquals(['Sent:7', 'outbox_1']));
    final mails = await db.select(db.emails).get();
    expect(mails.map((m) => m.id), unorderedEquals(['draft-1', 'Sent:7']));
  });

  group('календарь: запрос без диапазона дат', () {
    test('на тайм-аут — не повторяется (он ещё больше)', () async {
      var calls = 0;
      final c = MockClient((r) async {
        calls++;
        throw TimeoutException('slow');
      });
      final dav = DavClient('Bearer x', httpClient: c);
      final items = await dav.reportCalendarItems('https://dav.example/cal/',
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(items, isNull);
      expect(calls, 1);
      expect(dav.lastFailure, DavFailure.timeout);
    });

    test('сервер не принял диапазон (HTTP 400) — повтор без него', () async {
      final bodies = <String>[];
      final c = MockClient((r) async {
        bodies.add(r.body);
        if (r.body.contains('time-range')) return http.Response('bad', 400);
        return http.Response(
            '<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/cal/1.ics</d:href>'
            '<d:propstat><d:prop><d:getetag>"1"</d:getetag><c:calendar-data>BEGIN:VCALENDAR\nEND:VCALENDAR</c:calendar-data>'
            '</d:prop></d:propstat></d:response></d:multistatus>',
            207);
      });
      final dav = DavClient('Bearer x', httpClient: c);
      final items = await dav.reportCalendarItems('https://dav.example/cal/',
          from: DateTime(2026, 1, 1), to: DateTime(2026, 12, 31));
      expect(bodies.length, 2);
      expect(items, hasLength(1));
      expect(dav.lastFailure, isNull);
    });
  });
}

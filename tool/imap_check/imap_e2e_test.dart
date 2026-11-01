// ignore_for_file: invalid_use_of_visible_for_testing_member
// IMAP и SMTP на настоящем сервере (01.11.2026, вопрос владельца «IMAP
// полностью работает?»). Обычный `flutter test` (папка test/) эту проверку не
// запускает: нужен сервер IMAP с пустым ящиком и SMTP-приёмник.
//
//   python3 tool/imap_check/smtp_sink.py 1025 /tmp/smtp-sink &
//   OGN_IMAP=127.0.0.1:1143:e2e:e2epass OGN_SMTP=127.0.0.1:1025:/tmp/smtp-sink \
//     flutter test tool/imap_check/imap_e2e_test.dart
//
// Проверяется код приложения (ImapService) против сервера; «посторонний»
// клиент (enough_mail напрямую) кладёт письма и меняет флаги, как это делал
// бы другой почтовый клиент или веб-почта. Проверено на Dovecot 2.3
// (CONDSTORE, QRESYNC, NOTIFY, MOVE, SPECIAL-USE).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

final _imap = Platform.environment['OGN_IMAP']?.split(':');
final _smtp = Platform.environment['OGN_SMTP']?.split(':');

/// Байты «PDF» вложения — проверка, что вложение приходит без искажений.
final _pdf = Uint8List.fromList([
  ...utf8.encode('%PDF-1.4\n'),
  for (var i = 0; i < 3000; i++) i % 251,
  ...utf8.encode('\n%%EOF\n'),
]);

String _mail({
  required String subject,
  required String body,
  String from = 'Анна Петрова <anna@corp.example>',
  String messageId = '',
  bool html = false,
  Uint8List? pdf,
}) {
  final subj = '=?UTF-8?B?${base64.encode(utf8.encode(subject))}?=';
  final fromHdr = from.contains('<')
      ? '=?UTF-8?B?${base64.encode(utf8.encode(from.substring(0, from.indexOf('<')).trim()))}?= '
          '${from.substring(from.indexOf('<'))}'
      : from;
  final id = messageId.isEmpty ? '<${subject.hashCode}.${DateTime.now().microsecondsSinceEpoch}@corp.example>' : messageId;
  final head = 'From: $fromHdr\r\nTo: e2e@corp.example\r\nSubject: $subj\r\n'
      'Date: Sat, 01 Nov 2026 10:00:00 +0300\r\nMessage-ID: $id\r\nMIME-Version: 1.0\r\n';
  final text = 'Content-Type: ${html ? 'text/html' : 'text/plain'}; charset=utf-8\r\n'
      'Content-Transfer-Encoding: base64\r\n\r\n${base64.encode(utf8.encode(body))}\r\n';
  if (pdf == null) return '$head$text';
  const b = 'og-e2e-boundary';
  return '${head}Content-Type: multipart/mixed; boundary="$b"\r\n\r\n'
      '--$b\r\n$text'
      '--$b\r\nContent-Type: application/pdf; name="smeta.pdf"\r\n'
      'Content-Disposition: attachment; filename="smeta.pdf"\r\n'
      'Content-Transfer-Encoding: base64\r\n\r\n${base64.encode(pdf)}\r\n'
      '--$b--\r\n';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = (_imap?.length ?? 0) < 4 || (_smtp?.length ?? 0) < 3
      ? 'нет OGN_IMAP=host:port:user:password и OGN_SMTP=host:port:каталог'
      : null;

  late AccountModel account;
  late ImapService service;
  late ImapClient other; // «посторонний» клиент
  late ImapFolderState inboxState;
  final uids = <String, int>{}; // тема → UID во «Входящих»

  Future<Set<String>> flagsOf(String path, int uid) async {
    await other.selectMailboxByPath(path);
    final r = await other.uidFetchMessages(MessageSequence.fromId(uid, isUid: true), '(FLAGS)');
    return {...?r.messages.firstOrNull?.flags};
  }

  Future<List<EmailModel>> listOf(String path) async =>
      (await service.syncFolderDelta(account, folderId: path)).added;

  Future<void> append(String path, String raw, {List<String> flags = const []}) async {
    await other.appendMessage(MimeMessage.parseFromText(raw), targetMailboxPath: path, flags: flags);
  }

  setUpAll(() async {
    if (skip != null) return;
    final imap = _imap!, smtp = _smtp!;
    final (host, port, user, pass) = (imap[0], int.parse(imap[1]), imap[2], imap[3]);
    FlutterSecureStorage.setMockInitialValues({'pwd_e2e': pass});
    account = AccountModel(
      id: 'e2e',
      type: AccountType.imap,
      email: 'e2e@corp.example',
      displayName: 'Проверка',
      username: user,
      imapServer: host,
      imapPort: port,
      imapEncryption: EncryptionType.none,
      smtpServer: smtp[0],
      smtpPort: int.parse(smtp[1]),
      smtpEncryption: EncryptionType.none,
      createdAt: DateTime(2026),
    );
    service = ImapService(SecureStorageService());
    other = ImapClient(isLogEnabled: false);
    await other.connectToServer(host, port, isSecure: false);
    await other.login(user, pass);
    await append('INBOX', _mail(subject: 'Отчёт за октябрь', body: 'Добрый день! Отчёт во вложении.', pdf: _pdf));
    await append('INBOX', _mail(subject: 'Встреча завтра', body: '<p>Созвон в <b>15:00</b>.</p>', html: true));
    await append('INBOX', _mail(subject: 'Счёт №42', body: 'Оплатить до пятницы.'));
    await append('INBOX', _mail(subject: 'Рассылка', body: '<h1>Новости</h1>', html: true));
    await append('INBOX', _mail(subject: 'Удалят снаружи', body: 'x'));
  });

  tearDownAll(() async {
    if (skip != null) return;
    await service.stopAllIdle();
    try {
      await other.logout();
    } catch (_) {}
  });

  test('вход и папки по SPECIAL-USE', () async {
    expect(await service.testConnection(account), isTrue);
    final folders = await service.getFolders(account);
    FolderModel? byType(FolderType t) => folders.where((f) => f.type == t).firstOrNull;
    expect(byType(FolderType.inbox)?.id, 'INBOX');
    expect(byType(FolderType.sent)?.id, 'Sent');
    expect(byType(FolderType.trash)?.id, 'Trash');
    expect(byType(FolderType.drafts)?.id, 'Drafts');
    expect(byType(FolderType.junk)?.id, 'Junk');
  }, skip: skip);

  test('первая синхронизация: 5 писем, темы и отправитель по-русски, HIGHESTMODSEQ', () async {
    final d = await service.syncFolderDelta(account, folderId: 'INBOX');
    expect(d.reset, isTrue);
    expect(d.added, hasLength(5));
    for (final e in d.added) {
      uids[e.subject] = int.parse(e.id.split(':').last);
    }
    expect(uids.keys, containsAll(['Отчёт за октябрь', 'Встреча завтра', 'Счёт №42', 'Рассылка']));
    final report = d.added.firstWhere((e) => e.subject == 'Отчёт за октябрь');
    expect(report.from.displayName, 'Анна Петрова');
    expect(report.from.email, 'anna@corp.example');
    expect(report.isRead, isFalse);
    expect(d.state.highestModSeq, isNotNull, reason: 'CONDSTORE не включился');
    inboxState = d.state;
  }, skip: skip);

  test('письмо целиком: текст, HTML, вложение байт в байт', () async {
    final full = await service.getEmailDetail(account,
        folderId: 'INBOX', uid: uids['Отчёт за октябрь']!, fetchMode: EmailFetchMode.full);
    expect(full, isNotNull);
    expect('${full!.bodyPlain}${full.bodyHtml}', contains('Отчёт во вложении'));
    final att = full.attachments.where((a) => a.name == 'smeta.pdf').single;
    final bytes = await service.fetchAttachment(account,
        folderId: 'INBOX', uid: uids['Отчёт за октябрь']!, partNumber: att.id);
    expect(bytes, _pdf);
    // Режим по умолчанию («без вложений»): текст — без файла, файл — по запросу.
    final light = await service.getEmailDetail(account, folderId: 'INBOX', uid: uids['Отчёт за октябрь']!);
    expect('${light!.bodyPlain}${light.bodyHtml}', contains('Отчёт во вложении'));
    final att2 = light.attachments.where((a) => a.name == 'smeta.pdf').single;
    expect(await service.fetchAttachment(account, folderId: 'INBOX', uid: uids['Отчёт за октябрь']!, partNumber: att2.id),
        _pdf);
    final html = await service.getEmailDetail(account, folderId: 'INBOX', uid: uids['Встреча завтра']!);
    expect(html!.bodyHtml, contains('<b>15:00</b>'));
    final raw = await service.fetchRawMessage(account, folderId: 'INBOX', uid: uids['Счёт №42']!);
    expect(utf8.decode(raw!, allowMalformed: true), contains('Message-ID:'));
  }, skip: skip);

  test('прочитано и флажок из приложения видны другому клиенту', () async {
    await service.markAsRead(account, folderId: 'INBOX', uid: '${uids['Отчёт за октябрь']}', isRead: true);
    await service.flagEmail(account, folderId: 'INBOX', uid: '${uids['Отчёт за октябрь']}', isFlagged: true);
    expect(await flagsOf('INBOX', uids['Отчёт за октябрь']!), containsAll([MessageFlags.seen, MessageFlags.flagged]));
    await service.markAsRead(account, folderId: 'INBOX', uid: '${uids['Отчёт за октябрь']}', isRead: false);
    expect(await flagsOf('INBOX', uids['Отчёт за октябрь']!), isNot(contains(MessageFlags.seen)));
  }, skip: skip);

  test('быстрая синхронизация (QRESYNC): флаги, новое и удалённое другим клиентом', () async {
    await other.selectMailboxByPath('INBOX');
    await other.uidStore(MessageSequence.fromId(uids['Счёт №42']!, isUid: true), [MessageFlags.seen],
        action: StoreAction.add);
    await append('INBOX', _mail(subject: 'Новое письмо', body: 'Пришло, пока приложение спало.'));
    final gone = uids['Удалят снаружи']!;
    await other.selectMailboxByPath('INBOX');
    await other.uidStore(MessageSequence.fromId(gone, isUid: true), [MessageFlags.deleted], action: StoreAction.add);
    await other.uidExpunge(MessageSequence.fromId(gone, isUid: true));

    // Как приложение после первой загрузки (sync_service: история загружена — backfill 0).
    final d = await service.syncFolderDelta(account, folderId: 'INBOX', known: inboxState, backfill: 0);
    expect(d.fast, isTrue, reason: 'быстрый способ не сработал');
    expect(d.flags[uids['Счёт №42']]?.read, isTrue);
    expect(d.added.map((e) => e.subject), contains('Новое письмо'));
    final removed = d.vanished ?? {for (var u = d.checkedFrom ?? 0; u <= (d.checkedTo ?? -1); u++) if (!d.present.contains(u)) u};
    expect(removed, contains(gone));
    inboxState = d.state;
  }, skip: skip);

  test('папки: создать (кириллица), переименовать, переместить письмо, удалить', () async {
    final path = await service.createFolder(account, 'Проекты');
    expect(path, isNotNull);
    final folders = await service.getFolders(account);
    expect(folders.map((f) => f.displayName), contains('Проекты'));
    await service.moveEmail(account, fromFolderId: 'INBOX', toFolderId: path!, uid: '${uids['Рассылка']}');
    expect((await listOf(path)).map((e) => e.subject), ['Рассылка']);
    expect(await service.renameFolder(account, path: path, newName: 'Проекты 2026'), isTrue);
    final renamed = (await service.getFolders(account)).firstWhere((f) => f.displayName == 'Проекты 2026');
    expect((await listOf(renamed.id)).map((e) => e.subject), ['Рассылка']);
    expect(await service.deleteFolder(account, path: renamed.id), isTrue);
    expect((await service.getFolders(account)).map((f) => f.displayName), isNot(contains('Проекты 2026')));
  }, skip: skip);

  test('удаление: в корзину, из корзины — насовсем', () async {
    await service.deleteEmail(account, folderId: 'INBOX', uid: '${uids['Встреча завтра']}');
    final trash = await listOf('Trash');
    expect(trash.map((e) => e.subject), contains('Встреча завтра'));
    final t = trash.firstWhere((e) => e.subject == 'Встреча завтра');
    await service.deleteEmail(account, folderId: 'Trash', uid: t.id.split(':').last, hard: true);
    expect((await listOf('Trash')).map((e) => e.subject), isNot(contains('Встреча завтра')));
  }, skip: skip);

  test('поиск на сервере по-русски', () async {
    final found = await service.searchMailbox(account, 'Счёт');
    expect(found.map((e) => e.subject), contains('Счёт №42'));
  }, skip: skip);

  test('черновик: сохранить в «Черновики» и удалить', () async {
    const mid = '<draft-e2e-1@ogneliss>';
    await service.saveDraft(account,
        to: const [EmailAddress(email: 'boss@corp.example')],
        subject: 'Черновик отчёта',
        bodyHtml: '<p>Пишу…</p>',
        messageId: mid,
        attachments: [(name: 'smeta.pdf', contentType: 'application/pdf', bytes: _pdf)]);
    expect((await listOf('Drafts')).map((e) => e.subject), contains('Черновик отчёта'));
    await service.deleteDraftByMessageId(account, mid);
    expect((await listOf('Drafts')).map((e) => e.subject), isNot(contains('Черновик отчёта')));
  }, skip: skip);

  test('мгновенные уведомления: IDLE во «Входящих», NOTIFY в другой папке', () async {
    await other.createMailbox('Work');
    final events = <ImapPushEvent>[];
    final sub = service.startIdle(account, 'INBOX', watch: () async => ['Work']).listen(events.add);
    await Future<void>.delayed(const Duration(seconds: 2));
    await append('INBOX', _mail(subject: 'Срочно', body: 'IDLE'));
    await append('Work', _mail(subject: 'В рабочую папку', body: 'NOTIFY'));
    final until = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(until) &&
        !(events.any((e) => e.folderId == 'INBOX') && events.any((e) => e.folderId == 'Work'))) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await service.stopIdle(account.id);
    await sub.cancel();
    expect(events.map((e) => e.folderId), contains('INBOX'));
    expect(events.map((e) => e.folderId), contains('Work'), reason: 'NOTIFY: события по другой папке нет');
  }, skip: skip);

  test('отправка по SMTP: письмо с вложением, отчёт о доставке, копия в «Отправленных»', () async {
    final dir = Directory(_smtp![2]);
    final before = dir.existsSync() ? dir.listSync().where((f) => f.path.endsWith('.eml')).length : 0;
    await service.sendEmail(account,
        to: const [EmailAddress(email: 'client@other.example', displayName: 'Клиент')],
        subject: 'Смета на ноябрь',
        bodyHtml: '<p>Добрый день! Смета во вложении.</p>',
        attachments: [(name: 'smeta.pdf', contentType: 'application/pdf', bytes: _pdf)],
        requestDeliveryReport: true);
    final emls = dir.listSync().where((f) => f.path.endsWith('.eml')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(emls.length, before + 1);
    final last = emls.reduce((a, b) => int.parse(a.uri.pathSegments.last.split('.').first) >
            int.parse(b.uri.pathSegments.last.split('.').first)
        ? a
        : b);
    final msg = MimeMessage.parseFromText(File(last.path).readAsStringSync());
    expect(msg.decodeSubject(), 'Смета на ноябрь');
    expect(msg.findContentInfo().map((i) => i.fileName), contains('smeta.pdf'));
    final env = File(last.path.replaceAll('.eml', '.env')).readAsStringSync();
    expect(env, contains('client@other.example'));
    expect(env.toUpperCase(), contains('NOTIFY=SUCCESS'), reason: 'отчёт о доставке (DSN) не запрошен: $env');
    expect((await listOf('Sent')).map((e) => e.subject), contains('Смета на ноябрь'));
  }, skip: skip);
}

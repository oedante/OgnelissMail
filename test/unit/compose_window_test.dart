// Многооконный режим на компьютере (2.5.4, просьба владельца 15.11.2026:
// «как в Outlook»): письмо окна редактора уходит через главное окно, база —
// та же (второе соединение), изменения базы окна видит главное окно, окно
// закрывается только после записи черновика. Сами окна (desktop_multi_window)
// в тестах не создать — проверяется всё, что между ними.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/compose/compose_window.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/services/mail/draft_sync_service.dart';
import 'package:ogneliss/services/mail/offline_send_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отправка главного окна в тесте: запоминает письмо, отвечает заданным.
class _FakeSend extends OfflineSendService {
  _FakeSend(super.ref, this.answer);
  final Future<bool> Function() answer;
  Map<String, Object?>? got;

  @override
  Future<bool> sendOrQueue({
    required String accountId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool keepTooLarge = false,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
  }) {
    got = {
      'accountId': accountId,
      'to': to,
      'cc': cc,
      'subject': subject,
      'html': bodyHtml,
      'inReplyTo': inReplyTo,
      'files': attachments,
      'remote': remoteAttachments,
      'from': from,
      'keepTooLarge': keepTooLarge,
      'mdn': requestReadReceipt,
    };
    return answer();
  }
}

void main() {
  // Окно и главное окно — две базы на один файл намеренно.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('аргументы окна: туда и обратно; чужие аргументы — не окно редактора', () {
    const q = {'replyToId': 'm1', 'accountId': 'a1', 'withAttachments': 'true'};
    final back = ComposeWindowArgs.fromJson(const ComposeWindowArgs(q).toJson());
    expect(back?.query, q);
    expect(ComposeWindowArgs.fromJson({'kind': 'ogneliss-message'}), isNull);
    expect(ComposeWindowArgs.fromJson('x'), isNull);
  });

  test('настройки копией: списки строк и простые значения', () {
    final p = ComposeWindow.decodePrefs({
      's_locale': 'ru',
      'n': 3,
      'f': 1.5,
      'b': true,
      'list': ['a', 'b'],
      'junk': {'x': 1},
    });
    expect(p, {'s_locale': 'ru', 'n': 3, 'f': 1.5, 'b': true, 'list': ['a', 'b']});
    expect(p['list'], isA<List<String>>());
  });

  test('письмо окна: адреса, файлы, ссылки на файлы — без потерь', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    late _FakeSend send;
    final p = Provider<OfflineSendService>((ref) => send = _FakeSend(ref, () async => true));
    final service = c.read(p);
    final bytes = Uint8List.fromList([1, 2, 3]);
    final r = await ComposeWindowHost.send(service, {
      'accountId': 'a1',
      'to': SendCodec.addrList(const [EmailAddress(email: 'anna@corp.example', displayName: 'Анна')]),
      'cc': SendCodec.addrList(const [EmailAddress(email: 'boris@corp.example')]),
      'subject': 'Согласовано',
      'bodyHtml': '<p>Согласовано</p>',
      'inReplyTo': '<x@corp>',
      'attachments': SendCodec.fileList([(name: 'Смета.pdf', contentType: 'application/pdf', bytes: bytes)]),
      'remote': SendCodec.remoteList(
          const [(accountId: 'a1', emailId: 'm1', attachmentId: '2', name: 'Договор.pdf', contentType: null)]),
      'from': SendCodec.addrMap(const EmailAddress(email: 'otdel@corp.example', displayName: 'Отдел')),
      'keepTooLarge': true,
      'mdn': true,
    });
    expect(r, {'sent': true});
    final got = send.got!;
    expect((got['to'] as List<EmailAddress>).single.displayName, 'Анна');
    expect((got['cc'] as List<EmailAddress>).single.email, 'boris@corp.example');
    final files = got['files'] as List<({String name, String? contentType, Uint8List bytes})>;
    expect(files.single.name, 'Смета.pdf');
    expect(files.single.bytes, bytes);
    final remote = got['remote'] as List<RemoteAttachment>;
    expect(remote.single.attachmentId, '2');
    expect((got['from'] as EmailAddress).email, 'otdel@corp.example');
    expect(got['keepTooLarge'], isTrue);
    expect(got['mdn'], isTrue);
  });

  test('ответ главного окна: письмо слишком большое и сбой — исключениями в окне', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final big = c.read(Provider<OfflineSendService>(
        (ref) => _FakeSend(ref, () async => throw const MessageTooLargeException(sizeBytes: 30, limitBytes: 20))));
    final r = await ComposeWindowHost.send(big, {'accountId': 'a1', 'subject': '', 'bodyHtml': ''});
    expect(r['error'], 'too_large');
    expect(
        () => WindowSendService.decodeSendResult(r),
        throwsA(isA<MessageTooLargeException>()
            .having((e) => e.sizeBytes, 'size', 30)
            .having((e) => e.limitBytes, 'limit', 20)));

    final fail = c.read(Provider<OfflineSendService>((ref) => _FakeSend(ref, () async => throw StateError('нет связи'))));
    final r2 = await ComposeWindowHost.send(fail, {'accountId': 'a1', 'subject': '', 'bodyHtml': ''});
    expect(r2['error'], 'failed');
    expect(() => WindowSendService.decodeSendResult(r2), throwsStateError);

    expect(WindowSendService.decodeSendResult({'sent': false}), isFalse, reason: 'в очереди «Исходящих»');
  });

  test('окно открывает ту же базу вторым соединением', () async {
    final dir = await Directory.systemTemp.createTemp('cw');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ogneliss.db');
    final main = AppDatabase.forTesting(NativeDatabase(file));
    await main.into(main.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'i.petrov@corp.example', displayName: 'Иван', username: 'i', createdAt: DateTime(2026)));

    final window = AppDatabase.secondary(path: file.path);
    final rows = await window.select(window.accounts).get();
    expect(rows.single.email, 'i.petrov@corp.example');
    // Запись окна видна главному окну.
    await window.into(window.accounts).insert(AccountsCompanion.insert(
        id: 'a2', type: 7, email: 'otdel@corp.example', displayName: 'Отдел', username: 'o', createdAt: DateTime(2026)));
    expect((await main.select(main.accounts).get()).length, 2);
    await window.close();
    await main.close();

    expect(() => AppDatabase.secondary(path: '${dir.path}/нет.db').customSelect('SELECT 1').get(),
        throwsA(anything), reason: 'базы нет — окно не создаёт пустую');
  });

  test('изменения базы окна — главному окну: потоки перечитываются', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    final seen = <String>[];
    final sub = db.tableUpdates(const TableUpdateQuery.any()).listen((u) => seen.addAll(u.map((x) => x.table)));
    addTearDown(sub.cancel);
    await ComposeWindowHost.handle(c, 'composeDbChanged', {'tables': ['emails', 'folders']});
    await Future<void>.delayed(Duration.zero);
    expect(seen, containsAll(['emails', 'folders']));
  });

  test('главное окно помнит, какой черновик в каком окне: второе окно не открывается', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    addTearDown(ComposeWindow.editing.clear);
    await ComposeWindowHost.handle(c, 'composeDraft', {'op': 'begin', 'id': 'd1', 'window': '7'});
    expect(ComposeWindow.editing, {'d1': '7'});
    expect(DraftSyncService.editing, contains('d1'), reason: 'синхронизация не трогает черновик');
    // Отметка «закрыт» от другого окна — не наша.
    await ComposeWindowHost.handle(c, 'composeDraft', {'op': 'end', 'id': 'd1', 'window': '9'});
    expect(ComposeWindow.editing, {'d1': '7'});
    await ComposeWindowHost.handle(c, 'composeDraft', {'op': 'end', 'id': 'd1', 'window': '7'});
    expect(ComposeWindow.editing, isEmpty);
    expect(DraftSyncService.editing, isNot(contains('d1')));
  });

  test('окно закрывается после записи черновика (не дольше предела)', () async {
    ComposeWindow.inWindow = true;
    addTearDown(() => ComposeWindow.inWindow = false);
    final done = Completer<void>();
    var saved = false;
    unawaited(ComposeWindow.track(done.future.then((_) => saved = true)));
    Timer(const Duration(milliseconds: 50), done.complete);
    await ComposeWindow.idle(timeout: const Duration(seconds: 2));
    expect(saved, isTrue);

    // Зависшая запись не держит окно вечно.
    unawaited(ComposeWindow.track(Completer<void>().future));
    final t = Stopwatch()..start();
    await ComposeWindow.idle(timeout: const Duration(milliseconds: 200));
    expect(t.elapsedMilliseconds, lessThan(1500));
  });

  test('в главном окне учёт работы не ведётся', () async {
    expect(ComposeWindow.inWindow, isFalse);
    final f = Future<int>.value(1);
    expect(identical(ComposeWindow.track(f), f), isTrue);
    await ComposeWindow.idle(timeout: const Duration(milliseconds: 10));
  });
}

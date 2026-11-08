// Фоновая задача и открытое приложение (08.11.2026, вопрос владельца «не
// мешают ли друг другу пробуждение, сигнал сервера и Firebase»).
//
// Если фоновая задача проверила почту сама (в своём изоляте, со своим
// соединением с базой), открытый в приложении список о новых письмах не
// узнаёт: уведомления drift об изменениях работают внутри одного
// соединения. Следующие проверки приложения писем уже не находят — они в
// базе, — и список оставался прежним до перезапуска процесса. Теперь задача
// сообщает приложению «база изменилась», и оно перечитывает открытые
// запросы (notifyUpdates по всем таблицам).

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/services/background/background_service.dart' show notifyMainDbChanged;

Future<void> _mail(AppDatabase db, String id) => db.into(db.emails).insert(EmailsCompanion.insert(
      id: id,
      accountId: 'a1',
      folderId: 'INBOX',
      fromEmail: 'boss@example.com',
      toRecipients: '[]',
      subject: 'Письмо $id',
      receivedAt: DateTime(2026, 11, 8, 9),
    ));

void main() {
  late Directory dir;
  late AppDatabase app; // соединение приложения
  late AppDatabase bg; // соединение фоновой задачи

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ogneliss_bg_refresh');
    final file = File('${dir.path}/m.db');
    app = AppDatabase.forTesting(NativeDatabase(file));
    await app.into(app.accounts).insert(AccountsCompanion.insert(
          id: 'a1',
          type: 7,
          email: 'me@example.com',
          displayName: 'me',
          username: 'me',
          createdAt: DateTime(2026, 1, 1),
        ));
    await _mail(app, 'm1');
    bg = AppDatabase.forTesting(NativeDatabase(file));
  });

  tearDown(() async {
    await bg.close();
    await app.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('запись другого соединения список не видит, пока не перечитать', () async {
    final seen = <int>[];
    final sub = app.select(app.emails).watch().listen((rows) => seen.add(rows.length));
    await pumpEventQueue();
    expect(seen.last, 1);

    // Фоновая задача записала новое письмо своим соединением.
    await _mail(bg, 'm2');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(seen.last, 1, reason: 'поток приложения о чужой записи не узнаёт — так было');

    // То, что делает приложение по сообщению задачи (refreshFromDatabase).
    app.notifyUpdates({for (final t in app.allTables) TableUpdate.onTable(t)});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(seen.last, 2, reason: 'после перечитывания — новое письмо в списке');
    await sub.cancel();
  });

  test('фоновая задача сообщает приложению, что база изменилась', () async {
    const name = 'ogneliss_main_tasks_v1';
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(name);
    expect(IsolateNameServer.registerPortWithName(port.sendPort, name), isTrue);
    addTearDown(() {
      IsolateNameServer.removePortNameMapping(name);
      port.close();
    });
    final got = Completer<Object?>();
    port.listen((m) {
      if (!got.isCompleted) got.complete(m);
    });
    notifyMainDbChanged('WorkManager');
    expect(await got.future.timeout(const Duration(seconds: 2)), {'dbChanged': true});
  });

  test('приложения в процессе нет — сообщать некому, без ошибок', () {
    IsolateNameServer.removePortNameMapping('ogneliss_main_tasks_v1');
    expect(() => notifyMainDbChanged('WorkManager'), returnsNormally);
  });
}

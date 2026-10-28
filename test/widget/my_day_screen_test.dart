// «Мой день» строится на настоящей базе (в памяти): список и доска, письмо
// без грифа, «Позже», задача на сегодня. Версия 1.5.0 падала здесь на любом
// письме без грифа (подпись письма вызывала саму себя) — этот тест ловит
// такие ошибки до выдачи сборки.
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/my_day/my_day_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/later_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _laterSubject = 'Квартальный отчёт по ремонтам';
const _taskTitle = 'Согласовать график ТОиР';

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final now = DateTime.now();
  await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1',
        type: 7,
        email: 'me@example.com',
        displayName: 'Я',
        username: 'me',
        createdAt: DateTime(2026),
      ));
  await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'inbox',
        accountId: 'a1',
        displayName: 'Входящие',
        type: Value(FolderType.inbox.index),
      ));
  // Письмо без грифа (sensitivity = null), вернувшееся из «Позже».
  await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'm1',
        accountId: 'a1',
        folderId: 'inbox',
        fromEmail: 'boss@example.com',
        toRecipients: '[]',
        subject: _laterSubject,
        receivedAt: now.subtract(const Duration(hours: 2)),
        laterState: const Value(LaterState.returned),
        remindAt: Value(now.subtract(const Duration(minutes: 5))),
      ));
  // Непрочитанное без грифа — для счётчика и «почты за сегодня».
  await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'm2',
        accountId: 'a1',
        folderId: 'inbox',
        fromEmail: 'colleague@example.com',
        toRecipients: '[]',
        subject: 'Без грифа',
        receivedAt: now.subtract(const Duration(minutes: 30)),
      ));
  await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 't1',
        accountId: 'a1',
        title: _taskTitle,
        createdAt: now,
        dueDate: Value(DateTime(now.year, now.month, now.day, 23, 0)),
      ));
  return db;
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, SharedPreferences prefs) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MyDayScreen(),
    ),
  ));
  // Запросы к базе идут настоящим временем: даём им завершиться.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 100));
    if (find.textContaining(_taskTitle, findRichText: true).evaluate().isNotEmpty) break;
  }
}

Future<void> _tearDown(WidgetTester tester, AppDatabase db) async {
  // Убрать экран (таймер «сейчас», потоки базы) и закрыть базу.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(db.close);
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('ru');
  });

  testWidgets('список: письмо без грифа, «Позже» и задача на сегодня', (tester) async {
    SharedPreferences.setMockInitialValues({'myday_board': false});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(_db))!;

    await _pumpScreen(tester, db, prefs);

    expect(tester.takeException(), isNull);
    expect(find.byType(MyDayScreen), findsOneWidget);
    expect(find.textContaining(_taskTitle, findRichText: true), findsWidgets);
    expect(find.textContaining(_laterSubject, findRichText: true), findsWidgets);

    await _tearDown(tester, db);
  });

  testWidgets('доска строится без ошибок', (tester) async {
    SharedPreferences.setMockInitialValues({'myday_board': true});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(_db))!;

    await _pumpScreen(tester, db, prefs);

    expect(tester.takeException(), isNull);
    expect(find.byType(MyDayScreen), findsOneWidget);
    expect(find.textContaining(_taskTitle, findRichText: true), findsWidgets);

    await _tearDown(tester, db);
  });

  testWidgets('без ящиков — пустой день без ошибок', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await _pumpScreen(tester, db, prefs);

    expect(tester.takeException(), isNull);
    expect(find.byType(MyDayScreen), findsOneWidget);

    await _tearDown(tester, db);
  });
}

// Экран письма целиком (1.15.1, технические хвосты по решению владельца
// 07.11.2026): база в памяти, письмо с текстом и вложением уже в базе —
// сервер не нужен. Шапка (тема, отправитель), текст, плашка вложения,
// кнопки ответа; письмо, которого нет, — сообщение, а не вечная загрузка.

import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/screens/mail_detail_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/background/work_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _body = 'Добрый день! Прошу согласовать смету до пятницы.';

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: 'a1',
          type: 7,
          email: 'me@corp.example',
          displayName: 'Я',
          username: 'me',
          createdAt: DateTime(2026),
        ),
      );
  await db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: 'INBOX',
          accountId: 'a1',
          displayName: 'Входящие',
          type: Value(FolderType.inbox.index),
        ),
      );
  await db
      .into(db.emails)
      .insert(
        EmailsCompanion.insert(
          id: 'INBOX:42',
          accountId: 'a1',
          folderId: 'INBOX',
          fromEmail: 'petrova@corp.example',
          fromName: const Value('Мария Петрова'),
          toRecipients: jsonEncode([
            {'email': 'me@corp.example', 'displayName': 'Я'},
          ]),
          subject: 'Смета на ремонт офиса',
          bodyPlain: const Value(_body),
          bodyHtml: const Value('<p>$_body</p>'),
          bodyPreview: const Value(_body),
          receivedAt: DateTime(2026, 11, 6, 10, 30),
          isRead: const Value(true),
          hasAttachments: const Value(true),
          attachmentsJson: Value(
            jsonEncode([
              {'id': '2', 'name': 'Смета.xlsx', 'mimeType': 'application/vnd.ms-excel', 'size': 18432},
            ]),
          ),
        ),
      );
  return db;
}

Widget _app(AppDatabase db, SharedPreferences prefs, Widget home) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db), sharedPrefsProvider.overrideWithValue(prefs)],
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
    home: home,
  ),
);

/// Запросы базы идут в настоящем времени, кадры — в тестовом.
Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  // Пауза фоновой работы на время открытия письма считается по часам, а не
  // по тестовому времени, — снять её сразу.
  WorkScheduler.instance.releaseHold();
  await tester.pump(const Duration(seconds: 3));
  await tester.runAsync(db.close);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('письмо из базы: шапка, текст, вложение, кнопки ответа', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(_db))!;
    await tester.pumpWidget(_app(db, prefs, const MailDetailScreen(emailId: 'INBOX:42', accountId: 'a1')));
    await _settle(tester);

    expect(find.text('Смета на ремонт офиса'), findsWidgets);
    expect(find.textContaining('Мария Петрова'), findsWidgets);
    expect(find.textContaining('согласовать смету'), findsWidgets);
    expect(find.textContaining('Смета.xlsx'), findsWidgets);
    // «Ответить» с долгим нажатием (быстрые ответы) — без подсказки, по значку.
    expect(find.byIcon(AppIcons.reply), findsWidgets);
    expect(find.byIcon(AppIcons.reply_all), findsWidgets);

    // «Ещё» — карточка со всеми действиями по группам; «Переместить» — в
    // «Упорядочить» (1.15.0).
    await tester.tap(find.byTooltip('Ещё'));
    await _settle(tester, rounds: 4);
    expect(find.text('УПОРЯДОЧИТЬ'), findsOneWidget);
    expect(find.text('Переместить'), findsOneWidget);
    expect(find.text('Ответить всем'), findsWidgets);
    expect(tester.takeException(), isNull);
    await _done(tester, db);
  });

  testWidgets('письма нет в базе — сообщение, а не вечная загрузка', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(_db))!;
    await tester.pumpWidget(_app(db, prefs, const MailDetailScreen(emailId: 'INBOX:404', accountId: 'a1')));
    await _settle(tester);
    expect(find.text('Письмо не найдено'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await _done(tester, db);
  });
}

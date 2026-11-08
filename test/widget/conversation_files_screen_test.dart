// «Файлы и ссылки» беседы (2.2.0, план 08.11.2026 «из мессенджеров»).

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/screens/conversation_files_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUpAll(() => initializeDateFormatting('ru'));

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    Future<void> mail(String id, int day, {String? html, List<Map<String, Object?>> files = const []}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a1',
              folderId: 'INBOX',
              conversationId: const Value('c1'),
              fromEmail: 'anna@corp.example',
              fromName: const Value('Анна Петрова'),
              toRecipients: '[{"email":"me@corp.example","displayName":"Я"}]',
              subject: 'Отчёт',
              bodyHtml: Value(html),
              attachmentsJson: Value(files.isEmpty ? null : jsonEncode(files)),
              hasAttachments: Value(files.isNotEmpty),
              receivedAt: DateTime(2026, 11, day),
            ));
    await mail('INBOX:1', 2,
        html: '<p>Таблица: <a href="https://docs.example.com/t/7">план работ</a></p>',
        files: [
          {'id': '2', 'name': 'отчёт.xlsx', 'mimeType': 'application/vnd.ms-excel', 'size': 20480},
          {'id': '3', 'name': 'image001.png', 'mimeType': 'image/png', 'size': 900, 'isInline': true},
        ]);
    await mail('INBOX:2', 5, html: '<p>Спасибо</p><blockquote><a href="https://docs.example.com/t/7">план работ</a></blockquote>');
  });

  tearDown(() => db.close());

  testWidgets('вложения и ссылки писем беседы — на двух вкладках', (t) async {
    await t.pumpWidget(ProviderScope(
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
        home: const ConversationFilesScreen(conversationId: 'c1', accountId: 'a1'),
      ),
    ));
    // Ссылки разбираются в отдельном изоляте — настоящим временем.
    for (var i = 0; i < 50 && find.text('Ссылки · 1').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(find.text('Файлы и ссылки'), findsOneWidget);
    expect(find.text('Файлы · 1'), findsOneWidget, reason: 'картинка внутри текста — не файл беседы');
    expect(find.text('Ссылки · 1'), findsOneWidget, reason: 'ссылка из цитаты — один раз');
    expect(find.text('отчёт.xlsx'), findsOneWidget);
    expect(find.textContaining('Анна Петрова'), findsOneWidget);
    await t.tap(find.text('Ссылки · 1'));
    await t.pumpAndSettle();
    expect(find.text('план работ'), findsOneWidget);
    expect(find.textContaining('docs.example.com'), findsOneWidget);
  });
}

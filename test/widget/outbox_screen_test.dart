// Экран «Исходящие» (21.11.2026): письмо с отсчётом и не отправленное с
// ошибкой; полный свайп влево — «Отменить», письмо уходит в «Черновики».
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/screens/outbox_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('отсчёт, ошибка и «Отменить» свайпом', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
          username: 'me', createdAt: DateTime(2026)));
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            accountId: 'a1',
            operationType: 'send_email',
            targetId: 'q1',
            payloadJson: jsonEncode({
              'to': [{'email': 'boss@example.com'}],
              'subject': 'Отчёт',
              'bodyHtml': '<p>Текст</p>',
              'scheduledAt': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
            }),
            createdAt: DateTime.now(),
          ));
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            accountId: 'a1',
            operationType: 'send_failed',
            targetId: 'q2',
            payloadJson: jsonEncode({'to': [{'email': 'x@example.com'}], 'subject': 'Счёт', 'bodyHtml': ''}),
            createdAt: DateTime.now(),
            errorMessage: const Value('Сервер не принял письмо'),
          ));
    });
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
        home: const OutboxScreen(),
      ),
    ));
    for (var i = 0; i < 20 && find.text('Отчёт').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.text('Отчёт'), findsOneWidget);
    expect(find.text('Счёт'), findsOneWidget);
    expect(find.textContaining('Отправка через'), findsOneWidget);
    expect(find.text('Сервер не принял письмо'), findsOneWidget);
    expect(find.text('Отправить снова'), findsOneWidget);

    // Свайп влево по письму — под ним «Отменить» (сама отмена — в
    // test/unit/outbox_test.dart).
    expect(find.text('Отменить'), findsNWidgets(2), reason: 'кнопки у двух писем');
    await tester.drag(find.text('Отчёт'), const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Отменить'), findsNWidgets(3), reason: 'и действие свайпа');

    // Таймер отсчёта остановить: экран закрыть; потоки базы — дождаться.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  });
}

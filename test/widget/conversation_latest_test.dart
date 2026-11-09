// Беседа как чат: «↓ N новых» (2.2.0, план 08.11.2026 «из мессенджеров»).
// Беседа прокручена от последнего письма — кнопка «к последнему»; пришло
// новое письмо — число на ней; нажатие — к последнему, число сбрасывается.

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
import 'package:ogneliss/features/mail/screens/conversation_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUpAll(() => initializeDateFormatting('ru'));

  Future<void> mail(int n, {String from = 'anna@corp.example'}) => db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'INBOX:$n',
        accountId: 'a1',
        folderId: 'INBOX',
        conversationId: const Value('c1'),
        fromEmail: from,
        fromName: const Value('Анна Петрова'),
        toRecipients: '[{"email":"me@corp.example"}]',
        subject: 'Отчёт',
        bodyPreview: Value('Письмо номер $n — текст для карточки беседы, чтобы она была повыше.'),
        receivedAt: DateTime(2026, 11, 1).add(Duration(hours: n)),
        isRead: const Value(true),
      ));

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(FoldersCompanion.insert(id: 'INBOX', accountId: 'a1', displayName: 'Входящие'));
    for (var i = 1; i <= 30; i++) {
      await mail(i);
    }
  });

  tearDown(() => db.close());

  testWidgets('прокрутили от последнего — кнопка; новое письмо — «1»; нажатие — к последнему', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty()),
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
        home: const ConversationScreen(conversationId: 'c1', accountId: 'a1'),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(FloatingActionButton), findsNothing, reason: 'у последнего письма кнопки нет');

    // «Как чат» (reverse) — последнее письмо внизу: от него — вниз пальцем;
    // иначе — вверх.
    final chat = t.widget<ListView>(find.byType(ListView)).reverse;
    await t.drag(find.byType(ListView), Offset(0, chat ? 1500 : -1500));
    await t.pumpAndSettle();
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);

    await t.runAsync(() => mail(31));
    for (var i = 0; i < 20; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

    await t.tap(fab);
    await t.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    // Экран закрыт — отложенные таймеры экрана (запись «прочитано» и т. п.)
    // доходят до конца.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  });
}

// «Сводка ящиков» (2.7.4): карточка на ящик — непрочитанные во «Входящих»,
// три последних письма, выбранные папки с числом непрочитанных; нажатие на
// папку — эта папка этого ящика в ленте.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/features/mail/providers/start_screen.dart';
import 'package:ogneliss/features/mail/screens/accounts_board_screen.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('карточки ящиков, письма, папки; папка — в ленте', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      BoardFoldersNotifier.prefKey: jsonEncode({
        'a1': ['a1proj'],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await tester.runAsync(() async {
      for (final (id, name, mail) in [('a1', 'Работа', 'ivan@corp.example'), ('a2', 'Дом', 'ivan@home.example')]) {
        await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: id, type: AccountType.imap.index, email: mail, displayName: name, username: mail, createdAt: DateTime(2026)));
      }
      for (final (id, acc, name, type) in [
        ('a1in', 'a1', 'INBOX', FolderType.inbox),
        ('a1proj', 'a1', 'Проекты', FolderType.custom),
        ('a2in', 'a2', 'INBOX', FolderType.inbox),
      ]) {
        await db.into(db.folders).insert(FoldersCompanion.insert(
            id: id, accountId: acc, displayName: name, type: Value(type.index)));
      }
      for (var i = 1; i <= 4; i++) {
        await db.into(db.emails).insert(EmailsCompanion.insert(
              id: 'm$i',
              accountId: 'a1',
              folderId: 'a1in',
              fromEmail: 'anna$i@partner.example',
              fromName: Value('Анна $i'),
              toRecipients: '[]',
              subject: 'Смета $i',
              receivedAt: now.subtract(Duration(minutes: 10 * (5 - i))),
            ));
      }
      await db.into(db.emails).insert(EmailsCompanion.insert(
            id: 'p1',
            accountId: 'a1',
            folderId: 'a1proj',
            fromEmail: 'pm@corp.example',
            toRecipients: '[]',
            subject: 'План',
            receivedAt: now,
          ));
    });

    final router = GoRouter(initialLocation: '/accounts', routes: [
      GoRoute(path: '/accounts', builder: (_, __) => const AccountsBoardScreen()),
      GoRoute(path: '/mail', builder: (_, __) => const Scaffold(body: Text('ЛЕНТА'))),
    ]);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.lightTheme(1.0),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ));
    Future<void> settle(Finder f) async {
      for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    await settle(find.textContaining('Смета 4'));
    expect(find.text('Сводка ящиков'), findsOneWidget);
    expect(find.text('Работа'), findsOneWidget);
    expect(find.text('Дом'), findsOneWidget);
    // Три последних непрочитанных и «и ещё 1».
    for (final s in ['Смета 4', 'Смета 3', 'Смета 2']) {
      expect(find.textContaining(s, findRichText: true), findsOneWidget, reason: s);
    }
    expect(find.textContaining('Смета 1', findRichText: true), findsNothing);
    expect(find.text('и ещё 1'), findsOneWidget);
    expect(find.text('Новых писем нет'), findsOneWidget, reason: 'ящик «Дом»');
    expect(find.byKey(const ValueKey('board_folder_a1in')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('board_folder_a1proj')), matching: find.text('Проекты  1')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('board_all')), findsOneWidget, reason: 'два ящика — «Все ящики»');

    // «Вся почта» второго ящика — он становится текущим.
    await tester.tap(find.byKey(const ValueKey('board_allmail_a2')));
    await settle(find.text('ЛЕНТА'));
    expect(find.text('ЛЕНТА'), findsOneWidget);
    expect(container.read(activeAccountProvider)?.id, 'a2');
    expect(container.read(unifiedModeProvider), isTrue);
    expect(container.read(selectedFolderIdProvider), isNull);

    // Снова сводка — папка «Проекты» первого ящика.
    router.go('/accounts');
    await settle(find.byKey(const ValueKey('board_folder_a1proj')));
    await tester.tap(find.byKey(const ValueKey('board_folder_a1proj')));
    await settle(find.text('ЛЕНТА'));
    expect(container.read(activeAccountProvider)?.id, 'a1');
    expect(container.read(settingsProvider).activeAccountId, 'a1');
    expect(container.read(selectedFolderIdProvider), 'a1proj');
    expect(container.read(unifiedModeProvider), isFalse);
    expect(container.read(allAccountsModeProvider), isFalse);

    // Потоки базы держит контейнер: сначала он (отписка потоков drift —
    // таймерами в поддельном времени теста, их прокручивает pump), потом база.
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  testWidgets('«Мой день»: ящики кружками — число новых, нажатие — «Входящие» ящика', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      for (final (id, name) in [('a1', 'Работа'), ('a2', 'Дом')]) {
        await db.into(db.accounts).insert(AccountsCompanion.insert(
            id: id, type: AccountType.imap.index, email: '$id@example.com', displayName: name,
            username: id, createdAt: DateTime(2026)));
        await db.into(db.folders).insert(FoldersCompanion.insert(
            id: '${id}in', accountId: id, displayName: 'INBOX', type: Value(FolderType.inbox.index)));
      }
      for (var i = 0; i < 2; i++) {
        await db.into(db.emails).insert(EmailsCompanion.insert(
              id: 'd$i', accountId: 'a2', folderId: 'a2in', fromEmail: 'x@example.com',
              toRecipients: '[]', subject: 'Письмо $i', receivedAt: DateTime.now()));
      }
    });
    final router = GoRouter(initialLocation: '/my-day', routes: [
      GoRoute(path: '/my-day', builder: (_, __) => const Scaffold(bottomNavigationBar: AccountsStrip())),
      GoRoute(path: '/mail', builder: (_, __) => const Scaffold(body: Text('ЛЕНТА'))),
      GoRoute(path: '/accounts', builder: (_, __) => const Scaffold(body: Text('СВОДКА'))),
    ]);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ));
    final a2Badge = find.descendant(of: find.byKey(const ValueKey('strip_a2')), matching: find.text('2'));
    for (var i = 0; i < 40 && a2Badge.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('strip_all')), findsOneWidget);
    expect(a2Badge, findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('strip_a1')), matching: find.text('Работа')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('strip_a2')));
    for (var i = 0; i < 40 && find.text('ЛЕНТА').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
    expect(container.read(activeAccountProvider)?.id, 'a2');
    expect(container.read(selectedFolderIdProvider), 'a2in');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  test('начальный экран: адрес; «Мой день» выключен — почта', () {
    expect(startScreenRoute(StartScreen.mail, myDayOn: true), '/mail');
    expect(startScreenRoute(StartScreen.myDay, myDayOn: true), '/my-day');
    expect(startScreenRoute(StartScreen.myDay, myDayOn: false), '/mail');
    expect(startScreenRoute(StartScreen.board, myDayOn: false), '/accounts');
  });
}

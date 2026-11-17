// Сочетания клавиш на компьютере (владелец 17.11.2026: «сочетания клавиш
// не реагировали на Windows и macOS»). Окно как в приложении: оболочка с
// общими клавишами (KeyboardShortcutsWrapper, фокус у неё при запуске),
// лента и письмо в панели справа.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/features/mail/screens/mail_detail_screen.dart';
import 'package:ogneliss/features/mail/screens/mail_list_screen.dart';
import 'package:ogneliss/features/mail/widgets/mail_find.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/background/work_scheduler.dart';
import 'package:ogneliss/widgets/common/keyboard_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

var refreshes = 0;
final tabs = <int>[];

const _n = 8;

String _subject(int i) => 'Смета участка $i';

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1',
        type: 7,
        email: 'me@corp.example',
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
  final now = DateTime.now();
  for (var i = 1; i <= _n; i++) {
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'm$i',
          accountId: 'a1',
          folderId: 'inbox',
          // Без «@»: строка не просит фото у адресной книги.
          fromEmail: 'sender-$i',
          fromName: Value('Отправитель $i'),
          toRecipients: '[]',
          subject: _subject(i),
          // m1 — самое новое, вверху ленты.
          receivedAt: now.subtract(Duration(minutes: i)),
          isRead: const Value(true),
        ));
  }
  return db;
}

/// Лента без сервера: письма — из базы, «Обновить» ничего не делает.
class _NoSyncEmails extends EmailsNotifier {
  _NoSyncEmails(Ref ref)
      : super(
          ref: ref,
          db: ref.watch(databaseProvider),
          account: ref.watch(activeAccountProvider),
          accounts: ref.watch(accountsProvider),
          folderId: ref.watch(selectedFolderIdProvider),
          isUnified: ref.watch(unifiedModeProvider),
          allAccountsMode: ref.watch(allAccountsModeProvider),
          groupByConversation: false,
        );

  @override
  Future<void> refresh() async {}
}

Future<SharedPreferences> _prefs({String pane = 'right'}) async {
  SharedPreferences.setMockInitialValues({
    // Экран разрешений после входа и листание соседних писем — не здесь.
    'perm_setup_shown_v2': true,
    'mail_swipe_pager': false,
    'reading_pane': pane,
  });
  return SharedPreferences.getInstance();
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpList(WidgetTester tester, AppDatabase db, SharedPreferences prefs,
    {Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/mail', routes: [
    GoRoute(
      path: '/mail',
      builder: (_, __) => KeyboardShortcutsWrapper(onRefresh: () => refreshes++, onSwitchTab: tabs.add, child: const MailListScreen()),
      routes: [
        GoRoute(
          path: 'detail/:id',
          builder: (_, s) => Scaffold(body: Text('ЭКРАН ПИСЬМА ${s.pathParameters['id']}')),
        ),
      ],
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      emailsProvider.overrideWith(_NoSyncEmails.new),
    ],
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
  await _settle(tester);
  expect(find.text(_subject(1)), findsOneWidget);
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  // Отложенный прогрев (движок письма, редактор) — после ухода экрана.
  // Пауза фоновой работы на время открытия письма — по настоящим часам.
  WorkScheduler.instance.releaseHold();
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(db.close);
}

String? _open(WidgetTester tester) {
  final d = find.byType(MailDetailScreen);
  return d.evaluate().isEmpty ? null : tester.widget<MailDetailScreen>(d).emailId;
}

Future<void> _click(WidgetTester tester, Finder f) async {
  await tester.tap(f, kind: PointerDeviceKind.mouse);
  await _settle(tester, rounds: 4);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {bool control = false, bool meta = false}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _settle(tester, rounds: 4);
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('ru');
  });

  testWidgets('сразу после запуска: F5 и J — без нажатия мышью', (tester) async {
    refreshes = 0;
    final db = (await tester.runAsync(_db))!;
    await _pumpList(tester, db, await _prefs());
    await _press(tester, LogicalKeyboardKey.f5);
    expect(refreshes, 1, reason: 'F5 — проверить почту');
    await _press(tester, LogicalKeyboardKey.keyJ);
    expect(_open(tester), 'm1', reason: 'J — первое письмо в панели');
    await _press(tester, LogicalKeyboardKey.keyJ);
    expect(_open(tester), 'm2');
    await _done(tester, db);
  });

  testWidgets('письмо открыто мышью: J/K, F4 — поиск в письме, Esc; F5 — по-прежнему', (tester) async {
    refreshes = 0;
    final db = (await tester.runAsync(_db))!;
    await _pumpList(tester, db, await _prefs());
    await _click(tester, find.text(_subject(2)));
    expect(_open(tester), 'm2');
    await _press(tester, LogicalKeyboardKey.keyJ);
    expect(_open(tester), 'm3', reason: 'J после открытия мышью');
    await _press(tester, LogicalKeyboardKey.keyK);
    expect(_open(tester), 'm2');
    await _press(tester, LogicalKeyboardKey.f4);
    expect(find.byType(MailFindBar), findsOneWidget, reason: 'F4 — поиск в письме из панели');
    await _press(tester, LogicalKeyboardKey.f5);
    expect(refreshes, 1);
    await _done(tester, db);
  });

  testWidgets('F4 сразу после открытия мышью', (tester) async {
    final db = (await tester.runAsync(_db))!;
    await _pumpList(tester, db, await _prefs());
    await _click(tester, find.text(_subject(2)));
    await _press(tester, LogicalKeyboardKey.f4);
    expect(find.byType(MailFindBar), findsOneWidget, reason: 'F4 — поиск в письме из панели');
    await _done(tester, db);
  });

  testWidgets('нажатие мышью в письме (панель): клавиши письма и ленты работают', (tester) async {
    final db = (await tester.runAsync(_db))!;
    await _pumpList(tester, db, await _prefs());
    await _click(tester, find.text(_subject(2)));
    // Нажатие по теме письма в панели (не в ленте).
    final inPane = find.descendant(of: find.byType(MailDetailScreen), matching: find.text(_subject(2)));
    await _click(tester, inPane.first);
    await _press(tester, LogicalKeyboardKey.f4);
    expect(find.byType(MailFindBar), findsOneWidget, reason: 'F4 после нажатия в письме');
    await _done(tester, db);
  });

  testWidgets('Ctrl+2 — раздел; Windows: ⊞+2 — ничего', (tester) async {
    tabs.clear();
    final db = (await tester.runAsync(_db))!;
    await _pumpList(tester, db, await _prefs());
    await _press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(tabs, [1]);
    await _press(tester, LogicalKeyboardKey.digit3, meta: true);
    expect(tabs, [1], reason: 'не на Mac клавиша Windows не главная');
    await _done(tester, db);
  });

  testWidgets('Mac: ⌘2 — раздел, ⌘F — поиск в письме, ⌘Q не перехватывается', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tabs.clear();
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs());
      await _press(tester, LogicalKeyboardKey.digit2, meta: true);
      expect(tabs, [1]);
      await _click(tester, find.text(_subject(2)));
      await _press(tester, LogicalKeyboardKey.keyF, meta: true);
      expect(find.byType(MailFindBar), findsOneWidget);
      // Справка Mac — те же сочетания.
      final keys = desktopKeyList(AppLocalizations.of(tester.element(find.byType(MailListScreen))), mac: true);
      expect(keys.map((e) => e.$1), containsAll(['⌘R', '⌘J', '⌘F   F4', '⌘1 … 5', '⌃Q']));
      await _done(tester, db);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('withMacCommand: на Mac — и ⌘, кроме исключений; на Windows — как есть', () {
    final m = {
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): 1,
      const SingleActivator(LogicalKeyboardKey.keyQ, control: true): 2,
      const SingleActivator(LogicalKeyboardKey.f5): 3,
    };
    expect(withMacCommand(m), m);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final mac = withMacCommand({
        ...m,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): 4,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): 5,
      }, except: {LogicalKeyboardKey.keyQ});
      int? cmd(LogicalKeyboardKey k) => [
            for (final e in mac.entries)
              if (e.key case SingleActivator(meta: true, :final trigger) when trigger == k) e.value,
          ].singleOrNull;
      expect(cmd(LogicalKeyboardKey.keyR), 1);
      expect(cmd(LogicalKeyboardKey.keyQ), isNull, reason: '⌘Q — выход из программы');
      expect(cmd(LogicalKeyboardKey.keyF), 5, reason: 'свой ⌘ не дублируется');
      expect(mac, hasLength(6));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

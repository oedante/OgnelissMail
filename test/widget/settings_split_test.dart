// Настройки в две колонки на компьютере и планшете (2.3.0, решение
// владельца 10.11.2026): слева — список разделов, справа — открытый раздел
// без «Назад»; вглубь из раздела — с «Назад» справа; на телефоне — как
// раньше: список, раздел поверх с «Назад».

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/screens/settings_screen.dart';
import 'package:ogneliss/features/settings/widgets/settings_split.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _screen(String title, {String? deeper}) => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: deeper == null
            ? const SizedBox()
            : TextButton(onPressed: () => context.push(deeper), child: Text('ВГЛУБЬ $title')),
      ),
    );

GoRouter _router() => GoRouter(initialLocation: '/mail', routes: [
      GoRoute(
        path: '/mail',
        builder: (context, __) => Scaffold(
          body: Center(
            child: TextButton(onPressed: () => context.push('/settings'), child: const Text('ЛЕНТА')),
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, st) => settingsRoutePage(st, const SettingsScreen(), splitChild: _screen('ОБЩИЕ')),
      ),
      GoRoute(path: '/settings/mail', pageBuilder: (_, st) => settingsRoutePage(st, _screen('ПОЧТА', deeper: '/settings/swipes'))),
      GoRoute(path: '/settings/swipes', pageBuilder: (_, st) => settingsRoutePage(st, _screen('СВАЙПЫ'))),
      GoRoute(path: '/settings/notifications', pageBuilder: (_, st) => settingsRoutePage(st, _screen('УВЕДОМЛЕНИЯ'))),
    ]);

Future<(GoRouter, AppDatabase)> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final router = _router();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
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
  await tester.tap(find.text('ЛЕНТА'));
  await _settle(tester);
  return (router, db);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(db.close);
}

Finder _inList(Finder f) => find.descendant(of: find.byKey(const ValueKey('settings_split_list')), matching: f);

Finder _inDetail(Finder f) => find.descendant(of: find.byKey(const ValueKey('settings_split_detail')), matching: f);

/// Выделенные строки списка (названия).
List<String> _selectedRows(WidgetTester tester) => [
      for (final e in _inList(find.byType(ListTile)).evaluate())
        if ((e.widget as ListTile).selected)
          tester.widget<Text>(find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text)).first).data!,
    ];

Future<void> _tapInList(WidgetTester tester, String title) async {
  // Строка, а не заголовок группы с тем же названием («Уведомления»).
  final f = _inList(find.descendant(of: find.byType(ListTile), matching: find.text(title)));
  final list = find.descendant(of: find.byKey(const ValueKey('settings_split_list')), matching: find.byType(Scrollable)).first;
  if (f.evaluate().isEmpty) {
    // Список открыт там, где его оставили: раздел может быть выше.
    for (var i = 0; i < 20 && f.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, 200));
      await tester.pump();
    }
    if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 200, scrollable: list);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('компьютер: список слева, раздел справа без «Назад», вглубь — с «Назад»', (tester) async {
    final (router, db) = await _pump(tester, const Size(1280, 800));
    final l10n = AppLocalizations.of(tester.element(find.byType(SettingsScreen).first));
    final mail = l10n.tr('mailReadingSettings');
    final general = l10n.tr('general');
    final notifications = l10n.tr('notifications');

    expect(find.byKey(const ValueKey('settings_split_list')), findsOneWidget);
    expect(_inDetail(find.text('ОБЩИЕ')), findsOneWidget, reason: 'справа — «Общие», а не второй список');
    expect(_selectedRows(tester), [general]);
    expect(_inDetail(find.byType(BackButton)), findsNothing);

    await _tapInList(tester, mail);
    expect(_inDetail(find.text('ПОЧТА')), findsOneWidget);
    expect(_selectedRows(tester), [mail]);
    expect(_inDetail(find.byType(BackButton)), findsNothing, reason: 'раздел из списка — без «Назад»');

    await tester.tap(find.text('ВГЛУБЬ ПОЧТА'));
    await _settle(tester);
    expect(_inDetail(find.text('СВАЙПЫ')), findsOneWidget);
    expect(_inDetail(find.byType(BackButton)), findsOneWidget, reason: 'вглубь — «Назад» к разделу');
    expect(_selectedRows(tester), [mail], reason: 'выбран раздел, из которого пришли');

    // Другой раздел из списка — вместо открытых, без «Назад».
    await _tapInList(tester, notifications);
    expect(_inDetail(find.text('УВЕДОМЛЕНИЯ')), findsOneWidget);
    expect(_inDetail(find.byType(BackButton)), findsNothing);
    final pages = router.routerDelegate.currentConfiguration.matches.map((m) => m.matchedLocation).toList();
    expect(pages, ['/mail', '/settings', '/settings/notifications'], reason: 'открытые разделы сняты');

    // «Общие» — снова главный экран настроек.
    await _tapInList(tester, general);
    expect(_inDetail(find.text('ОБЩИЕ')), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.matches.map((m) => m.matchedLocation).toList(),
        ['/mail', '/settings']);

    // «Назад» над списком закрывает настройки.
    await tester.tap(_inList(find.byTooltip(l10n.tr('back'))));
    await _settle(tester);
    expect(find.text('ЛЕНТА'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    await _done(tester, db);
  });

  testWidgets('телефон: список, раздел поверх с «Назад»', (tester) async {
    final (_, db) = await _pump(tester, const Size(400, 800));
    final l10n = AppLocalizations.of(tester.element(find.byType(SettingsScreen).first));
    expect(find.byKey(const ValueKey('settings_split_list')), findsNothing);
    expect(find.text('ОБЩИЕ'), findsNothing);
    final mail = find.text(l10n.tr('mailReadingSettings'));
    await tester.scrollUntilVisible(mail, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(mail);
    await _settle(tester);
    expect(find.text('ПОЧТА'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _settle(tester);
    expect(find.text('ПОЧТА'), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _done(tester, db);
  });
}

// Вход по адресу (1.8.0, п. 6): адрес первым, способ — по домену. Gmail —
// кнопка «Войти через Google» (без пароля), Mail.ru — пароль приложения без
// кнопки входа через Mail.ru, «Изменить» возвращает к адресу.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/auth/screens/login_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('адрес первым: Gmail — вход через Google, Mail.ru — пароль приложения', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(400, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

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
        home: const LoginScreen(),
      ),
    ));
    await _settle(tester);

    // Шаг 1: адрес. Неверный адрес — ошибка у поля, шага 2 нет.
    expect(find.text('Далее'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ivan');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    expect(find.text('Далее'), findsOneWidget);
    expect(find.text('Введите корректный email'), findsWidgets);

    // Gmail → страница входа Google, пароля нет.
    await tester.enterText(find.byType(TextField).first, 'ivan@gmail.com');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    expect(find.text('Войти через Google'), findsOneWidget);
    expect(find.text('ivan@gmail.com'), findsOneWidget);
    expect(find.text('Пароль'), findsNothing);

    // «Изменить» — к адресу; Mail.ru — пароль приложения, без входа через Mail.ru.
    await tester.tap(find.text('Изменить'));
    await _settle(tester);
    expect(find.text('Далее'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ivan@bk.ru');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    expect(find.text('Пароль для внешнего приложения'), findsOneWidget);
    expect(find.text('Войти через Mail.ru'), findsNothing);

    // Пустой пароль — подсказка под полем.
    await tester.ensureVisible(find.text('Войти'));
    await tester.tap(find.text('Войти'));
    await _settle(tester);
    expect(find.text('Введите пароль'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

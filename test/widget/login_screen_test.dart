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
import 'package:ogneliss/services/mail/mail_provider_detect.dart' show MailKind;
import 'package:ogneliss/services/mail/oauth/cross_platform_oauth.dart';
import 'package:ogneliss/services/mail/oauth/oauth_service.dart';
import 'package:ogneliss/services/mail/oauth/proxy_pkce.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Вход через Google, который Google не пускает: лимит пользователей
/// непроверенного приложения (2.5.4).
/// Сборка с клиентами служб: вход через Google, Яндекс и Microsoft есть.
class _Direct extends CrossPlatformOAuthService {
  const _Direct();

  @override
  bool available(String providerName) => true;
}

/// Сборка без клиентов служб и без сервера входа: только пароль приложения.
class _NoDirect extends CrossPlatformOAuthService {
  const _NoDirect();

  @override
  bool available(String providerName) => false;
}

class _CapOAuth extends _Direct {
  const _CapOAuth();

  @override
  Future<OAuthResult> authenticate(String providerName, {String? loginHint}) async =>
      throw const OAuthProviderError(OAuthProviderError.userCap);
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('нет входа через службу на этой платформе — пароль приложения (Gmail, Яндекс)', (tester) async {
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
        crossPlatformOAuthProvider.overrideWithValue(const _NoDirect()),
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
    await tester.enterText(find.byType(TextField).first, 'ivan@gmail.com');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    expect(find.text('Войти через Google'), findsNothing);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.textContaining('двухэтапную проверку'), findsOneWidget);
    expect(find.text('Создать пароль приложения'), findsOneWidget);

    await tester.tap(find.text('Изменить'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, 'ivan@yandex.ru');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    expect(find.text('Войти через Яндекс'), findsNothing);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.textContaining('только по паролю приложения'), findsOneWidget);
    expect(find.text('Создать пароль приложения'), findsOneWidget);
  });

  testWidgets('Google не пускает новых пользователей — объяснение и вход паролем приложения', (tester) async {
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
        crossPlatformOAuthProvider.overrideWithValue(const _CapOAuth()),
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
    await tester.enterText(find.byType(TextField).first, 'ivan@gmail.com');
    await tester.tap(find.text('Далее'));
    await _settle(tester);
    await tester.tap(find.text('Войти через Google'));
    await _settle(tester);
    // Текст ошибки — на языке настроек (в тесте не задан), число — в любом.
    expect(find.textContaining('100 '), findsOneWidget);
    await tester.tap(find.text('Подключить паролем приложения'));
    await _settle(tester);

    // Вход по паролю: подсказка Google и ссылка на страницу паролей.
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.textContaining('двухэтапную проверку'), findsOneWidget);
    expect(find.text('Создать пароль приложения'), findsOneWidget);
    expect(find.text('Войти через Google'), findsNothing);
    expect(find.textContaining('100 '), findsNothing, reason: 'ошибка снята');
  });

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
        crossPlatformOAuthProvider.overrideWithValue(const _Direct()),
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

  // 1.8.8 (замечание 29.10.2026): способ входа — плиткой, без адреса;
  // у рабочей почты — переключатель «Exchange | IMAP».
  testWidgets('плитки способов входа и переключатель Exchange | IMAP', (tester) async {
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
        crossPlatformOAuthProvider.overrideWithValue(const _Direct()),
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

    // На первом шаге — плитки всех способов.
    for (final t in ['Google', 'Яндекс', 'Microsoft', 'Mail.ru', 'iCloud', 'Exchange', 'IMAP']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }

    // Exchange без адреса: шаг 2 с полем адреса и переключателем.
    await tester.ensureVisible(find.text('Exchange'));
    await tester.tap(find.text('Exchange'));
    await _settle(tester);
    expect(find.byType(SegmentedButton<MailKind>), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);

    // Поле адреса не пропадает, когда адрес стал похож на настоящий.
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'oedante@ogneliss.ru');
    await _settle(tester);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);

    // IMAP — серверы домена в «Расширенных настройках».
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<MailKind>), matching: find.text('IMAP')));
    await _settle(tester);
    expect(find.text('Другая почта (IMAP)'), findsOneWidget);
    expect(find.text('imap.ogneliss.ru'), findsOneWidget);
    expect(find.text('smtp.ogneliss.ru'), findsOneWidget);

    // Обратно на Exchange.
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<MailKind>), matching: find.text('Exchange')));
    await _settle(tester);
    expect(find.text('imap.ogneliss.ru'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

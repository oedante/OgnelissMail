// Окно входа на всех размерах (проверка UI 15.11.2026): узкий телефон,
// телефон, планшет, компьютер; обычный и крупный шрифт; светлая и тёмная
// темы. Переполнение вёрстки — ошибка теста. Шаг адреса, «IMAP организации»
// и окно «Вход через систему организации».

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
import 'package:ogneliss/services/mail/oauth/cross_platform_oauth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Direct extends CrossPlatformOAuthService {
  const _Direct();
  @override
  bool available(String providerName) => true;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  const sizes = {
    'узкий телефон': Size(320, 568),
    'телефон': Size(400, 860),
    'планшет': Size(820, 1180),
    'компьютер': Size(1440, 900),
  };

  for (final entry in sizes.entries) {
    for (final scale in [1.0, 1.3]) {
      for (final locale in ['ru', 'de']) {
        testWidgets('${entry.key}, шрифт ×$scale, $locale: без переполнений', (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          addTearDown(db.close);
          tester.view.physicalSize = entry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(db),
              sharedPrefsProvider.overrideWithValue(prefs),
              crossPlatformOAuthProvider.overrideWithValue(const _Direct()),
            ],
            child: MaterialApp(
              theme: scale > 1 ? AppTheme.darkTheme(scale) : AppTheme.lightTheme(scale),
              locale: Locale(locale),
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
          expect(tester.takeException(), isNull, reason: 'шаг адреса');

          // Окно «Вход через систему организации».
          await tester.ensureVisible(find.byKey(const ValueKey('login_sso')));
          await tester.tap(find.byKey(const ValueKey('login_sso')));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: 'окно входа организации');
          await tester.tapAt(const Offset(2, 2));
          await _settle(tester);

          // «IMAP организации» с расширенными настройками.
          await tester.ensureVisible(find.byKey(const ValueKey('login_work_imap')));
          await tester.tap(find.byKey(const ValueKey('login_work_imap')));
          await _settle(tester);
          expect(find.byKey(const ValueKey('imap_login')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'IMAP организации');
        });
      }
    }
  }
}

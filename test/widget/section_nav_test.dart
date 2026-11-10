// Разделы на компьютере и планшете (2.2.1, решение владельца 10.11.2026:
// без полосы слева; «Написать» и разделы — над «Избранным»).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show totalUnreadCountProvider;
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/navigation/section_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('разделы: переход, выбранный — по экрану; вне почты — «Мой день», «Поручения»…', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    Widget page(String name, {bool extras = false}) => Scaffold(
          body: Row(children: [
            SizedBox(width: 248, child: SingleChildScrollView(child: SectionNav(extras: extras))),
            Expanded(child: Text('ЭКРАН $name')),
          ]),
        );
    final router = GoRouter(initialLocation: '/mail', routes: [
      GoRoute(path: '/mail', builder: (_, __) => page('mail')),
      GoRoute(path: '/calendar', builder: (_, __) => page('calendar', extras: true)),
      GoRoute(path: '/assignments', builder: (_, __) => page('assignments', extras: true)),
      GoRoute(path: '/compose', builder: (_, __) => const Scaffold(body: Text('РЕДАКТОР'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        totalUnreadCountProvider.overrideWithValue(3),
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
    await tester.pumpAndSettle();
    expect(find.text('ЭКРАН mail'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'непрочитанные — на «Почте»');
    expect(find.byKey(const ValueKey('section_assignments')), findsNothing, reason: 'в почте — плитками «Избранного»');

    await tester.tap(find.byKey(const ValueKey('section_calendar')));
    await tester.pumpAndSettle();
    expect(find.text('ЭКРАН calendar'), findsOneWidget);
    expect(find.byKey(const ValueKey('section_assignments')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('section_assignments')));
    await tester.pumpAndSettle();
    expect(find.text('ЭКРАН assignments'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('section_compose')));
    await tester.pumpAndSettle();
    expect(find.text('РЕДАКТОР'), findsOneWidget);
  });
}

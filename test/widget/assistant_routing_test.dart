// Siri и Google Ассистент → экран (1.9.x): платформа кладёт «экран» в канал
// ogneliss/widget («take» при запуске, «open» — пришло новое), Dart
// открывает нужное окно (AppShortcuts.openType). Канал — поддельный.

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/navigation/app_router.dart';
import 'package:ogneliss/core/platform/app_shortcuts.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/home_widget_service.dart';
import 'package:ogneliss/widgets/navigation/panel_requests.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('ogneliss/widget');

  testWidgets('экраны из канала: холодный запуск и «open»', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    Object? eventExtra;
    Uri? composeUri;
    final router = GoRouter(
      initialLocation: '/my-day',
      routes: [
        for (final p in ['/mail', '/my-day', '/calendar', '/tasks'])
          GoRoute(path: p, builder: (_, s) => Text(s.uri.toString())),
        // Редакторы открываются поверх (push) — адрес запоминает сам маршрут.
        GoRoute(
          path: '/compose',
          builder: (_, s) {
            composeUri = s.uri;
            return const Text('compose');
          },
        ),
        GoRoute(
          path: '/create-event',
          builder: (_, s) {
            eventExtra = s.extra;
            return const Text('event');
          },
        ),
      ],
    );
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        appRouterProvider.overrideWithValue(router),
      ],
    );
    final pending = <String>['search?q=%D1%81%D1%87%D1%91%D1%82'];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'take') return pending.isEmpty ? null : pending.removeAt(0);
      return null;
    });
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      c.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    String location() => router.routerDelegate.currentConfiguration.uri.toString();
    Future<void> platformOpens(String type) async {
      pending.add(type);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('open')),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    // Холодный запуск: экран ждал в очереди платформы.
    await HomeWidgetService.listenOpens((t) => AppShortcuts.openType(c, t));
    await tester.pumpAndSettle();
    expect(location(), '/mail');
    expect(c.read(mailSearchQueryProvider), 'счёт');

    await platformOpens('vip');
    expect(location(), '/mail');
    expect(c.read(mailFilterProvider), MailFilter.vip);

    await platformOpens('feature?f=myday');
    expect(location(), '/my-day');

    await platformOpens('compose?to=anna%40example.com&subject=Hi');
    expect(composeUri?.queryParameters, {'to': 'anna@example.com', 'subject': 'Hi'});
    router.go('/calendar');
    await tester.pumpAndSettle();

    await platformOpens('event?phrase=${Uri.encodeQueryComponent('Обед завтра в 13')}');
    expect((eventExtra as Map)['title'], 'Обед');
    router.go('/calendar');
    await tester.pumpAndSettle();

    await platformOpens('reminder?phrase=${Uri.encodeQueryComponent('Позвонить маме')}');
    expect(Uri.parse(location()).queryParameters, {'new': '1', 'text': 'Позвонить маме'});

    debugDefaultTargetPlatformOverride = null;
  });
}

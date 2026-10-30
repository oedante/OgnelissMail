// Письмо из уведомления (1.8.12, замечание владельца 29.10.2026: «при
// открытии письма из шторки и возврате в приложение пропадают все панели»).
//
//  · Сверху экран вне оболочки (настройки, новое письмо): письмо ленты
//    (/mail/detail) открывало вторую оболочку с тем же ключом страницы —
//    стек ломался. Теперь письмо — отдельным экраном (/email) поверх.
//  · Одно нажатие при открытом окне приходило дважды (колбэк плагина и
//    проверка намерения при возврате) — письмо открывалось двумя экранами.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/navigation/app_router.dart';
import 'package:ogneliss/services/notifications/notification_router.dart';

class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});
  @override
  Widget build(BuildContext context) {
    // Как MainShell: нижняя панель — только на корневых экранах разделов.
    final path = GoRouterState.of(context).uri.path;
    return Scaffold(body: child, bottomNavigationBar: path == '/mail' ? const Text('ПАНЕЛЬ') : null);
  }
}

class _Mail extends StatelessWidget {
  final String id;
  const _Mail(this.id);
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('ПИСЬМО $id')),
        // Как «Назад» экрана письма.
        body: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('НАЗАД')),
      );
}

GoRouter _router() => GoRouter(initialLocation: '/mail', routes: [
      ShellRoute(builder: (_, __, child) => _Shell(child: child), routes: [
        GoRoute(path: '/mail', builder: (_, __) => const Text('ЛЕНТА'), routes: [
          GoRoute(path: 'detail/:emailId', builder: (_, s) => _Mail(s.pathParameters['emailId']!)),
        ]),
      ]),
      GoRoute(path: '/settings', builder: (_, __) => const Scaffold(body: Text('НАСТРОЙКИ'))),
      GoRoute(path: '/email/:emailId', builder: (_, s) => _Mail(s.pathParameters['emailId']!)),
    ]);

Future<GoRouter> _pump(WidgetTester t, {ProviderContainer? container}) async {
  final r = _router();
  final app = MaterialApp.router(routerConfig: r);
  await t.pumpWidget(container == null ? app : UncontrolledProviderScope(container: container, child: app));
  await t.pumpAndSettle();
  return r;
}

void main() {
  testWidgets('в оболочке — письмо ленты, «Назад» возвращает панель', (t) async {
    final r = await _pump(t);
    expect(routerTopInShell(r), isTrue);
    unawaited(pushMailDetail(r, 'INBOX:5', accountId: 'a1'));
    await t.pumpAndSettle();
    expect(find.text('ПИСЬМО INBOX:5'), findsOneWidget);
    expect(find.text('ПАНЕЛЬ'), findsNothing);
    await t.tap(find.text('НАЗАД'));
    await t.pumpAndSettle();
    expect(find.text('ПАНЕЛЬ'), findsOneWidget);
  });

  testWidgets('поверх настроек — отдельным экраном, без второй оболочки', (t) async {
    final r = await _pump(t);
    unawaited(r.push('/settings'));
    await t.pumpAndSettle();
    expect(routerTopInShell(r), isFalse);
    unawaited(pushMailDetail(r, 'INBOX:5', accountId: 'a1'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('ПИСЬМО INBOX:5'), findsOneWidget);
    await t.tap(find.text('НАЗАД'));
    await t.pumpAndSettle();
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('ЛЕНТА'), findsOneWidget);
    expect(find.text('ПАНЕЛЬ'), findsOneWidget);
  });

  testWidgets('уведомление: поверх настроек и повтор того же нажатия', (t) async {
    final router = _router();
    final c = ProviderContainer(overrides: [appRouterProvider.overrideWithValue(router)]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: MaterialApp.router(routerConfig: router)));
    await t.pumpAndSettle();
    NotificationRouter.shellMounted();
    addTearDown(NotificationRouter.shellUnmounted);
    unawaited(router.push('/settings'));
    await t.pumpAndSettle();

    final payload = jsonEncode({'type': 'email', 'emailId': 'INBOX:7'});
    final nr = c.read(notificationRouterProvider);
    nr.open(payload); // колбэк плагина
    nr.open(payload); // то же нажатие — проверка намерения при возврате
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('ПИСЬМО INBOX:7'), findsOneWidget);

    // Один экран письма: «Назад» — сразу к настройкам, затем к ленте с панелью.
    await t.tap(find.text('НАЗАД'));
    await t.pumpAndSettle();
    expect(find.text('ПИСЬМО INBOX:7'), findsNothing);
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('ПАНЕЛЬ'), findsOneWidget);
  });
}

// Письмо из уведомления и со страниц поверх главного экрана (1.8.13).
//
// Страница ленты (/mail/detail/…) живёт внутри главного экрана (ShellRoute).
// Открытая поверх страницы вне его (настройки, «Написать», встреча) она
// создавала второй главный экран с теми же ключами страниц, и после «Назад»
// пропадали панели. Теперь такие переходы идут на отдельную страницу
// /message/… (mailOpenPath, messagePath), а уведомление открывает письмо
// только так.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/core/navigation/app_router.dart' show mailOpenPath, messagePath;
import 'package:ogneliss/services/notifications/notification_router.dart';

class _Shell extends StatelessWidget {
  final Widget child;
  const _Shell({required this.child});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    return Scaffold(
      body: child,
      bottomNavigationBar: path == '/mail' ? const SizedBox(height: 48, child: Text('BAR')) : null,
    );
  }
}

void main() {
  late String fromShell;
  late String fromPage;

  GoRouter router() => GoRouter(initialLocation: '/mail', routes: [
        GoRoute(
          path: '/settings',
          builder: (context, _) {
            fromPage = mailOpenPath(context, 'INBOX:7', accountId: 'a 1');
            return const Text('settings');
          },
        ),
        GoRoute(path: '/message/:emailId', builder: (_, s) => Text('message ${s.pathParameters['emailId']}')),
        ShellRoute(
          builder: (_, __, child) => _Shell(child: child),
          routes: [
            GoRoute(
              path: '/mail',
              builder: (context, _) {
                fromShell = mailOpenPath(context, 'INBOX:7', accountId: 'a 1');
                return const Text('list');
              },
              routes: [GoRoute(path: 'detail/:emailId', builder: (_, s) => Text('detail ${s.pathParameters['emailId']}'))],
            ),
          ],
        ),
      ]);

  testWidgets('адрес письма: в главном экране — страница ленты, поверх него — отдельная страница', (t) async {
    final r = router();
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    expect(fromShell, '/mail/detail/INBOX%3A7?accountId=a+1');
    unawaited(r.push('/settings'));
    await t.pumpAndSettle();
    expect(fromPage, '/message/INBOX%3A7?accountId=a+1');
    expect(fromPage, messagePath('INBOX:7', accountId: 'a 1'));
  });

  testWidgets('письмо поверх настроек: «Назад» возвращает в настройки, затем в ленту с панелью', (t) async {
    final r = router();
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    unawaited(r.push('/settings'));
    await t.pumpAndSettle();
    unawaited(r.push(messagePath('INBOX:7', accountId: 'a')));
    await t.pumpAndSettle();
    expect(find.text('message INBOX:7'), findsOneWidget);
    expect(NotificationRouter.topLocation(r), messagePath('INBOX:7', accountId: 'a'));
    r.pop();
    await t.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
    r.pop();
    await t.pumpAndSettle();
    expect(find.text('list'), findsOneWidget);
    expect(find.text('BAR'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('верхняя страница: открытая поверх — её адрес, иначе — текущий', (t) async {
    final r = router();
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    expect(NotificationRouter.topLocation(r), '/mail');
    unawaited(r.push('/mail/detail/x'));
    await t.pumpAndSettle();
    expect(NotificationRouter.topLocation(r), '/mail/detail/x');
    r.pop();
    await t.pumpAndSettle();
    expect(NotificationRouter.topLocation(r), '/mail');
    expect(find.text('BAR'), findsOneWidget);
  });
}

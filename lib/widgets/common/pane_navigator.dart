// lib/widgets/common/pane_navigator.dart
//
// Своя навигация панели письма рядом с лентой (1.11.0, по образцу Outlook):
// ответ и пересылка открываются прямо в панели, а не поверх всего окна.
// Экран письма закрывается как обычно (Navigator.pop) — закрывается только
// он, панель возвращается к письму. Системное «Назад» (планшет Android)
// сначала закрывает то, что открыто в панели.

import 'package:flutter/material.dart';

class PaneNavigator extends StatefulWidget {
  final Widget child;
  const PaneNavigator({super.key, required this.child});

  /// Экран внутри панели рядом с лентой.
  static bool isInside(BuildContext context) => context.getInheritedWidgetOfExactType<_PaneScope>() != null;

  /// Открыть страницу в панели: мягкое появление, как смена письма.
  static Future<T?> push<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: const Duration(milliseconds: 150),
        reverseTransitionDuration: const Duration(milliseconds: 120),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ));

  @override
  State<PaneNavigator> createState() => _PaneNavigatorState();
}

class _PaneNavigatorState extends State<PaneNavigator> {
  final _key = GlobalKey<NavigatorState>();
  bool _canPop = false;

  @override
  Widget build(BuildContext context) {
    return _PaneScope(
      child: NavigatorPopHandler<Object?>(
        enabled: _canPop,
        onPopWithResult: (_) => _key.currentState?.maybePop(),
        child: Navigator(
          key: _key,
          observers: [_PopWatch(() {
            final can = _key.currentState?.canPop() ?? false;
            if (can != _canPop && mounted) setState(() => _canPop = can);
          })],
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (_, __, ___) => widget.child,
            transitionDuration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

class _PaneScope extends InheritedWidget {
  const _PaneScope({required super.child});
  @override
  bool updateShouldNotify(_PaneScope oldWidget) => false;
}

/// Следит, есть ли в панели что закрывать (для системного «Назад»).
class _PopWatch extends NavigatorObserver {
  _PopWatch(this.onChange);
  final VoidCallback onChange;

  void _later() => WidgetsBinding.instance.addPostFrameCallback((_) => onChange());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _later();
}

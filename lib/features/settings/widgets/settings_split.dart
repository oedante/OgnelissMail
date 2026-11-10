// lib/features/settings/widgets/settings_split.dart
// Настройки в две колонки на компьютере и планшете (2.3.0, решение
// владельца 10.11.2026 «Две колонки»; замечание «настройки растягиваются»).
// С ширины окна [Breakpoints.tablet] слева — список разделов, справа —
// открытый раздел. Уже — как на телефоне: список, раздел поверх.
//
// Каждый экран настроек — по-прежнему своя страница (адрес /settings/…),
// и на узком окне всё как раньше. На широком страница сама рисует список
// слева ([SettingsSplitFrame]); раздел из списка открывается справа без
// «Назад» и без анимации всей страницы ([SettingsPage]): выбор в списке
// снимает открытые разделы и открывает новый. Вглубь из раздела — как
// обычно, с «Назад» в правой колонке.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/common/adaptive_layout.dart' show Breakpoints;
import '../../../widgets/common/wide_frame.dart';
import '../screens/settings_screen.dart';

/// Отметка (extra) страницы, открытой из списка разделов.
const kSettingsSectionRoot = 'settings-section';

/// Две колонки с этой ширины окна.
bool settingsSplitFor(double width) => width >= Breakpoints.tablet;

/// Адрес — экран настроек (такие страницы рисует [SettingsPage]).
bool isSettingsLocation(String location) =>
    location == '/settings' || location.startsWith('/settings/') || location.startsWith('/settings?') ||
    location == '/vip-settings';

String _norm(String location) => Uri.decodeFull(location);

/// Раздел, открытый сейчас из списка: последняя страница с отметкой; если
/// таких нет — страница над главным экраном настроек или первая страница
/// настроек. Без настроек — главный экран ('/settings').
String currentSettingsSection(GoRouter router) {
  final cfg = router.routerDelegate.currentConfiguration;
  final settings = <String>[];
  String? marked;
  for (final m in cfg.matches) {
    if (m is ShellRouteMatch) continue;
    final String loc;
    final Object? extra;
    if (m is ImperativeRouteMatch) {
      loc = m.matches.uri.toString();
      extra = m.matches.extra;
    } else {
      loc = m.matchedLocation;
      extra = null;
    }
    if (!isSettingsLocation(loc)) continue;
    settings.add(loc);
    if (extra == kSettingsSectionRoot) marked = loc;
  }
  if (marked != null) return marked;
  if (settings.isEmpty) return '/settings';
  if (settings.first == '/settings' && settings.length > 1) return settings[1];
  return settings.first;
}

/// Раздел [location] выбран при открытом [selected]. «Общие» — справа на
/// главном экране настроек.
bool settingsSectionSelected(String location, String selected) {
  final a = _norm(location), b = _norm(selected);
  if (a == b) return true;
  return a == '/settings/general' && Uri.parse(b).path == '/settings';
}

/// Открыть раздел из списка настроек: на узком окне — поверх списка; в две
/// колонки ([split]) — справа вместо открытого раздела, без «Назад».
/// [router] и [nav] (корневой) — до перехода: поиск по настройкам
/// закрывается раньше.
void openSettingsSectionWith(GoRouter router, NavigatorState nav, String location, {required bool split}) {
  if (!split) {
    router.push(location, extra: kSettingsSectionRoot);
    return;
  }
  // «Общие» — правая колонка главного экрана настроек.
  if (location == '/settings/general') location = '/settings';
  final selected = currentSettingsSection(router);
  if (settingsSectionSelected(location, selected) && location != '/settings') {
    // Тот же раздел — вернуться к нему из глубины.
    nav.popUntil((r) {
      final s = r.settings;
      return s is! SettingsPage || s.base || _norm(s.location) == _norm(selected);
    });
    return;
  }
  var base = false;
  nav.popUntil((r) {
    final s = r.settings;
    if (s is SettingsPage && s.base) return base = true;
    return s is! SettingsPage;
  });
  if (location == '/settings') {
    if (!base) router.push('/settings');
    return;
  }
  router.push(location, extra: kSettingsSectionRoot);
}

/// Закрыть настройки целиком (кнопка над списком в две колонки).
void closeSettings(BuildContext context) {
  final router = GoRouter.of(context);
  final nav = Navigator.of(context, rootNavigator: true);
  final under = router.routerDelegate.currentConfiguration.matches.any((m) {
    if (m is ShellRouteMatch) return true;
    final loc = m is ImperativeRouteMatch ? m.matches.uri.toString() : m.matchedLocation;
    return !isSettingsLocation(loc);
  });
  if (!under) {
    router.go('/mail');
    return;
  }
  nav.popUntil((r) => r.settings is! SettingsPage);
}

/// Страница маршрута экрана настроек (app_router): на компьютере и
/// планшете — список разделов слева и экран справа; на телефоне — как
/// MaterialPage, которую go_router строит для builder (те же ключ, имя и
/// аргументы).
Page<void> settingsRoutePage(GoRouterState state, Widget child,
        {Widget? splitChild, bool split = true, double maxWidth = 800}) =>
    SettingsPage(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      location: state.uri.toString(),
      base: state.uri.path == '/settings',
      sectionRoot: state.extra == kSettingsSectionRoot,
      child: SettingsSplitFrame(split: split, maxWidth: maxWidth, splitChild: splitChild, child: child),
    );

/// Страница экрана настроек. На узком окне — как обычная страница
/// приложения (MaterialPage). На широком: без анимации всей страницы
/// (список слева не «уезжает» при выборе раздела) и без «Назад» у
/// главного экрана настроек и у раздела, открытого из списка.
class SettingsPage extends Page<void> {
  final Widget child;

  /// Адрес страницы (выбор в списке, переход к разделу из глубины).
  final String location;

  /// Главный экран настроек ('/settings').
  final bool base;

  /// Открыта из списка разделов ([kSettingsSectionRoot]).
  final bool sectionRoot;

  const SettingsPage({
    required this.child,
    required this.location,
    this.base = false,
    this.sectionRoot = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  @override
  Route<void> createRoute(BuildContext context) => _SettingsRoute(this);
}

class _SettingsRoute extends PageRoute<void> with MaterialRouteTransitionMixin<void> {
  _SettingsRoute(SettingsPage page) : super(settings: page);

  SettingsPage get _page => settings as SettingsPage;

  bool get _split {
    // Без зависимости: читается из AppBar во время его сборки.
    final mq = navigator?.context.getInheritedWidgetOfExactType<MediaQuery>();
    return mq != null && settingsSplitFor(mq.data.size.width);
  }

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => true;

  @override
  bool get impliesAppBarDismissal =>
      (_page.base || _page.sectionRoot) && _split ? false : super.impliesAppBarDismissal;

  @override
  Widget buildTransitions(
      BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (settingsSplitFor(MediaQuery.sizeOf(context).width)) return child;
    return super.buildTransitions(context, animation, secondaryAnimation, child);
  }

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}

/// Экран настроек в рамке: на широком окне — список разделов слева и
/// экран справа (не шире [maxWidth], по центру колонки); уже — экран как
/// есть ([WideFrame]). [split] = false — без списка (первая настройка).
/// [splitChild] — что справа в две колонки вместо [child] (главный экран
/// настроек: справа «Общие», а не второй список).
class SettingsSplitFrame extends StatelessWidget {
  final Widget child;
  final Widget? splitChild;
  final bool split;
  final double maxWidth;

  const SettingsSplitFrame({
    super.key,
    required this.child,
    this.splitChild,
    this.split = true,
    this.maxWidth = 800,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    if (!split || !settingsSplitFor(width)) return WideFrame(child: child);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final listWidth = (width * 0.3).clamp(288.0, 340.0);
    final selected = currentSettingsSection(GoRouter.of(context));
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: bg,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: listWidth,
          child: MediaQuery(
            data: _side(mq, listWidth, removeLeft: rtl, removeRight: !rtl),
            // Своя полоса сообщений: снизу у правой колонки, а не у обеих.
            child: ScaffoldMessenger(
              child: SettingsScreen(key: const ValueKey('settings_split_list'), pane: true, selected: selected),
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final w = math.min(box.maxWidth, maxWidth);
            final theme = Theme.of(context);
            return Stack(children: [
              // Шапка экрана — на всю ширину правой части, а не обрывом по
              // краям колонки (цвет шапки постоянный, тема без подкраски).
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: mq.padding.top + (theme.appBarTheme.toolbarHeight ?? kToolbarHeight),
                child: ColoredBox(color: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: const ValueKey('settings_split_detail'),
                  width: w,
                  // Экран справа считает своей ширину колонки.
                  child: MediaQuery(
                    data: _side(mq, w, removeLeft: !rtl, removeRight: rtl),
                    child: splitChild ?? child,
                  ),
                ),
              ),
            ]);
          }),
        ),
      ]),
    );
  }

  static MediaQueryData _side(MediaQueryData mq, double width, {required bool removeLeft, required bool removeRight}) {
    EdgeInsets cut(EdgeInsets e) => e.copyWith(left: removeLeft ? 0 : null, right: removeRight ? 0 : null);
    return mq.copyWith(
      size: Size(width, mq.size.height),
      padding: cut(mq.padding),
      viewPadding: cut(mq.viewPadding),
      viewInsets: mq.viewInsets,
    );
  }
}

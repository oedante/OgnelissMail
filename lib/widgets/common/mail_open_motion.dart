// lib/widgets/common/mail_open_motion.dart
// «Анимация открытия письма» (1.9.x, просьба владельца 31.10.2026: как в
// Telegram, но только по желанию — прежние анимации были медленными).
// Выключена по умолчанию; «Уменьшить движение» и системное «Убрать
// анимацию» выключают и её (AppearanceLook.openAnimation уже это учитывает).
//
//  · Портрет и тема «перелетают» из строки ленты в шапку письма (Hero) —
//    [MailSubjectHero], [mailAvatarShuttle]. Окно браузера с текстом письма
//    не анимируется: оно и так создаётся к концу перехода и показывается,
//    когда готово, а на время перехода закрыто снимком (MailHtmlView).
//  · Письмо из ленты открывается своим переходом ([MailOpenPage]): проявляется
//    и чуть поднимается, лента под ним стоит на месте — портрет и тема
//    летят из неё. На iPhone и Mac — системный сдвиг (со свайпом «назад»).
//  · Закрыть письмо можно свайпом вниз на телефоне ([MailSwipeToClose]):
//    страница идёт за пальцем, под ней видна лента; отпустили дальше порога
//    — письмо закрывается, иначе возвращается на место.
//
// Выключено — ничего этого нет: маршрут ведёт себя как MaterialPage, у строк
// ленты нет Hero, у письма — обёртки для жеста (ноль лишней работы).

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../core/theme/appearance.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/email_model.dart';

/// Ярлыки Hero письма: одинаковые у строки ленты и шапки письма. id письма
/// уникален только внутри ящика — поэтому с ящиком.
abstract final class MailHeroTags {
  static String avatar(String accountId, String emailId) => 'avatar_$accountId/$emailId';
  static String subject(String accountId, String emailId) => 'subject_$accountId/$emailId';
}

/// Шапка письма из строки ленты — экрану письма, пока он читает письмо из
/// базы. Полёт портрета и темы начинается в первом кадре нового экрана, а
/// письмо из базы приходит позже — без шапки из ленты им было некуда
/// лететь. Одна запись: кладёт лента перед открытием (только с анимацией),
/// забирает экран письма.
abstract final class MailOpenHandoff {
  static EmailModel? _email;

  static void put(EmailModel email) => _email = email;

  static EmailModel? take(String accountId, String emailId) {
    final e = _email;
    _email = null;
    return e != null && e.accountId == accountId && e.id == emailId ? e : null;
  }
}

/// Страница письма, открытого из ленты или беседы (go_router pageBuilder).
/// С выключенной анимацией — как MaterialPage. Включена ли — решается при
/// открытии письма: смена настройки при открытом письме подействует со
/// следующего.
class MailOpenPage<T> extends Page<T> {
  const MailOpenPage({required this.child, super.key, super.name, super.arguments, super.restorationId});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      MailOpenRoute<T>(page: this, motion: AppearanceLook.of(context).openAnimation);
}

class MailOpenRoute<T> extends PageRoute<T> with MaterialRouteTransitionMixin<T> {
  MailOpenRoute({required MailOpenPage<T> page, required this.motion}) : super(settings: page);

  /// Анимация открытия письма включена (на момент открытия).
  final bool motion;

  MailOpenPage<T> get _page => settings as MailOpenPage<T>;

  @override
  bool get maintainState => true;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  static bool _cupertino(BuildContext context) {
    final p = Theme.of(context).platform;
    return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
  }

  /// Свой переход: Android, Windows, Linux. На iPhone и Mac — системный, с
  /// главным жестом iOS — свайпом «назад» от левого края.
  bool get _own => motion && navigator != null && !_cupertino(navigator!.context);

  @override
  Duration get transitionDuration => _own ? const Duration(milliseconds: 260) : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _own ? const Duration(milliseconds: 220) : super.reverseTransitionDuration;

  // Лента под письмом стоит на месте (не уезжает влево): портрет и тема
  // летят из своих мест, а при свайпе вниз лента видна такой, как была.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => !motion && super.canTransitionFrom(previousRoute);

  @override
  DelegatedTransitionBuilder? get delegatedTransition => motion ? null : super.delegatedTransition;

  @override
  Widget buildContent(BuildContext context) => motion ? MailSwipeToClose(route: this, child: _page.child) : _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!motion || _cupertino(context)) {
      return super.buildTransitions(context, animation, secondaryAnimation, child);
    }
    // Экран поверх письма (вложение, шторка) — переходом темы, как раньше.
    return super.buildTransitions(
      context,
      kAlwaysCompleteAnimation,
      secondaryAnimation,
      _MailOpenTransition(animation: animation, child: child),
    );
  }

  /// Показать ленту под письмом (на время свайпа вниз): маршрут перестаёт
  /// быть «непрозрачным» для оверлея навигатора.
  void revealBelow(bool reveal) {
    if (overlayEntries.isEmpty || !(animation?.isCompleted ?? false)) return;
    final entry = overlayEntries.first;
    final opaqueNow = !reveal && opaque;
    if (entry.opaque != opaqueNow) entry.opaque = opaqueNow;
  }
}

/// Письмо проявляется и поднимается на 3,5 % высоты; при закрытии —
/// обратно вниз, быстрее.
class _MailOpenTransition extends StatefulWidget {
  const _MailOpenTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_MailOpenTransition> createState() => _MailOpenTransitionState();
}

class _MailOpenTransitionState extends State<_MailOpenTransition> {
  late CurvedAnimation _curve;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _curve = CurvedAnimation(parent: widget.animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    // Непрозрачно уже к 60 % пути — портрет и тема долетают на готовую шапку.
    _fade = CurvedAnimation(
      parent: widget.animation,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(_curve);
  }

  @override
  void didUpdateWidget(_MailOpenTransition old) {
    super.didUpdateWidget(old);
    if (!identical(old.animation, widget.animation)) {
      _curve.dispose();
      (_fade as CurvedAnimation).dispose();
      _bind();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    (_fade as CurvedAnimation).dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}

// ───────────────────────── Hero: портрет и тема ─────────────────────────

/// Полёт портрета: портрет места назначения, вписанный в летящий
/// прямоугольник (буква растёт и уменьшается вместе с кружком, без скачка
/// размера шрифта в конце).
Widget mailAvatarShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final to = (toContext.widget as Hero).child;
  final box = toContext.findRenderObject();
  final size = box is RenderBox && box.hasSize ? box.size : null;
  if (size == null || size.isEmpty) return to;
  return FittedBox(
    child: SizedBox.fromSize(size: size, child: to),
  );
}

/// Тема письма — Hero между строкой ленты и шапкой письма. [enabled] false
/// — просто [child] (выключенная анимация, планшет со списком и письмом
/// рядом). [child] — Text: полёт плавно меняет кегль и перетекает из одной
/// строки ленты в шапку.
class MailSubjectHero extends StatelessWidget {
  const MailSubjectHero({super.key, required this.tag, required this.enabled, required this.child});

  final String tag;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      enabled ? Hero(tag: tag, flightShuttleBuilder: _textShuttle, child: child) : child;

  /// Строка ленты гаснет, шапка письма проявляется; обе масштабируются от
  /// кегля одной к кеглю другой, левым верхним углом к месту полёта.
  static Widget _textShuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final push = direction == HeroFlightDirection.push;
    final listCtx = push ? fromContext : toContext;
    final mailCtx = push ? toContext : fromContext;
    final listText = (listCtx.widget as Hero).child;
    final mailText = (mailCtx.widget as Hero).child;
    Size sizeOf(BuildContext c) {
      final b = c.findRenderObject();
      return b is RenderBox && b.hasSize ? b.size : Size.zero;
    }

    final listSize = sizeOf(listCtx);
    final mailSize = sizeOf(mailCtx);
    final listStyle = DefaultTextStyle.of(listCtx);
    final mailStyle = DefaultTextStyle.of(mailCtx);
    double? font(Widget w, DefaultTextStyle d) => w is Text ? d.style.merge(w.style).fontSize : null;
    final fl = font(listText, listStyle);
    final fm = font(mailText, mailStyle);
    final k = (fl != null && fm != null && fl > 0) ? fm / fl : 1.0;
    const outList = Interval(0.0, 0.55, curve: Curves.easeOut);
    const inMail = Interval(0.25, 0.9, curve: Curves.easeIn);
    Widget part(Widget text, DefaultTextStyle style, Size size) => SizedBox.fromSize(
      size: size,
      child: DefaultTextStyle(
        style: style.style,
        textAlign: style.textAlign,
        softWrap: style.softWrap,
        overflow: style.overflow,
        maxLines: style.maxLines,
        child: text,
      ),
    );
    final listPart = part(listText, listStyle, listSize);
    final mailPart = part(mailText, mailStyle, mailSize);
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // 0 — строка ленты, 1 — шапка письма (и при закрытии тоже).
          final t = animation.value;
          final e = Curves.easeInOut.transform(t);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: Opacity(
                  opacity: 1 - outList.transform(t),
                  child: Transform.scale(
                    scale: lerpDouble(1, k, e)!,
                    alignment: AlignmentDirectional.topStart,
                    child: listPart,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Opacity(
                  opacity: inMail.transform(t),
                  child: Transform.scale(
                    scale: lerpDouble(1 / k, 1, e)!,
                    alignment: AlignmentDirectional.topStart,
                    child: mailPart,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Свайп вниз — закрыть ─────────────────────────

/// Идёт свайп вниз по письму: окно браузера закрыто снимком (или цветом
/// страницы, если снимка ещё нет) — встроенное окно не двигается вместе со
/// страницей (рывки гибридной композиции). Читает MailHtmlView.
class MailDragCover extends InheritedWidget {
  const MailDragCover({super.key, required this.dragging, required super.child});

  final ValueListenable<bool> dragging;

  /// Без подписки на перестроение: слушатель вешает сам MailHtmlView.
  static ValueListenable<bool>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MailDragCover>()?.dragging;

  @override
  bool updateShouldNotify(MailDragCover oldWidget) => !identical(dragging, oldWidget.dragging);
}

/// Свайп вниз закрывает письмо (телефон, Android и iPhone). Жест — только
/// когда письмо прокручено к началу: прокрутка вверх, листание писем вбок,
/// щипок и выделение текста в письме его не начинают.
class MailSwipeToClose extends StatefulWidget {
  const MailSwipeToClose({super.key, required this.route, required this.child});

  final MailOpenRoute<dynamic> route;
  final Widget child;

  /// Доля высоты экрана, после которой отпущенное письмо закрывается.
  static const closeFraction = 0.16;

  /// Скорость броска вниз (dp/с), которая закрывает письмо и раньше порога.
  static const flingVelocity = 700.0;

  @override
  State<MailSwipeToClose> createState() => _MailSwipeToCloseState();
}

class _MailSwipeToCloseState extends State<MailSwipeToClose> with SingleTickerProviderStateMixin {
  /// Сдвиг страницы вниз, dp.
  late final AnimationController _dy = AnimationController.unbounded(vsync: this);
  final ValueNotifier<bool> _dragging = ValueNotifier<bool>(false);

  bool _active = false;
  bool _closing = false;

  // Прокрутка письма: жест начался у самого верха и по вертикали.
  bool _verticalScroll = false;
  bool _scrollStartAtTop = false;

  @override
  void dispose() {
    _dy.dispose();
    _dragging.dispose();
    super.dispose();
  }

  /// Можно ли начать: телефон, письмо не закрывается, клавиатура скрыта.
  bool get _canStart {
    if (_closing || !mounted) return false;
    final mq = MediaQuery.maybeOf(context);
    if (mq == null || mq.size.shortestSide >= 600) return false;
    // Клавиатура (быстрый ответ под письмом) — свайп не закрывает письмо.
    return View.of(context).viewInsets.bottom <= 0;
  }

  void _begin() {
    if (_active) return;
    _active = true;
    _dy.stop();
    _dragging.value = true;
    widget.route.revealBelow(true);
  }

  void _moveBy(double delta) {
    if (!_active) return;
    // Палец снова на странице, пока она возвращалась, — ведёт палец.
    if (_dy.isAnimating) _dy.stop();
    _dy.value = (_dy.value + delta).clamp(0.0, double.infinity);
  }

  void _release(double velocity) {
    if (!_active || _closing) return;
    final h = MediaQuery.sizeOf(context).height;
    final far = _dy.value > h * MailSwipeToClose.closeFraction;
    final fling = velocity > MailSwipeToClose.flingVelocity;
    final back = velocity < -MailSwipeToClose.flingVelocity;
    if ((far || fling) && !back && _dy.value > 0) {
      _close();
    } else {
      _springBack(velocity);
    }
  }

  Future<void> _close() async {
    _closing = true;
    // Переход закрытия начинается с места, где страницу отпустили:
    // портрет и тема летят обратно в строку ленты отсюда же.
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      _closing = false;
      _springBack(0);
    }
  }

  void _springBack(double velocity) {
    const spring = SpringDescription(mass: 1, stiffness: 520, damping: 46);
    final sim = SpringSimulation(
      spring,
      _dy.value,
      0,
      velocity,
      tolerance: const Tolerance(distance: 0.5, velocity: 5),
    );
    _dy.animateWith(sim).whenCompleteOrCancel(() {
      if (!mounted || _closing || _dy.value > 0.5) return;
      _dy.value = 0;
      _active = false;
      _dragging.value = false;
      widget.route.revealBelow(false);
    });
  }

  // ── Прокрутка письма: свайп вниз от самого верха ──
  bool _onScroll(ScrollNotification n) {
    // Прокрутка страницы письма (depth 0) или страницы листания (1);
    // вложенные горизонтальные ленты (вложения) — мимо.
    if (n.depth > 1 || n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollStartNotification) {
      _verticalScroll = n.dragDetails != null;
      _scrollStartAtTop = _verticalScroll && n.metrics.extentBefore <= 0.5;
    } else if (n is OverscrollNotification) {
      if (n.dragDetails != null && n.overscroll < 0 && _scrollStartAtTop && (_active || _canStart)) {
        _begin();
        _moveBy(-n.overscroll);
      }
    } else if (n is ScrollUpdateNotification) {
      // Палец пошёл вверх, пока страница сдвинута: сначала страница
      // возвращается на место.
      final d = n.scrollDelta ?? 0;
      if (_active && n.dragDetails != null && d > 0) _moveBy(-d);
    } else if (n is ScrollEndNotification) {
      if (_active) _release(n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0);
      _verticalScroll = false;
      _scrollStartAtTop = false;
    }
    return false;
  }

  /// Растяжение края (Android) у верха — не показывать, когда свайп
  /// закрывает письмо.
  bool _onIndicator(OverscrollIndicatorNotification n) {
    if (n.leading && _verticalScroll && _scrollStartAtTop && (_active || _canStart)) n.disallowIndicator();
    return false;
  }

  // ── Шапка, верхняя и нижняя панели: прокрутки нет, жест — сразу ──
  void _onDragUpdate(DragUpdateDetails d) {
    if (!_active) {
      if (d.delta.dy <= 0 || !_canStart) return;
      _begin();
    }
    _moveBy(d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) => _release(d.velocity.pixelsPerSecond.dy);

  void _onDragCancel() {
    if (_active && !_closing) _springBack(0);
  }

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    final content = MailDragCover(
      dragging: _dragging,
      // iPhone: у верха письма — без «пружины», иначе она съедала бы жест.
      child: ScrollConfiguration(
        behavior: behavior.copyWith(physics: _NoTopBouncePhysics(parent: behavior.getScrollPhysics(context))),
        child: widget.child,
      ),
    );
    return NotificationListener<OverscrollIndicatorNotification>(
      onNotification: _onIndicator,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: GestureDetector(
          // Только палец и стилус: мышью письмо не «стягивают».
          supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragCancel,
          child: AnimatedBuilder(
            animation: _dy,
            child: content,
            builder: (context, child) {
              final dy = _dy.value < 0 ? 0.0 : _dy.value;
              final h = MediaQuery.sizeOf(context).height;
              final p = h <= 0 ? 0.0 : (dy / (h * 0.5)).clamp(0.0, 1.0);
              final moving = dy > 0;
              // Дерево одно и то же в покое и в движении: состояние письма
              // (окно браузера) не пересоздаётся.
              return Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(
                    child: ColoredBox(color: Colors.black.withValues(alpha: moving ? 0.28 * (1 - p) : 0)),
                  ),
                  Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.scale(
                      scale: 1 - 0.06 * p,
                      alignment: Alignment.topCenter,
                      child: ClipRRect(
                        clipBehavior: moving ? Clip.antiAlias : Clip.none,
                        borderRadius: BorderRadius.circular(Radii.of(Radii.card) * (p * 4).clamp(0.0, 1.0)),
                        child: child,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Без «пружины» у верха вертикальной прокрутки (как ClampingScrollPhysics),
/// у низа и по горизонтали — как у [parent]. Упор в верх даёт
/// OverscrollNotification — по нему и идёт свайп вниз.
class _NoTopBouncePhysics extends ScrollPhysics {
  const _NoTopBouncePhysics({super.parent});

  @override
  _NoTopBouncePhysics applyTo(ScrollPhysics? ancestor) => _NoTopBouncePhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (position.axis == Axis.vertical) {
      // Уже у верха и тянут дальше вниз.
      if (value < position.pixels && position.pixels <= position.minScrollExtent) return value - position.pixels;
      // Доехали до верха в этом шаге.
      if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) {
        return value - position.minScrollExtent;
      }
    }
    return super.applyBoundaryConditions(position, value);
  }
}

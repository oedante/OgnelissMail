// lib/widgets/common/quick_long_press.dart
// Короткое удержание (1.6.46, просьба владельца и тестировщиков 19.10.2026:
// «время срабатывания раза в два сократить»). Карточка письма по удержанию
// открывалась через 500 мс — это kLongPressTimeout Flutter, у InkWell его не
// поменять. Здесь — 250 мс.
//
// Android: если в «Спец. возможностях» выбрана задержка при нажатии длиннее
// обычной (например, когда дрожат руки), берём её — короткое удержание
// иначе срабатывало бы от простого касания.
//
// После удержания палец можно не отпускать: [HoldTracker] получает, куда он
// движется и где отпущен (карточка — провести на кнопку и отпустить).
//
// 1.6.47: «вдавливание» ([pressEffect]) — пока палец держит, содержимое чуть
// уменьшается, как сообщение в Telegram: видно, что удержание засчитывается.
// [HoldPointer] — общий для карточек писем, встреч, контактов и меню кнопки
// «Написать».

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class HoldTiming {
  /// Удержание до карточки.
  static const quick = Duration(milliseconds: 250);

  /// Обычная системная задержка Android — 400–500 мс; длиннее выбирают
  /// в специальных возможностях.
  static const _systemNormalMs = 500;

  static Duration _peek = quick;
  static Duration get peek => _peek;

  /// При запуске: системная задержка Android (ViewConfiguration).
  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final ms = await const MethodChannel('ogneliss/foreground_sync').invokeMethod<int>('longPressTimeout');
      if (ms != null && ms > _systemNormalMs) _peek = Duration(milliseconds: ms);
    } catch (_) {
      // Старая нативная часть или фоновый изолят — остаётся 250 мс.
    }
  }
}

/// Куда сообщать о пальце после удержания (глобальные координаты).
abstract interface class HoldTracker {
  void begin(Offset global);
  void move(Offset global);
  void end();
}

/// Цель «провести и отпустить»: ряд кнопок карточки, пункты меню.
abstract interface class HoldTarget {
  /// Палец над точкой [global] (подсветить пункт под ним).
  void holdHover(Offset global);

  /// Палец отпущен — выполнить подсвеченный пункт, если он есть.
  void holdRelease();
}

/// Палец после удержания (1.6.46): не отпуская, провести на кнопку карточки
/// и отпустить — кнопка срабатывает, как в контекстных меню iOS и Telegram.
/// Отпустить, не сдвинув палец, — карточка остаётся открытой; отпустить
/// мимо кнопок — тоже.
class HoldPointer implements HoldTracker {
  HoldPointer._();
  static final instance = HoldPointer._();

  /// Палец должен сдвинуться: у нижнего края экрана карточка поднимается, и
  /// кнопки могут оказаться прямо под пальцем — отпускание на месте тогда
  /// нажало бы кнопку.
  static const armDistance = 16.0;

  Offset? _start;
  Offset? _last;
  Offset? _pressedAt;
  bool _armed = false;
  HoldTarget? _target;

  /// Где начато последнее удержание — чтобы показать карточку у пальца, когда
  /// строка не знает своего места (встречи календаря).
  Offset? get pressedAt => _pressedAt;

  @override
  void begin(Offset global) {
    _start = global;
    _last = global;
    _pressedAt = global;
    _armed = false;
  }

  @override
  void move(Offset global) {
    final start = _start;
    if (start == null) return;
    _last = global;
    if (!_armed) {
      if ((global - start).distance < armDistance) return;
      _armed = true;
    }
    _target?.holdHover(global);
  }

  @override
  void end() {
    final armed = _armed;
    _start = null;
    _last = null;
    _armed = false;
    if (armed) _target?.holdRelease();
  }

  /// Карточка или меню появились (initState).
  void attach(HoldTarget target) {
    _target = target;
    // Палец уже двигался, пока карточка появлялась: подсветить пункт под
    // ним после первой раскладки (до неё размеров пунктов нет).
    final at = _last;
    if (_armed && at != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_armed && identical(_target, target)) target.holdHover(_last ?? at);
      });
    }
  }

  void detach(HoldTarget target) {
    if (identical(_target, target)) _target = null;
  }
}

/// Удержание [HoldTiming.peek] вместо 500 мс. Касание, свайп и прокрутка
/// остаются у дочерних виджетов: удержание выигрывает, только если палец
/// постоял на месте.
class QuickLongPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLongPress;
  final HoldTracker? tracker;
  final HitTestBehavior? behavior;

  /// «Вдавливание» во время удержания (1.6.47).
  final bool pressEffect;

  const QuickLongPress({
    super.key,
    required this.child,
    required this.onLongPress,
    this.tracker,
    this.behavior,
    this.pressEffect = false,
  });

  @override
  State<QuickLongPress> createState() => _QuickLongPressState();
}

class _QuickLongPressState extends State<QuickLongPress> with SingleTickerProviderStateMixin {
  /// Короткое касание и начало прокрутки не «вдавливают»: эффект — только
  /// если палец постоял хоть немного.
  static const _pressDelay = Duration(milliseconds: 70);
  static const _pressScale = 0.975;

  AnimationController? _press;
  Timer? _pressTimer;

  AnimationController _controller() =>
      _press ??= AnimationController(vsync: this, duration: HoldTiming.peek - _pressDelay);

  @override
  void dispose() {
    _pressTimer?.cancel();
    _press?.dispose();
    super.dispose();
  }

  void _down() {
    if (!widget.pressEffect || MediaQuery.maybeDisableAnimationsOf(context) == true) return;
    _pressTimer?.cancel();
    _pressTimer = Timer(_pressDelay, () {
      if (mounted) unawaited(_controller().forward(from: 0).orCancel.catchError((Object _) {}));
    });
  }

  /// Вернуть размер. 1.7.2 (замечание 20.10.2026: «карточки после удержания
  /// не всегда возвращаются к своему размеру»): раньше при значении 0 выход
  /// был сразу — а «вдавливание» могло только что начаться (первый кадр, ещё
  /// 0), и его никто не останавливал: прокрутка отменяла удержание, анимация
  /// доходила до конца, и строка оставалась на несколько пикселей меньше.
  void _release() {
    _pressTimer?.cancel();
    final c = _press;
    if (c == null || (c.value == 0 && !c.isAnimating)) return;
    unawaited(c.animateBack(0, duration: const Duration(milliseconds: 140), curve: Curves.easeOut)
        .orCancel
        .catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final cb = widget.onLongPress;
    if (cb == null) return widget.child;
    final t = widget.tracker;
    Widget child = widget.child;
    if (widget.pressEffect) {
      final c = _controller();
      child = AnimatedBuilder(
        animation: c,
        child: child,
        builder: (_, ch) => Transform.scale(
          scale: 1 - (1 - _pressScale) * Curves.easeOut.transform(c.value),
          child: ch,
        ),
      );
    }
    // Палец поднят или касание отменено (прокрутка забрала жест) — размер
    // возвращается в любом случае, даже если распознаватель удержания об этом
    // не сообщил.
    if (widget.pressEffect) {
      child = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: child,
      );
    }
    return RawGestureDetector(
      behavior: widget.behavior,
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: HoldTiming.peek, debugOwner: this),
          (r) {
            // Порядок у распознавателя: onLongPressStart, затем onLongPress —
            // точка начала известна до того, как откроется карточка.
            r.onLongPressDown = (_) => _down();
            r.onLongPressCancel = _release;
            r.onLongPress = () {
              _release();
              cb();
            };
            r.onLongPressStart = t == null ? null : (d) => t.begin(d.globalPosition);
            r.onLongPressMoveUpdate = t == null ? null : (d) => t.move(d.globalPosition);
            r.onLongPressEnd = (_) {
              _release();
              t?.end();
            };
          },
        ),
      },
      child: child,
    );
  }
}

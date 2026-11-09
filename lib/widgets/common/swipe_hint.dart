// lib/widgets/common/swipe_hint.dart
//
// Подсказка о свайпах — один раз (2.2.0, решение владельца 09.11.2026):
// первая строка ленты сама слегка отъезжает в одну сторону, потом в другую —
// видно значок и подпись действия под ней, и что строку можно тянуть.
// Потом не повторяется (настройка 'swipe_hint_v1').

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SwipeHint extends StatefulWidget {
  static const prefKey = 'swipe_hint_v1';

  /// Подсказку уже показывает строка этого запуска.
  static bool _claimed = false;

  /// В тестах подсказка выключена (у неё таймеры); тест подсказки включает.
  @visibleForTesting
  static bool? debugEnabled;

  @visibleForTesting
  static void debugReset() => _claimed = false;

  final SharedPreferences prefs;

  /// Есть действие при свайпе вправо (панель у начала строки) / влево.
  final bool start;
  final bool end;
  final Widget child;

  const SwipeHint({super.key, required this.prefs, required this.start, required this.end, required this.child});

  @override
  State<SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<SwipeHint> with SingleTickerProviderStateMixin {
  AnimationController? _a;
  Timer? _timer;

  static bool get _enabled =>
      SwipeHint.debugEnabled ?? !(kIsWeb ? false : Platform.environment.containsKey('FLUTTER_TEST'));

  @override
  void initState() {
    super.initState();
    if (!_enabled || SwipeHint._claimed || (!widget.start && !widget.end)) return;
    if (widget.prefs.getBool(SwipeHint.prefKey) == true) return;
    SwipeHint._claimed = true;
    _timer = Timer(const Duration(milliseconds: 1200), () => unawaited(_run()));
  }

  Future<void> _run() async {
    if (!mounted) return;
    final c = Slidable.of(context);
    if (c == null) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    await widget.prefs.setBool(SwipeHint.prefKey, true);
    final a = _a = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      reverseDuration: const Duration(milliseconds: 350),
    );
    var sign = 1.0;
    void move() => c.ratio = sign * 0.34 * Curves.easeOutCubic.transform(a.value);
    a.addListener(move);
    Future<void> side(double s) async {
      sign = s;
      await a.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      await a.reverse();
    }

    try {
      if (widget.start) await side(1);
      if (!mounted) return;
      if (widget.end) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) await side(-1);
      }
    } on TickerCanceled {
      // Строку убрали с экрана — подсказка просто прерывается.
    } finally {
      if (mounted) c.ratio = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _a?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

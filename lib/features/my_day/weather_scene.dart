// lib/features/my_day/weather_scene.dart
// Рисунок погоды фоном карточки «Сейчас» в «Моём дне» (2.7.5, просьба
// владельца 27.11.2026: «статический рисунок соответствующей погоды как
// фон — солнце, облака, туман, дождевые капли, снежинки»).
//
// Рисуется кодом (без картинок и шрифтов), бледно, справа — за значком
// погоды; текст карточки остаётся читаемым. Город — тот, что пролистан в
// карточке («Сейчас», города в других поясах).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/theme/tokens.dart';
import '../../services/weather/weather_service.dart';
import 'weather_view.dart' show weatherAllowed;

/// Город, пролистанный в карточке «Сейчас» (ключ; null — свой, первый).
final nowCardPlaceProvider = StateProvider<String?>((ref) => null);

/// Рисунок погоды пролистанного города; погоды нет — ничего.
class MyDayWeatherBackdrop extends ConsumerWidget {
  const MyDayWeatherBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(weatherSettingsProvider);
    if (!s.active || !weatherAllowed(ref)) return const SizedBox.shrink();
    final key = ref.watch(nowCardPlaceProvider) ?? s.place?.key;
    if (key == null || s.byKey(key) == null) return const SizedBox.shrink();
    final f = ref.watch(weatherForProvider(key)).value;
    final kind = f?.now.kind;
    if (f == null || kind == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        key: ValueKey('weather_scene_${kind.name}${f.now.night ? '_night' : ''}'),
        painter: WeatherScenePainter(kind, night: f.now.night, dark: Theme.of(context).brightness == Brightness.dark),
      ),
    );
  }
}

/// Сцена погоды: солнце или луна, облака, туман, капли, снежинки, молния.
class WeatherScenePainter extends CustomPainter {
  final WeatherKind kind;
  final bool night;
  final bool dark;
  const WeatherScenePainter(this.kind, {this.night = false, this.dark = false});

  // Бледность: на тёмной теме чуть заметнее.
  double get _a => dark ? 0.20 : 0.16;

  Color get _sun => const Color(0xFFF5B400).withValues(alpha: _a + 0.08);
  Color get _moon => (dark ? const Color(0xFFE8E4D0) : const Color(0xFF8A8F99)).withValues(alpha: _a + 0.04);
  Color get _cloud => (dark ? const Color(0xFFB8C0CC) : const Color(0xFF7D8694)).withValues(alpha: _a);
  Color get _rain => const Color(0xFF2F80ED).withValues(alpha: _a + 0.10);
  Color get _snow => (dark ? Colors.white : const Color(0xFF5B8DB8)).withValues(alpha: _a + 0.10);
  Color get _bolt => const Color(0xFFF2C94C).withValues(alpha: _a + 0.14);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Сцена — в правом верхнем углу карточки, за значком погоды; размер —
    // от высоты карточки, но не больше значка с запасом.
    final r = (size.height * 0.16).clamp(18.0, 34.0);
    final cx = size.width - r * 2.4;
    final cy = r * 2.3;
    switch (kind) {
      case WeatherKind.clear:
        night ? _drawMoon(canvas, Offset(cx, cy), r, stars: true) : _drawSun(canvas, Offset(cx, cy), r);
      case WeatherKind.fair:
        night ? _drawMoon(canvas, Offset(cx, cy), r, stars: true) : _drawSun(canvas, Offset(cx, cy), r);
        _drawCloud(canvas, Offset(cx - r * 1.4, cy + r * 1.3), r * 0.9);
      case WeatherKind.partlyCloudy:
        night ? _drawMoon(canvas, Offset(cx + r * 0.5, cy - r * 0.2), r * 0.9) : _drawSun(canvas, Offset(cx + r * 0.5, cy - r * 0.2), r * 0.9);
        _drawCloud(canvas, Offset(cx - r * 0.3, cy + r * 0.7), r * 1.2);
      case WeatherKind.cloudy:
        _drawCloud(canvas, Offset(cx + r * 0.6, cy - r * 0.1), r * 1.0);
        _drawCloud(canvas, Offset(cx - r * 0.7, cy + r * 0.8), r * 1.3);
      case WeatherKind.fog:
        _drawFog(canvas, size);
      case WeatherKind.lightRain:
        _drawCloud(canvas, Offset(cx, cy), r * 1.2);
        _drawDrops(canvas, size, Offset(cx, cy + r * 1.2), r, 6);
      case WeatherKind.rain:
        _drawCloud(canvas, Offset(cx, cy), r * 1.3);
        _drawDrops(canvas, size, Offset(cx, cy + r * 1.2), r, 11);
      case WeatherKind.heavyRain:
        _drawCloud(canvas, Offset(cx + r * 0.6, cy - r * 0.2), r * 1.0);
        _drawCloud(canvas, Offset(cx - r * 0.5, cy + r * 0.3), r * 1.3);
        _drawDrops(canvas, size, Offset(cx, cy + r * 1.4), r * 1.2, 18);
      case WeatherKind.sleet:
        _drawCloud(canvas, Offset(cx, cy), r * 1.3);
        _drawDrops(canvas, size, Offset(cx - r * 0.4, cy + r * 1.3), r * 0.8, 5);
        _drawFlakes(canvas, size, Offset(cx + r * 0.5, cy + r * 1.3), r * 0.8, 5);
      case WeatherKind.snow:
        _drawCloud(canvas, Offset(cx, cy - r * 0.2), r * 1.2);
        _drawFlakes(canvas, size, Offset(cx, cy + r * 1.2), r * 1.2, 12);
      case WeatherKind.thunder:
        _drawCloud(canvas, Offset(cx, cy), r * 1.35);
        _drawBolt(canvas, Offset(cx + r * 0.1, cy + r * 0.9), r);
        _drawDrops(canvas, size, Offset(cx - r * 0.8, cy + r * 1.3), r * 0.6, 5);
    }
  }

  void _drawSun(Canvas c, Offset o, double r) {
    final p = Paint()..color = _sun;
    c.drawCircle(o, r, p);
    final ray = Paint()
      ..color = _sun
      ..strokeWidth = math.max(2, r * 0.12)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(o + d * (r * 1.35), o + d * (r * 1.75), ray);
    }
  }

  void _drawMoon(Canvas c, Offset o, double r, {bool stars = false}) {
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: o, radius: r)),
      Path()..addOval(Rect.fromCircle(center: o + Offset(r * 0.55, -r * 0.35), radius: r * 0.9)),
    );
    c.drawPath(moon, Paint()..color = _moon);
    if (!stars) return;
    final sp = Paint()..color = _moon;
    for (final (dx, dy, s) in const [(-2.2, -0.4, 0.10), (-1.6, 0.9, 0.07), (1.4, 1.2, 0.08), (-2.8, 0.6, 0.06)]) {
      c.drawCircle(o + Offset(r * dx, r * dy), r * s, sp);
    }
  }

  /// Облако из кругов на плоском основании; [o] — середина основания.
  void _drawCloud(Canvas c, Offset o, double r) {
    final p = Paint()..color = _cloud;
    final path = Path()
      ..addOval(Rect.fromCircle(center: o + Offset(-r * 0.9, -r * 0.35), radius: r * 0.55))
      ..addOval(Rect.fromCircle(center: o + Offset(-r * 0.2, -r * 0.75), radius: r * 0.8))
      ..addOval(Rect.fromCircle(center: o + Offset(r * 0.7, -r * 0.45), radius: r * 0.62))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(o.dx - r * 1.45, o.dy - r * 0.5, o.dx + r * 1.32, o.dy + r * 0.05), Radius.circular(r * 0.3)));
    c.drawPath(path, p);
  }

  void _drawDrops(Canvas c, Size size, Offset o, double r, int n) {
    final p = Paint()
      ..color = _rain
      ..strokeWidth = math.max(1.6, r * 0.08)
      ..strokeCap = StrokeCap.round;
    final rnd = math.Random(7 + n); // всегда тот же узор
    for (var i = 0; i < n; i++) {
      final x = o.dx - r * 1.6 + rnd.nextDouble() * r * 3.2;
      final y = o.dy + rnd.nextDouble() * r * 1.6;
      if (y > size.height - 2) continue;
      c.drawLine(Offset(x, y), Offset(x - r * 0.12, y + r * 0.34), p);
    }
  }

  void _drawFlakes(Canvas c, Size size, Offset o, double r, int n) {
    final p = Paint()
      ..color = _snow
      ..strokeWidth = math.max(1.2, r * 0.05)
      ..strokeCap = StrokeCap.round;
    final rnd = math.Random(11 + n);
    for (var i = 0; i < n; i++) {
      final at = Offset(o.dx - r * 1.7 + rnd.nextDouble() * r * 3.4, o.dy + rnd.nextDouble() * r * 1.7);
      if (at.dy > size.height - 2) continue;
      final s = r * (0.12 + rnd.nextDouble() * 0.1);
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a)) * s;
        c.drawLine(at - d, at + d, p);
      }
    }
  }

  void _drawFog(Canvas c, Size size) {
    final p = Paint()
      ..color = _cloud
      ..strokeWidth = math.max(3, size.height * 0.035)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final left = size.width * 0.58;
    for (var i = 0; i < 5; i++) {
      final y = 18.0 + i * 16.0;
      final shift = (i.isEven ? 0.0 : size.width * 0.05);
      final path = Path()..moveTo(left + shift, y);
      final w = size.width - left - Space.s - shift;
      for (var k = 1; k <= 4; k++) {
        path.quadraticBezierTo(left + shift + w * (k - 0.5) / 4, y + (k.isEven ? 4 : -4), left + shift + w * k / 4, y);
      }
      c.drawPath(path, p);
    }
  }

  void _drawBolt(Canvas c, Offset o, double r) {
    final path = Path()
      ..moveTo(o.dx, o.dy)
      ..lineTo(o.dx - r * 0.35, o.dy + r * 0.65)
      ..lineTo(o.dx - r * 0.05, o.dy + r * 0.62)
      ..lineTo(o.dx - r * 0.3, o.dy + r * 1.25)
      ..lineTo(o.dx + r * 0.3, o.dy + r * 0.45)
      ..lineTo(o.dx + r * 0.02, o.dy + r * 0.48)
      ..lineTo(o.dx + r * 0.22, o.dy)
      ..close();
    c.drawPath(path, Paint()..color = _bolt);
  }

  @override
  bool shouldRepaint(WeatherScenePainter old) => old.kind != kind || old.night != night || old.dark != dark;
}

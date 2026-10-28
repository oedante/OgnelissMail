// lib/core/platform/orientation_policy.dart
// Поворот экрана: телефон (короткая сторона экрана < 600 dp) — только
// портрет, если не включено «Поворот экрана» (Настройки → Общие); планшет,
// раскрытый складной телефон — любая ориентация.
//
// Раньше это решалось один раз при запуске. Складной телефон, открытый на
// внешнем экране, после раскрытия оставался «телефоном» с запретом поворота.
// Теперь правило пересчитывается при каждом изменении экрана (раскрыли,
// сложили, сменили дисплей) — см. MainShell.didChangeMetrics.
//
// Размер берётся у ДИСПЛЕЯ, а не у окна: в разделённом экране окно узкое,
// но это не повод запрещать поворот планшета.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class OrientationPolicy {
  OrientationPolicy._();

  static bool? _phoneLocked;

  /// Короткая сторона экрана в dp (0 — неизвестно).
  static double shortestSideDp() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 0;
    final v = views.first;
    try {
      final d = v.display;
      if (d.size.shortestSide > 0 && d.devicePixelRatio > 0) {
        return d.size.shortestSide / d.devicePixelRatio;
      }
    } catch (_) {}
    return v.physicalSize.shortestSide / v.devicePixelRatio;
  }

  /// Применить правило; повторный вызов без изменений ничего не делает
  /// ([force] — после смены настройки «Поворот экрана»).
  static Future<void> apply({bool force = false}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final shortest = shortestSideDp();
    if (shortest <= 0) return;
    var allow = false;
    try {
      allow = (await SharedPreferences.getInstance()).getBool('s_allow_rotation') ?? false;
    } catch (_) {}
    final lock = shortest < 600 && !allow;
    if (!force && _phoneLocked == lock) return;
    _phoneLocked = lock;
    await SystemChrome.setPreferredOrientations(lock
        ? const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
        : const <DeviceOrientation>[]); // пустой список — любые ориентации
  }
}

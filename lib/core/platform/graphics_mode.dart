// lib/core/platform/graphics_mode.dart
// Движок рисования на Android: Impeller (по умолчанию) или Skia
// (совместимость). Нативная часть и причины — GraphicsMode.kt.
//
// Коротко (диагностика владельца 08.11.2026, HUAWEI DEL-LX9): Impeller на
// OpenGL ES падал при передаче картинки в видеопамять — чёрный экран до
// перезагрузки. После такого падения приложение само переходит на Skia;
// здесь — чтение состояния, ручной выбор и перезапуск для настроек,
// журнала и диагностики.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// Состояние движка рисования (только Android).
class GraphicsState {
  /// Выбор в настройках: auto | skia | impeller.
  final String mode;

  /// Чем рисует этот процесс: skia | impeller.
  final String active;

  /// Чем будет рисовать после перезапуска.
  final String next;

  /// Путь Impeller из журнала движка: «OpenGLES», «Vulkan» (если известен).
  final String? backend;

  /// «Автоматически» перешло на Skia после падения Impeller.
  final bool autoSkia;
  final DateTime? autoAt;
  final String? autoReason;

  /// Память телефона и приложения (МБ): totalMb, availMb, thresholdMb, low,
  /// lowRamDevice, appLimitMb, appPssMb.
  final Map<String, Object?> memory;

  const GraphicsState({
    required this.mode,
    required this.active,
    required this.next,
    this.backend,
    this.autoSkia = false,
    this.autoAt,
    this.autoReason,
    this.memory = const {},
  });

  factory GraphicsState.fromMap(Map<Object?, Object?> m) {
    final at = (m['autoAt'] as num?)?.toInt() ?? 0;
    final mem = m['memory'];
    return GraphicsState(
      mode: m['mode'] as String? ?? 'auto',
      active: m['active'] as String? ?? 'impeller',
      next: m['next'] as String? ?? 'impeller',
      backend: m['backend'] as String?,
      autoSkia: m['autoSkia'] == true,
      autoAt: at > 0 ? DateTime.fromMillisecondsSinceEpoch(at) : null,
      autoReason: m['autoReason'] as String?,
      memory: mem is Map ? {for (final e in mem.entries) '${e.key}': e.value} : const {},
    );
  }

  /// Нужен перезапуск, чтобы выбор вступил в силу.
  bool get restartNeeded => next != active;

  /// Для журнала и диагностики (по-русски, как весь журнал).
  String get summary {
    final b = StringBuffer(active == 'skia' ? 'Skia (совместимость)' : 'Impeller');
    if (active != 'skia' && backend != null) b.write(' ($backend)');
    b.write(switch (mode) {
      'skia' => ', выбрано вручную',
      'impeller' => ', Impeller выбран вручную',
      _ => autoSkia ? ', автоматически после сбоя Impeller' : ', автоматически',
    });
    if (autoSkia && autoAt != null) b.write(' ${autoAt!.toIso8601String().substring(0, 16)}');
    if (restartNeeded) b.write('; после перезапуска — ${next == 'skia' ? 'Skia' : 'Impeller'}');
    return b.toString();
  }

  /// «Память: всего 3700 МБ, свободно 900 МБ (порог 220), мало: нет; приложению до 256 МБ, занято 180 МБ».
  String get memorySummary {
    if (memory.isEmpty) return '';
    String n(String k) => '${(memory[k] as num?)?.toInt() ?? '?'}';
    return 'всего ${n('totalMb')} МБ, свободно ${n('availMb')} МБ (порог ${n('thresholdMb')}), '
        'мало: ${memory['low'] == true ? 'да' : 'нет'}'
        '${memory['lowRamDevice'] == true ? ', слабый телефон (low RAM)' : ''}; '
        'приложению до ${n('appLimitMb')} МБ, занято ${n('appPssMb')} МБ';
  }
}

class GraphicsMode {
  static const _ch = MethodChannel('ogneliss/graphics');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// null — не Android или канал не ответил.
  static Future<GraphicsState?> state() async {
    if (!supported) return null;
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('state');
      return m == null ? null : GraphicsState.fromMap(m);
    } catch (e) {
      AppLogger.debug('Графика: $e');
      return null;
    }
  }

  static Future<GraphicsState?> setMode(String mode) async {
    if (!supported) return null;
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('setMode', mode);
      AppLogger.info('Графика: выбрано «$mode»');
      return m == null ? null : GraphicsState.fromMap(m);
    } catch (e) {
      AppLogger.warning('Графика: не сохранено: $e');
      return null;
    }
  }

  /// Перезапустить приложение (новый процесс — новый движок рисования).
  static Future<void> restart() async {
    if (!supported) return;
    AppLogger.info('Графика: перезапуск приложения');
    AppLogger.flushNow();
    try {
      await _ch.invokeMethod<void>('restart');
    } catch (e) {
      AppLogger.warning('Перезапуск: $e');
    }
  }

  /// При запуске — в журнал: чем рисуем и сколько памяти.
  static Future<void> logStartup() async {
    final s = await state();
    if (s == null) return;
    AppLogger.info('Графика: ${s.summary}');
    if (s.autoSkia && s.active == 'skia' && s.autoReason != null) {
      AppLogger.info('Графика: причина перехода на Skia — ${s.autoReason}');
    }
    final mem = s.memorySummary;
    if (mem.isNotEmpty) AppLogger.info('Память: $mem');
  }
}

// lib/core/logging/open_trace.dart
// Замер открытия письма (1.5.9): от нажатия на строку ленты до показа
// текста — одной строкой в журнал диагностики на каждое открытие, без
// отладчика и profile-сборки. Пример строки:
//   «Открытие письма, мс от нажатия: окно 212 · создано 268 · кадр 331 ·
//    загрузка 342 · текст 371»
// Отметки, пришедшие без нажатия (письмо из уведомления, беседы), не пишутся.

import 'app_logger.dart';

class OpenTrace {
  OpenTrace._();

  static final Stopwatch _sw = Stopwatch();
  static final List<String> _marks = [];

  /// Нажатие на письмо в ленте.
  static void start() {
    _marks.clear();
    _sw
      ..reset()
      ..start();
  }

  /// Промежуточная отметка (только во время замера).
  static void mark(String what) {
    if (_sw.isRunning) _marks.add('$what ${_sw.elapsedMilliseconds}');
  }

  /// Текст письма показан — итог в журнал.
  static void done() {
    if (!_sw.isRunning) return;
    _sw.stop();
    _marks.add('текст ${_sw.elapsedMilliseconds}');
    AppLogger.info('Открытие письма, мс от нажатия: ${_marks.join(' · ')}');
    _marks.clear();
  }

  /// Замер больше не нужен (письмо без WebView, ушли с экрана).
  static void cancel() {
    _sw.stop();
    _marks.clear();
  }
}

// lib/services/mail/engine/engine_log.dart
// Журнал движка (packages/mail_engine) — в журнал приложения сразу, по мере
// работы: раньше он копился в памяти и попадал в файл только при неудачном
// подключении — ошибки синхронизации, 403 от шлюза, повторный Provision и
// строка «Политики: …» при успешном входе терялись.
// В обычном режиме — шаги и коды ответов; в подробном (AppLogger.detailed)
// ещё заголовки, фрагменты тел и деревья WBXML.

import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/logging/app_logger.dart';

me.DebugLog newEngineLog() {
  return me.DebugLog(
    // Проверяется на каждой записи: подробный режим выключается сам через
    // сутки, а движок подключённого ящика живёт всю сессию.
    isVerbose: () => AppLogger.detailed,
    echo: false,
    sink: (e) {
      final line = '[${e.transport}] ${e.message}';
      switch (e.level) {
        case me.LogLevel.debug:
          if (AppLogger.detailed) AppLogger.debug(line);
        case me.LogLevel.info:
          AppLogger.info(line);
        case me.LogLevel.warn:
          AppLogger.warning(line);
        case me.LogLevel.error:
          AppLogger.error(line);
      }
    },
  );
}

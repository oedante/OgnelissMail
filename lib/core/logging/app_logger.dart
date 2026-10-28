// lib/core/logging/app_logger.dart
// Логирование: ОДИН файл + console + уровни. Максимальный размер 15 МБ; при
// достижении порога отсекается старейшая 1/3 (остаются новейшие 2/3). Ошибки
// пишутся в файл вместе со стектрейсом.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class AppLogger {
  AppLogger._();

  static File? _logFile;
  static bool _initialized = false;

  /// Максимальный размер лог-файла (15 МБ). При достижении файл усекается:
  /// удаляется старейшая треть, остаются новейшие ~2/3 (~10 МБ). Файл один.
  static const int maxBytes = 15 * 1024 * 1024;

  /// Приблизительный счётчик байтов текущего файла (чтобы не делать stat на
  /// каждую запись). Инициализируется реальным размером при старте.
  static int _currentBytes = 0;

  /// Идёт асинхронное усечение файла. Пока true — новые строки не пишем в файл
  /// (чтобы не потерять их при перезаписи), а копим в буфере ниже.
  static bool _trimming = false;

  /// Буфер строк, накопленных во время усечения; дописывается после него.
  static final List<String> _pending = [];

  /// Ограничение буфера на случай, если усечение затянется (защита от роста
  /// памяти): при переполнении старейшие буферизованные строки отбрасываются.
  static const int _maxPending = 20000;

  /// Подробный журнал: протокольные записи движка (заголовки, коды, краткие
  /// фрагменты ответов, деревья WBXML). Включается на 24 часа кнопкой в
  /// «Журнале» — в нём могут оказаться фрагменты писем, поэтому навсегда
  /// не остаётся.
  static DateTime? _detailedUntil;
  static const _kDetailedUntil = 'log_detailed_until';

  static bool get detailed {
    final u = _detailedUntil;
    return u != null && DateTime.now().isBefore(u);
  }

  static DateTime? get detailedUntil => detailed ? _detailedUntil : null;

  /// Прочитать настройку из SharedPreferences (main.dart после их загрузки).
  static void loadSettings(int? untilMs) {
    _detailedUntil = untilMs == null ? null : DateTime.fromMillisecondsSinceEpoch(untilMs);
  }

  /// Ключ настройки в SharedPreferences (для экрана «Журнал»).
  static String get detailedPrefsKey => _kDetailedUntil;

  /// Включить подробный журнал на [duration] или выключить (null).
  /// Возвращает значение для сохранения в SharedPreferences.
  static int? setDetailed(Duration? duration) {
    _detailedUntil = duration == null ? null : DateTime.now().add(duration);
    info(duration == null
        ? 'Подробный журнал выключен'
        : 'Подробный журнал включён до ${DateFormat('dd.MM HH:mm').format(_detailedUntil!)}');
    return _detailedUntil?.millisecondsSinceEpoch;
  }

  static Future<void> init() async {
    if (_initialized) return;
    try {
      if (!kIsWeb) {
        // Каталог данных приложения, а не «Документы»: на Windows «Документы»
        // часто синхронизируются в OneDrive, и журнал с адресами коллег
        // уходил в облако. Старый журнал из «Документов» удаляем.
        final dir = await getApplicationSupportDirectory();
        final sep = Platform.pathSeparator;
        final logDir = Directory('${dir.path}${sep}logs');
        if (!await logDir.exists()) await logDir.create(recursive: true);
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            final docs = await getApplicationDocumentsDirectory();
            final old = File('${docs.path}/logs/ogneliss.log');
            if (await old.exists()) await old.delete();
          } catch (_) {}
        }
        // Единый файл (без даты в имени).
        _logFile = File('${logDir.path}${sep}ogneliss.log');
        _currentBytes = await _logFile!.exists() ? (await _logFile!.length()) : 0;
      }
      _initialized = true;
    } catch (_) {}
  }

  /// Строки ждут записи пачкой: раньше каждая строка писалась в файл
  /// синхронно отдельной операцией — в подробном журнале это тысячи
  /// обращений к диску в час на главном потоке (заряд и подёргивания).
  /// Буфер пишется раз в 2 с, при 64 КБ, сразу на ошибке и при сворачивании
  /// приложения / конце фоновой задачи ([flushNow]).
  static final StringBuffer _buf = StringBuffer();
  static int _bufBytes = 0;
  static Timer? _flushTimer;
  static const int _bufMax = 64 * 1024;

  /// Записать накопленные строки сейчас (сворачивание, конец фоновой задачи).
  static void flushNow() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_bufBytes == 0) return;
    final data = _buf.toString();
    final bytes = _bufBytes;
    _buf.clear();
    _bufBytes = 0;
    final f = _logFile;
    if (f == null) return;
    if (_trimming) {
      _pending.add(data);
      return;
    }
    try {
      f.writeAsStringSync(data, mode: FileMode.append, flush: false);
      _currentBytes += bytes;
    } catch (_) {}
  }

  /// Метка изолята в каждой строке: «фон» — фоновая задача (WorkManager,
  /// BGTask iOS, кнопка уведомления при выгруженном приложении). Пишут в
  /// один файл оба изолята — по метке видно, чья строка.
  static String _tag = '';
  static void setTag(String tag) => _tag = tag.isEmpty ? '' : '[$tag] ';

  /// Строки пишет фоновый изолят (метка задана).
  static bool get isBackground => _tag.isNotEmpty;

  static void debug(String message) => _log('DEBUG', message);
  static void info(String message) => _log('INFO', message);
  static void warning(String message) => _log('WARN', message);

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _log('ERROR', '$message${error != null ? ': $error' : ''}');
    if (stackTrace != null) {
      // Стектрейс пишем в ФАЙЛ (не только в консоль) — иначе в релизе причина
      // ошибки теряется. Ограничиваем длину, чтобы не раздувать лог.
      var st = stackTrace.toString();
      if (st.length > 4000) st = '${st.substring(0, 4000)}\n…(стектрейс усечён)';
      _log('ERROR', 'stacktrace:\n$st');
      if (kDebugMode) debugPrint(st);
    }
  }

  static final _emailRe = RegExp(r'([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})');
  static final _secretRe = RegExp(
      r'\b((?:access_token|refresh_token|id_token|password|passwd|pwd|secret|code|rt|at)=)[^&\s"]+|(Bearer\s+)[A-Za-z0-9._~+/=-]+|(Basic\s+)[A-Za-z0-9+/=]+',
      caseSensitive: false);

  /// Маскирование персональных данных и секретов перед записью в журнал:
  /// адрес «ivanov@corp.ru» → «i***@corp.ru» (домен оставлен для
  /// диагностики), токены и пароли в адресах и заголовках → «***».
  /// Журнал отправляют в поддержку — в нём не должно быть ни адресов
  /// коллег, ни токенов.
  static String mask(String message) => message
      .replaceAllMapped(_emailRe, (m) => '${m[1]}***@${m[2]}')
      .replaceAllMapped(_secretRe, (m) => '${m[1] ?? m[2] ?? m[3]}***');

  static void _log(String level, String message) {
    final timestamp = DateFormat('HH:mm:ss.SSS').format(DateTime.now());
    final line = '[$timestamp] $_tag$level: ${mask(message)}';

    if (kDebugMode) {
      debugPrint(line);
    }

    try {
      final f = _logFile;
      if (f == null) return;
      final data = '$line\n';
      final bytes = utf8.encode(data).length;

      // Идёт усечение — не трогаем файл, копим строку в буфер (её допишут после).
      if (_trimming) {
        _pending.add(data);
        if (_pending.length > _maxPending) _pending.removeAt(0);
        return;
      }

      // Порог достигнут — запускаем усечение АСИНХРОННО (не блокируем поток),
      // а текущую строку кладём в буфер, чтобы не потерять.
      if (_currentBytes + _bufBytes + bytes > maxBytes) {
        flushNow();
        _pending.add(data);
        _startTrim();
        return;
      }

      _buf.write(data);
      _bufBytes += bytes;
      if (level == 'ERROR' || _bufBytes >= _bufMax) {
        flushNow();
      } else {
        _flushTimer ??= Timer(const Duration(seconds: 2), flushNow);
      }
    } catch (_) {}
  }

  /// Запускает асинхронное усечение (если не запущено). Тяжёлое чтение/перезапись
  /// файла (до 15 МБ) выполняется через async-I/O, не блокируя поток. Строки,
  /// пришедшие за время усечения, буферизуются в `_pending` и дописываются в конце.
  static void _startTrim() {
    if (_trimming) return;
    _trimming = true;
    // Не await — работа идёт в фоне; ошибки гасим, флаг снимаем в finally.
    _trimAsync();
  }

  static Future<void> _trimAsync() async {
    try {
      final f = _logFile;
      if (f == null || !await f.exists()) {
        _currentBytes = 0;
        return;
      }
      final all = await f.readAsBytes();
      const keep = (maxBytes * 2) ~/ 3; // новейшие 2/3
      List<int> trimmed;
      if (all.length <= keep) {
        trimmed = all;
      } else {
        var start = all.length - keep;
        // Обрезаем по границе строки (до ближайшего '\n' = 0x0A).
        while (start < all.length && all[start] != 0x0A) {
          start++;
        }
        if (start < all.length) start++; // перешагнуть сам '\n'
        trimmed = all.sublist(start);
      }
      await f.writeAsBytes(trimmed, flush: false);
      _currentBytes = trimmed.length;
    } catch (_) {
      _currentBytes = 0;
    } finally {
      // Снимаем флаг и дописываем всё, что накопилось за время усечения.
      _trimming = false;
      _flushPending();
    }
  }

  /// Дописать буферизованные строки в файл (после усечения). Синхронно и быстро —
  /// это лишь накопившиеся за короткое окно строки, не весь файл.
  static void _flushPending() {
    final f = _logFile;
    if (f == null || _pending.isEmpty) return;
    try {
      final data = _pending.join();
      _pending.clear();
      f.writeAsStringSync(data, mode: FileMode.append, flush: false);
      _currentBytes += utf8.encode(data).length;
    } catch (_) {
      _pending.clear();
    }
  }

  /// Прочитать последние строки лог-файла (для просмотра в приложении).
  static Future<String> readRecentLogs({int maxLines = 500}) async {
    try {
      if (kIsWeb) return 'Логи недоступны в веб-версии';
      flushNow();
      final f = _logFile;
      if (f == null || !await f.exists()) return 'Лог-файл пуст';
      final lines = await f.readAsLines();
      final tail = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
      return tail.join('\n');
    } catch (e) {
      return 'Не удалось прочитать логи: $e';
    }
  }

  /// Путь к лог-файлу (для экспорта/прикрепления к письму в ИТ-поддержку).
  static String? get logFilePath => _logFile?.path;

  /// Весь журнал (для пакета диагностики). Перед чтением дописывает строки,
  /// накопленные во время усечения.
  static Future<String> readAll() async {
    try {
      final f = _logFile;
      if (f == null || !await f.exists()) return '';
      await settle();
      return await f.readAsString();
    } catch (e) {
      return 'Не удалось прочитать журнал: $e';
    }
  }

  /// Дождаться конца усечения (если идёт) и дописать буфер — перед тем как
  /// читать файл целиком (пакет диагностики).
  static Future<void> settle() async {
    for (var i = 0; i < 50 && _trimming; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!_trimming) {
      flushNow();
      _flushPending();
    }
  }

  /// Очистить лог-файл (для кнопки «Очистить»).
  static Future<void> clearLogs() async {
    try {
      _flushTimer?.cancel();
      _flushTimer = null;
      _buf.clear();
      _bufBytes = 0;
      _pending.clear();
      _trimming = false;
      final f = _logFile;
      if (f != null && await f.exists()) {
        await f.writeAsString('');
      }
      _currentBytes = 0;
    } catch (_) {}
  }
}

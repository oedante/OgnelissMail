// lib/src/debug_log.dart
// Единый подробный логгер для всех транспортов. Цель — видеть КАЖДОЕ действие:
// какой транспорт, какой запрос (метод/URL/заголовки/тело), какой ответ
// (статус/заголовки/тело), тайминг и расшифровку WBXML. Так сразу видно,
// на каком протоколе и из-за чего движок перестаёт работать.

import 'dart:convert';
import 'dart:typed_data';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime ts;
  final String transport; // EAS / EWS / IMAP / SMTP / CalDAV / CardDAV / AUTO
  final LogLevel level;
  final String message;
  const LogEntry(this.ts, this.transport, this.level, this.message);

  @override
  String toString() {
    final t = ts.toIso8601String().substring(11, 23);
    final lvl = level.name.toUpperCase().padRight(5);
    return '[$t] $lvl ${transport.padRight(7)} | $message';
  }
}

/// Сборщик логов. verbose=true → детальный дамп заголовков/тел/hex.
///
/// [sink] получает каждую запись сразу (приложение пишет их в свой журнал).
/// В памяти хранятся только последние [maxEntries] записей: движок живёт,
/// пока подключён ящик, и без ограничения список рос бы бесконечно.
class DebugLog {
  final bool _verbose;
  /// Подробность можно менять на лету (приложение выключает подробный
  /// журнал через сутки, а движок живёт всю сессию).
  final bool Function()? isVerbose;
  bool get verbose => isVerbose?.call() ?? _verbose;
  final bool echo; // печатать сразу в stdout
  final void Function(LogEntry entry)? sink;
  final int maxEntries;
  final List<LogEntry> entries = [];
  DebugLog({bool verbose = true, this.isVerbose, this.echo = true, this.sink, this.maxEntries = 2000})
      : _verbose = verbose;

  void log(String transport, LogLevel level, String message) {
    final e = LogEntry(DateTime.now(), transport, level, message);
    entries.add(e);
    if (entries.length > maxEntries) {
      entries.removeRange(0, entries.length - maxEntries);
    }
    if (echo) {
      // ignore: avoid_print
      print(e.toString());
    }
    final s = sink;
    if (s != null) {
      try {
        s(e);
      } catch (_) {}
    }
  }

  void debug(String t, String m) => log(t, LogLevel.debug, m);
  void info(String t, String m) => log(t, LogLevel.info, m);
  void warn(String t, String m) => log(t, LogLevel.warn, m);
  void error(String t, String m) => log(t, LogLevel.error, m);

  /// Лог исходящего HTTP-запроса.
  void httpRequest(String transport, String method, Uri url,
      Map<String, String> headers, List<int>? body) {
    info(transport, '→ $method ${url.origin}${url.path}${url.hasQuery ? "?<query ${url.query.length} симв.>" : ""}');
    if (verbose) {
      headers.forEach((k, v) {
        final shown = _redact(k, v);
        debug(transport, '    H> $k: $shown');
      });
      if (body != null && body.isNotEmpty) {
        debug(transport, '    B> ${body.length} байт; hex: ${_hexPreview(body)}');
        final text = _asTextIfPrintable(body);
        if (text != null) debug(transport, '    B> text: ${_clip(text, 300)}');
      }
    }
  }

  /// Лог входящего HTTP-ответа.
  void httpResponse(String transport, int status, Map<String, String> headers,
      List<int> body, Duration elapsed) {
    final lvl = status >= 200 && status < 300 ? LogLevel.info : LogLevel.warn;
    log(transport, lvl, '← HTTP $status (${body.length} байт, ${elapsed.inMilliseconds} мс)');
    if (verbose) {
      headers.forEach((k, v) {
        debug(transport, '    H< $k: ${_redact(k, v)}');
      });
      if (body.isNotEmpty) {
        debug(transport, '    B< hex: ${_hexPreview(body)}');
        final text = _asTextIfPrintable(body);
        if (text != null) debug(transport, '    B< text: ${_clip(text, 400)}');
      }
    }
  }

  /// Дамп расшифрованного WBXML (краткое дерево). Вызывать под
  /// `if (log.verbose)`: дерево ответа с телами писем строится долго, а без
  /// подробного журнала оно не нужно (1.5.6).
  void wbxml(String transport, String label, String treeSummary) {
    if (verbose) debug(transport, 'WBXML $label:\n$treeSummary');
  }

  String _redact(String key, String value) {
    final k = key.toLowerCase();
    if (k == 'authorization') {
      // Показываем схему, скрываем секрет.
      final parts = value.split(' ');
      return parts.isNotEmpty ? '${parts.first} <скрыто ${value.length} симв.>' : '<скрыто>';
    }
    // Куки — это сессия (OWA, X-BackEndCookie): в журнал не пишем вовсе.
    if (k == 'cookie' || k == 'set-cookie') return '<скрыто ${value.length} симв.>';
    if (k == 'x-ms-policykey') return _clip(value, 40);
    return _clip(value, 200);
  }

  String _hexPreview(List<int> bytes, {int max = 64}) {
    final take = bytes.take(max).toList();
    final hex = take.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return bytes.length > max ? '$hex … (+${bytes.length - max})' : hex;
  }

  String? _asTextIfPrintable(List<int> bytes) {
    try {
      final sample = bytes.take(64).toList();
      // WBXML начинается с 0x03 0x01 — это не текст.
      if (sample.isNotEmpty && sample.first == 0x03) return null;
      final printable = sample.where((b) => b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127)).length;
      if (printable / sample.length < 0.7) return null;
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  String _clip(String s, int n) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > n ? '${one.substring(0, n)}…' : one;
  }

  /// Весь лог как текст (для сохранения/вывода).
  String dump() => entries.map((e) => e.toString()).join('\n');
}

/// Краткое текстовое дерево WBXML-элемента (для дампа).
String wbxmlTree(dynamic element, {int indent = 0}) {
  // element ожидается WbxmlElement (name, text, children).
  final pad = '  ' * indent;
  final name = (element.name as String?) ?? '?';
  final text = element.text as String?;
  final children = (element.children as List?) ?? const [];
  final sb = StringBuffer();
  sb.write('$pad<$name>');
  if (text != null && text.isNotEmpty) sb.write(' "$text"');
  sb.write('\n');
  for (final c in children) {
    sb.write(wbxmlTree(c, indent: indent + 1));
  }
  return sb.toString();
}

Uint8List asBytes(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

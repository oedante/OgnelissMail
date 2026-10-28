// lib/core/security/mail_body_processor.dart
// Подготовка HTML письма к показу вне UI-изолята.
//
// Разбор DOM санитайзером (пакет html) и десяток регулярных выражений
// трекер-блокера на письме в сотни килобайт (рассылки, вёрстка Outlook,
// длинные цепочки) занимали главный изолят на сотни миллисекунд: открытие
// письма подтормаживало, анимация перехода дёргалась. Теперь крупные письма
// обрабатываются в отдельном изоляте (Isolate.run), мелкие — сразу: запуск
// изолята стоит дороже их обработки.
//
// С 1.5.9 — в долгоживущих рабочих изолятах (WorkIsolate): открытое письмо —
// в интерактивном, пачки синхронизации — в фоновом; без запуска изолята на
// каждый вызов и без очереди открытого письма за синхронизацией.

import 'dart:async';

import '../utils/text_safe.dart';
import '../utils/work_isolate.dart';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../services/security/tracker_blocker.dart';
import '../logging/app_logger.dart';
import 'html_sanitizer.dart';
import 'security_utils.dart';

class MailBodyProcessor {
  MailBodyProcessor._();

  /// Порог, после которого работа уходит в отдельный изолят (символов).
  /// С рабочим изолятом запуск не нужен — порог ниже (было 24 КБ): на
  /// главном изоляте остаются только совсем мелкие письма.
  static const isolateThreshold = 8 * 1024;

  /// Санитайзер + блокировка трекеров. [keepStyles] — для WebView (стили
  /// письма сохраняются очищенными).
  static Future<TrackerBlockResult> secure(
    String html, {
    required bool keepStyles,
    required TrackerBlockOptions options,
  }) async {
    if (kIsWeb || html.length < isolateThreshold) {
      return _process(html, keepStyles, options);
    }
    try {
      return await WorkIsolate.interactive.run(() => _process(html, keepStyles, options));
    } on UnsupportedError catch (e) {
      AppLogger.debug('MailBodyProcessor: изолят недоступен ($e) — обработка на месте');
      return _process(html, keepStyles, options);
    }
  }

  /// То же, что [secure], но сразу (для работы, которая уже идёт в изоляте:
  /// подготовка письма целиком — mail_open_cache.dart).
  static TrackerBlockResult processSync(String html,
          {required bool keepStyles, required TrackerBlockOptions options}) =>
      _process(html, keepStyles, options);

  static TrackerBlockResult _process(String html, bool keepStyles, TrackerBlockOptions o) {
    final clean = keepStyles
        ? HtmlSanitizer.sanitizeKeepingStyles(html)
        : SecurityUtils.sanitizeHtml(html);
    return TrackerBlockerNotifier.block(clean, o);
  }

  /// Санитайзер для пачки писем (синхронизация EWS) — одним заходом в изолят.
  /// Стили письма сохраняются очищенными (1.5.9): раньше здесь удалялись
  /// блоки <style> вместе с содержимым, и вёрстка Outlook у писем Exchange
  /// была беднее, чем у IMAP и ActiveSync (у них HTML хранится как есть и
  /// очищается при показе). Очистка при показе остаётся.
  static Future<List<String?>> sanitizeAll(List<String?> htmls) async {
    final total = htmls.fold<int>(0, (s, h) => s + (h?.length ?? 0));
    if (kIsWeb || total < isolateThreshold) return _sanitizeAll(htmls);
    try {
      return await WorkIsolate.background.run(() => _sanitizeAll(htmls));
    } on UnsupportedError {
      return _sanitizeAll(htmls);
    } on TimeoutException {
      // Очистка зависла на чём-то в пачке — тексты не сохраняем, при
      // открытии письмо загрузится и очистится заново.
      return List<String?>.filled(htmls.length, null);
    }
  }

  static List<String?> _sanitizeAll(List<String?> src) =>
      [for (final h in src) h == null ? null : HtmlSanitizer.sanitizeKeepingStyles(h)];

  /// HTML → простой текст для поискового индекса (id → текст), не длиннее
  /// 20 000 символов на письмо.
  static Future<Map<String, String>> htmlToPlainAll(Map<String, String> htmls) async {
    final total = htmls.values.fold<int>(0, (s, h) => s + h.length);
    if (kIsWeb || total < isolateThreshold) return _plainAll(htmls);
    try {
      return await WorkIsolate.background.run(() => _plainAll(htmls));
    } on UnsupportedError {
      return _plainAll(htmls);
    } on TimeoutException {
      // Текст для поиска не получен — письма сохраняются без него (поиск
      // найдёт их по теме и превью), синхронизация не встаёт (1.6.12).
      return const {};
    }
  }

  static Map<String, String> _plainAll(Map<String, String> src) =>
      src.map((k, v) => MapEntry(k, htmlToPlain(v)));

  /// HTML → текст с переносами строк для превью (1.6.31): <br>, абзацы,
  /// строки таблиц и пункты списков — новой строкой; пустые строки
  /// (Outlook ставит абзац «&nbsp;» между абзацами) убирает
  /// [multilinePreviewOf]. Берётся только начало письма.
  static String htmlToPreviewText(String html) {
    var t = cutSafe(html, 60000);
    t = _dropBetween(t, '<!--', '-->');
    for (final tag in const ['style', 'script', 'head', 'title']) {
      t = _dropTagBlocks(t, tag);
    }
    return t
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|li|tr|h[1-6]|blockquote|table|ul|ol)\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
  }

  /// Превью с переносами (id → превью) — пачкой, тяжёлый разбор в фоне.
  static Future<Map<String, String>> previewAll(Map<String, ({String? plain, String? html})> src) async {
    Map<String, String> run() {
      final out = <String, String>{};
      src.forEach((k, v) {
        final text = (v.plain ?? '').trim().isNotEmpty ? v.plain! : (v.html == null ? '' : htmlToPreviewText(v.html!));
        final p = multilinePreviewOf(text);
        if (p != null) out[k] = p;
      });
      return out;
    }
    if (kIsWeb) return run();
    try {
      return await WorkIsolate.background.run(run);
    } on UnsupportedError {
      return run();
    } on TimeoutException {
      return const {};
    }
  }

  static String htmlToPlain(String html) {
    // Комментарии (условные блоки Outlook с VML), заголовок документа
    // (<title> рассылки попадал в начало превью), стили и скрипты — за один
    // линейный проход (1.6.12): прежние выражения с [\s\S]*? на письме с
    // незакрытым <style> или комментарием просматривали остаток письма от
    // каждого открывающего тега — на письме в мегабайт это минуты.
    var t = _dropBetween(html, '<!--', '-->');
    for (final tag in const ['style', 'script', 'head', 'title']) {
      t = _dropTagBlocks(t, tag);
    }
    final s = t
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cutSafe(s, 20000);
  }

  /// Убрать всё от [open] до [close] включительно; незакрытый — до конца.
  static String _dropBetween(String s, String open, String close) {
    if (!s.contains(open)) return s;
    final out = StringBuffer();
    var i = 0;
    while (true) {
      final a = s.indexOf(open, i);
      if (a < 0) {
        out.write(s.substring(i));
        break;
      }
      out
        ..write(s.substring(i, a))
        ..write(' ');
      final b = s.indexOf(close, a + open.length);
      if (b < 0) break;
      i = b + close.length;
    }
    return out.toString();
  }

  /// Убрать блоки <tag …>…</tag> без учёта регистра, за линейное время.
  static String _dropTagBlocks(String s, String tag) {
    // Только латиница в нижний регистр: длина строки не меняется (у
    // toLowerCase для некоторых букв Юникода она другая — индексы съехали бы).
    final units = s.codeUnits;
    final lower = String.fromCharCodes([for (final c in units) c >= 65 && c <= 90 ? c + 32 : c]);
    final open = '<$tag';
    final close = '</$tag';
    if (!lower.contains(open)) return s;
    final out = StringBuffer();
    var i = 0;
    while (true) {
      var a = lower.indexOf(open, i);
      // «<header», «<titlebar» — не наш тег.
      while (a >= 0 && a + open.length < lower.length && RegExp(r'[a-z0-9_-]').hasMatch(lower[a + open.length])) {
        a = lower.indexOf(open, a + open.length);
      }
      if (a < 0) {
        out.write(s.substring(i));
        break;
      }
      out
        ..write(s.substring(i, a))
        ..write(' ');
      final b = lower.indexOf(close, a + open.length);
      if (b < 0) break;
      final end = lower.indexOf('>', b);
      if (end < 0) break;
      i = end + 1;
    }
    return out.toString();
  }

  /// Любая чистая функция над большим текстом — в изоляте, мелкое — сразу.
  /// [fn] — статическая функция или tear-off (замыкание на объект с сокетами
  /// в изолят не передать). [background] — работа синхронизации: она идёт
  /// через Isolate.run, как раньше — результат (например, дерево разобранного
  /// ответа EWS) передаётся без копирования (Isolate.exit) и не занимает
  /// очередь интерактивного изолята.
  static Future<R> heavy<R>(String input, R Function(String) fn, {bool background = false}) async {
    if (kIsWeb || input.length < isolateThreshold) return fn(input);
    try {
      return await (background ? Isolate.run(() => fn(input)) : WorkIsolate.interactive.run(() => fn(input)));
    } on UnsupportedError {
      return fn(input);
    }
  }
}

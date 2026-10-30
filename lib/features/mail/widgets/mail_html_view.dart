// lib/features/mail/widgets/mail_html_view.dart
// Тело HTML-письма во встроенном браузере (WebView) с максимально урезанными
// возможностями.
//
// ══════════════════════════════════════════════════════════════════════
// ПОЧЕМУ WEBVIEW
// ══════════════════════════════════════════════════════════════════════
// flutter_html не поддерживает вложенные таблицы — основу вёрстки писем
// Outlook/Word: ячейки рисовались пустыми, «таблицы пропадали». Браузерный
// движок отображает письмо так же, как Outlook в браузере.
//
// ══════════════════════════════════════════════════════════════════════
// БЕЗОПАСНОСТЬ — НЕСКОЛЬКО НЕЗАВИСИМЫХ СЛОЁВ
// ══════════════════════════════════════════════════════════════════════
//  1. HTML уже очищен (HtmlSanitizer: script, обработчики on*, javascript:,
//     формы, iframe, object) и прошёл блокировщик трекеров.
//  2. JavaScript в WebView выключен полностью.
//  3. Политика CSP в самом документе: скрипты, фреймы, формы, шрифты и любые
//     сетевые загрузки запрещены; картинки — только встроенные (data:),
//     внешние — лишь когда пользователь нажал «Показать изображения».
//  4. Настройки WebView: нет доступа к файлам и content://, нет
//     cookie/DOM-хранилища/БД/кэша, режим инкогнито, без геолокации, без
//     новых окон; сетевые загрузки заблокированы на уровне движка (Android),
//     пока изображения не разрешены.
//  5. Навигация внутри WebView запрещена. Нажатие на ссылку отменяется и
//     передаётся приложению (LinkOpener — проверка домена, предупреждение
//     о фишинге). Переход без нажатия (meta refresh и т.п.) молча отменяется.
//
// Высота: JavaScript выключен, поэтому высота содержимого берётся у движка
// (getContentHeight) после загрузки и повторно — когда догрузятся картинки.
// Прокрутку по вертикали ведёт экран письма, горизонтальную (широкие
// таблицы) — сам WebView.
//
// Широкие письма (рассылки с вёрсткой 600–800 px) по умолчанию вписываются
// в ширину экрана: документ размечается на свою ширину (viewport) и
// уменьшается движком. Кнопка в углу письма возвращает обычный масштаб
// (100 %, широкие части прокручиваются вбок) и обратно.

import 'dart:async';
import '../../../core/theme/app_icons.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/open_trace.dart';
import '../../../services/background/work_scheduler.dart';
import '../../../core/utils/work_isolate.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../core/utils/linkify.dart';
import '../../../core/utils/symbol_fonts.dart';
import '../../../l10n/app_localizations.dart';

/// Где показ письма в WebView поддерживается. Остальные платформы (Linux,
/// Windows без проверенного WebView2) — прежний рендер flutter_html.
bool get mailWebViewSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Подготовленный к показу документ письма.
class MailHtmlDocument {
  /// Полный HTML-документ: CSP, viewport, базовые стили, тело письма.
  final String html;

  /// Адрес ссылки → её видимый текст (для проверки «текст показывает другой
  /// домен»: в WebView без JavaScript текст нажатой ссылки не узнать).
  final Map<String, String> linkTexts;

  /// Ширина вёрстки письма в CSS-пикселях по объявленным размерам
  /// (width у таблиц и картинок, width/min-width в стилях); null — не задана.
  final int? declaredWidth;

  const MailHtmlDocument(this.html, this.linkTexts, {this.declaredWidth});

  static const _viewportTag = '<meta name="viewport" content="width=device-width, initial-scale=1">';

  /// Тот же документ, размеченный ровно на ширину окна [width] в обычном
  /// масштабе (1.5.9). «device-width» на Android — ширина экрана, а не окна
  /// WebView: в окне уже экрана (вкладка «Письмо» в просмотре вложений —
  /// с полями) страница была шире окна, и Android сдвигал её — текст
  /// обрезался слева и справа.
  ///
  /// Пределы щипка (1.6.2): мельче исходного масштаба не уменьшить (иначе
  /// под письмом оставалось «бесконечное» пустое поле), крупнее — до ×4
  /// (при ×5 от вписанного письма окно становилось таким высоким, что
  /// Android переставал его рисовать — письмо пропадало).
  String atWidth(int width) => html.replaceFirst(
      _viewportTag,
      '<meta name="viewport" content="width=$width, initial-scale=1, minimum-scale=1, maximum-scale=4, user-scalable=yes">');

  /// Тот же документ, размеченный на ширину [width] и уменьшенный до
  /// [scale]: так широкое письмо целиком помещается на экран.
  String fitted(int width, double scale) => html.replaceFirst(
      _viewportTag,
      '<meta name="viewport" content="width=$width, initial-scale=${scale.toStringAsFixed(3)}, '
      'minimum-scale=${scale.toStringAsFixed(3)}, maximum-scale=${(scale * 4).clamp(scale, 5.0).toStringAsFixed(3)}, '
      'user-scalable=yes">');

  /// Ширина вёрстки: максимум объявленных размеров от 320 до 3000 px (широкие
  /// таблицы-трекеры тоже вписываются, а не обрезаются справа).
  /// Учитываются px и pt (Outlook пишет ширины колонок подписи в pt:
  /// «width:225.0pt»), а у строк таблиц — сумма ширин ячеек: подпись из двух
  /// колонок по 300 px не помещалась в экран, но ни один элемент не был
  /// шире 320 px, и письмо не вписывалось — справа обрезалось.
  static int? _declaredWidth(dom.Element body) {
    var best = 0;
    void consider(int? v) {
      if (v != null && v >= 320 && v <= 3000 && v > best) best = v;
    }

    final cssWidth = RegExp(r'(?<![-\w])(?:min-)?width\s*:\s*(\d{2,4}(?:\.\d+)?)(px|pt)', caseSensitive: false);
    int? toPx(String num, String unit) {
      final v = double.tryParse(num);
      if (v == null) return null;
      return (unit.toLowerCase() == 'pt' ? v * 4 / 3 : v).round();
    }

    int? widthOf(dom.Element e) {
      final w = e.attributes['width']?.trim();
      if (w != null && RegExp(r'^\d+(px)?$').hasMatch(w)) return int.tryParse(w.replaceAll('px', ''));
      final st = e.attributes['style'];
      if (st != null) {
        final m = cssWidth.firstMatch(st);
        if (m != null) return toPx(m.group(1)!, m.group(2)!);
      }
      return null;
    }

    for (final e in body.querySelectorAll('[width],[style]')) {
      consider(widthOf(e));
    }
    for (final tr in body.querySelectorAll('tr')) {
      var sum = 0;
      for (final td in tr.children.where((c) => c.localName == 'td' || c.localName == 'th')) {
        sum += widthOf(td) ?? 0;
      }
      consider(sum);
    }
    for (final st in body.querySelectorAll('style')) {
      for (final m in cssWidth.allMatches(st.text)) {
        consider(toPx(m.group(1)!, m.group(2)!));
      }
    }
    return best == 0 ? null : best;
  }

  /// [build] вне UI-изолята для крупного письма.
  static Future<MailHtmlDocument> buildAsync(
    String bodyHtml, {
    required bool allowRemoteImages,
    Map<String, String> inlineImages = const {},
    bool keepCid = false,
  }) async {
    if (kIsWeb || bodyHtml.length < MailBodyProcessor.isolateThreshold) {
      return build(bodyHtml, allowRemoteImages: allowRemoteImages, inlineImages: inlineImages, keepCid: keepCid);
    }
    try {
      return await WorkIsolate.interactive.run(() => build(bodyHtml,
          allowRemoteImages: allowRemoteImages, inlineImages: inlineImages, keepCid: keepCid));
    } on UnsupportedError {
      return build(bodyHtml, allowRemoteImages: allowRemoteImages, inlineImages: inlineImages, keepCid: keepCid);
    }
  }

  /// [bodyHtml] — уже очищенный HTML письма. [inlineImages] — Content-ID →
  /// data URI встроенных картинок (`cid:`). [keepCid] — картинки, которых нет
  /// в [inlineImages], остаются ссылками `cid:` (скрыты стилем) и
  /// подставляются потом [withInlineImages]: документ собирается, не дожидаясь
  /// картинок (1.5.6). Без него такие картинки убираются сразу.
  static MailHtmlDocument build(
    String bodyHtml, {
    required bool allowRemoteImages,
    Map<String, String> inlineImages = const {},
    bool keepCid = false,
  }) {
    final doc = html_parser.parse(bodyHtml);
    final body = doc.body ?? dom.Element.tag('body');
    // <style> в начале фрагмента разборщик относит в <head>, а документ для
    // показа берёт только тело — стили рассылки терялись, и ширина вёрстки
    // из них не учитывалась. Переносим их в начало тела.
    final headStyles = doc.head?.querySelectorAll('style') ?? const <dom.Element>[];
    for (final st in headStyles.reversed) {
      st.remove();
      body.nodes.insert(0, st);
    }

    // Встроенные картинки: cid:xxx → data:…; неизвестные cid убираем, чтобы
    // движок не пытался их загрузить.
    for (final img in body.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.toLowerCase().startsWith('cid:')) {
        final cid = _normCid(src.substring(4));
        final data = inlineImages[cid];
        if (data != null) {
          img.attributes['src'] = data;
        } else if (!keepCid) {
          // Картинку не получили (вложение не скачано, сервер его не отдал):
          // убираем элемент целиком. Раньше оставался пустой блок размером с
          // картинку и подпись «cid:image004.jpg@01D3…» — под подписью письма
          // появлялось пустое место, и граница письма «уезжала» вниз.
          img.remove();
        }
      }
    }

    // Картинка, у которой задана только высота (height="64" у логотипа,
    // 28 — у значков; файлы — в 2–3 раза крупнее, «@2x», «@3x»), — этой
    // высоты (1.8.12, письмо Google Play 29.10.2026). Базовый стиль ставит
    // всем картинкам height:auto (против вытянутых картинок Outlook), и такие
    // картинки выходили в 2–3 раза больше задуманного. object-fit — без
    // искажения, если ширину ограничит экран.
    for (final img in body.querySelectorAll('img[height]')) {
      final h = int.tryParse((img.attributes['height'] ?? '').trim().replaceAll(RegExp(r'px$'), ''));
      final style = img.attributes['style'] ?? '';
      if (h == null || h <= 0 || h > 2000 || img.attributes.containsKey('width') ||
          RegExp(r'(^|[;\s])(width|height)\s*:', caseSensitive: false).hasMatch(style)) {
        continue;
      }
      img.attributes['style'] = '${style.isEmpty || style.trim().endsWith(';') ? style : '$style;'}'
          'height:${h}px !important;width:auto !important;object-fit:contain';
    }

    // Стрелки и маркеры из шрифтов Wingdings и Symbol («à» вместо «→»).
    if (SymbolFonts.mayContain(bodyHtml)) SymbolFonts.mapDom(body);

    // Пустые абзацы в начале и в конце (Outlook: <p>&nbsp;</p>, <br>, пустой
    // остаток после отрезанной цитаты) давали белые поля над и под текстом.
    _trimSide(body, start: true);
    _trimSide(body, start: false);

    // Ссылки и адреса почты обычным текстом — нажимаемые (1.5.10).
    if (Linkify.mayContain(bodyHtml)) _linkifyText(body);

    final links = <String, String>{};
    for (final a in body.querySelectorAll('a[href]')) {
      final href = a.attributes['href']!.trim();
      final text = a.text.trim();
      if (href.isNotEmpty && text.isNotEmpty) links.putIfAbsent(href, () => text);
      // Ссылки — только в этом окне: target="_blank" просит новое окно.
      a.attributes.remove('target');
      // Длинный адрес текстом ссылки переносится где угодно (1.8.12,
      // замечание 29.10.2026, рассылка с ссылками drive.google.com/…):
      // неразрывный адрес раздвигал ячейку таблицы шире вёрстки (600 → 800),
      // и даже вписанное по ширине письмо обрезалось справа — вместе с
      // абзацами той же ячейки. Обычные слова и короткие ссылки — как раньше:
      // перенос «где угодно» для всего письма рвал бы слова в узких
      // колонках таблиц.
      if (isLongToken(text)) a.classes.add('og-brk');
    }

    // Стили письма (<style> в теле — Outlook кладёт их туда при пересылке)
    // остаются: CSP разрешает только встроенные стили, а загрузки из CSS
    // (url(), @import, шрифты) запрещены той же политикой.
    // cid: — встроенные картинки, которые окно получает по запросу
    // (MailHtmlView.inlineRaw); без обработчика такие адреса не загружаются.
    final img = allowRemoteImages ? 'data: cid: https: http:' : 'data: cid:';
    final csp = "default-src 'none'; img-src $img; style-src 'unsafe-inline'; "
        "font-src 'none'; media-src 'none'; frame-src 'none'; child-src 'none'; "
        "object-src 'none'; script-src 'none'; form-action 'none'; base-uri 'none'";

    final declared = _declaredWidth(body);
    final out = '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="$csp">'
        '$_viewportTag'
        '<meta name="referrer" content="no-referrer">'
        '<style>$_baseCss</style></head>'
        '<body>${body.innerHtml}</body></html>';
    return MailHtmlDocument(out, links, declaredWidth: declared);
  }

  /// Текст ссылки — один длинный «токен» без пробелов (адрес, путь, код):
  /// такой можно переносить в любом месте.
  static bool isLongToken(String text) => text.length >= 24 && !text.contains(RegExp(r'\s'));

  static final _imgTag = RegExp(r'''<img\b(?:[^>"']|"[^"]*"|'[^']*')*>''', caseSensitive: false);
  static final _cidSrc = RegExp(r'''\ssrc\s*=\s*"cid:([^"]*)"''', caseSensitive: false);

  /// Документ со встроенными картинками: `cid:` → data URI. Картинки без
  /// данных убираются (как раньше при сборке). Строковая замена по уже
  /// собранному документу — без повторного разбора HTML.
  MailHtmlDocument withInlineImages(Map<String, String> images) {
    // Проверка по атрибуту src: слово «cid:» есть и в базовом стиле
    // документа (img[src^="cid:"]), по нему одному не отличить.
    if (!_cidSrc.hasMatch(html)) return this;
    final out = html.replaceAllMapped(_imgTag, (m) {
      final tag = m.group(0)!;
      final s = _cidSrc.firstMatch(tag);
      if (s == null) return tag;
      final data = images[_normCid(s.group(1)!.replaceAll('&amp;', '&'))];
      if (data == null) return '';
      return tag.replaceRange(s.start, s.end, ' src="$data"');
    });
    return MailHtmlDocument(out, linkTexts, declaredWidth: declaredWidth);
  }

  /// Текст вне ссылок, стилей и полей ввода: найденные адреса → `<a href>`.
  static void _linkifyText(dom.Node node, {int depth = 0}) {
    if (depth > 64) return;
    for (final n in node.nodes.toList()) {
      if (n is dom.Element) {
        final tag = n.localName ?? '';
        if (tag == 'a' || tag == 'style' || tag == 'script' || tag == 'textarea' || tag == 'title' || tag == 'svg') {
          continue;
        }
        _linkifyText(n, depth: depth + 1);
      } else if (n is dom.Text) {
        final t = n.text;
        final found = Linkify.find(t);
        if (found.isEmpty) continue;
        final parent = n.parentNode!;
        var at = parent.nodes.indexOf(n);
        n.remove();
        var pos = 0;
        void put(dom.Node x) => parent.nodes.insert(at++, x);
        for (final m in found) {
          if (m.start > pos) put(dom.Text(t.substring(pos, m.start)));
          put(dom.Element.tag('a')
            ..attributes['href'] = m.href
            ..append(dom.Text(t.substring(m.start, m.end))));
          pos = m.end;
        }
        if (pos < t.length) put(dom.Text(t.substring(pos)));
      }
    }
  }

  static const _contentTags = 'img,table,hr,svg,video,audio,input,iframe,object,picture';

  static bool _isBlank(dom.Node n) {
    if (n is dom.Comment) return true;
    if (n is dom.Text) return n.text.replaceAll('\u00a0', ' ').trim().isEmpty;
    if (n is dom.Element) {
      final tag = n.localName ?? '';
      if (tag == 'br') return true;
      if (tag == 'style' || tag == 'img' || tag == 'table' || tag == 'hr') return false;
      if (n.querySelector(_contentTags) != null) return false;
      return n.text.replaceAll('\u00a0', ' ').trim().isEmpty;
    }
    return false;
  }

  /// Убрать пустые узлы с одного края, спускаясь в обёртки (div.WordSection1).
  static void _trimSide(dom.Element e, {required bool start, int depth = 0}) {
    var i = start ? 0 : e.nodes.length - 1;
    while (i >= 0 && i < e.nodes.length) {
      final n = e.nodes[i];
      // <style> и <meta> в теле — не текст письма: обходим, не удаляя.
      if (n is dom.Element && (n.localName == 'style' || n.localName == 'meta')) {
        i += start ? 1 : -1;
        continue;
      }
      if (_isBlank(n)) {
        n.remove();
        if (!start) i--;
        continue;
      }
      if (n is dom.Element && depth < 8) _trimSide(n, start: start, depth: depth + 1);
      return;
    }
  }

  static String _normCid(String raw) {
    var c = raw.trim();
    // «%» без кода после него (cid:50%off), русские буквы в cid, неверный
    // UTF-8 — Uri.decodeComponent бросает исключение, и письмо не
    // собиралось. Такой cid берём как есть.
    try {
      c = Uri.decodeComponent(c);
    } on ArgumentError {
      // как есть
    } on FormatException {
      // как есть
    }
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    return c.toLowerCase();
  }

  static const _baseCss = '''
html,body{margin:0;padding:0;background:#ffffff;color:#1b1c1f;color-scheme:light;}
body{padding:4px 0 12px;font-family:-apple-system,Roboto,"Segoe UI",Arial,sans-serif;
font-size:14px;line-height:1.35;overflow-wrap:anywhere;word-wrap:break-word;-webkit-text-size-adjust:100%;}
p{margin:0 0 .4em;}
p.MsoNormal,li.MsoNormal,div.MsoNormal{margin:0;}
img{max-width:100%;height:auto !important;}
/* !important у высоты: у картинок Outlook высота задана в style — ширина
   сжималась, а высота оставалась прежней, картинка вытягивалась (10.10.2026).
   У ширины — без !important (1.8.12, письмо CDEK 29.10.2026): адаптивные
   рассылки задают картинке «width:100%; max-width:80px», и наше
   max-width:100% !important отменяло их 80 px — значок растягивался на всю
   ширину экрана. */
pre,code{white-space:pre-wrap;}
a{color:#1D4F91;}
/* Длинный адрес текстом ссылки — переносится где угодно и не раздвигает
   таблицу (MailHtmlDocument.build, og-brk). */
.og-brk{overflow-wrap:anywhere !important;word-break:break-all !important;}
blockquote{margin:8px 0 8px 4px;padding-left:10px;border-left:3px solid #c7cdd6;color:#4a4f57;}
table{border-collapse:collapse;}
/* Широкая таблица листается вбок, даже если письмо запретило прокрутку. */
html,body{overflow-x:auto !important;}
/* Встроенная картинка, которая ещё не подставлена: без пустого места. */
img[src^="cid:" i]{display:none !important;}
''';
}

/// Тело письма в WebView. Ссылки — через [onLink]; высота подстраивается под
/// содержимое.
class MailHtmlView extends StatefulWidget {
  const MailHtmlView({
    super.key,
    required this.document,
    required this.allowRemoteImages,
    required this.onLink,
    this.textScale = 1.0,
    this.pageColor,
    this.dark = false,
    this.active = true,
    this.onShown,
    this.inlineRaw,
  });

  /// Встроенные картинки по запросу окна (1.5.9, «Настройки → Почта →
  /// Открытие писем → Картинки письма отдельно»): документ оставляет адреса `cid:`, окно
  /// запрашивает их само и получает байты отсюда — без base64 в документе
  /// (мегабайты текста через канал платформы и разбор в Chromium). null —
  /// как раньше: картинки уже подставлены в документ data URI.
  final Map<String, ({String mime, Uint8List data})>? inlineRaw;

  final MailHtmlDocument document;

  /// Текст письма показан (заглушка снята). Экран письма откладывает до
  /// этого момента работу, которая занимает главный поток («прочитано»,
  /// цепочка беседы): раньше она шла ровно тогда, когда создавался WebView
  /// (1.5.9).
  final VoidCallback? onShown;

  /// false — встроенное окно пока не создаётся (страница беседы, которую
  /// листают: создание окна на ходу давало рывок). Созданное окно остаётся.
  final bool active;

  /// Прогреть движок WebView заранее (Android): первое встроенное окно в
  /// процессе загружает Chromium — 0,2–0,5 с, и первое письмо после запуска
  /// открывалось заметно дольше остальных. Невидимое окно 1×1 загружает
  /// пустую страницу и закрывается (1.5.6).
  ///
  /// С 1.5.9 вместо прогрева — запасное окно ([MailWebViewPool]): оно и
  /// загружает движок, и остаётся наготове для следующего письма. [width] —
  /// ширина окна письма (экран телефона), [textScale] — размер шрифта писем.
  static Future<void> warmUp({double width = 0, double textScale = 1}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (MailWebViewPool.enabled && width > 0) {
      await MailWebViewPool.ensureSpare(width: width, textScale: textScale);
      return;
    }
    if (_warmed) return;
    _warmed = true;
    HeadlessInAppWebView? w;
    final loaded = Completer<void>();
    try {
      w = HeadlessInAppWebView(
        initialSize: const Size(1, 1),
        initialData: InAppWebViewInitialData(
          data: '<!DOCTYPE html><html><body></body></html>',
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: WebUri('about:blank'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: false,
          javaScriptBridgeEnabled: false,
          cacheEnabled: false,
          blockNetworkLoads: true,
          blockNetworkImage: true,
          transparentBackground: true,
        ),
        onLoadStop: (controller, url) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      await w.run();
      await loaded.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {
      // Прогрев — необязательный: без него первое письмо откроется чуть дольше.
    } finally {
      try {
        await w?.dispose();
      } catch (_) {}
    }
  }

  static bool _warmed = false;

  /// Фон страницы письма — тот же, что у экрана вокруг (белый в светлой
  /// теме, тёмный в тёмной, чёрный в AMOLED). Раньше письмо было белой
  /// карточкой на сером фоне в любой теме.
  final Color? pageColor;

  /// Тёмная тема: письмо перекрашивается инверсией цветов (картинки
  /// возвращаются к исходным). Письма Outlook задают чёрный текст прямо в
  /// разметке — без инверсии на тёмном фоне его было бы не прочитать.
  final bool dark;
  final bool allowRemoteImages;
  final void Function(String url, String? linkText) onLink;
  final double textScale;

  @override
  State<MailHtmlView> createState() => _MailHtmlViewState();

  /// Документ для окна: разметка по ширине окна (или вписывание широкого
  /// письма) и оформление под тему. Один и тот же для виджета и запасного
  /// окна (MailWebViewPool) — по совпадению строки окно и находит своё письмо.
  static String composeHtml(MailHtmlDocument doc,
      {required double viewWidth,
      required int? fitWidth,
      required bool dark,
      required Color? pageColor,
      required double textScale,
      bool cidByRequest = false}) {
    final scale = fitWidth == null || viewWidth <= 0 ? 1.0 : viewWidth / fitWidth;
    final html = fitWidth != null
        ? doc.fitted(fitWidth, scale)
        : viewWidth > 0
            ? doc.atWidth(viewWidth.round())
            : doc.html;
    final out = _themed(html, dark: dark, pageColor: pageColor, textScale: textScale);
    if (!cidByRequest) return out;
    // Картинки cid: окно запросит само — не скрывать их.
    const show = '<style id="og-cid">img[src^="cid:" i]{display:inline !important;}</style>';
    final i = out.indexOf('</head>');
    return i < 0 ? '$show$out' : '${out.substring(0, i)}$show${out.substring(i)}';
  }

  /// Настройки окна письма — общие у виджета и запасного окна
  /// (MailWebViewPool): забранное запасное окно работает с ними же.
  static InAppWebViewSettings _settings({required bool blockNet, required double textScale, bool cidByRequest = false}) =>
      InAppWebViewSettings(
          // iOS: адреса cid: окно отдаёт обработчику (картинки по запросу).
          resourceCustomSchemes: cidByRequest ? const ['cid'] : null,
          // Скрипты, окна, навигация
          javaScriptEnabled: false,
          // Мост JavaScript ↔ Dart без JavaScript бесполезен, а плагин при
          // каждом создании окна добавлял JavascriptInterface и служебные
          // скрипты (InAppWebView.prepareAndAddUserScripts) — 1.5.9.
          javaScriptBridgeEnabled: false,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          useShouldOverrideUrlLoading: true,
          // Файлы и хранилища
          allowFileAccess: false,
          allowContentAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          cacheEnabled: false,
          incognito: true,
          domStorageEnabled: false,
          databaseEnabled: false,
          thirdPartyCookiesEnabled: false,
          geolocationEnabled: false,
          // Сеть: до «Показать изображения» движок ничего не загружает
          blockNetworkImage: blockNet,
          blockNetworkLoads: blockNet,
          safeBrowsingEnabled: true,
          mediaPlaybackRequiresUserGesture: true,
          allowsInlineMediaPlayback: false,
          allowsLinkPreview: false,
          // Вид и жесты
          // Прозрачный до загрузки: без белой вспышки в тёмной теме.
          transparentBackground: true,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
          // Android: гибридная композиция («встроенное окно» WebView) всегда.
          // С текстурой (TLHC, 09–10.10.2026) выделение текста ломалось:
          // системных ручек и лупы нет (лупа — серое пятно не на месте),
          // вместо меню «Копировать…» — строка слов без подложки от самого
          // плагина, выделить можно было одно слово (замечание 10.10.2026).
          // Плюсы гибридной композиции: выделение и меню — системные, нет
          // предела высоты текстуры у длинных писем. Минус — шторки поверх
          // письма могут выезжать чуть менее плавно.
          useHybridComposition: true,
          // Android: учитывать ширину из viewport (вписывание широких писем).
          useWideViewPort: true,
          loadWithOverviewMode: true,
          verticalScrollBarEnabled: false,
          // Полоса прокрутки вбок поверх письма выглядела как рамка снизу.
          horizontalScrollBarEnabled: false,
          disableVerticalScroll: true,
          textZoom: (textScale * 100).round().clamp(80, 300),
        );

  /// Ширина тела письма на экране письма (телефон): ширина экрана без
  /// вырезов и боковых панелей (SafeArea), не больше удобной ширины чтения
  /// (ReadableWidth, 860), минус поля 16 dp. Окно заранее готовится на эту
  /// ширину; раньше бралась ширина экрана — в альбомной ориентации широкого
  /// телефона (больше 860 dp) и с вырезом сбоку окно не совпадало (1.5.10).
  static double bodyWidthOf(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final avail = size.width - pad.left - pad.right;
    return (avail < 860 ? avail : 860) - 2 * 16;
  }

  /// Широкое письмо при открытии — сразу по ширине экрана (true) или в
  /// обычном масштабе с кнопкой «По ширине экрана» (false, по умолчанию).
  ///
  /// 1.5.11 (замечание 12.10.2026: «каждое письмо открывается со своим
  /// масштабом»): широкое письмо раньше всегда уменьшалось до ширины экрана —
  /// масштаб, а с ним и размер текста, у каждого письма был свой (800 px на
  /// 360 точек — меньше половины). Теперь письмо открывается в обычном
  /// масштабе — текст размера из настроек, не меньше; широкие части
  /// листаются вбок, над письмом — «По ширине экрана». Настройка:
  /// «Почта → Широкие письма по ширине экрана». Щипок — как раньше.
  static bool fitWide = false;
  static const fitWideKey = 'mail_wide_fit';

  /// Вписывание при первом показе: письмо шире окна по объявленным размерам
  /// и включено «сразу по ширине экрана».
  static int? initialFit(MailHtmlDocument doc, double viewWidth) {
    final dw = doc.declaredWidth;
    return fitWide && dw != null && dw > viewWidth + 8 ? dw : null;
  }

  static String _hex(Color c) {
    int ch(double v) => (v * 255).round().clamp(0, 255);
    return '#${[ch(c.r), ch(c.g), ch(c.b)].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Оформление под тему приложения — отдельным стилем после стилей письма.
  static String _themed(String html, {required bool dark, required Color? pageColor, required double textScale}) {
    final page = pageColor ?? Colors.white;
    // Поля слева и справа — у экрана письма (16 dp, как у шапки и плашек), а
    // не внутри документа: внутренний отступ 14px уменьшался вместе с
    // вписанным широким письмом, и текст стоял левее плашек (10.10.2026).
    final css = StringBuffer('html,body{padding-left:0;padding-right:0;margin-left:0 !important;margin-right:0 !important;}'
        'body{padding:4px 0 12px !important;}'
        // Письма с html,body{height:100%;overflow:hidden} (квитанции,
        // рассылки) обрезались по высоте первого окна WebView: движок
        // сообщал высоту окна, а не письма (замечание 11.10.2026).
        'html,body{height:auto !important;min-height:0 !important;max-height:none !important;'
        'overflow-y:visible !important;}'
        // Подсветка выделенного текста — спокойный синий (как в остальном
        // приложении). В тёмной теме документ инвертируется вместе с ней и
        // получается светлее — на тёмном фоне так и нужно.
        '::selection{background:rgba(47,109,181,.30);}'
        // Центровка (1.5.9): блок по центру (align="center", margin:auto),
        // который шире окна, выходил за обе стороны поровну — левую часть
        // нельзя было даже прокрутить, текст обрезался слева. Тело теперь
        // не уже самого широкого неразрывного блока: лишнее уходит вправо и
        // листается вбок.
        'body{min-width:-webkit-min-content !important;min-width:min-content !important;}');
    // Размер шрифта письма: на Android — textZoom WebView, на iOS такой
    // настройки нет — масштаб текста задаётся стилем (как «аА» в Safari).
    if (!kIsWeb && Platform.isIOS) {
      final pct = (textScale * 100).round().clamp(80, 300);
      css.write('html,body{-webkit-text-size-adjust:$pct% !important;}');
    }
    if (dark) {
      // Инверсия всего документа: белый фон письма становится цветом
      // страницы, чёрный текст — светлым. Фон задаётся «до инверсии» —
      // обратным к нужному цвету.
      final inv = Color.fromARGB(255, 255 - (page.r * 255).round(),
          255 - (page.g * 255).round(), 255 - (page.b * 255).round());
      css
        ..write('html{filter:invert(1) hue-rotate(180deg);background:${_hex(inv)} !important;}')
        ..write('body{background:transparent !important;}')
        ..write('img,video,picture,svg,canvas,[style*="background-image"],[background]'
            '{filter:invert(1) hue-rotate(180deg);}');
    } else {
      css.write('html,body{background:${_hex(page)} !important;}');
    }
    final tag = '<style id="og-theme">$css</style>';
    final i = html.indexOf('</head>');
    return i < 0 ? '$tag$html' : '${html.substring(0, i)}$tag${html.substring(i)}';
  }
}

class _MailHtmlViewState extends State<MailHtmlView> {
  double _height = 160;

  /// Высота и вписывание уже показанных писем (документ + ширина + шрифт +
  /// тема). Повторное открытие письма показывается сразу нужной высоты, без
  /// ожидания замеров (1.5.6: письмо, открытое минуту назад, снова ждало
  /// секунду).
  static final _layouts = <String, ({double height, int? fit, bool wide})>{};
  static const _layoutsMax = 80;

  /// Высота взята из [_layouts]: письмо можно показывать, как только движок
  /// его загрузил.
  bool _knownLayout = false;

  /// Идёт перезагрузка документа (вписывание по ширине, смена масштаба):
  /// показывать рано.
  bool _reloading = false;

  /// Окно уже разрешено создать ([MailHtmlView.active] был true).
  bool _activated = false;

  String _layoutKey() {
    final h = widget.document.html;
    return '${h.length}:${h.hashCode}|${_viewWidth.round()}|${widget.textScale}|${widget.dark}|$_actualSize';
  }

  void _rememberLayout() {
    if (!_measured || _viewWidth <= 0) return;
    // Высота увеличенного щипком письма — не для следующего открытия: окно
    // откроется в исходном масштабе.
    final z = _zoom;
    if (z != null && (z / _scale - 1).abs() > 0.02) return;
    final k = _layoutKey();
    _layouts.remove(k);
    _layouts[k] = (height: _height, fit: _fitWidth, wide: _wide);
    while (_layouts.length > _layoutsMax) {
      _layouts.remove(_layouts.keys.first);
    }
  }

  /// Письмо показывается, когда WebView загрузил его и высота измерена:
  /// раньше было видно, как документ догружается — меняются высота, цвет,
  /// масштаб (замечание 11.10.2026, видео). До готовности — заглушка цвета
  /// страницы поверх.
  bool _ready = false;

  /// WebView создаётся ближе к концу перехода на экран письма: создание
  /// встроенного окна в начале анимации давало рывки при открытии.
  bool _create = false;
  Animation<double>? _routeAnim;

  /// Доля перехода, после которой окно уже можно создавать (1.5.9). Переход
  /// SlideFade проявляет экран за первые 70 % времени, к этому моменту экран
  /// непрозрачен и стоит в ~3 dp от своего места: последние 90 мс из 300
  /// окно раньше ждало впустую. Если на слабом телефоне заметен рывок в
  /// конце перехода — поднять до 0,8–0,85.
  static const _createAt = 0.7;

  /// Заглушка поверх WebView гаснет без проявления: показ идёт, когда высота
  /// уже устоялась, скрывать нечего (было 100 мс — их и было видно на
  /// скриншоте «бледного» текста).
  static const _coverFade = Duration.zero;

  /// «Поколение» ожидания устоявшейся высоты: новая загрузка документа
  /// отменяет прежнее ожидание.
  int _revealGen = 0;

  /// Ключ документа, с которым создавался WebView (initialData). Документ
  /// мог смениться, пока окно создавалось, — тогда загрузить новый.
  String? _initialHtmlKey;

  /// Окно взято из запасного ([MailWebViewPool]) — письмо в нём уже
  /// загружено (или грузится) с нажатия на строку ленты.
  HeadlessInAppWebView? _adopted;
  bool _adoptChecked = false;
  bool _adoptedLoaded = false;

  void _adoptSpare() {
    if (_adoptChecked) return;
    _adoptChecked = true;
    final t = MailWebViewPool.take(_htmlFor(), textScale: widget.textScale, blockNet: !widget.allowRemoteImages);
    if (t == null) {
      // В замер открытия — почему окно заранее не подошло.
      if (MailWebViewPool.enabled && MailWebViewPool.supported) OpenTrace.mark('заранее нет: ${MailWebViewPool.lastMiss}');
      return;
    }
    _adopted = t.view;
    _adoptedLoaded = t.loaded;
    final h = t.height;
    if (t.measured && h != null) {
      _height = h;
      _measured = true;
      _knownLayout = true;
    }
    OpenTrace.mark('заранее');
  }

  /// Вписывание по фактической ширине — один раз на документ: повторные
  /// перезагрузки давали «прыжки» и уменьшали письмо раз за разом.
  bool _refitted = false;


  /// Высота уже измерена для текущего документа. Документ WebView не бывает
  /// ниже самого WebView, а масштаб, которым Android вписывает широкое письмо,
  /// чуть отличается от расчётного: каждое повторное измерение возвращало
  /// высоту на ~1 % больше прежней, и граница письма «уезжала» вниз на
  /// несколько десятков точек при неизменном тексте (замечание 08.10.2026).
  bool _measured = false;
  final List<Timer> _timers = [];
  InAppWebViewController? _web;

  /// Ширина экрана для письма (логические пиксели).
  double _viewWidth = 0;

  /// Ширина вёрстки, под которую письмо вписано; null — обычный масштаб.
  int? _fitWidth;

  /// Пользователь выбрал «100 %» — не вписывать.
  bool _actualSize = false;

  /// Письмо шире экрана (кнопка масштаба нужна).
  bool _wide = false;

  /// Ширина вёрстки письма, под которую его вписывать (объявленная или, на
  /// iOS, фактическая), — даже если сейчас письмо помещается: после
  /// поворота в портрет оно может перестать помещаться (1.5.10). Раньше
  /// «По ширине экрана» после «100 %» брало только объявленную ширину, и
  /// письмо, вписанное по фактической (iOS), не вписывалось обратно.
  int? _fitTarget;

  /// Фактический масштаб окна (Android: CSS-пиксели → точки экрана), как его
  /// сообщил движок; null — ещё не сообщал, считается [_scale]. Нужен для
  /// щипка: увеличенное письмо выше окна, а прокрутка по вертикали внутри
  /// окна выключена — без пересчёта высоты низ письма обрезался (1.5.10).
  double? _zoom;

  /// Масштаб, при котором измерена [_height] (0 — неизвестен).
  double _heightZoom = 0;
  Timer? _zoomTimer;

  /// Письмо увеличено щипком (1.8.0): над письмом — «Обычный размер».
  bool _pinched = false;
  /// Плотность экрана: [_dpr] — настоящая (масштаб WebView на Android
  /// задан в ней), [_mqDpr] — с учётом масштаба интерфейса (UiZoom):
  /// точек экрана на единицу вёрстки.
  double _dpr = 1;
  double _mqDpr = 1;

  /// Письмо уже показывалось (onShown — один раз: после поворота письмо
  /// перезагружается и показывается снова).
  bool _shownOnce = false;

  /// Ширина, на которую надо перестроить письмо (поворот, разделённый экран,
  /// складной телефон), — ждёт кадра.
  double? _pendingWidth;

  double get _effScale => _zoom ?? _scale;

  double get _scale => _fitWidth == null || _viewWidth <= 0 ? 1 : _viewWidth / _fitWidth!;

  String _htmlFor() {
    final w = _fitWidth;
    // Документ собирается один раз на ширину вписывания: страница
    // перестраивается при каждом замере высоты, а строка письма с
    // картинками — мегабайты.
    final key = '${identityHashCode(widget.document)}|$w|${_viewWidth.round()}|${_scale.toStringAsFixed(4)}|${widget.dark}|'
        '${widget.inlineRaw != null}|'
        '${widget.textScale}|${widget.pageColor}';
    final cached = _htmlMemo;
    if (cached != null && cached.$1 == key) return cached.$2;
    final out = MailHtmlView.composeHtml(widget.document,
        viewWidth: _viewWidth,
        fitWidth: w,
        dark: widget.dark,
        pageColor: widget.pageColor,
        textScale: widget.textScale,
        cidByRequest: widget.inlineRaw != null);
    _htmlMemo = (key, out);
    return out;
  }

  (String, String)? _htmlMemo;


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchTransitions();
    if (_create) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed || anim.value >= _createAt) {
      _create = true;
      return;
    }
    if (!identical(anim, _routeAnim)) {
      _routeAnim?.removeListener(_onRouteTick);
      _routeAnim = anim..addListener(_onRouteTick);
    }
  }

  /// Значение анимации перехода, а не её статус: окно создаётся на
  /// [_createAt] перехода, а не после его последнего кадра.
  void _onRouteTick() {
    final a = _routeAnim;
    if (a == null || _create || !mounted) return;
    if (a.value < _createAt && a.status != AnimationStatus.completed) return;
    a.removeListener(_onRouteTick);
    _routeAnim = null;
    OpenTrace.mark('окно');
    setState(() => _create = true);
  }

  @override
  void didUpdateWidget(MailHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Тот же документ, но с подставленными картинками (встроенные картинки
    // пришли после показа текста): загружаем его в то же окно, а не
    // создаём WebView заново — раньше ради этого текст держали до 1,5 с
    // (1.5.9). Высота письма сохраняется, замеры её только увеличат.
    final rawChanged = widget.inlineRaw != null && !identical(oldWidget.inlineRaw, widget.inlineRaw);
    if (rawChanged ||
        (!identical(oldWidget.document, widget.document) && oldWidget.document.html != widget.document.html)) {
      final c = _web;
      if (c != null) {
        _reloading = true;
        unawaited(c
            .loadData(data: _htmlFor(), mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'))
            .catchError((Object _) {}));
        // Снимок — заново, уже с картинками.
        _snap = null;
        _scheduleSnap();
      }
    }
  }

  void _markReady() {
    if (_ready || !mounted) return;
    setState(() => _ready = true);
    if (!_shownOnce) {
      _shownOnce = true;
      OpenTrace.done();
      widget.onShown?.call();
    }
    _scheduleSnap();
  }

  // ── Снимок окна на время перехода (1.5.9) ──
  // Пока окно браузера (гибридная композиция) на экране, кадры Flutter
  // собираются на главном потоке Android, и анимации перехода — «назад»,
  // вложение, ответ поверх письма — дёргаются. На время перехода окно
  // скрывается (Offstage: само окно и письмо в нём живы), а на его месте —
  // снимок верха письма. Снимок — один раз после показа, в простое;
  // только верх письма (до полутора экранов) и в уменьшенном размере: память
  // и работа главного потока Android — на один кадр, не на каждый переход.
  Uint8List? _snap;
  Timer? _snapTimer;
  bool _covered = false;
  Animation<double>? _ownAnim;
  Animation<double>? _overAnim;

  void _scheduleSnap() {
    _snapTimer?.cancel();
    _snapTimer = Timer(const Duration(milliseconds: 1200), () => unawaited(_takeSnap()));
  }

  Future<void> _takeSnap() async {
    final c = _web;
    if (c == null || !mounted || _covered || _viewWidth <= 0 || _height <= 0) return;
    final screenH = MediaQuery.sizeOf(context).height;
    final h = _height < screenH * 1.5 ? _height : screenH * 1.5;
    try {
      final bytes = await c.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          rect: InAppWebViewRect(x: 0, y: 0, width: _viewWidth, height: h),
          snapshotWidth: _viewWidth * 0.75,
          compressFormat: CompressFormat.JPEG,
          quality: 70,
        ),
      );
      // Пустой снимок (на некоторых телефонах окно гибридной композиции
      // рисуется в снимок белым) сжимается в единицы килобайт — такой
      // снимок хуже, чем рывок: не использовать.
      if (!mounted || bytes == null || bytes.length < 6000) return;
      _snap = bytes;
    } catch (_) {}
  }

  void _watchTransitions() {
    final route = ModalRoute.of(context);
    final own = route?.animation;
    final over = route?.secondaryAnimation;
    if (!identical(own, _ownAnim)) {
      _ownAnim?.removeStatusListener(_onTransition);
      _ownAnim = own?..addStatusListener(_onTransition);
    }
    if (!identical(over, _overAnim)) {
      _overAnim?.removeStatusListener(_onTransition);
      _overAnim = over?..addStatusListener(_onTransition);
    }
  }

  /// Уход с экрана («назад») или экран поверх письма — окно скрыть;
  /// вернулись — показать.
  void _onTransition(AnimationStatus _) {
    if (!mounted) return;
    final leaving = _ownAnim?.status == AnimationStatus.reverse;
    final over = _overAnim?.status;
    // Без снимка не скрывать (1.5.10): на месте письма было пустое поле
    // цвета страницы (снимок ещё не сделан — первые 1,2 с после показа — или
    // не удался).
    final covered = _ready && _web != null && _snap != null &&
        (leaving || (over != null && over != AnimationStatus.dismissed));
    if (covered != _covered) setState(() => _covered = covered);
  }

  @override
  void dispose() {
    _ownAnim?.removeStatusListener(_onTransition);
    _overAnim?.removeStatusListener(_onTransition);
    _snapTimer?.cancel();
    _zoomTimer?.cancel();
    _routeAnim?.removeListener(_onRouteTick);
    _revealGen++;
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  /// Замер, который уже идёт: таймеры ждут его, а не запускают второй
  /// (два замера подряд могли дважды перезагрузить документ).
  Future<void>? _inFlight;

  Future<void> _measure(InAppWebViewController c) {
    final f = _inFlight;
    if (f != null) return f;
    final n = _measureNow(c).whenComplete(() => _inFlight = null);
    _inFlight = n;
    return n;
  }

  Future<void> _measureNow(InAppWebViewController c) async {
    try {
      // Ширина содержимого: вёрстка без объявленных размеров тоже бывает шире
      // экрана — тогда письмо вписывается по фактической ширине.
      // Только iOS: на Android плагин узнаёт ширину через evaluateJavascript,
      // а JavaScript в окне выключен — Blink скрипт не выполняет, ответ
      // всегда null. Вызов был лишним походом в процесс Chromium в каждом
      // замере (1.5.9). На Android ширину даёт declaredWidth.
      if (Platform.isIOS && !_actualSize && !_refitted && _viewWidth > 0) {
        final cw = await c.getContentWidth();
        final layout = _fitWidth?.toDouble() ?? _viewWidth;
        if (cw != null && cw > layout + 8 && cw < 6000) {
          if (!mounted) return;
          if (!MailHtmlView.fitWide) {
            // Шире экрана — в обычном масштабе с кнопкой (1.5.11).
            setState(() {
              _refitted = true;
              _wide = true;
              _fitTarget = cw;
              _actualSize = true;
            });
          } else {
          setState(() {
            _refitted = true;
            _wide = true;
            _fitWidth = cw;
            _fitTarget = cw;
            _measured = false;
            _reloading = true;
          });
          await c.loadData(data: _htmlFor(), mimeType: 'text/html', encoding: 'utf-8',
              baseUrl: WebUri('about:blank'));
          return;
          }
        }
      }
      final h = await c.getContentHeight();
      if (!mounted || h == null || h <= 0) return;
      // Android отдаёт высоту в CSS-пикселях — на экране она умножается на
      // масштаб; iOS — уже в экранных точках.
      final v = (h * (Platform.isAndroid ? _effScale : 1)).toDouble().clamp(40.0, 60000.0);
      final grow = v - _height;
      // Небольшой рост после первого измерения — эффект самого измерения, а
      // не содержимого; картинки и раскрытые блоки дают заметно больше.
      if (_measured && grow > 0 && grow < _height * 0.05 + 8) return;
      // До показа письма высота может и уменьшаться (заглушка выше письма),
      // после — только расти: уменьшение на глазах выглядело рывком.
      if (_measured && _ready && grow < 0) return;
      _measured = true;
      if (grow.abs() > 2) setState(() => _height = v);
      _heightZoom = _effScale;
      _rememberLayout();
    } catch (_) {}
  }

  /// «Обычный размер» (1.8.0): письмо — в исходном масштабе, как при
  /// открытии (документ перезагружается: другого способа вернуть масштаб без
  /// JavaScript у окна нет).
  Future<void> _resetZoom() async {
    final c = _web;
    if (c == null) return;
    setState(() {
      _pinched = false;
      _zoom = null;
      _heightZoom = 0;
      _snap = null;
      _measured = false;
      _knownLayout = false;
      _reloading = true;
    });
    await c.loadData(data: _htmlFor(), mimeType: 'text/html', encoding: 'utf-8',
        baseUrl: WebUri('about:blank'));
  }

  /// «100 %» ↔ «По ширине экрана».
  Future<void> _toggleScale() async {
    final c = _web;
    if (c == null) return;
    setState(() {
      _actualSize = !_actualSize;
      _fitWidth = _actualSize ? null : _fitTarget;
      _pinched = false;
      _zoom = null;
      _heightZoom = 0;
      // Снимок прежнего масштаба больше не годится.
      _snap = null;
      _measured = false;
      _knownLayout = false;
      _reloading = true;
    });
    await c.loadData(data: _htmlFor(), mimeType: 'text/html', encoding: 'utf-8',
        baseUrl: WebUri('about:blank'));
  }

  void _scheduleMeasures(InAppWebViewController c) {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _reloading = false;
    // Письмо — с левого края (1.5.9): Android сохранял сдвиг вбок от
    // прежнего документа и масштаба (перезагрузка с картинками, «100 %» ↔
    // «по ширине») и сдвигал страницу к центру при смене масштаба.
    // scrollTo — родной вызов WebView, JavaScript не нужен.
    unawaited(_toLeft(c));
    // Высота известна с прошлого открытия — показываем сразу, замеры идут
    // следом и при нужде поправят высоту.
    if (_knownLayout) _markReady();
    // Показ — как только высота устоялась (обычно 1–2 кадра), а не через
    // фиксированные 70 мс (1.5.9).
    unawaited(_revealWhenStable(c));
    // Картинки и шрифты меняют высоту уже после onLoadStop: поздние замеры
    // ловят догрузившиеся картинки и страхуют показ.
    for (final ms in const [250, 800, 2000, 5000]) {
      _timers.add(Timer(Duration(milliseconds: ms), () async {
        await _measure(c);
        if (!_reloading) _markReady();
      }));
    }
  }

  Future<void> _toLeft(InAppWebViewController c) async {
    try {
      await c.scrollTo(x: 0, y: 0);
    } catch (_) {}
  }

  /// Ждать, пока высота документа перестанет меняться, и показать письмо.
  ///
  /// onLoadStop на Android — это onPageFinished: он приходит по событию load
  /// и не ждёт кадра, а высоту содержимого WebView узнаёт только с кадрами
  /// компоновщика (AwContents.updateScrollState). Поэтому первый замер бывает
  /// устаревшим — раньше от этого спасала пауза 70 мс «с запасом». Теперь
  /// высота меряется каждый кадр, пока два замера подряд не совпадут.
  /// Значение, равное высоте самого окна, может быть ещё прежним — ему нужно
  /// совпасть дольше. Не больше 8 кадров: дальше страхуют таймеры.
  Future<void> _revealWhenStable(InAppWebViewController c) async {
    final gen = ++_revealGen;
    int? prev;
    var same = 0;
    for (var i = 0; i < 8; i++) {
      if (!mounted || gen != _revealGen || _reloading) return;
      int? h;
      try {
        h = await c.getContentHeight();
      } catch (_) {}
      if (!mounted || gen != _revealGen) return;
      if (h != null && h > 0 && h == prev) {
        same++;
        final v = h * (Platform.isAndroid ? _effScale : 1);
        final likeWindow = (v - _height).abs() <= 2;
        if (!likeWindow || same >= 2) break;
      } else {
        same = 0;
      }
      prev = h;
      await SchedulerBinding.instance.endOfFrame;
    }
    if (!mounted || gen != _revealGen || _reloading) return;
    await _measure(c);
    if (!mounted || gen != _revealGen || _reloading) return;
    _markReady();
  }

  /// Прозрачная картинка 1×1 (GIF) — для `cid:`, которой ещё нет: без
  /// значка «картинка не загрузилась».
  static final _blankGif = Uint8List.fromList(const [
    0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00, 0x00, 0x00,
    0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3b,
  ]);

  /// Картинка `cid:` для окна; не `cid:` — null (запрос идёт своим путём:
  /// документ письма, заблокированная сеть).
  WebResourceResponse? _cidResponse(WebUri? url) {
    final raw = widget.inlineRaw;
    if (raw == null || url == null) return null;
    final s = url.toString();
    if (!s.toLowerCase().startsWith('cid:')) return null;
    var cid = s.substring(4).trim();
    try {
      cid = Uri.decodeComponent(cid);
    } catch (_) {}
    if (cid.startsWith('<') && cid.endsWith('>')) cid = cid.substring(1, cid.length - 1);
    final img = raw[cid.toLowerCase()];
    return img == null
        ? WebResourceResponse(contentType: 'image/gif', data: _blankGif)
        : WebResourceResponse(contentType: img.mime, data: img.data);
  }

  static bool _isLocal(Uri? u) {
    final s = u?.scheme.toLowerCase() ?? '';
    return s.isEmpty || s == 'about' || s == 'data';
  }

  /// Ширина окна письма изменилась: разметить и вписать письмо заново под
  /// новую ширину (1.5.10). Высота — заведомо не больше будущей (документ
  /// WebView не бывает ниже окна: завышенную высоту замер не уменьшил бы),
  /// замеры её поднимут; до показа — заглушка цвета страницы, без видимой
  /// перестройки письма.
  void _onWidthChanged() {
    final w = _pendingWidth;
    _pendingWidth = null;
    if (!mounted || w == null || (w - _viewWidth).abs() <= 1 || _viewWidth <= 0) return;
    final r = w / _viewWidth;
    setState(() {
      _viewWidth = w;
      _pinched = false;
      _zoom = null;
      _heightZoom = 0;
      _snap = null;
      _snapTimer?.cancel();
      final known = _layouts[_layoutKey()];
      if (known != null) {
        _height = known.height;
        _fitWidth = known.fit;
        _wide = known.wide;
        _measured = true;
        _knownLayout = true;
      } else {
        final t = _fitTarget;
        final wasWide = _wide;
        _wide = t != null && t > w + 8;
        // Стало широким после поворота — по правилу открытия (1.5.11).
        if (_wide && !wasWide) _actualSize = !MailHtmlView.fitWide;
        _fitWidth = _wide && !_actualSize ? t : null;
        _height = (_height * (r < 1 ? r : 1 / r)).clamp(40.0, 60000.0);
        _measured = false;
        _knownLayout = false;
      }
    });
    final c = _web;
    // Окна ещё нет — оно создастся сразу под новую ширину (_htmlFor).
    if (c == null) return;
    setState(() {
      _ready = false;
      _reloading = true;
    });
    unawaited(c
        .loadData(data: _htmlFor(), mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'))
        .catchError((Object _) {}));
  }

  /// Масштаб окна изменился после показа (щипок, двойное нажатие): высота —
  /// под новый масштаб. Android: содержимое при щипке не перестраивается, его
  /// высота меняется ровно в отношении масштабов; замер здесь не помог бы —
  /// после уменьшения документ не ниже окна. iOS отдаёт высоту уже в точках
  /// экрана — там просто замер.
  void _onZoomed(InAppWebViewController c, double newScale) {
    if (Platform.isAndroid) {
      final z = newScale / _dpr;
      if (z > 0.05 && z < 10) _zoom = z;
    }
    // Увеличено относительно исходного масштаба — показать «Обычный размер».
    final zs = Platform.isAndroid ? newScale / _dpr : newScale;
    final pinched = zs > _scale * 1.02;
    if (pinched != _pinched && mounted) setState(() => _pinched = pinched);
    _zoomTimer?.cancel();
    _zoomTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final z = _zoom;
      if (Platform.isAndroid && z != null && _heightZoom > 0 && (z / _heightZoom - 1).abs() > 0.01) {
        // Окно не выше ~30 000 точек экрана: выше Android его не рисует
        // (письмо пропадало после щипка, 13.10.2026).
        final maxH = 30000 / (_mqDpr <= 0 ? 1 : _mqDpr);
        setState(() => _height = (_height * z / _heightZoom).clamp(40.0, maxH < 2000 ? 2000.0 : maxH));
        _heightZoom = z;
      } else if (!Platform.isAndroid) {
        _measured = false;
      }
      unawaited(_measure(c));
      _snap = null;
      _scheduleSnap();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active) _activated = true;
    return LayoutBuilder(builder: (context, box) {
      _mqDpr = MediaQuery.devicePixelRatioOf(context);
      _dpr = View.maybeOf(context)?.devicePixelRatio ?? _mqDpr;
      if (_viewWidth > 0 && box.maxWidth.isFinite && (box.maxWidth - _viewWidth).abs() > 1) {
        // Поворот экрана, разделённый экран, складной телефон (1.5.10):
        // раньше ширина запоминалась один раз, и после поворота письмо
        // оставалось размеченным и вписанным под прежнюю ширину — узкой
        // полосой слева в альбомной ориентации или обрезанным справа в
        // портретной, с высотой от прежней ширины.
        final first = _pendingWidth == null;
        _pendingWidth = box.maxWidth;
        if (first) WidgetsBinding.instance.addPostFrameCallback((_) => _onWidthChanged());
      }
      if (_viewWidth == 0 && box.maxWidth.isFinite) {
        _viewWidth = box.maxWidth;
        _fitTarget = widget.document.declaredWidth;
        // Широкое письмо — в обычном масштабе, пока не включено «сразу по
        // ширине экрана» (1.5.11).
        final dw0 = _fitTarget;
        if (dw0 != null && dw0 > _viewWidth + 8 && !MailHtmlView.fitWide) _actualSize = true;
        final known = _layouts[_layoutKey()];
        if (known != null) {
          // Письмо уже показывали на этой ширине: высота и вписывание —
          // сразу, без перезагрузки документа по ширине.
          _height = known.height;
          _fitWidth = known.fit;
          _wide = known.wide;
          _fitTarget = known.fit ?? _fitTarget;
          _refitted = true;
          _measured = true;
          _knownLayout = true;
        } else {
          final dw = widget.document.declaredWidth;
          if (dw != null && dw > _viewWidth + 8) {
            _wide = true;
            if (!_actualSize) _fitWidth = dw;
          }
        }
      }
      final l10n = AppLocalizations.of(context);
      final fitLabel = l10n.tr('mailFitToWidth');
      final realLabel = l10n.tr('mailActualSize');
      // Переключатель масштаба — строкой под письмом, а не кружком в углу
      // поверх текста (он закрывал начало строк; замечание 06.10.2026).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Над письмом (1.5.10): под длинным письмом кнопка уезжала вниз,
          // до неё приходилось листать всё письмо.
          if (_pinched)
            // Увеличено щипком (1.8.0) — назад к исходному масштабу.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _resetZoom,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(AppIcons.fit_screen, size: 18),
                label: Text(l10n.tr('mailZoomReset')),
              ),
            )
          else if (_wide)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _toggleScale,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: Icon(_actualSize ? AppIcons.fit_screen : AppIcons.zoom_in, size: 18),
                label: Text(_actualSize ? fitLabel : realLabel),
              ),
            ),
          _webView(),
        ],
      );
    });
  }

  Widget _webView() {
    final cover = widget.pageColor ?? Theme.of(context).colorScheme.surface;
    if (!_create || !_activated) return SizedBox(height: _height, child: ColoredBox(color: cover));
    // До SizedBox: высота, измеренная в запасном окне, — сразу в этой сборке.
    _adoptSpare();
    return SizedBox(
      height: _height,
      child: Stack(children: [
        // Окно скрыто на время перехода (не удаляется: письмо в нём живо).
        Positioned.fill(child: Offstage(offstage: _covered, child: _inAppWebView())),
        if (_covered)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: cover,
                child: _snap == null
                    ? null
                    : Align(
                        alignment: Alignment.topCenter,
                        // По ширине с сохранением пропорций (1.6.2): при
                        // fill снимок, снятый другим размером (до смены
                        // масштаба письма), растягивался по высоте.
                        child: Image.memory(_snap!,
                            width: _viewWidth, fit: BoxFit.fitWidth, alignment: Alignment.topCenter,
                            gaplessPlayback: true),
                      ),
              ),
            ),
          ),
        // Заглушка до готовности письма — без мигания догрузки.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: _coverFade,
              child: ColoredBox(color: cover),
            ),
          ),
        ),
      ]),
    );
  }

  /// Порог сдвига прокрутки экрана (системный) — для распознавателей окна.
  double _touchSlop = kTouchSlop;

  /// Листать письмо вбок есть что: «Исходный масштаб» у широкого письма или
  /// письмо увеличено щипком. Иначе жест вбок — листанию писем беседы.
  bool _canPanSideways() {
    if (!Platform.isAndroid) return true;
    if (_actualSize && _wide) return true;
    final z = _zoom;
    return z != null && z > _scale * 1.02;
  }

  Widget _inAppWebView() {
    final blockNet = !widget.allowRemoteImages;
    _touchSlop = MediaQuery.gestureSettingsOf(context).touchSlop ?? kTouchSlop;
    final html = _htmlFor();
    _initialHtmlKey ??= _htmlMemo?.$1;
    return InAppWebView(
        // Запасное окно с уже загруженным письмом (этап 2): плагин передаёт
        // созданный WebView виджету, initialData тогда не загружается.
        headlessWebView: _adopted,
        initialData: InAppWebViewInitialData(
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
          baseUrl: WebUri('about:blank'),
        ),
        initialSettings: MailHtmlView._settings(
            blockNet: blockNet, textScale: widget.textScale, cidByRequest: widget.inlineRaw != null),
        // Горизонтальные жесты — WebView (широкие таблицы), вертикальные —
        // прокрутке экрана письма. Щипок двумя пальцами — масштаб письма, долгое
        // нажатие — выделение текста и «Копировать»: раньше оба жеста забирала
        // прокрутка экрана, и письмо нельзя было ни увеличить, ни скопировать.
        //
        // 1.5.10 (замечание 12.10.2026: «нельзя изменить масштаб пальцами и
        // промотать вбок, выделение — через 2–3 с»): окно получает касание,
        // только когда его распознаватель выиграл у прокрутки экрана и
        // листания писем беседы. У них порог сдвига — системный (на Android
        // ~8 точек), у распознавателей окна был стандартный Flutter (18) —
        // прокрутка и листание выигрывали почти всегда. Теперь:
        //  · два пальца — сразу окну, без порогов (_TwoFingerGestureRecognizer);
        //  · вбок — окну с порогом меньше системного, но только когда
        //    листать вбок есть что («Исходный масштаб» у широкого письма или
        //    письмо увеличено), иначе вбок листаются письма беседы;
        //  · долгое нажатие — окну через 250 мс (было 500 мс, и ещё столько
        //    же ждёт само окно, а при настройке «Задержка нажатия и
        //    удержания» в спецвозможностях — до 1,5 с).
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<_TwoFingerGestureRecognizer>(() => _TwoFingerGestureRecognizer()),
          Factory<HorizontalDragGestureRecognizer>(() => _SidewaysPanRecognizer(_canPanSideways)
            ..gestureSettings = DeviceGestureSettings(touchSlop: _touchSlop * 0.75)),
          Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
          Factory<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 250))),
        },
        shouldOverrideUrlLoading: (controller, action) async {
          final url = action.request.url;
          // Сам документ письма грузится как about:blank/data.
          if (_isLocal(url)) return NavigationActionPolicy.ALLOW;
          // Переход по нажатию пользователя — открываем через приложение с
          // проверкой домена. Без нажатия (meta refresh, редирект) — отменяем.
          final byUser = action.navigationType == NavigationType.LINK_ACTIVATED ||
              (action.hasGesture ?? false);
          if (byUser && url != null) {
            final s = url.toString();
            widget.onLink(s, widget.document.linkTexts[s]);
          }
          return NavigationActionPolicy.CANCEL;
        },
        onCreateWindow: (controller, action) async => false,
        // Встроенные картинки по запросу окна (1.5.9). Обработчики заданы,
        // только когда режим включён: заданный обработчик сам включает
        // перехват всех запросов окна.
        shouldInterceptRequest: widget.inlineRaw == null ? null : (controller, request) => _cidResponse(request.url),
        onLoadResourceWithCustomScheme: widget.inlineRaw == null
            ? null
            : (controller, request) {
                final r = _cidResponse(request.url);
                return r == null
                    ? null
                    : CustomSchemeResponse(data: r.data ?? Uint8List(0), contentType: r.contentType ?? 'image/gif');
              },
        onWebViewCreated: (c) {
          _web = c;
          OpenTrace.mark('создано');
          // Движок уже загружен этим окном — прогрев не нужен.
          MailHtmlView._warmed = true;
          final adopted = _adopted;
          if (adopted != null) {
            // Окно из запасного: письмо уже загружено — события загрузки
            // этому виджету не придут, показ — сразу (высота измерена) или
            // по устоявшейся высоте. Ещё грузится — onLoadStop придёт сюда.
            if (_adoptedLoaded || MailWebViewPool.takenLoaded(adopted)) _scheduleMeasures(c);
          } else {
            // Документ сменился, пока окно создавалось (пришли картинки):
            // загрузить актуальный.
            final now = _htmlFor();
            if (_initialHtmlKey != null && _htmlMemo?.$1 != _initialHtmlKey) {
              _reloading = true;
              unawaited(c
                  .loadData(data: now, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'))
                  .catchError((Object _) {}));
            }
          }
          // Подстраховка: письмо показывается, даже если движок не сообщил
          // о загрузке.
          _timers.add(Timer(const Duration(seconds: 3), _markReady));
        },
        // Высота известна — письмо можно показать уже при первой отрисовке.
        onPageCommitVisible: (controller, url) {
          OpenTrace.mark('кадр');
          if (_knownLayout && !_reloading) _markReady();
        },
        onLoadStop: (controller, url) {
          OpenTrace.mark('загрузка');
          _scheduleMeasures(controller);
        },
        // Смена масштаба больше не сбрасывает таймеры показа (раньше 70 мс
        // начинались заново): до показа — заново ждать устоявшейся высоты,
        // после — только замер.
        onZoomScaleChanged: (controller, oldScale, newScale) {
          if (_ready) {
            _onZoomed(controller, newScale);
          } else {
            // Масштаб вписывания, который поставил движок, — для замеров.
            final z = newScale / _dpr;
            if (Platform.isAndroid && z > 0.05 && z < 10) _zoom = z;
            // Масштаб из документа (вписывание) движок ставит вокруг центра —
            // вернуть письмо к левому краю, пока оно не показано.
            unawaited(_toLeft(controller));
            unawaited(_revealWhenStable(controller));
          }
        },
        onPermissionRequest: (controller, request) async =>
            PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
        onGeolocationPermissionsShowPrompt: (controller, origin) async =>
            GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: false),
    );
  }
}

/// Запасное окно браузера для следующего письма (1.5.9, этап 2 разбора
/// задержки открытия).
///
/// Самая дорогая часть показа письма — создание окна WebView, загрузка и
/// вёрстка документа — раньше начиналась, когда экран письма уже выехал.
/// Здесь одно невидимое окно (HeadlessInAppWebView, ширина тела × 1 px)
/// держится наготове с теми же настройками, что у [MailHtmlView]. На нажатии
/// строки ленты в него загружается документ письма (тот же, что соберёт
/// экран: [MailHtmlView.composeHtml]) и меряется высота — пока идёт переход.
/// Экран письма забирает окно уже загруженным ([take]): плагин передаёт
/// созданный Android-WebView виджету без повторной загрузки.
///
/// Только Android (там создание окна гибридной композиции дорогое) и только
/// для писем без внешних картинок с тем же размером шрифта — иначе обычный
/// путь. Любая ошибка — тоже обычный путь. Выключатель — «Настройки → Почта →
/// Открытие писем → Окно письма заранее».
class MailWebViewPool {
  MailWebViewPool._();

  /// Выключатель (настройка); выключение закрывает запасное окно.
  static bool enabled = true;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static HeadlessInAppWebView? _spare;
  static Future<void>? _creating;
  static double _width = 0;
  static double _textScale = 1;

  /// Документ, загруженный (или загружаемый) в запасное окно.
  static String? _html;
  static bool _loaded = false;
  static double? _height;
  static double _heightScale = 1;
  static int _gen = 0;

  /// Событие загрузки документа уже пришло (высота может ещё измеряться).
  static bool _loadStopped = false;

  /// Сеть окна заблокирована (картинки из интернета не грузятся).
  static bool _blockNet = true;

  /// Почему последнее окно не подошло экрану письма — в замер открытия.
  static String lastMiss = '';

  /// Окно, которое забрал экран письма, и пришла ли его загрузка до того,
  /// как виджет принял события окна на себя.
  static HeadlessInAppWebView? _taken;
  static bool _takenLoaded = false;

  /// Загрузка забранного окна закончилась ещё до того, как виджет начал
  /// получать события (иначе onLoadStop придёт самому виджету).
  static bool takenLoaded(HeadlessInAppWebView v) => identical(v, _taken) && _takenLoaded;

  /// Создать запасное окно (в простое: после показа ленты, после того как
  /// прежнее забрал экран письма).
  static Future<void> ensureSpare({required double width, required double textScale}) {
    if (!enabled || !supported || width <= 0) return Future<void>.value();
    final h = _spare;
    if (h != null && _textScale == textScale) {
      if ((_width - width).abs() < 0.5) return Future<void>.value();
      _width = width;
      _html = null;
      return h.setSize(Size(width, 1)).catchError((Object _) {});
    }
    return _creating ??= _create(width, textScale).whenComplete(() => _creating = null);
  }

  static Future<void> _create(double width, double textScale) async {
    await release();
    final blank = Completer<void>();
    late final HeadlessInAppWebView h;
    h = HeadlessInAppWebView(
      initialSize: Size(width, 1),
      initialData: InAppWebViewInitialData(
        data: '<!DOCTYPE html><html><body></body></html>',
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: MailHtmlView._settings(blockNet: true, textScale: textScale),
      // Документ письма грузится как about:blank; любой переход без
      // нажатия (meta refresh) — отменяется, как и в самом окне письма.
      shouldOverrideUrlLoading: (c, action) async => _MailHtmlViewState._isLocal(action.request.url)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      onCreateWindow: (c, action) async => false,
      onPermissionRequest: (c, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
      onLoadStop: (c, url) {
        if (!blank.isCompleted) {
          blank.complete();
          return;
        }
        if (identical(h, _taken)) {
          // Окно уже забрано, виджет ещё не принял события.
          _takenLoaded = true;
          return;
        }
        if (!identical(h, _spare) || _html == null) return;
        _loadStopped = true;
        unawaited(_onLoaded(c));
      },
    );
    final sw = Stopwatch()..start();
    try {
      await h.run();
      await blank.future.timeout(const Duration(seconds: 5));
      AppLogger.info('Окно письма заранее готово за ${sw.elapsedMilliseconds} мс');
      _spare = h;
      _width = width;
      _textScale = textScale;
      _blockNet = true;
      _html = null;
      _loaded = false;
      _height = null;
      // Движок загружен этим окном — прогрев не нужен.
      MailHtmlView._warmed = true;
    } catch (e) {
      AppLogger.warning('Окно письма заранее не создано: $e');
      try {
        await h.dispose();
      } catch (_) {}
    }
  }

  /// Нажатие строки ленты: загрузить документ письма в запасное окно.
  /// [heightScale] — множитель высоты (вписанное широкое письмо на Android
  /// меряется в CSS-пикселях документа).
  static Future<void> preload(String html,
      {required double textScale, required double heightScale, bool blockNet = true, double? width}) async {
    final c = _spare?.webViewController;
    if (!enabled || c == null) {
      OpenTrace.mark('заранее: нет окна');
      return;
    }
    if (_textScale != textScale) {
      OpenTrace.mark('заранее: другой шрифт');
      return;
    }
    if (_html == html && _blockNet == blockNet) return;
    final gen = ++_gen;
    // Ширина экрана сменилась (поворот, 1.5.10) — окно под новую ширину:
    // иначе высота мерилась в окне прежней ширины.
    final sp = _spare;
    if (width != null && width > 0 && sp != null && (_width - width).abs() >= 0.5) {
      _width = width;
      try {
        await sp.setSize(Size(width, 1));
      } catch (_) {}
      if (gen != _gen) return;
    }
    _html = html;
    _loaded = false;
    _loadStopped = false;
    _height = null;
    _heightScale = heightScale;
    OpenTrace.mark('заранее: грузится');
    try {
      // Картинки из интернета разрешены (доверенный отправитель, «Показать
      // изображения», блокировка внешних картинок выключена) — окно тоже
      // должно их грузить (1.5.9: раньше такие письма в окно заранее не
      // попадали, а у внутренней почты отправитель часто доверенный).
      if (_blockNet != blockNet) {
        final st = await c.getSettings();
        if (gen != _gen) return;
        if (st != null) {
          st.blockNetworkImage = blockNet;
          st.blockNetworkLoads = blockNet;
          await c.setSettings(settings: st);
          _blockNet = blockNet;
        }
        if (gen != _gen) return;
      }
      await c.loadData(data: html, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'));
    } catch (_) {
      if (gen == _gen) _html = null;
    }
  }

  /// Загружено: мерить высоту, пока два замера подряд не совпадут. Окно
  /// высотой 1 px — высота содержимого равна высоте письма, а не окна.
  static Future<void> _onLoaded(InAppWebViewController c) async {
    final gen = _gen;
    if (_html == null) return;
    int? prev;
    for (var i = 0; i < 12; i++) {
      int? h;
      try {
        h = await c.getContentHeight();
      } catch (_) {}
      if (gen != _gen) return;
      if (h != null && h > 0 && h == prev) break;
      prev = h;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (gen != _gen) return;
    _loaded = true;
    if (prev != null && prev > 0) _height = (prev * _heightScale).clamp(40.0, 60000.0).toDouble();
  }

  /// Экран письма: забрать окно, если в нём именно этот документ. Окно
  /// перестаёт быть запасным; следующее создаётся в простое.
  static ({HeadlessInAppWebView view, bool loaded, bool measured, double? height})? take(String html,
      {required double textScale, required bool blockNet}) {
    final h = _spare;
    final cur = _html;
    lastMiss = !enabled
        ? 'выключено'
        : h == null
            ? 'нет окна'
            : cur == null
                ? 'не загружалось'
                : _textScale != textScale
                    ? 'другой шрифт'
                    : _blockNet != blockNet
                        ? 'картинки'
                        : cur.length != html.length
                            ? 'другой документ (${cur.length}/${html.length})'
                            : cur != html
                                ? 'другой документ'
                                : !h.isRunning()
                                    ? 'окно закрыто'
                                    : '';
    if (lastMiss.isNotEmpty || h == null) return null;
    final r = (view: h, loaded: _loadStopped, measured: _loaded, height: _height);
    _taken = h;
    _takenLoaded = _loadStopped;
    _spare = null;
    _html = null;
    _loaded = false;
    _loadStopped = false;
    _height = null;
    _gen++;
    final w = _width, ts = _textScale;
    // Следующее запасное окно — в простое: планировщик ждёт конца паузы
    // открытого письма (4 с), создание окна не мешает его показу.
    unawaited(WorkScheduler.instance.run(WorkPriority.idle, () => ensureSpare(width: w, textScale: ts)));
    return r;
  }

  /// Приложение свёрнуто или выключатель выключен — закрыть запасное окно.
  static Future<void> release() async {
    final h = _spare;
    _spare = null;
    _html = null;
    _loaded = false;
    _loadStopped = false;
    _height = null;
    _gen++;
    if (h == null) return;
    try {
      await h.dispose();
    } catch (_) {}
  }
}

/// Второй палец на письме — жест окну сразу, без порогов (щипок): иначе
/// первый палец успевал сдвинуться на системный порог, и прокрутка экрана
/// забирала жест (1.5.10).
class _TwoFingerGestureRecognizer extends OneSequenceGestureRecognizer {
  final Set<int> _down = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) _down.remove(event.pointer);
    stopTrackingIfPointerNoLongerDown(event);
  }

  @override
  void rejectGesture(int pointer) {
    _down.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _down.clear();

  @override
  String get debugDescription => 'two fingers';
}

/// Жест вбок — окну, только когда вбок есть что листать ([canPan]).
class _SidewaysPanRecognizer extends HorizontalDragGestureRecognizer {
  _SidewaysPanRecognizer(this.canPan);

  final bool Function() canPan;

  @override
  bool isPointerAllowed(PointerEvent event) => canPan() && super.isPointerAllowed(event);
}


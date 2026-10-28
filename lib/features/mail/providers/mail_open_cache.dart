// lib/features/mail/providers/mail_open_cache.dart
// Открытие письма без ожидания (1.5.6).
//
// Раньше всё начиналось, когда экран письма уже построен: чтение из базы,
// очистка HTML, отделение цитаты, сборка документа WebView — и каждый раз
// заново, даже для письма, открытого минуту назад. Теперь:
//  · касание строки списка (палец ещё на экране) — письмо читается из базы и
//    готовится в отдельном изоляте; к моменту, когда экран письма построен,
//    обычно всё уже готово;
//  · подготовленные письма (очищенный HTML, ответ и цитата, документ
//    WebView) запоминаются — повторное открытие работу не повторяет;
//  · встроенные картинки (подпись, схемы) читаются из кэша вложений разом,
//    недостающие ActiveSync отдаёт одним запросом; при нажатии на строку их
//    загрузка начинается ещё до перехода на экран письма.
// Всё здесь — только ускорение: экран письма работает и без подготовки.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/security/mail_body_processor.dart';
import '../../../core/utils/work_isolate.dart';
import '../../../core/utils/quote_splitter.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/security/tracker_blocker.dart';
import '../widgets/mail_html_view.dart';
import '../widgets/mail_native_body.dart';
import '../../settings/widgets/feature_settings_sections.dart' show ExperimentalKeys;
import 'mail_providers.dart' show accountsProvider, emailModelFromRow;

final mailOpenCacheProvider = Provider<MailOpenCache>((ref) => MailOpenCache(ref));

/// Письмо, подготовленное к показу: очищенный HTML (с отчётом блокировщика
/// трекеров), ответ и цитата, документ WebView для первого показа (ответ
/// без цитаты или письмо целиком) — без встроенных картинок, они
/// подставляются потом ([MailHtmlDocument.withInlineImages]).
class PreparedMailBody {
  final TrackerBlockResult secured;
  final QuoteSplit split;
  final MailHtmlDocument firstDoc;

  /// Внешние картинки разрешены в документе (CSP).
  final bool remoteImages;

  /// То же, что [firstDoc], для показа без WebView (простое письмо, 1.5.9);
  /// null — письмо сложное, показывается в WebView.
  final NativeMail? native;

  /// Почему письмо показывается в WebView (1.5.10) — в замер открытия.
  final String? nativeWhy;

  const PreparedMailBody({
    required this.secured,
    required this.split,
    required this.firstDoc,
    required this.remoteImages,
    this.native,
    this.nativeWhy,
  });

  int get _chars =>
      secured.html.length + split.reply.length + split.quoted.length + firstDoc.html.length;
}

/// Встроенные картинки письма: Content-ID (без «<>», нижний регистр) →
/// data URI, и вложения, которые показать в тексте нельзя и поэтому они
/// нужны в списке вложений ([failed]: слишком большие, формат, который
/// WebView не показывает). Картинки, не полученные из-за сети или сервера,
/// в [failed] не входят: это подпись или схема из текста, в списке файлов
/// она лишняя, а при следующем открытии загрузится.
class InlineImages {
  final Map<String, String> map;
  final Set<String> failed;

  /// Те же картинки байтами (Content-ID → тип и данные) — для отдачи окну
  /// письма по запросу, без base64 в документе (1.5.9, «Настройки → Почта →
  /// Открытие писем → Картинки письма отдельно»).
  final Map<String, ({String mime, Uint8List data})> raw;
  const InlineImages(this.map, this.failed, {this.raw = const {}});
  static const empty = InlineImages({}, {});
}

class MailOpenCache {
  MailOpenCache(this._ref);
  final Ref _ref;

  static String _key(String accountId, String emailId) => '$accountId|$emailId';

  // ───────────────────────── строка письма ─────────────────────────

  /// Строки, прочитанные заранее (касание строки списка): не старше 3 с —
  /// дальше письмо могло измениться (прочитано, загружен текст).
  final Map<String, ({Future<Email?> future, DateTime at})> _rows = {};
  static const _rowFresh = Duration(seconds: 3);

  /// Строка письма из базы — заранее прочитанная или новым запросом.
  Future<Email?> row(String accountId, String emailId) {
    final k = _key(accountId, emailId);
    final now = DateTime.now();
    final hit = _rows[k];
    if (hit != null && now.difference(hit.at) < _rowFresh) return hit.future;
    final f = _ref.read(databaseProvider).getEmailById(emailId, accountId: accountId);
    // Ошибка чтения — тому, кто ждёт; здесь — только чтобы не было
    // «необработанной ошибки» у заранее запущенного чтения.
    unawaited(f.then((_) {}, onError: (Object _) {}));
    _rows[k] = (future: f, at: now);
    if (_rows.length > 24) _rows.remove(_rows.keys.first);
    return f;
  }

  /// Письмо изменилось в базе (загружен текст, отметки) — читать заново.
  void forgetRow(String accountId, String emailId) => _rows.remove(_key(accountId, emailId));

  /// Приложение свёрнуто: картинки в base64 и строки — больше не нужны;
  /// подготовленные тела — только последние несколько (вернувшись, человек
  /// чаще открывает то же письмо). Меньше памяти в фоне — меньше шансов,
  /// что система выгрузит приложение и push.
  void trim() {
    _images.clear();
    _rows.clear();
    while (_bodies.length > 4) {
      final k = _bodies.keys.first;
      _bodies.remove(k);
      _ready.remove(k);
      _total -= _sizes.remove(k) ?? 0;
    }
  }

  /// Системе не хватает памяти — всё подготовленное заново соберётся при
  /// открытии письма.
  void clear() {
    _images.clear();
    _rows.clear();
    _bodies.clear();
    _ready.clear();
    _sizes.clear();
    _total = 0;
  }

  // ───────────────────────── подготовка тела ─────────────────────────

  final LinkedHashMap<String, Future<PreparedMailBody>> _bodies = LinkedHashMap();
  final Map<String, PreparedMailBody> _ready = {};
  final Map<String, int> _sizes = {};
  var _total = 0;
  static const _maxBodies = 24;
  static const _maxChars = 6 * 1024 * 1024;

  static const _kImagesAllowed = 'images_allowed_msgs';

  static String imagesKey(EmailModel e) => '${e.accountId}|${e.internetMessageId ?? e.id}';

  /// «Показать изображения» для этого письма уже нажимали.
  bool imagesRemembered(EmailModel e) =>
      (_ref.read(sharedPrefsProvider).getStringList(_kImagesAllowed) ?? const <String>[]).contains(imagesKey(e));

  /// Запомнить «Показать изображения» для письма (до 500 писем).
  void rememberImages(EmailModel e) {
    final prefs = _ref.read(sharedPrefsProvider);
    final k = imagesKey(e);
    final list = [k, ...?prefs.getStringList(_kImagesAllowed)?.where((x) => x != k)];
    unawaited(prefs.setStringList(_kImagesAllowed, list.take(500).toList()));
  }

  /// Параметры очистки письма — те же, что у экрана письма.
  ({TrackerBlockOptions options, bool allowImages, String? domain}) optionsFor(EmailModel e,
      {bool allowImages = false}) {
    final domain = e.from.email.contains('@') ? e.from.email.split('@').last : null;
    if (!allowImages && imagesRemembered(e)) allowImages = true;
    final opts = _ref
        .read(trackerBlockerProvider.notifier)
        .options(senderDomain: domain, allowExternalImages: allowImages);
    return (options: opts, allowImages: allowImages, domain: domain);
  }

  static String _bodyKey(String raw, TrackerBlockOptions o, bool remote) {
    final hosts = o.allowedHosts.isEmpty ? '' : (o.allowedHosts.toList()..sort()).join(',');
    return '${mailWebViewSupported ? 1 : 0}|${o.enabled ? 1 : 0}|${o.blockExternal ? 1 : 0}|'
        '${remote ? 1 : 0}|$hosts|${raw.length}|${raw.hashCode}';
  }

  /// Подготовленное тело уже готово (без ожидания).
  PreparedMailBody? peekPrepared(String raw, {required TrackerBlockOptions options, required bool allowImages}) {
    final remote = allowImages || !options.blockExternal;
    return _ready[_bodyKey(raw, options, remote)];
  }

  /// Очистка, цитата и документ WebView — одним заходом в отдельный изолят
  /// (раньше — три разбора письма по очереди, мелкие — на главном потоке,
  /// прямо во время перехода на экран письма).
  Future<PreparedMailBody> prepare(String raw,
      {required TrackerBlockOptions options, required bool allowImages}) {
    final remote = allowImages || !options.blockExternal;
    final k = _bodyKey(raw, options, remote);
    final hit = _bodies.remove(k);
    if (hit != null) {
      _bodies[k] = hit; // свежее — в конец очереди вытеснения
      return hit;
    }
    final f = _run(raw, mailWebViewSupported, options, remote);
    _bodies[k] = f;
    unawaited(f.then((p) {
      if (!_bodies.containsKey(k)) return;
      _ready[k] = p;
      _sizes[k] = p._chars;
      _total += p._chars;
      _evict();
    }, onError: (Object e) {
      _bodies.remove(k);
      AppLogger.debug('Подготовка письма: $e');
    }));
    return f;
  }

  void _evict() {
    while (_bodies.length > _maxBodies || (_total > _maxChars && _bodies.length > 1)) {
      final k = _bodies.keys.first;
      _bodies.remove(k);
      _ready.remove(k);
      _total -= _sizes.remove(k) ?? 0;
    }
  }

  /// Статическая обёртка: замыкание для изолята не должно захватывать
  /// объект с Ref.
  static Future<PreparedMailBody> _run(String raw, bool keepStyles, TrackerBlockOptions o, bool remote) async {
    // Рабочий изолят (1.5.9): без запуска изолята на каждое письмо — порог
    // ниже (было 4 КБ).
    if (kIsWeb || raw.length < 2048) return _prepareSync(raw, keepStyles, o, remote);
    try {
      return await WorkIsolate.interactive.run(() => _prepareSync(raw, keepStyles, o, remote));
    } on UnsupportedError {
      return _prepareSync(raw, keepStyles, o, remote);
    }
  }

  static PreparedMailBody _prepareSync(String raw, bool keepStyles, TrackerBlockOptions o, bool remote) {
    final secured = MailBodyProcessor.processSync(raw, keepStyles: keepStyles, options: o);
    QuoteSplit split;
    try {
      split = splitQuotedHtml(secured.html);
    } catch (_) {
      split = QuoteSplit(secured.html, '');
    }
    final first = split.hasQuote ? split.reply : secured.html;
    final doc = MailHtmlDocument.build(first, allowRemoteImages: remote, keepCid: true);
    // Простое письмо — и для показа без WebView (тот же проход изолята).
    NativeMail? native;
    String? why;
    if (keepStyles) {
      try {
        final r = buildNativeMailWhy(first, remoteImages: remote);
        native = r.mail;
        why = r.why;
      } catch (e) {
        why = 'ошибка разбора';
      }
    }
    return PreparedMailBody(
        secured: secured, split: split, firstDoc: doc, remoteImages: remote, native: native, nativeWhy: why);
  }

  // ───────────────────────── заранее ─────────────────────────

  /// Касание строки списка: прочитать письмо и подготовить его тело.
  /// [images] — нажатие (письмо точно откроют): начать и загрузку
  /// недостающих встроенных картинок с сервера. [body] = false — только
  /// строка из базы: палец на строке ещё не значит, что письмо откроют
  /// (с касания начинается и прокрутка ленты), а подготовка тела — работа
  /// процессора; она начинается при нажатии и успевает за время перехода.
  void prefetch(String accountId, String emailId, {bool images = false, bool body = true}) {
    if (accountId.isEmpty || emailId.isEmpty) return;
    unawaited(() async {
      try {
        final r = await row(accountId, emailId);
        if (r == null || !body) return;
        final e = emailModelFromRow(r);
        final html = e.bodyHtml;
        if (html != null && html.isNotEmpty) {
          final o = optionsFor(e);
          unawaited(prepare(html, options: o.options, allowImages: o.allowImages)
              .then((_) {}, onError: (Object _) {}));
          if (images) unawaited(inlineImages(accountId, e).then((_) {}, onError: (Object _) {}));
        }
      } catch (e) {
        AppLogger.debug('Подготовка письма заранее: $e');
      }
    }());
  }

  /// Свежее письмо вверху ленты — подготовить тело заранее, в простое
  /// (1.5.9; вызывает лента через планировщик с приоритетом prefetch). К
  /// нажатию очистка, цитата и документ WebView уже готовы — письмо
  /// показывается без ожидания подготовки, а окно браузера заранее
  /// (MailWebViewPool) получает документ сразу на нажатии.
  Future<void> warm(String accountId, String emailId) async {
    if (accountId.isEmpty || emailId.isEmpty) return;
    try {
      final r = await row(accountId, emailId);
      if (r == null) return;
      final e = emailModelFromRow(r);
      final html = e.bodyHtml;
      if (html == null || html.isEmpty) return;
      final o = optionsFor(e);
      await prepare(html, options: o.options, allowImages: o.allowImages);
    } catch (e) {
      AppLogger.debug('Подготовка свежего письма: $e');
    }
  }

  /// Нажатие строки ленты (телефон): письмо — в запасное окно браузера,
  /// пока идёт переход (1.5.9, этап 2). Документ собирается так же, как его
  /// соберёт экран письма (первый документ, встроенные картинки — если они
  /// уже на телефоне, разметка по ширине окна и тема): экран узнаёт его по
  /// совпадению строки и забирает окно уже загруженным. Не совпало (другие
  /// картинки, «Показать изображения») — обычный путь.
  void preloadWebView(String accountId, String emailId,
      {required double width, required bool dark, required Color pageColor, required double textScale}) {
    if (!MailWebViewPool.enabled || !MailWebViewPool.supported || width <= 0) return;
    unawaited(() async {
      try {
        final r = await row(accountId, emailId);
        if (r == null) return;
        final e = emailModelFromRow(r);
        final html = e.bodyHtml;
        if (html == null || html.isEmpty) return;
        final o = optionsFor(e);
        final p = await prepare(html, options: o.options, allowImages: o.allowImages);
        // Простое письмо покажется без WebView — окно ему не нужно.
        if (p.native != null && (_ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.nativeMail) ?? true)) return;
        // Картинки из интернета разрешены (письмо, доверенный отправитель,
        // блокировка внешних картинок выключена) — так же, как решит экран
        // письма (_imagesAllowed): окно заранее тогда грузит и их.
        final remote = o.allowImages || !o.options.blockExternal;
        var doc = p.firstDoc;
        if (p.secured.html.toLowerCase().contains('cid:')) {
          if (inlineImagesLocal(accountId, e, html)) {
            final imgs = await inlineImages(accountId, e, rawHtml: html);
            doc = doc.withInlineImages(imgs.map);
          } else {
            doc = doc.withInlineImages(const {});
          }
        }
        final fit = MailHtmlView.initialFit(doc, width);
        final composed = MailHtmlView.composeHtml(doc,
            viewWidth: width, fitWidth: fit, dark: dark, pageColor: pageColor, textScale: textScale);
        await MailWebViewPool.preload(composed,
            textScale: textScale, heightScale: fit == null ? 1.0 : width / fit, blockNet: !remote, width: width);
      } catch (e) {
        AppLogger.debug('Окно письма заранее: $e');
      }
    }());
  }

  // ───────────────────────── встроенные картинки ─────────────────────────

  final Map<String, ({Future<InlineImages> future, DateTime at})> _images = {};
  static const _imagesFresh = Duration(seconds: 20);

  static const maxEach = 3 * 1024 * 1024;
  static const _maxTotal = 12 * 1024 * 1024;

  static String _normCid(String raw) {
    var c = raw.trim().toLowerCase();
    if (c.startsWith('<') && c.endsWith('>')) c = c.substring(1, c.length - 1);
    return c;
  }

  /// Запасная картинка Outlook (VML: .wmz, .emz) — см. EmailAttachment.
  static bool isVmlPreview(EmailAttachment a) => a.isVmlPreview;

  /// Вложение показано в тексте письма (на него ссылается `cid:`).
  static bool embeddedIn(EmailAttachment a, String rawLower) {
    final cid = a.contentId;
    if (cid == null || cid.trim().isEmpty) return false;
    return rawLower.contains('cid:${_normCid(cid)}');
  }

  /// MIME картинки по сигнатуре байтов. Объявленному в письме типу не
  /// верим; SVG (может содержать сценарии) и прочее не допускается.
  static String? imageMimeOf(Uint8List b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
    if (at(0, const [0x42, 0x4D])) return 'image/bmp';
    return null;
  }

  /// Встроенные картинки письма: из кэша вложений разом, недостающие — с
  /// сервера (ActiveSync — одним запросом). [rawHtml] — исходный HTML письма
  /// (по нему видно, какие вложения показаны в тексте).
  Future<InlineImages> inlineImages(String accountId, EmailModel email, {String? rawHtml}) {
    final html = rawHtml ?? email.bodyHtml ?? '';
    // Без длины HTML: исходный и очищенный текст ссылаются на те же cid.
    final k = '${_key(accountId, email.id)}|${email.attachments.length}';
    final now = DateTime.now();
    final hit = _images[k];
    if (hit != null && now.difference(hit.at) < _imagesFresh) return hit.future;
    // Устаревшие записи не нужны (повторно они не выдаются), а держат в
    // памяти картинки в base64 — до 12 МБ на письмо.
    _images.removeWhere((_, v) => now.difference(v.at) >= _imagesFresh);
    final f = _loadImages(accountId, email, html);
    unawaited(f.then((_) {}, onError: (Object _) {}));
    _images[k] = (future: f, at: now);
    if (_images.length > 16) _images.remove(_images.keys.first);
    return f;
  }

  /// Все встроенные картинки письма уже лежат в кэше вложений (проверка без
  /// чтения файлов). Тогда показ текста может их подождать — они придут за
  /// несколько кадров; иначе текст показывается сразу, а картинки
  /// подставляются, когда скачаются (1.5.9). Индекс кэша ещё не прочитан —
  /// «не на телефоне»: лучше показать текст без картинок, чем ждать.
  bool inlineImagesLocal(String accountId, EmailModel email, String rawHtml) {
    final lower = rawHtml.toLowerCase();
    if (!lower.contains('cid:')) return true;
    final cache = _ref.read(attachmentCacheProvider);
    for (final a in email.attachments) {
      if (isVmlPreview(a) || !embeddedIn(a, lower) || (a.size != 0 && a.size > maxEach)) continue;
      if (!cache.has(MailEngineService.attachmentCacheKey(accountId, email.id, a.id))) return false;
    }
    return true;
  }

  Future<InlineImages> _loadImages(String accountId, EmailModel email, String html) async {
    final lower = html.toLowerCase();
    if (!lower.contains('cid:')) return InlineImages.empty;
    final wanted = email.attachments
        .where((a) => !isVmlPreview(a) && embeddedIn(a, lower) && (a.size == 0 || a.size <= maxEach))
        .take(20)
        .toList();
    if (wanted.isEmpty) return InlineImages.empty;
    final cache = _ref.read(attachmentCacheProvider);
    await cache.ensureLoaded();
    final bytes = <String, Uint8List>{};
    final failed = <String>{};
    // Сначала — то, что уже на телефоне («Письма на телефоне» докачивают
    // картинки заранее), разом.
    final paths = await Future.wait([
      for (final a in wanted)
        cache
            .get(MailEngineService.attachmentCacheKey(accountId, email.id, a.id))
            .catchError((Object _) => null),
    ]);
    final missing = <EmailAttachment>[];
    for (var i = 0; i < wanted.length; i++) {
      final p = paths[i];
      if (p == null) {
        missing.add(wanted[i]);
        continue;
      }
      try {
        bytes[wanted[i].id] = await File(p).readAsBytes();
      } catch (_) {
        missing.add(wanted[i]);
      }
    }
    // С сервера — только недостающие, ActiveSync — одним запросом.
    if (missing.isNotEmpty) {
      final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        // Ящика нет — показать нечего; в список вложений не добавляем.
      } else {
        Map<String, Uint8List> got = const {};
        try {
          got = await _ref
              .read(mailEngineServiceProvider)
              .getAttachmentsBytes(account, [for (final a in missing) a.id], emailId: email.id);
        } catch (e) {
          AppLogger.debug('Встроенные картинки письма: $e');
        }
        for (final a in missing) {
          final b = got[a.id];
          // Сеть или сервер (например, HTTP 504): картинка загрузится при
          // следующем открытии; в список вложений её не выносим.
          if (b == null) continue;
          bytes[a.id] = b;
          unawaited(cache
              .put(MailEngineService.attachmentCacheKey(accountId, email.id, a.id), a.name, b)
              .then((_) {}, onError: (Object _) {}));
        }
      }
    }
    final items = <({String cid, Uint8List data})>[];
    var total = 0;
    for (final a in wanted) {
      final b = bytes[a.id];
      if (b == null) continue;
      if (b.length > maxEach || total + b.length > _maxTotal || imageMimeOf(b) == null) {
        failed.add(a.id);
        continue;
      }
      total += b.length;
      items.add((cid: _normCid(a.contentId!), data: b));
    }
    if (items.isEmpty) return InlineImages(const {}, failed);
    // Крупные картинки кодируются вне главного потока.
    final map = total > 512 * 1024 ? await _encodeAsync(items) : _encode(items);
    return InlineImages(map, failed, raw: {for (final i in items) i.cid: (mime: imageMimeOf(i.data)!, data: i.data)});
  }

  static Map<String, String> _encode(List<({String cid, Uint8List data})> items) => {
        for (final i in items) i.cid: 'data:${imageMimeOf(i.data)};base64,${base64Encode(i.data)}',
      };

  static Future<Map<String, String>> _encodeAsync(List<({String cid, Uint8List data})> items) async {
    if (kIsWeb) return _encode(items);
    try {
      return await WorkIsolate.interactive.run(() => _encode(items));
    } on UnsupportedError {
      return _encode(items);
    }
  }
}

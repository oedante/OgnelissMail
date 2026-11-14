// lib/features/mail/widgets/desktop_mail_web_view.dart
// Письмо со сложной вёрсткой на компьютере — во встроенном окне браузера:
// Mac — WKWebView (12.11.2026, план 2026-11 п. 5 «macOS — WebView, как на
// iOS»), Windows — WebView2 (14.11.2026, просьба владельца: «сложные письма
// не отображаются, а предлагают открыть в браузере»).
//
// Документ — тот же, что у окна письма на телефоне и у «Открыть в браузере»
// (MailHtmlDocument + MailHtmlView.composeHtml): HTML уже очищен, в документе
// политика CSP (без скриптов, фреймов, форм; картинки из интернета — только
// когда разрешены), JavaScript в окне выключен, хранилищ нет, переход по
// ссылке отменяется и передаётся приложению.
//
// Отличие от телефона: высоту письма без JavaScript узнать нельзя (плагин
// меряет её скриптом), поэтому окно — заданной высоты и листает письмо само.
// Не загрузилось — [onFailed]: экран показывает письмо, как раньше,
// виджетами.
//
// Windows:
//  · документ строкой WebView2 принимает только до 2 МБ (NavigateToString), а
//    письмо с картинками внутри больше — такое загружается из временного
//    файла (один файл на окно, удаляется при закрытии письма);
//  · плагин рисует WebView2 картинкой и передаёт в него только мышь —
//    клавиатура до окна не доходит; окно не забирает фокус у ленты, иначе
//    стрелки и Delete в ленте переставали бы работать после открытия письма;
//  · WebView2 Runtime нет или окно не загрузилось за [_loadTimeout] —
//    [onFailed].

import 'dart:async';
import 'dart:convert' show utf8;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import 'mail_html_view.dart';

/// Высота окна письма на компьютере по высоте окна приложения [screen]: окно
/// листает письмо само, шапка письма и панель ответа остаются на виду.
double desktopMailWebHeight(double screen) => (screen - 260).clamp(320.0, 2000.0);

/// Документ строкой — не больше этого (байт UTF-8): у WebView2 предел 2 МБ,
/// с запасом на служебное.
const desktopMailInlineLimit = 1800 * 1024;

/// Документ [page] на Windows — из файла: строкой WebView2 его не примет.
bool desktopMailNeedsFile(String page, {required bool windows}) =>
    windows && page.length * 3 > desktopMailInlineLimit && utf8.encode(page).length > desktopMailInlineLimit;

class DesktopMailWebView extends StatefulWidget {
  const DesktopMailWebView({
    super.key,
    required this.html,
    required this.allowRemoteImages,
    required this.height,
    required this.onLink,
    this.inlineImages = const {},
    this.dark = false,
    this.pageColor,
    this.textScale = 1,
    this.onFailed,
  });

  /// Уже очищенный HTML письма.
  final String html;
  final bool allowRemoteImages;

  /// Встроенные картинки: Content-ID → data URI.
  final Map<String, String> inlineImages;
  final double height;
  final bool dark;
  final Color? pageColor;
  final double textScale;
  final void Function(String url, String? linkText) onLink;

  /// Окно не показало письмо (ошибка загрузки, процесс движка завершился,
  /// WebView2 не запустился).
  final VoidCallback? onFailed;

  @override
  State<DesktopMailWebView> createState() => _DesktopMailWebViewState();
}

class _DesktopMailWebViewState extends State<DesktopMailWebView> {
  static const _loadTimeout = Duration(seconds: 10);
  static int _files = 0;

  final bool _windows = !kIsWeb && Platform.isWindows;
  MailHtmlDocument? _doc;
  String? _page;

  /// Временный файл с документом (Windows, документ больше предела строки).
  File? _file;

  /// Нынешний документ — из [_file], а не строкой.
  bool _fromFile = false;
  InAppWebViewController? _web;
  Timer? _watchdog;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(DesktopMailWebView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html ||
        old.allowRemoteImages != widget.allowRemoteImages ||
        old.inlineImages.length != widget.inlineImages.length) {
      unawaited(_prepare());
    } else if (old.dark != widget.dark || old.pageColor != widget.pageColor || old.textScale != widget.textScale) {
      unawaited(_compose());
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    final f = _file;
    if (f != null) unawaited(f.delete().then((_) {}, onError: (Object _) {}));
    super.dispose();
  }

  void _fail(String why) {
    if (_failed) return;
    _failed = true;
    _watchdog?.cancel();
    AppLogger.warning('Письмо в окне (${_windows ? 'Windows' : 'Mac'}): $why');
    if (mounted) widget.onFailed?.call();
  }

  Future<void> _prepare() async {
    final gen = ++_gen;
    try {
      final doc = await MailHtmlDocument.buildAsync(widget.html,
          allowRemoteImages: widget.allowRemoteImages, inlineImages: widget.inlineImages);
      if (!mounted || gen != _gen) return;
      _doc = doc;
      await _compose();
    } catch (e) {
      if (mounted && gen == _gen) _fail('документ не собран — $e');
    }
  }

  /// Документ под тему и размер текста; открытое окно получает его без
  /// пересоздания.
  Future<void> _compose() async {
    final doc = _doc;
    if (doc == null) return;
    final page = MailHtmlView.composeHtml(doc,
        viewWidth: 0, fitWidth: null, dark: widget.dark, pageColor: widget.pageColor, textScale: widget.textScale);
    if (page == _page) return;
    final gen = _gen;
    File? file;
    if (desktopMailNeedsFile(page, windows: _windows)) {
      try {
        file = _file ?? File('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
            'ogneliss-mail-pane-$pid-${_files++}.html');
        await file.writeAsString(page, flush: true);
      } catch (e) {
        _fail('файл документа не записан — $e');
        return;
      }
      if (!mounted || gen != _gen) return;
    }
    final first = _page == null;
    setState(() {
      _page = page;
      _file = file ?? _file;
      _fromFile = file != null;
    });
    if (first) {
      if (_windows) _watchdog = Timer(_loadTimeout, () => _fail('WebView2 не загрузил письмо'));
      return;
    }
    final web = _web;
    if (web == null) return;
    try {
      if (file != null) {
        await web.loadUrl(urlRequest: URLRequest(url: WebUri.uri(file.uri)));
      } else {
        await web.loadData(data: page, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'));
      }
    } catch (_) {}
  }

  /// Адрес самого документа: about:blank, data: или наш временный файл.
  bool _isDocument(Uri? url) {
    if (MailHtmlView.isLocalUrl(url)) return true;
    final f = _file;
    if (f == null || url == null || url.scheme != 'file') return false;
    try {
      return url.toFilePath(windows: _windows).toLowerCase() == f.path.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final file = _file;
    final fromFile = _fromFile && file != null;
    Widget web = page == null
        ? const SizedBox.shrink()
        : InAppWebView(
            initialData: fromFile
                ? null
                : InAppWebViewInitialData(
                    data: page,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                    baseUrl: WebUri('about:blank'),
                  ),
            initialUrlRequest: fromFile ? URLRequest(url: WebUri.uri(file.uri)) : null,
            initialSettings: MailHtmlView.desktopSettings(textScale: widget.textScale),
            onWebViewCreated: (c) => _web = c,
            onLoadStop: (controller, url) => _watchdog?.cancel(),
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url;
              if (_isDocument(url)) return NavigationActionPolicy.ALLOW;
              // Нажатая ссылка — через приложение (проверка домена); переход
              // без нажатия (meta refresh, редирект) — отменяется молча.
              final byUser =
                  action.navigationType == NavigationType.LINK_ACTIVATED || (action.hasGesture ?? false);
              if (byUser && url != null) {
                final s = url.toString();
                widget.onLink(s, _doc?.linkTexts[s]);
              }
              return NavigationActionPolicy.CANCEL;
            },
            onCreateWindow: (controller, action) async => false,
            onPermissionRequest: (controller, request) async =>
                PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
            onReceivedError: (controller, request, error) {
              // Только сам документ: не загрузившаяся картинка — не сбой письма.
              if (request.isForMainFrame ?? false) _fail(error.description);
            },
            onWebContentProcessDidTerminate: (controller) => _fail('процесс WebKit завершился'),
            onRenderProcessGone: (controller, detail) async => _fail('процесс WebView2 завершился'),
          );
    // Windows: фокус у ленты (клавиатура до WebView2 всё равно не доходит).
    if (_windows) web = ExcludeFocus(child: web);
    return SizedBox(height: widget.height, child: web);
  }
}

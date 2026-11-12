// lib/features/mail/widgets/mac_mail_web_view.dart
// Письмо со сложной вёрсткой на Mac — во встроенном окне WKWebView
// (12.11.2026, план 2026-11 п. 5 «macOS — WebView, как на iOS»).
//
// Документ — тот же, что у окна письма на телефоне и у «Открыть в браузере»
// (MailHtmlDocument + MailHtmlView.composeHtml): HTML уже очищен, в документе
// политика CSP (без скриптов, фреймов, форм; картинки из интернета — только
// когда разрешены), JavaScript в окне выключен, хранилищ и файлов нет,
// переход по ссылке отменяется и передаётся приложению.
//
// Отличие от телефона: высоту письма на Mac без JavaScript узнать нельзя
// (плагин меряет её скриптом), поэтому окно — заданной высоты и листает
// письмо само. Не загрузилось — [onFailed]: экран показывает письмо, как
// раньше, виджетами.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/logging/app_logger.dart';
import 'mail_html_view.dart';

/// Высота окна письма на Mac по высоте окна приложения [screen]: окно
/// листает письмо само, шапка письма и панель ответа остаются на виду.
double macMailWebHeight(double screen) => (screen - 260).clamp(320.0, 2000.0);

class MacMailWebView extends StatefulWidget {
  const MacMailWebView({
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

  /// Окно не показало письмо (ошибка загрузки, процесс WebKit завершился).
  final VoidCallback? onFailed;

  @override
  State<MacMailWebView> createState() => _MacMailWebViewState();
}

class _MacMailWebViewState extends State<MacMailWebView> {
  MailHtmlDocument? _doc;
  String? _page;
  InAppWebViewController? _web;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  @override
  void didUpdateWidget(MacMailWebView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html ||
        old.allowRemoteImages != widget.allowRemoteImages ||
        old.inlineImages.length != widget.inlineImages.length) {
      unawaited(_prepare());
    } else if (old.dark != widget.dark || old.pageColor != widget.pageColor || old.textScale != widget.textScale) {
      _compose();
    }
  }

  Future<void> _prepare() async {
    final gen = ++_gen;
    try {
      final doc = await MailHtmlDocument.buildAsync(widget.html,
          allowRemoteImages: widget.allowRemoteImages, inlineImages: widget.inlineImages);
      if (!mounted || gen != _gen) return;
      _doc = doc;
      _compose();
    } catch (e) {
      AppLogger.warning('Письмо в окне (Mac): документ не собран — $e');
      if (mounted && gen == _gen) widget.onFailed?.call();
    }
  }

  /// Документ под тему и размер текста; открытое окно получает его без
  /// пересоздания.
  void _compose() {
    final doc = _doc;
    if (doc == null) return;
    final page = MailHtmlView.composeHtml(doc,
        viewWidth: 0, fitWidth: null, dark: widget.dark, pageColor: widget.pageColor, textScale: widget.textScale);
    if (page == _page) return;
    final first = _page == null;
    setState(() => _page = page);
    if (!first) {
      unawaited(_web
          ?.loadData(data: page, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank'))
          .catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return SizedBox(
      height: widget.height,
      child: page == null
          ? const SizedBox.shrink()
          : InAppWebView(
              initialData: InAppWebViewInitialData(
                data: page,
                mimeType: 'text/html',
                encoding: 'utf-8',
                baseUrl: WebUri('about:blank'),
              ),
              initialSettings: MailHtmlView.macSettings(textScale: widget.textScale),
              onWebViewCreated: (c) => _web = c,
              shouldOverrideUrlLoading: (controller, action) async {
                final url = action.request.url;
                if (MailHtmlView.isLocalUrl(url)) return NavigationActionPolicy.ALLOW;
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
                if (request.isForMainFrame ?? false) {
                  AppLogger.warning('Письмо в окне (Mac): ${error.description}');
                  widget.onFailed?.call();
                }
              },
              onWebContentProcessDidTerminate: (controller) {
                AppLogger.warning('Письмо в окне (Mac): процесс WebKit завершился');
                widget.onFailed?.call();
              },
            ),
    );
  }
}

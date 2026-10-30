// lib/features/compose/widgets/mail_editor.dart
// Редактор писем и подписей — HugeRTE (MIT-форк TinyMCE 6) во встроенном
// браузере. Заменил html_editor_enhanced (Summernote).
//
// ══════════════════════════════════════════════════════════════════════
// УСТРОЙСТВО
// ══════════════════════════════════════════════════════════════════════
// Файлы редактора — assets/editor/ (сборка: tool/editor/build_editor.sh).
// Страница собирается здесь одной строкой: стили и скрипт встроены, документ
// загружается как данные (about:blank) — без доступа к файлам и без сети.
//
// Приложение → редактор: `OgnEditor.set/insert/append/get/focus` через
// evaluateJavascript; строки передаются как JSON (jsonEncode) — никакого
// ручного экранирования, и текст письма не может «закрыть» строку JS.
// Редактор → приложение: обработчики ready / change / pickImage / failed.
//
// ══════════════════════════════════════════════════════════════════════
// БЕЗОПАСНОСТЬ
// ══════════════════════════════════════════════════════════════════════
//  1. CSP: выполняется только встроенный скрипт редактора — по его хэшу
//     SHA-256, посчитанному здесь же (не зависит от переводов строк при
//     распаковке). Сеть (`connect-src`), фреймы, формы, шрифты — запрещены;
//     картинки — только data: и blob:.
//  2. Настройки WebView: нет файлов и content://, нет cookie и хранилищ,
//     инкогнито; на Android все сетевые загрузки заблокированы движком.
//  3. Навигация запрещена: ссылки в редакторе не открываются, окна не создаются.
//  4. HugeRTE: xss_sanitization (DOMPurify), sandbox_iframes,
//     convert_unsafe_embeds. Плюс HtmlSanitizer до входа и при отправке.
//  5. Внешние картинки цитаты не загружаются (CSP + `data-ogn-src` в
//     compose_screen).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import '../../../core/platform/file_pick.dart' show FilePick, FileType;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/background/work_scheduler.dart';
import '../../../widgets/common/ui_zoom.dart';

/// Где редактор работает. Остальные платформы — простое текстовое поле.
bool get mailEditorSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

/// Лицензия HugeRTE (MIT) — на странице «Лицензии» приложения.
void registerMailEditorLicense() {
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/editor/LICENSE-hugerte.txt');
    yield LicenseEntryWithLineBreaks(const ['HugeRTE'], text);
  });
}

/// Выбрать картинку для вставки в письмо: data URI или null. Тип — по
/// сигнатуре файла (не по расширению); SVG не принимается (может содержать
/// скрипт); не больше 3 МБ — письмо с крупной встроенной картинкой не
/// пропустят многие серверы.
Future<String?> pickInlineImageDataUri() async {
  try {
    final f = await FilePick.file(type: FileType.image);
    // Размер — до чтения: картинку больше 3 МБ не читаем вовсе.
    if (f == null || f.size > 3 * 1024 * 1024) return null;
    final bytes = await f.readBytes();
    if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) return null;
    final mime = imageMimeBySignature(bytes);
    if (mime == null) return null;
    return 'data:$mime;base64,${base64.encode(bytes)}';
  } catch (_) {
    return null;
  }
}

/// MIME картинки по первым байтам; null — не картинка из белого списка.
String? imageMimeBySignature(List<int> b) {
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

/// Управление редактором из экрана.
class MailEditorController {
  InAppWebViewController? _web;
  bool _ready = false;

  /// Пока редактор не готов, вызовы копятся и выполняются после загрузки.
  final List<String> _pending = [];

  bool get isReady => _ready;

  Future<void> _run(String js) async {
    if (!_ready || _web == null) {
      _pending.add(js);
      return;
    }
    try {
      await _web!.evaluateJavascript(source: js);
    } catch (_) {}
  }

  /// Заменить содержимое (история отмены начинается заново).
  Future<void> setHtml(String html) => _run('OgnEditor.set(${_js(html)})');

  /// Вставить в позицию курсора.
  Future<void> insertHtml(String html) => _run('OgnEditor.insert(${_js(html)})');

  /// Дописать в конец (подпись, цитата).
  Future<void> appendHtml(String html) => _run('OgnEditor.append(${_js(html)})');

  Future<void> focus() => _run('OgnEditor.focus()');

  /// Снять курсор и выделение (фокус ушёл в поле темы или адресатов):
  /// иначе окно редактора продолжало показывать свой курсор и «каплю»
  /// выделения рядом с курсором поля Flutter (1.5.10). Не копится до
  /// готовности — снимать ещё нечего.
  Future<void> blur() async {
    final w = _web;
    if (!_ready || w == null) return;
    try {
      // Только курсор и выделение в документе: фокус самого окна не
      // трогаем — клавиатура уже у поля Flutter, и clearFocus у окна мог бы
      // её перезапустить.
      await w.evaluateJavascript(source: 'OgnEditor.blur()');
    } catch (_) {}
  }

  /// Окно редактора сдвинулось на экране — спрятать «каплю» выделения,
  /// оставшуюся на старом месте (курсор остаётся там, где идёт ввод).
  /// Не копится до готовности.
  Future<void> refreshSelection() async {
    final w = _web;
    if (!_ready || w == null) return;
    try {
      await w.evaluateJavascript(source: 'OgnEditor.refreshSelection()');
    } catch (_) {}
  }

  /// Обновить приветствие, если пользователь не правил его ([previous] —
  /// прежний автоматический текст).
  Future<void> setGreeting(String text, String? previous) =>
      _run('OgnEditor.setGreeting(${_js(text)}, ${previous == null ? 'null' : _js(previous)})');

  /// Заменить подпись ('' — убрать).
  Future<void> setSignature(String html) => _run('OgnEditor.setSignature(${_js(html)})');

  /// Показать или скрыть панель форматирования.
  Future<void> showToolbar(bool show) => _run('OgnEditor.toolbar(${show ? 'true' : 'false'})');

  /// Стиль текста (CSS: шрифт и размер) — у каждого аккаунта свой.
  Future<void> setBodyStyle(String css) => _run('OgnEditor.setBodyStyle(${_js(css)})');

  /// Фокус на строку для текста — под приветствием.
  Future<void> focusText() => _run('OgnEditor.focusText()');

  /// Текущий HTML. Пока редактор не готов — null.
  Future<String?> getHtml() async {
    if (!_ready || _web == null) return null;
    try {
      final r = await _web!.evaluateJavascript(source: 'OgnEditor.get()');
      return r is String ? r : r?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Строка JS-литералом. jsonEncode экранирует кавычки, `\` и управляющие
  /// символы; U+2028/2029 — дополнительно, для старых движков.
  static String _js(String s) =>
      jsonEncode(s).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

  Future<void> _attach(InAppWebViewController c) async {
    _web = c;
    _ready = true;
    final queued = List<String>.of(_pending);
    _pending.clear();
    for (final js in queued) {
      try {
        await c.evaluateJavascript(source: js);
      } catch (_) {}
    }
  }

  void _detach() {
    _web = null;
    _ready = false;
  }
}

/// Файлы редактора из assets — читаются один раз.
class _EditorAssets {
  final String script; // ядро + плагины + языки + мост
  /// SHA-256 скрипта для CSP — считается один раз, в фоновом изоляте
  /// (1.6.19). Раньше хэш 1,3 МБ считался на главном потоке при КАЖДОМ
  /// открытии «Нового сообщения» — в первом кадре анимации, и окно
  /// выезжало рывками.
  final String scriptHash;
  final String skin;
  final String skinDark;
  final String content;
  final String contentDark;
  const _EditorAssets(this.script, this.scriptHash, this.skin, this.skinDark, this.content, this.contentDark);

  static Future<_EditorAssets>? _loading;
  static Future<_EditorAssets> load() => _loading ??= () async {
        final r = await Future.wait([
          rootBundle.loadString('assets/editor/hugerte.bundle.js', cache: false),
          rootBundle.loadString('assets/editor/bridge.js', cache: false),
          rootBundle.loadString('assets/editor/skin.css', cache: false),
          rootBundle.loadString('assets/editor/skin-dark.css', cache: false),
          rootBundle.loadString('assets/editor/content.css', cache: false),
          rootBundle.loadString('assets/editor/content-dark.css', cache: false),
        ]);
        final script = '${r[0]}\n${r[1]}';
        final hash = await compute(editorScriptHash, script);
        return _EditorAssets(script, hash, r[2], r[3], r[4], r[5]);
      }();
}

/// Хэш скрипта редактора для Content-Security-Policy (base64 SHA-256 тех же
/// байтов, что окажутся между <script> и </script>).
String editorScriptHash(String script) => base64.encode(sha256.convert(utf8.encode(script)).bytes);

/// Прогреть редактор письма заранее (файлы, хэш): первое «Новое сообщение»
/// после запуска открывается без паузы на чтение 1,3 МБ.
Future<void> warmUpMailEditor() async {
  try {
    await _EditorAssets.load();
  } catch (_) {
    _EditorAssets._loading = null; // повторим при открытии редактора
  }
}

/// Собрать страницу редактора. Вынесено для тестов.
@visibleForTesting
String buildMailEditorPage({
  required String script,
  required String skinCss,
  required Map<String, Object?> config,
  String? scriptHash,
}) {
  // Хэш — по тем же байтам, что окажутся между <script> и </script>.
  // Готовый (из _EditorAssets) не пересчитывается.
  final hash = scriptHash ?? editorScriptHash(script);
  final csp = "default-src 'none'; script-src 'sha256-$hash'; "
      "style-src 'unsafe-inline'; img-src data: blob:; font-src data:; "
      "connect-src 'none'; media-src 'none'; frame-src 'none'; child-src 'none'; "
      "object-src 'none'; form-action 'none'; base-uri 'none'";
  // JSON внутри <script type="application/json"> не исполняется, но «</script>»
  // в строке закрыл бы тег: `<` заменяется на \u003c.
  final cfg = jsonEncode(config).replaceAll('<', r'\u003c');
  return '<!DOCTYPE html><html><head><meta charset="utf-8">'
      '<meta http-equiv="Content-Security-Policy" content="$csp">'
      '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">'
      '<meta name="referrer" content="no-referrer">'
      '<style>$skinCss\n'
      'html,body{margin:0;padding:0;height:100%;}'
      '#ogn-editor{display:none;}'
      // Без рамки и «карточки»: редактор сливается с экраном письма, панель
      // инструментов — плоская полоса с тонкой линией снизу.
      '.tox-hugerte{border:0!important;border-radius:0!important;background:transparent!important;}'
      '.tox .tox-edit-area::before{display:none!important;}'
      '.tox .tox-edit-area__iframe,.tox .tox-sidebar-wrap,.tox .tox-edit-area{background:transparent!important;}'
      '.tox .tox-editor-header{box-shadow:none!important;padding:0!important;background:transparent!important;'
      'border-bottom:1px solid rgba(127,127,127,.18)!important;}'
      '.tox .tox-toolbar,.tox .tox-toolbar__primary,.tox .tox-toolbar__overflow,.tox .tox-toolbar-overlord{'
      'background:transparent!important;}'
      // Компактные кнопки: 32 px вместо 40, группы без широких отступов.
      '.tox .tox-tbtn{height:32px!important;width:32px!important;margin:1px 0!important;}'
      '.tox .tox-tbtn--select,.tox .tox-tbtn--bespoke{width:auto!important;}'
      '.tox .tox-split-button{height:32px!important;margin:1px 0!important;}'
      '.tox .tox-split-button .tox-tbtn{width:28px!important;}'
      '.tox .tox-tbtn svg{transform:scale(.85);}'
      '.tox .tox-toolbar__group{padding:0 2px!important;}'
      '.ogn-notoolbar .tox .tox-editor-header{display:none!important;}'
      '</style></head><body>'
      '<textarea id="ogn-editor"></textarea>'
      '<script type="application/json" id="ogn-config">$cfg</script>'
      '<script>$script</script>'
      '</body></html>';
}

class MailEditor extends StatefulWidget {
  const MailEditor({
    super.key,
    required this.controller,
    this.initialHtml = '',
    this.placeholder = '',
    this.height = 360,
    this.onChanged,
    this.onReady,
    this.onFailed,
    this.onPickImage,
    this.onFocus,
    this.bodyStyle = '',
    this.toolbarHidden = false,
    this.usePool = false,
  });

  final MailEditorController controller;

  /// Брать готовое окно редактора из запасного ([MailEditorPool], Android):
  /// «Новое сообщение». Подписи в настройках — без него.
  final bool usePool;

  /// CSS текста письма (шрифт и размер аккаунта).
  final String bodyStyle;

  /// Начать со скрытой панелью форматирования.
  final bool toolbarHidden;
  final String initialHtml;
  final String placeholder;
  final double height;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onReady;

  /// Редактор не загрузился (нет WebView, ошибка скрипта, таймаут) — экран
  /// переключается на простое текстовое поле.
  final VoidCallback? onFailed;

  /// Кнопка «Картинка»: вернуть data URI выбранной картинки или null.
  final Future<String?> Function()? onPickImage;

  /// Курсор в тексте письма (нажатие в редактор).
  final VoidCallback? onFocus;

  @override
  State<MailEditor> createState() => _MailEditorState();
}

class _MailEditorState extends State<MailEditor> {
  String? _page;
  Timer? _watchdog;
  bool _done = false;

  static const _loadTimeout = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _watchdog = Timer(_loadTimeout, () => _fail('timeout'));
  }

  /// WebView редактора создаётся после анимации открытия экрана: встроенное
  /// окно во время анимации давало рывки (замечание 11.10.2026).
  bool _routeDone = false;
  Animation<double>? _routeAnim;

  void _onRouteStatus(AnimationStatus st) {
    if (st != AnimationStatus.completed || !mounted) return;
    _routeAnim?.removeStatusListener(_onRouteStatus);
    setState(() => _routeDone = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_routeDone) {
      final anim = ModalRoute.of(context)?.animation;
      if (anim == null || anim.status == AnimationStatus.completed) {
        _routeDone = true;
      } else if (!identical(anim, _routeAnim)) {
        _routeAnim?.removeStatusListener(_onRouteStatus);
        _routeAnim = anim..addStatusListener(_onRouteStatus);
      }
    }
    if (_page == null) _build();
  }

  /// Окно из запасного ([MailEditorPool]) и пришло ли из него «готов».
  HeadlessInAppWebView? _adopted;

  Future<void> _build() async {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = _lang(Localizations.localeOf(context).languageCode);
    if (widget.usePool && MailEditorPool.supported) {
      final key = MailEditorPool.keyOf(lang: lang, dark: dark, placeholder: widget.placeholder);
      final size = Size(MediaQuery.sizeOf(context).width * _zoom, widget.height * _zoom);
      final t = MailEditorPool.take(key, size: size);
      if (t != null) {
        // Стиль ящика и панель — после подключения (в запасном окне их нет).
        unawaited(widget.controller.setBodyStyle(widget.bodyStyle));
        unawaited(widget.controller.showToolbar(!widget.toolbarHidden));
        setState(() {
          _adopted = t;
          _page = '';
          _contextMenu = _buildContextMenu(lang);
        });
        return;
      }
    }
    try {
      final a = await _EditorAssets.load();
      final page = buildMailEditorPage(
        script: a.script,
        scriptHash: a.scriptHash,
        skinCss: dark ? a.skinDark : a.skin,
        config: {
          'lang': lang,
          'dark': dark,
          'placeholder': widget.placeholder,
          'contentCss': dark ? a.contentDark : a.content,
          'extraCss': _contentExtraCss,
          'imageTooltip': _imageTooltip(lang),
          'bodyStyle': widget.bodyStyle,
          'toolbarHidden': widget.toolbarHidden,
        },
      );
      if (mounted) {
        setState(() {
          _page = page;
          _contextMenu = _buildContextMenu(lang);
        });
      }
    } catch (e) {
      _fail('assets: $e');
    }
  }

  static String _lang(String code) => switch (code) {
        'ru' => 'ru',
        'de' => 'de',
        'fr' => 'fr_FR',
        _ => 'en',
      };

  /// Пункты меню выделения текста: долгое нажатие на слово → «Жирный» и т. д.
  static const _menuCommands = ['Bold', 'Italic', 'Underline', 'RemoveFormat', 'Undo'];
  static List<String> _menuTitles(String lang) => switch (lang) {
        'ru' => const ['Жирный', 'Курсив', 'Подчёркнутый', 'Без оформления', 'Отменить'],
        'de' => const ['Fett', 'Kursiv', 'Unterstrichen', 'Ohne Formatierung', 'Rückgängig'],
        'fr_FR' => const ['Gras', 'Italique', 'Souligné', 'Sans mise en forme', 'Annuler'],
        _ => const ['Bold', 'Italic', 'Underline', 'Clear formatting', 'Undo'],
      };

  ContextMenu? _contextMenu;
  ContextMenu _buildContextMenu(String lang) {
    final titles = _menuTitles(lang);
    return ContextMenu(
      settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: false),
      menuItems: [
        for (var i = 0; i < _menuCommands.length; i++)
          ContextMenuItem(
            id: i + 1,
            title: titles[i],
            action: () => widget.controller._run('OgnEditor.exec(${MailEditorController._js(_menuCommands[i])})'),
          ),
      ],
    );
  }

  static String _imageTooltip(String lang) => switch (lang) {
        'ru' => 'Картинка',
        'de' => 'Bild',
        'fr_FR' => 'Image',
        _ => 'Image',
      };

  static const _contentExtraCss =
      'html,body{background:transparent!important;}'
      // Плотные строки, как в Outlook; шрифт и размер — стиль аккаунта (bodyStyle).
      'body{font-family:Calibri,Carlito,Arial,sans-serif;font-size:11pt;'
      'line-height:1.3;margin:6px 0;overflow-wrap:anywhere;}'
      'img{max-width:100%;height:auto;}'
      'blockquote{margin:8px 0 8px 4px;padding-left:10px;border-left:3px solid #c7cdd6;}'
      'img[data-ogn-src]{min-width:24px;min-height:24px;outline:1px dashed #c7cdd6;}';

  void _fail(String why) {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    debugPrint('MailEditor: не загрузился ($why)');
    widget.onFailed?.call();
  }

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_onRouteStatus);
    _watchdog?.cancel();
    widget.controller._detach();
    // Следующее «Новое сообщение» — из готового окна (создаётся в простое).
    if (widget.usePool) MailEditorPool.scheduleSpare();
    super.dispose();
  }

  static bool _isLocal(Uri? u) {
    final s = u?.scheme.toLowerCase() ?? '';
    return s.isEmpty || s == 'about' || s == 'data' || s == 'blob';
  }

  /// Android: окно редактора рисуется без масштаба интерфейса ([UiZoomUndo]) —
  /// иначе «капля» под курсором и ручки выделения уезжали от текста
  /// (замечание 28.10.2026). Текст уменьшается самим окном (textZoom), чтобы
  /// письмо было того же размера, что и остальной экран.
  static double get _zoom => !kIsWeb && Platform.isAndroid ? UiZoom.current : 1.0;

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final web = page == null || !_routeDone ? null : _webView(page);
    return SizedBox(
      height: widget.height,
      child: web == null
          ? const SizedBox.shrink()
          : Platform.isAndroid
              ? UiZoomUndo(zoom: _zoom, child: web)
              : web,
    );
  }

  /// Настройки окна редактора (и запасного — те же).
  static InAppWebViewSettings _settings() => InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        useShouldOverrideUrlLoading: true,
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
        // Редактору сеть не нужна вовсе.
        blockNetworkImage: true,
        blockNetworkLoads: true,
        safeBrowsingEnabled: true,
        mediaPlaybackRequiresUserGesture: true,
        allowsLinkPreview: false,
        transparentBackground: true,
        supportZoom: false,
        builtInZoomControls: false,
        displayZoomControls: false,
        textZoom: UiZoom.isIdentity(_zoom) ? 100 : (_zoom * 100).round(),
      );

  Future<void> _onReady(InAppWebViewController c) async {
    if (_done) return;
    _done = true;
    _watchdog?.cancel();
    await widget.controller._attach(c);
    if (widget.initialHtml.isNotEmpty) {
      await widget.controller.setHtml(widget.initialHtml);
    }
    widget.onReady?.call();
  }

  Widget _webView(String page) => InAppWebView(
      // Готовое окно из запасного: страница уже загружена, initialData не
      // загружается.
      headlessWebView: _adopted,
      // Меню выделения: жирный, курсив, подчёркнутый, без
      // оформления, отменить — без открытия панели форматирования.
      contextMenu: _contextMenu,
      initialData: _adopted != null
          ? null
          : InAppWebViewInitialData(
              data: page,
              mimeType: 'text/html',
              encoding: 'utf-8',
              baseUrl: WebUri('about:blank'),
            ),
      initialSettings: _settings(),
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
        Factory<HorizontalDragGestureRecognizer>(() => HorizontalDragGestureRecognizer()),
      },
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(
          handlerName: 'ready',
          callback: (_) async {
            await _onReady(c);
            return null;
          },
        );
        // Запасное окно уже сообщило «готов» — до того, как его забрал экран.
        final adopted = _adopted;
        if (adopted != null && MailEditorPool.takenReady(adopted)) unawaited(_onReady(c));
        c.addJavaScriptHandler(
          handlerName: 'change',
          callback: (args) {
            final html = args.isNotEmpty && args.first is String ? args.first as String : '';
            widget.onChanged?.call(html);
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'failed',
          callback: (args) {
            _fail(args.isNotEmpty ? '${args.first}' : 'init');
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'focus',
          callback: (_) {
            widget.onFocus?.call();
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'pickImage',
          callback: (_) async {
            final pick = widget.onPickImage;
            if (pick == null) return null;
            final uri = await pick();
            if (uri != null && uri.startsWith('data:image/')) {
              await widget.controller.insertHtml('<img src="${_attr(uri)}" alt="">');
            }
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (controller, action) async =>
          _isLocal(action.request.url) ? NavigationActionPolicy.ALLOW : NavigationActionPolicy.CANCEL,
      onCreateWindow: (controller, action) async => false,
      onPermissionRequest: (controller, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
      onGeolocationPermissionsShowPrompt: (controller, origin) async =>
          GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: false),
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) _fail('load: ${error.description}');
      },
      onWebContentProcessDidTerminate: (controller) => _fail('process'),
    );

  static String _attr(String s) => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
}


/// Запасное окно редактора (1.8.12, замечание 29.10.2026: «при открытии окна
/// нового письма интерфейс сильно тормозит»).
///
/// Редактор — 1,3 МБ скрипта HugeRTE во встроенном окне (гибридная
/// композиция): пока окно создавалось, а скрипт разбирался и запускал
/// редактор, кадры Flutter ждали главный поток Android — экран дёргался.
/// Как и у просмотра писем ([MailWebViewPool]): одно невидимое окно с уже
/// запущенным редактором держится наготове, «Новое сообщение» забирает его
/// готовым. Ключ — язык, тема и подсказка; стиль ящика и панель
/// форматирования задаются после подключения. Ключ последнего окна
/// запоминается — и после перезапуска окно готовится в простое.
/// Только Android; свёрнуто — окно закрывается ([release]).
class MailEditorPool {
  MailEditorPool._();

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _prefKey = 'mail_editor_spare_v1';

  static HeadlessInAppWebView? _spare;
  static String? _key;
  static bool _ready = false;
  static Future<void>? _creating;

  /// Последний ключ и размер окна (с «Нового сообщения»).
  static String? _lastKey;
  static Size? _lastSize;

  /// Окно, которое забрал экран, и пришло ли «готов» до подключения виджета.
  static HeadlessInAppWebView? _taken;
  static bool _takenReady = false;

  static bool takenReady(HeadlessInAppWebView v) => identical(v, _taken) && _takenReady;

  static String keyOf({required String lang, required bool dark, required String placeholder}) =>
      jsonEncode({'l': lang, 'd': dark, 'p': placeholder});

  /// Забрать готовое окно с ключом [key]; null — нет такого (обычный путь).
  static HeadlessInAppWebView? take(String key, {required Size size}) {
    _lastKey = key;
    _lastSize = size;
    unawaited(_save(key, size));
    final h = _spare;
    if (h == null || _key != key || !h.isRunning()) return null;
    _taken = h;
    _takenReady = _ready;
    _spare = null;
    _key = null;
    _ready = false;
    return h;
  }

  /// Подготовить окно в простое (после закрытия «Нового сообщения», при
  /// показе ленты).
  static void scheduleSpare() {
    if (!supported) return;
    unawaited(WorkScheduler.instance.run(WorkPriority.idle, ensureSpare));
  }

  static Future<void> ensureSpare() async {
    if (!supported) return;
    if (_lastKey == null) await _restore();
    final key = _lastKey, size = _lastSize;
    if (key == null || size == null || size.isEmpty) return;
    if (_spare != null && _key == key) return;
    return _creating ??= _create(key, size).whenComplete(() => _creating = null);
  }

  static Future<void> _create(String key, Size size) async {
    await release();
    final cfg = jsonDecode(key) as Map<String, dynamic>;
    final dark = cfg['d'] == true;
    final lang = cfg['l'] as String? ?? 'en';
    final a = await _EditorAssets.load();
    final page = buildMailEditorPage(
      script: a.script,
      scriptHash: a.scriptHash,
      skinCss: dark ? a.skinDark : a.skin,
      config: {
        'lang': lang,
        'dark': dark,
        'placeholder': cfg['p'] as String? ?? '',
        'contentCss': dark ? a.contentDark : a.content,
        'extraCss': _MailEditorState._contentExtraCss,
        'imageTooltip': _MailEditorState._imageTooltip(lang),
        'bodyStyle': '',
        'toolbarHidden': true,
      },
    );
    late final HeadlessInAppWebView h;
    h = HeadlessInAppWebView(
      initialSize: size,
      initialData: InAppWebViewInitialData(
          data: page, mimeType: 'text/html', encoding: 'utf-8', baseUrl: WebUri('about:blank')),
      initialSettings: _MailEditorState._settings(),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(
          handlerName: 'ready',
          callback: (_) {
            if (identical(h, _spare)) _ready = true;
            if (identical(h, _taken)) _takenReady = true;
            return null;
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'failed',
          callback: (_) {
            if (identical(h, _spare)) unawaited(release());
            return null;
          },
        );
      },
      shouldOverrideUrlLoading: (c, action) async => _MailEditorState._isLocal(action.request.url)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      onCreateWindow: (c, action) async => false,
      onPermissionRequest: (c, request) async =>
          PermissionResponse(resources: request.resources, action: PermissionResponseAction.DENY),
    );
    _spare = h;
    _key = key;
    _ready = false;
    try {
      await h.run();
    } catch (e) {
      debugPrint('MailEditorPool: окно не создано ($e)');
      if (identical(_spare, h)) {
        _spare = null;
        _key = null;
      }
    }
  }

  /// Приложение свёрнуто — закрыть запасное окно (память).
  static Future<void> release() async {
    final h = _spare;
    _spare = null;
    _key = null;
    _ready = false;
    if (h == null) return;
    try {
      await h.dispose();
    } catch (_) {}
  }

  static Future<void> _save(String key, Size size) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, jsonEncode({'k': key, 'w': size.width, 'h': size.height}));
    } catch (_) {}
  }

  static Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _lastKey = m['k'] as String?;
      _lastSize = Size((m['w'] as num).toDouble(), (m['h'] as num).toDouble());
    } catch (_) {}
  }
}

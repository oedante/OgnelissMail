// lib/services/translation/bergamot/bergamot_translator.dart
//
// Перевод писем на Windows (2.2.0, план 08.11.2026; решение владельца
// 09.11.2026 — модели с ogneliss.ru). Движок — Bergamot (Mozilla и
// университеты проекта Bergamot, MPL-2.0): тот же, что в переводе Firefox.
// Текст писем переводится на компьютере, в интернет уходят только запросы
// моделей к серверу Ogneliss (при скачивании языка).
//
//  · движок — data\bergamot рядом с exe (сборка Windows кладёт его туда:
//    tool/bergamot/fetch_engine.dart, ci.yml и scripts/build_windows.ps1);
//    нет папки — перевода на этом компьютере нет, как раньше;
//  · модели — BergamotStore (bergamot_models.dart);
//  · работает в скрытом WebView2 (flutter_inappwebview) со страницей
//    локального сервера (bergamot_server.dart);
//  · язык письма — detectLanguageHeuristic (lang_detect.dart): Bergamot
//    языки не определяет;
//  · названия языков — language_names.g.dart (CLDR).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_logger.dart';
import '../lang_detect.dart';
import '../language_names.g.dart';
import '../translator.dart';
import 'bergamot_models.dart';
import 'bergamot_server.dart';

/// Папка движка рядом с exe: data\bergamot.
Directory bergamotEngineDir() =>
    Directory('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}data'
        '${Platform.pathSeparator}bergamot');

/// Движок в этой сборке есть (проверка один раз за запуск).
bool get bergamotEnginePresent => _present ??= Platform.isWindows && BergamotServer.engineComplete(bergamotEngineDir());
bool? _present;

/// Запуск перевода в движке.
abstract class BergamotEngine {
  /// [from], [to] — коды моделей («en», «ru», «nb»).
  Future<List<String>> translate(String from, String to, List<String> texts);

  /// Языки скачали или удалили — движок перечитает registry.json.
  Future<void> reset();
}

/// Движок в скрытом WebView2.
class WebViewBergamotEngine implements BergamotEngine {
  final BergamotServer server;
  WebViewBergamotEngine(this.server);

  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Future<InAppWebViewController>? _starting;
  Timer? _idle;

  /// Без переводов 5 минут — WebView и модели выгружаются (сотни МБ памяти).
  static const idleTimeout = Duration(minutes: 5);

  Future<InAppWebViewController> _start() => _starting ??= () async {
        final url = await server.start();
        final loaded = Completer<void>();
        final view = HeadlessInAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url.toString())),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            javaScriptCanOpenWindowsAutomatically: false,
            supportMultipleWindows: false,
            cacheEnabled: false,
            useShouldOverrideUrlLoading: true,
            isInspectable: false,
          ),
          shouldOverrideUrlLoading: (c, action) async {
            final u = action.request.url;
            return u != null && server.owns(u.uriValue)
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          },
          onCreateWindow: (c, a) async => false,
          onLoadStop: (c, u) {
            if (!loaded.isCompleted) loaded.complete();
          },
          onReceivedError: (c, req, err) {
            if (req.isForMainFrame != false && !loaded.isCompleted) {
              loaded.completeError(StateError('страница движка: ${err.description}'));
            }
          },
          onConsoleMessage: (c, m) => AppLogger.debug('Bergamot: ${m.message}'),
        );
        _view = view;
        await view.run();
        await loaded.future.timeout(const Duration(seconds: 20));
        final c = view.webViewController;
        if (c == null) throw StateError('WebView2 не запустился');
        // Модуль-мост загружается после onLoadStop не всегда сразу.
        for (var i = 0; i < 100; i++) {
          if (await c.evaluateJavascript(source: 'window.ognReady === true') == true) {
            return _controller = c;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        throw StateError('движок перевода не загрузился');
      }()
          .catchError((Object e) async {
        await _dispose();
        throw e;
      });

  @override
  Future<List<String>> translate(String from, String to, List<String> texts) async {
    _idle?.cancel();
    try {
      final c = await _start();
      final r = await c.callAsyncJavaScript(
        functionBody: 'return await window.ognTranslate(from, to, texts);',
        arguments: {'from': from, 'to': to, 'texts': texts},
      );
      if (r == null || r.error != null) throw StateError('Bergamot: ${r?.error ?? 'нет ответа'}');
      final v = r.value;
      if (v is! List || v.length != texts.length) throw StateError('Bergamot: ответ не тот');
      return [for (final s in v) s is String ? s : '$s'];
    } finally {
      _idle = Timer(idleTimeout, () => unawaited(_dispose()));
    }
  }

  @override
  Future<void> reset() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: 'window.ognReset()');
    } catch (_) {
      await _dispose();
    }
  }

  Future<void> _dispose() async {
    _idle?.cancel();
    final v = _view;
    _view = null;
    _controller = null;
    _starting = null;
    try {
      await v?.dispose();
    } catch (_) {}
    await server.close();
  }
}

/// [Translator] на Bergamot.
class BergamotTranslator implements Translator {
  final Future<BergamotStore> Function() _storeFactory;
  final BergamotEngine Function(BergamotStore store) _engineFactory;
  final bool Function() _enginePresent;

  BergamotTranslator({
    Future<BergamotStore> Function()? store,
    BergamotEngine Function(BergamotStore store)? engine,
    bool Function()? enginePresent,
  })  : _storeFactory = store ?? _defaultStore,
        _engineFactory = engine ??
            ((s) => WebViewBergamotEngine(BergamotServer(engineDir: bergamotEngineDir(), store: s))),
        _enginePresent = enginePresent ?? (() => bergamotEnginePresent);

  static Future<BergamotStore> _defaultStore() async {
    final dir = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    return BergamotStore(Directory('${dir.path}${sep}translate${sep}bergamot'));
  }

  Future<BergamotStore>? _store;
  Future<BergamotStore> get store => _store ??= _storeFactory();

  BergamotEngine? _engine;
  Future<BergamotEngine> get _eng async => _engine ??= _engineFactory(await store);

  /// Вызовы движка и скачивания — по одному.
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _tail = _tail.then((_) => f().then(c.complete, onError: c.completeError));
    return c.future;
  }

  @override
  Future<bool> isAvailable() async => _enginePresent();

  @override
  Future<String?> detectLanguage(String text) async => (await identifyLanguage(text))?.lang;

  @override
  Future<LangDetection?> identifyLanguage(String text) async =>
      text.trim().isEmpty ? null : detectLanguageHeuristic(text);

  @override
  Future<List<String>> supportedLanguages() async {
    if (!_enginePresent()) return const [];
    final idx = await (await store).index();
    return idx.languages.toList()..sort();
  }

  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async =>
      bergamotLanguageNames(codes, displayLang);

  @override
  Future<Set<String>?> downloadedModels() async {
    final s = await store;
    final idx = await s.index();
    final have = s.installed().keys.toSet();
    return {
      for (final l in idx.languages)
        if (l != 'en' && idx.pairsOf(l).isNotEmpty && idx.pairsOf(l).every(have.contains)) l,
    };
  }

  @override
  Future<List<String>> missingModels(String from, String to) async {
    final s = await store;
    final idx = await s.index();
    final route = idx.route(from, to);
    if (route == null) throw UnsupportedError('Bergamot: нет пути $from → $to');
    final have = s.installed().keys.toSet();
    return {
      for (final k in route)
        if (!have.contains(k)) bergamotAppLang(k.substring(0, 2) == 'en' ? k.substring(2, 4) : k.substring(0, 2)),
    }.toList();
  }

  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) => _serial(() async {
        final missing = await missingModels(from, to);
        if (missing.isEmpty) return;
        final s = await store;
        final idx = await s.index(refresh: true);
        final have = s.installed().keys.toSet();
        for (final lang in missing) {
          for (final k in idx.pairsOf(lang)) {
            if (have.contains(k)) continue;
            await s.download(idx.pairs[k]!);
            AppLogger.info('Перевод: скачана пара $k');
          }
        }
        await (await _eng).reset();
      });

  @override
  Future<void> deleteModel(String lang) => _serial(() async {
        final s = await store;
        final idx = await s.index();
        for (final k in {...idx.pairsOf(lang), ...s.installed().keys.where((k) => _side(k) == lang)}) {
          await s.delete(k);
        }
        await (await _eng).reset();
      });

  static String _side(String key) =>
      bergamotAppLang(key.substring(0, 2) == 'en' ? key.substring(2, 4) : key.substring(0, 2));

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) => _serial(() async {
        if (from == to || texts.isEmpty) return texts;
        final s = await store;
        final idx = await s.index();
        final f = idx.modelLang(from, asSource: true);
        final t = idx.modelLang(to, asSource: false);
        if (f == null || t == null) throw UnsupportedError('Bergamot: нет языка $from или $to');
        return (await _eng).translate(f, t, texts);
      });

  @override
  bool get googleAttribution => false;

  // Пара Firefox Translations — около 22 МБ, язык — две пары (с английского
  // и на английский).
  @override
  int? get modelSizeMb => 45;

  @override
  bool get canManageModels => true;
}

/// Названия языков [codes] на языке [display] (CLDR); нет — английское,
/// нет и его — код.
Map<String, String> bergamotLanguageNames(List<String> codes, String display) {
  List<String>? row(String lang) => kLanguageNames[lang]?.split('|');
  final names = row(display) ?? row(display == 'no' ? 'nb' : 'en');
  final en = row('en')!;
  final out = <String, String>{};
  for (final c in codes) {
    final i = kLanguageNameCodes.indexOf(c);
    final n = i < 0 ? '' : (names != null && names[i].isNotEmpty ? names[i] : en[i]);
    out[c] = n.isEmpty ? c.toUpperCase() : n;
  }
  return out;
}

/// «Тексты лицензий» на Windows: движок Bergamot (MPL-2.0, исходный код —
/// по ссылке, как требует MPL), библиотеки внутри его WebAssembly, модели
/// Firefox Translations (MPL-2.0) и названия языков CLDR (Unicode License
/// v3). Тексты лицензий движка лежат рядом с ним (data\bergamot, их кладёт
/// tool/bergamot/fetch_engine.dart).
void registerBergamotLicenses() {
  LicenseRegistry.addLicense(() async* {
    final dir = bergamotEngineDir().path;
    String read(String name) {
      try {
        return File('$dir${Platform.pathSeparator}$name').readAsStringSync();
      } catch (_) {
        return '';
      }
    }

    final mpl = read('LICENSE-MPL-2.0.txt');
    yield LicenseEntryWithLineBreaks(const ['Bergamot Translator'],
        'Bergamot Translator $kBergamotEngineVersion (npm @browsermt/bergamot-translator), '
        'used for on-device translation on Windows.\n'
        'Developed by the Bergamot Project (University of Edinburgh, Charles University, '
        'University of Sheffield, University of Tartu, Mozilla) and contributors.\n'
        'Licensed under the Mozilla Public License 2.0. The files are distributed unmodified; '
        'Source Code Form: https://github.com/browsermt/bergamot-translator '
        '(npm package: https://www.npmjs.com/package/@browsermt/bergamot-translator/v/$kBergamotEngineVersion).\n\n$mpl');
    final third = read('THIRD-PARTY-NOTICES.txt');
    if (third.isNotEmpty) yield LicenseEntryWithLineBreaks(const ['Bergamot Translator (components)'], third);
    yield LicenseEntryWithLineBreaks(const ['Firefox Translations models'],
        'Translation models (language pairs) by Mozilla, Firefox Translations models, '
        'downloaded on request from the Ogneliss server unmodified.\n'
        'Licensed under the Mozilla Public License 2.0. Source: '
        'https://github.com/mozilla/firefox-translations-models\n\n$mpl');
    yield const LicenseEntryWithLineBreaks(['Unicode CLDR (language names)'], kCldrLicense);
  });
}

/// Версия движка в сборке (tool/bergamot/fetch_engine.dart).
const kBergamotEngineVersion = '0.4.9';

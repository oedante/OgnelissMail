// lib/services/translation/bergamot/bergamot_server.dart
//
// Локальный сервер движка перевода на Windows (2.2.0). Bergamot — это
// WebAssembly и JavaScript (npm @browsermt/bergamot-translator, MPL-2.0); он
// работает в скрытом WebView2 и берёт файлы по http: ES-модули, Worker и
// WebAssembly.instantiateStreaming с file:// не работают. Поэтому файлы
// движка (data\bergamot рядом с exe) и скачанные модели отдаёт этот сервер:
//
//  · только 127.0.0.1, порт — свободный, выбирает система;
//  · все адреса — под случайным ключом /<32 байта hex>/: другая программа на
//    компьютере не угадает адрес;
//  · Host — ровно 127.0.0.1:<порт> (страница чужого сайта через DNS
//    rebinding сюда не достучится);
//  · только GET и HEAD, только известные файлы (имена движка — списком,
//    модели — из manifest.json скачанных пар), без «..» в путях;
//  · CSP: скрипты и запросы — только с этого же адреса, наружу страница
//    ничего не отправит.
//
// Текст писем идёт в движок как данные (callAsyncJavaScript с аргументами),
// не как разметка страницы.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'bergamot_models.dart';

/// Файлы движка в data\bergamot (tool/bergamot/fetch_engine.dart).
const kBergamotEngineFiles = [
  'translator.js',
  'worker/translator-worker.js',
  'worker/bergamot-translator-worker.js',
  'worker/bergamot-translator-worker.wasm',
];

class BergamotServer {
  /// Папка движка: translator.js и worker/.
  final Directory engineDir;
  final BergamotStore store;

  /// Сколько потоков перевода (Web Worker) — у каждого своя копия модели.
  final int workers;
  BergamotServer({required this.engineDir, required this.store, int? workers})
      : workers = workers ?? (Platform.numberOfProcessors >= 8 ? 2 : 1);

  HttpServer? _http;
  late final String _token = _randomToken();

  static String _randomToken() {
    final r = Random.secure();
    return [for (var i = 0; i < 32; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Движок на месте (все файлы).
  static bool engineComplete(Directory dir) =>
      kBergamotEngineFiles.every((f) => File('${dir.path}/$f').existsSync());

  /// Адрес страницы движка (сервер запускается при первом вызове).
  Future<Uri> start() async {
    final s = _http ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (!_listening) {
      _listening = true;
      s.listen((r) => unawaited(_handle(r)), onError: (_) {});
    }
    return Uri.parse('http://127.0.0.1:${s.port}/$_token/index.html');
  }

  bool _listening = false;

  /// Адрес принадлежит этому серверу (для запрета переходов в WebView).
  bool owns(Uri u) => _http != null && u.host == '127.0.0.1' && u.port == _http!.port && u.path.startsWith('/$_token/');

  Future<void> close() async {
    final s = _http;
    _http = null;
    _listening = false;
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final port = _http?.port;
      if (req.headers.value(HttpHeaders.hostHeader) != '127.0.0.1:$port') {
        return await _fail(res, HttpStatus.forbidden);
      }
      if (req.method != 'GET' && req.method != 'HEAD') return await _fail(res, HttpStatus.methodNotAllowed);
      final segs = req.uri.pathSegments;
      if (segs.length < 2 || segs.first != _token || segs.any((s) => s.isEmpty || s == '..' || s == '.')) {
        return await _fail(res, HttpStatus.notFound);
      }
      final rest = segs.sublist(1).join('/');
      final head = req.method == 'HEAD';
      switch (rest) {
        case 'index.html':
          return await _bytes(res, utf8.encode(bergamotPageHtml), 'text/html; charset=utf-8', head: head, page: true);
        case 'bridge.js':
          return await _bytes(res, utf8.encode(bergamotBridgeJs(workers)), 'text/javascript; charset=utf-8', head: head);
        case 'registry.json':
          return await _bytes(res, utf8.encode(jsonEncode(store.localRegistry())), 'application/json', head: head);
      }
      if (segs.length >= 3 && segs[1] == 'engine') {
        final name = segs.sublist(2).join('/');
        if (!kBergamotEngineFiles.contains(name)) return await _fail(res, HttpStatus.notFound);
        return await _file(res, File('${engineDir.path}/$name'), head: head);
      }
      if (segs.length == 4 && segs[1] == 'models') {
        final f = store.file(segs[2], segs[3]);
        if (f == null) return await _fail(res, HttpStatus.notFound);
        return await _file(res, f, head: head);
      }
      return await _fail(res, HttpStatus.notFound);
    } catch (_) {
      try {
        await _fail(res, HttpStatus.internalServerError);
      } catch (_) {}
    }
  }

  static String _type(String path) {
    if (path.endsWith('.js')) return 'text/javascript; charset=utf-8';
    if (path.endsWith('.wasm')) return 'application/wasm';
    return 'application/octet-stream';
  }

  static const _csp = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; "
      "worker-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'";

  // Скрипты Worker (Emscripten) — со своей политикой: WebAssembly и
  // importScripts с этого же адреса.
  static const _workerCsp = "default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'";

  void _common(HttpResponse res, String type, {bool page = false, bool worker = false}) {
    res.headers
      ..set(HttpHeaders.contentTypeHeader, type)
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Cross-Origin-Resource-Policy', 'same-origin')
      ..set('Referrer-Policy', 'no-referrer');
    if (page) res.headers.set('Content-Security-Policy', _csp);
    if (worker) res.headers.set('Content-Security-Policy', _workerCsp);
  }

  Future<void> _bytes(HttpResponse res, List<int> body, String type, {required bool head, bool page = false}) async {
    _common(res, type, page: page);
    res.contentLength = body.length;
    if (!head) res.add(body);
    await res.close();
  }

  Future<void> _file(HttpResponse res, File f, {required bool head}) async {
    if (!f.existsSync()) return _fail(res, HttpStatus.notFound);
    _common(res, _type(f.path), worker: f.path.contains('worker/') && f.path.endsWith('.js'));
    res.contentLength = f.lengthSync();
    if (!head) await res.addStream(f.openRead());
    await res.close();
  }

  Future<void> _fail(HttpResponse res, int code) async {
    res.statusCode = code;
    res.contentLength = 0;
    await res.close();
  }
}

/// Страница движка: только модуль-мост.
const bergamotPageHtml = '<!doctype html><html><head><meta charset="utf-8"><title>Ogneliss translate</title>'
    '<script type="module" src="bridge.js"></script></head><body></body></html>';

/// Мост: ognTranslate(from, to, texts) → переводы по порядку; ognReset() —
/// заново прочитать registry.json (скачали или удалили язык).
String bergamotBridgeJs(int workers) => '''
import {BatchTranslator} from './engine/translator.js';
let tr = null;
function get() {
  if (!tr) tr = new BatchTranslator({registryUrl: 'registry.json', workers: $workers, downloadTimeout: 0, pivotLanguage: 'en'});
  return tr;
}
window.ognTranslate = async (from, to, texts) => {
  const t = get();
  return await Promise.all(texts.map((text) => text.trim() === ''
    ? text
    : t.translate({from, to, text, html: false, qualityScores: false}).then((r) => r.target.text)));
};
window.ognReset = () => {
  if (tr) { try { tr.delete(); } catch (e) {} }
  tr = null;
  return true;
};
window.ognReady = true;
''';

// lib/services/translation/bergamot/bergamot_models.dart
//
// Модели перевода для Windows (2.2.0): Firefox Translations (Mozilla,
// MPL-2.0) с сервера Ogneliss — решение владельца 09.11.2026 «модели с
// ogneliss.ru». Сервер выкладывает их скриптом
// server/translate-models/install-translate-models.sh; список — index.json
// в формате registry.json проекта Bergamot:
//
//   {"enru": {"model": {"name": "model.enru.intgemm.alphas.bin", "size": …,
//             "expectedSha256Hash": "…"}, "lex": {…}, "vocab": {…}}, …}
//
// Файл пары — <база>/<пара>/<name>. Пара — направление («enru» — с
// английского на русский); другие пары — через английский. «Язык» в
// приложении — обе пары с английским (как языки ML Kit на Android).
// Скачанное проверяется по sha256 и хранится в папке данных приложения:
// <support>/translate/bergamot/<пара>/, список файлов пары — manifest.json
// (пишется последним: нет его — пара не скачана).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../translation_languages.dart';

/// Папка моделей на сервере Ogneliss.
const bergamotModelsBase = 'https://ogneliss.ru/mail/translate/v1/';

/// Пары набора Firefox Translations 0.3.3 — языки до первого чтения
/// index.json (без сети).
const kBergamotKnownPairs = [
  'bgen', 'csen', 'deen', 'enbg', 'encs', 'ende', 'enes', 'enet', 'enfa', 'enfr', 'enit', 'ennl', 'enpl', //
  'enpt', 'enru', 'enuk', 'esen', 'eten', 'faen', 'fren', 'isen', 'iten', 'nben', 'nlen', 'nnen', 'plen',
  'pten', 'ruen', 'uken',
];

/// Файл модели: имя, размер, sha256 (hex).
class BergamotFile {
  final String name;
  final int size;
  final String sha256;
  const BergamotFile(this.name, this.size, this.sha256);

  static final _safeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
  static final _hex = RegExp(r'^[0-9a-f]{64}$');

  /// null — запись не годится (имя с путём, нет хэша, размер не тот).
  static BergamotFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    final size = j['size'];
    final hash = j['expectedSha256Hash'];
    if (name is! String || !_safeName.hasMatch(name) || name.contains('..')) return null;
    if (size is! int || size <= 0 || size > 512 * 1024 * 1024) return null;
    if (hash is! String || !_hex.hasMatch(hash.toLowerCase())) return null;
    return BergamotFile(name, size, hash.toLowerCase());
  }

  Map<String, Object> toJson({String prefix = ''}) =>
      {'name': '$prefix$name', 'size': size, 'expectedSha256Hash': sha256};
}

/// Пара моделей (направление перевода) и её файлы по ролям: model, lex,
/// vocab или srcvocab/trgvocab, qualityModel.
class BergamotPair {
  final String key;
  final Map<String, BergamotFile> files;
  const BergamotPair(this.key, this.files);

  String get from => key.substring(0, 2);
  String get to => key.substring(2, 4);
  int get size => files.values.fold(0, (s, f) => s + f.size);

  static final _key = RegExp(r'^[a-z]{4}$');

  static BergamotPair? fromJson(String key, Object? j) {
    if (!_key.hasMatch(key) || j is! Map) return null;
    final files = <String, BergamotFile>{};
    for (final e in j.entries) {
      final role = e.key;
      if (role is! String || !_roles.contains(role)) continue;
      final f = BergamotFile.fromJson(e.value);
      if (f != null) files[role] = f;
    }
    final vocab = files.containsKey('vocab') || (files.containsKey('srcvocab') && files.containsKey('trgvocab'));
    if (!files.containsKey('model') || !files.containsKey('lex') || !vocab) return null;
    return BergamotPair(key, files);
  }

  static const _roles = {'model', 'lex', 'vocab', 'srcvocab', 'trgvocab', 'qualityModel'};

  Map<String, Object> toJson({String prefix = ''}) => {for (final e in files.entries) e.key: e.value.toJson(prefix: prefix)};
}

/// Код языка приложения (normalizeLang) у моделей: норвежский — «nb»
/// (букмол; «nn» — нюношк, если букмола нет).
String bergamotAppLang(String model) => normalizeLang(model) ?? model;

/// Список моделей сервера.
class BergamotIndex {
  final Map<String, BergamotPair> pairs;

  /// Пары известны только по именам (встроенный список, без файлов).
  final bool offline;
  const BergamotIndex(this.pairs, {this.offline = false});

  static BergamotIndex parse(String body) {
    final j = jsonDecode(body);
    if (j is! Map) throw const FormatException('index.json: не объект');
    final pairs = <String, BergamotPair>{};
    for (final e in j.entries) {
      final p = e.key is String ? BergamotPair.fromJson(e.key as String, e.value) : null;
      if (p != null) pairs[p.key] = p;
    }
    if (pairs.isEmpty) throw const FormatException('index.json: нет моделей');
    return BergamotIndex(pairs);
  }

  /// Встроенный список: языки известны, файлов нет.
  static final builtIn =
      BergamotIndex({for (final k in kBergamotKnownPairs) k: BergamotPair(k, const {})}, offline: true);

  /// Языки (коды приложения), английский — тоже.
  Set<String> get languages => {'en', for (final p in pairs.values) ...[bergamotAppLang(p.from), bergamotAppLang(p.to)]};

  /// Код модели для языка приложения: «no» → «nb» (или «nn»).
  String? modelLang(String app, {required bool asSource}) {
    final codes = [for (final p in pairs.values) asSource ? p.from : p.to];
    if (codes.contains(app)) return app;
    for (final c in codes) {
      if (bergamotAppLang(c) == app && c == 'nb') return c;
    }
    for (final c in codes) {
      if (bergamotAppLang(c) == app) return c;
    }
    return null;
  }

  /// Пары для перевода [from] → [to] (коды приложения): прямая или через
  /// английский. null — так не перевести.
  List<String>? route(String from, String to) {
    if (from == to) return const [];
    final f = modelLang(from, asSource: true);
    final t = modelLang(to, asSource: false);
    if (f == null || t == null) return null;
    if (pairs.containsKey('$f$t')) return ['$f$t'];
    if (f == 'en' || t == 'en') return null;
    if (pairs.containsKey('${f}en') && pairs.containsKey('en$t')) return ['${f}en', 'en$t'];
    return null;
  }

  /// Пары языка [lang] с английским (в обе стороны, какие есть).
  List<String> pairsOf(String lang) => [
        for (final p in pairs.values)
          if ((bergamotAppLang(p.from) == lang && p.to == 'en') || (p.from == 'en' && bergamotAppLang(p.to) == lang))
            p.key,
      ]..sort();
}

/// Модели на диске и их скачивание.
class BergamotStore {
  /// <support>/translate/bergamot.
  final Directory root;
  final Uri base;
  final http.Client Function() client;
  BergamotStore(this.root, {Uri? base, http.Client Function()? client})
      : base = base ?? Uri.parse(bergamotModelsBase),
        client = client ?? http.Client.new;

  static const _indexMaxAge = Duration(days: 7);

  File get _indexFile => File('${root.path}${Platform.pathSeparator}index.json');

  Directory _pairDir(String key) => Directory('${root.path}${Platform.pathSeparator}$key');

  BergamotIndex? _index;
  DateTime? _failedAt;
  static const _retryAfter = Duration(minutes: 10);

  /// Список моделей: сохранённый (моложе недели), с сервера, сохранённый
  /// старше недели, встроенный — что найдётся первым. [refresh] — сразу с
  /// сервера (перед скачиванием: файлы могли смениться).
  Future<BergamotIndex> index({bool refresh = false}) async {
    if (!refresh && _index != null && !_index!.offline) return _index!;
    // Сервер недоступен — не чаще раза в 10 минут (без сети каждый вызов
    // ждал бы 20 секунд).
    final failed = _failedAt;
    if (!refresh && _index != null && failed != null && DateTime.now().difference(failed) < _retryAfter) {
      return _index!;
    }
    BergamotIndex? saved;
    try {
      if (_indexFile.existsSync()) {
        saved = BergamotIndex.parse(await _indexFile.readAsString());
        final fresh = DateTime.now().difference(_indexFile.lastModifiedSync()) < _indexMaxAge;
        if (fresh && !refresh) return _index = saved;
      }
    } catch (_) {
      saved = null;
    }
    final c = client();
    try {
      final r = await c.get(base.resolve('index.json')).timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) {
        final body = utf8.decode(r.bodyBytes);
        final idx = BergamotIndex.parse(body);
        await root.create(recursive: true);
        await _indexFile.writeAsString(body, flush: true);
        _failedAt = null;
        return _index = idx;
      }
      if (refresh) throw HttpException('index.json: ${r.statusCode}', uri: base.resolve('index.json'));
    } catch (_) {
      _failedAt = DateTime.now();
      if (refresh) rethrow;
    } finally {
      c.close();
    }
    _failedAt ??= DateTime.now();
    return _index = saved ?? BergamotIndex.builtIn;
  }

  /// Скачанные пары: manifest.json есть, файлы на месте нужного размера.
  Map<String, BergamotPair> installed() {
    final out = <String, BergamotPair>{};
    if (!root.existsSync()) return out;
    for (final d in root.listSync().whereType<Directory>()) {
      final key = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final m = File('${d.path}${Platform.pathSeparator}manifest.json');
      if (!m.existsSync()) continue;
      try {
        final p = BergamotPair.fromJson(key, jsonDecode(m.readAsStringSync()));
        if (p == null) continue;
        final ok = p.files.values.every((f) {
          final file = File('${d.path}${Platform.pathSeparator}${f.name}');
          return file.existsSync() && file.lengthSync() == f.size;
        });
        if (ok) out[key] = p;
      } catch (_) {}
    }
    return out;
  }

  /// Файл скачанной пары для локального сервера движка; null — нет такого.
  File? file(String key, String name) {
    final p = installed()[key];
    if (p == null || !p.files.values.any((f) => f.name == name)) return null;
    return File('${_pairDir(key).path}${Platform.pathSeparator}$name');
  }

  /// Скачать пару [p]: файлы во временные, проверка размера и sha256,
  /// затем manifest.json. [progress] — байты скачано / всего.
  Future<void> download(BergamotPair p, {void Function(int done, int total)? progress}) async {
    if (p.files.isEmpty) throw StateError('нет списка файлов пары ${p.key}');
    final dir = _pairDir(p.key);
    await dir.create(recursive: true);
    final manifest = File('${dir.path}${Platform.pathSeparator}manifest.json');
    if (manifest.existsSync()) await manifest.delete();
    final total = p.size;
    var done = 0;
    final c = client();
    try {
      for (final f in p.files.values) {
        final target = File('${dir.path}${Platform.pathSeparator}${f.name}');
        if (target.existsSync() && target.lengthSync() == f.size && await _sha(target) == f.sha256) {
          done += f.size;
          progress?.call(done, total);
          continue;
        }
        final part = File('${target.path}.part');
        final uri = base.resolve('${p.key}/${f.name}');
        final r = await c.send(http.Request('GET', uri)).timeout(const Duration(seconds: 30));
        if (r.statusCode != 200) {
          await r.stream.drain<void>();
          throw HttpException('${p.key}/${f.name}: ${r.statusCode}', uri: uri);
        }
        final sink = part.openWrite();
        final hashOut = _DigestSink();
        final hasher = sha256.startChunkedConversion(hashOut);
        var got = 0;
        try {
          await for (final chunk in r.stream.timeout(const Duration(seconds: 60))) {
            got += chunk.length;
            if (got > f.size) throw HttpException('${f.name}: больше ${f.size} байт', uri: uri);
            hasher.add(chunk);
            sink.add(chunk);
            progress?.call(done + got, total);
          }
        } finally {
          await sink.close();
        }
        hasher.close();
        if (got != f.size || hashOut.value.toString() != f.sha256) {
          await part.delete();
          throw HttpException('${f.name}: файл не совпал с index.json', uri: uri);
        }
        if (target.existsSync()) await target.delete();
        await part.rename(target.path);
        done += f.size;
      }
    } finally {
      c.close();
    }
    await manifest.writeAsString(jsonEncode(p.toJson()), flush: true);
  }

  /// Удалить пару.
  Future<void> delete(String key) async {
    final d = _pairDir(key);
    if (d.existsSync()) await d.delete(recursive: true);
  }

  /// registry.json для движка: скачанные пары, файлы — models/<пара>/<имя>.
  Map<String, Object> localRegistry() =>
      {for (final e in installed().entries) e.key: e.value.toJson(prefix: 'models/${e.key}/')};

  static Future<String> _sha(File f) async => (await sha256.bind(f.openRead()).first).toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

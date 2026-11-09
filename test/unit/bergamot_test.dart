// Перевод на Windows (2.2.0): модели Bergamot с сервера Ogneliss, локальный
// сервер движка, Translator поверх них. Движок (WebView2) — подделка; сам
// WebAssembly проверялся в Chromium вручную (docs/guides/TRANSLATION_WINDOWS.md).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/services/translation/bergamot/bergamot_models.dart';
import 'package:ogneliss/services/translation/bergamot/bergamot_server.dart';
import 'package:ogneliss/services/translation/bergamot/bergamot_translator.dart';

/// Файлы «сервера»: пара → имя → содержимое.
Map<String, Map<String, List<int>>> _files(List<String> pairs) => {
      for (final p in pairs)
        p: {
          'model.$p.bin': utf8.encode('model-$p' * 50),
          'lex.$p.bin': utf8.encode('lex-$p' * 20),
          'vocab.$p.spm': utf8.encode('vocab-$p' * 10),
        },
    };

String _index(Map<String, Map<String, List<int>>> files) => jsonEncode({
      for (final e in files.entries)
        e.key: {
          for (final f in e.value.entries)
            (f.key.startsWith('model')
                ? 'model'
                : f.key.startsWith('lex')
                    ? 'lex'
                    : 'vocab'): {
              'name': f.key,
              'size': f.value.length,
              'expectedSha256Hash': sha256.convert(f.value).toString(),
            },
        },
    });

/// Клиент «сервера Ogneliss»; [broken] — файл, который отдаётся испорченным.
http.Client Function() _client(Map<String, Map<String, List<int>>> files, {String? broken, List<String>? log}) =>
    () => MockClient((req) async {
          log?.add(req.url.path);
          final segs = req.url.pathSegments;
          if (segs.last == 'index.json') return http.Response(_index(files), 200);
          final body = files[segs[segs.length - 2]]?[segs.last];
          if (body == null) return http.Response('', 404);
          final out = segs.last == broken ? [...body.sublist(1), 0] : body;
          return http.Response.bytes(out, 200);
        });

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('bergamot_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('index.json', () {
    test('плохие записи пропускаются: путь в имени, нет хэша, нет словаря', () {
      final good = {'name': 'model.enru.bin', 'size': 10, 'expectedSha256Hash': 'a' * 64};
      final idx = BergamotIndex.parse(jsonEncode({
        'enru': {'model': good, 'lex': {...good, 'name': 'lex.bin'}, 'vocab': {...good, 'name': 'v.spm'}},
        'ende': {'model': {...good, 'name': '../../evil'}, 'lex': good, 'vocab': good},
        'enfr': {'model': {...good, 'expectedSha256Hash': 'xyz'}, 'lex': good, 'vocab': good},
        'enit': {'model': good, 'lex': good},
        'bad!': {'model': good, 'lex': good, 'vocab': good},
      }));
      expect(idx.pairs.keys, ['enru']);
      expect(() => BergamotIndex.parse('[]'), throwsFormatException);
      expect(() => BergamotIndex.parse('{}'), throwsFormatException);
    });

    test('языки, путь через английский, норвежский — «no» (модель «nb»)', () {
      final idx = BergamotIndex.builtIn;
      expect(idx.languages, containsAll(['en', 'ru', 'de', 'uk', 'no', 'is']));
      expect(idx.languages, isNot(contains('nb')));
      expect(idx.route('en', 'ru'), ['enru']);
      expect(idx.route('de', 'ru'), ['deen', 'enru']);
      expect(idx.route('no', 'ru'), ['nben', 'enru']);
      expect(idx.route('ru', 'no'), isNull, reason: 'на норвежский моделей нет');
      expect(idx.route('ru', 'ru'), isEmpty);
      expect(idx.modelLang('no', asSource: true), 'nb');
      expect(idx.pairsOf('ru'), ['enru', 'ruen']);
      expect(idx.pairsOf('no'), ['nben', 'nnen']);
    });
  });

  group('BergamotStore', () {
    test('скачивание: sha256 и размер, manifest.json, registry для движка, удаление', () async {
      final files = _files(['enru', 'ruen']);
      final store = BergamotStore(tmp, base: Uri.parse('https://ogneliss.test/v1/'), client: _client(files));
      final idx = await store.index(refresh: true);
      final progress = <int>[];
      await store.download(idx.pairs['enru']!, progress: (d, t) => progress.add(d));
      expect(store.installed().keys, ['enru']);
      expect(progress.last, idx.pairs['enru']!.size);
      final reg = store.localRegistry();
      expect((reg['enru'] as Map)['model'], containsPair('name', 'models/enru/model.enru.bin'));
      expect(store.file('enru', 'vocab.enru.spm')?.readAsBytesSync(), files['enru']!['vocab.enru.spm']);
      expect(store.file('enru', 'other.bin'), isNull, reason: 'только файлы из manifest.json');
      expect(store.file('ruen', 'vocab.ruen.spm'), isNull, reason: 'пара не скачана');
      await store.delete('enru');
      expect(store.installed(), isEmpty);
    });

    test('файл не совпал с index.json — пара не скачана, обрывков нет', () async {
      final files = _files(['enru']);
      final store = BergamotStore(tmp,
          base: Uri.parse('https://ogneliss.test/v1/'), client: _client(files, broken: 'lex.enru.bin'));
      final idx = await store.index(refresh: true);
      await expectLater(store.download(idx.pairs['enru']!), throwsA(isA<HttpException>()));
      expect(store.installed(), isEmpty);
      final left = Directory('${tmp.path}/enru').listSync().map((e) => e.path.split('/').last).toList();
      expect(left.where((n) => n.endsWith('.part') || n == 'manifest.json'), isEmpty);
    });

    test('без сети — встроенный список, повтор не чаще раза в 10 минут', () async {
      final log = <String>[];
      final store = BergamotStore(tmp, client: () => MockClient((req) async {
            log.add(req.url.path);
            throw http.ClientException('offline');
          }));
      final a = await store.index();
      expect(a.offline, isTrue);
      expect(a.languages, contains('ru'));
      await store.index();
      expect(log, hasLength(1));
      await expectLater(store.index(refresh: true), throwsA(isA<http.ClientException>()));
    });
  });

  group('локальный сервер движка', () {
    late BergamotServer server;
    late Uri page;

    setUp(() async {
      final engine = Directory('${tmp.path}/engine')..createSync();
      for (final f in kBergamotEngineFiles) {
        File('${engine.path}/$f')
          ..parent.createSync(recursive: true)
          ..writeAsStringSync('// $f');
      }
      final files = _files(['enru']);
      final store = BergamotStore(Directory('${tmp.path}/models'),
          base: Uri.parse('https://ogneliss.test/v1/'), client: _client(files));
      await store.download((await store.index(refresh: true)).pairs['enru']!);
      server = BergamotServer(engineDir: engine, store: store, workers: 1);
      page = await server.start();
    });
    tearDown(() => server.close());

    Future<HttpClientResponse> get(Uri u, {String method = 'GET', String? host}) async {
      final c = HttpClient();
      final req = await c.openUrl(method, u);
      if (host != null) req.headers.set(HttpHeaders.hostHeader, host);
      final r = await req.close();
      c.close();
      return r;
    }

    test('страница, мост, registry.json, файлы движка и моделей', () async {
      expect(page.host, '127.0.0.1');
      final r = await get(page);
      expect(r.statusCode, 200);
      expect(r.headers.value('content-security-policy'), contains("connect-src 'self'"));
      expect(await utf8.decodeStream(r), contains('bridge.js'));
      final bridge = await get(page.resolve('bridge.js'));
      expect(await utf8.decodeStream(bridge), contains('workers: 1'));
      final reg = jsonDecode(await utf8.decodeStream(await get(page.resolve('registry.json')))) as Map;
      expect(reg.keys, ['enru']);
      final wasm = await get(page.resolve('engine/worker/bergamot-translator-worker.wasm'));
      expect(wasm.headers.contentType?.mimeType, 'application/wasm');
      await wasm.drain<void>();
      final worker = await get(page.resolve('engine/worker/translator-worker.js'));
      expect(worker.headers.value('content-security-policy'), contains('wasm-unsafe-eval'));
      await worker.drain<void>();
      final model = await get(page.resolve('models/enru/vocab.enru.spm'));
      expect(model.statusCode, 200);
      await model.drain<void>();
    });

    test('чужой Host, без ключа, не GET, «..», не из списка — отказ', () async {
      Future<int> code(Uri u, {String method = 'GET', String? host}) async {
        final r = await get(u, method: method, host: host);
        await r.drain<void>();
        return r.statusCode;
      }

      expect(await code(page, host: 'evil.example:${page.port}'), 403);
      expect(await code(page.replace(path: '/index.html')), 404);
      expect(await code(page.replace(path: '/${'0' * 64}/index.html')), 404);
      expect(await code(page, method: 'POST'), 405);
      expect(await code(page.resolve('engine/main.js')), 404);
      expect(await code(page.replace(path: '${page.path.replaceAll('index.html', '')}engine/%2E%2E/x')), 404);
      expect(await code(page.resolve('models/enru/other.bin')), 404);
      expect(await code(page.resolve('models/ruen/vocab.ruen.spm')), 404);
      expect(server.owns(page), isTrue);
      expect(server.owns(Uri.parse('https://example.com${page.path}')), isFalse);
    });
  });

  group('BergamotTranslator', () {
    late _FakeEngine engine;
    late BergamotTranslator t;
    final files = _files(['enru', 'ruen', 'deen', 'ende', 'nben']);

    setUp(() {
      engine = _FakeEngine();
      t = BergamotTranslator(
        store: () async => BergamotStore(tmp, base: Uri.parse('https://ogneliss.test/v1/'), client: _client(files)),
        engine: (_) => engine,
        enginePresent: () => true,
      );
    });

    test('недостающие языки, скачивание обеих пар языка, перевод через движок', () async {
      expect(await t.isAvailable(), isTrue);
      await (await t.store).index(refresh: true);
      expect(await t.supportedLanguages(), containsAll(['en', 'ru', 'de', 'no']));
      expect(await t.missingModels('de', 'ru'), unorderedEquals(['de', 'ru']));
      await t.download('de', 'ru', wifiOnly: false);
      expect(await t.missingModels('de', 'ru'), isEmpty);
      expect(await t.downloadedModels(), {'de', 'ru'});
      expect(engine.resets, 1);
      expect(await t.translate(['Hallo'], from: 'de', to: 'ru'), ['de>ru:Hallo']);
      await t.download('no', 'ru', wifiOnly: false);
      expect(await t.translate(['Hei'], from: 'no', to: 'ru'), ['nb>ru:Hei'], reason: 'норвежский — модель «nb»');
      await t.deleteModel('de');
      expect(await t.downloadedModels(), {'ru', 'no'});
      expect(await t.missingModels('de', 'ru'), ['de']);
      expect(() => t.missingModels('ru', 'no'), throwsUnsupportedError);
    });

    test('язык письма — свой определитель; названия — CLDR на языке приложения', () async {
      final d = await t.identifyLanguage('Добрый день! Спасибо за отчёт, мы отправим договор в понедельник.');
      expect(d?.lang, 'ru');
      final ru = await t.languageNames(['de', 'no', 'uk', 'xx'], 'ru');
      expect(ru, {'de': 'немецкий', 'no': 'норвежский', 'uk': 'украинский', 'xx': 'XX'});
      expect((await t.languageNames(['de'], 'nb'))['de'], 'tysk');
      expect(t.googleAttribution, isFalse);
      expect(t.canManageModels, isTrue);
    });
  });
}

class _FakeEngine implements BergamotEngine {
  int resets = 0;
  @override
  Future<List<String>> translate(String from, String to, List<String> texts) async =>
      [for (final s in texts) '$from>$to:$s'];
  @override
  Future<void> reset() async => resets++;
}

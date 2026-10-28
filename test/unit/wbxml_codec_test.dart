// test/unit/wbxml_codec_test.dart
// WBXML-кодек ActiveSync — самое рискованное место движка: ошибка в нём
// означает, что почта не работает вовсе (TECH_DEBT_AUDIT, раздел 3).
// Проверяем байты по примеру из [MS-ASWBXML], кодовые страницы, многобайтные
// длины, кириллицу, устойчивость к обрезанному ответу и таблицу тегов.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

String _dump(WbxmlDocument d) => d.root.toString();

WbxmlDocument _roundTrip(WbxmlDocument doc) => WbxmlDecoder().decode(WbxmlEncoder().encode(doc));

/// Запрос Sync с переходом AirSync → AirSyncBase → обратно в AirSync.
WbxmlDocument _syncRequest() {
  final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
  final col = root.addChild('Collections').addChild('Collection');
  col.addChild('SyncKey', text: '1234567890');
  col.addChild('CollectionId', text: '5');
  col.addChild('GetChanges', text: '');
  col.addChild('WindowSize', text: '50');
  final opts = col.addChild('Options');
  final pref = opts.addChild('BodyPreference', namespace: 'AirSyncBase');
  pref.addChild('Type', text: '2');
  pref.addChild('TruncationSize', text: '65536');
  opts.addChild('FilterType', text: '3'); // снова AirSync после AirSyncBase
  return WbxmlDocument(root: root);
}

void main() {
  group('байты по спецификации', () {
    // [MS-ASWBXML]: FolderSync с SyncKey 0.
    final folderSync = _bytes([0x03, 0x01, 0x6A, 0x00, 0x00, 0x07, 0x56, 0x52, 0x03, 0x30, 0x00, 0x01, 0x01]);

    test('кодирование FolderSync', () {
      final root = WbxmlElement(name: 'FolderSync', namespace: 'FolderHierarchy');
      root.addChild('SyncKey', text: '0');
      expect(WbxmlEncoder().encode(WbxmlDocument(root: root)), folderSync);
    });

    test('разбор FolderSync', () {
      final d = WbxmlDecoder().decode(folderSync);
      expect(d.version, 3);
      expect(d.charset, 106);
      expect(d.root.name, 'FolderSync');
      expect(d.root.namespace, 'FolderHierarchy');
      expect(d.root.childText('SyncKey'), '0');
    });

    test('пустой элемент — без флага содержимого и без END', () {
      final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
      final b = WbxmlEncoder().encode(WbxmlDocument(root: root));
      // заголовок, SWITCH_PAGE 14, тег Provision (0x05) без бита 0x40
      expect(b, _bytes([0x03, 0x01, 0x6A, 0x00, 0x00, 0x0E, 0x05]));
    });
  });

  group('туда и обратно', () {
    test('несколько кодовых страниц и возврат на прежнюю', () {
      final doc = _syncRequest();
      final back = _roundTrip(doc);
      expect(_dump(back), _dump(doc));
      final opts = back.root.findChild('Collections')!.findChild('Collection')!.findChild('Options')!;
      expect(opts.findChild('BodyPreference')!.namespace, 'AirSyncBase');
      expect(opts.findChild('FilterType')!.namespace, 'AirSync');
      expect(opts.childText('FilterType'), '3');
    });

    test('кириллица, эмодзи и пустая строка', () {
      final root = WbxmlElement(name: 'Settings', namespace: 'Settings');
      final info = root.addChild('DeviceInformation').addChild('Set');
      info.addChild('FriendlyName', text: 'Телефон Олега 📱');
      info.addChild('OSLanguage', text: 'ru-RU');
      info.addChild('Model', text: '');
      final back = _roundTrip(WbxmlDocument(root: root));
      final set = back.root.findChild('DeviceInformation')!.findChild('Set')!;
      expect(set.childText('FriendlyName'), 'Телефон Олега 📱');
      expect(set.childText('Model'), '');
    });

    for (final len in [0, 1, 127, 128, 300, 16383, 16384, 70000]) {
      test('непрозрачные данные длиной $len', () {
        final data = Uint8List.fromList(List.generate(len, (i) => i & 0xFF));
        final root = WbxmlElement(name: 'SendMail', namespace: 'ComposeMail');
        root.addChild('ClientId', text: 'abc');
        root.addChild('MIME', opaqueData: data);
        final back = _roundTrip(WbxmlDocument(root: root));
        expect(back.root.findChild('MIME')!.opaqueData, data);
        expect(back.root.childText('ClientId'), 'abc');
      });
    }

    test('длина 128 кодируется двумя байтами 0x81 0x00', () {
      final root = WbxmlElement(name: 'SendMail', namespace: 'ComposeMail');
      root.addChild('MIME', opaqueData: Uint8List(128));
      final b = WbxmlEncoder().encode(WbxmlDocument(root: root));
      final i = b.indexOf(0xC3); // OPAQUE
      expect(b.sublist(i + 1, i + 3), [0x81, 0x00]);
    });
  });

  group('разбор ответов сервера', () {
    test('текст из нескольких STR_I склеивается', () {
      final b = _bytes([
        0x03, 0x01, 0x6A, 0x00, 0x00, 0x07, 0x56, 0x52, //
        0x03, 0x61, 0x00, 0x03, 0x62, 0x63, 0x00, 0x01, 0x01,
      ]);
      expect(WbxmlDecoder().decode(b).root.childText('SyncKey'), 'abc');
    });

    test('неизвестный токен не роняет разбор', () {
      // SyncKey (0x52) и рядом токен 0x7E без имени в таблице FolderHierarchy.
      final b = _bytes([0x03, 0x01, 0x6A, 0x00, 0x00, 0x07, 0x56, 0x52, 0x03, 0x31, 0x00, 0x01, 0x7E, 0x03, 0x78, 0x00, 0x01, 0x01]);
      final d = WbxmlDecoder().decode(b);
      expect(d.root.childText('SyncKey'), '1');
      expect(d.root.children.last.name, startsWith('Tag_0x'));
    });

    test('обрезанный ответ (обрыв связи) — без исключений на любой длине', () {
      final root = _syncRequest().root;
      root.addChild('MIME', namespace: 'ComposeMail', opaqueData: Uint8List(500));
      final full = WbxmlEncoder().encode(WbxmlDocument(root: root));
      for (var n = 0; n <= full.length; n++) {
        expect(() => WbxmlDecoder().decode(Uint8List.fromList(full.sublist(0, n))), returnsNormally,
            reason: 'длина $n из ${full.length}');
      }
    });

    test('крупный ответ разбирается и через изолят', () async {
      final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
      final data = Uint8List.fromList(List.generate(200 * 1024, (i) => (i * 7) & 0xFF));
      root.addChild('Response').addChild('Fetch').addChild('Data', opaqueData: data);
      final back = await decodeWbxmlAsync(WbxmlEncoder().encode(WbxmlDocument(root: root)));
      expect(back.root.findChild('Response')!.findChild('Fetch')!.findChild('Data')!.opaqueData, data);
    });
  });

  test('таблица тегов: имя ↔ токен однозначно на каждой странице', () {
    for (final page in AsTags.tags.entries) {
      for (final tag in page.value.entries) {
        expect(AsTags.getToken(page.key, tag.value), tag.key,
            reason: 'страница ${page.key}, ${tag.value}');
        expect(AsTags.getTagName(page.key, tag.key), tag.value);
      }
    }
    for (final page in AsTags.specExtras.entries) {
      for (final tag in page.value.entries) {
        expect(AsTags.getToken(page.key, tag.value), tag.key,
            reason: 'страница ${page.key}, ${tag.value} (specExtras)');
      }
    }
    // Ключевые токены по [MS-ASWBXML].
    expect(AsTags.getToken(0, 'Sync'), 0x05);
    expect(AsTags.getToken(0, 'SyncKey'), 0x0B);
    expect(AsTags.getToken(7, 'FolderSync'), 0x16);
    expect(AsTags.getToken(14, 'PolicyKey'), 0x09);
    expect(AsTags.getToken(14, 'AccountOnlyRemoteWipe'), 0x3B);
    expect(AsTags.getToken(13, 'HeartbeatInterval'), 0x08);
    expect(AsTags.getToken(17, 'BodyPreference'), 0x05);
    expect(AsTags.getToken(18, 'DeviceInformation'), 0x16);
    expect(AsTags.getToken(21, 'SendMail'), 0x05);
  });

  test('страницы ↔ пространства имён согласованы', () {
    for (final e in AsCodePages.namespaceToPage.entries) {
      expect(AsCodePages.pageToNamespace[e.value], e.key);
    }
  });
}

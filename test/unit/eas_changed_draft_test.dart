// Черновик, исправленный на сервере (2.7.2, замечание владельца 24.11.2026:
// «сохранил черновик с телефона, отредактировал на сервере — на телефоне не
// обновился»). ActiveSync сообщает о правке командой Change только с
// изменёнными свойствами; раньше приложение брало из неё лишь «прочитано» и
// флажок. Теперь письмо с изменённым содержимым перечитывается целиком.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _cfg = AccountConfig(
  email: 'oleg@corp.example',
  password: 'secret',
  exchangeServer: 'mail.corp.example',
  deviceId: 'TESTDEVICE0001',
  forceTransport: MailTransportKind.eas,
);

http.Response _wbxml(WbxmlElement root) => http.Response.bytes(
    WbxmlEncoder().encode(WbxmlDocument(root: root)), 200,
    headers: {'content-type': 'application/vnd.ms-sync.wbxml'});

WbxmlElement _provision() {
  final root = WbxmlElement(name: 'Provision', namespace: 'Provision');
  root.addChild('Status', namespace: 'Provision', text: '1');
  final p = root.addChild('Policies', namespace: 'Provision').addChild('Policy', namespace: 'Provision');
  p.addChild('PolicyType', namespace: 'Provision', text: 'MS-EAS-Provisioning-WBXML');
  p.addChild('Status', namespace: 'Provision', text: '2');
  return root;
}

/// Ответ Sync: черновик d1 — новая тема и текст; письмо m1 — только «прочитано».
WbxmlElement _sync() {
  final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
  final col = root.addChild('Collections', namespace: 'AirSync').addChild('Collection', namespace: 'AirSync');
  col.addChild('SyncKey', namespace: 'AirSync', text: 'k2');
  col.addChild('CollectionId', namespace: 'AirSync', text: 'drafts');
  col.addChild('Status', namespace: 'AirSync', text: '1');
  final cmds = col.addChild('Commands', namespace: 'AirSync');
  final ch = cmds.addChild('Change', namespace: 'AirSync');
  ch.addChild('ServerId', namespace: 'AirSync', text: 'd1');
  final app = ch.addChild('ApplicationData', namespace: 'AirSync');
  app.addChild('Subject', namespace: 'Email', text: 'Инструктаж — новое');
  final ch2 = cmds.addChild('Change', namespace: 'AirSync');
  ch2.addChild('ServerId', namespace: 'AirSync', text: 'm1');
  ch2.addChild('ApplicationData', namespace: 'AirSync').addChild('Read', namespace: 'Email', text: '1');
  return root;
}

/// Ответ ItemOperations: черновик целиком.
WbxmlElement _fetch(String serverId) {
  final root = WbxmlElement(name: 'ItemOperations', namespace: 'ItemOperations');
  root.addChild('Status', namespace: 'ItemOperations', text: '1');
  final f = root.addChild('Response', namespace: 'ItemOperations').addChild('Fetch', namespace: 'ItemOperations');
  f.addChild('Status', namespace: 'ItemOperations', text: '1');
  f.addChild('CollectionId', namespace: 'AirSync', text: 'drafts');
  f.addChild('ServerId', namespace: 'AirSync', text: serverId);
  final p = f.addChild('Properties', namespace: 'ItemOperations');
  p.addChild('To', namespace: 'Email', text: '"Клинов А.С." <andrey@corp.example>');
  p.addChild('From', namespace: 'Email', text: '"Ермишин О.А." <oleg@corp.example>');
  p.addChild('Subject', namespace: 'Email', text: 'Инструктаж — новое');
  p.addChild('DateReceived', namespace: 'Email', text: '2026-11-24T08:00:00.000Z');
  p.addChild('Read', namespace: 'Email', text: '1');
  final b = p.addChild('Body', namespace: 'AirSyncBase');
  b.addChild('Type', namespace: 'AirSyncBase', text: '2');
  b.addChild('Data', namespace: 'AirSyncBase', text: '<p>Текст, исправленный в Outlook</p>');
  return root;
}

void main() {
  setUp(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  test('Change с темой — черновик перечитан целиком; Change «прочитано» — нет', () async {
    final fetched = <String>[];
    final eng = EasEngine(
      httpClient: MockClient((req) async {
        if (req.method == 'OPTIONS') {
          return http.Response('', 200, headers: {
            'ms-asprotocolversions': '14.1,16.1',
            'ms-asprotocolcommands': 'Sync,FolderSync,Provision,ItemOperations',
          });
        }
        final cmd = req.url.queryParameters['Cmd'];
        if (cmd == 'Provision') return _wbxml(_provision());
        if (cmd == 'Sync') return _wbxml(_sync());
        if (cmd == 'ItemOperations') {
          final doc = WbxmlDecoder().decode(Uint8List.fromList(req.bodyBytes));
          final f = doc.root.findChild('Fetch')!;
          final sid = f.childText('ServerId')!;
          fetched.add(sid);
          // Полный текст HTML, без обрезки.
          final bp = f.findChild('Options')!.findChild('BodyPreference')!;
          expect(bp.childText('Type'), '2');
          expect(bp.findChild('TruncationSize'), isNull);
          return _wbxml(_fetch(sid));
        }
        return http.Response('', 500);
      }),
    );
    expect((await eng.connect(_cfg)).success, isTrue);
    final r = await eng.syncFolder('drafts', since: const SyncState('k1'));
    expect(fetched, ['d1'], reason: 'только письмо с изменённым содержимым');
    expect(r.changed, hasLength(1));
    final d = r.changed.single;
    expect(d.id, 'd1');
    expect(d.folderId, 'drafts');
    expect(d.subject, 'Инструктаж — новое');
    expect(d.bodyHtml, '<p>Текст, исправленный в Outlook</p>');
    expect(d.to.single.email, 'andrey@corp.example');
    expect(d.from.email, 'oleg@corp.example');
    expect(r.flagChanges.single.id, 'm1');
    expect(r.flagChanges.single.read, isTrue);
    expect(r.newState?.token, 'k2');
  });
}

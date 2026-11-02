// Запись встречи в Exchange ActiveSync 16 (1.10.3, журнал владельца 02.11.2026):
// встреча «на весь день» — без TimeZone и с датами без времени (MS-ASCAL
// 2.2.2.1); при отказе (Status 6) — один повтор в прежнем виде. Ключ папки,
// отклонённый сервером (Status 3), — новый ключ и повтор записи, а не ошибка
// при каждой следующей попытке.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mail_engine/mail_engine.dart';

const _email = 'user@example.com';
const _server = 'mail.example.com';
const _device = 'TESTDEVICE0001';
const _fid = '43';

AccountConfig _cfg() => const AccountConfig(
      email: _email,
      password: 'secret',
      exchangeServer: _server,
      deviceId: _device,
      forceTransport: MailTransportKind.eas,
    );

String _session() => jsonEncode({
      'v': 1,
      'server': _server,
      'device': _device,
      'url': 'https://$_server/Microsoft-Server-ActiveSync',
      'host': _server,
      'proto': '16.1',
      'b64': false,
      'versions': ['14.1', '16.0', '16.1'],
      'cmds': ['Sync', 'FolderSync', 'Ping'],
      'key': '1234567890',
      'at': DateTime.now().millisecondsSinceEpoch,
    });

String _compactUtc(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// Ответ Sync: коллекция со статусом, ключом и (для записи) ответом на Add.
http.Response _syncResponse({required String status, String? key, String? addStatus, String? serverId}) {
  final root = WbxmlElement(name: 'Sync', namespace: 'AirSync');
  final col = root
      .addChild('Collections', namespace: 'AirSync')
      .addChild('Collection', namespace: 'AirSync');
  if (key != null) col.addChild('SyncKey', namespace: 'AirSync', text: key);
  col.addChild('CollectionId', namespace: 'AirSync', text: _fid);
  col.addChild('Status', namespace: 'AirSync', text: status);
  if (addStatus != null) {
    final add = col.addChild('Responses', namespace: 'AirSync').addChild('Add', namespace: 'AirSync');
    add.addChild('ClientId', namespace: 'AirSync', text: 'c1');
    if (serverId != null) add.addChild('ServerId', namespace: 'AirSync', text: serverId);
    add.addChild('Status', namespace: 'AirSync', text: addStatus);
  }
  return http.Response.bytes(WbxmlEncoder().encode(WbxmlDocument(root: root)), 200,
      headers: {'content-type': 'application/vnd.ms-sync.wbxml'});
}

/// Запрос Sync, разобранный обратно: ключ и поля ApplicationData.
class _Req {
  final String key;
  final Map<String, String?> data;
  final bool isAdd;
  _Req(this.key, this.data, this.isAdd);
}

_Req _parse(Uint8List body) {
  final doc = WbxmlDecoder().decode(body);
  final col = doc.root.findChild('Collections')!.findChild('Collection')!;
  final add = col.findChild('Commands')?.findChild('Add');
  final app = add?.findChild('ApplicationData');
  return _Req(col.childText('SyncKey')!, {
    for (final c in app?.children ?? const <WbxmlElement>[]) c.name: c.text,
  }, add != null);
}

Map<String, String?> _allDayFields() {
  final start = DateTime(2026, 11, 3);
  final end = DateTime(2026, 11, 4);
  return {
    'TimeZone': base64.encode(List<int>.filled(172, 0)),
    'Subject': 'Собрание',
    'StartTime': _compactUtc(start),
    'EndTime': _compactUtc(end),
    'AllDayEvent': '1',
    'BusyStatus': '2',
    'Reminder': '15',
    'Sensitivity': '0',
  };
}

void main() {
  late List<_Req> requests;
  late http.Response Function(_Req r, int n) reply;

  MockClient client() => MockClient((req) async {
        final r = _parse(req.bodyBytes);
        requests.add(r);
        return reply(r, requests.length);
      });

  Future<EasEngine> engine() async {
    EasEngine.loadSession = (_) => _session();
    final eng = EasEngine(httpClient: client());
    expect((await eng.connect(_cfg())).success, isTrue);
    eng.restorePimSyncKey(_fid, 'K1');
    return eng;
  }

  setUp(() => requests = []);
  tearDown(() {
    EasEngine.loadSession = null;
    EasEngine.saveSession = null;
  });

  test('дата без времени: местная полночь в UTC → дата того же дня', () {
    expect(EasEngine.floatingDate(_compactUtc(DateTime(2026, 11, 3))), '20261103T000000Z');
    expect(EasEngine.floatingDate(_compactUtc(DateTime(2026, 12, 31))), '20261231T000000Z');
    expect(EasEngine.floatingDate('мусор'), 'мусор');
    expect(EasEngine.floatingDate(null), isNull);
  });

  test('весь день в AS 16 — без TimeZone, даты без времени', () async {
    reply = (r, n) => _syncResponse(status: '1', key: 'K2', addStatus: '1', serverId: '$_fid:9');
    final eng = await engine();
    final sid = await eng.upsertPim(_fid, dataClass: 'Calendar', fields: _allDayFields());
    expect(sid, '$_fid:9');
    expect(requests, hasLength(1));
    final d = requests.single.data;
    expect(d.containsKey('TimeZone'), isFalse);
    expect(d['StartTime'], '20261103T000000Z');
    expect(d['EndTime'], '20261104T000000Z');
    expect(d['AllDayEvent'], '1');
    expect(eng.pimSyncKeyFor(_fid), 'K2');
  });

  test('сервер отверг вид AS 16 (Status 6) — повтор с поясом и временем в UTC', () async {
    reply = (r, n) => n == 1
        ? _syncResponse(status: '1', key: 'K2', addStatus: '6')
        : _syncResponse(status: '1', key: 'K3', addStatus: '1', serverId: '$_fid:10');
    final eng = await engine();
    final sid = await eng.upsertPim(_fid, dataClass: 'Calendar', fields: _allDayFields());
    expect(sid, '$_fid:10');
    expect(requests, hasLength(2));
    expect(requests[1].key, 'K2', reason: 'повтор — с ключом, выданным после отказа');
    expect(requests[1].data.containsKey('TimeZone'), isTrue);
    expect(requests[1].data['StartTime'], _compactUtc(DateTime(2026, 11, 3)));
  });

  test('обычная встреча — с поясом и временем, как раньше', () async {
    reply = (r, n) => _syncResponse(status: '1', key: 'K2', addStatus: '1', serverId: '$_fid:11');
    final eng = await engine();
    final f = _allDayFields()
      ..['AllDayEvent'] = '0'
      ..['StartTime'] = _compactUtc(DateTime(2026, 11, 3, 8))
      ..['EndTime'] = _compactUtc(DateTime(2026, 11, 3, 8, 30));
    await eng.upsertPim(_fid, dataClass: 'Calendar', fields: f);
    final d = requests.single.data;
    expect(d.containsKey('TimeZone'), isTrue);
    expect(d['StartTime'], _compactUtc(DateTime(2026, 11, 3, 8)));
  });

  test('ключ отклонён (Status 3) — новый ключ и повтор записи', () async {
    reply = (r, n) {
      if (r.key == 'K1') return _syncResponse(status: '3');
      if (r.key == '0') return _syncResponse(status: '1', key: 'N1');
      return _syncResponse(status: '1', key: 'N2', addStatus: '1', serverId: '$_fid:12');
    };
    final eng = await engine();
    final sid = await eng.upsertPim(_fid, dataClass: 'Calendar', fields: _allDayFields());
    expect(sid, '$_fid:12');
    expect([for (final r in requests) r.key], ['K1', '0', 'N1']);
    expect(requests.last.isAdd, isTrue);
    expect(eng.pimSyncKeyFor(_fid), 'N2');
    expect(eng.takePimReinit(_fid), isTrue, reason: 'ближайшая синхронизация загрузит папку заново');
  });

  test('Status 3 и после нового ключа — ошибка, без бесконечных повторов', () async {
    reply = (r, n) => r.key == '0' ? _syncResponse(status: '1', key: 'N1') : _syncResponse(status: '3');
    final eng = await engine();
    await expectLater(eng.upsertPim(_fid, dataClass: 'Calendar', fields: _allDayFields()), throwsStateError);
    expect(requests.length, lessThanOrEqualTo(4));
    expect(eng.pimSyncKeyFor(_fid), '0');
  });
}

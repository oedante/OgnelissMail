// Удаление одного повтора серии CalDAV, когда сервер не принимает EXDATE
// (2.7.1, журнал пользователя 22.11.2026 18:48: «Удаление события
// …@google.com#20261220: Сервер не принял изменение (HTTP 400)»). У дня
// рождения из контактов Google даты не меняются: сначала — отменённое
// вхождение (RECURRENCE-ID, STATUS:CANCELLED), не принял и его — повтор
// скрывается в приложении и не возвращается при синхронизации. Данные —
// вымышленные.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/dav/dav_pim_service.dart';
import 'package:ogneliss/services/mail/dav/ical_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _birthday = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:-//Example//Calendar//EN\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:bday0001@google.com\r\n'
    'DTSTART;VALUE=DATE:20241220\r\n'
    'DTEND;VALUE=DATE:20241221\r\n'
    'RRULE:FREQ=YEARLY\r\n'
    'SUMMARY:Иван – день рождения\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

const _href = 'https://dav.example/cal/bday0001.ics';

final _account = AccountModel(
  id: 'acc1',
  type: AccountType.google,
  email: 'me@gmail.example',
  displayName: 'Я',
  username: 'me@gmail.example',
  createdAt: DateTime(2026),
);

String get _occurrence => '${DavPimService.idPrefix(_account.id)}bday0001@google.com#20261220';

/// Сервер: GET отдаёт серию, на каждый PUT — следующий код из [put].
Future<List<String>> _run(List<int> put, {bool writable = true}) async {
  SharedPreferences.setMockInitialValues({
    'dav_res_${_account.id}': jsonEncode({
      'bday0001@google.com': {'h': _href, 'e': '"1"', 'w': writable},
    }),
  });
  final bodies = <String>[];
  final client = MockClient((r) async {
    if (r.method == 'GET') return http.Response.bytes(utf8.encode(_birthday), 200, headers: {'etag': '"1"'});
    if (r.method == 'PUT') {
      bodies.add(r.body);
      final code = put[bodies.length - 1];
      return http.Response('', code, headers: {if (code < 300) 'etag': '"2"'});
    }
    return http.Response('', 405);
  });
  await http.runWithClient(() => DavPimService().deleteEvent(_account, 'Bearer x', _occurrence), () => client);
  return bodies;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('сервер принял EXDATE — одна запись, ничего не скрыто', () async {
    final bodies = await _run([204]);
    expect(bodies, hasLength(1));
    expect(bodies.single, contains('EXDATE;VALUE=DATE:20261220'));
    expect(await DavPimService.hiddenIds(_account.id), isEmpty);
  });

  test('EXDATE — 400, отменённое вхождение принято: повтор убран на сервере', () async {
    final bodies = await _run([400, 204]);
    expect(bodies, hasLength(2));
    final evs = ICalParser.parse(bodies[1]);
    final cancelled = evs.where((e) => e.recurrenceId != null).single;
    expect(cancelled.cancelled, isTrue);
    expect(bodies[1], contains('RECURRENCE-ID;VALUE=DATE:20261220'));
    expect(bodies[1], isNot(contains('EXDATE')));
    expect(await DavPimService.hiddenIds(_account.id), isEmpty);
  });

  test('день рождения Google: сервер не принял ни то, ни другое — повтор скрыт без ошибки', () async {
    final bodies = await _run([400, 400]);
    expect(bodies, hasLength(2));
    final hidden = await DavPimService.hiddenIds(_account.id);
    expect(hidden, {_occurrence});
    expect(DavPimService.isHidden(hidden, _occurrence), isTrue);
    // Остальные годы — на месте.
    expect(DavPimService.isHidden(hidden, _occurrence.replaceFirst('20261220', '20271220')), isFalse);
  });

  test('нет прав в своём календаре — ошибка (без скрытия)', () async {
    await expectLater(_run([403]), throwsA(isA<DavRefused>()));
    expect(await DavPimService.hiddenIds(_account.id), isEmpty);
  });

  test('календарь только для чтения — отказ сервера, повтор скрыт', () async {
    final bodies = await _run([403], writable: false);
    expect(bodies, hasLength(1));
    expect(await DavPimService.hiddenIds(_account.id), {_occurrence});
  });

  test('скрытое событие целиком скрывает все его повторы', () {
    final master = '${DavPimService.idPrefix('a')}uid@x';
    final hidden = {master};
    expect(DavPimService.isHidden(hidden, master), isTrue);
    expect(DavPimService.isHidden(hidden, '$master#20261220'), isTrue);
    expect(DavPimService.isHidden(hidden, '${DavPimService.idPrefix('a')}other@x#20261220'), isFalse);
    expect(DavPimService.isHidden(const {}, master), isFalse);
  });

  test('отменённое вхождение: серия разворачивается без этого дня', () {
    final orig = DateTime(2026, 12, 20);
    final out = ICalPatch.cancelOccurrence(_birthday,
        uid: 'bday0001@google.com', originalStart: orig, end: DateTime(2026, 12, 21), allDay: true, summary: 'Иван');
    final evs = ICalParser.parse(out);
    final master = evs.firstWhere((e) => e.recurrenceId == null);
    final occs = ICalSeries.expand(master, DateTime(2026, 12, 1), DateTime(2028, 1, 1),
        skip: [for (final e in evs.where((e) => e.recurrenceId != null)) e.recurrenceId!]);
    expect([for (final o in occs!) o.day], ['20271220']);
  });
}

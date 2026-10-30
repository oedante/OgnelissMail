// События «весь день» из CalDAV (iCloud, Яндекс): конец DTEND — исключительный,
// событие на один день — один день в календаре (1.8.12, проверка по
// замечанию 29.10.2026 о днях рождения из iCloud на два дня).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/dav/ical_parser.dart';

String _ics(String body) => 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:День рождения\r\n$body\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

void main() {
  test('один день: DTEND следующего дня, серия с годом рождения, DURATION', () {
    final single = ICalParser.parse(_ics('DTSTART;VALUE=DATE:20261029\r\nDTEND;VALUE=DATE:20261030')).single;
    expect(single.isAllDay, isTrue);
    expect(single.start, DateTime(2026, 10, 29));
    expect(single.end, DateTime(2026, 10, 30));

    for (final body in [
      'DTSTART;VALUE=DATE:19851029\r\nDTEND;VALUE=DATE:19851030\r\nRRULE:FREQ=YEARLY',
      'DTSTART;VALUE=DATE:19851029\r\nDTEND;VALUE=DATE:19851030\r\nRRULE:FREQ=YEARLY;BYMONTH=10;BYMONTHDAY=29',
      'DTSTART;VALUE=DATE:19851029\r\nDURATION:P1D\r\nRRULE:FREQ=YEARLY',
      // Год до 1900 (iOS ставит 1604, когда год рождения не указан).
      'DTSTART;VALUE=DATE:16041029\r\nDTEND;VALUE=DATE:16041030\r\nRRULE:FREQ=YEARLY',
    ]) {
      final ev = ICalParser.parse(_ics(body)).single;
      final occ = ICalSeries.expand(ev, DateTime(2026, 10, 1), DateTime(2026, 11, 30))!.single;
      expect(occ.start, DateTime(2026, 10, 29), reason: body);
      expect(occ.end, DateTime(2026, 10, 30), reason: body);
    }
  });
}

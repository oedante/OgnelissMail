// test/unit/booking_parser_test.dart
// Бронирования из письма: разметка schema.org (JSON-LD) → карточка.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/booking_parser.dart';

String _html(String json) => '<html><head><script type="application/ld+json">$json</script></head>'
    '<body>Ваш билет</body></html>';

void main() {
  test('нет разметки — пусто', () {
    expect(BookingParser.parseHtml(null), isEmpty);
    expect(BookingParser.parseHtml('<p>Привет</p>'), isEmpty);
    expect(BookingParser.parseHtml(_html('{broken')), isEmpty);
    expect(BookingParser.parseHtml(_html('{"@type":"Organization","name":"X"}')), isEmpty);
  });

  test('перелёт', () {
    final b = BookingParser.parseHtml(_html('''
{
  "@context": "http://schema.org",
  "@type": "FlightReservation",
  "reservationNumber": "ABC123",
  "airplaneSeat": "14A",
  "reservationFor": {
    "@type": "Flight",
    "flightNumber": "1124",
    "airline": {"@type": "Airline", "name": "Aeroflot", "iataCode": "SU"},
    "departureAirport": {"@type": "Airport", "name": "Шереметьево", "iataCode": "SVO"},
    "departureTime": "2026-11-02T08:40:00+03:00",
    "arrivalAirport": {"@type": "Airport", "name": "Пулково", "iataCode": "LED"},
    "arrivalTime": "2026-11-02T10:05:00+03:00"
  }
}''')).single;
    expect(b.kind, BookingKind.flight);
    expect(b.title, 'SU 1124 · SVO → LED');
    expect(b.reservationNumber, 'ABC123');
    expect(b.details, '14A');
    expect(b.location, 'Шереметьево');
    expect(b.start!.toUtc(), DateTime.utc(2026, 11, 2, 5, 40));
    expect(b.end!.toUtc(), DateTime.utc(2026, 11, 2, 7, 5));
  });

  test('отель: даты без времени — 15:00 и 12:00', () {
    final b = BookingParser.parseHtml(_html('''
[{"@context":"https://schema.org","@type":"LodgingReservation","reservationNumber":"H-77",
  "checkinDate":"2026-12-10","checkoutDate":"2026-12-12",
  "reservationFor":{"@type":"LodgingBusiness","name":"Отель Невский",
    "address":{"@type":"PostalAddress","streetAddress":"Невский пр., 1","addressLocality":"Санкт-Петербург"}}}]
''')).single;
    expect(b.kind, BookingKind.hotel);
    expect(b.title, 'Отель Невский');
    expect(b.start, DateTime(2026, 12, 10, 15));
    expect(b.end, DateTime(2026, 12, 12, 12));
    expect(b.location, 'Отель Невский, Невский пр., 1, Санкт-Петербург');
  });

  test('поезд в @graph и HTML-комментарии; повтор не дублируется', () {
    const json = '''
{"@graph":[{"@type":"TrainReservation","reservationNumber":"77",
  "reservationFor":{"@type":"TrainTrip","trainNumber":"752А",
    "departureStation":{"@type":"TrainStation","name":"Москва Ленинградская"},
    "arrivalStation":{"@type":"TrainStation","name":"Санкт-Петербург Главный"},
    "departureTime":"2026-11-05T09:30:00+03:00","arrivalTime":"2026-11-05T13:25:00+03:00"}}]}''';
    final html = '${_html('<!-- $json -->')}${_html(json)}';
    final list = BookingParser.parseHtml(html);
    expect(list, hasLength(1));
    expect(list.single.kind, BookingKind.train);
    expect(list.single.title, '752А · Москва Ленинградская → Санкт-Петербург Главный');
  });

  test('мероприятие и столик', () {
    final list = BookingParser.parseHtml(_html('''
[{"@type":"EventReservation","reservationNumber":"T1",
  "reservationFor":{"@type":"Event","name":"Концерт","startDate":"2026-11-20T19:00:00+03:00",
    "location":{"@type":"Place","name":"Зал","address":"ул. Мира, 5"}}},
 {"@type":"FoodEstablishmentReservation","startTime":"2026-11-21T20:00:00+03:00",
  "reservationFor":{"@type":"FoodEstablishment","name":"Ресторан"}}]
'''));
    expect(list.map((b) => b.kind), [BookingKind.event, BookingKind.restaurant]);
    expect(list.first.location, 'Зал, ул. Мира, 5');
    expect(list.last.title, 'Ресторан');
  });
}

// lib/services/mail/booking_parser.dart
// Бронирования из письма: структурированные данные schema.org (JSON-LD,
// <script type="application/ld+json">), которые авиакомпании, РЖД, отели и
// сервисы бронирования кладут в письмо для почтовых программ (так их читает
// и Gmail). Текст письма «на глаз» не разбирается — только эти данные.
//
// Поддержано: FlightReservation, TrainReservation, BusReservation,
// LodgingReservation, EventReservation, FoodEstablishmentReservation,
// RentalCarReservation. Результат — карточка в письме с кнопкой
// «Добавить в календарь» (см. booking_card.dart).

import 'dart:convert';

enum BookingKind { flight, train, bus, hotel, event, restaurant, car }

class Booking {
  final BookingKind kind;
  final String title;
  final DateTime? start;
  final DateTime? end;
  final String? location;
  final String? reservationNumber;
  final String? details;

  const Booking({
    required this.kind,
    required this.title,
    this.start,
    this.end,
    this.location,
    this.reservationNumber,
    this.details,
  });
}

class BookingParser {
  static final _script = RegExp(
    r'''<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// Бронирования из HTML письма (без повторов). Пустой список — данных нет.
  static List<Booking> parseHtml(String? html) {
    if (html == null || !html.toLowerCase().contains('application/ld+json')) return const [];
    final out = <Booking>[];
    final seen = <String>{};
    for (final m in _script.allMatches(html)) {
      final raw = _unescape(m.group(1)!.trim());
      Object? data;
      try {
        data = jsonDecode(raw);
      } catch (_) {
        continue;
      }
      for (final node in _nodes(data)) {
        final b = _booking(node);
        if (b == null) continue;
        final key = '${b.kind}|${b.reservationNumber}|${b.start}|${b.title}';
        if (seen.add(key)) out.add(b);
      }
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('<!--', '')
      .replaceAll('-->', '')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');

  /// Узлы верхнего уровня: объект, массив или @graph.
  static Iterable<Map<String, dynamic>> _nodes(Object? data) sync* {
    if (data is List) {
      for (final d in data) {
        yield* _nodes(d);
      }
    } else if (data is Map<String, dynamic>) {
      final graph = data['@graph'];
      if (graph is List) {
        yield* _nodes(graph);
      } else {
        yield data;
      }
    }
  }

  static String? _type(Map<String, dynamic> m) {
    final t = m['@type'];
    if (t is String) return t.replaceAll('http://schema.org/', '').replaceAll('https://schema.org/', '');
    if (t is List && t.isNotEmpty && t.first is String) return t.first as String;
    return null;
  }

  static Map<String, dynamic>? _obj(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) return v.first as Map<String, dynamic>;
    return null;
  }

  static String? _str(Object? v) {
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    if (v is num) return v.toString();
    if (v is Map<String, dynamic>) return _str(v['name']);
    return null;
  }

  static DateTime? _date(Object? v) {
    final s = _str(v);
    if (s == null) return null;
    final d = DateTime.tryParse(s);
    return d?.isUtc == true ? d!.toLocal() : d;
  }

  /// Дата без времени («2026-10-12») — с часом [hour] по местному времени.
  static DateTime? _withDefaultHour(Object? v, int hour) {
    final d = _date(v);
    final s = _str(v);
    if (d == null || s == null) return d;
    return s.length <= 10 ? DateTime(d.year, d.month, d.day, hour) : d;
  }

  static String? _address(Object? place) {
    final p = _obj(place);
    if (p == null) return _str(place);
    final a = p['address'];
    if (a is String) return [_str(p['name']), a].whereType<String>().join(', ');
    final am = _obj(a);
    final parts = [
      _str(p['name']),
      if (am != null) ...[_str(am['streetAddress']), _str(am['addressLocality'])],
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  static Booking? _booking(Map<String, dynamic> m) {
    final type = _type(m);
    if (type == null || !type.endsWith('Reservation')) return null;
    final number = _str(m['reservationNumber']) ?? _str(m['reservationId']);
    final f = _obj(m['reservationFor']) ?? const <String, dynamic>{};
    switch (type) {
      case 'FlightReservation':
        final airline = _obj(f['airline']);
        final code = [_str(airline?['iataCode']), _str(f['flightNumber'])].whereType<String>().join(' ');
        final from = _obj(f['departureAirport']);
        final to = _obj(f['arrivalAirport']);
        final route = [
          _str(from?['iataCode']) ?? _str(from?['name']),
          _str(to?['iataCode']) ?? _str(to?['name']),
        ].whereType<String>().join(' → ');
        return Booking(
          kind: BookingKind.flight,
          title: [if (code.isNotEmpty) code, if (route.isNotEmpty) route].join(' · '),
          start: _date(f['departureTime']),
          end: _date(f['arrivalTime']),
          location: _str(from?['name']),
          reservationNumber: number,
          details: _str(m['airplaneSeat']) ?? _str(_obj(m['reservedTicket'])?['ticketedSeat']),
        );
      case 'TrainReservation':
      case 'BusReservation':
        final train = type == 'TrainReservation';
        final from = _obj(f[train ? 'departureStation' : 'departureBusStop']);
        final to = _obj(f[train ? 'arrivalStation' : 'arrivalBusStop']);
        final vehicle = _str(f[train ? 'trainNumber' : 'busNumber']);
        final route = [_str(from?['name']), _str(to?['name'])].whereType<String>().join(' → ');
        return Booking(
          kind: train ? BookingKind.train : BookingKind.bus,
          title: [if (vehicle != null) vehicle, if (route.isNotEmpty) route].join(' · '),
          start: _date(f['departureTime']),
          end: _date(f['arrivalTime']),
          location: _str(from?['name']),
          reservationNumber: number,
        );
      case 'LodgingReservation':
        // Только дата заезда/выезда — обычное время отелей (15:00 / 12:00).
        final cin = m['checkinTime'] ?? m['checkinDate'];
        final cout = m['checkoutTime'] ?? m['checkoutDate'];
        return Booking(
          kind: BookingKind.hotel,
          title: _str(f['name']) ?? 'Hotel',
          start: _withDefaultHour(cin, 15),
          end: _withDefaultHour(cout, 12),
          location: _address(f),
          reservationNumber: number,
        );
      case 'EventReservation':
        return Booking(
          kind: BookingKind.event,
          title: _str(f['name']) ?? 'Event',
          start: _date(f['startDate']),
          end: _date(f['endDate']),
          location: _address(f['location']),
          reservationNumber: number,
        );
      case 'FoodEstablishmentReservation':
        return Booking(
          kind: BookingKind.restaurant,
          title: _str(f['name']) ?? 'Restaurant',
          start: _date(m['startTime']),
          end: _date(m['endTime']),
          location: _address(f),
          reservationNumber: number,
        );
      case 'RentalCarReservation':
        return Booking(
          kind: BookingKind.car,
          title: _str(_obj(f['rentalCompany'])?['name']) ?? _str(f['name']) ?? 'Car',
          start: _date(m['pickupTime']),
          end: _date(m['dropoffTime']),
          location: _address(m['pickupLocation']),
          reservationNumber: number,
        );
    }
    return null;
  }
}

// Файл календаря .ics (22.11.2026, вопрос владельца «А приложение не может
// такое открывать?» — бронирование гостиницы файлом): вложение открывается
// в приложении событием с «В календарь». Бронирование — METHOD:REQUEST без
// участников, организатор без «mailto:» — не приглашение: отвечать некому.
// Данные — вымышленные, по образцу файла системы бронирования.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/calendar/widgets/ics_events_view.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/calendar/imip_service.dart';
import 'package:ogneliss/services/mail/dav/ical_parser.dart';

const _booking = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'PRODID:BookingSystem\r\n'
    'METHOD:REQUEST\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:0f1e2d3c-0000-4000-8000-000000000001\r\n'
    'DTSTART:20261210T140000\r\n'
    'SEQUENCE:0\r\n'
    'TRANSP:OPAQUE\r\n'
    'DTEND:20261211T120000\r\n'
    'LOCATION:г. Город\\, ул. Примерная\\, д. 1\r\n'
    'SUMMARY:Гостиница «Пример»\r\n'
    'CLASS:PUBLIC\r\n'
    'DESCRIPTION:Заезд: 2026-12-10 14:00\\nВыезд: 2026-12-11 12:00\\nБронирование №: 0000-1111\r\n'
    'ORGANIZER:Гостиница <booking@hotel.example>\r\n'
    'DTSTAMP:20261122T100000\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('разбор файла бронирования', () {
    test('событие: время без пояса — как написано, место и описание раскрыты', () {
      final evs = IcsEventsView.eventsOf(_booking);
      expect(evs, hasLength(1));
      final e = evs.single;
      expect(e.summary, 'Гостиница «Пример»');
      expect(e.start!.toLocal(), DateTime(2026, 12, 10, 14));
      expect(e.end!.toLocal(), DateTime(2026, 12, 11, 12));
      expect(e.isAllDay, isFalse);
      expect(e.location, 'г. Город, ул. Примерная, д. 1');
      expect(e.description, contains('\nВыезд: 2026-12-11 12:00'));
      // Организатор без «mailto:» — адрес всё равно виден.
      expect(e.organizerEmail, 'booking@hotel.example');
    });

    test('запрос без участников — не приглашение: отвечать некому', () {
      final p = ICalITip.parse(_booking)!;
      final invite = ImipInvite(_booking, p.method, p.event);
      expect(invite.isRequest, isTrue);
      expect(invite.canReply, isFalse);

      final meeting = _booking.replaceFirst(
          'ORGANIZER:Гостиница <booking@hotel.example>\r\n',
          'ORGANIZER;CN=Иванов:mailto:ivanov@corp.example\r\n'
              'ATTENDEE;PARTSTAT=NEEDS-ACTION:mailto:me@corp.example\r\n');
      final q = ICalITip.parse(meeting)!;
      expect(ImipInvite(meeting, q.method, q.event).canReply, isTrue);
    });

    test('время на несколько дней — с датой конца', () {
      final l10n = AppLocalizations(const Locale('ru'));
      final multi = eventRangeText(DateTime(2026, 12, 10, 14), DateTime(2026, 12, 11, 12),
          allDay: false, l10n: l10n, locale: 'ru');
      expect(multi, contains('14:00'));
      expect(multi, contains('11'));
      expect(multi, contains('12:00'));
      expect(multi, contains(' – '));
      final same = eventRangeText(DateTime(2026, 12, 10, 14), DateTime(2026, 12, 10, 15),
          allDay: false, l10n: l10n, locale: 'ru');
      expect(same, endsWith('14:00–15:00'));
    });
  });

  testWidgets('вложение .ics открывается в приложении событием с «В календарь»', (tester) async {
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('ics_preview'));
    final f = File('${dir!.path}/booking-event.ics');
    await tester.runAsync(() => f.writeAsBytes(utf8.encode(_booking)));
    final item = PreviewItem(filePath: f.path, fileName: 'booking-event.ics', mimeType: 'text/calendar');
    expect(await tester.runAsync(() => AttachmentPreviewScreen.opensInApp(item)), isTrue);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(1.0),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AttachmentPreviewScreen(items: [item]),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Гостиница «Пример»').evaluate().isNotEmpty) break;
    }

    expect(tester.takeException(), isNull);
    expect(find.text('Гостиница «Пример»'), findsOneWidget);
    expect(find.text('Событие календаря'), findsOneWidget);
    expect(find.text('В календарь'), findsOneWidget);
    expect(find.textContaining('ул. Примерная'), findsOneWidget);
    expect(find.textContaining('BEGIN:VCALENDAR'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}

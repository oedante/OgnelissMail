// Новое в сборке 28: переход по нажатию на уведомление, гриф → пометка
// Outlook, время встречи из окна «Создать» виджета календаря.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/calendar/quick_create_service.dart';
import 'package:ogneliss/services/notifications/notification_router.dart';

void main() {
  group('NotificationRouter.routeFor', () {
    test('письмо — отдельной страницей поверх любого экрана, с ящиком', () {
      final p = jsonEncode({'type': 'email', 'accountId': 'acc 1', 'emailId': 'eas_2:15'});
      expect(NotificationRouter.routeFor(p), '/message/eas_2%3A15?accountId=acc+1');
    });

    test('письмо без id — лента', () {
      expect(NotificationRouter.routeFor(jsonEncode({'type': 'email', 'accountId': 'a'})), '/mail');
    });

    test('сводка — лента', () {
      expect(NotificationRouter.routeFor(jsonEncode({'type': 'mail_summary', 'accountId': 'a'})), '/mail');
      expect(NotificationRouter.routeFor('summary:a'), '/mail');
    });

    test('встреча — карточка встречи', () {
      final p = jsonEncode({'type': 'event', 'id': 'eas_2:15#20261007', 'accountId': 'a'});
      expect(NotificationRouter.routeFor(p), '/event/eas_2%3A15%2320261007?accountId=a');
    });

    test('задача — «Напоминания» с открытой задачей', () {
      final r = NotificationRouter.routeFor(jsonEncode({'type': 'task', 'id': 't1', 'accountId': 'a'}))!;
      final u = Uri.parse(r);
      expect(u.path, '/tasks');
      expect(u.queryParameters, {'task': 't1', 'accountId': 'a'});
    });

    test('«Мой день» и неизвестное', () {
      expect(NotificationRouter.routeFor(jsonEncode({'type': 'myday'})), '/my-day');
      expect(NotificationRouter.routeFor(jsonEncode({'type': 'что-то'})), isNull);
      expect(NotificationRouter.routeFor(null), isNull);
      expect(NotificationRouter.routeFor('не json'), isNull);
    });

    test('главный экран: новый появился раньше, чем закрылся прежний (1.8.0)', () {
      // Журнал 26.10.2026: флаг «готов» сбрасывался закрытием прежнего
      // MainShell уже после открытия нового — нажатие на уведомление ждало
      // главного экрана, который уже был на месте.
      NotificationRouter.shellMounted(); // прежний
      NotificationRouter.shellMounted(); // новый
      NotificationRouter.shellUnmounted(); // прежний закрылся позже
      expect(NotificationRouter.shellReady, isTrue);
      NotificationRouter.shellUnmounted();
      expect(NotificationRouter.shellReady, isFalse);
      NotificationRouter.shellUnmounted(); // лишнее закрытие — не уходит в минус
      NotificationRouter.shellMounted();
      expect(NotificationRouter.shellReady, isTrue);
      NotificationRouter.shellUnmounted();
    });

    test('ящик для переключения — только для почты', () {
      expect(NotificationRouter.mailAccountFor(jsonEncode({'type': 'email', 'accountId': 'a', 'emailId': 'x'})), 'a');
      expect(NotificationRouter.mailAccountFor(jsonEncode({'type': 'mail_summary', 'accountId': 'b'})), 'b');
      expect(NotificationRouter.mailAccountFor(jsonEncode({'type': 'event', 'accountId': 'c', 'id': 'e'})), isNull);
      expect(NotificationRouter.mailAccountFor('summary:a'), isNull);
    });
  });

  group('Окно «Создать» виджета: время встречи', () {
    final st = DateTime(2026, 10, 12, 14, 30);

    test('обычная встреча — как выбрали', () {
      final t = QuickCreateService.eventTimes(st, DateTime(2026, 10, 12, 15, 15), false);
      expect(t.start, st);
      expect(t.end, DateTime(2026, 10, 12, 15, 15));
    });

    test('конец не позже начала — час', () {
      expect(QuickCreateService.eventTimes(st, st, false).end, DateTime(2026, 10, 12, 15, 30));
      expect(QuickCreateService.eventTimes(st, null, false).end, DateTime(2026, 10, 12, 15, 30));
    });

    test('весь день: от полуночи до полуночи следующего дня', () {
      final day = DateTime(2026, 10, 12);
      final t = QuickCreateService.eventTimes(day, DateTime(2026, 10, 13), true);
      expect(t.start, day);
      expect(t.end, DateTime(2026, 10, 13));
    });

    test('весь день без конца — один день', () {
      final t = QuickCreateService.eventTimes(DateTime(2026, 10, 12, 9), null, true);
      expect(t.start, DateTime(2026, 10, 12));
      expect(t.end, DateTime(2026, 10, 13));
    });

    test('миллисекунды из очереди', () {
      final ms = DateTime(2026, 10, 12, 9).millisecondsSinceEpoch;
      expect(QuickCreateService.ms(ms), DateTime(2026, 10, 12, 9));
      expect(QuickCreateService.ms(0), isNull);
      expect(QuickCreateService.ms(null), isNull);
      expect(QuickCreateService.ms('x'), isNull);
    });
  });
}

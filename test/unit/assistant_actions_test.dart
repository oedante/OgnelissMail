// Siri, «Команды» и Google Ассистент (1.9.x, просьба владельца 31.10.2026):
// «экраны», которые передают iPhone (WidgetBridgePlugin.swift) и Android
// (shortcuts.xml, WidgetBridge), — разбор и маршрут. Прежние быстрые
// действия значка открываются так же, как до 1.9.x.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/assistant_actions.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show MailFilter;

AssistantRoute route(String type, {String? acc}) =>
    AssistantAction.parse(type)!.route(accountId: acc, now: DateTime(2026, 11, 2, 9, 0));

void main() {
  group('прежние быстрые действия и виджеты', () {
    test('маршруты — как до 1.9.x', () {
      expect(route('compose', acc: 'a1').location, '/compose?accountId=a1');
      expect(route('compose', acc: 'a1').push, isTrue);
      expect(route('compose').location, '/compose');
      expect(route('event').location, '/create-event');
      expect(route('event').push, isTrue);
      expect(route('event').extra, isNull);
      expect(route('reminder', acc: 'a1').location, '/tasks?new=1&accountId=a1');
      expect(route('reminder').push, isFalse);
      expect(route('myday').location, '/my-day');
      expect(route('mail').location, '/mail');
      expect(route('mail').filter, isNull);
      expect(route('calendar').location, '/calendar');
      expect(route('notes').location, '/notes');
    });

    test('письмо, встреча, заметка из виджета — не действие помощника', () {
      expect(AssistantAction.parse('email?id=1&acc=a'), isNull);
      expect(AssistantAction.parse('calevent?id=1&acc=a'), isNull);
      expect(AssistantAction.parse('note?id=1'), isNull);
      expect(AssistantAction.parse('newnote'), isNull);
      expect(AssistantAction.parse('что-то'), isNull);
      expect(AssistantAction.parse(''), isNull);
    });
  });

  group('Siri и «Команды»', () {
    test('новое письмо: кому и тема, «&» и «+» в значениях', () {
      final r = route('compose?to=anna%40example.com&subject=A%20%26%20B%2B1', acc: 'a1');
      final uri = Uri.parse(r.location);
      expect(uri.path, '/compose');
      expect(uri.queryParameters, {'accountId': 'a1', 'to': 'anna@example.com', 'subject': 'A & B+1'});
      expect(r.push, isTrue);
    });

    test('пустые кому и тема не передаются', () {
      expect(route('compose?to=&subject=%20').location, '/compose');
    });

    test('новая встреча по фразе — редактор, заполненный разбором фразы', () {
      final r = route('event?phrase=${Uri.encodeQueryComponent('Обед завтра в 13 в кафе «Ромашка»')}');
      expect(r.location, '/create-event');
      expect(r.push, isTrue);
      final extra = r.extra as Map;
      expect(extra['title'], 'Обед');
      expect(extra['start'], DateTime(2026, 11, 3, 13, 0));
      expect(extra['end'], DateTime(2026, 11, 3, 13, 30));
      expect(extra['location'], 'кафе «Ромашка»');
    });

    test('встреча на весь день', () {
      final extra = route('event?phrase=${Uri.encodeQueryComponent('Отпуск завтра')}').extra as Map;
      expect(extra['allDay'], isTrue);
      expect(extra['start'], DateTime(2026, 11, 3));
      expect(extra['title'], 'Отпуск');
    });

    test('новое напоминание по фразе — в задачи с текстом', () {
      final r = route('reminder?phrase=${Uri.encodeQueryComponent('Позвонить маме завтра в 10')}', acc: 'a1');
      final uri = Uri.parse(r.location);
      expect(uri.path, '/tasks');
      expect(uri.queryParameters, {'new': '1', 'accountId': 'a1', 'text': 'Позвонить маме завтра в 10'});
    });

    test('непрочитанные и VIP — лента с фильтром', () {
      expect(route('unread').location, '/mail');
      expect(route('unread').filter, MailFilter.unread);
      expect(route('vip').filter, MailFilter.vip);
    });

    test('поиск: запрос, без запроса — поле поиска', () {
      final r = route('search?q=%D1%81%D1%87%D1%91%D1%82');
      expect(r.location, '/mail');
      expect(r.search, 'счёт');
      expect(route('search').search, '');
    });
  });

  group('Google Ассистент: OPEN_APP_FEATURE', () {
    test('id ярлыков из shortcuts.xml', () {
      for (final (id, kind) in [
        ('myday', AssistantKind.myDay),
        ('compose', AssistantKind.compose),
        ('event', AssistantKind.event),
        ('reminder', AssistantKind.reminder),
        ('unread', AssistantKind.unread),
        ('vip', AssistantKind.vip),
        ('calendar', AssistantKind.calendar),
        ('tasks', AssistantKind.tasks),
      ]) {
        expect(AssistantAction.parse('feature?f=$id')?.kind, kind, reason: id);
      }
    });

    test('слова человека (ru/en)', () {
      final cases = {
        'Мой день': AssistantKind.myDay,
        'my day': AssistantKind.myDay,
        'непрочитанные письма': AssistantKind.unread,
        'Unread mail': AssistantKind.unread,
        'письма от VIP': AssistantKind.vip,
        'новое напоминание': AssistantKind.reminder,
        'напоминания': AssistantKind.tasks,
        'Задачи': AssistantKind.tasks,
        'новая встреча': AssistantKind.event,
        'календарь': AssistantKind.calendar,
        'новое письмо': AssistantKind.compose,
        'входящие': AssistantKind.mail,
        'Inbox': AssistantKind.mail,
      };
      cases.forEach((words, kind) => expect(AssistantAction.feature(words), kind, reason: words));
    });

    test('неизвестный раздел — просто открыть приложение', () {
      expect(AssistantAction.parse('feature?f=${Uri.encodeQueryComponent('погода')}'), isNull);
      expect(AssistantAction.parse('feature'), isNull);
    });

    test('запрос GET_THING от Android (Uri.Builder): пробелы и «+»', () {
      // Uri.encode на Android: пробел — %20, «+» — %2B.
      expect(route('search?q=C%2B%2B%20%D0%BE%D1%82%D1%87%D1%91%D1%82').search, 'C++ отчёт');
    });
  });
}

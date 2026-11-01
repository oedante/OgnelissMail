// lib/core/platform/assistant_actions.dart
// Действия голосовых помощников и быстрых действий значка (1.9.x, просьба
// владельца 31.10.2026): Siri и «Команды» на iPhone (App Intents,
// WidgetBridgePlugin.swift), Google Ассистент на Android (App Actions и
// статические ярлыки, res/xml/shortcuts.xml). Обе системы открывают
// приложение и передают «экран» тем же путём, что нажатие на виджет
// (канал ogneliss/widget: «take» — забрать, «open» — пришло новое; пока
// Dart не готов, экран ждёт в очереди на стороне платформы):
//   compose[?to=…&subject=…]  — новое письмо;
//   event[?phrase=…]          — новая встреча (фраза — QuickEventParser);
//   reminder[?phrase=…]       — новое напоминание (TaskQuickParser);
//   myday, mail, calendar, tasks, notes — разделы;
//   unread, vip               — лента с фильтром;
//   search[?q=…]              — поиск в почте;
//   feature?f=…               — «Открой … в Ogneliss Mail» (Android,
//                               OPEN_APP_FEATURE): id ярлыка или слова.
// Здесь только разбор и маршрут — без роутера, чтобы проверять тестами;
// открывает экран AppShortcuts.

import '../../features/calendar/quick_event.dart';
import '../../features/mail/providers/mail_providers.dart' show MailFilter;

enum AssistantKind { compose, event, reminder, myDay, mail, calendar, tasks, notes, unread, vip, search }

class AssistantAction {
  final AssistantKind kind;

  /// Кому и тема нового письма.
  final String? to;
  final String? subject;

  /// Фраза встречи или напоминания, запрос поиска.
  final String? text;

  const AssistantAction(this.kind, {this.to, this.subject, this.text});

  static const _kinds = {
    'compose': AssistantKind.compose,
    'event': AssistantKind.event,
    'reminder': AssistantKind.reminder,
    'myday': AssistantKind.myDay,
    'mail': AssistantKind.mail,
    'calendar': AssistantKind.calendar,
    'tasks': AssistantKind.tasks,
    'notes': AssistantKind.notes,
    'unread': AssistantKind.unread,
    'vip': AssistantKind.vip,
    'search': AssistantKind.search,
  };

  /// Слова разделов (начала слов). Порядок важен: «новое напоминание» — не
  /// «задачи», «письма VIP» — не «почта».
  static const _featureWords = <(List<String>, AssistantKind)>[
    (['vip', 'вип'], AssistantKind.vip),
    (['непрочитан', 'unread', 'new mail', 'новые письма'], AssistantKind.unread),
    (['мой день', 'my day', 'today', 'сегодня'], AssistantKind.myDay),
    (['нов(ое|ая|ый) напомин', 'new reminder', 'создать напомин', 'напомни'], AssistantKind.reminder),
    (['нов(ая|ую) встреч', 'new (meeting|event)', 'создать встреч'], AssistantKind.event),
    (['нов(ое|ые) письм', 'написать', 'new (email|message)', 'compose', 'write'], AssistantKind.compose),
    (['календар', 'calendar', 'встреч', 'meetings', 'events'], AssistantKind.calendar),
    (['задач', 'напомин', 'task', 'reminder', 'to do', 'todo'], AssistantKind.tasks),
    (['заметк', 'note'], AssistantKind.notes),
    (['почт', 'входящ', 'письм', 'mail', 'inbox', 'email'], AssistantKind.mail),
    (['поиск', 'найти', 'search'], AssistantKind.search),
  ];

  /// Разобрать «экран». null — не действие (письмо или заметка из виджета
  /// разбираются отдельно, неизвестное — просто открыть приложение).
  static AssistantAction? parse(String type) {
    final Uri uri;
    try {
      uri = Uri.parse(type.trim());
    } catch (_) {
      return null;
    }
    final q = uri.queryParameters;
    String? v(String k) {
      final s = q[k]?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    if (uri.path == 'feature') {
      final kind = feature(q['f'] ?? '');
      return kind == null ? null : AssistantAction(kind);
    }
    final kind = _kinds[uri.path];
    if (kind == null) return null;
    return AssistantAction(kind, to: v('to'), subject: v('subject'), text: v('phrase') ?? v('q'));
  }

  /// Раздел по словам Ассистента: id ярлыка из shortcuts.xml («myday»,
  /// «unread»…) или то, что человек сказал («мой день», «непрочитанные»).
  static AssistantKind? feature(String name) {
    final s = name.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();
    if (s.isEmpty) return null;
    final exact = _kinds[s.replaceAll(' ', '')];
    if (exact != null) return exact;
    for (final (words, kind) in _featureWords) {
      if (words.any((w) => RegExp('(^| )$w').hasMatch(s))) return kind;
    }
    return null;
  }

  /// Куда открыть. [accountId] — ящик нового письма и напоминания;
  /// [now] и [monthFirst] — для разбора фразы встречи.
  AssistantRoute route({String? accountId, DateTime? now, bool monthFirst = false}) {
    switch (kind) {
      case AssistantKind.compose:
        return AssistantRoute(
          Uri(
            path: '/compose',
            queryParameters: {
              if (accountId != null) 'accountId': accountId,
              if (to != null) 'to': to!,
              if (subject != null) 'subject': subject!,
            },
          ).toString(),
          push: true,
        );
      case AssistantKind.event:
        final phrase = text;
        if (phrase == null) return const AssistantRoute('/create-event', push: true);
        // Редактор, заполненный по фразе, — как «Подробнее» во вводе
        // одной фразой: человек проверяет и сохраняет сам.
        final e = QuickEventParser.parse(phrase, now: now, monthFirst: monthFirst);
        return AssistantRoute(
          '/create-event',
          push: true,
          extra: {
            if (e.dated) 'start': e.start,
            if (e.dated) 'end': e.end,
            if (e.allDay) 'allDay': true,
            if (e.title.isNotEmpty) 'title': e.title,
            if (e.location != null) 'location': e.location,
          },
        );
      case AssistantKind.reminder:
        return AssistantRoute(
          Uri(
            path: '/tasks',
            queryParameters: {
              'new': '1',
              if (accountId != null) 'accountId': accountId,
              if (text != null) 'text': text!,
            },
          ).toString(),
        );
      case AssistantKind.myDay:
        return const AssistantRoute('/my-day');
      case AssistantKind.mail:
        return const AssistantRoute('/mail');
      case AssistantKind.calendar:
        return const AssistantRoute('/calendar');
      case AssistantKind.tasks:
        return const AssistantRoute('/tasks');
      case AssistantKind.notes:
        return const AssistantRoute('/notes');
      case AssistantKind.unread:
        return const AssistantRoute('/mail', filter: MailFilter.unread);
      case AssistantKind.vip:
        return const AssistantRoute('/mail', filter: MailFilter.vip);
      case AssistantKind.search:
        return AssistantRoute('/mail', search: text ?? '');
    }
  }
}

/// Маршрут действия: [push] — поверх текущего экрана (редакторы), иначе —
/// переход в раздел; [filter] — фильтр ленты; [search] — поиск в ленте
/// (пусто — открыть поле поиска).
class AssistantRoute {
  final String location;
  final bool push;
  final Object? extra;
  final MailFilter? filter;
  final String? search;

  const AssistantRoute(this.location, {this.push = false, this.extra, this.filter, this.search});
}

// lib/data/models/calendar_event_model.dart

enum RecurrenceType { none, daily, weekly, biweekly, monthly, yearly }
enum ShowAs { free, tentative, busy, outOfOffice }
enum EventPriority { low, normal, high }

class EventAttendee {
  final String email;
  final String? displayName;
  final bool isRequired;

  /// Ответ на приглашение: 0 — нет ответа/неизвестно, 1 — принял,
  /// 2 — под вопросом, 3 — отклонил. Сервер сообщает его только в копии
  /// встречи у организатора.
  final int response;
  const EventAttendee({required this.email, this.displayName, this.isRequired = true, this.response = 0});

  /// EAS Attendee_Status: 2 — под вопросом, 3 — принято, 4 — отклонено.
  static int responseFromEas(String? s) => switch (s) { '3' => 1, '2' => 2, '4' => 3, _ => 0 };

  /// EWS ResponseType.
  static int responseFromEws(String? s) => switch (s) {
        'Accept' => 1,
        'Organizer' => 1,
        'Tentative' => 2,
        'Decline' => 3,
        _ => 0,
      };
}

class EventReminder {
  final int minutesBefore;
  const EventReminder({required this.minutesBefore});
}

class CalendarEventModel {
  final String id;
  final String accountId;
  final String? calendarId;
  final String title;
  final String? description;
  final String? location;
  final String? onlineMeetingUrl;
  final DateTime startTime;
  final DateTime endTime;
  final bool isAllDay;
  final List<EventAttendee> attendees;
  final String? organizerEmail;
  final RecurrenceType recurrence;
  final bool isPrivate;
  final ShowAs showAs;
  final int? colorValue;
  final List<EventReminder> reminders;
  final bool isCancelled;
  final DateTime createdAt;
  final EventPriority priority;
  final String? linkedEmailId;

  /// Собрание (1.6.7): запрашивать ответы участников и разрешать им
  /// предлагать новое время — как флажки «Запросить ответы» и «Разрешить
  /// предлагать новое время» в Outlook. На сервер уходят при создании.
  final bool responseRequested;
  final bool allowNewTimeProposal;

  const CalendarEventModel({
    required this.id, required this.accountId, this.calendarId,
    required this.title, this.description, this.location,
    this.onlineMeetingUrl, required this.startTime, required this.endTime,
    this.isAllDay = false, this.attendees = const [],
    this.organizerEmail, this.recurrence = RecurrenceType.none,
    this.isPrivate = false, this.showAs = ShowAs.busy,
    this.colorValue, this.reminders = const [],
    this.isCancelled = false, required this.createdAt,
    this.priority = EventPriority.normal, this.linkedEmailId,
    this.responseRequested = true, this.allowNewTimeProposal = true,
  });

  /// Та же встреча в другое время (1.6.7: изменение всей серии сдвигает
  /// главный элемент).
  CalendarEventModel copyWith({DateTime? startTime, DateTime? endTime}) => CalendarEventModel(
        id: id, accountId: accountId, calendarId: calendarId,
        title: title, description: description, location: location,
        onlineMeetingUrl: onlineMeetingUrl,
        startTime: startTime ?? this.startTime, endTime: endTime ?? this.endTime,
        isAllDay: isAllDay, attendees: attendees,
        organizerEmail: organizerEmail, recurrence: recurrence,
        isPrivate: isPrivate, showAs: showAs,
        colorValue: colorValue, reminders: reminders,
        isCancelled: isCancelled, createdAt: createdAt,
        priority: priority, linkedEmailId: linkedEmailId,
        responseRequested: responseRequested, allowNewTimeProposal: allowNewTimeProposal,
      );
}

// lib/features/settings/providers/module_settings_provider.dart
// Настройки отдельных модулей (Calendar / Contacts / To Do / Notes),
// как на эталонных экранах. Хранятся прямо в SharedPreferences, чтобы
// не раздувать основную модель AppSettings и не требовать миграций.

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

/// Вид календаря по умолчанию. Новые значения — только в конец (в настройках
/// хранится индекс). agenda — «Расписание»: лента событий по дням.
enum CalendarDefaultView { day, threeDay, week, month, agenda }

/// Сортировка контактов.
enum ContactSort { firstName, lastName, recent }

/// Вид списка задач по умолчанию.
enum TaskDefaultView { all, today, upcoming }

class ModuleSettings {
  // Calendar
  final CalendarDefaultView calendarView;
  final int weekStartDay; // 1 = Пн, 7 = Вс
  final bool showWeekNumbers;
  final int defaultReminderMinutes;
  final bool showDeclinedEvents;
  /// Напоминать о встречах без своего напоминания (за defaultReminderMinutes).
  final bool eventFallbackReminder;
  /// Напоминания о встречах — «будильником» Android (точно в глубоком сне,
  /// со значком будильника в строке состояния).
  final bool eventAlarmClock;

  // Contacts
  final ContactSort contactSort;
  final bool showContactPhotos;
  final bool galFirst; // приоритет глобального каталога в поиске

  // To Do (Tasks)
  final TaskDefaultView taskView;
  final bool hideCompletedTasks;
  final bool taskReminderDefault;
  /// Час напоминания для задач со сроком без времени.
  final int taskDueHour;

  // Notes
  final bool notesPreviewLines; // показывать превью текста в списке
  final bool notesSortByModified; // сортировка по дате изменения (иначе по созданию)

  const ModuleSettings({
    this.calendarView = CalendarDefaultView.month,
    this.weekStartDay = 1,
    this.showWeekNumbers = false,
    this.defaultReminderMinutes = 15,
    this.showDeclinedEvents = false,
    this.eventFallbackReminder = true,
    this.eventAlarmClock = true,
    this.contactSort = ContactSort.lastName,
    this.showContactPhotos = true,
    this.galFirst = false,
    this.taskView = TaskDefaultView.all,
    this.hideCompletedTasks = false,
    this.taskReminderDefault = false,
    this.taskDueHour = 9,
    this.notesPreviewLines = true,
    this.notesSortByModified = true,
  });
}

class _MK {
  static const calendarView = 'mod_calendar_view';
  static const weekStartDay = 'mod_week_start';
  static const showWeekNumbers = 'mod_week_numbers';
  static const defaultReminder = 'mod_default_reminder';
  static const showDeclined = 'mod_show_declined';
  // Ключи читает и ReminderSchedulerService (без Riverpod, из фона).
  static const eventFallback = 'mod_event_fallback_reminder';
  static const eventAlarmClock = 'mod_event_alarm_clock';
  static const taskDueHour = 'mod_task_due_hour';
  static const contactSort = 'mod_contact_sort';
  static const showPhotos = 'mod_contact_photos';
  static const galFirst = 'mod_gal_first';
  static const taskView = 'mod_task_view';
  static const hideCompleted = 'mod_hide_completed';
  static const taskReminder = 'mod_task_reminder';
  static const notesPreview = 'mod_notes_preview';
  static const notesSortModified = 'mod_notes_sort_modified';
}

class ModuleSettingsNotifier extends StateNotifier<ModuleSettings> {
  final SharedPreferences _p;
  ModuleSettingsNotifier(this._p) : super(_load(_p));

  static ModuleSettings _load(SharedPreferences p) {
    return ModuleSettings(
      calendarView: CalendarDefaultView.values[
          (p.getInt(_MK.calendarView) ?? CalendarDefaultView.agenda.index)
              .clamp(0, CalendarDefaultView.values.length - 1)],
      weekStartDay: p.getInt(_MK.weekStartDay) ?? 1,
      showWeekNumbers: p.getBool(_MK.showWeekNumbers) ?? false,
      defaultReminderMinutes: p.getInt(_MK.defaultReminder) ?? 15,
      showDeclinedEvents: p.getBool(_MK.showDeclined) ?? false,
      eventFallbackReminder: p.getBool(_MK.eventFallback) ?? true,
      eventAlarmClock: p.getBool(_MK.eventAlarmClock) ?? true,
      contactSort: ContactSort.values[(p.getInt(_MK.contactSort) ?? 1).clamp(0, 2)],
      showContactPhotos: p.getBool(_MK.showPhotos) ?? true,
      galFirst: p.getBool(_MK.galFirst) ?? false,
      taskView: TaskDefaultView.values[(p.getInt(_MK.taskView) ?? 0).clamp(0, 2)],
      hideCompletedTasks: p.getBool(_MK.hideCompleted) ?? false,
      taskReminderDefault: p.getBool(_MK.taskReminder) ?? false,
      taskDueHour: (p.getInt(_MK.taskDueHour) ?? 9).clamp(0, 23),
      notesPreviewLines: p.getBool(_MK.notesPreview) ?? true,
      notesSortByModified: p.getBool(_MK.notesSortModified) ?? true,
    );
  }

  // Calendar
  Future<void> setCalendarView(CalendarDefaultView v) async {
    await _p.setInt(_MK.calendarView, v.index);
    state = _load(_p);
  }

  Future<void> setWeekStartDay(int day) async {
    await _p.setInt(_MK.weekStartDay, day);
    state = _load(_p);
  }

  Future<void> setShowWeekNumbers(bool v) async {
    await _p.setBool(_MK.showWeekNumbers, v);
    state = _load(_p);
  }

  Future<void> setDefaultReminder(int minutes) async {
    await _p.setInt(_MK.defaultReminder, minutes);
    state = _load(_p);
  }

  Future<void> setShowDeclined(bool v) async {
    await _p.setBool(_MK.showDeclined, v);
    state = _load(_p);
  }

  Future<void> setEventFallbackReminder(bool v) async {
    await _p.setBool(_MK.eventFallback, v);
    state = _load(_p);
  }

  Future<void> setEventAlarmClock(bool v) async {
    await _p.setBool(_MK.eventAlarmClock, v);
    state = _load(_p);
  }

  Future<void> setTaskDueHour(int h) async {
    await _p.setInt(_MK.taskDueHour, h.clamp(0, 23));
    state = _load(_p);
  }

  // Contacts
  Future<void> setContactSort(ContactSort v) async {
    await _p.setInt(_MK.contactSort, v.index);
    state = _load(_p);
  }

  Future<void> setShowContactPhotos(bool v) async {
    await _p.setBool(_MK.showPhotos, v);
    state = _load(_p);
  }

  Future<void> setGalFirst(bool v) async {
    await _p.setBool(_MK.galFirst, v);
    state = _load(_p);
  }

  // To Do
  Future<void> setTaskView(TaskDefaultView v) async {
    await _p.setInt(_MK.taskView, v.index);
    state = _load(_p);
  }

  Future<void> setHideCompleted(bool v) async {
    await _p.setBool(_MK.hideCompleted, v);
    state = _load(_p);
  }

  Future<void> setTaskReminderDefault(bool v) async {
    await _p.setBool(_MK.taskReminder, v);
    state = _load(_p);
  }

  // Notes
  Future<void> setNotesPreviewLines(bool v) async {
    await _p.setBool(_MK.notesPreview, v);
    state = _load(_p);
  }

  Future<void> setNotesSortByModified(bool v) async {
    await _p.setBool(_MK.notesSortModified, v);
    state = _load(_p);
  }
}

final moduleSettingsProvider =
    StateNotifierProvider<ModuleSettingsNotifier, ModuleSettings>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return ModuleSettingsNotifier(prefs);
});

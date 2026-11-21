// Виджеты «Календарь» и «Мой день» (замечание владельца 18.11.2026: «не все
// события, которые есть в календаре, отображаются в виджете» — задача
// «Проверка, срок сегодня» была на экране и не было в виджете): дела в
// виджете — те же слои, что в календаре приложения; выходные — для сетки.
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/home_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
        username: 'me@example.com', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'INBOX', accountId: 'a1', displayName: 'Inbox', type: Value(FolderType.inbox.index)));
    // Задача со сроком сегодня (без времени), выполненная задача — не нужна.
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 't1', accountId: 'a1', title: 'Проверка', createdAt: today, dueDate: Value(today)));
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 't2', accountId: 'a1', title: 'Сделано', createdAt: today, dueDate: Value(today), status: const Value(2)));
    // Поручение со сроком сегодня в 15:00; черновик (0) — нет.
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'as1', accountId: 'a1', title: 'Отчёт', ownerEmail: 'boss@corp.ru', status: const Value(1),
        dueAt: Value(today.add(const Duration(hours: 15))), createdAt: today, updatedAt: today));
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'as2', accountId: 'a1', title: 'Черновик', ownerEmail: 'boss@corp.ru',
        dueAt: Value(today.add(const Duration(hours: 16))), createdAt: today, updatedAt: today));
    // Письмо с напоминанием завтра в 10:00.
    await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'm1', accountId: 'a1', folderId: 'INBOX', fromEmail: 'x@corp.ru', toRecipients: '[]',
        subject: 'Счёт', receivedAt: today, followUpAt: Value(today.add(const Duration(days: 1, hours: 10)))));
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> run(String key, [Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    await HomeWidgetService.update(db, ['a1'], AppLocalizations(const Locale('ru')), force: true);
    final p = await SharedPreferences.getInstance();
    return jsonDecode(p.getString(key)!) as Map<String, dynamic>;
  }

  test('календарь: задачи, поручения и письма с напоминанием — как в приложении', () async {
    final j = await run(HomeWidgetService.calendarKey);
    final titles = [for (final e in j['events'] as List) e['s'] as String];
    expect(titles, containsAll(['✓ Проверка', '⚑ Отчёт', '✉ Счёт']));
    expect(titles.any((t) => t.contains('Сделано') || t.contains('Черновик')), isFalse);
    final task = (j['events'] as List).firstWhere((e) => e['s'] == '✓ Проверка');
    expect(task['a'], 1, reason: 'срок без времени — на весь день');
    expect(task['c'], 0xFF2E8B57);
    expect(task['o'], 'task?id=t1&acc=a1');
    final assign = (j['events'] as List).firstWhere((e) => e['s'] == '⚑ Отчёт');
    expect(assign['o'], 'assign?id=as1');
    // Список на 14 дней (виджеты iPhone) — тоже с делами.
    expect([for (final e in j['items'] as List) e['s']], containsAll(['✓ Проверка', '⚑ Отчёт', '✉ Счёт']));
    expect(j['weekend'], [6, 7]);
    expect(j['tabs'], ['День', 'Неделя', 'Месяц', 'Мой день'], reason: 'вкладка «Мой день» на Android');
  });

  test('задача на день с напоминанием в тот же день — во время напоминания (21.11.2026)', () async {
    final at = today.add(const Duration(hours: 11, minutes: 40));
    await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 't3', accountId: 'a1', title: 'Позвонить', createdAt: today, dueDate: Value(today), reminderAt: Value(at)));
    final j = await run(HomeWidgetService.calendarKey);
    final e = (j['events'] as List).firstWhere((e) => e['s'] == '✓ Позвонить');
    expect(e['a'], isNull, reason: 'не «весь день»');
    expect(e['st'], at.millisecondsSinceEpoch);
    // Без напоминания — по-прежнему на весь день.
    expect((j['events'] as List).firstWhere((e) => e['s'] == '✓ Проверка')['a'], 1);
  });

  test('приглашение без ответа — как в календаре приложения, без повтора', () async {
    final st = today.add(const Duration(days: 1, hours: 11));
    String meeting(DateTime s) => jsonEncode({
          'start': s.toUtc().toIso8601String(),
          'end': s.add(const Duration(hours: 1)).toUtc().toIso8601String(),
          'class': 'IPM.Schedule.Meeting.Request',
        });
    await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'inv1', accountId: 'a1', folderId: 'INBOX', fromEmail: 'boss@corp.ru', toRecipients: '[]',
        subject: 'Планёрка', receivedAt: today, meetingJson: Value(meeting(st))));
    // Второе приглашение сервер уже положил в календарь — показываем встречу.
    final st2 = st.add(const Duration(hours: 3));
    await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'inv2', accountId: 'a1', folderId: 'INBOX', fromEmail: 'boss@corp.ru', toRecipients: '[]',
        subject: 'Приглашение: Бюджет', receivedAt: today, meetingJson: Value(meeting(st2))));
    await db.into(db.calendarEvents).insert(CalendarEventsCompanion.insert(
        id: 'ev2', accountId: 'a1', title: 'Бюджет', startTime: st2,
        endTime: st2.add(const Duration(hours: 1)), createdAt: today));
    final j = await run(HomeWidgetService.calendarKey);
    final events = j['events'] as List;
    final inv = events.firstWhere((e) => e['s'] == '? Планёрка');
    expect(inv['o'], 'email?id=inv1&acc=a1', reason: 'письмо с «Принять / Отклонить»');
    expect(inv['en'], st.add(const Duration(hours: 1)).millisecondsSinceEpoch);
    expect(events.where((e) => (e['s'] as String).contains('Бюджет')).length, 1);
  });

  test('слои календаря выключены — и в виджете нет', () async {
    final j = await run(HomeWidgetService.calendarKey,
        {'cal_layer_tasks': false, 'cal_layer_mail': false, 'cal_layer_assignments': false});
    expect(j['events'], isEmpty);
  });

  test('«Мой день»: поручение на сегодня — в списке дня', () async {
    final j = await run(HomeWidgetService.prefKey);
    final titles = [for (final e in j['items'] as List) e['s'] as String];
    expect(titles, contains('⚑ Отчёт'));
    expect(titles, contains('Проверка'), reason: 'задача — своей строкой с галочкой');
    expect(titles.any((t) => t.contains('Счёт')), isFalse, reason: 'напоминание — завтра');
  });
}

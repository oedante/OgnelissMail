// Виджеты 21.11.2026: «Мой день» — «В работе» с письмами на контроле (как
// на экране), дела со временем и подписью, погода из прогноза «Моего дня»;
// «Почта» — название ящика, заданное пользователем, без лишней строки
// счётчиков у одного ящика.
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
        id: 'a1', type: AccountType.imap.index, email: 'oleg@corp.ru', displayName: 'Ермишин Олег Андреевич',
        username: 'oleg@corp.ru', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'INBOX', accountId: 'a1', displayName: 'Inbox', type: Value(FolderType.inbox.index)));
    // Письмо на контроле «Нужно ответить» со сроком сегодня; непрочитанное.
    await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'm1', accountId: 'a1', folderId: 'INBOX', fromEmail: 'boss@corp.ru', toRecipients: '[]',
        subject: 'Цели и задачи', receivedAt: today, controlState: const Value(2),
        followUpAt: Value(today.add(const Duration(hours: 18)))));
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> run(String key, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await HomeWidgetService.update(db, ['a1'], AppLocalizations(const Locale('ru')),
        force: true, labels: const {'a1': 'Ермишин Олег Андреевич'});
    final p = await SharedPreferences.getInstance();
    return jsonDecode(p.getString(key)!) as Map<String, dynamic>;
  }

  test('«Мой день»: письмо на контроле — в «В работе» с подписью', () async {
    final j = await run(HomeWidgetService.prefKey, const {});
    final work = (j['cols'] as List)[1] as Map<String, dynamic>;
    final item = (work['items'] as List).single as Map<String, dynamic>;
    expect(item['s'], 'Цели и задачи');
    expect(item['sub'], contains('Нужно ответить'));
    expect(item['sub'], contains('сегодня'));
    expect(j.containsKey('weather'), isFalse, reason: 'погода выключена');
  });

  test('«Мой день»: погода из сохранённого прогноза', () async {
    final hour = DateTime.now().toUtc();
    final at = DateTime.utc(hour.year, hour.month, hour.day, hour.hour);
    final body = jsonEncode({
      'properties': {
        'timeseries': [
          {
            'time': at.toIso8601String(),
            'data': {
              'instant': {'details': {'air_temperature': -8.6}},
              'next_1_hours': {'summary': {'symbol_code': 'cloudy'}},
            },
          },
        ],
      },
    });
    final j = await run(HomeWidgetService.prefKey, {
      'weather_on': true,
      'weather_cache_v1': jsonEncode({
        'lat': 66.08,
        'lon': 76.68,
        'expires': DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String(),
        'body': body,
        'fetched': DateTime.now().toUtc().toIso8601String(),
      }),
    });
    expect(j['weather'], '☁ −9°');
  });

  test('«Почта»: название ящика от пользователя; один ящик — без строки счётчиков', () async {
    await db.into(db.emails).insert(EmailsCompanion.insert(
        id: 'm2', accountId: 'a1', folderId: 'INBOX', fromEmail: 'x@corp.ru', toRecipients: '[]',
        subject: 'Новое', receivedAt: today));
    final j = await run(HomeWidgetService.mailKey, {'widget_mail_filter': 'acc:a1', 'account_label_a1': 'Работа'});
    expect(j['title'], 'Почта · Работа');
    expect(j['accounts'], '');
  });
}

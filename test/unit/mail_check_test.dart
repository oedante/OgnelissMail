// «Проверка почты» и уведомления по ящику (1.6.45).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/background/background_journal.dart';
import 'package:ogneliss/services/notifications/account_notify_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _entry(String kind, DateTime at, String result, {int ms = 0}) =>
    jsonEncode({'k': kind, 't': at.millisecondsSinceEpoch, 'd': ms, 'r': result, 's': ''});

void main() {
  group('Уведомления по ящику', () {
    test('по умолчанию — все письма; режимы сохраняются и сбрасываются', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      expect(AccountNotify.of(p, 'a1'), AccountNotifyMode.all);
      await AccountNotify.set(p, 'a1', AccountNotifyMode.quiet);
      expect(AccountNotify.of(p, 'a1'), AccountNotifyMode.quiet);
      await AccountNotify.set(p, 'a1', AccountNotifyMode.vipOnly);
      expect(AccountNotify.of(p, 'a1'), AccountNotifyMode.vipOnly);
      // Другой ящик не задет.
      expect(AccountNotify.of(p, 'a2'), AccountNotifyMode.all);
      await AccountNotify.set(p, 'a1', AccountNotifyMode.all);
      expect(p.getString('acc_notify_a1'), isNull);
    });

    test('у каждого режима есть подпись', () {
      for (final m in AccountNotifyMode.values) {
        expect(AccountNotify.labelKey(m), startsWith('accNotify'));
      }
    });
  });

  group('Последняя проверка в фоне', () {
    test('пропуски, ошибки и чужие записи не в счёт', () async {
      final t = DateTime(2026, 10, 19, 12);
      SharedPreferences.setMockInitialValues({
        'bg_journal_v1': [
          _entry('WorkManager', t, 'ok', ms: 5000),
          _entry('пульс', t.add(const Duration(minutes: 10)), 'ok', ms: 2000),
          _entry('WorkManager', t.add(const Duration(minutes: 20)), 'пропуск: приложение работает само'),
          _entry('WorkManager', t.add(const Duration(minutes: 25)), 'проверило приложение: пропуск: приложение открыто'),
          _entry('BGTask iOS', t.add(const Duration(minutes: 30)), 'ошибка: сеть'),
          _entry('свёрнуто', t.add(const Duration(minutes: 40)), 'приложение ушло в фон'),
        ],
      });
      final last = await BackgroundJournal.lastBackgroundCheck();
      expect(last, isNotNull);
      expect(last!.kind, 'пульс');
      expect(last.at, t.add(const Duration(minutes: 10, seconds: 2)));
    });

    test('записей нет — null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await BackgroundJournal.lastBackgroundCheck(), isNull);
    });
  });
}

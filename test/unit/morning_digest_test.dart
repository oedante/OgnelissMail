// test/unit/morning_digest_test.dart
// Утренняя сводка: текст с правильными формами числа, пустой день — без
// уведомления.

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/notifications/reminder_scheduler_service.dart';

void main() {
  test('русский: формы числа и порядок', () {
    final l10n = AppLocalizations(const Locale('ru'));
    expect(ReminderSchedulerService.digestBody(l10n, events: 3, tasks: 1, control: 5),
        '3 встречи · 1 задача · 5 писем на контроле');
    expect(ReminderSchedulerService.digestBody(l10n, events: 0, tasks: 0, control: 21),
        '21 письмо на контроле');
  });

  test('английский и пустой день', () {
    final l10n = AppLocalizations(const Locale('en'));
    expect(ReminderSchedulerService.digestBody(l10n, events: 1, tasks: 2, control: 0), '1 meeting · 2 tasks');
    expect(ReminderSchedulerService.digestBody(l10n, events: 0, tasks: 0, control: 0), isNull);
  });
}

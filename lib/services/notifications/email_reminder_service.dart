// lib/services/notifications/email_reminder_service.dart
// «Посмотреть позже»: периодический чекер (раз в минуту, пока приложение
// живо) возвращает отложенные письма с наступившим сроком — см.
// EmailActionsService.returnDueLater.
//
// Хранение — колонка emails.remindAt (без отдельной таблицы). Работает, пока
// приложение живо/в фоне; при запуске проверка выполняется сразу, поэтому
// просроченные за время оффлайна напоминания сработают при следующем старте.

import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../mail/email_actions_service.dart';

final emailReminderProvider = Provider<EmailReminderService>((ref) {
  final db = ref.watch(databaseProvider);
  final accounts = ref.watch(accountsProvider);
  return EmailReminderService(db, ref, accounts.map((a) => a.id).toList());
});

class EmailReminderService {
  // ignore: unused_field
  final AppDatabase _db;
  final Ref _ref;
  final List<String> _accountIds;
  Timer? _checkTimer;

  EmailReminderService(this._db, this._ref, this._accountIds);

  void start() {
    _checkTimer?.cancel();
    // Раз в минуту — только пока приложение на экране: письмо «возвращается»
    // в ленту, а в фоне о нём и так напомнит уведомление ОС. Раньше таймер
    // будил процесс каждую минуту и свёрнутым (аудит 11.10.2026); при
    // возврате в приложение проверка — сразу (checkNow из MainShell).
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_onScreen) return;
      _checkReminders();
    });
    _checkReminders(); // сразу при старте — подхватываем просроченные за оффлайн
  }

  /// Возврат в приложение: отложенные с наступившим сроком — сразу.
  void checkNow() => unawaited(_checkReminders());

  static bool get _onScreen {
    try {
      final s = WidgetsBinding.instance.lifecycleState;
      return s == null || s == AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  void stop() => _checkTimer?.cancel();

  Future<void> _checkReminders() async {
    if (_accountIds.isEmpty) return;
    // ОС-уведомление (zonedSchedule) само срабатывает в назначенное время, в
    // т.ч. при выгруженном приложении. Здесь — возврат отложенных писем
    // («Посмотреть позже»): «Вернулось» и снова непрочитанное. Уведомление тут
    // НЕ показываем — иначе дубль с ОС-уведомлением.
    try {
      await _ref.read(emailActionsProvider).returnDueLater();
    } catch (e) {
      AppLogger.error('EmailReminder: возврат отложенных', e);
    }
  }
}

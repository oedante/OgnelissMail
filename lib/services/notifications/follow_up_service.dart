// lib/services/notifications/follow_up_service.dart
//
// Напоминания «на письмо нет ответа».
//
// ПОЧЕМУ ЭТО НЕ НАГРУЖАЕТ СИСТЕМУ
// Наивный вариант — периодически перебирать все отправленные письма и для
// каждого искать ответ — стоил бы O(n) запросов при тысячах писем.
// Здесь другой подход:
//  1. Отслеживаются ТОЛЬКО письма, на которые пользователь сам поставил
//     напоминание. Таких строк единицы, а не тысячи.
//  2. Выборка идёт по частичному индексу `idx_emails_followup`
//     (WHERE follow_up_at IS NOT NULL) — индекс маленький.
//  3. Проверка ответа — один запрос по индексу `idx_emails_conversation`
//     с LIMIT 1: ищем в цепочке письмо новее нашего и не от нас.
//  4. Запускается не по таймеру, а вместе с обычной синхронизацией.
// Итого на прогон: 1 запрос + по одному на каждое отслеживаемое письмо.

import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../l10n/app_localizations.dart';
import 'notification_service.dart';

class FollowUpService {
  final AppDatabase _db;
  final NotificationService _notifications;

  FollowUpService(this._db, this._notifications);

  /// Язык текстов уведомлений. BuildContext и Ref здесь нет (сервис работает
  /// и из фоновой синхронизации), поэтому язык читается из настроек
  /// (s_locale), иначе — системный (ru/en/de/fr), иначе английский.
  static Future<AppLocalizations> _l10n() async {
    final supported = AppLocalizations.supportedCodes;
    String? lang;
    try {
      lang = (await SharedPreferences.getInstance()).getString('s_locale');
    } catch (_) {}
    if (lang == null || !supported.contains(lang)) {
      final sys = PlatformDispatcher.instance.locale.languageCode;
      lang = supported.contains(sys) ? sys : 'en';
    }
    // Строки языка — из файла assets/l10n (1.7.3): загрузить до чтения.
    return AppLocalizations.load(lang);
  }

  /// Стандартные варианты отсрочки, предлагаемые в интерфейсе.
  static const presets = <int>[1, 3, 7];

  /// Проверить наступившие напоминания и уведомить о письмах без ответа.
  ///
  /// [accountEmails] — адреса аккаунтов пользователя (письмо от самого себя
  /// ответом не считается). Возвращает число показанных напоминаний.
  Future<int> checkDue(Map<String, String> accountEmails) async {
    var notified = 0;
    try {
      final now = DateTime.now();
      final due = await _db.dueFollowUps(now);
      if (due.isEmpty) return 0;
      final l10n = await _l10n();

      for (final email in due) {
        // Срок — часть «На контроле» (09.10.2026). Исполнено или снято —
        // напоминать не о чем.
        if (email.controlState == 3 || email.controlState == 0) {
          await _db.clearFollowUp(email.id, accountId: email.accountId);
          continue;
        }
        final mustReply = email.controlState == 2;
        if (mustReply) {
          final days = DateTime.now().difference(email.receivedAt).inDays;
          await _notifications.showReminderNotification(
            id: email.id.hashCode & 0x7FFFFFFF,
            title: l10n.tr('controlMustReplyTitle').replaceAll('{subject}', email.subject),
            body: l10n.tr('controlMustReplyBody')
                .replaceAll('{from}', email.fromName ?? email.fromEmail)
                .replaceAll('{n}', '$days'),
            payload: 'email:${email.accountId}:${email.id}',
          );
          await _db.clearFollowUp(email.id, accountId: email.accountId);
          notified++;
          continue;
        }

        // Переиспользуем канал «Напоминания»: отдельный канал ради одной
        // функции не нужен, а пользователь управляет ими в одном месте.
        final days = DateTime.now().difference(email.receivedAt).inDays;
        // Кому: имена тех, кто ещё не ответил (раньше в текст попадал JSON
        // списка адресатов как есть).
        final who = _waitingNames(email.toRecipients, email.controlReplied, accountEmails[email.accountId] ?? '');
        await _notifications.showReminderNotification(
          id: email.id.hashCode & 0x7FFFFFFF,
          title: l10n.tr('followUpNoReplyTitle').replaceAll('{subject}', email.subject),
          body: days > 0
              ? l10n.tr('followUpSentDaysAgo')
                  .replaceAll('{n}', '$days')
                  .replaceAll('{to}', who)
              : l10n.tr('followUpSentToday').replaceAll('{to}', who),
          payload: 'email:${email.accountId}:${email.id}',
        );
        // Срок снимается (отметка «На контроле» остаётся), чтобы не
        // напоминать бесконечно; новый срок ставится из письма.
        await _db.clearFollowUp(email.id, accountId: email.accountId);
        notified++;
      }
    } catch (e, st) {
      AppLogger.error('Ошибка проверки follow-up напоминаний', e, st);
    }
    return notified;
  }

  /// «Иванов, Петров» — адресаты «Кому», которые ещё не ответили.
  static String _waitingNames(String? toJson, String? replied, String me) {
    final done = {for (final a in (replied ?? '').split(',')) if (a.trim().isNotEmpty) a.trim().toLowerCase()};
    try {
      final names = [
        for (final m in (jsonDecode(toJson ?? '[]') as List).whereType<Map>())
          if ((m['email'] ?? '').toString().isNotEmpty &&
              (m['email'] as String).toLowerCase() != me.toLowerCase() &&
              !done.contains((m['email'] as String).toLowerCase()))
            ((m['displayName'] ?? '').toString().trim().isNotEmpty ? m['displayName'] as String : m['email'] as String),
      ];
      return names.take(3).join(', ') + (names.length > 3 ? '…' : '');
    } catch (_) {
      return '';
    }
  }
}

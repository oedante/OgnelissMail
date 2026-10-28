// lib/services/notifications/notification_action_handler.dart
// Обработчик действий из уведомлений: быстрый ответ,
// пометка флагом, архивирование, создание задачи,
// отправка умных шаблонных ответов прямо из шторки.

import '../mail/later_service.dart';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:shared_preferences/shared_preferences.dart';
import '../mail/email_actions_service.dart';
import '../mail/engine/mail_engine_service.dart';
import 'notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/email_model.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../data/providers/database_provider.dart';
import '../../data/database/app_database.dart';
import 'package:drift/drift.dart';
import '../mail/quick_reply_service.dart';
import '../tasks/task_actions_service.dart';
import 'reminder_scheduler_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Провайдер обработчика действий уведомлений
final notificationActionHandlerProvider =
    Provider<NotificationActionHandler>((ref) {
  return NotificationActionHandler(ref);
});

/// Обработчик действий из уведомлений
class NotificationActionHandler {
  final Ref _ref;

  NotificationActionHandler(this._ref);

  /// Выполнить действия, отложенные фоновым обработчиком (не было сети или
  /// фоновый изолят не поднялся). Вызывается при запуске и возврате в
  /// приложение.
  Future<void> runPending() => _pendingRun ??= _runPending().whenComplete(() => _pendingRun = null);

  /// Один проход за раз: запуск и возврат в приложение совпадают по времени,
  /// и два прохода выполнили бы действия дважды.
  static Future<void>? _pendingRun;

  Future<void> _runPending() async {
    try {
      for (final a in await NotificationService.takePendingActions()) {
        await handleAction(a.action, a.payload, a.input);
      }
    } catch (e) {
      AppLogger.warning('Отложенные действия уведомлений: $e');
    }
  }

  /// Обработать действие из уведомления
  /// Возвращает false, если действие не выполнено из-за сбоя (сеть, база) —
  /// фоновый обработчик тогда ставит его в очередь до следующего запуска.
  Future<bool> handleAction(
    String actionId,
    String? payload,
    String? inputText,
  ) async {
    if (payload == null) return true;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String? ?? 'email';

      if (type == 'calendar') {
        await _handleCalendarAction(actionId, data);
        return true;
      }

      // Напоминания встреч и задач (reminder_scheduler_service): кнопки
      // «Подключиться», «Отложить», «Выполнено». Раньше payload встречи
      // («type: event») разбирался как письмо и падал на emailId.
      if (type == 'event') {
        return await _handleEventReminderAction(actionId, data);
      }

      if (type == 'task') {
        return await _handleTaskAction(actionId, data);
      }

      // Сводка группы писем — кнопок нет, нажатие обрабатывает навигация.
      if (type == 'mail_summary') return true;

      // Email actions
      final emailId = data['emailId'] as String;
      final accountId = data['accountId'] as String;
      final folderId = data['folderId'] as String? ?? 'inbox';
      final fromEmail = data['fromEmail'] as String?;
      final subject = data['subject'] as String? ?? '';

      switch (actionId) {
        case 'quick_reply':
          if (inputText != null && inputText.isNotEmpty) {
            await _sendQuickReply(
              accountId: accountId,
              toEmail: fromEmail ?? '',
              subject: subject,
              replyText: inputText,
              originalEmailId: emailId,
            );
          }
          break;

        case 'smart_reply_0':
        case 'smart_reply_1':
          // Умный быстрый ответ — шаблонный текст из кнопки
          // Текст кнопки передаётся через actionId + payload
          final replyText = _getSmartReplyText(actionId, data);
          if (replyText != null) {
            await _sendQuickReply(
              accountId: accountId,
              toEmail: fromEmail ?? '',
              subject: subject,
              replyText: replyText,
              originalEmailId: emailId,
            );
          }
          break;

        case 'flag':
          return await _flagEmail(accountId, emailId);

        case 'mark_read':
          return await _markRead(accountId, emailId, folderId);

        // Приглашение на встречу: ответ прямо из уведомления.
        case 'invite_accept':
          return await _respondInvite(accountId, emailId, folderId, 'accept');
        case 'invite_tentative':
          return await _respondInvite(accountId, emailId, folderId, 'tentative');
        case 'invite_decline':
          return await _respondInvite(accountId, emailId, folderId, 'decline');

        case 'archive':
          return await _archiveEmail(accountId, emailId, folderId);

        case 'delete':
          return await _deleteEmail(accountId, emailId, folderId);

        case 'create_task':
          await _createTaskFromEmail(accountId, emailId, subject);
          break;

        // «Посмотреть позже» вернулось — отложить ещё раз из шторки.
        case 'later_1h':
        case 'later_tomorrow':
          final key = actionId == 'later_1h' ? 'laterIn1h' : 'laterTomorrow';
          final at = LaterService.options(DateTime.now()).firstWhere((o) => o.key == key).at;
          await _ref.read(emailActionsProvider).setLater(emailId, accountId, on: true, at: at);
          return true;

        case 'reply':
          // Открыть экран ответа (через deep link/навигацию)
          // Реализуется через onNotificationTap
          break;

        default:
          AppLogger.warning(
              'Неизвестное действие уведомления: $actionId');
      }
      return true;
    } catch (e, stack) {
      AppLogger.error('Ошибка обработки действия уведомления', e, stack);
      return false;
    }
  }

  /// Отправить быстрый ответ из уведомления
  Future<void> _sendQuickReply({
    required String accountId,
    required String toEmail,
    required String subject,
    required String replyText,
    required String originalEmailId,
  }) async {
    try {
      AppLogger.info(
          'Quick reply: "$replyText" -> $toEmail (re: $subject)');

      final accounts = _ref.read(accountsProvider);
      // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
      // firstWhere без orElse бросал бы StateError и ронял операцию.
      final account = accounts.where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        AppLogger.warning('Аккаунт $accountId не найден — операция пропущена');
        return;
      }

      // Письмом (приветствие, текст, подпись), через очередь отправки —
      // общий с быстрым ответом внизу письма (QuickReplyService, 1.6.49).
      await _ref.read(quickReplyServiceProvider).send(
            account: account,
            to: [EmailAddress(email: toEmail)],
            subject: subject,
            text: replyText,
            originalEmailId: originalEmailId,
          );
    } catch (e, stack) {
      AppLogger.error('Ошибка обработки quick reply', e, stack);
    }
  }

  /// Пометить письмо флагом
  Future<bool> _flagEmail(String accountId, String emailId) async {
    try {
      final accounts = _ref.read(accountsProvider);
      // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
      // firstWhere без orElse бросал бы StateError и ронял операцию.
      final account = accounts.where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        AppLogger.warning('Аккаунт $accountId не найден — операция пропущена');
        return true; // ящика больше нет — повторять нечего
      }

      // EAS→движок, EWS→ews, IMAP→imap (папка по умолчанию — входящие).
      await _ref.read(emailActionsProvider).setFlag(account, emailId, 'inbox', true);

      AppLogger.info('Email flagged from notification: $emailId');
      return true;
    } catch (e) {
      AppLogger.error('Ошибка пометки флагом из уведомления', e);
      return false;
    }
  }

  /// Пометить прочитанным из шторки + убрать уведомление.
  Future<bool> _markRead(String accountId, String emailId, String folderId) async {
    try {
      final accounts = _ref.read(accountsProvider);
      // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
      // firstWhere без orElse бросал бы StateError и ронял операцию.
      final account = accounts.where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        AppLogger.warning('Аккаунт $accountId не найден — операция пропущена');
        return true; // ящика больше нет — повторять нечего
      }
      await _ref.read(emailActionsProvider).setRead(account, emailId, folderId, true);
      // Прочитано → уведомление больше не нужно.
      await _ref.read(notificationServiceProvider).cancelEmail(accountId, emailId);
      AppLogger.info('Email marked read from notification: $emailId');
      return true;
    } catch (e) {
      AppLogger.error('Ошибка пометки прочитанным из уведомления', e);
      return false;
    }
  }

  /// Ответ на приглашение из уведомления (Exchange: ActiveSync
  /// MeetingResponse или EWS). Сервер сам отправляет ответ организатору и
  /// ставит встречу в календарь; письмо-приглашение — прочитано, уведомление
  /// убирается. false — не дошло (нет сети): повторим при открытии.
  Future<bool> _respondInvite(String accountId, String emailId, String folderId, String response) async {
    try {
      final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
      if (account == null) return true;
      // Данные приглашения — для ActiveSync до 16.0: там ответ организатору
      // уходит письмом (iMIP), нужны UID и адрес организатора.
      final row = await _ref.read(databaseProvider).getEmailById(emailId, accountId: accountId);
      final prefs = await SharedPreferences.getInstance();
      final l10n = await AppLocalizations.load(prefs.getString('s_locale') ?? PlatformDispatcher.instance.locale.languageCode);
      final title = row?.subject ?? '';
      final kind = switch (response) { 'accept' => 'Accept', 'tentative' => 'Tentative', _ => 'Decline' };
      final res = await _ref.read(mailEngineServiceProvider).respondToMeeting(
            account,
            itemId: emailId,
            response: response,
            folderId: folderId,
            meeting: EmailMeeting.parse(row?.meetingJson),
            title: title,
            mailSubject: l10n.tr('imipSubj$kind').replaceAll('{s}', title),
            mailBody: l10n.tr('imipBody$kind').replaceAll('{s}', title),
          );
      final ok = res.ok;
      if (!ok) {
        AppLogger.warning('Ответ на приглашение из уведомления ($response) не отправлен');
        return false;
      }
      try {
        await _ref.read(emailActionsProvider).setRead(account, emailId, folderId, true);
      } catch (_) {}
      await _ref.read(notificationServiceProvider).cancelEmail(accountId, emailId);
      // Встреча появится в календаре со следующей синхронизацией (сервер уже
      // поставил её). Синхронизацию отсюда не запускаем: в фоновом изоляте у
      // действия 50 с, а долгий проход по таймауту повторил бы и сам ответ.
      AppLogger.info('Ответ на приглашение из уведомления: $response');
      return true;
    } catch (e) {
      AppLogger.error('Ответ на приглашение из уведомления', e);
      return false;
    }
  }

  /// Удалить письмо (в «Удалённые») и убрать уведомление.
  Future<bool> _deleteEmail(String accountId, String emailId, String folderId) async {
    try {
      final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
      if (account == null) return true;
      await _ref.read(emailActionsProvider).delete(account, emailId, folderId);
      await _ref.read(notificationServiceProvider).cancelEmail(accountId, emailId);
      AppLogger.info('Email deleted from notification: $emailId');
      return true;
    } catch (e) {
      AppLogger.error('Ошибка удаления из уведомления', e);
      return false;
    }
  }

  /// Архивировать письмо
  Future<bool> _archiveEmail(
      String accountId, String emailId, String folderId) async {
    try {
      final accounts = _ref.read(accountsProvider);
      // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
      // firstWhere без orElse бросал бы StateError и ронял операцию.
      final account = accounts.where((a) => a.id == accountId).firstOrNull;
      if (account == null) {
        AppLogger.warning('Аккаунт $accountId не найден — операция пропущена');
        return true; // ящика больше нет — повторять нечего
      }

      await _ref.read(emailActionsProvider)
          .moveTo(account, emailId, folderId, 'archivemsgfolderroot');

      AppLogger.info('Email archived from notification: $emailId');
      return true;
    } catch (e) {
      AppLogger.error('Ошибка архивирования из уведомления', e);
      return false;
    }
  }

  /// Создать задачу из письма
  Future<void> _createTaskFromEmail(
      String accountId, String emailId, String subject) async {
    try {
      // Создаём задачу в локальной БД
      final db = _ref.read(databaseProvider);
      await db.into(db.tasks).insert(TasksCompanion.insert(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}',
        accountId: accountId,
        title: subject,
        status: const Value(0),
        priority: const Value(1),
        createdAt: DateTime.now(),
        linkedEmailId: Value(emailId),
        linkedEmailSubject: Value(subject),
      ));
      AppLogger.info('Задача создана из уведомления: $subject');
    } catch (e) {
      AppLogger.error('Ошибка создания задачи из уведомления', e);
    }
  }

  /// Обработка действий календаря
  Future<void> _handleCalendarAction(
      String actionId, Map<String, dynamic> data) async {
    final eventId = data['eventId'] as String?;
    if (eventId == null) return;

    switch (actionId) {
      case 'accept':
        AppLogger.info('Calendar event accepted: $eventId');
        break;
      case 'decline':
        AppLogger.info('Calendar event declined: $eventId');
        break;
      case 'tentative':
        AppLogger.info('Calendar event tentative: $eventId');
        break;
    }
  }

  /// Кнопки напоминания о встрече.
  Future<bool> _handleEventReminderAction(String actionId, Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    final accountId = data['accountId'] as String?;
    if (id == null || accountId == null) return true;
    switch (actionId) {
      case 'snooze':
        await _ref.read(reminderSchedulerProvider).snooze(
            kind: 'event', accountId: accountId, id: id, delay: const Duration(minutes: 10));
        return true;
      case 'join':
        final url = data['url'] as String?;
        if (url == null || url.isEmpty) return true;
        final uri = Uri.tryParse(url);
        if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http' ||
            uri.scheme == 'msteams' || uri.scheme == 'zoommtg')) {
          return true;
        }
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          AppLogger.warning('Подключение к встрече: $e');
        }
        return true;
      default:
        return true;
    }
  }

  /// Кнопки напоминания о задаче: «Выполнено», «Через час».
  Future<bool> _handleTaskAction(String actionId, Map<String, dynamic> data) async {
    final id = (data['id'] ?? data['taskId']) as String?;
    final accountId = data['accountId'] as String?;
    if (id == null || accountId == null) return true;
    try {
      switch (actionId) {
        case 'task_done':
          await _ref.read(taskActionsProvider).setDone(accountId, id, true);
          AppLogger.info('Задача выполнена из уведомления');
          return true;
        case 'snooze':
          await _ref.read(reminderSchedulerProvider).snooze(
              kind: 'task', accountId: accountId, id: id, delay: const Duration(hours: 1));
          return true;
        default:
          return true;
      }
    } catch (e) {
      AppLogger.warning('Действие задачи $actionId: $e');
      return false;
    }
  }

  /// Получить текст умного ответа по actionId
  String? _getSmartReplyText(
      String actionId, Map<String, dynamic> data) {
    // Умные ответы генерируются динамически при показе уведомления
    // и сохраняются в payload
    final replies = data['smartReplies'] as List<dynamic>?;
    if (replies == null) return null;

    final index = actionId == 'smart_reply_0' ? 0 : 1;
    if (index < replies.length) {
      return replies[index] as String;
    }
    return null;
  }
}

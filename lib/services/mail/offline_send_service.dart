// lib/services/mail/offline_send_service.dart
// Отправка писем через offline queue:
// - Если нет сети → сохраняем в sync_queue
// - При восстановлении связи → отправляем
// - Статус: pending / sending / sent / failed
// - Уведомление при успешной отправке

import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/finish_in_background.dart';
import '../notifications/notification_service.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import 'transport/mail_transport.dart';
import '../../features/mail/providers/mail_open_cache.dart' show mailOpenCacheProvider;
import '../../features/mail/providers/mail_providers.dart';
import '../../features/compose/providers/attachment_limit_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../sync/sync_service.dart';
import 'attachment_cache_service.dart' show attachmentCacheProvider;
import 'draft_files.dart';
import 'sent_placeholder.dart';
import 'engine/mail_engine_service.dart' show MailEngineService, mailEngineServiceProvider;
import 'draft_autosave_service.dart' show DraftData, draftAutosaveProvider;
import 'draft_sync_service.dart' show draftSyncServiceProvider;
import 'email_actions_service.dart' show emailActionsProvider;
import 'package:mail_engine/mail_engine.dart' as me show EasEngine, GatewayBlocked, GatewaySizeRejected, SmtpNotSentException;
import 'package:uuid/uuid.dart';

/// Письмо не ушло из-за размера: сервер назвал лимит или шлюз перед
/// Exchange не пропустил большое письмо (1.7.2+114). Повтор того же письма
/// не поможет. Редактор письма ловит это исключение и оставляет письмо
/// открытым (раньше письмо, отклонённое по размеру, не попадало ни в
/// очередь, ни в черновики — редактор закрывался, и письмо пропадало).
class MessageTooLargeException implements Exception {
  /// Размер письма, которое не пропустили (байт), если известен.
  final int? sizeBytes;

  /// Лимит, который назвал сервер (байт), если назвал.
  final int? limitBytes;

  /// Не пропустил шлюз перед сервером (а не сам сервер).
  final bool gateway;

  const MessageTooLargeException({this.sizeBytes, this.limitBytes, this.gateway = false});

  @override
  String toString() => 'message_too_large${gateway ? ' (шлюз)' : ''}'
      '${sizeBytes != null ? ', письмо $sizeBytes байт' : ''}'
      '${limitBytes != null ? ', лимит $limitBytes байт' : ''}';
}

/// Вложение письма с сервера, которое ещё не скачано на телефон (1.6.18):
/// пересылка письма, файлы которого не открывали. Скачивается перед
/// отправкой — сразу или из очереди, когда появится связь.
typedef RemoteAttachment = ({
  String accountId,
  String emailId,
  String attachmentId,
  String name,
  String? contentType,
});

final offlineSendProvider = Provider<OfflineSendService>((ref) {
  return OfflineSendService(ref);
});

/// Письмо, которое отправляется прямо сейчас без очереди (окно отмены
/// выключено): в «Исходящих» — «Отправляется…», пока сервер не принял.
class OutboxSending {
  final String id;
  final String accountId;
  final String subject;
  final String to;
  final DateTime startedAt;
  const OutboxSending({required this.id, required this.accountId, required this.subject, required this.to, required this.startedAt});
}

class OfflineSendService {
  final Ref _ref;

  /// Предельный суммарный размер офлайн-очереди (base64 вложений хранится в
  /// БД). 200 МБ — компромисс: письма с вложениями при недельной работе без
  /// связи поместятся, но база не разрастётся до опасных величин, а чтение
  /// payload не исчерпает память на слабом устройстве.
  static const int maxQueueBytes = 200 * 1024 * 1024;

  OfflineSendService(this._ref);

  /// Отправляемые сейчас без очереди — для «Исходящих» (21.11.2026).
  final ValueNotifier<List<OutboxSending>> sendingNow = ValueNotifier(const []);

  /// Строки для пользователя (уведомления, причина в «не отправлено») на языке
  /// интерфейса: BuildContext в сервисе нет, язык берём из настроек.
  AppLocalizations _l10n() => AppLocalizations(_ref.read(settingsProvider).locale);

  /// Отправить письмо (если онлайн — сразу, если офлайн — в очередь).
  /// iPhone (1.6.44): свернули сразу после «Отправить» — iOS даёт время
  /// доделать отправку ([FinishInBackground]), а не морозит её до открытия.
  Future<bool> sendOrQueue({
    required String accountId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    List<RemoteAttachment> remoteAttachments = const [],
    /// Адрес отправки «от имени» (1.6.27); null — адрес ящика.
    EmailAddress? from,
    /// Письмо, не принятое по размеру, — исключением
    /// [MessageTooLargeException] (редактор письма оставляет его открытым).
    /// false — в «не отправлено» с причиной и уведомлением.
    bool keepTooLarge = false,
    /// «Запросить подтверждение доставки» (1.9.x, DSN NOTIFY=SUCCESS у SMTP).
    bool requestDeliveryReport = false,
    /// «Запросить уведомление о прочтении» (2.2.0): Disposition-Notification-To
    /// (SMTP, ActiveSync), IsReadReceiptRequested (EWS).
    bool requestReadReceipt = false,
    /// Отправленное — сразу в беседе временной строкой с текстом (2.6.8,
    /// [SentPlaceholder]). Быстрый ответ ставит свою строку сам (с набранным
    /// текстом) — передаёт false.
    bool showInConversation = true,
  }) =>
      FinishInBackground.guard(() => _sendOrQueue(
            accountId: accountId,
            to: to,
            cc: cc,
            bcc: bcc,
            subject: subject,
            bodyHtml: bodyHtml,
            inReplyTo: inReplyTo,
            attachments: attachments,
            importance: importance,
            sensitivity: sensitivity,
            remoteAttachments: remoteAttachments,
            from: from,
            keepTooLarge: keepTooLarge,
            requestDeliveryReport: requestDeliveryReport,
            requestReadReceipt: requestReadReceipt,
            showInConversation: showInConversation,
          ));

  Future<bool> _sendOrQueue({
    required String accountId,
    required List<EmailAddress> to,
    required List<EmailAddress> cc,
    required List<EmailAddress> bcc,
    required String subject,
    required String bodyHtml,
    required String? inReplyTo,
    required List<({String name, String? contentType, Uint8List bytes})> attachments,
    required String importance,
    required String sensitivity,
    required List<RemoteAttachment> remoteAttachments,
    required EmailAddress? from,
    required bool keepTooLarge,
    required bool requestDeliveryReport,
    required bool requestReadReceipt,
    bool showInConversation = true,
  }) async {
    final connectivity = _ref.read(connectivityServiceProvider);
    // Один ClientId на письмо с первой попытки (07.11.2026, аудит): сервер
    // ActiveSync по нему узнаёт повтор (Status 118) и не отправит дважды.
    // Раньше первая отправка шла без ClientId, а очередь — с новым «q<id>»:
    // при обрыве VPN после приёма письма получатель мог получить дубль.
    final clientId = 'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '${math.Random().nextInt(0x7fffffff).toRadixString(36)}';

    if (connectivity.isConnected) {
      // Онлайн — отправляем сразу
      try {
        final accounts = _ref.read(accountsProvider);
        // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
        // firstWhere без orElse бросал бы StateError и ронял операцию.
        final account = accounts.where((a) => a.id == accountId).firstOrNull;
        if (account == null) {
          AppLogger.warning('Аккаунт $accountId не найден — операция пропущена');
          return false;
        }

        // Файлы пересылаемого письма, которых нет на телефоне: качаем сейчас.
        // Не вышло (нет связи с сервером) — письмо ждёт в очереди и уйдёт
        // вместе с ними, а не без них (1.6.18).
        var all = attachments;
        if (remoteAttachments.isNotEmpty) {
          try {
            all = [...attachments, ...await fetchRemoteAttachments(remoteAttachments)];
          } catch (e) {
            AppLogger.warning('Вложения пересылаемого письма не скачаны — письмо в очереди: $e');
            await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo,
                attachments: attachments, importance: importance, sensitivity: sensitivity,
                remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt);
            _wakeAt(accountId, DateTime.now().add(const Duration(seconds: 60)));
            return false;
          }
        }

        final transport = _ref.read(mailTransportFactoryProvider).forAccount(account);
        // В «Исходящих» — пока сервер не принял (как в Outlook).
        final now = OutboxSending(
          id: clientId,
          accountId: accountId,
          subject: subject,
          to: [for (final r in to) (r.displayName ?? '').trim().isNotEmpty ? r.displayName!.trim() : r.email].join(', '),
          startedAt: DateTime.now(),
        );
        sendingNow.value = [...sendingNow.value, now];
        try {
          await transport.send(account, to: to, cc: cc, bcc: bcc,
              subject: subject, bodyHtml: bodyHtml, inReplyTo: inReplyTo, attachments: all, importance: importance, sensitivity: sensitivity,
              from: from, clientId: clientId,
              requestDeliveryReport: requestDeliveryReport,
              requestReadReceipt: requestReadReceipt);
        } finally {
          sendingNow.value = [for (final x in sendingNow.value) if (x.id != clientId) x];
        }

        AppLogger.info('Email sent: $subject');
        if (showInConversation) {
          unawaited(_showSentInConversation(account,
              to: to, cc: cc, subject: subject, html: bodyHtml, inReplyTo: inReplyTo, hasAttachments: all.isNotEmpty));
        }
        _afterSent(account);
        return true;
      } catch (e) {
        // Сервер или шлюз не принял письмо по размеру: повторная отправка
        // того же письма не поможет — в очередь не ставим. Лимит, если
        // сервер его назвал, запоминаем. Раньше на этом письмо пропадало:
        // ни очереди, ни черновика, а редактор закрывался.
        final tooLarge = tooLargeOf(e);
        if (tooLarge != null) {
          AppLogger.error('Send failed (размер письма), в очередь не ставим: $e');
          final limit = tooLarge.limitBytes;
          if (limit != null) await _ref.read(attachmentLimitProvider).setLimit(accountId, limit);
          if (keepTooLarge) throw tooLarge;
          await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo,
              attachments: attachments, importance: importance, sensitivity: sensitivity,
              remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt,
              operationType: 'send_failed',
              errorMessage: tooLargeText(_l10n(), tooLarge));
          await _notifyNotSent(accountId, 'toolarge_${DateTime.now().millisecondsSinceEpoch}', subject);
          return false;
        }
        AppLogger.error('Send failed, queuing: $e');
        // Шлюз не пропустил запрос из этой сети (18.11.2026): в очередь с
        // понятной причиной; уйдёт после смены сети или паузы шлюза.
        if (e is me.GatewayBlocked) {
          final id = await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo,
              attachments: attachments, importance: importance, sensitivity: sensitivity,
              remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt,
              clientId: clientId, errorMessage: _l10n().tr('offlineErrGateway'));
          _gatewayHeld[id] = e.host;
          final left = me.EasEngine.wafPauseMinutesLeft(e.host);
          _wakeAt(accountId, DateTime.now().add(Duration(minutes: left > 0 ? left : 15)));
          return false;
        }
        // Таймаут ожидания ответа: сервер мог письмо уже принять. Повторная
        // отправка из очереди дала бы получателю дубль. Кладём письмо в
        // «не отправлено» (видно и можно отправить заново) и просим проверить
        // «Отправленные».
        // ActiveSync — повтор безопасен: тот же ClientId, сервер узнает
        // уже принятое письмо.
        final eas = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull?.usesEas ?? false;
        if (_isUncertainTimeout(e) && !eas) {
          await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo,
              attachments: attachments, importance: importance, sensitivity: sensitivity,
              remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt,
              operationType: 'send_failed',
              errorMessage: _l10n().tr('offlineErrTimeout'));
          await _notifyUncertain(accountId, 'timeout_${DateTime.now().millisecondsSinceEpoch}',
              jsonEncode({'subject': subject}));
          return false;
        }
        await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo, attachments: attachments, importance: importance, sensitivity: sensitivity,
            remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt, clientId: clientId);
        // Раньше письмо из очереди уходило только со следующей полной
        // синхронизацией (до 15 минут). Теперь — повтор через 30 секунд.
        _wakeAt(accountId, DateTime.now().add(const Duration(seconds: 30)));
        return false;
      }
    } else {
      // Офлайн — в очередь
      await _enqueue(accountId, to, cc, bcc, subject, bodyHtml, inReplyTo, attachments: attachments, importance: importance, sensitivity: sensitivity,
          remoteAttachments: remoteAttachments, from: from, dsn: requestDeliveryReport, mdn: requestReadReceipt);
      AppLogger.info('Email queued (offline): $subject');
      return false;
    }
  }

  /// Запланировать отправку письма на заданное время [scheduledAt].
  /// Письмо ставится в очередь и не отправляется, пока время не наступит
  /// (проверяется в processQueue). Хранится в том же sync_queue без миграции БД.
  Future<void> scheduleSend({
    required String accountId,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    required DateTime scheduledAt,
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
    ({String accountId, String emailId})? quoteImages,
    ({String accountId, String id, String folderId})? dropDraft,
  }) async {
    final db = _ref.read(databaseProvider);
    // Защита от разрастания БД при длительной работе без связи: вложения
    // лежат в очереди как base64. Без проверки несколько писем по 25 МБ
    // раздули бы базу на сотни мегабайт, а чтение payload могло исчерпать
    // память на слабом устройстве.
    final queued = await db.queuePayloadBytes();
    final incoming = attachments.fold<int>(0, (sum, a) => sum + (a.bytes.length * 4 ~/ 3));
    if (queued + incoming > maxQueueBytes) {
      AppLogger.warning(
          'Очередь офлайн-отправки переполнена: ${queued ~/ (1024 * 1024)} МБ + '
          '${incoming ~/ (1024 * 1024)} МБ > лимит ${maxQueueBytes ~/ (1024 * 1024)} МБ');
      throw StateError('offline_queue_full');
    }
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          accountId: accountId,
          operationType: 'send_email',
          targetId: 'scheduled_${DateTime.now().millisecondsSinceEpoch}',
          payloadJson: jsonEncode({
            'to': to.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'cc': cc.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'bcc': bcc.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'subject': subject,
            'bodyHtml': bodyHtml,
            'inReplyTo': inReplyTo,
            'attachments': [for (final a in attachments) {'name': a.name, 'contentType': a.contentType, 'base64': base64Encode(a.bytes)}],
            'importance': importance,
            'sensitivity': sensitivity,
            if (from != null) 'from': {'email': from.email, 'displayName': from.displayName},
            if (remoteAttachments.isNotEmpty) 'remoteAttachments': _remoteToJson(remoteAttachments),
            // Картинки цитаты, которых не было на телефоне (25.11.2026):
            // докачиваются перед отправкой ([_embedQuoteImages]).
            if (quoteImages != null) 'quoteImages': {'accountId': quoteImages.accountId, 'emailId': quoteImages.emailId},
            // Серверный черновик, из которого берутся не скачанные файлы, —
            // удалить после отправки ([_dropSentDraft]).
            if (dropDraft != null)
              'dropDraft': {'accountId': dropDraft.accountId, 'id': dropDraft.id, 'folderId': dropDraft.folderId},
            'scheduledAt': scheduledAt.toIso8601String(),
            if (requestDeliveryReport) 'dsn': true,
            if (requestReadReceipt) 'mdn': true,
          }),
          priority: const Value(10),
          createdAt: DateTime.now(),
        ));
    AppLogger.info('Email scheduled for $scheduledAt: $subject');
    // Пока приложение живо — отправляем точно в срок, а не при ближайшей
    // синхронизации после него.
    _wakeAt(accountId, scheduledAt);
  }

  /// Новое время отложенного письма (1.6.49, «Запланированные» над лентой).
  /// [at] не в будущем — «Отправить сейчас»: очередь разбирается сразу.
  /// false — строки уже нет (письмо ушло или отменено).
  Future<bool> rescheduleQueued(int queueId, DateTime at) async {
    final db = _ref.read(databaseProvider);
    final row = await (db.select(db.syncQueue)..where((q) => q.id.equals(queueId))).getSingleOrNull();
    if (row == null) return false;
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    final now = DateTime.now();
    final when = at.isAfter(now) ? at : now;
    payload['scheduledAt'] = when.toIso8601String();
    await (db.update(db.syncQueue)..where((q) => q.id.equals(queueId)))
        .write(SyncQueueCompanion(payloadJson: Value(jsonEncode(payload))));
    AppLogger.info(at.isAfter(now) ? 'Отложенное письмо перенесено на $when' : 'Отложенное письмо — отправить сейчас');
    if (at.isAfter(now)) {
      _wakeAt(row.accountId, when);
    } else if (_ref.read(connectivityServiceProvider).isConnected) {
      unawaited(processQueue(row.accountId).catchError((Object e) {
        AppLogger.warning('Очередь отправки: $e');
        return 0;
      }));
    }
    return true;
  }

  /// Отменить отложенное письмо: строка очереди удаляется (письмо не уйдёт).
  /// false — письмо уже отправляется (или ушло).
  Future<bool> cancelQueued(int queueId) async {
    final db = _ref.read(databaseProvider);
    final n = await (db.delete(db.syncQueue)
          ..where((q) => q.id.equals(queueId) & q.operationType.equals('send_email')))
        .go();
    if (n > 0) AppLogger.info('Отложенная отправка отменена');
    return n > 0;
  }

  // ─────────────────────── Блокировка шлюзом организации ───────────────────────
  /// Письма очереди, которые шлюз перед Exchange не пропустил из текущей
  /// сети: id строки очереди → узел шлюза (18.11.2026).
  final Map<int, String> _gatewayHeld = {};

  /// Попыток отправки, которые шлюз не пропустил, до «не отправлено».
  static const gatewayMaxRetries = 8;

  /// «Отправить снова» в списке очереди: не ждать смены сети.
  void releaseGatewayHold(int queueId) => _gatewayHeld.remove(queueId);

  /// Сеть сменилась (Wi-Fi ↔ мобильная, VPN): блокировка шлюза была по
  /// прежнему адресу — паузы снимаются, задержанные письма уходят сразу.
  void onNetworkChanged() {
    me.EasEngine.clearWafPauses();
    if (_gatewayHeld.isEmpty) return;
    AppLogger.info('Сеть сменилась — повторяем письма, которые не пропустил шлюз (${_gatewayHeld.length})');
    unawaited(() async {
      final db = _ref.read(databaseProvider);
      final rows = await (db.select(db.syncQueue)..where((q) => q.id.isIn(_gatewayHeld.keys.toList()))).get();
      for (final accountId in {for (final r in rows) r.accountId}) {
        _wakeAt(accountId, DateTime.now());
      }
    }());
  }

  // ─────────────────────────── Пробуждение очереди ───────────────────────────
  final Map<String, Timer> _wakeTimers = {};
  final Map<String, DateTime> _wakeAtTime = {};

  /// Разобрать очередь аккаунта в момент [at] (берётся самый ранний из
  /// запрошенных). Без связи таймер не крутится впустую: при восстановлении
  /// сети очередь разбирает синхронизация.
  void _wakeAt(String accountId, DateTime at) {
    final prev = _wakeAtTime[accountId];
    if (prev != null && !at.isBefore(prev) && _wakeTimers[accountId]?.isActive == true) return;
    _wakeTimers[accountId]?.cancel();
    _wakeAtTime[accountId] = at;
    var delay = at.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    _wakeTimers[accountId] = Timer(delay + const Duration(milliseconds: 500), () async {
      _wakeTimers.remove(accountId);
      _wakeAtTime.remove(accountId);
      if (!_ref.read(connectivityServiceProvider).isConnected) return;
      try {
        await processQueue(accountId);
      } catch (e) {
        AppLogger.warning('Очередь отправки: $e');
      }
    });
  }

  /// Ответ — сразу в беседе письма, на которое отвечали (2.6.8, замечание
  /// владельца 21.11.2026: «карточки в беседах… пустыми, а потом
  /// подгружают. Часто если только отправил»): временная строка с текстом
  /// до прихода серверной копии ([SentPlaceholder]). Новое письмо (не
  /// ответ) — без неё: беседы ещё нет.
  Future<void> _showSentInConversation(AccountModel account,
      {required List<EmailAddress> to,
      required List<EmailAddress> cc,
      required String subject,
      required String html,
      required String? inReplyTo,
      bool hasAttachments = false}) async {
    try {
      final db = _ref.read(databaseProvider);
      final conv = await SentPlaceholder.conversationOf(db, account.id, inReplyTo);
      if (conv == null) return;
      await SentPlaceholder.insert(db, account,
          conversationId: conv, to: to, cc: cc, subject: subject, html: html, hasAttachments: hasAttachments);
    } catch (e) {
      AppLogger.debug('Отправленное в беседе: $e');
    }
  }

  void _afterSent(AccountModel account) {
    try {
      _ref.read(syncServiceProvider).refreshSentSoon(account);
    } catch (_) {}
  }

  // ─────────────────────────── Undo Send (через Исходящие) ───────────────────────────
  // Письмо кладётся в папку Исходящие (видно, можно отменить/отредактировать) и
  // ставится в очередь с отложенным временем. По истечении окна отправляется;
  // переживает перезапуск (очередь обработается при следующей синхронизации).
  final Map<String, Timer> _undoTimers = {};

  /// Запланировать отправку с окном отмены. Возвращает id письма в Исходящих.
  Future<String> scheduleUndoSend({
    required String accountId,
    required String fromEmail,
    required List<EmailAddress> to,
    List<EmailAddress> cc = const [],
    List<EmailAddress> bcc = const [],
    required String subject,
    required String bodyHtml,
    String? bodyPlain,
    String? inReplyTo,
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    required Duration window,
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool requestDeliveryReport = false,
    bool requestReadReceipt = false,
    ({String accountId, String emailId})? quoteImages,
    ({String accountId, String id, String folderId})? dropDraft,
  }) async {
    final db = _ref.read(databaseProvider);
    final outboxId = 'undosend_${DateTime.now().millisecondsSinceEpoch}';
    final scheduledAt = DateTime.now().add(window);

    List<Map<String, dynamic>> mapAddrs(List<EmailAddress> a) =>
        a.map((r) => {'email': r.email, 'displayName': r.displayName}).toList();

    // 1. Материализуем письмо в папке Исходящие (для видимости/отмены/правки).
    await db.into(db.emails).insertOnConflictUpdate(EmailsCompanion.insert(
          id: outboxId,
          accountId: accountId,
          folderId: 'outbox',
          folderName: const Value('Outbox'),
          fromEmail: fromEmail,
          toRecipients: jsonEncode(mapAddrs(to)),
          ccJson: Value(cc.isNotEmpty ? jsonEncode(mapAddrs(cc)) : null),
          bccJson: Value(bcc.isNotEmpty ? jsonEncode(mapAddrs(bcc)) : null),
          subject: subject,
          bodyPlain: Value(bodyPlain),
          bodyHtml: Value(bodyHtml),
          receivedAt: DateTime.now(),
          // Когда уйдёт: строка «Отправка через N с · Отменить» в ленте.
          sentAt: Value(scheduledAt),
          isDraft: const Value(false),
          status: const Value(0),
          cachedAt: Value(DateTime.now()),
        ));

    // 2. Отложенная отправка в очередь (targetId = id письма в Исходящих —
    //    по нему processQueue уберёт письмо из Исходящих после отправки).
    await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          accountId: accountId,
          operationType: 'send_email',
          targetId: outboxId,
          payloadJson: jsonEncode({
            'to': mapAddrs(to),
            'cc': mapAddrs(cc),
            'bcc': mapAddrs(bcc),
            'subject': subject,
            'bodyHtml': bodyHtml,
            'inReplyTo': inReplyTo,
            'attachments': [for (final a in attachments) {'name': a.name, 'contentType': a.contentType, 'base64': base64Encode(a.bytes)}],
            'importance': importance,
            'sensitivity': sensitivity,
            if (from != null) 'from': {'email': from.email, 'displayName': from.displayName},
            if (remoteAttachments.isNotEmpty) 'remoteAttachments': _remoteToJson(remoteAttachments),
            // Картинки цитаты, которых не было на телефоне (25.11.2026):
            // докачиваются перед отправкой ([_embedQuoteImages]).
            if (quoteImages != null) 'quoteImages': {'accountId': quoteImages.accountId, 'emailId': quoteImages.emailId},
            // Серверный черновик, из которого берутся не скачанные файлы, —
            // удалить после отправки ([_dropSentDraft]).
            if (dropDraft != null)
              'dropDraft': {'accountId': dropDraft.accountId, 'id': dropDraft.id, 'folderId': dropDraft.folderId},
            'scheduledAt': scheduledAt.toIso8601String(),
            if (requestDeliveryReport) 'dsn': true,
            if (requestReadReceipt) 'mdn': true,
          }),
          priority: const Value(10),
          createdAt: DateTime.now(),
        ));

    // 3. Таймер на своевременную отправку (если приложение закроют — письмо всё
    //    равно уйдёт при следующей синхронизации, т.к. лежит в очереди).
    _undoTimers[outboxId]?.cancel();
    _undoTimers[outboxId] = Timer(window + const Duration(milliseconds: 300), () {
      _undoTimers.remove(outboxId);
      processQueue(accountId);
    });
    return outboxId;
  }

  /// Отменить отложенную отправку: убрать из очереди, письмо вернуть в Черновики
  /// (чтобы можно было отредактировать). true, если успели до фактической отправки.
  Future<bool> cancelUndoSend(String outboxId) async {
    final db = _ref.read(databaseProvider);
    _undoTimers[outboxId]?.cancel();
    _undoTimers.remove(outboxId);
    // Файлы письма — из очереди, пока запись не удалена (1.7.2+111: раньше
    // письмо возвращалось в «Черновики» без вложений).
    final queued = await (db.select(db.syncQueue)
          ..where((q) =>
              q.targetId.equals(outboxId) &
              q.operationType.isIn(const ['send_email', 'send_pending'])))
        .get();
    // Удаляем только ещё не начатую отправку: если запись уже захвачена
    // («отправляется»), письмо может уйти — сообщать «отменено» нельзя.
    final removed = await (db.delete(db.syncQueue)
          ..where((q) =>
              q.targetId.equals(outboxId) &
              q.operationType.isIn(const ['send_email', 'send_pending'])))
        .go();
    if (removed == 0) return false;
    // Письмо → в Черновики для правки (если ещё существует в Исходящих).
    // Локальный черновик хранит содержимое редактора в bodyPlain — туда
    // кладётся HTML письма, иначе при правке терялось оформление.
    final row = await (db.select(db.emails)..where((e) => e.id.equals(outboxId))).getSingleOrNull();
    final files = _draftFilesOf(queued.firstOrNull?.payloadJson);
    String? filesJson;
    try {
      filesJson = await DraftFiles.store(outboxId, files);
    } catch (e) {
      AppLogger.warning('Отмена отправки: файлы письма не сохранены в черновик — $e');
    }
    await (db.update(db.emails)..where((e) => e.id.equals(outboxId))).write(
      EmailsCompanion(
        folderId: const Value('drafts'),
        folderName: const Value('Drafts'),
        isDraft: const Value(true),
        sentAt: const Value(null),
        bodyPlain: row?.bodyHtml == null ? const Value.absent() : Value(row!.bodyHtml),
        attachmentsJson: filesJson == null ? const Value.absent() : Value(filesJson),
        hasAttachments: filesJson == null ? const Value.absent() : Value(files.isNotEmpty),
      ),
    );
    await _replaceHeldDraft(outboxId, queued.firstOrNull);
    return true;
  }

  /// Файлы письма из записи очереди: приложенные — байтами, не скачанные
  /// вложения пересылки — ссылками.
  static List<DraftFile> _draftFilesOf(String? payloadJson) {
    if (payloadJson == null) return const [];
    try {
      final p = jsonDecode(payloadJson) as Map<String, dynamic>;
      return [
        for (final a in (p['attachments'] as List?) ?? const [])
          if (a is Map && a['base64'] is String)
            () {
              final bytes = base64Decode(a['base64'] as String);
              final ct = a['contentType'] as String?;
              return DraftFile.local(
                  name: (a['name'] as String?) ?? 'attachment',
                  size: bytes.length,
                  mimeType: ct,
                  bytes: bytes);
            }(),
        for (final r in _remoteFromPayload(p['remoteAttachments']))
          DraftFile.remote(
              name: r.name,
              size: 0,
              mimeType: r.contentType,
              accountId: r.accountId,
              emailId: r.emailId,
              attachmentId: r.attachmentId),
      ];
    } catch (e) {
      AppLogger.warning('Отмена отправки: файлы письма не прочитаны — $e');
      return const [];
    }
  }

  Future<int> _enqueue(
    String accountId,
    List<EmailAddress> to,
    List<EmailAddress> cc,
    List<EmailAddress> bcc,
    String subject,
    String bodyHtml,
    String? inReplyTo, {
    List<({String name, String? contentType, Uint8List bytes})> attachments = const [],
    String importance = 'Normal',
    String sensitivity = 'Normal',
    String operationType = 'send_email',
    String? errorMessage,
    List<RemoteAttachment> remoteAttachments = const [],
    EmailAddress? from,
    bool dsn = false,
    bool mdn = false,
    String? clientId,
  }) async {
    final db = _ref.read(databaseProvider);
    // Защита от разрастания БД при длительной работе без связи: вложения
    // лежат в очереди как base64. Без проверки несколько писем по 25 МБ
    // раздули бы базу на сотни мегабайт, а чтение payload могло исчерпать
    // память на слабом устройстве.
    final queued = await db.queuePayloadBytes();
    final incoming = attachments.fold<int>(0, (sum, a) => sum + (a.bytes.length * 4 ~/ 3));
    if (queued + incoming > maxQueueBytes) {
      AppLogger.warning(
          'Очередь офлайн-отправки переполнена: ${queued ~/ (1024 * 1024)} МБ + '
          '${incoming ~/ (1024 * 1024)} МБ > лимит ${maxQueueBytes ~/ (1024 * 1024)} МБ');
      throw StateError('offline_queue_full');
    }
    return db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
          accountId: accountId,
          operationType: operationType,
          targetId: 'outbox_${DateTime.now().millisecondsSinceEpoch}',
          errorMessage: Value(errorMessage),
          payloadJson: jsonEncode({
            'to': to.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'cc': cc.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'bcc': bcc.map((r) => {'email': r.email, 'displayName': r.displayName}).toList(),
            'subject': subject,
            'bodyHtml': bodyHtml,
            'inReplyTo': inReplyTo,
            'attachments': [for (final a in attachments) {'name': a.name, 'contentType': a.contentType, 'base64': base64Encode(a.bytes)}],
            if (remoteAttachments.isNotEmpty) 'remoteAttachments': _remoteToJson(remoteAttachments),
            'importance': importance,
            'sensitivity': sensitivity,
            if (from != null) 'from': {'email': from.email, 'displayName': from.displayName},
            if (dsn) 'dsn': true,
            if (mdn) 'mdn': true,
            if (clientId != null) 'clientId': clientId,
          }),
          priority: const Value(10),
          createdAt: DateTime.now(),
        ));
  }

  /// Скачать вложения с сервера (из кэша, если уже есть) — от имени ящика,
  /// где лежит исходное письмо. Любой сбой — исключение: отправлять письмо
  /// без части файлов молча нельзя.
  Future<List<({String name, String? contentType, Uint8List bytes})>> fetchRemoteAttachments(
      List<RemoteAttachment> refs) async {
    final out = <({String name, String? contentType, Uint8List bytes})>[];
    final cache = _ref.read(attachmentCacheProvider);
    final engine = _ref.read(mailEngineServiceProvider);
    for (final r in refs) {
      final account = _ref.read(accountsProvider).where((a) => a.id == r.accountId).firstOrNull;
      if (account == null) throw StateError('ящик письма с вложением «${r.name}» удалён');
      final key = MailEngineService.attachmentCacheKey(r.accountId, r.emailId, r.attachmentId);
      Uint8List? bytes;
      try {
        final path = await cache.get(key);
        if (path != null) bytes = await File(path).readAsBytes();
      } catch (_) {}
      if (bytes == null || bytes.isEmpty) {
        bytes = await engine.getAttachmentBytes(account, r.attachmentId, emailId: r.emailId);
        if (bytes.isEmpty) throw StateError('сервер вернул пустое вложение «${r.name}»');
        try {
          await cache.put(key, r.name, bytes);
        } catch (_) {}
      }
      out.add((name: r.name, contentType: r.contentType, bytes: bytes));
    }
    return out;
  }

  static List<Map<String, dynamic>> _remoteToJson(List<RemoteAttachment> refs) => [
        for (final r in refs)
          {
            'accountId': r.accountId,
            'emailId': r.emailId,
            'attachmentId': r.attachmentId,
            'name': r.name,
            'contentType': r.contentType,
          }
      ];

  static List<RemoteAttachment> _remoteFromPayload(Object? raw) => [
        for (final m in (raw as List?) ?? const [])
          (
            accountId: (m as Map)['accountId'] as String,
            emailId: m['emailId'] as String,
            attachmentId: m['attachmentId'] as String,
            name: (m['name'] as String?) ?? 'attachment',
            contentType: m['contentType'] as String?,
          ),
      ];

  /// Обработать очередь отправки (вызывается из sync_service, таймера
  /// «Отправляется через N с», восстановления сети). Отправка — работа,
  /// которую доделывают после сворачивания ([FinishInBackground], 2.7.5:
  /// с 2.7.4 все письма уходят через «Исходящие», и эта отправка не была
  /// отмечена — свёрнутое приложение замерзало посреди неё).
  Future<int> processQueue(String accountId) => FinishInBackground.guard(() => _processQueue(accountId));

  Future<int> _processQueue(String accountId) async {
    final db = _ref.read(databaseProvider);
    await _resolveStaleInflight(db, accountId);
    final ops = await (db.select(db.syncQueue)
          ..where((q) => q.accountId.equals(accountId))
          ..where((q) => q.operationType.equals('send_email') | q.operationType.equals('send_pending'))
          ..orderBy([(q) => OrderingTerm(expression: q.createdAt, mode: OrderingMode.asc)]))
        .get();

    if (ops.isEmpty) return 0;

    int sent = 0;
    final accounts = _ref.read(accountsProvider);
    // Аккаунт мог быть удалён (уведомление/очередь пережили удаление) —
    // firstWhere без orElse бросал бы StateError и ронял операцию.
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      // Ящик удалён — его письма к отправке отправить уже нечем (1.6.12).
      await (db.delete(db.syncQueue)..where((q) => q.accountId.equals(accountId))).go();
      AppLogger.info('Очередь отправки удалённого ящика $accountId очищена');
      return 0;
    }
    final transport = _ref.read(mailTransportFactoryProvider).forAccount(account);
    final now = DateTime.now();
    DateTime? nextWake;
    void wakeNoLaterThan(DateTime t) {
      if (nextWake == null || t.isBefore(nextWake!)) nextWake = t;
    }

    for (final op in ops) {
      try {
        // Шлюз организации не пропускал запросы из этой сети (18.11.2026):
        // ждём смены сети или конца паузы шлюза — повторы в паузе анти-бот
        // считает атакой. «Отправить снова» снимает ожидание
        // ([releaseGatewayHold]).
        final held = _gatewayHeld[op.id];
        if (held != null) {
          final left = me.EasEngine.wafPauseMinutesLeft(held);
          if (left > 0) {
            wakeNoLaterThan(now.add(Duration(minutes: left)));
            continue;
          }
          _gatewayHeld.remove(op.id);
        }
        // Пауза между попытками растёт: 30 с, 1, 2, 4, 8 мин, дальше — 10 мин.
        if (op.lastAttemptAt != null && op.retryCount > 0) {
          final nextAllowed = op.lastAttemptAt!.add(retryDelay(op.retryCount));
          if (now.isBefore(nextAllowed)) {
            wakeNoLaterThan(nextAllowed);
            continue; // ещё рано повторять — пропускаем до следующего прохода
          }
        }

        final payload = jsonDecode(op.payloadJson) as Map<String, dynamic>;

        // Отложенная отправка: если задано время и оно ещё не наступило — пропускаем.
        final scheduledStr = payload['scheduledAt'] as String?;
        if (scheduledStr != null) {
          final scheduledAt = DateTime.tryParse(scheduledStr);
          if (scheduledAt != null && now.isBefore(scheduledAt)) {
            wakeNoLaterThan(scheduledAt);
            continue; // ещё не время отправлять
          }
        }

        final to = (payload['to'] as List).map((m) =>
            EmailAddress(email: m['email'] as String, displayName: m['displayName'] as String?)).toList();
        final cc = (payload['cc'] as List?)?.map((m) =>
            EmailAddress(email: m['email'] as String, displayName: m['displayName'] as String?)).toList() ?? [];
        final bcc = (payload['bcc'] as List?)?.map((m) =>
            EmailAddress(email: m['email'] as String, displayName: m['displayName'] as String?)).toList() ?? [];
        final subject = payload['subject'] as String;
        // Картинки цитаты, которых при «Отправить» не было на телефоне
        // (25.11.2026: окно письма закрывается сразу) — докачиваются здесь.
        final bodyHtml = await _embedQuoteImages(payload['quoteImages'], payload['bodyHtml'] as String);
        final inReplyTo = payload['inReplyTo'] as String?;
        final attachments = (((payload['attachments'] as List?) ?? []).map((a) => (
              name: a['name'] as String,
              contentType: a['contentType'] as String?,
              bytes: base64Decode(a['base64'] as String),
            ))).toList();
        final importance = payload['importance'] as String? ?? 'Normal';
        final sensitivity = payload['sensitivity'] as String? ?? 'Normal';
        final fromMap = payload['from'] as Map<String, dynamic>?;
        final from = fromMap == null
            ? null
            : EmailAddress(email: fromMap['email'] as String, displayName: fromMap['displayName'] as String?);

        // Файлы пересылаемого письма, не скачанные при отправке (1.6.18):
        // качаем до захвата записи — сбой здесь не значит, что письмо ушло.
        final remote = _remoteFromPayload(payload['remoteAttachments']);
        if (remote.isNotEmpty) {
          try {
            attachments.addAll(await fetchRemoteAttachments(remote));
          } catch (e) {
            // Сообщение без «timed out»: это не таймаут отправки, а сбой
            // скачивания — повтор безопасен (письмо ещё не отправлялось).
            throw StateError('network: вложения пересылаемого письма не скачаны (${e.runtimeType})');
          }
        }

        // Отправка через единый транспорт (EWS/EAS/IMAP)
        // Окно риска: если приложение будет закрыто МЕЖДУ отправкой и
        // удалением записи, письмо уйдёт повторно (получатель увидит дубликат).
        // Полностью это решается только идемпотентностью на стороне сервера,
        // поэтому здесь мы делаем ситуацию хотя бы диагностируемой: в журнале
        // видно, что отправка началась, но не завершилась.
        // Захват записи: отправляет только тот, кто атомарно перевёл её в
        // «отправляется». Очередь разбирают несколько участников — синхронизация,
        // таймер отмены отправки, восстановление сети и фоновый процесс
        // WorkManager (отдельный изолят со своим подключением к БД). Раньше все
        // они могли взять одну запись, и письмо уходило дважды. SQLite
        // сериализует записи между соединениями, поэтому захват работает и
        // между изолятами.
        final claimed = await (db.update(db.syncQueue)
              ..where((q) =>
                  q.id.equals(op.id) &
                  q.operationType.isIn(const ['send_email', 'send_pending'])))
            .write(SyncQueueCompanion(
          operationType: const Value(_inflight),
          lastAttemptAt: Value(DateTime.now()),
        ));
        if (claimed != 1) continue; // уже отправляет другой участник (или отменено)

        AppLogger.info('Отправка из очереди: начало (queueId=${op.id}, $subject)');
        // ClientId из id записи: повтор той же записи EAS-сервер опознает
        // (Status 118) и не отправит письмо второй раз.
        await transport.send(account, to: to, cc: cc, bcc: bcc,
            subject: subject, bodyHtml: bodyHtml, inReplyTo: inReplyTo, attachments: attachments,
            importance: importance, sensitivity: sensitivity,
            clientId: (payload['clientId'] as String?) ?? 'q${op.id}', from: from,
            requestDeliveryReport: payload['dsn'] == true,
            requestReadReceipt: payload['mdn'] == true);

        await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
        // Для undo-send targetId = id письма в Исходящих — убираем его после
        // отправки (для обычных outbox_/scheduled_ id совпадения нет — no-op).
        await (db.delete(db.emails)..where((e) => e.id.equals(op.targetId))).go();
        sent++;
        AppLogger.info('Письмо из очереди отправлено: $subject');
        await _dropSentDraft(payload['dropDraft']);
        unawaited(_showSentInConversation(account,
            to: to, cc: cc, subject: subject, html: bodyHtml, inReplyTo: inReplyTo, hasAttachments: attachments.isNotEmpty));
        _afterSent(account);
      } catch (e) {
        // Таймаут ожидания ответа: сервер мог письмо уже принять. У EAS
        // повтор безопасен (тот же ClientId), у EWS и SMTP — нет: повтор дал
        // бы получателю дубль. Такое письмо — в «не отправлено» с уведомлением
        // «проверьте Отправленные», как и при отправке без очереди.
        if (_isUncertainTimeout(e) && !account.usesEas) {
          AppLogger.warning('Отправка из очереди: таймаут без подтверждения — не повторяем (queueId=${op.id})');
          await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id)))
              .write(SyncQueueCompanion(
            operationType: const Value('send_failed'),
            lastAttemptAt: Value(DateTime.now()),
            errorMessage: Value(_l10n().tr('offlineErrTimeout')),
          ));
          await _notifyUncertain(op.accountId, op.targetId, op.payloadJson);
          continue;
        }
        // Не принято по размеру — повторять бессмысленно: сразу «не
        // отправлено» с понятной причиной (раньше — три попытки и
        // «EAS SendMail: HTTP 403» в списке очереди).
        final tooLarge = tooLargeOf(e);
        if (tooLarge != null) {
          AppLogger.warning('Отправка из очереди: письмо не принято по размеру — не повторяем (queueId=${op.id}): $e');
          final limit = tooLarge.limitBytes;
          if (limit != null) await _ref.read(attachmentLimitProvider).setLimit(op.accountId, limit);
          await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id))).write(SyncQueueCompanion(
            operationType: const Value('send_failed'),
            retryCount: Value(op.retryCount + 1),
            lastAttemptAt: Value(DateTime.now()),
            errorMessage: Value(tooLargeText(_l10n(), tooLarge)),
          ));
          await _notifyNotSent(op.accountId, op.targetId, _subjectOf(op.payloadJson), queueId: op.id);
          continue;
        }
        // Шлюз не пропустил запрос из этой сети (VPN, чужой адрес): дело не
        // в письме — оно остаётся в очереди и уйдёт после смены сети или
        // паузы шлюза, без «Отправить снова» (18.11.2026: пять нажатий).
        if (e is me.GatewayBlocked) {
          AppLogger.warning('Отправка из очереди: шлюз организации не пропустил запрос из этой сети — '
              'повтор после смены сети или паузы шлюза (queueId=${op.id})');
          _gatewayHeld[op.id] = e.host;
          await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id))).write(SyncQueueCompanion(
            operationType: const Value('send_email'),
            retryCount: Value(op.retryCount + 1),
            lastAttemptAt: Value(DateTime.now()),
            errorMessage: Value(_l10n().tr('offlineErrGateway')),
          ));
          // Около двух часов в той же сети (8 попыток раз в паузу шлюза) —
          // «не отправлено» с уведомлением, как после других сбоев.
          if (op.retryCount + 1 >= gatewayMaxRetries) {
            _gatewayHeld.remove(op.id);
            await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id)))
                .write(const SyncQueueCompanion(operationType: Value('send_failed')));
            AppLogger.warning('Письмо помечено как НЕ доставленное: шлюз не пропускал ${op.retryCount + 1} попыток');
            await _notifyNotSent(op.accountId, op.targetId, _subjectOf(op.payloadJson), queueId: op.id);
            continue;
          }
          final left = me.EasEngine.wafPauseMinutesLeft(e.host);
          wakeNoLaterThan(DateTime.now().add(Duration(minutes: left > 0 ? left : 15)));
          continue;
        }
        final isTransient = _isTransientError('$e');
        AppLogger.error('Отправка из очереди не удалась (${isTransient ? "временная" : "постоянная"}): $e');
        // Возвращаем запись в очередь (она могла быть захвачена выше).
        await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id)))
            .write(SyncQueueCompanion(
          operationType: const Value('send_email'),
          retryCount: Value(op.retryCount + 1),
          lastAttemptAt: Value(DateTime.now()),
          errorMessage: Value('$e'),
        ));

        // Постоянные ошибки (4xx, кроме 408/429) — три попытки. Временные
        // (сеть, таймаут, 5xx) — сутки (25.11.2026, мобильный интернет: сервер
        // по нескольку часов не пускал, а через 10 попыток за 20 минут
        // письмо считалось не отправленным и уходило только вручную).
        final giveUp = isTransient
            ? DateTime.now().difference(retryWindowStart(op)) >= transientRetryWindow
            : op.retryCount + 1 >= 3;
        if (!giveUp) wakeNoLaterThan(DateTime.now().add(retryDelay(op.retryCount + 1)));
        if (giveUp) {
          await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id)))
              .write(const SyncQueueCompanion(operationType: Value('send_failed')));
          AppLogger.warning('Письмо помечено как НЕ доставленное после ${op.retryCount + 1} попыток: ${op.targetId}');
          // Сообщаем пользователю: письмо помечалось недоставленным только в
          // БД, и человек продолжал считать его отправленным. Для деловой
          // переписки это недопустимо — уведомляем явно.
          // Тему берём из payload заново: переменная subject объявлена внутри
          // try и в catch-блоке недоступна.
          await _notifyNotSent(op.accountId, op.targetId, _subjectOf(op.payloadJson), queueId: op.id);
        }
      }
    }

    if (nextWake != null) _wakeAt(accountId, nextWake!);
    return sent;
  }

  static const _inflight = 'send_inflight';

  /// Сколько повторять отправку при временных сбоях (сеть, таймаут, 5xx).
  static const transientRetryWindow = Duration(hours: 24);

  /// Пауза перед попыткой номер [retry] (считая с 1): 30 с, 1, 2, 4, 8 мин,
  /// дальше — 10 мин. Повторы ещё и при смене сети и каждой синхронизации.
  static Duration retryDelay(int retry) {
    if (retry <= 0) return Duration.zero;
    final secs = 30 * (1 << (retry - 1).clamp(0, 5));
    return Duration(seconds: secs > 600 ? 600 : secs);
  }

  /// Начало окна повторов: время постановки в очередь, у отложенного
  /// письма — назначенное время, после «Отправить сейчас» — это нажатие.
  @visibleForTesting
  static DateTime retryWindowStart(SyncQueueData op) {
    var start = op.createdAt;
    try {
      final p = jsonDecode(op.payloadJson) as Map;
      for (final k in const ['scheduledAt', 'retryFrom']) {
        final at = DateTime.tryParse(p[k] as String? ?? '');
        if (at != null && at.isAfter(start)) start = at;
      }
    } catch (_) {}
    return start;
  }

  /// Письмо ушло — серверный черновик, из которого брались не скачанные
  /// файлы, больше не нужен (на телефоне его строку убрало окно письма).
  /// Без связи удаление встаёт в очередь действий.
  Future<void> _dropSentDraft(Object? ref) async {
    if (ref is! Map) return;
    final accountId = ref['accountId'], id = ref['id'], folderId = ref['folderId'];
    if (accountId is! String || id is! String || folderId is! String) return;
    final account = _ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (account == null) return;
    try {
      await _ref.read(emailActionsProvider).delete(account, id, folderId, hard: true);
    } catch (e) {
      AppLogger.warning('Отправка: черновик на сервере не удалён — $e');
    }
  }

  /// Письмо из «Исходящих» вернулось в «Черновики» ([draftId]): серверный
  /// черновик, из которого оно брало файлы, заменится им при выгрузке —
  /// без второй копии в «Черновиках».
  Future<void> _replaceHeldDraft(String draftId, SyncQueueData? op) async {
    if (op == null) return;
    try {
      final ref = (jsonDecode(op.payloadJson) as Map)['dropDraft'];
      if (ref is! Map || ref['accountId'] != op.accountId) return;
      final id = ref['id'], folderId = ref['folderId'];
      if (id is! String || folderId is! String) return;
      await _ref.read(draftSyncServiceProvider).rememberReplace(draftId, (id: id, folderId: folderId));
    } catch (e) {
      AppLogger.debug('Черновик из «Исходящих»: связь с серверной копией не записана — $e');
    }
  }

  /// Картинки исходного письма в цитате (cid:) — в письмо перед отправкой
  /// ([ref] — {accountId, emailId} исходного письма). Исходного письма нет
  /// или картинку не скачать — ссылка остаётся (письмо уходит как раньше).
  Future<String> _embedQuoteImages(Object? ref, String html) async {
    if (ref is! Map || !html.toLowerCase().contains('cid:')) return html;
    final accountId = ref['accountId'];
    final emailId = ref['emailId'];
    if (accountId is! String || emailId is! String) return html;
    try {
      final row = await _ref.read(databaseProvider).getEmailById(emailId, accountId: accountId);
      if (row == null) return html;
      return await _ref
          .read(mailOpenCacheProvider)
          .embedInlineImages(accountId, emailModelFromRow(row), html)
          .timeout(const Duration(minutes: 2));
    } catch (e) {
      AppLogger.warning('Отправка: картинки цитаты не вложены — $e');
      return html;
    }
  }

  /// Запись, «отправляемая» дольше 15 минут: процесс прервали посреди
  /// отправки (закрыли приложение, убила система). Ушло письмо или нет —
  /// неизвестно, а повтор вслепую рискует дублем делового письма. Переводим
  /// в «не отправлено» с пояснением: пользователь проверит «Отправленные» и
  /// при необходимости отправит повторно.
  Future<void> _resolveStaleInflight(AppDatabase db, String accountId) async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 15));
    final stale = await (db.select(db.syncQueue)
          ..where((q) =>
              q.accountId.equals(accountId) &
              q.operationType.equals(_inflight) &
              q.lastAttemptAt.isSmallerThanValue(cutoff)))
        .get();
    for (final op in stale) {
      await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id))).write(SyncQueueCompanion(
        operationType: const Value('send_failed'),
        errorMessage: Value(_l10n().tr('offlineErrInterrupted')),
      ));
      AppLogger.warning('Отправка прервана, статус неизвестен: queueId=${op.id}');
      await _notifyUncertain(op.accountId, op.targetId, op.payloadJson);
    }
  }

  Future<void> _notifyUncertain(String accountId, String targetId, String payloadJson) async {
    var subject = '';
    try {
      subject = (jsonDecode(payloadJson) as Map<String, dynamic>)['subject'] as String? ?? '';
    } catch (_) {}
    try {
      final l10n = _l10n();
      await _ref.read(notificationServiceProvider).showReminderNotification(
            id: targetId.hashCode & 0x7FFFFFFF,
            title: l10n.tr('offlineCheckSentTitle'),
            body: subject.isEmpty
                ? l10n.tr('offlineUnknownIfSent')
                : l10n.tr('offlineUnknownIfSentSubject').replaceAll('{subject}', subject),
            payload: 'outbox:$accountId:$targetId',
          );
    } catch (_) {}
  }

  /// Уведомление «Письмо не отправлено» (нажатие открывает список очереди).
  Future<void> _notifyNotSent(String accountId, String targetId, String subject, {int? queueId}) async {
    try {
      final l10n = _l10n();
      await _ref.read(notificationServiceProvider).showReminderNotification(
            id: (queueId ?? targetId).hashCode & 0x7FFFFFFF,
            title: l10n.tr('offlineNotSentTitle'),
            body: subject.isEmpty ? l10n.tr('offlineNotDelivered') : subject,
            payload: 'outbox:$accountId:$targetId',
          );
    } catch (e) {
      AppLogger.warning('Уведомление о недоставке не показано: $e');
    }
  }

  static String _subjectOf(String payloadJson) {
    try {
      return (jsonDecode(payloadJson) as Map<String, dynamic>)['subject'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Письмо не принято по размеру? Шлюз перед Exchange не пропустил большое
  /// письмо или сервер назвал лимит в тексте ошибки. null — другая ошибка.
  static MessageTooLargeException? tooLargeOf(Object e) {
    if (e is MessageTooLargeException) return e;
    if (e is me.GatewaySizeRejected) return MessageTooLargeException(sizeBytes: e.bytes, gateway: true);
    final limit = AttachmentLimitStore.parseLimitFromError('$e');
    return limit == null ? null : MessageTooLargeException(limitBytes: limit);
  }

  /// Причина для человека: что не пропустили и что сделать.
  static String tooLargeText(AppLocalizations l10n, MessageTooLargeException e) {
    String mb(int b) => (b / 1048576).toStringAsFixed(1).replaceAll('.', l10n.localeCode == 'en' ? '.' : ',');
    if (e.gateway) {
      return l10n.tr('sendTooLargeGateway').replaceAll('{mb}', e.sizeBytes == null ? '?' : mb(e.sizeBytes!));
    }
    return l10n.tr('sendTooLargeServer').replaceAll('{mb}', e.limitBytes == null ? '?' : mb(e.limitBytes!));
  }

  /// «Отменить» в «Исходящих» (21.11.2026): письмо больше не отправляется и
  /// возвращается в «Черновики» — с адресатами, текстом и файлами. Письмо,
  /// которое уже отправляется, отменить нельзя — null.
  /// Возвращает id черновика.
  Future<String?> cancelToDraft(SyncQueueData op) async {
    // Отсчёт перед отправкой: письмо уже лежит в «Исходящих» строкой
    // базы — она и становится черновиком.
    if (op.targetId.startsWith('undosend_') && op.operationType != 'send_failed') {
      return await cancelUndoSend(op.targetId) ? op.targetId : null;
    }
    _undoTimers.remove(op.targetId)?.cancel();
    final db = _ref.read(databaseProvider);
    // Сначала убрать из очереди — только если отправка ещё не началась.
    final removed = await (db.delete(db.syncQueue)
          ..where((q) => q.id.equals(op.id) & q.operationType.isIn(const ['send_email', 'send_pending', 'send_failed'])))
        .go();
    if (removed == 0) return null;
    final id = await _queuedToDraft(op);
    if (id == null) {
      // Черновик не записался — письмо не теряем: обратно в «Исходящие»
      // неотправленным, чтобы его было видно.
      await db.into(db.syncQueue).insert(SyncQueueCompanion.insert(
            accountId: op.accountId,
            operationType: 'send_failed',
            targetId: op.targetId,
            payloadJson: op.payloadJson,
            createdAt: op.createdAt,
            errorMessage: Value(op.errorMessage),
          ));
      return null;
    }
    await (db.delete(db.emails)..where((e) => e.id.equals(op.targetId))).go();
    return id;
  }

  /// «В черновики» для неотправленного письма (1.7.2+114): письмо из
  /// очереди становится черновиком того же ящика — с адресатами, текстом и
  /// файлами; там его можно поправить (уменьшить фото) и отправить снова.
  /// Возвращает id черновика или null, если не вышло.
  Future<String?> failedToDraft(SyncQueueData op) async {
    final db = _ref.read(databaseProvider);
    final id = await _queuedToDraft(op);
    if (id == null) return null;
    await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
    await (db.delete(db.emails)..where((e) => e.id.equals(op.targetId))).go();
    AppLogger.info('Неотправленное письмо — в черновики: queueId=${op.id} → $id');
    return id;
  }

  /// Черновик из записи очереди; не вышло — null.
  Future<String?> _queuedToDraft(SyncQueueData op) async {
    try {
      final p = jsonDecode(op.payloadJson) as Map<String, dynamic>;
      List<Map<String, String>> rcpt(Object? v) => [
            for (final r in (v as List?) ?? const [])
              if (r is Map && r['email'] is String)
                {
                  'email': r['email'] as String,
                  if (r['displayName'] is String && (r['displayName'] as String).isNotEmpty)
                    'name': r['displayName'] as String,
                },
          ];
      final id = 'draft-${const Uuid().v4()}';
      final draft = DraftData(
        id: id,
        accountId: op.accountId,
        to: rcpt(p['to']),
        cc: rcpt(p['cc']),
        bcc: rcpt(p['bcc']),
        subject: p['subject'] as String? ?? '',
        body: p['bodyHtml'] as String? ?? '',
        sensitivity: p['sensitivity'] as String?,
        savedAt: DateTime.now(),
        files: _draftFilesOf(op.payloadJson),
      );
      if (!await _ref.read(draftAutosaveProvider).saveStandalone(draft)) return null;
      await _replaceHeldDraft(id, op);
      return id;
    } catch (e) {
      AppLogger.warning('Неотправленное письмо в черновики не перенесено: $e');
      return null;
    }
  }

  /// Ошибка «ответ не дождались»: письмо могло уже уйти на сервере.
  /// Сбой подключения или входа SMTP ([me.SmtpNotSentException]) — не
  /// «неясный» тайм-аут: письмо до сервера не дошло, повтор безопасен.
  static bool _isUncertainTimeout(Object e) =>
      e is! me.SmtpNotSentException && (e is TimeoutException || '$e'.toLowerCase().contains('timed out'));

  /// Временная ли ошибка (стоит повторять) — 502/503/таймаут/нет сети.
  bool _isTransientError(String error) {
    final e = error.toLowerCase();
    return e.contains('502') || e.contains('503') || e.contains('504') ||
        e.contains('429') || e.contains('408') ||
        e.contains('timeout') || e.contains('timed out') ||
        e.contains('socket') || e.contains('connection') ||
        e.contains('network') || e.contains('bad gateway') ||
        e.contains('unavailable') ||
        // Нет ответа сервера (обрыв VPN, Wi-Fi): «HTTP 0» у ActiveSync.
        e.contains('http 0');
  }

  /// Количество писем в очереди отправки
  Future<int> pendingCount(String accountId) async {
    final db = _ref.read(databaseProvider);
    final result = await db.customSelect(
      'SELECT COUNT(*) as c FROM sync_queue WHERE account_id = ? AND operation_type = ?',
      variables: [Variable.withString(accountId), Variable.withString('send_email')],
    ).getSingle();
    return result.data['c'] as int? ?? 0;
  }
}

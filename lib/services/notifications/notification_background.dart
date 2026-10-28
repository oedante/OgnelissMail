// lib/services/notifications/notification_background.dart
// Кнопки уведомления без открытия приложения («Прочитано», «Удалить», умные
// ответы). Android доставляет их в отдельный фоновый изолят
// (ActionBroadcastReceiver плагина flutter_local_notifications) — и когда
// приложение свёрнуто, и когда процесс выгружен.
//
// Раньше обработчик только писал в журнал: письмо не помечалось прочитанным
// и не удалялось. Теперь действие выполняется сразу в фоновом изоляте (тот же
// набор сервисов, что у фоновой синхронизации), а если не получилось (нет
// сети, сбой БД) — ставится в очередь и выполняется при следующем открытии.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../background/background_service.dart';
import 'notification_action_handler.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  final id = response.actionId;
  if (id == null || id.isEmpty) return;
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  AppLogger.setTag('фон');
  await AppLogger.init();
  AppLogger.info('Действие уведомления в фоне: $id');
  // Ответы уходят через очередь отправки (sendOrQueue) — у неё своя доставка
  // без сети. Повтор ответа после таймаута мог бы отправить его дважды,
  // поэтому ответы в очередь действий не ставятся.
  final isReply = id == 'quick_reply' || id.startsWith('smart_reply_');
  var ok = false;
  try {
    await runInBackgroundContainer((c) async {
      ok = await c
          .read(notificationActionHandlerProvider)
          .handleAction(id, response.payload, response.input)
          .timeout(const Duration(seconds: 50));
    });
  } on TimeoutException {
    AppLogger.warning('Действие уведомления $id: истекло время');
    if (isReply) return;
  } catch (e) {
    AppLogger.warning('Действие уведомления $id: $e');
  }
  if (ok) {
    AppLogger.info('Действие уведомления выполнено в фоне: $id');
    AppLogger.flushNow();
    return;
  }
  // Пометка прочитанным, удаление, флаг — повтор безопасен.
  AppLogger.info('Действие уведомления $id отложено до запуска приложения');
  await _enqueue(id, response.payload, response.input);
  AppLogger.flushNow();
}

Future<void> _enqueue(String id, String? payload, String? input) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(NotificationService.pendingActionsKey) ?? <String>[];
    list.add(jsonEncode({'a': id, 'p': payload, 'i': input}));
    // Не копим бесконечно, если приложение долго не открывают.
    while (list.length > 50) {
      list.removeAt(0);
    }
    await prefs.setStringList(NotificationService.pendingActionsKey, list);
  } catch (_) {}
}

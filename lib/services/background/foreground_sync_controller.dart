import 'dart:async';
import '../sync/sync_schedule.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart';

final foregroundSyncControllerProvider = Provider<ForegroundSyncController>((ref) {
  return ForegroundSyncController();
});

/// Управляет Android foreground-сервисом, который удерживает процесс приложения
/// живым в свёрнутом состоянии — чтобы работали существующие Dart-таймеры
/// синхронизации (BackgroundService) и IMAP IDLE в главном изоляте.
///
/// Только Android. На iOS ОС не позволяет держать приложение в фоне (см. ROADMAP:
/// нужен BGTaskScheduler/APNs). На десктопе свёрнутое приложение и так живёт.
class ForegroundSyncController {
  static const _channel = MethodChannel('ogneliss/foreground_sync');

  bool _running = false;
  bool get isRunning => _running;

  bool _handlerSet = false;

  /// Обработчик «пульса» от нативного сервиса: будильник ОС будит процесс
  /// примерно раз в 10 минут (и в глубоком сне), держит процессор не дольше
  /// двух минут и ждёт ответа. Здесь — сторож push и плановая проверка.
  void setHeartbeatHandler(Future<void> Function() onHeartbeat) {
    if (!isSupported) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'heartbeat') {
        final started = DateTime.now();
        unawaited(_checkLate(call.arguments));
        try {
          await onHeartbeat().timeout(const Duration(seconds: 100));
        } catch (e) {
          AppLogger.warning('Пульс фоновой работы: $e');
        }
        unawaited(_checkFrozen(started));
        return true;
      }
      return null;
    });
  }

  bool get hasHeartbeatHandler => _handlerSet;

  /// Ключи «система замораживает приложение» (читает экран «Разрешения»).
  static const frozenCountKey = 'bg_frozen_count';
  static const frozenLastKey = 'bg_frozen_last';
  static const frozenMinutesKey = 'bg_frozen_minutes';

  /// Пульс ограничен 100 секундами. Если он закончился через 5+ минут —
  /// процесс всё это время стоял: оболочка производителя (MagicOS, ColorOS,
  /// MIUI…) замораживает свёрнутые приложения даже со службой и блокировкой
  /// сна. Запросы к серверу тогда «висят» до следующего пробуждения, и
  /// уведомления опаздывают (журнал Honor, 10.10.2026). Сам код это не
  /// исправит — нужно разрешение в настройках телефона, поэтому факт
  /// записывается и показывается на экране «Разрешения».
  Future<void> _checkFrozen(DateTime started) async {
    final took = DateTime.now().difference(started);
    if (took < const Duration(minutes: 5)) return;
    AppLogger.warning('Фон: процесс был заморожен системой ~${took.inMinutes} мин '
        '(пульс ограничен 100 с) — уведомления в это время не приходят');
    await _noteFrozen(took.inMinutes);
  }

  /// Пульс опоздал (1.6.43). Журнал Honor 19.10.2026: со службой и точными
  /// будильниками приложение молчало 84 и 89 минут — ни пульса, ни
  /// WorkManager; MagicOS останавливала процесс целиком. Длительность пульса
  /// это не ловила (пульса просто не было), и строка-подсказка в ленте
  /// («Телефон может останавливать приложение…») не появлялась. Точный будильник ОС опаздывает не больше
  /// чем на ~15 минут даже в глубоком сне (Doze); на 20+ — значит, его
  /// придержала оболочка производителя.
  Future<void> _checkLate(Object? args) async {
    final minutes = lateMinutesIfFrozen(args);
    if (minutes == null) return;
    AppLogger.warning('Фон: пульс опоздал на $minutes мин (точный будильник) — система или оболочка '
        'производителя останавливала приложение, уведомления в это время не приходили');
    // Без пульса приложение стояло с прошлого (за 10 мин до ожидаемого).
    await _noteFrozen(minutes + 10);
  }

  /// Опоздание пульса в минутах, если оно означает заморозку (точный
  /// будильник, 20+ минут); иначе null. [args] — аргументы `heartbeat` из
  /// SyncHeartbeatReceiver: {lateMs, exact}.
  @visibleForTesting
  static int? lateMinutesIfFrozen(Object? args) {
    if (args is! Map) return null;
    final lateMs = args['lateMs'];
    if (args['exact'] != true || lateMs is! int || lateMs < 20 * 60 * 1000) return null;
    return lateMs ~/ 60000;
  }

  static Future<void> _noteFrozen(int minutes) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(frozenCountKey, (p.getInt(frozenCountKey) ?? 0) + 1);
      await p.setInt(frozenLastKey, DateTime.now().millisecondsSinceEpoch);
      await p.setInt(frozenMinutesKey, minutes);
    } catch (_) {}
  }

  /// Замораживание замечено за последние 3 дня.
  static bool frozenRecently(SharedPreferences p) {
    final last = p.getInt(frozenLastKey);
    if (last == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < const Duration(days: 3);
  }

  /// Сбросить отметку (пользователь изменил настройки телефона).
  static Future<void> clearFrozen(SharedPreferences p) async {
    await p.remove(frozenCountKey);
    await p.remove(frozenLastKey);
    await p.remove(frozenMinutesKey);
  }

  /// Открыть настройки канала уведомления фоновой работы (скрыть его).
  Future<void> openNotificationSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (e) {
      AppLogger.warning('Настройки уведомления фоновой работы: $e');
    }
  }

  /// Поддерживается ли режим на этой платформе (нативный канал + Android).
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Закрыла ли система приложению сеть (1.6.43): Doze, ограничения фона
  /// Android, «оптимизатор» производителя. Свёрнутому приложению без службы
  /// это обычное дело — сеть ему дают только на время фоновой задачи.
  Future<bool> networkBlocked() async {
    if (!isSupported) return false;
    try {
      return (await _channel.invokeMethod<bool>('networkBlocked')) == true;
    } catch (_) {
      return false;
    }
  }

  /// Реально ли подключён нативный сервис (иначе — тихо ничего не делаем).
  Future<bool> isChannelReady() async {
    if (!isSupported) return false;
    try {
      return (await _channel.invokeMethod<bool>('ping')) == true;
    } catch (_) {
      return false;
    }
  }

  /// Запустить foreground-сервис (показывает постоянное уведомление).
  ///
  /// Повторный вызов безвреден и нужен: сервис мог остановиться без ведома
  /// Dart (Android 15 ограничивает dataSync 6 часами в фоне за сутки и
  /// останавливает сервис через onTimeout; при возврате в приложение лимит
  /// сбрасывается, и сервис надо поднять снова).
  Future<void> start() async {
    if (!isSupported) return;
    try {
      final wasRunning = _running;
      await _channel.invokeMethod('start');
      _running = true;
      if (!wasRunning) AppLogger.info('Foreground sync service: запущен');
      // Система может тихо отказать: запуск службы из фона запрещён на
      // Android 12+, у dataSync исчерпан суточный лимит (Android 15+),
      // оболочка производителя не даёт работать в фоне. Проверяем.
      unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
        try {
          final ok = await _channel.invokeMethod<bool>('isRunning');
          if (ok == false) {
            _running = false;
            AppLogger.warning('Фоновая служба не запустилась (система отказала: запуск из фона '
                'запрещён, лимит Android 15 или ограничение производителя) — '
                'почту в фоне проверяет только WorkManager');
          }
        } catch (_) {}
      }));
    } on MissingPluginException {
      // Нативная часть не встроена — молча пропускаем.
    } catch (e) {
      AppLogger.warning('Foreground sync service start: $e');
    }
  }

  /// Остановить foreground-сервис.
  Future<void> stop() async {
    if (!isSupported || !_running) return;
    try {
      await _channel.invokeMethod('stop');
      _running = false;
      AppLogger.info('Foreground sync service: остановлен');
    } on MissingPluginException {
      _running = false;
    } catch (e) {
      AppLogger.warning('Foreground sync service stop: $e');
    }
  }
}


/// Нужен ли фоновый сервис (и его уведомление). Только для мгновенной
/// доставки: если ни один ящик не в режиме «Мгновенно», почту по интервалу
/// проверяет WorkManager без сервиса и без строки в шторке. Раньше сервис
/// запускался при любых ящиках, если включена «Работа в фоне».
bool keepAliveNeeded({required bool keepAliveSetting, required int globalInterval,
    required Iterable<AccountModel> accounts}) {
  if (!keepAliveSetting || globalInterval < 0) return false;
  // «По расписанию» — служба весь день: в начале рабочих часов push
  // поднимает её пульс (запустить службу из фона Android 12+ не даёт).
  return accounts.any((a) => a.isActive && a.authFailedAt == null && SyncSchedule.needsService(a));
}

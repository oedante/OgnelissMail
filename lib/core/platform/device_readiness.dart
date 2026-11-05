// lib/core/platform/device_readiness.dart
// Что нужно ЭТОМУ устройству, чтобы о письмах оно сообщало вовремя (1.12.x,
// просьба владельца 05.11.2026: «Пользователь не должен думать, что ему
// включить и настроить»). Один расчёт для шага первой настройки (после
// входа в первый ящик), экрана «Разрешения» и журнала — по состоянию
// устройства (PlatformDiagnostics) и способу сигналов сервера
// (PushWakeService.signalChannel). Всё в порядке — шагов нет, и ничего не
// показывается.

import 'platform_diagnostics.dart';

/// Как свёрнутое приложение узнаёт о новых письмах (кроме своих соединений
/// push, которые живут, пока жив процесс).
enum SignalChannel {
  /// Android: сигналы сервера через Google (FCM).
  google,

  /// iPhone: сигналы сервера через Apple (APNs).
  apple,

  /// Android без сервисов Google: через распространитель UnifiedPush.
  unifiedPush,

  /// Распространителей UnifiedPush несколько — выбирает человек.
  chooseDistributor,

  /// Ни сервисов Google, ни распространителя: только проверки по
  /// расписанию (WorkManager — раз в 15 минут и реже в глубоком сне).
  periodicOnly,

  /// Сигналы выключены человеком или их нет в этой сборке.
  off,
}

/// Чего не хватает устройству — по порядку важности.
enum ReadyStep {
  /// Разрешение на уведомления (Android 13+, iPhone).
  notifications,

  /// Android: категория «Почта» выключена в настройках уведомлений.
  mailChannel,

  /// Android: «Батарея → Ограничено» — в фоне приложение не работает вовсе.
  backgroundRestricted,

  /// Android: приложение не исключено из оптимизации батареи.
  battery,

  /// Android: «оптимизатор» оболочки производителя (автозапуск, работа в фоне).
  oemAutostart,

  /// Android 12+: точные будильники для напоминаний о встречах.
  exactAlarms,

  /// iPhone: «Обновление контента» выключено.
  iosRefresh,

  /// Android: распространителей UnifiedPush несколько — выбрать один.
  chooseSignals,

  /// Android без Google и распространителя: только сведения — почта
  /// проверяется по расписанию, для мгновенных сигналов нужен, например, ntfy.
  periodicOnly,
}

class DeviceReadiness {
  DeviceReadiness._();

  /// Шаги для этого устройства. [diag] — PlatformDiagnostics.collect;
  /// пустой (компьютер, фоновый изолят) — шагов нет.
  static List<ReadyStep> steps(
    Map<String, dynamic> diag, {
    required bool ios,
    SignalChannel signal = SignalChannel.off,
  }) {
    if (diag.isEmpty) return const [];
    final issues = PlatformDiagnostics.issues(diag, ios: ios);
    final out = <ReadyStep>[
      if (issues.contains(BgIssue.notificationsOff)) ReadyStep.notifications,
      if (issues.contains(BgIssue.mailChannelOff)) ReadyStep.mailChannel,
      if (issues.contains(BgIssue.backgroundRestricted)) ReadyStep.backgroundRestricted,
      if (issues.contains(BgIssue.batteryOptimized)) ReadyStep.battery,
      if (issues.contains(BgIssue.oemManager)) ReadyStep.oemAutostart,
      if (issues.contains(BgIssue.exactAlarmsOff)) ReadyStep.exactAlarms,
      if (issues.contains(BgIssue.iosRefreshOff)) ReadyStep.iosRefresh,
      if (!ios && signal == SignalChannel.chooseDistributor) ReadyStep.chooseSignals,
      if (!ios && signal == SignalChannel.periodicOnly) ReadyStep.periodicOnly,
    ];
    return out;
  }

  /// Есть ли что сделать человеку. «Только по расписанию» — сведения, сами
  /// по себе не повод показывать шаг настройки.
  static bool needsAction(List<ReadyStep> steps) => steps.any((s) => s != ReadyStep.periodicOnly);

  /// Способ сигналов на Android по тому, что есть на телефоне.
  /// [transportFcm] — выбран (или выбран сам) Google; [distributor] —
  /// выбранный распространитель UnifiedPush; [distributors] — сколько их
  /// установлено.
  static SignalChannel androidSignal({
    required bool enabled,
    required bool transportFcm,
    required String? distributor,
    required int distributors,
  }) {
    if (!enabled) return SignalChannel.off;
    if (transportFcm) return SignalChannel.google;
    if (distributor != null && distributor.isNotEmpty) return SignalChannel.unifiedPush;
    if (distributors == 1) return SignalChannel.unifiedPush; // выберется сам при регистрации
    return distributors > 1 ? SignalChannel.chooseDistributor : SignalChannel.periodicOnly;
  }
}

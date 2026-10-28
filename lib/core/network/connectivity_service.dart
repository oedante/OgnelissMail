// lib/core/network/connectivity_service.dart
// Мониторинг сетевого соединения.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../logging/app_logger.dart';

final connectivityServiceProvider = StateNotifierProvider<ConnectivityNotifier, ConnectivityState>((ref) {
  return ConnectivityNotifier();
});

class ConnectivityState {
  final bool isConnected;
  final bool isWifi;
  final bool isMobile;

  const ConnectivityState({this.isConnected = true, this.isWifi = false, this.isMobile = false});

  ConnectivityState copyWith({bool? isConnected, bool? isWifi, bool? isMobile}) => ConnectivityState(
    isConnected: isConnected ?? this.isConnected,
    isWifi: isWifi ?? this.isWifi,
    isMobile: isMobile ?? this.isMobile,
  );
}

class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  StreamSubscription? _sub;

  ConnectivityNotifier() : super(const ConnectivityState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      _handleResult(result);

      _sub = Connectivity().onConnectivityChanged.listen(_handleResult);
    } catch (e) {
      AppLogger.warning('Connectivity init: $e');
    }
  }

  void _handleResult(dynamic result) {
    // connectivity_plus v4 returns ConnectivityResult, v5+ returns List
    if (result is List) {
      _updateList(result.cast<ConnectivityResult>());
    } else if (result is ConnectivityResult) {
      _updateList([result]);
    }
  }

  void _updateList(List<ConnectivityResult> results) {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    final hasMobile = results.contains(ConnectivityResult.mobile);
    final hasEthernet = results.contains(ConnectivityResult.ethernet);
    final hasVpn = results.contains(ConnectivityResult.vpn);
    final connected = hasWifi || hasMobile || hasEthernet || hasVpn;

    final wasConnected = state.isConnected;
    final wasKind = _kind;
    _kind = [
      if (hasWifi) 'wifi', if (hasMobile) 'mobile', if (hasEthernet) 'ethernet', if (hasVpn) 'vpn',
    ].join('+');
    // Проводная сеть (компьютер, док-станция) — не мобильный трафик: для
    // настройки «только по Wi-Fi» считается как Wi-Fi. Иначе на ПК с кабелем
    // синхронизация при этой настройке не шла никогда.
    state = ConnectivityState(isConnected: connected, isWifi: hasWifi || hasEthernet, isMobile: hasMobile);

    // Связь ВЕРНУЛАСЬ — сообщаем подписчику. Без этого письма и правки,
    // накопленные в офлайн-очереди, ждали бы ручного обновления или
    // периодического синка: пользователь видел бы «отправлено», а на сервер
    // ничего не уходило.
    if (!wasConnected && connected) {
      try {
        onReconnected?.call();
      } catch (_) {}
    } else if (wasConnected && connected && wasKind.isNotEmpty && wasKind != _kind) {
      // Сеть сменилась без разрыва (Wi-Fi ↔ мобильная, включили VPN):
      // открытые соединения привязаны к прежнему адресу и умирают молча —
      // push об этом не узнал бы до таймаута (до получаса).
      try {
        onNetworkChanged?.call();
      } catch (_) {}
    }
  }

  String _kind = '';

  /// Вызывается при смене типа сети без разрыва связи.
  void Function()? onNetworkChanged;

  /// Проверить сеть сейчас и дождаться результата. Нужен фоновому изоляту:
  /// там синхронизация стартует раньше, чем завершится асинхронная первая
  /// проверка, и состояние «Wi-Fi» ещё ложно — при настройке «только по
  /// Wi-Fi» фоновая синхронизация не выполнялась никогда.
  Future<void> refresh() async {
    try {
      final dynamic result = await Connectivity().checkConnectivity();
      _handleResult(result);
    } catch (e) {
      AppLogger.warning('Connectivity refresh: $e');
    }
  }

  /// Вызывается при восстановлении связи. Задаётся снаружи (в приложении),
  /// чтобы сервис сети не зависел от сервиса синхронизации.
  void Function()? onReconnected;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

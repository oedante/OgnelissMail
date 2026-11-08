// lib/services/security/pin_lock_service.dart
// PIN-блокировка приложения:
// - PIN из 4–6 цифр (хеш с солью в защищённом хранилище);
// - при холодном старте приложение заблокировано сразу, ещё до первого кадра
//   с почтой (раньше наличие PIN читалось асинхронно, и заставка успевала
//   пропустить блокировку);
// - автоблокировка при сворачивании (с короткой паузой, чтобы выбор файла
//   или окно «Поделиться» не требовали PIN заново);
// - разблокировка биометрией только после реальной проверки;
// - неверные попытки и время блокировки хранятся в защищённом хранилище:
//   перезапуск приложения больше не обнуляет счётчик. После 5 ошибок —
//   пауза 30 с, дальше каждая ошибка удваивает её (до часа).

import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

import 'package:flutter_riverpod/legacy.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/security_utils.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'managed_config.dart' show ManagedConfigService;

final pinLockProvider = StateNotifierProvider<PinLockNotifier, PinLockState>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPrefsProvider);
  } catch (_) {/* тесты без настроек */}
  return PinLockNotifier(secureStorage, prefs);
});

class PinLockState {
  /// Состояние прочитано из хранилища (до этого содержимое не показываем).
  final bool loaded;
  final bool isPinSet;
  final bool isLocked;
  final int failedAttempts;

  /// До какого момента ввод PIN запрещён (null — не запрещён).
  final DateTime? blockedUntil;

  /// Длина установленного PIN: проверка запускается, когда введено столько
  /// цифр (раньше проверялось на 4-й цифре, и PIN из 5–6 цифр ввести было
  /// невозможно — каждая попытка засчитывалась как ошибка).
  final int pinLength;

  const PinLockState({
    this.loaded = false,
    this.isPinSet = false,
    this.isLocked = false,
    this.failedAttempts = 0,
    this.blockedUntil,
    this.pinLength = 4,
  });

  bool get isBlocked =>
      (blockedUntil != null && DateTime.now().isBefore(blockedUntil!)) || PinLockNotifier.blockedByUptime;

  PinLockState copyWith({
    bool? loaded,
    bool? isPinSet,
    bool? isLocked,
    int? failedAttempts,
    DateTime? blockedUntil,
    bool clearBlock = false,
    int? pinLength,
  }) {
    return PinLockState(
      loaded: loaded ?? this.loaded,
      isPinSet: isPinSet ?? this.isPinSet,
      isLocked: isLocked ?? this.isLocked,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      blockedUntil: clearBlock ? null : (blockedUntil ?? this.blockedUntil),
      pinLength: pinLength ?? this.pinLength,
    );
  }
}

class PinLockNotifier extends StateNotifier<PinLockState> {
  final SecureStorageService _storage;
  static const _pinHashKey = 'app_pin_hash';
  static const _pinSaltKey = 'app_pin_salt';
  static const _pinLenKey = 'app_pin_len';
  static const _failedKey = 'app_pin_failed';
  static const _blockedKey = 'app_pin_blocked_until';

  /// Признак «PIN задан» и его длина — вне хранилища ключей (план 08.11.2026
  /// п. 2): если хранилище не читается (сразу после перезагрузки, сбой
  /// Keystore), приложение не открывается без PIN, а остаётся закрытым и
  /// перечитывает хранилище при каждой попытке. Сам PIN и соль — только в
  /// хранилище ключей.
  static const _markerKey = 'app_pin_set';
  static const _markerLenKey = 'app_pin_len_hint';
  final SharedPreferences? _prefs;

  /// Хранилище ключей не прочиталось при запуске, а PIN был задан.
  bool _storageFailed = false;

  void _setMarker(bool isSet, [int? len]) {
    final p = _prefs;
    if (p == null) return;
    if (isSet) {
      unawaited(p.setBool(_markerKey, true));
      if (len != null) unawaited(p.setInt(_markerLenKey, len));
    } else {
      unawaited(p.remove(_markerKey));
      unawaited(p.remove(_markerLenKey));
    }
  }

  static const maxAttempts = 5;

  /// Сколько приложение может пробыть свёрнутым без повторного ввода PIN.
  static const lockGrace = Duration(seconds: 15);

  final _ready = Completer<void>();
  Timer? _unblockTimer;
  Timer? _idleTimer;
  Duration? _idleTimeout;
  DateTime? _backgroundSince;

  PinLockNotifier(this._storage, [this._prefs]) : super(const PinLockState()) {
    _load();
  }

  /// Завершается, когда состояние прочитано из хранилища.
  Future<void> get ready => _ready.future;

  Future<void> _load() async {
    try {
      // Хранилище ключей сразу после перезагрузки или обновления системы
      // бывает недоступно доли секунды (08.11.2026, аудит безопасности:
      // при ошибке приложение открывалось без PIN) — несколько повторов.
      String? hash;
      for (var i = 0;; i++) {
        try {
          hash = await _storage.read(_pinHashKey);
          break;
        } catch (e) {
          if (i >= 4) rethrow;
          await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
        }
      }
      final isSet = hash != null && hash.isNotEmpty;
      final len = int.tryParse(await _storage.read(_pinLenKey) ?? '') ?? 4;
      final failed = int.tryParse(await _storage.read(_failedKey) ?? '') ?? 0;
      final blockedMs = int.tryParse(await _storage.read(_blockedKey) ?? '');
      final blocked = blockedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(blockedMs);
      if (!mounted) return;
      state = PinLockState(
        loaded: true,
        isPinSet: isSet,
        // Холодный старт с установленным PIN — сразу заблокировано.
        isLocked: isSet,
        failedAttempts: failed,
        blockedUntil: blocked,
        pinLength: len.clamp(4, 6),
      );
      _scheduleUnblock();
      _storageFailed = false;
      _setMarker(isSet, len.clamp(4, 6));
      // С PIN — без снимков экрана и миниатюры в недавних приложениях.
      unawaited(ManagedConfigService.secureFor('pin', isSet));
    } catch (e) {
      AppLogger.warning('PIN: не удалось прочитать состояние: $e');
      if (_prefs?.getBool(_markerKey) == true) {
        // PIN был задан: без него не открываем (план 08.11.2026 п. 2). Ввод
        // PIN перечитает хранилище; есть и вход по биометрии.
        _storageFailed = true;
        if (mounted) {
          state = PinLockState(
            loaded: true,
            isPinSet: true,
            isLocked: true,
            pinLength: (_prefs?.getInt(_markerLenKey) ?? 4).clamp(4, 6),
          );
        }
        unawaited(ManagedConfigService.secureFor('pin', true));
      } else if (mounted) {
        // PIN не задавался — открываем как обычно.
        state = state.copyWith(loaded: true);
      }
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  void _scheduleUnblock() {
    _unblockTimer?.cancel();
    final until = state.blockedUntil;
    if (until == null) return;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return;
    // Перерисовать экран, когда пауза закончится.
    _unblockTimer = Timer(left, () {
      if (mounted) state = state.copyWith();
    });
  }

  static bool _isDigits(String s) => RegExp(r'^\d+$').hasMatch(s);

  /// Установить PIN (4–6 цифр). Возвращает false, если PIN не подходит.
  Future<bool> setPin(String pin) async {
    if (pin.length < 4 || pin.length > 6 || !_isDigits(pin)) return false;

    final salt = SecurityUtils.generateSalt();
    final hash = SecurityUtils.hashWithSalt(pin, salt);

    await _storage.write(_pinHashKey, hash);
    await _storage.write(_pinSaltKey, salt);
    await _storage.write(_pinLenKey, '${pin.length}');
    await _resetFailures();
    _storageFailed = false;
    _setMarker(true, pin.length);

    state = state.copyWith(
        loaded: true, isPinSet: true, isLocked: false, pinLength: pin.length,
        failedAttempts: 0, clearBlock: true);
    recordActivity();
    unawaited(ManagedConfigService.secureFor('pin', true));
    AppLogger.info('PIN установлен');
    return true;
  }

  /// Пауза после неверных попыток по монотонному времени процесса.
  static Stopwatch? _blockClock;
  static Duration _blockFor = Duration.zero;
  static bool get blockedByUptime {
    final c = _blockClock;
    return c != null && c.elapsed < _blockFor;
  }

  Future<void> _resetFailures() async {
    _blockClock = null;
    await _storage.delete(_failedKey);
    await _storage.delete(_blockedKey);
  }

  /// Проверить PIN.
  Future<bool> verifyPin(String pin) async {
    if (state.isBlocked) return false;

    String? storedHash;
    String? salt;
    try {
      storedHash = await _storage.read(_pinHashKey);
      salt = await _storage.read(_pinSaltKey);
    } catch (e) {
      // Хранилище ключей всё ещё недоступно — это не ошибка ввода: попытка
      // не засчитывается, приложение остаётся закрытым.
      AppLogger.warning('PIN: хранилище недоступно при проверке: $e');
      return false;
    }
    if (_storageFailed) {
      _storageFailed = false;
      if (storedHash == null || salt == null) {
        // Хранилище прочиталось, а PIN в нём нет (данные приложения
        // сброшены системой) — PIN не задан.
        _setMarker(false);
        if (mounted) state = const PinLockState(loaded: true);
        unawaited(ManagedConfigService.secureFor('pin', false));
        return true;
      }
    }
    if (storedHash == null || salt == null) return false;

    final inputHash = SecurityUtils.hashWithSalt(pin, salt);
    if (SecurityUtils.constantTimeEquals(inputHash, storedHash)) {
      await _resetFailures();
      state = state.copyWith(isLocked: false, failedAttempts: 0, clearBlock: true);
      recordActivity();
      AppLogger.info('PIN verified');
      return true;
    }

    final attempts = state.failedAttempts + 1;
    DateTime? until;
    if (attempts >= maxAttempts) {
      // 30 с, 60 с, 120 с … но не больше часа.
      final seconds = math.min(3600, 30 * (1 << math.min(7, attempts - maxAttempts)));
      until = DateTime.now().add(Duration(seconds: seconds));
      // И по монотонному времени (08.11.2026, аудит): перевод часов вперёд
      // не снимает паузу, пока приложение работает.
      _blockClock = Stopwatch()..start();
      _blockFor = Duration(seconds: seconds);
    }
    await _storage.write(_failedKey, '$attempts');
    if (until != null) {
      await _storage.write(_blockedKey, '${until.millisecondsSinceEpoch}');
    }
    state = state.copyWith(failedAttempts: attempts, blockedUntil: until);
    _scheduleUnblock();

    AppLogger.warning('PIN failed: attempt $attempts');
    return false;
  }

  /// Удалить PIN.
  Future<void> removePin() async {
    await _storage.delete(_pinHashKey);
    await _storage.delete(_pinSaltKey);
    await _storage.delete(_pinLenKey);
    await _resetFailures();
    _setMarker(false);
    _unblockTimer?.cancel();
    state = const PinLockState(loaded: true);
    unawaited(ManagedConfigService.secureFor('pin', false));
    AppLogger.info('PIN removed');
  }

  /// Заблокировать немедленно.
  void lock() {
    _idleTimer?.cancel();
    if (state.isPinSet && mounted) {
      state = state.copyWith(isLocked: true);
    }
  }

  /// Блокировка после бездействия (политика Exchange MaxInactivityTimeDeviceLock).
  /// null или ноль — выключена.
  void setIdleTimeout(Duration? timeout) {
    _idleTimeout = (timeout == null || timeout <= Duration.zero) ? null : timeout;
    recordActivity();
  }

  /// Пользователь что-то сделал (касание, клавиша) — отсчёт бездействия заново.
  void recordActivity() {
    _idleTimer?.cancel();
    final t = _idleTimeout;
    if (t == null || !state.isPinSet || state.isLocked) return;
    _idleTimer = Timer(t, lock);
  }

  /// Приложение ушло в фон.
  void onBackground() {
    _backgroundSince ??= DateTime.now();
  }

  /// Приложение вернулось: блокируем, если оно было свёрнуто дольше паузы.
  void onForeground() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (since != null && DateTime.now().difference(since) >= lockGrace) {
      lock();
    }
  }

  /// Разблокировать через биометрию ТОЛЬКО после успешной проверки отпечатка/лица.
  /// Возвращает true при успехе. Без фактической аутентификации НЕ разблокирует.
  Future<bool> authenticateBiometric({String reason = 'Подтвердите личность для входа'}) async {
    try {
      final localAuth = LocalAuthentication();
      final canCheck = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
      if (!canCheck) {
        AppLogger.warning('Биометрия недоступна на устройстве');
        return false;
      }
      final ok = await localAuth.authenticate(localizedReason: reason);
      if (ok) {
        await _resetFailures();
        state = state.copyWith(isLocked: false, failedAttempts: 0, clearBlock: true);
        recordActivity();
        AppLogger.info('Биометрия подтверждена');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.warning('Ошибка биометрии: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _unblockTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }
}

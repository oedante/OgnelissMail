// PIN и сбой хранилища ключей (план 08.11.2026 п. 2): если PIN был задан,
// ошибка хранилища не открывает приложение; ввод PIN перечитывает
// хранилище, такие попытки не засчитываются как неверные.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/services/security/pin_lock_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Storage extends SecureStorageService {
  final data = <String, String>{};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw Exception('Keystore недоступен');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw Exception('Keystore недоступен');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PIN задан, хранилище сломано — закрыто; починилось — верный PIN открывает', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = _Storage();
    final first = PinLockNotifier(storage, prefs);
    await first.ready;
    expect(await first.setPin('2468'), isTrue);
    first.dispose();

    // Перезапуск: хранилище недоступно.
    storage.broken = true;
    final pin = PinLockNotifier(storage, prefs);
    await pin.ready;
    expect(pin.state.isPinSet, isTrue);
    expect(pin.state.isLocked, isTrue, reason: 'без PIN не открываем');
    expect(await pin.verifyPin('2468'), isFalse);
    expect(pin.state.failedAttempts, 0, reason: 'сбой хранилища — не ошибка ввода');

    storage.broken = false;
    expect(await pin.verifyPin('1111'), isFalse);
    expect(pin.state.failedAttempts, 1);
    expect(await pin.verifyPin('2468'), isTrue);
    expect(pin.state.isLocked, isFalse);
    pin.dispose();
  });

  test('PIN не задавался — сбой хранилища не закрывает приложение', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = _Storage()..broken = true;
    final pin = PinLockNotifier(storage, prefs);
    await pin.ready;
    expect(pin.state.loaded, isTrue);
    expect(pin.state.isLocked, isFalse);
    pin.dispose();
  });
}

// Опоздавший пульс фоновой работы = заморозка приложения оболочкой
// производителя (1.6.43, журнал Honor 19.10.2026: 84 минуты без пульса при
// службе и точных будильниках).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/background/foreground_sync_controller.dart';

void main() {
  group('Опоздание пульса', () {
    const min = 60 * 1000;

    test('точный будильник опоздал на 20+ минут — заморозка', () {
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': 84 * min, 'exact': true}), 84);
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': 20 * min, 'exact': true}), 20);
    });

    test('обычное опоздание в Doze (до ~15 мин) — не заморозка', () {
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': 15 * min, 'exact': true}), isNull);
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': 0, 'exact': true}), isNull);
    });

    test('неточный будильник Doze может отложить надолго — не считаем', () {
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': 90 * min, 'exact': false}), isNull);
    });

    test('прежняя нативная часть (без аргументов) — не заморозка', () {
      expect(ForegroundSyncController.lateMinutesIfFrozen(null), isNull);
      expect(ForegroundSyncController.lateMinutesIfFrozen(const <String, Object>{}), isNull);
      expect(ForegroundSyncController.lateMinutesIfFrozen({'lateMs': '84', 'exact': true}), isNull);
    });
  });
}

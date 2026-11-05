// Готовность устройства к уведомлениям о почте (1.12.x, аудит устройств,
// просьба владельца 05.11.2026): семейства прошивок, сборки без оболочки
// производителя, шаги первой настройки, способ сигналов с сервисами Google
// и без них.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/device_readiness.dart';
import 'package:ogneliss/core/platform/platform_diagnostics.dart';

/// Android без единой проблемы: уведомления, батарея, точные будильники.
Map<String, dynamic> android(
  String manufacturer, {
  String brand = '',
  String rom = '',
  Map<String, dynamic> extra = const {},
}) => {
  'manufacturer': manufacturer,
  'brand': brand,
  'rom': rom,
  'sdk': 35,
  'notificationsEnabled': true,
  'ignoringBatteryOptimizations': true,
  'backgroundRestricted': false,
  'standbyBucket': 'active',
  'exactAlarms': true,
  'dataSaver': 'off',
  'powerSaveMode': false,
  ...extra,
};

void main() {
  group('Семейство прошивки', () {
    test('производители и марки', () {
      expect(PlatformDiagnostics.family(android('Xiaomi', brand: 'Redmi')), 'xiaomi');
      expect(PlatformDiagnostics.family(android('Xiaomi', brand: 'POCO')), 'xiaomi');
      expect(PlatformDiagnostics.family(android('HUAWEI', brand: 'HUAWEI')), 'huawei');
      expect(PlatformDiagnostics.family(android('HONOR', brand: 'HONOR')), 'honor');
      expect(PlatformDiagnostics.family(android('OnePlus', brand: 'OnePlus')), 'oneplus');
      expect(PlatformDiagnostics.family(android('realme', brand: 'realme')), 'realme');
      expect(PlatformDiagnostics.family(android('vivo', brand: 'iQOO')), 'vivo');
      expect(PlatformDiagnostics.family(android('samsung', brand: 'samsung')), 'samsung');
      expect(PlatformDiagnostics.family(android('nubia', brand: 'nubia')), 'nubia');
      expect(PlatformDiagnostics.family(android('ZTE', brand: 'ZTE')), 'zte');
      expect(PlatformDiagnostics.family(android('motorola', brand: 'motorola')), 'motorola');
      expect(PlatformDiagnostics.family(android('Google', brand: 'google')), 'pixel');
      expect(PlatformDiagnostics.family(android('TECNO MOBILE LIMITED', brand: 'TECNO')), 'tecno');
      expect(PlatformDiagnostics.family(android('INFINIX MOBILITY LIMITED', brand: 'Infinix')), 'tecno');
      expect(PlatformDiagnostics.family(android('ITEL', brand: 'Itel')), 'tecno');
      expect(PlatformDiagnostics.family(android('HMD Global', brand: 'Nokia')), 'nokia');
      expect(PlatformDiagnostics.family(android('Fairphone', brand: 'Fairphone')), 'fairphone');
    });

    test('по словам, а не по подстроке', () {
      expect(PlatformDiagnostics.family(android('Satellite Phones', brand: 'Vitel')), 'other');
    });
  });

  group('Оболочка производителя', () {
    test('MIUI, One UI, MyOS — «оптимизатор» есть; Pixel и Motorola — нет', () {
      expect(PlatformDiagnostics.hasOemManager(android('Xiaomi', rom: 'HyperOS')), isTrue);
      expect(PlatformDiagnostics.hasOemManager(android('samsung', rom: 'One UI')), isTrue);
      expect(PlatformDiagnostics.hasOemManager(android('nubia', rom: 'MyOS/MiFavor')), isTrue);
      expect(PlatformDiagnostics.hasOemManager(android('TECNO MOBILE LIMITED')), isTrue);
      expect(PlatformDiagnostics.hasOemManager(android('Google')), isFalse);
      expect(PlatformDiagnostics.hasOemManager(android('motorola')), isFalse);
    });

    test('LineageOS и CalyxOS на телефоне Xiaomi или Samsung — без «оптимизатора»', () {
      final lineage = android('Xiaomi', brand: 'Redmi', rom: 'LineageOS');
      expect(PlatformDiagnostics.customRom(lineage), isTrue);
      expect(PlatformDiagnostics.hasOemManager(lineage), isFalse);
      expect(PlatformDiagnostics.issues(lineage, ios: false), isNot(contains(BgIssue.oemManager)));
      expect(PlatformDiagnostics.hasOemManager(android('samsung', rom: 'CalyxOS')), isFalse);
    });

    test('сервисы Google Play', () {
      expect(PlatformDiagnostics.googleServices(android('HUAWEI', extra: {'gms': 'missing'})), isFalse);
      expect(PlatformDiagnostics.googleServices(android('Google', extra: {'gms': 'disabled'})), isFalse);
      expect(PlatformDiagnostics.googleServices(android('Google', extra: {'gms': 'ok'})), isTrue);
      expect(PlatformDiagnostics.googleServices(android('Google')), isNull);
    });
  });

  group('Шаги первой настройки', () {
    test('всё в порядке — шагов нет, ничего не показывается', () {
      final steps = DeviceReadiness.steps(android('Google'), ios: false, signal: SignalChannel.google);
      expect(steps, isEmpty);
      expect(DeviceReadiness.needsAction(steps), isFalse);
    });

    test('Android 13+ без разрешения, оптимизация батареи, оболочка — по порядку важности', () {
      final d = android(
        'Xiaomi',
        rom: 'HyperOS',
        extra: {'notificationsEnabled': false, 'ignoringBatteryOptimizations': false, 'exactAlarms': false},
      );
      expect(DeviceReadiness.steps(d, ios: false, signal: SignalChannel.google), [
        ReadyStep.notifications,
        ReadyStep.battery,
        ReadyStep.oemAutostart,
        ReadyStep.exactAlarms,
      ]);
    });

    test('«Батарея → Ограничено» — шаг, даже без оболочки', () {
      final d = android('Google', extra: {'backgroundRestricted': true});
      expect(DeviceReadiness.steps(d, ios: false, signal: SignalChannel.google), [ReadyStep.backgroundRestricted]);
    });

    test('категория «Почта» выключена', () {
      final d = android(
        'Google',
        extra: {
          'channels': [
            {'id': 'email_default_sv', 'importance': 0},
          ],
        },
      );
      expect(DeviceReadiness.steps(d, ios: false), [ReadyStep.mailChannel]);
    });

    test('без Google и распространителя — только сведения, шаг настройки не нужен', () {
      final steps = DeviceReadiness.steps(
        android('HUAWEI', rom: 'LineageOS'),
        ios: false,
        signal: SignalChannel.periodicOnly,
      );
      expect(steps, [ReadyStep.periodicOnly]);
      expect(DeviceReadiness.needsAction(steps), isFalse);
    });

    test('несколько распространителей — выбрать', () {
      final steps = DeviceReadiness.steps(android('Google'), ios: false, signal: SignalChannel.chooseDistributor);
      expect(steps, [ReadyStep.chooseSignals]);
      expect(DeviceReadiness.needsAction(steps), isTrue);
    });

    test('iPhone: ещё не спрошено — шаг «уведомления»; выключено «Обновление контента»', () {
      final d = {'notifications': 'notDetermined', 'backgroundRefresh': 'denied', 'lowPowerMode': false};
      expect(DeviceReadiness.steps(d, ios: true, signal: SignalChannel.apple), [
        ReadyStep.notifications,
        ReadyStep.iosRefresh,
      ]);
      final ok = {'notifications': 'authorized', 'backgroundRefresh': 'available', 'lowPowerMode': true};
      expect(
        DeviceReadiness.steps(ok, ios: true, signal: SignalChannel.apple),
        isEmpty,
        reason: 'энергосбережение — временное, не шаг настройки',
      );
    });

    test('компьютер и фоновый изолят (сведений нет) — шагов нет', () {
      expect(DeviceReadiness.steps(const {}, ios: false, signal: SignalChannel.periodicOnly), isEmpty);
    });
  });

  group('Способ сигналов на Android', () {
    test('Google, распространитель, выбор, только расписание, выключено', () {
      SignalChannel sig({bool enabled = true, bool fcm = false, String? dist, int n = 0}) =>
          DeviceReadiness.androidSignal(enabled: enabled, transportFcm: fcm, distributor: dist, distributors: n);
      expect(sig(fcm: true), SignalChannel.google);
      expect(sig(dist: 'io.heckel.ntfy', n: 2), SignalChannel.unifiedPush);
      expect(sig(n: 1), SignalChannel.unifiedPush);
      expect(sig(n: 2), SignalChannel.chooseDistributor);
      expect(sig(), SignalChannel.periodicOnly);
      expect(sig(enabled: false, fcm: true), SignalChannel.off);
    });
  });
}

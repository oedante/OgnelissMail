// Имена пояса в TIME_ZONE_INFORMATION ActiveSync (1.6.2, исправлено 1.6.4):
// StandardName и DaylightName — как в реестре Windows, а не одно имя дважды.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/device_time_zone.dart';
import 'package:ogneliss/services/mail/engine/mail_engine_service.dart';

String _wchar(Uint8List b, int offset) {
  final bd = ByteData.sublistView(b);
  final units = <int>[];
  for (var i = 0; i < 32; i++) {
    final u = bd.getUint16(offset + i * 2, Endian.little);
    if (u == 0) break;
    units.add(u);
  }
  return String.fromCharCodes(units);
}

void main() {
  test('Екатеринбург: Standard и Daylight', () {
    final n = DeviceTimeZone.tziNames(DeviceTimeZone.windowsName('Asia/Yekaterinburg'))!;
    expect(n.std, 'Ekaterinburg Standard Time');
    expect(n.dlt, 'Ekaterinburg Daylight Time');
  });

  test('пояса с особыми именами в реестре', () {
    expect(DeviceTimeZone.tziNames('Russia Time Zone 3')!.std, 'Russia TZ 3 Standard Time');
    expect(DeviceTimeZone.tziNames('UTC')!.std, 'Coordinated Universal Time');
    expect(DeviceTimeZone.tziNames(null), isNull);
  });

  test('имена записаны в свои поля TIME_ZONE_INFORMATION', () {
    final b = Uint8List.fromList(base64.decode(MailEngineService.easTimeZone(
        DateTime(2026, 10, 13, 12), windowsName: 'Ekaterinburg Standard Time')));
    expect(b.length, 172);
    expect(_wchar(b, 4), 'Ekaterinburg Standard Time');
    expect(_wchar(b, 88), 'Ekaterinburg Daylight Time');
  });
}

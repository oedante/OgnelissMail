// Режим совместимости со шлюзом на всех платформах (2.2.x, просьба
// владельца 10.11.2026): каждая платформа представляется своей штатной
// почтой — Windows (Почта Windows и Outlook), Mac (Mail и Почта iPad),
// Linux (Thunderbird для EWS).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/device/device_user_agent.dart';

void main() {
  test('Windows: Почта Windows для ActiveSync, Outlook для EWS', () {
    expect(DeviceUserAgent.windowsMailUserAgent(22631), 'MSFT-WIN-3/10.0.22631');
    expect(DeviceUserAgent.windowsMailUserAgent(0), 'MSFT-WIN-3/10.0.19045', reason: 'сборка не прочиталась');
    expect(DeviceUserAgent.outlookUserAgent, startsWith('Microsoft Office/16.0 (Windows NT 10.0; Microsoft Outlook'));
  });

  test('Mac: Mail для EWS по версии системы, Почта iPad для ActiveSync', () {
    expect(DeviceUserAgent.macMailEwsUserAgent('14.6.1', '23G93'),
        'Mac OS X/14.6.1 (23G93); ExchangeWebServices/10.0 (269); Mail/16.0 (3774.600.62)');
    expect(DeviceUserAgent.macMailEwsUserAgent('15.5', ''), startsWith('Mac OS X/15.5; ExchangeWebServices/10.0'));
    expect(DeviceUserAgent.iosVersionForMac('15.5'), '18.5');
    expect(DeviceUserAgent.iosVersionForMac('14.6.1'), '17.6');
    expect(DeviceUserAgent.iosVersionForMac('26.1'), '26.1');
    expect(DeviceUserAgent.appleMailUserAgent('iPad13,1', DeviceUserAgent.iosVersionForMac('15.5')),
        'Apple-iPad13C1/2205.0');
  });

  test('Linux: Thunderbird для EWS', () {
    expect(DeviceUserAgent.thunderbirdUserAgent, contains('Thunderbird/'));
    expect(DeviceUserAgent.thunderbirdUserAgent, contains('X11; Linux'));
  });

  test('ящик без режима совместимости — свой честный User-Agent и для EWS', () {
    expect(DeviceUserAgent.valueFor('nobody', ews: true), DeviceUserAgent.valueFor('nobody'));
  });
}

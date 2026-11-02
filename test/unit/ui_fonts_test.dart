// Шрифт интерфейса на выбор — стандартные шрифты платформы (1.10.2).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/ui_fonts.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('на каждой платформе — системный, Roboto и шрифты системы', () {
    for (final p in TargetPlatform.values) {
      final list = UiFonts.forPlatform(p);
      expect(list.first.id, 'system', reason: '$p');
      expect(list.first.family, isNull);
      expect(list[1].family, UiFonts.robotoFamily);
      expect(list.length, greaterThanOrEqualTo(4), reason: '$p');
      expect(list.map((f) => f.id).toSet().length, list.length, reason: 'id без повторов: $p');
    }
  });

  test('неизвестный и прежний Medeo Sans — Roboto; шрифт другой платформы — тоже', () {
    expect(UiFonts.resolve('medeo', TargetPlatform.android).id, 'roboto');
    expect(UiFonts.resolve('calibri', TargetPlatform.android).id, 'roboto');
    expect(UiFonts.resolve('calibri', TargetPlatform.windows).family, 'Calibri');
    expect(UiFonts.resolve('serif', TargetPlatform.android).family, 'serif');
  });

  test('настройка: Medeo Sans становится Roboto, системный сохраняется', () async {
    SharedPreferences.setMockInitialValues({'s_ui_font': 'medeo'});
    final n = SettingsNotifier(await SharedPreferences.getInstance());
    expect(n.state.uiFont, 'roboto');
    await n.setUiFont('system');
    expect(SettingsNotifier(await SharedPreferences.getInstance()).state.uiFont, 'system');
    await n.setUiFont('nonsense');
    expect(n.state.uiFont, 'roboto');
  });
}

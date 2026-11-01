// «Оформление» (1.9.x, просьба владельца 31.10.2026): выбор сохраняется в
// настройках и переживает перезапуск, по умолчанию — прежний вид, анимация
// открытия письма выключена и уступает «Уменьшить движение».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/appearance.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsNotifier> _notifier([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsNotifier(await SharedPreferences.getInstance());
}

void main() {
  test('по умолчанию — «Классика», обычная плотность, анимация выключена', () async {
    final s = (await _notifier()).state;
    expect(s.themePreset, ThemePreset.classic);
    expect(s.accentColor, isNull);
    expect(s.listTint, ListTint.none);
    expect(s.corners, CornerSize.medium);
    expect(s.listDensity, ListDensity.normal);
    expect(s.openAnimation, isFalse);
    expect(s.appearance(), Appearance.classic);
    expect(s.appearance().classicColors, isTrue);
  });

  test('выбор сохраняется и читается заново', () async {
    final n = await _notifier();
    await n.setThemePreset(ThemePreset.forest);
    await n.setAccentColor(0xFFC62828);
    await n.setListTint(ListTint.soft);
    await n.setCorners(CornerSize.large);
    await n.setListDensity(ListDensity.compact);
    await n.setOpenAnimation(true);

    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.themePreset, ThemePreset.forest);
    expect(again.accentColor, 0xFFC62828);
    expect(again.listTint, ListTint.soft);
    expect(again.corners, CornerSize.large);
    expect(again.listDensity, ListDensity.compact);
    expect(again.openAnimation, isTrue);
    expect(again.appearance().openAnimation, isTrue);
  });

  test('акцент «как в теме» стирает свой цвет', () async {
    final n = await _notifier({'s_accent': 0xFF00838F});
    expect(n.state.accentColor, 0xFF00838F);
    await n.setAccentColor(null);
    expect(n.state.accentColor, isNull);
    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.accentColor, isNull);
  });

  test('анимация открытия уступает «Уменьшить движение» и системному «Убрать анимацию»', () async {
    final n = await _notifier({'s_open_anim': true});
    expect(n.state.appearance().openAnimation, isTrue);
    expect(n.state.appearance(systemNoAnimations: true).openAnimation, isFalse);
    await n.setReduceMotion(true);
    expect(n.state.appearance().openAnimation, isFalse);
    // Настройка не теряется: выключили «Уменьшить движение» — снова работает.
    await n.setReduceMotion(false);
    expect(n.state.appearance().openAnimation, isTrue);
  });

  test('неизвестная тема — «Классика», номер вне списка — ближайший вариант', () async {
    final s = (await _notifier({'s_theme_preset': 'neon', 's_list_tint': 99, 's_corners': -3, 's_density': 42})).state;
    expect(s.themePreset, ThemePreset.classic);
    expect(s.listTint, ListTint.soft);
    expect(s.corners, CornerSize.small);
    expect(s.listDensity, ListDensity.comfortable);
  });

  test('сброс настроек возвращает прежний вид', () async {
    final n = await _notifier({
      's_theme_preset': 'midnight',
      's_accent': 0xFF8E3FB5,
      's_list_tint': 2,
      's_corners': 0,
      's_density': 0,
      's_open_anim': true,
    });
    await n.resetAll();
    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.appearance(), Appearance.classic);
  });

  test('плотность: строки превью', () {
    expect(DensitySpec.compact.previewFor(3), 0);
    expect(DensitySpec.normal.previewFor(1), 1);
    expect(DensitySpec.normal.previewFor(4), 4);
    expect(DensitySpec.comfortable.previewFor(1), 2);
    expect(DensitySpec.comfortable.previewFor(3), 3);
  });
}

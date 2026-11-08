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
  test('по умолчанию — «Классика», обычная плотность, анимация открытия письма включена (1.10.1)', () async {
    final s = (await _notifier()).state;
    expect(s.themePreset, ThemePreset.classic);
    expect(s.accentColor, isNull);
    expect(s.listTint, ListTint.none);
    expect(s.corners, CornerSize.medium);
    expect(s.listDensity, ListDensity.normal);
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

    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.themePreset, ThemePreset.forest);
    expect(again.accentColor, 0xFFC62828);
    expect(again.listTint, ListTint.soft);
    expect(again.corners, CornerSize.large);
    expect(again.listDensity, ListDensity.compact);
  });

  test('акцент «как в теме» стирает свой цвет', () async {
    final n = await _notifier({'s_accent': 0xFF00838F});
    expect(n.state.accentColor, 0xFF00838F);
    await n.setAccentColor(null);
    expect(n.state.accentColor, isNull);
    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.accentColor, isNull);
  });

  test('анимации открытия письма нет (убрана 07.11.2026), даже если прежде была включена', () async {
    final n = await _notifier({'s_open_anim': true});
    expect(n.state.appearance().openAnimation, isFalse);
    expect(n.state.appearance(systemNoAnimations: true).openAnimation, isFalse);
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
      's_open_anim': false,
    });
    await n.resetAll();
    final again = SettingsNotifier(await SharedPreferences.getInstance()).state;
    expect(again.appearance(), Appearance.classic);
  });

  test('плотность: строки превью', () {
    // Число строк задаёт настройка (1.10.2); «Компактная» при одной строке —
    // превью в строке темы.
    expect(DensitySpec.compact.previewFor(1), 0);
    expect(DensitySpec.compact.previewFor(3), 3);
    expect(DensitySpec.normal.previewFor(1), 1);
    expect(DensitySpec.normal.previewFor(4), 4);
    expect(DensitySpec.comfortable.previewFor(1), 1);
    expect(DensitySpec.comfortable.previewFor(3), 3);
  });

  test('выбор плотности подстраивает «Строк текста», а та остаётся главной (1.10.2)', () async {
    final n = await _notifier({'s_preview_lines': 3});
    await n.setListDensity(ListDensity.compact);
    expect(n.state.previewLines, 1);
    await n.setPreviewLines(2);
    expect(n.state.listDensity, ListDensity.compact, reason: 'строки меняются, плотность — нет');
    expect(n.state.appearance().density, ListDensity.compact);
    await n.setListDensity(ListDensity.comfortable);
    expect(n.state.previewLines, 2);
    await n.setPreviewLines(1);
    expect(n.state.previewLines, 1);
    await n.setListDensity(ListDensity.normal);
    expect(n.state.previewLines, 1, reason: 'обычная не трогает выбор');
  });
}

// Цветовые темы и акценты «Оформления» (1.9.x, просьба владельца
// 31.10.2026): текст во всех темах — светлых, тёмных и AMOLED, со своим
// акцентом и с оттенком ленты — не ниже нормы WCAG AA (4,5:1).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/core/theme/appearance.dart';
import 'package:ogneliss/core/theme/theme_palette.dart';

const _aa = 4.5;

/// Пары «текст — фон», которые встречаются в приложении.
Map<String, (Color, Color)> _pairs(ThemeData t) {
  final s = t.colorScheme;
  final look = t.extension<AppearanceLook>()!;
  final list = look.listFill ?? s.surface;
  final card = t.cardTheme.color ?? s.surface;
  return {
    'onSurface/surface': (s.onSurface, s.surface),
    'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
    'onSurface/scaffold': (s.onSurface, t.scaffoldBackgroundColor),
    'onSurfaceVariant/scaffold': (s.onSurfaceVariant, t.scaffoldBackgroundColor),
    'onSurface/card': (s.onSurface, card),
    'onSurfaceVariant/card': (s.onSurfaceVariant, card),
    'onSurface/high': (s.onSurface, s.surfaceContainerHigh),
    'onSurfaceVariant/highest': (s.onSurfaceVariant, s.surfaceContainerHighest),
    'onSurface/list': (s.onSurface, list),
    'onSurfaceVariant/list': (s.onSurfaceVariant, list),
    // Непрочитанная строка — ещё чуть акцента поверх фона ленты.
    'onSurface/unread': (s.onSurface, Color.alphaBlend(s.primary.withValues(alpha: 0.035), list)),
    'primary/surface': (s.primary, s.surface),
    'primary/scaffold': (s.primary, t.scaffoldBackgroundColor),
    'primary/card': (s.primary, card),
    'primary/list': (s.primary, list),
    'primary/highest': (s.primary, s.surfaceContainerHighest),
    'onPrimary/primary': (s.onPrimary, s.primary),
    'onPrimaryContainer/primaryContainer': (s.onPrimaryContainer, s.primaryContainer),
    'onSecondaryContainer/secondaryContainer': (s.onSecondaryContainer, s.secondaryContainer),
    'onSecondary/secondary': (s.onSecondary, s.secondary),
    'onSurface/navBar': (s.onSurface, t.navigationBarTheme.backgroundColor ?? s.surface),
    'onSurface/input': (s.onSurface, t.inputDecorationTheme.fillColor ?? s.surface),
  };
}

void _expectAA(String what, ThemeData t) {
  for (final e in _pairs(t).entries) {
    final c = AccentFit.contrast(e.value.$1, e.value.$2);
    expect(c, greaterThanOrEqualTo(_aa), reason: '$what: ${e.key} = ${c.toStringAsFixed(2)}');
  }
}

List<(String, ThemeData)> _themes(Appearance a) => [
  ('light', AppTheme.lightTheme(1.0, appearance: a)),
  ('dark', AppTheme.darkTheme(1.0, appearance: a)),
  ('amoled', AppTheme.amoledTheme(1.0, appearance: a)),
];

void main() {
  test('«Классика» без своего акцента — прежние цвета', () {
    final t = AppTheme.lightTheme(1.0);
    expect(t.colorScheme.primary, AppColors.brandBlue);
    expect(t.scaffoldBackgroundColor, const Color(0xFFF2F5F9));
    expect(AppTheme.darkTheme(1.0).colorScheme.primary, const Color(0xFF9DBDEB));
    expect(t.extension<AppearanceLook>()!.listFill, isNull);
  });

  for (final p in ThemePreset.values) {
    for (final tint in ListTint.values) {
      test('тема ${p.name}, оттенок ${tint.name} — AA', () {
        for (final (name, t) in _themes(Appearance(preset: p, tint: tint))) {
          _expectAA('${p.name}/$name/${tint.name}', t);
        }
      });
    }
  }

  test('готовые акценты в каждой теме — AA', () {
    for (final p in ThemePreset.values) {
      for (final c in accentSwatches) {
        for (final (name, t) in _themes(Appearance(preset: p, accent: c.toARGB32(), tint: ListTint.soft))) {
          _expectAA('${p.name}/$name/${c.toARGB32().toRadixString(16)}', t);
        }
      }
    }
  });

  test('свой цвет: любой тон и насыщенность — AA', () {
    for (var hue = 0.0; hue < 360; hue += 15) {
      for (final sat in const [0.0, 0.3, 0.6, 1.0]) {
        for (final light in const [0.15, 0.5, 0.85]) {
          final c = AccentFit.hsl(hue, sat, light);
          for (final p in const [ThemePreset.classic, ThemePreset.sunset, ThemePreset.midnight]) {
            for (final (name, t) in _themes(Appearance(preset: p, accent: c.toARGB32()))) {
              _expectAA('${p.name}/$name/h$hue s$sat l$light', t);
            }
          }
        }
      }
    }
  });

  test('цветовые темы различимы между собой', () {
    final fills = {
      for (final p in ThemePreset.values) ThemePalette.light(Appearance(preset: p)).scheme.primary.toARGB32(),
    };
    expect(fills.length, ThemePreset.values.length);
  });

  test('скругление: среднее — как было, малое и большое меняют формы', () {
    RoundedRectangleBorder card(CornerSize c) =>
        AppTheme.lightTheme(1.0, appearance: Appearance(corners: c)).cardTheme.shape! as RoundedRectangleBorder;
    expect(card(CornerSize.medium).borderRadius, BorderRadius.circular(16));
    expect(card(CornerSize.small).borderRadius, BorderRadius.circular(8));
    expect(card(CornerSize.large).borderRadius, BorderRadius.circular(16 * 1.4));
    final sheet =
        AppTheme.lightTheme(1.0, appearance: const Appearance(corners: CornerSize.large)).bottomSheetTheme.shape!
            as RoundedRectangleBorder;
    expect(sheet.borderRadius, const BorderRadius.vertical(top: Radius.circular(32)));
  });

  test('высокий контраст: оттенка ленты нет', () {
    final t = AppTheme.lightTheme(1.0, highContrast: true, appearance: const Appearance(tint: ListTint.soft));
    expect(t.extension<AppearanceLook>()!.listFill, isNull);
  });
}

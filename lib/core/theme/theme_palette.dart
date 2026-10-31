// lib/core/theme/theme_palette.dart
// Палитра светлой и тёмной темы по «Оформлению» (1.9.x, просьба владельца
// 31.10.2026). У «Классики» без своего акцента — прежние цвета, цвет в цвет
// (их раньше задавал прямо AppTheme). Остальные темы строятся из тех же
// ступеней яркости: серые поверхности поворачиваются к тону темы, акцент и
// его производные (заливки выбранного, подписи) — от акцента с подобранной
// яркостью ([AccentFit]). Контраст всех пар «текст — фон» проверяет
// test/unit/theme_presets_test.dart.

import 'package:flutter/material.dart';

import 'appearance.dart';

/// Цвета, которые тема берёт не из ColorScheme: фон экрана, карточка,
/// поле ввода, разделитель, нижняя панель, вкладки.
class ThemePalette {
  final ColorScheme scheme;
  final Color scaffold;
  final Color card;
  final Color inputFill;
  final Color divider;
  final Color navBar;

  /// Подпись и черта выбранной вкладки (светлая тема); null — по схеме.
  final Color? tab;

  const ThemePalette({
    required this.scheme,
    required this.scaffold,
    required this.card,
    required this.inputFill,
    required this.divider,
    required this.navBar,
    this.tab,
  });

  // ── «Классика»: прежние значения AppTheme (до 1.9.x) ──
  static const _brandBlue = Color(0xFF1D4F91);

  static ThemePalette _classicLight() => ThemePalette(
        scheme: ColorScheme.fromSeed(seedColor: _brandBlue).copyWith(
          primary: _brandBlue,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD9E5F6),
          onPrimaryContainer: const Color(0xFF0B2545),
          secondary: const Color(0xFF4A5A70),
          onSecondary: Colors.white,
          // Выбранные/активные элементы (навигация, чипы) — мягкая
          // голубая заливка с тёмно-синим текстом, без яркого акцента.
          secondaryContainer: const Color(0xFFDCE6F3),
          onSecondaryContainer: const Color(0xFF13263F),
          tertiary: const Color(0xFFA35A0B),
          onTertiary: Colors.white,
          surface: Colors.white,
          // Мягче (1.6.20): основной текст — тёмный графит, а не почти
          // чёрный; вторичный светлее (5,9:1 к белому — норма AA).
          onSurface: const Color(0xFF242A33),
          onSurfaceVariant: const Color(0xFF5A6472),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFF2F5F9),
          surfaceContainer: const Color(0xFFF0F3F7),
          surfaceContainerHigh: const Color(0xFFEAEEF3),
          surfaceContainerHighest: const Color(0xFFE3E8EF),
          outline: const Color(0xFF8A94A3),
          outlineVariant: const Color(0xFFE1E6EC),
        ),
        // Фон чуть темнее (1.6.20): белые карточки отделяются тоном, без рамки.
        scaffold: const Color(0xFFF2F5F9),
        card: Colors.white,
        // #E9EDF2: заметно и на фоне экрана, и на белой карточке.
        inputFill: const Color(0xFFE9EDF2),
        divider: const Color(0xFFEBEEF2),
        // Светло-серо-голубая, как фон экрана (1.8.0, «воздушный» вид).
        navBar: const Color(0xFFF7F9FC),
        tab: _brandBlue,
      );

  static ThemePalette _classicDark() => ThemePalette(
        scheme: ColorScheme.fromSeed(seedColor: _brandBlue, brightness: Brightness.dark).copyWith(
          primary: const Color(0xFF9DBDEB),
          onPrimary: const Color(0xFF0B2545),
          primaryContainer: const Color(0xFF233E63),
          onPrimaryContainer: const Color(0xFFD9E5F6),
          secondary: const Color(0xFFB4C1D3),
          onSecondary: const Color(0xFF1B2533),
          secondaryContainer: const Color(0xFF2A3A50),
          onSecondaryContainer: const Color(0xFFDCE6F3),
          tertiary: const Color(0xFFF0B866),
          onTertiary: const Color(0xFF3A2200),
          surface: const Color(0xFF161A20),
          onSurface: const Color(0xFFDCE1E8),
          onSurfaceVariant: const Color(0xFFA3ACB9),
          surfaceContainerLowest: const Color(0xFF101318),
          surfaceContainerLow: const Color(0xFF181D24),
          surfaceContainer: const Color(0xFF1D232B),
          surfaceContainerHigh: const Color(0xFF242B34),
          surfaceContainerHighest: const Color(0xFF2C343E),
          outline: const Color(0xFF7D8796),
          outlineVariant: const Color(0xFF2D343E),
        ),
        scaffold: const Color(0xFF12161B),
        // Карточка на ступень светлее фона (по умолчанию surfaceContainerLow
        // — 1.07:1 к фону).
        card: const Color(0xFF1D232B),
        inputFill: const Color(0xFF232A33),
        divider: const Color(0xFF262C35),
        // Чуть светлее фона экрана (#12161B) — панель отделена от ленты.
        navBar: const Color(0xFF1C2229),
      );

  /// Светлая палитра для [a].
  static ThemePalette light(Appearance a) => _build(a, Brightness.light);

  /// Тёмная палитра для [a] (AMOLED поверх неё делает AppTheme.amoledTheme).
  static ThemePalette dark(Appearance a) => _build(a, Brightness.dark);

  static ThemePalette _build(Appearance a, Brightness b) {
    final dark = b == Brightness.dark;
    final classic = dark ? _classicDark() : _classicLight();
    if (a.classicColors) return classic;
    final spec = PresetSpec.of(a.preset);
    // Серые поверхности — к тону темы (у «Классики» со своим акцентом —
    // прежние сине-серые).
    final keepNeutrals = a.preset == ThemePreset.classic;
    Color n(Color c) {
      if (keepNeutrals) return c;
      final h = HSLColor.fromColor(c);
      return HSLColor.fromAHSL(1, spec.neutralHue, (h.saturation * spec.neutralSat).clamp(0.0, 1.0), h.lightness)
          .toColor();
    }

    final s = classic.scheme;
    // Акцент как текст должен читаться на самой тёмной (в светлой теме) или
    // самой светлой (в тёмной) поверхности, где бывает текст.
    final base = a.accent != null ? Color(a.accent!) : spec.accent;
    final fitOn = n(s.surfaceContainerHighest);
    final p = dark ? AccentFit.dark(base, fitOn) : AccentFit.light(base, fitOn);
    final hp = HSLColor.fromColor(base);
    final hue = hp.hue;
    double sat(double max) => hp.saturation < max ? hp.saturation : max;
    Color c(double maxSat, double l) => AccentFit.hsl(hue, sat(maxSat), l);

    // Тон поворачивает и яркость: у зелёного и бирюзового та же «светлота»
    // HSL ярче, чем у сине-серого, — вторичный текст на самой тёмной
    // подложке опускался до 4,49:1. Текст — темнее (светлее), пока не AA.
    final backs = [n(s.surfaceContainerHighest), n(s.surfaceContainerLow), n(classic.scaffold)];
    Color text(Color c) {
      var h = HSLColor.fromColor(c);
      while (backs.any((bg) => AccentFit.contrast(h.toColor(), bg) < AccentFit.target) &&
          h.lightness > 0.02 &&
          h.lightness < 0.98) {
        h = h.withLightness(h.lightness + (dark ? 0.01 : -0.01));
      }
      return h.toColor();
    }

    final scheme = ColorScheme.fromSeed(seedColor: p, brightness: b).copyWith(
      primary: p,
      onPrimary: dark ? c(0.72, 0.14) : Colors.white,
      primaryContainer: dark ? c(0.48, 0.26) : c(0.65, 0.91),
      onPrimaryContainer: dark ? c(0.65, 0.91) : c(0.72, 0.16),
      secondary: dark ? c(0.24, 0.77) : c(0.20, 0.365),
      onSecondary: dark ? c(0.31, 0.15) : Colors.white,
      secondaryContainer: dark ? c(0.31, 0.24) : c(0.48, 0.91),
      onSecondaryContainer: dark ? c(0.48, 0.91) : c(0.54, 0.16),
      tertiary: s.tertiary,
      onTertiary: s.onTertiary,
      surface: n(s.surface),
      onSurface: text(n(s.onSurface)),
      onSurfaceVariant: text(n(s.onSurfaceVariant)),
      surfaceContainerLowest: n(s.surfaceContainerLowest),
      surfaceContainerLow: n(s.surfaceContainerLow),
      surfaceContainer: n(s.surfaceContainer),
      surfaceContainerHigh: n(s.surfaceContainerHigh),
      surfaceContainerHighest: n(s.surfaceContainerHighest),
      outline: n(s.outline),
      outlineVariant: n(s.outlineVariant),
    );
    return ThemePalette(
      scheme: scheme,
      scaffold: n(classic.scaffold),
      card: n(classic.card),
      inputFill: n(classic.inputFill),
      divider: n(classic.divider),
      navBar: n(classic.navBar),
      tab: dark ? null : p,
    );
  }

  /// Акцент темы [p] для показа на плитке и в образцах (светлый или тёмный).
  static Color accentOf(Appearance a, Brightness b) =>
      (b == Brightness.dark ? dark(a) : light(a)).scheme.primary;
}

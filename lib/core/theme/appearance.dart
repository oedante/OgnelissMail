// lib/core/theme/appearance.dart
// «Оформление» (1.9.x, просьба владельца 31.10.2026, «темы как в Telegram»):
// цветовая тема, акцент, оттенок фона ленты, скругление углов, плотность
// ленты и анимация открытия письма.
//
// Как это складывается в тему (AppTheme):
//  · «Классика» без своего акцента — прежний вид, цвет в цвет;
//  · цветовая тема задаёт тон фона и поверхностей и свой акцент, у
//    каждой — светлый и тёмный вариант; у «Полночи» тёмный — чистый чёрный;
//  · свой акцент заменяет акцент темы; яркость акцента подбирается так,
//    чтобы текст проходил WCAG AA (не ниже 4,5:1) — [AccentFit];
//  · «Цвета от обоев» (Android 12+), пока обои дают цвета, заменяют и
//    цветовую тему, и акцент; выбор темы или акцента их выключает;
//  · высокий контраст и «Чтение» — свои палитры: тема и акцент к ним не
//    применяются; скругление, плотность и анимация — применяются.
//
// Виджеты узнают плотность, оттенок ленты и анимацию через
// AppearanceLook.of(context) — из темы: строки ленты и так зависят от неё,
// поэтому новых подписок и лишних перестроений нет.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Цветовые темы. Порядок — порядок плиток на экране; в настройках
/// хранится имя ([name]), а не номер.
enum ThemePreset { classic, sky, ocean, forest, sunset, graphite, midnight }

/// Плотность ленты: строк на экране больше или меньше.
enum ListDensity { compact, normal, comfortable }

/// Скругление карточек, шторок и «пузырей» беседы.
enum CornerSize { small, medium, large }

/// Оттенок фона ленты и беседы цветом акцента.
enum ListTint { none, subtle, soft }

/// Тон фона и поверхностей темы и её собственный акцент.
class PresetSpec {
  /// Тон серых поверхностей (градусы HSL) и множитель их насыщенности:
  /// у «Классики» — сине-серый 214° как был, у «Графита» насыщенность 0.
  final double neutralHue;
  final double neutralSat;

  /// Акцент темы (кнопки, переключатели, подписи разделов): исходный цвет,
  /// яркость под светлую и тёмную тему подбирает [AccentFit].
  final Color accent;

  /// Тёмный вариант — чистый чёрный (AMOLED), как у «Полночи».
  final bool blackDark;

  const PresetSpec(this.neutralHue, this.neutralSat, this.accent, {this.blackDark = false});

  static const _specs = <ThemePreset, PresetSpec>{
    ThemePreset.classic: PresetSpec(214, 1.0, Color(0xFF1D4F91)),
    // «Небо» — светлее и голубее, как Telegram по умолчанию.
    ThemePreset.sky: PresetSpec(206, 1.35, Color(0xFF1C6FC0)),
    ThemePreset.ocean: PresetSpec(188, 1.05, Color(0xFF00737E)),
    ThemePreset.forest: PresetSpec(140, 0.65, Color(0xFF2B7A4B)),
    // «Закат» — тёплый кремовый фон и терракотовый акцент.
    ThemePreset.sunset: PresetSpec(28, 0.85, Color(0xFFB4501E)),
    // «Графит» — чистый серый без синевы и графитовый акцент.
    ThemePreset.graphite: PresetSpec(0, 0.0, Color(0xFF4F5866)),
    ThemePreset.midnight: PresetSpec(238, 0.9, Color(0xFF5155C9), blackDark: true),
  };

  static PresetSpec of(ThemePreset p) => _specs[p]!;
}

/// Готовые акценты (12) — исходные цвета; яркость под тему подбирает
/// [AccentFit]. Первый — синий «Классики».
const accentSwatches = <Color>[
  Color(0xFF1D4F91), // синий
  Color(0xFF1C76C9), // голубой
  Color(0xFF00838F), // бирюзовый
  Color(0xFF2E7D32), // зелёный
  Color(0xFF6B8E23), // оливковый
  Color(0xFFB7791F), // янтарный
  Color(0xFFD2691E), // оранжевый
  Color(0xFFC62828), // красный
  Color(0xFFC2185B), // малиновый
  Color(0xFF8E3FB5), // фиолетовый
  Color(0xFF4A4FC4), // индиго
  Color(0xFF546E7A), // сине-серый
];

/// Выбор пользователя целиком — одно значение для сборки тем.
@immutable
class Appearance {
  final ThemePreset preset;

  /// Свой акцент (ARGB) или null — акцент цветовой темы.
  final int? accent;
  final ListTint tint;
  final CornerSize corners;
  final ListDensity density;

  /// Анимация открытия письма — уже с учётом «Уменьшить движение» и
  /// системного «Убрать анимацию».
  final bool openAnimation;

  const Appearance({
    this.preset = ThemePreset.classic,
    this.accent,
    this.tint = ListTint.none,
    this.corners = CornerSize.medium,
    this.density = ListDensity.normal,
    this.openAnimation = false,
  });

  /// Прежний вид приложения.
  static const classic = Appearance();

  /// Цвета — прежние (тема «Классика» без своего акцента).
  bool get classicColors => preset == ThemePreset.classic && accent == null;

  /// Множитель скругления: малое — заметно строже, большое — мягче.
  double get radiusScale => switch (corners) {
    CornerSize.small => 0.5,
    CornerSize.medium => 1.0,
    CornerSize.large => 1.4,
  };

  Appearance copyWith({
    ThemePreset? preset,
    int? accent,
    bool clearAccent = false,
    ListTint? tint,
    CornerSize? corners,
    ListDensity? density,
    bool? openAnimation,
  }) => Appearance(
    preset: preset ?? this.preset,
    accent: clearAccent ? null : (accent ?? this.accent),
    tint: tint ?? this.tint,
    corners: corners ?? this.corners,
    density: density ?? this.density,
    openAnimation: openAnimation ?? this.openAnimation,
  );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.preset == preset &&
      other.accent == accent &&
      other.tint == tint &&
      other.corners == corners &&
      other.density == density &&
      other.openAnimation == openAnimation;

  @override
  int get hashCode => Object.hash(preset, accent, tint, corners, density, openAnimation);
}

/// Размеры строки письма по плотности (лента, беседа, архив).
@immutable
class DensitySpec {
  /// Поле строки сверху и снизу.
  final double padV;

  /// Радиус портрета в ленте.
  final double avatarRadius;

  /// Между строками текста (имя, тема, превью).
  final double lineGap;

  /// «Компактная»: при одной строке текста превью идёт в строке темы.
  final bool mergeSingleLine;

  const DensitySpec({
    required this.padV,
    required this.avatarRadius,
    required this.lineGap,
    this.mergeSingleLine = false,
  });

  /// Компактная: имя и время, ниже — тема и начало текста одной строкой
  /// (при «Строк текста» = 1); портрет 36 dp. Строка — не ниже 48 dp
  /// (область нажатия).
  static const compact = DensitySpec(padV: 2, avatarRadius: 18, lineGap: 1, mergeSingleLine: true);

  /// Обычная — как было до 1.9.x (поле 10 dp, в высоком контрасте — 8).
  static const normal = DensitySpec(padV: 10, avatarRadius: 24, lineGap: 2);

  /// Просторная: больше воздуха, портрет крупнее (при выборе — две строки
  /// текста, SettingsNotifier.setListDensity).
  static const comfortable = DensitySpec(padV: 14, avatarRadius: 26, lineGap: 4);

  static DensitySpec of(ListDensity d) => switch (d) {
    ListDensity.compact => compact,
    ListDensity.normal => normal,
    ListDensity.comfortable => comfortable,
  };

  /// Строк превью при настройке «Строк текста в ленте» [setting] (1–4); 0 —
  /// превью в строке темы. Число строк задаёт только настройка (1.10.2,
  /// замечание владельца: раньше «Компактная» и «Просторная» её
  /// перекрывали, и она будто не работала); плотность — поля и портреты.
  int previewFor(int setting) {
    final n = setting.clamp(1, 4);
    return mergeSingleLine && n == 1 ? 0 : n;
  }
}

/// Плотность, оттенок ленты и анимация — в теме, чтобы виджеты не
/// подписывались на настройки.
@immutable
class AppearanceLook extends ThemeExtension<AppearanceLook> {
  final ListDensity density;

  /// Фон ленты и беседы: null — цвет поверхности темы (без оттенка).
  final Color? listFill;

  /// Анимация открытия письма (общие портрет и тема, закрытие свайпом вниз).
  final bool openAnimation;

  const AppearanceLook({this.density = ListDensity.normal, this.listFill, this.openAnimation = false});

  static const plain = AppearanceLook();

  static AppearanceLook of(BuildContext context) => Theme.of(context).extension<AppearanceLook>() ?? plain;

  DensitySpec get spec => DensitySpec.of(density);

  @override
  AppearanceLook copyWith({ListDensity? density, Color? listFill, bool? openAnimation}) => AppearanceLook(
    density: density ?? this.density,
    listFill: listFill ?? this.listFill,
    openAnimation: openAnimation ?? this.openAnimation,
  );

  @override
  AppearanceLook lerp(covariant AppearanceLook? other, double t) {
    if (other == null) return this;
    // Цвет фона — плавно вместе с темой, остальное — переключением.
    final fill = (listFill == null && other.listFill == null) ? null : Color.lerp(listFill, other.listFill, t);
    final near = t < 0.5 ? this : other;
    return AppearanceLook(density: near.density, listFill: fill, openAnimation: near.openAnimation);
  }
}

/// Контраст и подбор яркости акцента (WCAG 2.1).
abstract final class AccentFit {
  /// Отношение контраста двух непрозрачных цветов: 1…21.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Запас над нормой AA (4,5:1): расчёт яркости округляет.
  static const target = 4.6;

  /// Акцент для светлой темы: тон и насыщенность [base], яркость — не выше
  /// 45 % и такая, чтобы и белый текст на акценте, и акцент как текст на
  /// фоне [on] проходили AA.
  static Color light(Color base, Color on) {
    var h = HSLColor.fromColor(base);
    if (h.lightness > 0.45) h = h.withLightness(0.45);
    while (h.lightness > 0.06 && (contrast(h.toColor(), on) < target || contrast(Colors.white, h.toColor()) < target)) {
      h = h.withLightness(h.lightness - 0.01);
    }
    return h.toColor();
  }

  /// Акцент для тёмной темы: светлый тон [base] (насыщенность — не выше
  /// 75 %, яркость — от 70 %), светлее, пока акцент как текст на самой
  /// светлой тёмной поверхности [on] не пройдёт AA.
  static Color dark(Color base, Color on) {
    var h = HSLColor.fromColor(base);
    h = h.withSaturation(math.min(h.saturation, 0.75)).withLightness(math.max(h.lightness, 0.70));
    while (h.lightness < 0.95 && contrast(h.toColor(), on) < target) {
      h = h.withLightness(h.lightness + 0.01);
    }
    return h.toColor();
  }

  /// Цвет тона [hue] с насыщенностью [sat] и яркостью [light] (0…1).
  static Color hsl(double hue, double sat, double light) =>
      HSLColor.fromAHSL(1, hue % 360, sat.clamp(0.0, 1.0), light.clamp(0.0, 1.0)).toColor();
}

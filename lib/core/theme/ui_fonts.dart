// lib/core/theme/ui_fonts.dart
//
// Шрифт интерфейса на выбор (1.10.2, просьба владельца 02.11.2026: Medeo
// Sans убрать, вместо него — стандартные многоязычные шрифты платформ).
//
// Кроме Roboto (он в пакете приложения, одинаков везде) — только шрифты,
// которые уже есть в системе: приложение их не распространяет, лицензии в
// «Тексты лицензий» не нужны. Все с латиницей, кириллицей и греческим;
// остальные письменности (арабская, иврит, деванагари, тайская, CJK)
// система подставляет сама, как и раньше.

import 'package:flutter/foundation.dart';

class UiFont {
  /// Значение настройки `uiFont`.
  final String id;

  /// Название шрифта; null — «Системный» (подпись из строк приложения).
  final String? label;

  /// Семейство для TextStyle; null — шрифт системы по умолчанию.
  final String? family;

  const UiFont(this.id, this.label, this.family);
}

abstract final class UiFonts {
  /// Roboto из пакета приложения (pubspec.yaml → fonts).
  static const robotoFamily = 'AppRoboto';

  static const system = UiFont('system', null, null);
  static const roboto = UiFont('roboto', 'Roboto', robotoFamily);

  /// Варианты на этой платформе: системный, Roboto и шрифты системы.
  static List<UiFont> forPlatform(TargetPlatform p) => switch (p) {
        // Android: псевдонимы семейств из fonts.xml системы — есть на всех
        // устройствах (у оболочек производителей — их замена).
        TargetPlatform.android || TargetPlatform.fuchsia => const [
            system,
            roboto,
            UiFont('serif', 'Noto Serif', 'serif'),
            UiFont('condensed', 'Roboto Condensed', 'sans-serif-condensed'),
          ],
        TargetPlatform.iOS || TargetPlatform.macOS => const [
            system,
            roboto,
            UiFont('helvetica', 'Helvetica Neue', 'Helvetica Neue'),
            UiFont('arial', 'Arial', 'Arial'),
            UiFont('georgia', 'Georgia', 'Georgia'),
          ],
        TargetPlatform.windows => const [
            system,
            roboto,
            UiFont('arial', 'Arial', 'Arial'),
            UiFont('calibri', 'Calibri', 'Calibri'),
            UiFont('verdana', 'Verdana', 'Verdana'),
            UiFont('georgia', 'Georgia', 'Georgia'),
          ],
        TargetPlatform.linux => const [
            system,
            roboto,
            UiFont('noto_sans', 'Noto Sans', 'Noto Sans'),
            UiFont('dejavu', 'DejaVu Sans', 'DejaVu Sans'),
            UiFont('noto_serif', 'Noto Serif', 'Noto Serif'),
          ],
      };

  /// Выбранный шрифт на этой платформе; неизвестный (настройки с другого
  /// устройства, прежний Medeo Sans) — Roboto.
  static UiFont resolve(String id, TargetPlatform p) =>
      forPlatform(p).where((f) => f.id == id).firstOrNull ?? roboto;

  /// Все известные значения настройки (для проверки при сохранении).
  static final Set<String> ids = {
    for (final p in TargetPlatform.values)
      for (final f in forPlatform(p)) f.id,
  };

  /// Образец под названием шрифта: латиница, кириллица, греческий, цифры.
  static const sample = 'Aa Бб Γγ 0123';
}

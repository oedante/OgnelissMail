// lib/core/theme/tokens.dart
// Дизайн-токены (этап 4, docs/plan/UI_REDESIGN.md). Значения — из Ogneliss
// Dialer 1.3.4. В экранах чисел нет: отступы, радиусы и размеры берутся
// отсюда, цвета — из ролей ColorScheme.

import 'package:flutter/widgets.dart';

/// Шкала отступов.
abstract final class Space {
  /// Под подписью раздела («воздушный» вид, 1.8.0).
  static const xxs = 2.0;
  /// Между карточками, значок — подпись.
  static const xs = 4.0;
  /// Внутри групп, вертикальное поле строки.
  static const s = 8.0;
  /// Поля экрана, между блоками панели.
  static const m = 12.0;
  /// Горизонтальное поле карточки.
  static const l = 16.0;
  /// Между разделами, низ шторки.
  static const xl = 24.0;
  /// Пустые состояния.
  static const xxl = 32.0;
}

/// Радиусы скругления.
abstract final class Radii {
  /// Плашки, чипы. Мягкий стиль 1.6.20: 12 (было 8).
  static const chip = 12.0;
  /// Карточки-группы, первая и последняя строки внутри карточки.
  /// Мягкий стиль 1.6.20: 20 (было 16).
  static const card = 20.0;
  /// Шторки, верх нижней панели.
  static const panel = 28.0;

  static const chipAll = BorderRadius.all(Radius.circular(chip));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const panelTop = BorderRadius.vertical(top: Radius.circular(panel));
}

/// Размеры элементов.
abstract final class Sizes {
  /// Минимальная область нажатия.
  static const tapTarget = 48.0;
  /// Строка письма: две строки текста.
  static const mailRow = 72.0;
  /// Строка письма с превью.
  static const mailRowPreview = 88.0;
  /// Аватар отправителя (48 — в крупном режиме).
  static const avatar = 40.0;
  static const avatarLarge = 48.0;
  /// Кнопка «Написать».
  static const composeButton = 56.0;
  /// Кнопка нижней панели — пилюля.
  static const panelPillWidth = 56.0;
  static const panelPillHeight = 32.0;
  /// Слот аватара ящика слева в нижней панели телефона.
  static const bottomLeadingWidth = 52.0;
  /// Иконки: обычная, в строке письма, в тексте.
  static const icon = 24.0;
  static const iconRow = 20.0;
  static const iconInline = 18.0;
}

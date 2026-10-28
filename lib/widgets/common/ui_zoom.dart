// lib/widgets/common/ui_zoom.dart
//
// Масштаб интерфейса (1.6.12). Вёрстка рассчитана на телефон шириной около
// 412 dp при обычном шрифте. На экранах уже (iPhone 390–393 dp, iPhone SE и
// mini 375, Android с крупным «Размером экрана» — 360 и меньше) и с крупным
// шрифтом строки, чипы и кнопки не помещались и наезжали друг на друга
// (замечание 17.10.2026; журналы: OnePlus 363 dp — тесно, nubia 438 dp с
// шрифтом ×0,85 — всё помещается).
//
// Масштаб применяется ко всему приложению сразу: экран считается шире на
// 1/zoom, а картинка уменьшается в zoom раз (FittedBox — касания пересчитываются
// вместе с ним). Пропорции элементов сохраняются, ничего не обрезается.

import 'package:flutter/widgets.dart';

abstract final class UiZoom {
  /// Ширина, под которую сверстан интерфейс (dp, обычный шрифт).
  static const double referenceWidth = 412;

  /// Меньше — текст становится слишком мелким.
  static const double minAuto = 0.85;

  /// Варианты вручную («Настройки → Общие → Масштаб интерфейса»).
  static const manual = <double>[0.85, 0.9, 0.95, 1.0, 1.1];

  /// Масштаб «Авто»: по короткой стороне экрана (не меняется при повороте)
  /// и размеру шрифта. Крупный шрифт учитывается наполовину: он выбран ради
  /// крупного текста, и уменьшать его полностью было бы неправильно.
  static double auto(Size size, double textScale) {
    final side = size.shortestSide;
    if (side <= 0 || side >= 600) return 1.0; // планшеты и компьютеры
    final t = textScale <= 1 ? textScale : 1 + (textScale.clamp(1.0, 1.6) - 1) / 2;
    final z = side / (referenceWidth * t);
    if (z >= 0.97) return 1.0; // разница незаметна — не трогаем
    // Шаг 1 %: чтобы масштаб не «дрожал» от мелких изменений размера окна.
    return (z.clamp(minAuto, 1.0) * 100).floorToDouble() / 100;
  }

  /// Итоговый масштаб: [setting] 0 — авто, иначе выбранный вручную.
  static double resolve(double setting, Size size, double textScale) =>
      setting > 0 ? setting.clamp(0.85, 1.1).toDouble() : auto(size, textScale);

  /// Данные экрана в масштабированных единицах: размер и системные отступы
  /// делятся на [zoom], плотность пикселей умножается (картинки и шрифты
  /// растеризуются в полном разрешении экрана).
  static MediaQueryData scaleData(MediaQueryData mq, double zoom) {
    if (isIdentity(zoom)) return mq;
    return mq.copyWith(
      size: mq.size / zoom,
      devicePixelRatio: mq.devicePixelRatio * zoom,
      padding: mq.padding / zoom,
      viewPadding: mq.viewPadding / zoom,
      viewInsets: mq.viewInsets / zoom,
      systemGestureInsets: mq.systemGestureInsets / zoom,
    );
  }

  static bool isIdentity(double zoom) => (zoom - 1).abs() < 0.005;

  /// Масштаб, с которым приложение рисуется сейчас (для подписи в настройках).
  static double current = 1.0;
}

/// Рисует [child] в масштабе [zoom]: даёт ему место размером «доступное / zoom»
/// и вписывает обратно. MediaQuery для [child] — [UiZoom.scaleData].
class UiZoomBox extends StatelessWidget {
  final double zoom;
  final Widget child;

  const UiZoomBox({super.key, required this.zoom, required this.child});

  @override
  Widget build(BuildContext context) {
    // Структура дерева одна и та же при любом масштабе: смена масштаба в
    // настройках не должна пересоздавать навигатор и открытые экраны.
    final z = UiZoom.isIdentity(zoom) ? 1.0 : zoom;
    return LayoutBuilder(builder: (context, c) {
      final size = MediaQuery.sizeOf(context);
      final w = c.hasBoundedWidth ? c.maxWidth : size.width * z;
      final h = c.hasBoundedHeight ? c.maxHeight : size.height * z;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(width: w / z, height: h / z, child: child),
        ),
      );
    });
  }
}

/// Встроенное системное окно (WebView на Android) — без масштаба интерфейса.
///
/// Android рисует «каплю» под курсором, ручки выделения и лупу сам, по
/// координатам окна, не зная о масштабе, с которым Flutter его уменьшил: при
/// масштабе 0,9 капля уезжала от курсора тем дальше, чем правее и ниже он
/// стоял (замечание 28.10.2026). Окно получает место «доступное × zoom» и
/// обратный масштаб — на экране оно занимает то же место, но в масштабе 1, и
/// системные ручки встают на место. Содержимое уменьшает сама страница
/// (viewport письма, textZoom редактора).
///
/// Структура дерева одна при любом [zoom]: смена масштаба не пересоздаёт окно.
class UiZoomUndo extends StatelessWidget {
  final double zoom;
  final Widget child;

  const UiZoomUndo({super.key, required this.zoom, required this.child});

  @override
  Widget build(BuildContext context) {
    final z = UiZoom.isIdentity(zoom) ? 1.0 : zoom;
    return LayoutBuilder(builder: (context, c) {
      // Окно письма и редактор всегда в ограниченном месте; на случай
      // неограниченного — без пересчёта.
      final w = c.hasBoundedWidth ? c.maxWidth : null;
      final h = c.hasBoundedHeight ? c.maxHeight : null;
      return SizedBox(
        width: w,
        height: h,
        child: Transform.scale(
          scale: 1 / z,
          alignment: Alignment.topLeft,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w == null ? null : w * z,
            maxWidth: w == null ? null : w * z,
            minHeight: h == null ? null : h * z,
            maxHeight: h == null ? null : h * z,
            child: child,
          ),
        ),
      );
    });
  }
}

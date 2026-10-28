// lib/widgets/common/calendar_day_icon.dart
// Значок календаря с числом дня: вкладка «Календарь» на нижней панели (и в
// боковой на планшете) и кнопка «Сегодня» в шапке календаря (1.7.2+108,
// замечание владельца 24.10.2026: на нижней панели число стояло на нижней
// границе значка, а не посередине).
//
// Число — по центру «листа» значка calendar_today, пустой части под полосой
// с кольцами. В сетке Material Symbols (960 × 960) лист занимает по высоте
// 400..800, по ширине 200..760: центр — на 5/8 высоты и посередине ширины.
// Строка числа высотой ровно в кегль (height: 1, поровну сверху и снизу) —
// цифры Roboto стоят посередине такой строки. Раньше число прижималось к
// низу значка (bottom: 1) и наследовало высоту строки темы — цифры ложились
// на нижнюю рамку, а с крупным системным шрифтом вылезали за неё.
//
// Размер числа — от размера значка, крупный системный шрифт его не меняет;
// шрифт — всегда Roboto приложения (у OpenDyslexic другие пропорции цифр).
// Цвет — как у значка: выбранная вкладка, шапка, тёмная тема.
//
// Без числа в параметрах — сегодняшнее, и в полночь значок сменит его сам
// (и при возврате в приложение — если часы или пояс телефона поменяли):
// раньше число бралось при перестройке панели и после полуночи могло
// остаться вчерашним.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart' show AppTheme;

class CalendarDayIcon extends StatefulWidget {
  /// Число месяца (1..31); null — сегодняшнее, меняется в полночь.
  final int? day;

  /// Цвет значка и числа; по умолчанию — из IconTheme.
  final Color? color;

  /// Размер значка; по умолчанию — из IconTheme (24).
  final double? size;

  const CalendarDayIcon({super.key, this.day, this.color, this.size});

  /// Лист значка в долях высоты: 400/960 и 800/960.
  static const sheetTop = 400 / 960;
  static const sheetBottom = 800 / 960;

  /// Кегль числа в долях размера значка: «24» и «31» помещаются в лист
  /// с одинаковым запасом по ширине и высоте.
  static const digitScale = 0.38;

  @override
  State<CalendarDayIcon> createState() => _CalendarDayIconState();
}

class _CalendarDayIconState extends State<CalendarDayIcon> with WidgetsBindingObserver {
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  /// Таймер считает по ходу времени, а не по часам телефона: перевели часы
  /// или сменился пояс — число обновится при возврате в приложение.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || widget.day != null || !mounted) return;
    setState(() {});
    _schedule();
  }

  @override
  void didUpdateWidget(covariant CalendarDayIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.day == null) != (widget.day == null)) _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  /// Перестроиться в начале следующих суток (секунда запаса — чтобы часы
  /// точно показали новый день). Свёрнутое приложение получит срабатывание
  /// при возврате.
  void _schedule() {
    _midnight?.cancel();
    _midnight = null;
    if (widget.day != null) return;
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = widget.size ?? iconTheme.size ?? 24;
    final color = widget.color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    final day = widget.day ?? DateTime.now().day;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          // Без заливки и в выбранной вкладке: залитый лист скрыл бы число.
          Positioned.fill(child: Icon(AppIcons.calendar_today, size: size, color: color, fill: 0)),
          Positioned(
            left: 0,
            right: 0,
            top: size * CalendarDayIcon.sheetTop,
            bottom: size * (1 - CalendarDayIcon.sheetBottom),
            child: Center(
              child: Text(
                '$day',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  inherit: false,
                  fontFamily: AppTheme.fontFamily,
                  fontSize: size * CalendarDayIcon.digitScale,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

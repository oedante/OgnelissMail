// lib/widgets/common/adaptive_layout.dart
// Адаптивный layout для телефонов, планшетов, складных и компьютеров.
//
// 1.6.28 (PLAN п. 25–26):
//  · деление на «список + панель» решается по ширине ОБЛАСТИ, а не по
//    размеру устройства: окно Windows шириной 1000 и высотой 600 — две
//    панели, планшет в разделённом экране шириной 500 — одна. Раньше нажатие
//    решало по короткой стороне экрана, а раскладка — по ширине, и на
//    широком низком окне письмо открывалось отдельным экраном;
//  · на широком окне панель есть всегда — до выбора с подсказкой «Выберите
//    письмо», лента не прыгает по ширине;
//  · ширину списка можно менять, потянув за разделитель (мышью или пальцем),
//    она запоминается для каждого раздела;
//  · складной телефон: вертикальный сгиб («книжка») — список слева от него,
//    панель справа; горизонтальный («ноутбук», полураскрыт на столе) —
//    список сверху, панель снизу; на сам сгиб ничего не попадает.

import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Breakpoints {
  static const double phone = 600;
  static const double tablet = 840;
  static const double desktop = 1200;

  /// С этой ширины области — список и панель рядом.
  static const double split = 720;
}

/// Сообщает потомкам, показаны ли список и панель рядом.
class _SplitScope extends InheritedWidget {
  final bool split;
  const _SplitScope({required this.split, required super.child});

  @override
  bool updateShouldNotify(_SplitScope old) => old.split != split;
}

class AdaptiveLayout extends StatefulWidget {
  final Widget body;
  final Widget? detailBody;
  final bool showDetail;
  final double splitRatio;

  /// Ключ, под которым запоминается ширина списка (лента, контакты…).
  /// null — не запоминать.
  final String? widthKey;

  /// Что показать в панели, пока ничего не выбрано. null — до выбора
  /// список занимает всю ширину (как раньше).
  final Widget? placeholder;

  const AdaptiveLayout({
    super.key,
    required this.body,
    this.detailBody,
    this.showDetail = false,
    this.splitRatio = 0.38,
    this.widthKey,
    this.placeholder,
  });

  /// Список и панель сейчас рядом (вызывать из потомков списка): нажатие на
  /// строку открывает её в панели, а не отдельным экраном.
  static bool isSplit(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_SplitScope>()?.split ?? false;

  /// То же при построении: виджет перестроится, если раскладка сменится.
  static bool splitOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SplitScope>()?.split ?? false;

  /// Хватит ли области шириной [width] на список и панель.
  static bool canSplit(double width) => width >= Breakpoints.split;

  /// Вертикальный сгиб или шарнир экрана внутри области шириной [width]
  /// (её левый край — у правого края боковой навигации): положение и ширина
  /// относительно области. null — сгиба нет или он горизонтальный («ноутбук»).
  static ({double left, double width})? verticalHinge(BuildContext context, double width) {
    final mq = MediaQuery.of(context);
    final offset = mq.size.width - width; // боковая навигация слева
    for (final f in mq.displayFeatures) {
      if (f.type != DisplayFeatureType.fold && f.type != DisplayFeatureType.hinge) continue;
      final b = f.bounds;
      final vertical = b.height >= b.width && b.height >= mq.size.height * 0.5;
      if (!vertical) continue;
      final left = b.left - offset;
      // Слишком узкая колонка слева — не делим по сгибу.
      if (left < 280 || left > width - 280) continue;
      return (left: left, width: b.width);
    }
    return null;
  }

  /// Горизонтальный сгиб («ноутбук»: телефон полураскрыт и стоит на столе)
  /// внутри области высотой [height], отсчёт от её верха. null — нет.
  static ({double top, double height})? horizontalHinge(BuildContext context, double height) {
    final mq = MediaQuery.of(context);
    final offset = mq.size.height - height; // шапка и панели сверху
    for (final f in mq.displayFeatures) {
      if (f.type != DisplayFeatureType.fold && f.type != DisplayFeatureType.hinge) continue;
      final b = f.bounds;
      final horizontal = b.width > b.height && b.width >= mq.size.width * 0.5;
      if (!horizontal) continue;
      final top = b.top - offset;
      if (top < 160 || top > height - 160) continue;
      return (top: top, height: b.height);
    }
    return null;
  }

  static bool isTablet(BuildContext context) => MediaQuery.of(context).size.shortestSide >= Breakpoints.phone;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= Breakpoints.desktop;

  @override
  State<AdaptiveLayout> createState() => _AdaptiveLayoutState();
}

class _AdaptiveLayoutState extends State<AdaptiveLayout> {
  /// Доля ширины под список, выбранная пользователем (null — по умолчанию).
  double? _ratio;

  static const _minList = 280.0;
  static const _minDetail = 360.0;

  String? get _prefKey => widget.widthKey == null ? null : 'split_ratio_${widget.widthKey}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final k = _prefKey;
    if (k == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getDouble(k);
      if (v != null && mounted) setState(() => _ratio = v);
    } catch (_) {}
  }

  Future<void> _save() async {
    final k = _prefKey;
    final v = _ratio;
    if (k == null || v == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(k, v);
    } catch (_) {}
  }

  double _listWidth(double total) {
    final def = total >= Breakpoints.desktop ? total * 0.34 : total * widget.splitRatio;
    final w = _ratio == null ? def.clamp(320.0, 440.0) : total * _ratio!;
    final max = total - _minDetail;
    return w.clamp(_minList, max < _minList ? _minList : max);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final detail = (widget.showDetail ? widget.detailBody : null) ?? widget.placeholder;
        final split = AdaptiveLayout.canSplit(total) && detail != null;
        if (!split) {
          // Складной телефон «ноутбуком» (полураскрыт на столе): лента
          // сверху, письмо снизу, сгиб между ними — даже на узкой ширине.
          final h = widget.showDetail && widget.detailBody != null
              ? AdaptiveLayout.horizontalHinge(context, constraints.maxHeight)
              : null;
          if (h != null) {
            return _SplitScope(
              split: true,
              child: Column(children: [
                SizedBox(height: h.top, child: widget.body),
                SizedBox(height: h.height),
                Expanded(child: widget.detailBody!),
              ]),
            );
          }
          // Места на две панели хватает, но выбирать ещё нечего: нажатие на
          // строку откроет её в панели.
          return _SplitScope(split: AdaptiveLayout.canSplit(total), child: widget.body);
        }

        // Складной телефон «книжкой»: вертикальный сгиб — список слева от
        // него, панель справа, на сам сгиб ничего не попадает.
        final hinge = AdaptiveLayout.verticalHinge(context, total);
        if (hinge != null) {
          return _SplitScope(
            split: true,
            child: Row(
              children: [
                SizedBox(width: hinge.left, child: widget.body),
                SizedBox(width: hinge.width),
                Expanded(child: detail),
              ],
            ),
          );
        }

        final listWidth = _listWidth(total);
        return _SplitScope(
          split: true,
          child: Row(
            children: [
              SizedBox(width: listWidth, child: widget.body),
              // Разделитель тянется мышью и пальцем; двойное нажатие —
              // ширина по умолчанию.
              PaneSplitter(
                onDrag: (dx) => setState(() {
                  final w = (listWidth + dx).clamp(_minList, total - _minDetail);
                  _ratio = w / total;
                }),
                onDragEnd: _save,
                onReset: () {
                  setState(() => _ratio = null);
                  final k = _prefKey;
                  if (k != null) {
                    SharedPreferences.getInstance().then((p) => p.remove(k)).ignore();
                  }
                },
              ),
              Expanded(child: detail),
            ],
          ),
        );
      },
    );
  }
}

/// Вертикальный разделитель панелей: тянется мышью, пальцем и пером, курсор
/// «изменить ширину» при наведении, двойное нажатие — ширина по умолчанию.
/// Общий у «лента | письмо» и «папки | лента» (1.9.x, просьба владельца
/// 31.10.2026: панели на компьютере и планшете — своей ширины).
class PaneSplitter extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;
  final VoidCallback? onReset;

  const PaneSplitter({super.key, required this.onDrag, this.onDragEnd, this.onReset});

  @override
  State<PaneSplitter> createState() => _PaneSplitterState();
}

class _PaneSplitterState extends State<PaneSplitter> {
  bool _dragging = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _dragging || _hover;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.trackpad,
        },
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        onDoubleTap: widget.onReset,
        child: SizedBox(
          width: 9,
          child: Center(
            child: Container(
              width: active ? 3 : 1,
              color: _dragging
                  ? theme.colorScheme.primary
                  : _hover
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}

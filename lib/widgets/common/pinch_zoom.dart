// lib/widgets/common/pinch_zoom.dart
// Увеличение разведением пальцев (1.8.0, просьба владельца 26.10.2026:
// «увеличивать тело письма при просмотре разведением пальцев и сжимать
// обратно до стандартных габаритов — иногда попадаются мелкие детали в
// виде таблиц или картинок»).
//
// Для писем, которые рисуются виджетами (MailNativeBody); письма в окне
// браузера увеличиваются самим браузером (MailHtmlView).
//
// Как устроено:
//  · два пальца — сразу этому виджету (одним пальцем экран листается как
//    обычно, выделение текста работает);
//  · содержимое размечается в обычную ширину и рисуется увеличенным; место
//    по высоте растёт вместе с масштабом — увеличенное письмо листается
//    экраном письма, а вбок — само (только пока увеличено: иначе жест вбок
//    листает письма);
//  · точка между пальцами остаётся под пальцами;
//  · масштаб — от обычного до ×4; меньше обычного не уменьшается, у самого
//    обычного «прилипает»; «Обычный размер» над письмом — сразу назад.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_icons.dart';

class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.child,
    this.maxScale = 4,
    this.resetLabel,
  });

  final Widget child;

  /// Наибольшее увеличение.
  final double maxScale;

  /// Подпись кнопки «Обычный размер» над увеличенным содержимым (null — без
  /// кнопки).
  final String? resetLabel;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> with SingleTickerProviderStateMixin {
  final _h = ScrollController();
  final _boxKey = GlobalKey();
  double _scale = 1;

  // Начало щипка.
  double _startScale = 1;

  // Анимация «Обычный размер».
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(_onAnim);
  double _animFrom = 1;

  bool get _zoomed => _scale > 1.001;

  @override
  void dispose() {
    _anim.dispose();
    _h.dispose();
    super.dispose();
  }

  void _onStart(Offset focal) {
    _anim.stop();
    _startScale = _scale;
  }

  void _onUpdate(double factor, Offset focal) {
    final next = (_startScale * factor).clamp(1.0, widget.maxScale);
    _setScale(next, focal);
  }

  void _onEnd() {
    // У обычного размера — «прилипает» к нему.
    if (_scale < 1.06 && _scale != 1) _setScale(1, null);
  }

  void _reset() {
    if (!_zoomed) return;
    _animFrom = _scale;
    _anim.forward(from: 0);
  }

  void _onAnim() {
    final t = Curves.easeOut.transform(_anim.value);
    _setScale(_animFrom + (1 - _animFrom) * t, null);
  }

  /// Новый масштаб; [focal] (глобальные координаты) остаётся на месте.
  void _setScale(double next, Offset? focal) {
    final prev = _scale;
    if ((next - prev).abs() < 0.0005) return;
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    final outer = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    // Точка под пальцами — в координатах увеличенного содержимого.
    Offset? local;
    if (focal != null && box != null && box.hasSize) local = box.globalToLocal(focal);
    final hx = _h.hasClients ? _h.offset : 0.0;
    final oy = outer?.pixels;
    setState(() => _scale = next);
    if (next <= 1.0001) {
      if (_h.hasClients) _h.jumpTo(0);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = next / prev;
      // По горизонтали: та же точка содержимого под пальцами.
      if (_h.hasClients) {
        final viewportX = local == null ? _h.position.viewportDimension / 2 : local.dx - hx;
        final target = (hx + viewportX) * r - viewportX;
        final p = _h.position;
        _h.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
      }
      // По вертикали: содержимое растёт вниз от верха письма — экран
      // письма сдвигается настолько, насколько ушла точка под пальцами.
      if (outer != null && oy != null && local != null && outer.hasContentDimensions) {
        final target = oy + local.dy * (r - 1);
        outer.jumpTo(target.clamp(outer.minScrollExtent, outer.maxScrollExtent));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (!box.maxWidth.isFinite) return widget.child;
      final width = box.maxWidth;
      final label = widget.resetLabel;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_zoomed && label != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _reset,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(AppIcons.fit_screen, size: 18),
                label: Text(label),
              ),
            ),
          RawGestureDetector(
            gestures: <Type, GestureRecognizerFactory>{
              _PinchRecognizer: GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
                _PinchRecognizer.new,
                (r) => r
                  ..onStart = _onStart
                  ..onUpdate = _onUpdate
                  ..onEnd = _onEnd,
              ),
            },
            child: SingleChildScrollView(
              controller: _h,
              scrollDirection: Axis.horizontal,
              // Не увеличено — вбок листать нечего: жест вбок остаётся
              // листанию писем.
              physics: _zoomed ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(),
              child: _ScaledBox(
                key: _boxKey,
                scale: _scale,
                baseWidth: width,
                child: widget.child,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// Содержимое шириной [baseWidth], нарисованное в [scale] раз крупнее; сам
/// виджет занимает увеличенное место.
class _ScaledBox extends SingleChildRenderObjectWidget {
  const _ScaledBox({super.key, required this.scale, required this.baseWidth, super.child});

  final double scale;
  final double baseWidth;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScaledBox(scale, baseWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderScaledBox renderObject) {
    renderObject
      ..scale = scale
      ..baseWidth = baseWidth;
  }
}

class _RenderScaledBox extends RenderProxyBox {
  _RenderScaledBox(this._scale, this._baseWidth);

  double _scale;
  double get scale => _scale;
  set scale(double v) {
    if (v == _scale) return;
    _scale = v;
    markNeedsLayout();
  }

  double _baseWidth;
  set baseWidth(double v) {
    if (v == _baseWidth) return;
    _baseWidth = v;
    markNeedsLayout();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.constrain(Size.zero);
      return;
    }
    c.layout(BoxConstraints.tightFor(width: _baseWidth), parentUsesSize: true);
    size = constraints.constrain(Size(c.size.width * _scale, c.size.height * _scale));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(_baseWidth) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(_baseWidth) ?? 0) * _scale;

  @override
  double computeMinIntrinsicWidth(double height) => _baseWidth * _scale;

  @override
  double computeMaxIntrinsicWidth(double height) => _baseWidth * _scale;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.constrain(Size.zero);
    final s = c.getDryLayout(BoxConstraints.tightFor(width: _baseWidth));
    return constraints.constrain(Size(s.width * _scale, s.height * _scale));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (_scale == 1) {
      context.paintChild(c, offset);
      layer = null;
      return;
    }
    layer = context.pushTransform(needsCompositing, offset, _transform, (ctx, o) => ctx.paintChild(c, o),
        oldLayer: layer is TransformLayer ? layer as TransformLayer : null);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, p) => c.hitTest(result, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

/// Щипок двумя пальцами: с первым пальцем ничего не забирает (экран
/// листается, текст выделяется), со вторым — забирает оба.
class _PinchRecognizer extends OneSequenceGestureRecognizer {
  void Function(Offset focal)? onStart;
  void Function(double factor, Offset focal)? onUpdate;
  VoidCallback? onEnd;

  final Map<int, Offset> _pos = <int, Offset>{};
  double _startSpan = 0;
  bool _active = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pos[event.pointer] = event.position;
    if (_pos.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void acceptGesture(int pointer) {
    super.acceptGesture(pointer);
    if (!_active && _pos.length >= 2) {
      _active = true;
      _startSpan = _span();
      onStart?.call(_focal());
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (_pos.containsKey(event.pointer)) _pos[event.pointer] = event.position;
      if (_active && _pos.length >= 2 && _startSpan > 0) onUpdate?.call(_span() / _startSpan, _focal());
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pos.remove(event.pointer);
      if (_active && _pos.length < 2) {
        _active = false;
        onEnd?.call();
      }
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  List<Offset> get _two => _pos.values.take(2).toList();
  double _span() {
    final p = _two;
    return p.length < 2 ? 0 : (p[0] - p[1]).distance;
  }

  Offset _focal() {
    final p = _two;
    return p.length < 2 ? (p.isEmpty ? Offset.zero : p.first) : (p[0] + p[1]) / 2;
  }

  @override
  void rejectGesture(int pointer) {
    _pos.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    if (_active) {
      _active = false;
      onEnd?.call();
    }
    _pos.clear();
  }

  @override
  String get debugDescription => 'pinch zoom';
}

// lib/features/compose/screens/image_edit_screen.dart
// Обрезка и поворот фото перед отправкой (1.7.2+113, просьба владельца
// 25.10.2026: «небольшой редактор изображений — только обрезка и поворот»).
// Открывается из карточки фото в письме («Обрезать и повернуть»).
//
// Снимок — на тёмном фоне, поверх — рамка: углы и края тянутся, внутри
// рамку можно передвинуть; пока тянут — сетка третей. «Повернуть» — на
// четверть оборота против часовой стрелки, рамка поворачивается вместе со
// снимком; «Сбросить» — как было. «Готово» — правка применяется
// (`ImageEdit.apply`), экран возвращает новое имя и байты; ничего не
// меняли или «×» — null.
//
// Круглый режим ([circle], 1.15.1, просьба владельца 07.11.2026: «при выборе
// фото контакта — обрезка и поворот, как для фото в письме, но с просмотром,
// как оно будет смотреться в круге»): рамка квадратная (тянется за углы,
// двигается целиком), вне круга — затемнение, под снимком — живой просмотр в
// кружках тех размеров, что в ленте, шапке письма и карточке человека.
// «Готово» без правки возвращает исходный снимок (а не null — это отмена).

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/image_edit.dart';
import '../../../widgets/common/inline_notice.dart' show quietError;

/// Что тянут пальцем: угол, край или всю рамку.
enum _Grip { topLeft, topRight, bottomLeft, bottomRight, left, top, right, bottom, move }

class ImageEditScreen extends StatefulWidget {
  final Uint8List bytes;
  final String name;

  /// Круглый портрет (фото ящика, контакта): квадратная рамка, круг и
  /// просмотр в кружках.
  final bool circle;
  const ImageEditScreen({super.key, required this.bytes, required this.name, this.circle = false});

  /// Открыть редактор. null — ничего не меняли или передумали; в круглом
  /// режиме null — только отмена.
  static Future<({String name, Uint8List bytes})?> open(BuildContext context,
          {required Uint8List bytes, required String name, bool circle = false}) =>
      Navigator.of(context).push<({String name, Uint8List bytes})>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditScreen(bytes: bytes, name: name, circle: circle),
      ));

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<ImageEditScreen> {
  /// Снимок для экрана (не больше 2048 точек по ширине — экономия памяти);
  /// правка применяется к исходному файлу.
  ui.Image? _image;
  bool _failed = false;
  bool _busy = false;

  /// Четверти оборота по часовой стрелке (0–3).
  int _turns = 0;

  /// Рамка — доли повёрнутого снимка.
  Rect _crop = ImageEdit.full;

  _Grip? _grip;

  /// Где снимок на экране (последняя раскладка).
  Rect _dest = Rect.zero;

  bool get _changed => _turns != 0 || _crop != ImageEdit.full;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes, targetWidth: 2048, allowUpscaling: false);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        if (widget.circle) _crop = _centerSquare();
      });
    } catch (e) {
      AppLogger.warning('Правка фото: «${widget.name}» не открылось — $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  /// Размер повёрнутого снимка в точках.
  Size get _rotated {
    final image = _image!;
    return _turns.isOdd
        ? Size(image.height.toDouble(), image.width.toDouble())
        : Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Наибольший квадрат по центру повёрнутого снимка — в долях.
  Rect _centerSquare() {
    final r = _rotated;
    final side = math.min(r.width, r.height);
    final w = side / r.width, h = side / r.height;
    return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
  }

  /// Место снимка в области [box]: целиком, по центру, с полями под углы рамки.
  Rect _fit(Size box) {
    final image = _image;
    if (image == null) return Rect.zero;
    final odd = _turns.isOdd;
    final rw = (odd ? image.height : image.width).toDouble();
    final rh = (odd ? image.width : image.height).toDouble();
    const pad = Space.xl;
    final aw = math.max(1.0, box.width - 2 * pad);
    final ah = math.max(1.0, box.height - 2 * pad);
    final k = math.min(aw / rw, ah / rh);
    final w = rw * k, h = rh * k;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Rect _cropOnScreen(Rect d) => Rect.fromLTRB(
        d.left + _crop.left * d.width,
        d.top + _crop.top * d.height,
        d.left + _crop.right * d.width,
        d.top + _crop.bottom * d.height,
      );

  _Grip? _hit(Offset p) {
    final c = _cropOnScreen(_dest);
    const corner = 36.0, edge = 24.0;
    bool near(Offset a) => (p - a).distance <= corner;
    if (near(c.topLeft)) return _Grip.topLeft;
    if (near(c.topRight)) return _Grip.topRight;
    if (near(c.bottomLeft)) return _Grip.bottomLeft;
    if (near(c.bottomRight)) return _Grip.bottomRight;
    // Круг — только углы и перенос: край квадрата поменял бы пропорции.
    if (widget.circle) return c.inflate(edge).contains(p) ? _Grip.move : null;
    final inV = p.dy >= c.top - edge && p.dy <= c.bottom + edge;
    final inH = p.dx >= c.left - edge && p.dx <= c.right + edge;
    if (inV && (p.dx - c.left).abs() <= edge) return _Grip.left;
    if (inV && (p.dx - c.right).abs() <= edge) return _Grip.right;
    if (inH && (p.dy - c.top).abs() <= edge) return _Grip.top;
    if (inH && (p.dy - c.bottom).abs() <= edge) return _Grip.bottom;
    if (c.contains(p)) return _Grip.move;
    return null;
  }

  static double _limit(double v, double lo, double hi) => hi < lo ? lo : (v < lo ? lo : (v > hi ? hi : v));

  void _drag(Offset delta) {
    final d = _dest;
    final grip = _grip;
    if (grip == null || d.width <= 0 || d.height <= 0) return;
    final dx = delta.dx / d.width, dy = delta.dy / d.height;
    // Рамка не меньше 48 точек экрана.
    final minW = math.min(1.0, 48 / d.width), minH = math.min(1.0, 48 / d.height);
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    final moveL = grip == _Grip.left || grip == _Grip.topLeft || grip == _Grip.bottomLeft;
    final moveR = grip == _Grip.right || grip == _Grip.topRight || grip == _Grip.bottomRight;
    final moveT = grip == _Grip.top || grip == _Grip.topLeft || grip == _Grip.topRight;
    final moveB = grip == _Grip.bottom || grip == _Grip.bottomLeft || grip == _Grip.bottomRight;
    if (grip == _Grip.move) {
      final w = r - l, h = b - t;
      l = _limit(l + dx, 0, 1 - w);
      t = _limit(t + dy, 0, 1 - h);
      r = l + w;
      b = t + h;
    } else if (widget.circle) {
      // Квадрат на экране (снимок вписан без искажения): угол тянется по
      // диагонали, противоположный стоит на месте.
      final c = _cropOnScreen(d);
      final sx = moveR ? 1.0 : -1.0, sy = moveB ? 1.0 : -1.0;
      final anchor = Offset(moveR ? c.left : c.right, moveB ? c.top : c.bottom);
      final room = math.min(
        moveR ? d.right - anchor.dx : anchor.dx - d.left,
        moveB ? d.bottom - anchor.dy : anchor.dy - d.top,
      );
      final side = _limit(c.width + (sx * delta.dx + sy * delta.dy) / 2, math.min(48.0, room), room);
      final sq = Rect.fromPoints(anchor, anchor.translate(sx * side, sy * side));
      l = (sq.left - d.left) / d.width;
      r = (sq.right - d.left) / d.width;
      t = (sq.top - d.top) / d.height;
      b = (sq.bottom - d.top) / d.height;
    } else {
      if (moveL) l = _limit(l + dx, 0, r - minW);
      if (moveR) r = _limit(r + dx, l + minW, 1);
      if (moveT) t = _limit(t + dy, 0, b - minH);
      if (moveB) b = _limit(b + dy, t + minH, 1);
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  void _rotate() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _turns = (_turns + 3) % 4;
      _crop = ImageEdit.rotateLeft(_crop);
    });
  }

  void _reset() {
    setState(() {
      _turns = 0;
      _crop = ImageEdit.full;
      if (widget.circle && _image != null) _crop = _centerSquare();
    });
  }

  Future<void> _done() async {
    if (!_changed) {
      // Круг: «Готово» без правки (квадратный снимок) — снимок как есть.
      Navigator.of(context).pop(widget.circle ? (name: widget.name, bytes: widget.bytes) : null);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final r = await ImageEdit.apply(widget.bytes, widget.name, _turns, _crop);
    if (!mounted) return;
    if (r == null) {
      setState(() => _busy = false);
      quietError(l10n.tr('imageEditFailed'));
      return;
    }
    Navigator.of(context).pop(r);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final image = _image;
    const fg = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.7);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: fg,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          tooltip: l10n.tr('cancel'),
          icon: const Icon(AppIcons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.tr('attCropRotate')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(Space.m),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                  )
                : TextButton(
                    style: TextButton.styleFrom(foregroundColor: fg),
                    onPressed: image == null ? null : () => unawaited(_done()),
                    child: Text(l10n.tr('done')),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _failed
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text(l10n.tr('imageEditLoadFailed'),
                          textAlign: TextAlign.center, style: TextStyle(color: muted)),
                    ),
                  )
                : image == null
                    ? const Center(child: CircularProgressIndicator(color: fg))
                    : LayoutBuilder(builder: (context, c) {
                        _dest = _fit(c.biggest);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _busy ? null : (d) => setState(() => _grip = _hit(d.localPosition)),
                          onPanUpdate: _busy ? null : (d) => _drag(d.delta),
                          onPanEnd: (_) => setState(() => _grip = null),
                          onPanCancel: () => setState(() => _grip = null),
                          child: CustomPaint(
                            size: c.biggest,
                            painter: _EditPainter(
                              image: image,
                              turns: _turns,
                              dest: _dest,
                              crop: _cropOnScreen(_dest),
                              grid: _grip != null,
                              circle: widget.circle,
                            ),
                          ),
                        );
                      }),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.circle && image != null) ...[
                  _CirclePreview(image: image, turns: _turns, crop: _crop),
                  const SizedBox(height: Space.s),
                ],
                Text(l10n.tr(widget.circle ? 'imageEditHintCircle' : 'imageEditHint'),
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: Space.s),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ToolButton(
                      icon: AppIcons.rotate_90_degrees_ccw,
                      label: l10n.tr('imageRotate'),
                      onTap: image == null || _busy ? null : _rotate,
                    ),
                    _ToolButton(
                      icon: AppIcons.restart_alt,
                      label: l10n.tr('reset'),
                      onTap: !_changed || _busy ? null : _reset,
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка инструмента: круглый значок и подпись, светлые на тёмном фоне.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ToolButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final color = Colors.white.withValues(alpha: on ? 1 : 0.35);
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          child: ExcludeSemantics(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: on ? 0.14 : 0.06)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: Space.xs),
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Просмотр портрета: выбранный квадрат в кружках тех размеров, что в ленте
/// (40), шапке письма (56) и карточке человека (88).
class _CirclePreview extends StatelessWidget {
  final ui.Image image;
  final int turns;
  final Rect crop;
  const _CirclePreview({required this.image, required this.turns, required this.crop});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.tr('photoCirclePreview'),
      image: true,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in const [40.0, 56.0, 88.0]) ...[
            if (d != 40) const SizedBox(width: Space.l),
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: CustomPaint(painter: _CirclePainter(image: image, turns: turns, crop: crop)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Квадрат [crop] (доли повёрнутого снимка) — в круг на весь холст.
class _CirclePainter extends CustomPainter {
  final ui.Image image;
  final int turns;
  final Rect crop;
  _CirclePainter({required this.image, required this.turns, required this.crop});

  @override
  void paint(Canvas canvas, Size size) {
    final odd = turns.isOdd;
    final rw = (odd ? image.height : image.width).toDouble();
    final rh = (odd ? image.width : image.height).toDouble();
    final cw = crop.width * rw, ch = crop.height * rh;
    if (cw <= 0 || ch <= 0) return;
    final k = math.max(size.width / cw, size.height / ch);
    final whole = Rect.fromLTWH(-crop.left * rw * k, -crop.top * rh * k, rw * k, rh * k);
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    canvas.translate(whole.center.dx, whole.center.dy);
    canvas.rotate(turns * math.pi / 2);
    final w = odd ? whole.height : whole.width;
    final h = odd ? whole.width : whole.height;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CirclePainter old) => old.image != image || old.turns != turns || old.crop != crop;
}

/// Снимок с поворотом и рамка обрезки: снаружи затемнение, углы — уголками,
/// пока тянут — сетка третей. [circle] — затемнение вне круга, вписанного в
/// рамку.
class _EditPainter extends CustomPainter {
  final ui.Image image;
  final int turns;
  final Rect dest;
  final Rect crop;
  final bool grid;
  final bool circle;

  _EditPainter(
      {required this.image,
      required this.turns,
      required this.dest,
      required this.crop,
      required this.grid,
      this.circle = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (dest.isEmpty) return;
    canvas.save();
    canvas.translate(dest.center.dx, dest.center.dy);
    canvas.rotate(turns * math.pi / 2);
    final w = turns.isOdd ? dest.height : dest.width;
    final h = turns.isOdd ? dest.width : dest.height;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // Затемнение вне рамки (круга).
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(dest)
        ..addPath(circle ? (Path()..addOval(crop)) : (Path()..addRect(crop)), Offset.zero),
      Paint()..color = Colors.black.withValues(alpha: circle ? 0.65 : 0.55),
    );
    if (circle) {
      canvas.drawOval(
        crop,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
    canvas.drawRect(
      crop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    if (grid) {
      final p = Paint()
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.5);
      for (var i = 1; i < 3; i++) {
        final x = crop.left + crop.width * i / 3;
        final y = crop.top + crop.height * i / 3;
        canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), p);
        canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), p);
      }
    }
    // Уголки — за них тянут.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    final len = math.min(20.0, math.min(crop.width, crop.height) / 3);
    void mark(Offset o, double sx, double sy) {
      canvas.drawLine(o, o.translate(len * sx, 0), corner);
      canvas.drawLine(o, o.translate(0, len * sy), corner);
    }

    mark(crop.topLeft, 1, 1);
    mark(crop.topRight, -1, 1);
    mark(crop.bottomLeft, 1, -1);
    mark(crop.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_EditPainter old) =>
      old.image != image ||
      old.turns != turns ||
      old.dest != dest ||
      old.crop != crop ||
      old.grid != grid ||
      old.circle != circle;
}

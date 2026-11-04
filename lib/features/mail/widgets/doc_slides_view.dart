// lib/features/mail/widgets/doc_slides_view.dart
// Презентация (PPTX, ODP) в просмотре вложения (1.11.x, предпросмотр
// документов, план владельца 04.11.2026): слайды рисуются виджетами Flutter
// по модели [OfficeSlidesDoc] (pptx_reader.dart, odp_reader.dart).
//
// Как устроено:
//  · список слайдов — столбцом «листов» в пропорциях презентации, во всю
//    ширину (не шире 960 точек на планшете и компьютере), под каждым —
//    номер «3 / 12»; строятся только видимые слайды (ListView.builder);
//    список листается только по вертикали — боковые жесты остаются у
//    PageView экрана вложений;
//  · слайд — Stack размером со слайд в пунктах, уменьшенный FittedBox: шрифты
//    и положения масштабируются вместе; текст может выходить за рамку фигуры
//    (как в PowerPoint), но не за край слайда;
//  · картинки декодируются под размер на экране (cacheWidth), а не в
//    исходном разрешении — фото с телефона в презентации не занимает память
//    десятков мегапикселей;
//  · касание слайда — на весь экран: листание слайдов, увеличение пальцами
//    и двойным касанием, стрелки и Esc на компьютере;
//  · слайды — в своих цветах и в тёмной теме (белый лист остаётся белым),
//    вокруг — фон темы.
// Шрифтов презентации (Calibri, Arial…) в телефоне обычно нет: текст —
// шрифтом системы, если такого нет — Roboto приложения; с засечками и
// моноширинные — похожими системными.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/documents/doc_slides.dart';
import '../../../widgets/ui/empty_state.dart';

/// Шрифт приложения (pubspec.yaml) — если шрифта презентации нет.
const _appFont = 'AppRoboto';

/// Ширина слайда в списке на планшете и компьютере — не больше.
const _maxSlideWidth = 960.0;

String _slideLabel(BuildContext context, int n, int total) =>
    AppLocalizations.of(context).tr('docSlideOf').replaceAll('{n}', '$n').replaceAll('{total}', '$total');

class DocSlidesView extends StatefulWidget {
  const DocSlidesView({super.key, required this.doc});

  final OfficeSlidesDoc doc;

  @override
  State<DocSlidesView> createState() => _DocSlidesViewState();
}

class _DocSlidesViewState extends State<DocSlidesView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(int index) {
    final reduce = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 200),
        reverseTransitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 150),
        pageBuilder: (_, __, ___) => DocSlidesFullScreen(doc: widget.doc, initialIndex: index),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final theme = Theme.of(context);
    if (doc.slides.isEmpty) {
      return EmptyState(icon: AppIcons.slideshow, title: AppLocalizations.of(context).tr('docEmpty'));
    }
    final total = doc.slides.length;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: LayoutBuilder(
        builder: (context, box) {
          final width = math.max(1.0, math.min(box.maxWidth - 2 * Space.m, _maxSlideWidth));
          final height = width * doc.height / doc.width;
          final ppp = width / doc.width * MediaQuery.devicePixelRatioOf(context);
          Widget item(int i, {bool prototype = false}) => Center(
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: height,
                    child: prototype
                        ? null
                        : Semantics(
                            button: true,
                            label: _slideLabel(context, i + 1, total),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _open(i),
                              child: _Paper(
                                child: DocSlideCanvas(doc: doc, slide: doc.slides[i], pixelsPerPoint: ppp),
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs, bottom: Space.m),
                    child: ExcludeSemantics(child: Text('${i + 1} / $total', style: labelStyle)),
                  ),
                ],
              ),
            ),
          );
          return Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.only(top: Space.m),
              itemCount: total,
              // Все слайды одного размера — высота строки известна заранее:
              // полоса прокрутки и переход к концу точны и без построения.
              prototypeItem: item(0, prototype: true),
              itemBuilder: (context, i) => item(i),
            ),
          );
        },
      ),
    );
  }
}

/// Лист слайда: тень на светлой теме, тонкая рамка — на тёмной.
class _Paper extends StatelessWidget {
  const _Paper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.5) : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            if (!dark)
              BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Слайды на весь экран: листание, увеличение, номер слайда.
class DocSlidesFullScreen extends StatefulWidget {
  const DocSlidesFullScreen({super.key, required this.doc, this.initialIndex = 0});

  final OfficeSlidesDoc doc;
  final int initialIndex;

  @override
  State<DocSlidesFullScreen> createState() => _DocSlidesFullScreenState();
}

class _DocSlidesFullScreenState extends State<DocSlidesFullScreen> {
  late final PageController _pages;
  late int _index;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, math.max(0, widget.doc.slides.length - 1));
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.doc.slides.length - 1);
    if (next == _index || !_pages.hasClients) return;
    if (MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final total = doc.slides.length;
    final m = MaterialLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.space): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: total,
                  // Увеличенный слайд двигается пальцем — страницы не листаются.
                  physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) => Semantics(
                    label: _slideLabel(context, i + 1, total),
                    child: _ZoomableSlide(
                      doc: doc,
                      slide: doc.slides[i],
                      onZoomed: (z) {
                        if (z != _zoomed && i == _index) setState(() => _zoomed = z);
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: m.closeButtonLabel,
                          color: Colors.white,
                          icon: const Icon(AppIcons.close),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const Spacer(),
                        ExcludeSemantics(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: Radii.chipAll,
                            ),
                            child: Text('${_index + 1} / $total', style: textStyle),
                          ),
                        ),
                        const SizedBox(width: Space.m),
                      ],
                    ),
                  ),
                ),
              ),
              // На планшете и компьютере — кнопки «назад» и «вперёд» по бокам.
              if (wide && !_zoomed && _index > 0)
                Positioned(
                  left: Space.s,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _SideButton(
                      icon: AppIcons.chevron_left,
                      tooltip: m.previousPageTooltip,
                      onTap: () => _go(-1),
                    ),
                  ),
                ),
              if (wide && !_zoomed && _index < total - 1)
                Positioned(
                  right: Space.s,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _SideButton(icon: AppIcons.chevron_right, tooltip: m.nextPageTooltip, onTap: () => _go(1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.45)),
    color: Colors.white,
    icon: Icon(icon),
    onPressed: onTap,
  );
}

/// Один слайд на весь экран с увеличением (до ×5).
class _ZoomableSlide extends StatefulWidget {
  const _ZoomableSlide({required this.doc, required this.slide, required this.onZoomed});
  final OfficeSlidesDoc doc;
  final DocSlide slide;
  final ValueChanged<bool> onZoomed;

  @override
  State<_ZoomableSlide> createState() => _ZoomableSlideState();
}

class _ZoomableSlideState extends State<_ZoomableSlide> {
  final _tc = TransformationController();
  Offset? _tapAt;

  /// Ступень резкости картинок: при увеличении они декодируются заново
  /// крупнее, но не на каждый шаг щипка.
  double _detail = 1;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _settled() {
    final s = _tc.value.getMaxScaleOnAxis();
    widget.onZoomed(s > 1.01);
    final step = s > 2.5 ? 4.0 : (s > 1.3 ? 2.0 : 1.0);
    if (step > _detail) setState(() => _detail = step);
  }

  void _toggleZoom() {
    final at = _tapAt;
    if (at == null) return;
    if (_tc.value.getMaxScaleOnAxis() > 1.01) {
      _tc.value = Matrix4.identity();
    } else {
      const k = 2.5;
      _tc.value = Matrix4.translationValues(at.dx * (1 - k), at.dy * (1 - k), 0)
        ..multiply(Matrix4.diagonal3Values(k, k, 1));
    }
    _settled();
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    return LayoutBuilder(
      builder: (context, box) {
        final scale = math.min(box.maxWidth / doc.width, box.maxHeight / doc.height);
        final w = doc.width * scale, h = doc.height * scale;
        final ppp = scale * MediaQuery.devicePixelRatioOf(context) * _detail;
        return GestureDetector(
          onDoubleTapDown: (d) => _tapAt = d.localPosition,
          onDoubleTap: _toggleZoom,
          child: InteractiveViewer(
            transformationController: _tc,
            minScale: 1,
            maxScale: 5,
            onInteractionEnd: (_) => _settled(),
            child: SizedBox(
              width: box.maxWidth,
              height: box.maxHeight,
              child: Center(
                child: SizedBox(
                  width: w,
                  height: h,
                  child: ColoredBox(
                    color: Colors.white,
                    child: DocSlideCanvas(doc: doc, slide: widget.slide, pixelsPerPoint: ppp),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────────────── слайд ─────────────────────────────────

/// Один слайд, вписанный в отведённое место. [pixelsPerPoint] — физических
/// пикселей экрана на пункт слайда (для размера декодирования картинок).
class DocSlideCanvas extends StatelessWidget {
  const DocSlideCanvas({super.key, required this.doc, required this.slide, this.pixelsPerPoint = 2});

  final OfficeSlidesDoc doc;
  final DocSlide slide;
  final double pixelsPerPoint;

  @override
  Widget build(BuildContext context) {
    final w = doc.width, h = doc.height;
    return RepaintBoundary(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: w,
          height: h,
          // Размер текста слайда — свой, системная настройка крупного шрифта
          // его не меняет: иначе текст вылезет из фигур.
          child: MediaQuery.withNoTextScaling(
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 18,
                fontFamily: _appFont,
                decoration: TextDecoration.none,
              ),
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: _FillView(fill: slide.background ?? const DocFill.solid(0xFFFFFFFF), ppp: pixelsPerPoint),
                    ),
                    for (final s in slide.shapes) _shape(s),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _shape(DocShape s) {
    final w = s.w.isFinite ? math.max(0.0, s.w) : 0.0;
    final h = s.h.isFinite ? math.max(0.0, s.h) : 0.0;
    Widget body = _ShapeView(shape: s, w: w, h: h, ppp: pixelsPerPoint);
    if (s.rotation != 0) body = Transform.rotate(angle: s.rotation * math.pi / 180, child: body);
    return Positioned(left: s.x, top: s.y, width: w, height: h, child: body);
  }
}

/// Заливка прямоугольника (фон слайда, ячейка): цвет, градиент, картинка.
class _FillView extends StatelessWidget {
  const _FillView({required this.fill, required this.ppp});
  final DocFill fill;
  final double ppp;

  @override
  Widget build(BuildContext context) {
    final img = fill.image;
    if (img != null) {
      return LayoutBuilder(
        builder: (context, box) {
          if (fill.tile) {
            // Плитка: пиксель картинки — 0.75 пункта (96 точек на дюйм).
            return DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: MemoryImage(img.bytes),
                  repeat: ImageRepeat.repeat,
                  scale: 1 / (0.75 * fill.tileScale),
                  alignment: Alignment.topLeft,
                ),
              ),
            );
          }
          return Image.memory(
            img.bytes,
            fit: BoxFit.fill,
            cacheWidth: _cacheWidth(box.maxWidth, ppp),
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      );
    }
    if (fill.isGradient) return DecoratedBox(decoration: BoxDecoration(gradient: _gradient(fill)));
    final c = fill.flatColor;
    return c == null ? const SizedBox.shrink() : ColoredBox(color: Color(c));
  }
}

int? _cacheWidth(double points, double ppp) {
  if (!points.isFinite || points <= 0) return null;
  return (points * ppp).ceil().clamp(16, 4096);
}

Gradient _gradient(DocFill f) {
  final colors = [for (final c in f.gradientColors) Color(c)];
  final stops = f.gradientStops.length == colors.length ? f.gradientStops : null;
  if (f.radial) return RadialGradient(colors: colors, stops: stops, radius: 0.75);
  final a = f.gradientAngle * math.pi / 180;
  final dx = math.cos(a), dy = math.sin(a);
  // Направление — по диагонали рамки: на 45° — из угла в угол, как в PowerPoint.
  final k = 1 / math.max(dx.abs(), dy.abs()).clamp(1e-6, 1.0);
  return LinearGradient(
    begin: Alignment(-dx * k, -dy * k),
    end: Alignment(dx * k, dy * k),
    colors: colors,
    stops: stops,
  );
}

// ───────────────────────────────── фигура ─────────────────────────────────

class _ShapeView extends StatelessWidget {
  const _ShapeView({required this.shape, required this.w, required this.h, required this.ppp});
  final DocShape shape;
  final double w, h, ppp;

  @override
  Widget build(BuildContext context) {
    final s = shape;
    final flipped = s.flipH || s.flipV;
    Widget flip(Widget child) => flipped
        ? Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(s.flipH ? -1 : 1, s.flipV ? -1 : 1, 1),
            child: child,
          )
        : child;
    final fill = s.fill;
    final children = <Widget>[
      // Картинка вместо заливки — по форме фигуры.
      if (fill?.image != null)
        Positioned.fill(
          child: flip(
            ClipPath(
              clipper: _GeomClipper(s),
              child: _FillView(fill: fill!, ppp: ppp),
            ),
          ),
        ),
      if (s.picture != null)
        Positioned.fill(
          child: flip(_PictureView(shape: s, w: w, h: h, ppp: ppp)),
        ),
      if (s.embed != null)
        Positioned.fill(
          child: _EmbedView(kind: s.embed!, w: w, h: h),
        ),
      if ((fill != null && fill.image == null) || s.line != null)
        Positioned.fill(
          child: CustomPaint(painter: _GeomPainter(s, paintFill: fill?.image == null)),
        ),
      if (s.table != null) Positioned.fill(child: _TableView(table: s.table!)),
      if (s.text != null) _text(s.text!),
    ];
    return Stack(clipBehavior: Clip.none, children: children);
  }

  /// Текст — во внутренней области формы, как в PowerPoint: у ромба,
  /// треугольника, эллипса она меньше рамки.
  Widget _text(DocTextBody body) {
    final r = _textRect(shape, w, h);
    return Positioned.fromRect(
      rect: r,
      child: _TextBoxView(body: body, w: r.width, h: r.height),
    );
  }
}

/// Область текста формы (по описаниям заготовок ECMA-376, упрощённо).
Rect _textRect(DocShape s, double w, double h) {
  final ss = math.min(w, h);
  final a = s.adjust;
  Rect ltrb(double l, double t, double r, double b) => Rect.fromLTRB(l, t, math.max(l, r), math.max(t, b));
  switch (s.geom) {
    case DocGeom.roundRect:
      final i = ss * (a ?? 1 / 6).clamp(0.0, 0.5) * 0.29289;
      return ltrb(i, i, w - i, h - i);
    case DocGeom.ellipse:
      return ltrb(w * 0.14645, h * 0.14645, w * 0.85355, h * 0.85355);
    case DocGeom.diamond:
      return ltrb(w / 4, h / 4, w * 3 / 4, h * 3 / 4);
    case DocGeom.triangle:
      final x1 = w * (a ?? 0.5).clamp(0.0, 1.0) / 2;
      return ltrb(x1, h / 2, x1 + w / 2, h);
    case DocGeom.rtTriangle:
      return ltrb(w / 12, h * 7 / 12, w * 7 / 12, h * 11 / 12);
    case DocGeom.parallelogram || DocGeom.hexagon:
      final x = math.min(w / 2, ss * (a ?? 0.25)) / 2;
      return ltrb(x, 0, w - x, h);
    case DocGeom.trapezoid:
      final x = math.min(w / 2, ss * (a ?? 0.25)) * 2 / 3;
      return ltrb(x, h / 6, w - x, h);
    case DocGeom.octagon:
      final x = math.min(ss / 2, ss * (a ?? 0.29289)) / 2;
      return ltrb(x, x, w - x, h - x);
    case DocGeom.pentagon:
      return ltrb(w * 0.19, h * 0.25, w * 0.81, h);
    case DocGeom.homePlate:
      final x = w - math.min(w, ss * (a ?? 0.5));
      return ltrb(0, 0, (x + w) / 2, h);
    case DocGeom.chevron:
      final x = math.min(w / 2, ss * (a ?? 0.5));
      return ltrb(x, 0, w - x, h);
    case DocGeom.rightArrow:
      final x = w - math.min(w, ss * (a ?? 0.5));
      return ltrb(0, h / 4, x + (w - x) / 2, h * 3 / 4);
    case DocGeom.leftArrow:
      final x = math.min(w, ss * (a ?? 0.5));
      return ltrb(x / 2, h / 4, w, h * 3 / 4);
    case DocGeom.downArrow:
      final y = h - math.min(h, ss * (a ?? 0.5));
      return ltrb(w / 4, 0, w * 3 / 4, y + (h - y) / 2);
    case DocGeom.upArrow:
      final y = math.min(h, ss * (a ?? 0.5));
      return ltrb(w / 4, y / 2, w * 3 / 4, h);
    case DocGeom.leftRightArrow:
      final x = math.min(w / 2, ss * (a ?? 0.5));
      return ltrb(x / 2, h / 4, w - x / 2, h * 3 / 4);
    case DocGeom.plus:
      final x = math.min(ss / 2, ss * (a ?? 0.25));
      return ltrb(0, x, w, h - x);
    case DocGeom.star5:
      return ltrb(w * 0.31, h * 0.4, w * 0.69, h * 0.75);
    case DocGeom.rect || DocGeom.line || DocGeom.path:
      return Rect.fromLTWH(0, 0, w, h);
  }
}

/// Контур формы в рамке [size].
Path _geomPath(DocShape s, Size size) {
  final w = size.width, h = size.height;
  final ss = math.min(w, h);
  final p = Path();
  void poly(List<double> xy) {
    p.moveTo(xy[0], xy[1]);
    for (var i = 2; i + 1 < xy.length; i += 2) {
      p.lineTo(xy[i], xy[i + 1]);
    }
    p.close();
  }

  final adj = s.adjust;
  switch (s.geom) {
    case DocGeom.rect:
      p.addRect(Offset.zero & size);
    case DocGeom.roundRect:
      final r = ss * (adj ?? 1 / 6).clamp(0.0, 0.5);
      p.addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r)));
    case DocGeom.ellipse:
      p.addOval(Offset.zero & size);
    case DocGeom.line:
      p.moveTo(0, 0);
      p.lineTo(w, h);
    case DocGeom.triangle:
      poly([w * (adj ?? 0.5).clamp(0.0, 1.0), 0, w, h, 0, h]);
    case DocGeom.rtTriangle:
      poly([0, 0, w, h, 0, h]);
    case DocGeom.diamond:
      poly([w / 2, 0, w, h / 2, w / 2, h, 0, h / 2]);
    case DocGeom.parallelogram:
      final x = math.min(w, ss * (adj ?? 0.25));
      poly([x, 0, w, 0, w - x, h, 0, h]);
    case DocGeom.trapezoid:
      final x = math.min(w / 2, ss * (adj ?? 0.25));
      poly([0, h, x, 0, w - x, 0, w, h]);
    case DocGeom.pentagon:
      poly([w / 2, 0, w, h * 0.382, w * 0.809, h, w * 0.191, h, 0, h * 0.382]);
    case DocGeom.hexagon:
      final x = math.min(w / 2, ss * (adj ?? 0.25));
      poly([x, 0, w - x, 0, w, h / 2, w - x, h, x, h, 0, h / 2]);
    case DocGeom.octagon:
      final x = math.min(ss / 2, ss * (adj ?? 0.29289));
      poly([x, 0, w - x, 0, w, x, w, h - x, w - x, h, x, h, 0, h - x, 0, x]);
    case DocGeom.homePlate:
      final x = w - math.min(w, ss * (adj ?? 0.5));
      poly([0, 0, x, 0, w, h / 2, x, h, 0, h]);
    case DocGeom.chevron:
      final x = math.min(w, ss * (adj ?? 0.5));
      poly([0, 0, w - x, 0, w, h / 2, w - x, h, 0, h, x, h / 2]);
    case DocGeom.rightArrow:
      final x = w - math.min(w, ss * (adj ?? 0.5));
      poly([0, h / 4, x, h / 4, x, 0, w, h / 2, x, h, x, h * 3 / 4, 0, h * 3 / 4]);
    case DocGeom.leftArrow:
      final x = math.min(w, ss * (adj ?? 0.5));
      poly([w, h / 4, x, h / 4, x, 0, 0, h / 2, x, h, x, h * 3 / 4, w, h * 3 / 4]);
    case DocGeom.downArrow:
      final y = h - math.min(h, ss * (adj ?? 0.5));
      poly([w / 4, 0, w * 3 / 4, 0, w * 3 / 4, y, w, y, w / 2, h, 0, y, w / 4, y]);
    case DocGeom.upArrow:
      final y = math.min(h, ss * (adj ?? 0.5));
      poly([w / 4, h, w * 3 / 4, h, w * 3 / 4, y, w, y, w / 2, 0, 0, y, w / 4, y]);
    case DocGeom.leftRightArrow:
      final x = math.min(w / 2, ss * (adj ?? 0.5));
      poly([
        0,
        h / 2,
        x,
        0,
        x,
        h / 4,
        w - x,
        h / 4,
        w - x,
        0,
        w,
        h / 2,
        w - x,
        h,
        w - x,
        h * 3 / 4,
        x,
        h * 3 / 4,
        x,
        h,
      ]);
    case DocGeom.plus:
      final x = math.min(ss / 2, ss * (adj ?? 0.25));
      poly([x, 0, w - x, 0, w - x, x, w, x, w, h - x, w - x, h - x, w - x, h, x, h, x, h - x, 0, h - x, 0, x, x, x]);
    case DocGeom.star5:
      final pts = <double>[];
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? 0.5 : 0.19;
        final a = -math.pi / 2 + i * math.pi / 5;
        pts.addAll([w / 2 + r * w * math.cos(a), h / 2 + 0.105 * h + r * h * math.sin(a) * 1.05]);
      }
      poly(pts);
    case DocGeom.path:
      final d = s.path;
      if (d == null) {
        p.addRect(Offset.zero & size);
        break;
      }
      var k = 0;
      for (final op in d.ops) {
        switch (op) {
          case DocPathOp.move:
            if (k + 1 >= d.points.length) return p;
            p.moveTo(d.points[k] * w, d.points[k + 1] * h);
            k += 2;
          case DocPathOp.line:
            if (k + 1 >= d.points.length) return p;
            p.lineTo(d.points[k] * w, d.points[k + 1] * h);
            k += 2;
          case DocPathOp.cubic:
            if (k + 5 >= d.points.length) return p;
            p.cubicTo(
              d.points[k] * w,
              d.points[k + 1] * h,
              d.points[k + 2] * w,
              d.points[k + 3] * h,
              d.points[k + 4] * w,
              d.points[k + 5] * h,
            );
            k += 6;
          case DocPathOp.close:
            p.close();
        }
      }
  }
  return p;
}

class _GeomClipper extends CustomClipper<Path> {
  const _GeomClipper(this.shape);
  final DocShape shape;

  @override
  Path getClip(Size size) => _geomPath(shape, size);

  @override
  bool shouldReclip(_GeomClipper old) => old.shape != shape;
}

/// Заливка и контур формы (с отражениями фигуры).
class _GeomPainter extends CustomPainter {
  _GeomPainter(this.shape, {this.paintFill = true});
  final DocShape shape;
  final bool paintFill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = shape;
    canvas.save();
    if (s.flipH || s.flipV) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.scale(s.flipH ? -1 : 1, s.flipV ? -1 : 1);
      canvas.translate(-size.width / 2, -size.height / 2);
    }
    final path = _geomPath(s, size);
    final fill = s.fill;
    final open = s.geom == DocGeom.line || (s.path != null && !s.path!.filled);
    if (paintFill && fill != null && !open) {
      final paint = Paint()..style = PaintingStyle.fill;
      if (fill.isGradient) {
        paint.shader = _gradient(fill).createShader(Offset.zero & size);
      } else if (fill.flatColor != null) {
        paint.color = Color(fill.flatColor!);
      }
      canvas.drawPath(path, paint);
    }
    final line = s.line;
    if (line != null && (line.color >> 24) != 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Color(line.color)
        ..strokeWidth = line.width
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = line.dash == DocDash.dot ? StrokeCap.round : StrokeCap.butt;
      canvas.drawPath(line.dash == DocDash.solid ? path : _dashed(path, line), paint);
      if (open && (line.headArrow || line.tailArrow)) _arrows(canvas, path, line);
    }
    canvas.restore();
  }

  static Path _dashed(Path src, DocLine line) {
    final u = math.max(line.width, 0.75);
    final pattern = switch (line.dash) {
      DocDash.dot => [0.01, 2 * u],
      DocDash.dashDot => [4 * u, 3 * u, 0.01, 3 * u],
      _ => [4 * u, 3 * u],
    };
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      var i = 0;
      var guard = 0;
      while (d < m.length && guard++ < 20000) {
        final len = pattern[i % pattern.length];
        if (i.isEven) out.addPath(m.extractPath(d, math.min(d + len, m.length)), Offset.zero);
        d += len;
        i++;
      }
    }
    return out;
  }

  static void _arrows(Canvas canvas, Path path, DocLine line) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final size = math.max(line.width, 1.0) * 3 + 3;
    final paint = Paint()..color = Color(line.color);
    void head(ui.Tangent? t, bool atStart) {
      if (t == null) return;
      final dir = atStart ? -t.vector : t.vector;
      final len = dir.distance;
      if (len == 0) return;
      final d = dir / len;
      final n = Offset(-d.dy, d.dx);
      final tip = t.position;
      final base = tip - d * size;
      canvas.drawPath(
        Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(base.dx + n.dx * size / 2, base.dy + n.dy * size / 2)
          ..lineTo(base.dx - n.dx * size / 2, base.dy - n.dy * size / 2)
          ..close(),
        paint,
      );
    }

    if (line.headArrow) head(metrics.first.getTangentForOffset(0), true);
    if (line.tailArrow) head(metrics.last.getTangentForOffset(metrics.last.length), false);
  }

  @override
  bool shouldRepaint(_GeomPainter old) => old.shape != shape || old.paintFill != paintFill;
}

/// Картинка фигуры с обрезкой, по форме фигуры.
class _PictureView extends StatelessWidget {
  const _PictureView({required this.shape, required this.w, required this.h, required this.ppp});
  final DocShape shape;
  final double w, h, ppp;

  @override
  Widget build(BuildContext context) {
    final p = shape.picture!;
    final fw = w / math.max(0.01, 1 - p.cropLeft - p.cropRight);
    final fh = h / math.max(0.01, 1 - p.cropTop - p.cropBottom);
    final image = Image.memory(
      p.image.bytes,
      fit: BoxFit.fill,
      cacheWidth: _cacheWidth(fw, ppp),
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    final cropped = p.cropLeft == 0 && p.cropTop == 0 && p.cropRight == 0 && p.cropBottom == 0
        ? image
        : Stack(
            clipBehavior: Clip.hardEdge,
            children: [Positioned(left: -p.cropLeft * fw, top: -p.cropTop * fh, width: fw, height: fh, child: image)],
          );
    if (shape.geom == DocGeom.rect) return ClipRect(child: cropped);
    return ClipPath(clipper: _GeomClipper(shape), child: cropped);
  }
}

/// Что не рисуется (диаграмма, объект, видео): серая плашка со значком.
class _EmbedView extends StatelessWidget {
  const _EmbedView({required this.kind, required this.w, required this.h});
  final DocEmbed kind;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      DocEmbed.chart => AppIcons.bar_chart,
      DocEmbed.diagram => AppIcons.account_tree,
      DocEmbed.media => AppIcons.play_circle,
      DocEmbed.object => AppIcons.widgets,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F4),
        border: Border.all(color: const Color(0xFFD0D4D8), width: 1),
      ),
      child: Center(
        child: Icon(icon, size: (math.min(w, h) * 0.35).clamp(10.0, 120.0), color: const Color(0xFF9AA0A6)),
      ),
    );
  }
}

// ───────────────────────────────── текст ─────────────────────────────────

class _TextBoxView extends StatelessWidget {
  const _TextBoxView({required this.body, required this.w, required this.h});
  final DocTextBody body;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final b = body;
    final iw = math.max(0.0, w - b.insetLeft - b.insetRight);
    final ih = math.max(0.0, h - b.insetTop - b.insetBottom);
    final first = b.paragraphs.firstOrNull?.align ?? DocAlign.left;
    final hx = b.wrap ? -1.0 : _alignX(first);
    final vy = switch (b.anchor) {
      DocAnchor.top => -1.0,
      DocAnchor.middle => 0.0,
      DocAnchor.bottom => 1.0,
    };
    final content = _TextContent(body: b);
    Widget child;
    if (b.shrink && b.wrap) {
      // Автоподбор: не помещается — уменьшается целиком.
      child = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment(0, vy),
        child: SizedBox(width: iw, child: content),
      );
    } else {
      child = OverflowBox(
        alignment: Alignment(hx, vy),
        minWidth: b.wrap ? iw : 0,
        maxWidth: b.wrap ? iw : double.infinity,
        minHeight: 0,
        maxHeight: double.infinity,
        child: content,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [Positioned(left: b.insetLeft, top: b.insetTop, width: iw, height: ih, child: child)],
    );
  }

  static double _alignX(DocAlign a) => switch (a) {
    DocAlign.center => 0,
    DocAlign.right => 1,
    _ => -1,
  };
}

/// Абзацы текста: столбцом во всю ширину (или по ширине текста без переноса).
class _TextContent extends StatelessWidget {
  const _TextContent({required this.body});
  final DocTextBody body;

  @override
  Widget build(BuildContext context) {
    final b = body;
    final first = b.paragraphs.firstOrNull?.align ?? DocAlign.left;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: b.wrap
          ? CrossAxisAlignment.stretch
          : switch (first) {
              DocAlign.center => CrossAxisAlignment.center,
              DocAlign.right => CrossAxisAlignment.end,
              _ => CrossAxisAlignment.start,
            },
      children: [for (final p in b.paragraphs) _ParagraphView(p: p, body: b)],
    );
  }
}

class _ParagraphView extends StatelessWidget {
  const _ParagraphView({required this.p, required this.body});
  final DocParagraph p;
  final DocTextBody body;

  @override
  Widget build(BuildContext context) {
    final k = body.fontScale;
    final spacing = 1 - body.lineReduction;
    double lineHeight(double size) {
      final exact = p.lineExact;
      if (exact != null) return (exact * spacing / math.max(1.0, size * k)).clamp(0.5, 10.0);
      return (1.2 * p.lineSpacing * spacing).clamp(0.5, 10.0);
    }

    final align = switch (p.align) {
      DocAlign.center => TextAlign.center,
      DocAlign.right => TextAlign.right,
      DocAlign.justify => TextAlign.justify,
      DocAlign.left => TextAlign.left,
    };
    final hasText = p.runs.any((r) => r.text.isNotEmpty);
    final Widget text;
    if (!hasText) {
      // Пустой абзац — пустая строка высотой знака конца абзаца.
      text = Text(
        ' ',
        style: TextStyle(fontSize: p.endSize * k, height: lineHeight(p.endSize), fontFamily: _appFont),
      );
    } else {
      text = Text.rich(
        TextSpan(children: [for (final r in p.runs) _span(r, k, lineHeight(r.size))]),
        textAlign: align,
        softWrap: body.wrap,
      );
    }
    final first = p.runs.firstOrNull;
    final bullet = p.bullet;
    Widget out;
    if (bullet != null && first != null) {
      // Точка «•» у Roboto заметно мельче, чем у Arial и Calibri, — крупнее.
      final scale = bullet.sizeScale * (bullet.text == '•' ? 1.3 : 1.0);
      final size = first.size * k * scale;
      final style = _style(
        DocRun('', size: first.size, color: bullet.color ?? first.color, font: bullet.font ?? first.font),
        k * scale,
        lineHeight(first.size) / scale,
      ).copyWith(fontWeight: first.bold ? FontWeight.w700 : FontWeight.w400);
      final labelWidth = math.max(-p.indent, size * (bullet.text.length > 1 ? 0.6 * bullet.text.length : 0.9));
      final label = SizedBox(
        width: labelWidth,
        child: Text(bullet.text, style: style, softWrap: false, overflow: TextOverflow.visible),
      );
      out = Padding(
        padding: EdgeInsets.only(left: math.max(0.0, p.marginLeft + p.indent)),
        child: Row(
          mainAxisSize: body.wrap ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            label,
            if (body.wrap) Expanded(child: text) else text,
          ],
        ),
      );
    } else {
      final left = p.indent < 0 ? p.marginLeft + p.indent : p.marginLeft;
      Widget t = text;
      if (p.indent > 0 && hasText) {
        // Красная строка — пустым местом перед первым фрагментом.
        t = Text.rich(
          TextSpan(
            children: [
              WidgetSpan(child: SizedBox(width: p.indent)),
              for (final r in p.runs) _span(r, k, lineHeight(r.size)),
            ],
          ),
          textAlign: align,
          softWrap: body.wrap,
        );
      }
      out = Padding(
        padding: EdgeInsets.only(left: math.max(0.0, left)),
        child: t,
      );
    }
    final before = p.spaceBefore * spacing, after = p.spaceAfter * spacing;
    if (before > 0 || after > 0) {
      out = Padding(
        padding: EdgeInsets.only(top: before, bottom: after),
        child: out,
      );
    }
    return out;
  }
}

const _serifFonts = [
  'times',
  'georgia',
  'cambria',
  'garamond',
  'book antiqua',
  'palatino',
  'constantia',
  'serif',
  'baskerville',
  'bodoni',
  'century',
  'didot',
  'minion',
  'caslon',
];
const _monoFonts = ['courier', 'consolas', 'mono', 'lucida console', 'menlo', 'monaco', 'source code'];

/// Шрифт фрагмента: свой, если он есть в системе; иначе — похожий.
TextStyle _style(DocRun r, double k, double height) {
  final f = (r.font ?? '').toLowerCase();
  final serif = !f.contains('sans') && _serifFonts.any(f.contains);
  final mono = _monoFonts.any(f.contains);
  final under = r.underline, strike = r.strike;
  return TextStyle(
    fontSize: r.size * k,
    color: Color(r.color),
    fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
    decoration: under && strike
        ? TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough])
        : under
        ? TextDecoration.underline
        : (strike ? TextDecoration.lineThrough : TextDecoration.none),
    decorationColor: Color(r.color),
    fontFamily: (r.font ?? '').isEmpty ? _appFont : r.font,
    fontFamilyFallback: mono
        ? const ['monospace', 'Menlo', 'Courier New', 'Courier', _appFont]
        : serif
        ? const ['Noto Serif', 'serif', 'Times New Roman', 'Georgia', _appFont]
        : const [_appFont],
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    backgroundColor: r.highlight == null ? null : Color(r.highlight!),
  );
}

InlineSpan _span(DocRun r, double k, double height) {
  if (r.baseline == 0) return TextSpan(text: r.text, style: _style(r, k, height));
  // Индексы: шрифт меньше, строка — выше или ниже (в TextStyle сдвига нет).
  final small = _style(r, k * 0.65, height / 0.65);
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Transform.translate(
      offset: Offset(0, -r.size * k * r.baseline / 100),
      child: Text(r.text, style: small),
    ),
  );
}

// ──────────────────────────────── таблица ────────────────────────────────

/// Таблица: ячейки по сетке столбцов и строк; строка выше заданной, если
/// текст в неё не помещается (как в PowerPoint) — таблица растёт вниз.
class _TableView extends StatelessWidget {
  const _TableView({required this.table});
  final DocTable table;

  @override
  Widget build(BuildContext context) {
    final t = table;
    return CustomMultiChildLayout(
      delegate: _TableLayout(t),
      children: [
        for (var i = 0; i < t.cells.length; i++) ...[
          LayoutId(
            id: 'b$i',
            child: _CellBox(cell: t.cells[i]),
          ),
          LayoutId(
            id: 't$i',
            child: t.cells[i].text == null ? const SizedBox.shrink() : _TextContent(body: t.cells[i].text!),
          ),
        ],
      ],
    );
  }
}

class _TableLayout extends MultiChildLayoutDelegate {
  _TableLayout(this.t);
  final DocTable t;

  @override
  void performLayout(Size size) {
    final cols = t.columns, rows = List<double>.of(t.rows);
    final colX = <double>[0];
    for (final c in cols) {
      colX.add(colX.last + c);
    }
    double span(List<double> xs, int from, int n) => xs[math.min(from + n, xs.length - 1)] - xs[from];
    // Высота текста ячеек — при ширине ячейки за вычетом полей.
    final need = <int, double>{};
    for (var i = 0; i < t.cells.length; i++) {
      final c = t.cells[i];
      final b = c.text;
      final cw = span(colX, math.min(c.col, cols.length), c.colSpan);
      final iw = math.max(0.0, cw - (b?.insetLeft ?? 0) - (b?.insetRight ?? 0));
      final s = layoutChild('t$i', BoxConstraints(minWidth: iw, maxWidth: iw));
      if (b != null) need[i] = s.height + b.insetTop + b.insetBottom;
    }
    // Строки растут под текст: одиночные ячейки — сначала, объединённые —
    // добавляют недостающее последней строке.
    for (final entry in need.entries) {
      final c = t.cells[entry.key];
      if (c.rowSpan == 1 && c.row < rows.length && rows[c.row] < entry.value) rows[c.row] = entry.value;
    }
    for (final entry in need.entries) {
      final c = t.cells[entry.key];
      if (c.rowSpan <= 1 || c.row >= rows.length) continue;
      final last = math.min(c.row + c.rowSpan, rows.length) - 1;
      var have = 0.0;
      for (var r = c.row; r <= last; r++) {
        have += rows[r];
      }
      if (have < entry.value) rows[last] += entry.value - have;
    }
    final rowY = <double>[0];
    for (final r in rows) {
      rowY.add(rowY.last + r);
    }
    for (var i = 0; i < t.cells.length; i++) {
      final c = t.cells[i];
      final col = math.min(c.col, cols.length), row = math.min(c.row, rows.length);
      final x = colX[col], y = rowY[row];
      final w = span(colX, col, c.colSpan), h = span(rowY, row, c.rowSpan);
      layoutChild('b$i', BoxConstraints.tight(Size(math.max(0.0, w), math.max(0.0, h))));
      positionChild('b$i', Offset(x, y));
      final b = c.text;
      var ty = y + (b?.insetTop ?? 0);
      final n = need[i];
      if (b != null && n != null) {
        final free = math.max(0.0, h - n);
        ty += switch (b.anchor) {
          DocAnchor.top => 0.0,
          DocAnchor.middle => free / 2,
          DocAnchor.bottom => free,
        };
      }
      positionChild('t$i', Offset(x + (b?.insetLeft ?? 0), ty));
    }
  }

  @override
  bool shouldRelayout(_TableLayout old) => old.t != t;
}

class _CellBox extends StatelessWidget {
  const _CellBox({required this.cell});
  final DocCell cell;

  @override
  Widget build(BuildContext context) {
    final c = cell;
    return CustomPaint(
      foregroundPainter: _CellPainter(c),
      child: c.fill == null ? const SizedBox.expand() : _FillView(fill: c.fill!, ppp: 2),
    );
  }
}

/// Границы ячейки — поверх заливки, по краям (соседние ячейки рисуют общую
/// границу дважды, одним цветом).
class _CellPainter extends CustomPainter {
  _CellPainter(this.c);
  final DocCell c;

  @override
  void paint(Canvas canvas, Size size) {
    void side(DocLine? l, Offset a, Offset b) {
      if (l == null || (l.color >> 24) == 0) return;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Color(l.color)
          ..strokeWidth = l.width
          ..style = PaintingStyle.stroke,
      );
    }

    final w = size.width, h = size.height;
    side(c.top, Offset.zero, Offset(w, 0));
    side(c.bottom, Offset(0, h), Offset(w, h));
    side(c.left, Offset.zero, Offset(0, h));
    side(c.right, Offset(w, 0), Offset(w, h));
  }

  @override
  bool shouldRepaint(_CellPainter old) => old.c != c;
}

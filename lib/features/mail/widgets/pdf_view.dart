// lib/features/mail/widgets/pdf_view.dart
// PDF внутри приложения (1.8.14, просьба пользователей через владельца
// 29.10.2026). 12.10.2026 PDF ушёл во внешнее приложение: прежний встроенный
// просмотр (pdfx) был хуже системного. Здесь — Android, страницы рисует
// системный PdfRenderer (android/.../PdfRendererPlugin.kt): без сторонних
// библиотек и их лицензий. iPhone и iPad показывают PDF «Просмотром» iOS
// (он и так открывается внутри приложения), компьютер — своей программой.
//
// Как устроено:
//  · страницы — столбцом во всю ширину, рисуются только видимые и соседние;
//  · щипок и двойное касание — увеличение до ×6; после щипка видимые
//    страницы перерисовываются в нужной резкости (не размытым растром);
//  · в памяти — несколько последних страниц, остальные освобождаются;
//  · номер страницы — внизу, пока листают;
//  · PDF с паролем системный PdfRenderer не открывает — [onUnsupported],
//    экран предлагает другое приложение.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Документ, открытый системным PdfRenderer.
class NativePdfDocument {
  final int id;

  /// Размеры страниц в точках PDF.
  final List<Size> sizes;
  const NativePdfDocument(this.id, this.sizes);
}

class NativePdf {
  NativePdf._();

  static const _ch = MethodChannel('ogneliss/pdf');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Открыть PDF. Защищённый паролем — [PlatformException] с кодом
  /// «protected».
  static Future<NativePdfDocument> open(String path) async {
    final r = await _ch.invokeMapMethod<String, Object?>('open', {'path': path});
    final id = r?['id'] as int? ?? 0;
    final sizes = [
      for (final s in (r?['sizes'] as List? ?? const []))
        if (s is List && s.length == 2) Size((s[0] as num).toDouble(), (s[1] as num).toDouble()),
    ];
    return NativePdfDocument(id, sizes);
  }

  /// Страница [index] шириной [width] пикселей.
  static Future<ui.Image?> render(int id, int index, int width) async {
    final r = await _ch.invokeMapMethod<String, Object?>('render', {'id': id, 'index': index, 'width': width});
    final w = r?['w'] as int?;
    final h = r?['h'] as int?;
    final px = r?['pixels'];
    if (w == null || h == null || px is! Uint8List) return null;
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  static Future<void> close(int id) async {
    try {
      await _ch.invokeMethod<void>('close', {'id': id});
    } catch (_) {}
  }
}

class PdfView extends StatefulWidget {
  const PdfView({super.key, required this.path, required this.onUnsupported});

  final String path;

  /// PDF не открылся (пароль, повреждён): [protected] — защищён паролем.
  final void Function(bool protected, Object error) onUnsupported;

  @override
  State<PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<PdfView> {
  static const _margin = 8.0;
  static const _gap = 8.0;

  /// Сколько страниц держать в памяти.
  static const _keep = 8;

  /// Ступени резкости (во сколько раз шире экрана): перерисовка — не на
  /// каждое изменение масштаба, а при переходе на следующую ступень.
  static const _steps = [1.0, 1.5, 2.0, 3.0, 4.0, 6.0];

  NativePdfDocument? _doc;
  final _tc = TransformationController();
  final Map<int, ({ui.Image image, int width})> _images = {};
  final Set<int> _inFlight = {};
  List<double> _tops = const [];
  double _layoutWidth = 0;
  double _contentHeight = 0;
  Rect _view = Rect.zero;
  double _viewportHeight = 0;
  bool _interacting = false;
  int _page = 0;
  bool _showPage = false;
  Timer? _pageTimer;
  Offset? _doubleTapAt;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final d = await NativePdf.open(widget.path);
      if (!mounted) {
        unawaited(NativePdf.close(d.id));
        return;
      }
      if (d.sizes.isEmpty) {
        unawaited(NativePdf.close(d.id));
        widget.onUnsupported(false, 'empty');
        return;
      }
      setState(() => _doc = d);
    } on PlatformException catch (e) {
      if (mounted) widget.onUnsupported(e.code == 'protected', e);
    } catch (e) {
      if (mounted) widget.onUnsupported(false, e);
    }
  }

  @override
  void dispose() {
    _pageTimer?.cancel();
    _tc.dispose();
    for (final v in _images.values) {
      v.image.dispose();
    }
    _images.clear();
    final d = _doc;
    if (d != null) unawaited(NativePdf.close(d.id));
    super.dispose();
  }

  void _layout(double width) {
    final d = _doc!;
    if ((width - _layoutWidth).abs() < 0.5 && _tops.length == d.sizes.length) return;
    _layoutWidth = width;
    final pw = width - 2 * _margin;
    final tops = <double>[];
    var y = _gap;
    for (final s in d.sizes) {
      tops.add(y);
      y += pw * s.height / (s.width <= 0 ? 1 : s.width) + _gap;
    }
    _tops = tops;
    _contentHeight = y;
  }

  double _pageHeight(int i) {
    final s = _doc!.sizes[i];
    return (_layoutWidth - 2 * _margin) * s.height / (s.width <= 0 ? 1 : s.width);
  }

  /// Видимые страницы и по одной сверху и снизу.
  List<int> _visible() {
    final d = _doc;
    if (d == null || _tops.isEmpty) return const [];
    final out = <int>[];
    final pad = _view.height;
    for (var i = 0; i < _tops.length; i++) {
      final top = _tops[i];
      final bottom = top + _pageHeight(i);
      if (bottom < _view.top - pad) continue;
      if (top > _view.bottom + pad) break;
      out.add(i);
    }
    return out;
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  int _targetWidth() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final base = (_layoutWidth - 2 * _margin) * dpr;
    final s = _scale;
    final step = _steps.firstWhere((x) => x >= s - 0.05, orElse: () => _steps.last);
    return math.min((base * step).round(), 4096);
  }

  void _request() {
    final d = _doc;
    if (d == null || _interacting || !mounted) return;
    final want = _targetWidth();
    final visible = _visible();
    // Сначала видимые — по близости к середине экрана.
    final mid = _view.center.dy;
    visible.sort((a, b) =>
        (_tops[a] + _pageHeight(a) / 2 - mid).abs().compareTo((_tops[b] + _pageHeight(b) / 2 - mid).abs()));
    for (final i in visible) {
      if (_inFlight.length >= 2) break;
      if (_inFlight.contains(i)) continue;
      final have = _images[i];
      if (have != null && have.width >= want * 0.9) continue;
      _inFlight.add(i);
      unawaited(NativePdf.render(d.id, i, want).then((img) {
        _inFlight.remove(i);
        if (!mounted || img == null) {
          img?.dispose();
          return;
        }
        _images.remove(i)?.image.dispose();
        _images[i] = (image: img, width: want);
        _evict();
        setState(() {});
        _request();
      }, onError: (Object _) {
        _inFlight.remove(i);
      }));
    }
  }

  void _evict() {
    if (_images.length <= _keep) return;
    final mid = _view.center.dy;
    final keys = _images.keys.toList()
      ..sort((a, b) => (_tops[b] - mid).abs().compareTo((_tops[a] - mid).abs()));
    for (final k in keys) {
      if (_images.length <= _keep) break;
      _images.remove(k)?.image.dispose();
    }
  }

  void _onViewChanged(Rect view) {
    _view = view;
    var p = 0;
    final mid = view.center.dy;
    for (var i = 0; i < _tops.length; i++) {
      if (_tops[i] <= mid) p = i;
    }
    if (p != _page || !_showPage) {
      _page = p;
      _showPage = true;
    }
    _pageTimer?.cancel();
    _pageTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showPage = false);
    });
  }

  void _toggleZoom() {
    final at = _doubleTapAt;
    if (at == null) return;
    if (_scale > 1.05) {
      // Назад к ширине экрана — с тем же местом наверху.
      final maxY = math.max(0.0, _contentHeight - _viewportHeight);
      _tc.value = Matrix4.translationValues(0, -_view.top.clamp(0.0, maxY), 0);
    } else {
      const k = 2.5;
      _tc.value = Matrix4.translationValues(at.dx, at.dy, 0)
        ..multiply(Matrix4.diagonal3Values(k, k, 1))
        ..multiply(Matrix4.translationValues(-at.dx, -at.dy, 0))
        ..multiply(_tc.value);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  @override
  Widget build(BuildContext context) {
    final d = _doc;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      _layout(box.maxWidth);
      _viewportHeight = box.maxHeight;
      return Stack(children: [
        Positioned.fill(
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: GestureDetector(
              onDoubleTapDown: (e) => _doubleTapAt = e.localPosition,
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer.builder(
                transformationController: _tc,
                minScale: 1,
                maxScale: 6,
                boundaryMargin: EdgeInsets.zero,
                onInteractionStart: (_) => _interacting = true,
                onInteractionEnd: (_) {
                  _interacting = false;
                  _request();
                },
                builder: (context, quad) {
                  final xs = [quad.point0.x, quad.point1.x, quad.point2.x, quad.point3.x];
                  final ys = [quad.point0.y, quad.point1.y, quad.point2.y, quad.point3.y];
                  final view = Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
                  if (view != _view) {
                    _onViewChanged(view);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {});
                      _request();
                    });
                  }
                  final pw = _layoutWidth - 2 * _margin;
                  return SizedBox(
                    width: _layoutWidth,
                    height: math.max(_contentHeight, box.maxHeight),
                    child: Stack(children: [
                      for (final i in _visible())
                        Positioned(
                          left: _margin,
                          top: _tops[i],
                          width: pw,
                          height: _pageHeight(i),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.white, boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 3, offset: const Offset(0, 1)),
                            ]),
                            child: _images[i] == null
                                ? null
                                : RawImage(image: _images[i]!.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                          ),
                        ),
                    ]),
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showPage ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                  child: Text('${_page + 1} / ${d.sizes.length}',
                      style: theme.textTheme.labelLarge?.copyWith(color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

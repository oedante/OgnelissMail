// lib/features/mail/widgets/doc_sheet_view.dart
// Таблица из вложения (XLSX, ODS, CSV) сеткой, как в Excel (1.11.x,
// предпросмотр документов, план владельца 04.11.2026).
//
// Как устроено:
//  · сетка — один RenderBox, который рисует только видимые ячейки (и
//    заголовки «A, B, C…» и «1, 2, 3…», закреплённые сверху и слева, и
//    закреплённые в файле строки и столбцы); прокрутка в обе стороны —
//    TwoDimensionalScrollable фреймворка: физика платформы, колесо мыши,
//    тачпад, полосы прокрутки. Лист в 10 000 × 100 листается так же плавно,
//    как в 10 × 10: текст ячеек раскладывается при первом показе и хранится
//    в небольшом кэше;
//  · жест вбок по сетке листает сетку, а не вложения: распознаватель
//    сетки срабатывает на том же сдвиге пальца, что и у PageView экрана, и
//    получает касание первым;
//  · щипок — масштаб от ×0,5 до ×3 (на компьютере — Ctrl и колесо), точка
//    между пальцами остаётся на месте;
//  · касание ячейки — её полный текст в строке над сеткой (выделяется и
//    копируется), как строка формул Excel: длинный текст, обрезанный
//    ячейкой, становится читаемым;
//  · цвета: ячейки без заливки — цвета поверхности темы; заливки из файла
//    сохраняются (белая в тёмной теме — как фон), текст на них — читаемый;
//    тёмный текст на тёмном фоне становится светлым;
//  · несколько листов — вкладки внизу, как в Excel.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/documents/doc_sheets.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class DocSheetView extends StatefulWidget {
  const DocSheetView({super.key, required this.doc});

  final OfficeSheetsDoc doc;

  @override
  State<DocSheetView> createState() => _DocSheetViewState();
}

class _DocSheetViewState extends State<DocSheetView> {
  static const _minZoom = 0.5;
  static const _maxZoom = 3.0;
  static const _barHeight = 40.0;

  late int _index = widget.doc.sheets.isEmpty ? 0 : widget.doc.activeSheet.clamp(0, widget.doc.sheets.length - 1);
  final _h = ScrollController();
  final _v = ScrollController();
  final _focus = FocusNode(debugLabel: 'DocSheetView');
  final _cache = _TextCache();
  _Geo? _geo;
  double _zoom = 1;
  Offset? _focal;
  double _pinchStart = 1;
  ({int row, int col})? _sel;
  bool _barOpen = false;
  final Map<int, ({double x, double y, double zoom})> _saved = {};
  Brightness? _brightness;
  String? _font;

  DocSheet? get _sheet => widget.doc.sheets.isEmpty ? null : widget.doc.sheets[_index];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Цвета текста лежат в раскладке ячеек — при смене темы кэш заново.
    final theme = Theme.of(context);
    final font = theme.textTheme.bodyMedium?.fontFamily;
    if (_brightness != theme.brightness || _font != font) {
      _brightness = theme.brightness;
      _font = font;
      _cache.clear();
    }
  }

  @override
  void didUpdateWidget(DocSheetView old) {
    super.didUpdateWidget(old);
    if (!identical(old.doc, widget.doc)) {
      _cache.clear();
      _geo = null;
      _sel = null;
      _saved.clear();
      _index = widget.doc.sheets.isEmpty ? 0 : widget.doc.activeSheet.clamp(0, widget.doc.sheets.length - 1);
    }
  }

  @override
  void dispose() {
    _cache.clear();
    _h.dispose();
    _v.dispose();
    _focus.dispose();
    super.dispose();
  }

  _Geo _geoOf(DocSheet s) {
    final g = _geo;
    if (g != null && identical(g.sheet, s)) return g;
    return _geo = _Geo(s);
  }

  void _switchTo(int i) {
    if (i == _index) return;
    _saved[_index] = (x: _h.hasClients ? _h.offset : 0, y: _v.hasClients ? _v.offset : 0, zoom: _zoom);
    final back = _saved[i];
    // Положение листа — без анимации и до раскладки (пределы прокрутки
    // поправит раскладка нового листа).
    if (_h.hasClients) _h.position.correctPixels(back?.x ?? 0);
    if (_v.hasClients) _v.position.correctPixels(back?.y ?? 0);
    setState(() {
      _index = i;
      _zoom = back?.zoom ?? 1;
      _focal = null;
      _sel = null;
      _barOpen = false;
      _cache.clear();
    });
  }

  void _setZoom(double z, Offset? focal) {
    final next = z.clamp(_minZoom, _maxZoom);
    if ((next - _zoom).abs() < 0.001) return;
    setState(() {
      _zoom = next;
      _focal = focal;
    });
  }

  void _select(({int row, int col})? cell) {
    final s = _sheet;
    if (s == null) return;
    var c = cell;
    if (cell != null) {
      // Объединённые ячейки — как одна: выбирается первая.
      for (final m in s.merges) {
        if (m.contains(cell.row, cell.col)) {
          c = (row: m.row, col: m.col);
          break;
        }
      }
    }
    setState(() {
      _sel = c;
      _barOpen = false;
    });
  }

  String _selText() {
    final s = _sheet;
    final c = _sel;
    if (s == null || c == null) return '';
    return s.cell(c.row, c.col)?.text ?? '';
  }

  Future<void> _copy() async {
    final t = _selText();
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    showInlineNotice(AppLocalizations.of(context).tr('copied'));
  }

  // ── Клавиатура (компьютер): стрелки двигают выделение, Ctrl+C — копия ──

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final s = _sheet;
    if (s == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final hw = HardwareKeyboard.instance;
    if ((hw.isControlPressed || hw.isMetaPressed) && k == LogicalKeyboardKey.keyC) {
      _copy();
      return KeyEventResult.handled;
    }
    final cur = _sel ?? (row: 0, col: 0);
    ({int row, int col})? next;
    if (k == LogicalKeyboardKey.arrowDown) next = (row: cur.row + 1, col: cur.col);
    if (k == LogicalKeyboardKey.arrowUp) next = (row: math.max(0, cur.row - 1), col: cur.col);
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.tab) next = (row: cur.row, col: cur.col + 1);
    if (k == LogicalKeyboardKey.arrowLeft) next = (row: cur.row, col: math.max(0, cur.col - 1));
    if (next == null) return KeyEventResult.ignored;
    final g = _geoOf(s);
    // Мимо скрытых строк и столбцов.
    final down = next.row > cur.row, right = next.col > cur.col;
    var r = next.row, c = next.col;
    while (g.h(r) == 0 && r > 0 && r < SheetLimits.maxRows) {
      r += down ? 1 : -1;
    }
    while (g.w(c) == 0 && c > 0 && c < SheetLimits.maxCols) {
      c += right ? 1 : -1;
    }
    r = r.clamp(0, math.max(s.rowCount, 1) + 200);
    c = c.clamp(0, math.max(s.colCount, 1) + 50);
    _select((row: r, col: c));
    _reveal(r, c);
    return KeyEventResult.handled;
  }

  /// Прокрутить так, чтобы ячейка была видна.
  void _reveal(int r, int c) {
    final s = _sheet;
    final box = _gridSize;
    if (s == null || box == null || !_h.hasClients || !_v.hasClients) return;
    final g = _geoOf(s);
    final f = g.frame(box, _zoom);
    if (c >= f.fc) {
      final x0 = (g.x(c) - g.x(f.fc)) * _zoom, x1 = (g.x(c + 1) - g.x(f.fc)) * _zoom;
      final w = box.width - f.left;
      if (x0 < _h.offset) _h.jumpTo(x0);
      if (x1 > _h.offset + w) _h.jumpTo(math.min(x1 - w, math.max(x0, 0)));
    }
    if (r >= f.fr) {
      final y0 = (g.y(r) - g.y(f.fr)) * _zoom, y1 = (g.y(r + 1) - g.y(f.fr)) * _zoom;
      final hgt = box.height - f.top;
      if (y0 < _v.offset) _v.jumpTo(y0);
      if (y1 > _v.offset + hgt) _v.jumpTo(math.min(y1 - hgt, math.max(y0, 0)));
    }
  }

  Size? _gridSize;

  void _onTap(Offset p) {
    final s = _sheet;
    final box = _gridSize;
    if (s == null || box == null) return;
    _focus.requestFocus();
    final cell = _geoOf(s).hit(p, box, _zoom, _h.hasClients ? _h.offset : 0, _v.hasClients ? _v.offset : 0);
    _select(cell);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final hw = HardwareKeyboard.instance;
    if (!hw.isControlPressed && !hw.isMetaPressed) return;
    // Ctrl + колесо — масштаб (раньше прокрутки: она зарегистрируется позже).
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final d = (ev as PointerScrollEvent).scrollDelta.dy;
      if (d == 0) return;
      _setZoom(_zoom * (d < 0 ? 1.1 : 1 / 1.1), ev.localPosition);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _sheet;
    final sheets = widget.doc.sheets;
    final body = s == null || s.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(Space.xl),
              child: Text(
                s != null && s.truncated ? l10n.tr('docSheetTruncated') : l10n.tr('docSheetEmpty'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.mutedText(context)),
              ),
            ),
          )
        : Stack(
            children: [
              Positioned.fill(top: _barHeight, child: _grid(s, theme)),
              Positioned(top: 0, left: 0, right: 0, child: _bar(s, theme, l10n)),
              if ((_zoom - 1).abs() > 0.01)
                Positioned(
                  right: Space.m,
                  bottom: Space.m,
                  child: ActionChip(
                    avatar: const Icon(AppIcons.zoom_in, size: Sizes.iconInline),
                    label: Text('${(_zoom * 100).round()}%'),
                    onPressed: () => _setZoom(1, null),
                  ),
                ),
            ],
          );
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(child: body),
          if (s != null && s.truncated && !s.isEmpty) _truncatedNote(theme, l10n),
          if (sheets.length > 1) _tabs(theme),
        ],
      ),
    );
  }

  Widget _truncatedNote(ThemeData theme, AppLocalizations l10n) {
    final muted = AppColors.mutedText(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Row(
        children: [
          Icon(AppIcons.info, size: Sizes.iconInline, color: muted),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(l10n.tr('docSheetTruncated'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ],
      ),
    );
  }

  /// Строка над сеткой: адрес ячейки и её полный текст.
  Widget _bar(DocSheet s, ThemeData theme, AppLocalizations l10n) {
    final scheme = theme.colorScheme;
    final muted = AppColors.mutedText(context);
    final c = _sel;
    final text = _selText();
    final long = text.contains('\n') || text.length > 60;
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: _barOpen ? 3 : 0,
      child: Container(
        constraints: BoxConstraints(minHeight: _barHeight, maxHeight: _barOpen ? 220 : _barHeight),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: _barOpen ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: _barHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Text(
                c == null ? '' : '${SheetRef.colName(c.col)}${c.row + 1}',
                style: theme.textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            Expanded(
              child: c == null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      child: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 10),
                      physics: _barOpen ? null : const NeverScrollableScrollPhysics(),
                      child: SelectableText(
                        text,
                        key: ValueKey('bar_${c.row}_${c.col}_$_barOpen'),
                        maxLines: _barOpen ? null : 1,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
            ),
            if (c != null && long)
              IconButton(
                icon: Icon(_barOpen ? AppIcons.expand_less : AppIcons.expand_more),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _barOpen = !_barOpen),
              ),
            if (c != null && text.isNotEmpty)
              IconButton(
                icon: const Icon(AppIcons.content_copy, size: Sizes.iconRow),
                tooltip: l10n.tr('copy'),
                visualDensity: VisualDensity.compact,
                onPressed: _copy,
              ),
          ],
        ),
      ),
    );
  }

  /// Вкладки листов внизу, как в Excel.
  Widget _tabs(ThemeData theme) {
    final scheme = theme.colorScheme;
    final sheets = widget.doc.sheets;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.s),
        itemCount: sheets.length,
        itemBuilder: (context, i) {
          final on = i == _index;
          return Semantics(
            selected: on,
            button: true,
            child: InkWell(
              key: ValueKey('sheetTab$i'),
              onTap: () => _switchTo(i),
              child: Container(
                constraints: const BoxConstraints(minWidth: 64, maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? scheme.surface : null,
                  border: Border(top: BorderSide(color: on ? scheme.primary : Colors.transparent, width: 3)),
                ),
                child: Text(
                  sheets[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: on ? scheme.primary : AppColors.mutedText(context),
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _grid(DocSheet s, ThemeData theme) {
    final g = _geoOf(s);
    final colors = _GridColors.of(theme);
    final mq = MediaQuery.of(context);
    final slop = mq.gestureSettings.touchSlop ?? kTouchSlop;
    return LayoutBuilder(
      builder: (context, box) {
        _gridSize = box.biggest;
        final hh = _Geo.colHeaderH * _zoom, rw = g.rowHeaderW * _zoom;
        Widget bar(Widget child, Axis axis, EdgeInsets pad) => MediaQuery(
          data: mq.copyWith(padding: pad),
          child: Scrollbar(
            controller: axis == Axis.vertical ? _v : _h,
            notificationPredicate: (n) => n.metrics.axis == axis,
            child: child,
          ),
        );
        // Касание сетки — свой распознаватель «перетаскивания в обе стороны»
        // фреймворка; он срабатывает на удвоенном пороге сдвига. Половинный
        // порог внутри сетки уравнивает его с порогом PageView экрана: сетка
        // получает жест первой и листается сама.
        final grid = MediaQuery(
          data: mq.copyWith(gestureSettings: DeviceGestureSettings(touchSlop: slop / 2)),
          child: TwoDimensionalScrollable(
            horizontalDetails: ScrollableDetails.horizontal(controller: _h),
            verticalDetails: ScrollableDetails.vertical(controller: _v),
            diagonalDragBehavior: DiagonalDragBehavior.weightedEvent,
            viewportBuilder: (context, vertical, horizontal) => Listener(
              onPointerSignal: _onSignal,
              child: RawGestureDetector(
                gestures: {
                  // Щипок: второй палец — сразу масштаб (прокрутка его не
                  // перехватывает); одним пальцем — прокрутка.
                  _PinchRecognizer: GestureRecognizerFactoryWithHandlers<_PinchRecognizer>(
                    _PinchRecognizer.new,
                    (r) => r
                      ..onStart = (d) {
                        _pinchStart = _zoom;
                      }
                      ..onUpdate = (d) {
                        if (d.pointerCount < 2 || d.scale == 1) return;
                        _setZoom(_pinchStart * d.scale, d.localFocalPoint);
                      }
                      ..onEnd = (d) {
                        if ((_zoom - 1).abs() < 0.06) _setZoom(1, null);
                      },
                  ),
                  TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                    TapGestureRecognizer.new,
                    (r) => r.onTapUp = (d) => _onTap(d.localPosition),
                  ),
                },
                child: _GridViewport(
                  geo: g,
                  styles: widget.doc.styles,
                  zoom: _zoom,
                  focal: _focal,
                  vertical: vertical,
                  horizontal: horizontal,
                  colors: colors,
                  selection: _sel,
                  cache: _cache,
                  dpr: mq.devicePixelRatio,
                  onSelect: _select,
                ),
              ),
            ),
          ),
        );
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: SystemMouseCursors.cell,
            child: Semantics(
              label: s.name,
              child: bar(
                bar(grid, Axis.horizontal, EdgeInsets.only(left: rw)),
                Axis.vertical,
                EdgeInsets.only(top: hh),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Масштаб двумя пальцами: как только на сетке второй палец, жест —
/// масштаб. Иначе прокрутка, у которой порог сдвига меньше, забирает и
/// щипок (пальцы расходятся — это тоже сдвиг).
class _PinchRecognizer extends ScaleGestureRecognizer {
  _PinchRecognizer() : super(supportedDevices: const {PointerDeviceKind.touch});

  final Set<int> _down = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) _down.remove(event.pointer);
    super.handleEvent(event);
  }

  @override
  void rejectGesture(int pointer) {
    _down.remove(pointer);
    super.rejectGesture(pointer);
  }
}

// ── Геометрия листа ──

class _Frame {
  /// Закреплённые столбцы и строки (0 — закрепление не помещается).
  final int fc, fr;

  /// Где на экране начинаются прокручиваемые столбцы и строки.
  final double left, top;
  final double maxX, maxY;
  const _Frame(this.fc, this.fr, this.left, this.top, this.maxX, this.maxY);
}

class _Geo {
  _Geo(this.sheet) {
    final n = sheet.colCount, m = sheet.rowCount;
    colLeft = Float64List(n + 1);
    for (var c = 0; c < n; c++) {
      colLeft[c + 1] = colLeft[c] + sheet.colWidths[c];
    }
    rowTop = Float64List(m + 1);
    for (var r = 0; r < m; r++) {
      rowTop[r + 1] = rowTop[r] + sheet.rowHeights[r];
    }
    final digits = (m + 200).toString().length;
    rowHeaderW = math.max(34.0, 14 + 7.5 * digits);
    merges = List.of(sheet.merges)..sort((a, b) => a.row.compareTo(b.row));
  }

  final DocSheet sheet;
  late final Float64List colLeft;
  late final Float64List rowTop;
  late final double rowHeaderW;
  late final List<DocMerge> merges;
  static const colHeaderH = 22.0;

  double get dw => sheet.defaultColWidth > 0 ? sheet.defaultColWidth : 64;
  double get dh => sheet.defaultRowHeight > 0 ? sheet.defaultRowHeight : 20;
  double get width => colLeft[sheet.colCount];
  double get height => rowTop[sheet.rowCount];

  double x(int c) => c <= sheet.colCount ? colLeft[c] : width + (c - sheet.colCount) * dw;
  double y(int r) => r <= sheet.rowCount ? rowTop[r] : height + (r - sheet.rowCount) * dh;
  double w(int c) => c < sheet.colCount ? sheet.colWidths[c] : dw;
  double h(int r) => r < sheet.rowCount ? sheet.rowHeights[r] : dh;

  /// Столбец под точкой листа [sx] (за данными — столбцы по умолчанию).
  int colAt(double sx) => _at(colLeft, sheet.colCount, sx, dw);
  int rowAt(double sy) => _at(rowTop, sheet.rowCount, sy, dh);

  static int _at(Float64List edges, int n, double v, double d) {
    if (v <= 0 || n == 0) return v <= 0 ? 0 : (v / d).floor();
    if (v >= edges[n]) return n + ((v - edges[n]) / d).floor();
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (edges[mid] <= v) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  _Frame frame(Size size, double z) {
    var fc = sheet.frozenCols, fr = sheet.frozenRows;
    // Закрепление шире большей части экрана (телефон) — без него: иначе
    // остальной лист не увидеть.
    if (x(fc) * z > (size.width - rowHeaderW * z) * 0.6) fc = 0;
    if (y(fr) * z > (size.height - colHeaderH * z) * 0.6) fr = 0;
    final left = (rowHeaderW + x(fc)) * z;
    final top = (colHeaderH + y(fr)) * z;
    final maxX = math.max(0.0, (width - x(fc)) * z - (size.width - left));
    final maxY = math.max(0.0, (height - y(fr)) * z - (size.height - top));
    return _Frame(fc, fr, left, top, maxX, maxY);
  }

  /// Ячейка под точкой [p] сетки; заголовки — null.
  ({int row, int col})? hit(Offset p, Size size, double z, double ox, double oy) {
    final f = frame(size, z);
    if (p.dx < rowHeaderW * z || p.dy < colHeaderH * z) return null;
    final sx = p.dx < f.left ? p.dx / z - rowHeaderW : (p.dx - f.left + ox) / z + x(f.fc);
    final sy = p.dy < f.top ? p.dy / z - colHeaderH : (p.dy - f.top + oy) / z + y(f.fr);
    return (row: rowAt(sy), col: colAt(sx));
  }
}

// ── Цвета ──

class _GridColors {
  final Color surface, onSurface, grid, header, headerText, headerLine, selection, selectedHeader, frozenLine;
  final bool dark;
  final String? font;
  const _GridColors(
    this.surface,
    this.onSurface,
    this.grid,
    this.header,
    this.headerText,
    this.headerLine,
    this.selection,
    this.selectedHeader,
    this.frozenLine,
    this.dark,
    this.font,
  );

  factory _GridColors.of(ThemeData t) {
    final s = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return _GridColors(
      s.surface,
      s.onSurface,
      s.onSurface.withValues(alpha: dark ? 0.16 : 0.13),
      s.surfaceContainerHigh,
      s.onSurfaceVariant,
      s.outlineVariant,
      s.primary,
      s.primaryContainer,
      s.outline,
      dark,
      t.textTheme.bodyMedium?.fontFamily,
    );
  }

  @override
  bool operator ==(Object o) =>
      o is _GridColors &&
      o.surface == surface &&
      o.onSurface == onSurface &&
      o.selection == selection &&
      o.dark == dark &&
      o.font == font;

  @override
  int get hashCode => Object.hash(surface, onSurface, selection, dark, font);

  /// Заливка ячейки; null — фон сетки. Белая заливка в тёмной теме — это
  /// «бумага», а не цвет: как фон (иначе белые пятна на тёмном экране).
  Color? fill(int? argb) {
    if (argb == null) return null;
    final c = Color(argb);
    if (dark && (argb & 0xFF) >= 0xF0 && ((argb >> 8) & 0xFF) >= 0xF0 && ((argb >> 16) & 0xFF) >= 0xF0) return null;
    return c;
  }

  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Цвет текста на фоне [bg]: автоматический — тема или контрастный к
  /// заливке; явный нечитаемый (чёрный в тёмной теме) — с той же гаммой,
  /// но светлее или темнее.
  Color text(int? argb, Color? bg) {
    final back = bg ?? surface;
    if (argb == null) {
      if (bg == null) return onSurface;
      return back.computeLuminance() > 0.4 ? const Color(0xFF1B1B1B) : Colors.white;
    }
    final c = Color(argb);
    if (contrast(c, back) >= 3) return c;
    final hsl = HSLColor.fromColor(c);
    final light = back.computeLuminance() < 0.4;
    final l = light ? math.max(0.72, 1 - hsl.lightness) : math.min(0.32, 1 - hsl.lightness);
    final adapted = hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
    if (contrast(adapted, back) >= 3) return adapted;
    return light ? Colors.white : const Color(0xFF1B1B1B);
  }
}

// ── Кэш раскладки текста ──

/// Раскладка текста ячеек и заголовков: последние ~2000 — в памяти, старые
/// освобождаются (TextPainter держит память движка).
class _TextCache {
  static const _max = 2000;
  // Обычный Map Dart хранит порядок вставки: первый — самый старый.
  final _cells = <int, TextPainter>{};
  final _labels = <String, TextPainter>{};

  TextPainter cell(int key, TextPainter Function() make) => _get(_cells, key, make);
  TextPainter label(String key, TextPainter Function() make) => _get(_labels, key, make);

  static TextPainter _get<K>(Map<K, TextPainter> map, K key, TextPainter Function() make) {
    final hit = map.remove(key);
    if (hit != null) {
      map[key] = hit;
      return hit;
    }
    final p = make();
    map[key] = p;
    while (map.length > _max) {
      final first = map.keys.first;
      map.remove(first)?.dispose();
    }
    return p;
  }

  void clear() {
    for (final p in _cells.values) {
      p.dispose();
    }
    for (final p in _labels.values) {
      p.dispose();
    }
    _cells.clear();
    _labels.clear();
  }
}

// ── Сетка ──

class _GridViewport extends LeafRenderObjectWidget {
  const _GridViewport({
    required this.geo,
    required this.styles,
    required this.zoom,
    required this.focal,
    required this.vertical,
    required this.horizontal,
    required this.colors,
    required this.selection,
    required this.cache,
    required this.dpr,
    this.onSelect,
  });

  final _Geo geo;
  final List<DocCellStyle> styles;
  final double zoom;
  final Offset? focal;
  final ViewportOffset vertical;
  final ViewportOffset horizontal;
  final _GridColors colors;
  final ({int row, int col})? selection;
  final _TextCache cache;
  final double dpr;

  /// Выбор ячейки из доступности (двойное касание с TalkBack/VoiceOver).
  final ValueChanged<({int row, int col})>? onSelect;

  @override
  _RenderGrid createRenderObject(BuildContext context) =>
      _RenderGrid(geo, styles, zoom, focal, vertical, horizontal, colors, selection, cache, dpr)..onSelect = onSelect;

  @override
  void updateRenderObject(BuildContext context, _RenderGrid r) {
    r
      ..geo = geo
      ..styles = styles
      ..focal = focal
      ..zoom = zoom
      ..vertical = vertical
      ..horizontal = horizontal
      ..colors = colors
      ..selection = selection
      ..cache = cache
      ..dpr = dpr
      ..onSelect = onSelect;
  }
}

class _RenderGrid extends RenderBox {
  _RenderGrid(
    this._geo,
    this._styles,
    this._zoom,
    this.focal,
    this._v,
    this._h,
    this._colors,
    this._sel,
    this.cache,
    this._dpr,
  );

  _Geo _geo;
  List<DocCellStyle> _styles;
  double _zoom;
  Offset? focal;
  ViewportOffset _v;
  ViewportOffset _h;
  _GridColors _colors;
  ({int row, int col})? _sel;
  _TextCache cache;
  double _dpr;

  double? _laidZoom;
  _Frame? _laidFrame;
  ValueChanged<({int row, int col})>? onSelect;

  set geo(_Geo v) {
    if (identical(v, _geo)) return;
    _geo = v;
    _laidZoom = null;
    markNeedsLayout();
  }

  set styles(List<DocCellStyle> v) {
    if (identical(v, _styles)) return;
    _styles = v;
    markNeedsPaint();
  }

  set zoom(double v) {
    if (v == _zoom) return;
    _zoom = v;
    markNeedsLayout();
  }

  set vertical(ViewportOffset v) {
    if (v == _v) return;
    if (attached) _v.removeListener(_scrolled);
    _v = v;
    if (attached) _v.addListener(_scrolled);
    markNeedsLayout();
  }

  set horizontal(ViewportOffset v) {
    if (v == _h) return;
    if (attached) _h.removeListener(_scrolled);
    _h = v;
    if (attached) _h.addListener(_scrolled);
    markNeedsLayout();
  }

  set colors(_GridColors v) {
    if (v == _colors) return;
    _colors = v;
    markNeedsPaint();
  }

  set selection(({int row, int col})? v) {
    if (v == _sel) return;
    _sel = v;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  set dpr(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  void _scrolled() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _v.addListener(_scrolled);
    _h.addListener(_scrolled);
  }

  @override
  void detach() {
    _v.removeListener(_scrolled);
    _h.removeListener(_scrolled);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    final f = _geo.frame(size, _zoom);
    final old = _laidZoom, of = _laidFrame;
    if (old != null && of != null && old != _zoom) {
      // Новый масштаб: точка под пальцами (или середина) остаётся на месте.
      final p = focal ?? size.center(Offset.zero);
      double keep(double pixels, double pos, double oldStart, double newStart, double max) {
        final v = pos >= oldStart ? (pos - oldStart + pixels) / old * _zoom - (pos - newStart) : pixels / old * _zoom;
        return v.clamp(0.0, max);
      }

      final nx = keep(_h.pixels, p.dx, of.left, f.left, f.maxX);
      final ny = keep(_v.pixels, p.dy, of.top, f.top, f.maxY);
      _h.correctBy(nx - _h.pixels);
      _v.correctBy(ny - _v.pixels);
    }
    _laidZoom = _zoom;
    _laidFrame = f;
    _h.applyViewportDimension(size.width);
    _v.applyViewportDimension(size.height);
    _h.applyContentDimensions(0, f.maxX);
    _v.applyContentDimensions(0, f.maxY);
  }

  // Размеры в точках листа (до масштаба).
  static const _pad = 3.0;

  /// Что сейчас на экране: рамка закрепления, сдвиг прокручиваемой части
  /// (экранные точки) и видимые в ней столбцы и строки.
  ({_Frame f, double hw, double hh, double tx, double ty, int c0, int c1, int r0, int r1}) _view() {
    final z = _zoom, g = _geo;
    final f = _laidFrame ?? g.frame(size, z);
    final ox = _h.pixels.clamp(0.0, math.max(0.0, f.maxX));
    final oy = _v.pixels.clamp(0.0, math.max(0.0, f.maxY));
    final tx = f.left - g.x(f.fc) * z - ox;
    final ty = f.top - g.y(f.fr) * z - oy;
    return (
      f: f,
      hw: g.rowHeaderW * z,
      hh: _Geo.colHeaderH * z,
      tx: tx,
      ty: ty,
      c0: math.max(f.fc, g.colAt((f.left - tx) / z)),
      c1: g.colAt((size.width - tx) / z),
      r0: math.max(f.fr, g.rowAt((f.top - ty) / z)),
      r1: g.rowAt((size.height - ty) / z),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final v = _view();
    final f = v.f, hw = v.hw, hh = v.hh, mainTx = v.tx, mainTy = v.ty, c0 = v.c0, c1 = v.c1, r0 = v.r0, r1 = v.r1;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = _colors.surface);

    _region(canvas, Rect.fromLTRB(f.left, f.top, size.width, size.height), mainTx, mainTy, r0, r1, c0, c1);
    if (f.fr > 0) _region(canvas, Rect.fromLTRB(f.left, hh, size.width, f.top), mainTx, hh, 0, f.fr - 1, c0, c1);
    if (f.fc > 0) _region(canvas, Rect.fromLTRB(hw, f.top, f.left, size.height), hw, mainTy, r0, r1, 0, f.fc - 1);
    if (f.fr > 0 && f.fc > 0) _region(canvas, Rect.fromLTRB(hw, hh, f.left, f.top), hw, hh, 0, f.fr - 1, 0, f.fc - 1);

    // Заголовки столбцов и строк.
    final line = Paint()
      ..color = _colors.headerLine
      ..strokeWidth = 0;
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, hh), Paint()..color = _colors.header);
    canvas.drawRect(Rect.fromLTRB(0, 0, hw, size.height), Paint()..color = _colors.header);
    _colHeaders(canvas, Rect.fromLTRB(f.left, 0, size.width, hh), mainTx, c0, c1);
    if (f.fc > 0) _colHeaders(canvas, Rect.fromLTRB(hw, 0, f.left, hh), hw, 0, f.fc - 1);
    _rowHeaders(canvas, Rect.fromLTRB(0, f.top, hw, size.height), mainTy, r0, r1);
    if (f.fr > 0) _rowHeaders(canvas, Rect.fromLTRB(0, hh, hw, f.top), hh, 0, f.fr - 1);
    canvas.drawLine(Offset(0, hh), Offset(size.width, hh), line);
    canvas.drawLine(Offset(hw, 0), Offset(hw, size.height), line);
    // Граница закрепления.
    final frozen = Paint()
      ..color = _colors.frozenLine
      ..strokeWidth = 1;
    if (f.fc > 0) canvas.drawLine(Offset(f.left, hh), Offset(f.left, size.height), frozen);
    if (f.fr > 0) canvas.drawLine(Offset(hw, f.top), Offset(size.width, f.top), frozen);
    canvas.restore();
  }

  TextStyle _labelStyle(bool on) => TextStyle(
    fontFamily: _colors.font,
    fontSize: 11,
    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
    color: on ? _colors.selection : _colors.headerText,
  );

  TextPainter _label(String s, bool on) => cache.label('$s|$on', () {
    return TextPainter(
      text: TextSpan(text: s, style: _labelStyle(on)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
  });

  void _colHeaders(Canvas canvas, Rect clip, double tx, int c0, int c1) {
    final z = _zoom, g = _geo;
    canvas.save();
    canvas.clipRect(clip);
    canvas.translate(tx, 0);
    canvas.scale(z, z);
    final line = Paint()
      ..color = _colors.headerLine
      ..strokeWidth = 0;
    for (var c = c0; c <= c1; c++) {
      final w = g.w(c);
      if (w <= 0) continue;
      final x = g.x(c);
      final on = _sel?.col == c;
      if (on) canvas.drawRect(Rect.fromLTWH(x, 0, w, _Geo.colHeaderH), Paint()..color = _colors.selectedHeader);
      final p = _label(SheetRef.colName(c), on);
      if (p.width < w - 2) p.paint(canvas, Offset(x + (w - p.width) / 2, (_Geo.colHeaderH - p.height) / 2));
      canvas.drawLine(Offset(x + w, 0), Offset(x + w, _Geo.colHeaderH), line);
    }
    canvas.restore();
  }

  void _rowHeaders(Canvas canvas, Rect clip, double ty, int r0, int r1) {
    final z = _zoom, g = _geo;
    canvas.save();
    canvas.clipRect(clip);
    canvas.translate(0, ty);
    canvas.scale(z, z);
    final line = Paint()
      ..color = _colors.headerLine
      ..strokeWidth = 0;
    final w = g.rowHeaderW;
    for (var r = r0; r <= r1; r++) {
      final h = g.h(r);
      if (h <= 0) continue;
      final y = g.y(r);
      final on = _sel?.row == r;
      if (on) canvas.drawRect(Rect.fromLTWH(0, y, w, h), Paint()..color = _colors.selectedHeader);
      final p = _label('${r + 1}', on);
      if (p.height < h + 4) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, y, w, h));
        p.paint(canvas, Offset((w - p.width) / 2, y + (h - p.height) / 2));
        canvas.restore();
      }
      canvas.drawLine(Offset(0, y + h), Offset(w, y + h), line);
    }
    canvas.restore();
  }

  DocCellStyle _style(DocCell c) => c.style >= 0 && c.style < _styles.length ? _styles[c.style] : DocCellStyle.plain;

  DocMerge? _mergeAt(List<DocMerge> vis, int r, int c) {
    for (final m in vis) {
      if (m.contains(r, c)) return m;
    }
    return null;
  }

  /// Часть сетки: строки [r0]–[r1] и столбцы [c0]–[c1], нарисованные в
  /// [clip] со сдвигом [tx], [ty] (экранные точки).
  void _region(Canvas canvas, Rect clip, double tx, double ty, int r0, int r1, int c0, int c1) {
    if (clip.width <= 0 || clip.height <= 0 || r1 < r0 || c1 < c0) return;
    final z = _zoom, g = _geo, sheet = g.sheet;
    canvas.save();
    canvas.clipRect(clip);
    canvas.translate(tx, ty);
    canvas.scale(z, z);
    // Тонкая линия: 1 точка экрана на обычных экранах, 2 физических — на
    // плотных (иначе на 3× сетки почти не видно).
    final px = (_dpr >= 2.5 ? 2.0 : 1.0) / _dpr / z;

    // Объединения, задевающие видимую часть.
    final vis = <DocMerge>[];
    for (final m in g.merges) {
      if (m.row > r1) break;
      if (m.lastRow < r0 || m.lastCol < c0 || m.col > c1) continue;
      vis.add(m);
      if (vis.length > 400) break;
    }

    final top = g.y(r0), bottom = g.y(r1 + 1), left = g.x(c0), right = g.x(c1 + 1);
    // Линии сетки — одним контуром.
    if (sheet.showGrid) {
      final path = Path();
      for (var c = c0; c <= c1 + 1; c++) {
        if (c > c0 && g.w(c - 1) <= 0) continue;
        final x = g.x(c);
        path
          ..moveTo(x, top)
          ..lineTo(x, bottom);
      }
      for (var r = r0; r <= r1 + 1; r++) {
        if (r > r0 && g.h(r - 1) <= 0) continue;
        final y = g.y(r);
        path
          ..moveTo(left, y)
          ..lineTo(right, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = px
          ..color = _colors.grid,
      );
    }

    final rows = sheet.rows;
    final lastRow = math.min(r1, sheet.rowCount - 1);
    final fill = Paint();
    // Заливки (поверх линий сетки — как в Excel).
    for (var r = r0; r <= lastRow; r++) {
      final h = g.h(r);
      if (h <= 0) continue;
      final row = rows[r];
      for (var i = DocSheet.lowerBound(row, c0); i < row.length && row[i].col <= c1; i++) {
        final cell = row[i];
        final bg = _colors.fill(_style(cell).fill);
        if (bg == null || g.w(cell.col) <= 0) continue;
        if (vis.isNotEmpty && _mergeAt(vis, r, cell.col) != null) continue;
        canvas.drawRect(Rect.fromLTWH(g.x(cell.col), g.y(r), g.w(cell.col), h), fill..color = bg);
      }
    }
    // Объединения: фон без внутренних линий.
    for (final m in vis) {
      final anchor = sheet.cell(m.row, m.col);
      final bg = anchor == null ? null : _colors.fill(_style(anchor).fill);
      final rect = Rect.fromLTRB(g.x(m.col), g.y(m.row), g.x(m.lastCol + 1), g.y(m.lastRow + 1));
      canvas.drawRect(bg != null ? rect : rect.deflate(px * 0.75), fill..color = bg ?? _colors.surface);
    }
    // Рамки.
    for (var r = r0; r <= lastRow; r++) {
      final h = g.h(r);
      if (h <= 0) continue;
      final row = rows[r];
      for (var i = DocSheet.lowerBound(row, c0); i < row.length && row[i].col <= c1; i++) {
        final cell = row[i];
        final st = _style(cell);
        if (!st.hasBorders) continue;
        final m = vis.isEmpty ? null : _mergeAt(vis, r, cell.col);
        if (m != null) continue;
        _borders(canvas, st, Rect.fromLTWH(g.x(cell.col), g.y(r), g.w(cell.col), h));
      }
    }
    for (final m in vis) {
      final anchor = sheet.cell(m.row, m.col);
      if (anchor == null) continue;
      final st = _style(anchor);
      if (st.hasBorders) {
        _borders(canvas, st, Rect.fromLTRB(g.x(m.col), g.y(m.row), g.x(m.lastCol + 1), g.y(m.lastRow + 1)));
      }
    }
    // Текст.
    for (var r = r0; r <= lastRow; r++) {
      final h = g.h(r);
      if (h <= 0) continue;
      final row = rows[r];
      final start = DocSheet.lowerBound(row, c0);
      // Текст слева от видимой части может заходить в неё (длинный
      // заголовок в A1), справа — у выровненного вправо.
      for (var i = start - 1; i >= 0 && i >= start - 8; i--) {
        if (row[i].text.isEmpty) continue;
        _cellText(canvas, r, row[i], vis, row);
        break;
      }
      var i = start;
      for (; i < row.length && row[i].col <= c1; i++) {
        if (row[i].text.isNotEmpty) _cellText(canvas, r, row[i], vis, row);
      }
      for (var k = i; k < row.length && k < i + 8; k++) {
        if (row[k].text.isEmpty) continue;
        if (_style(row[k]).hAlign != DocHAlign.left) _cellText(canvas, r, row[k], vis, row);
        break;
      }
    }
    // Объединения, у которых первая ячейка за краем видимой части.
    for (final m in vis) {
      if (m.row >= r0 && m.row <= lastRow && m.col >= c0 && m.col <= c1) continue;
      final anchor = sheet.cell(m.row, m.col);
      if (anchor != null && anchor.text.isNotEmpty && m.row < sheet.rowCount) {
        _cellText(canvas, m.row, anchor, vis, rows[m.row]);
      }
    }
    // Выделение.
    final sel = _sel;
    if (sel != null && sel.row >= r0 && sel.row <= r1 && sel.col >= c0 && sel.col <= c1) {
      var rect = Rect.fromLTWH(g.x(sel.col), g.y(sel.row), g.w(sel.col), g.h(sel.row));
      for (final m in g.merges) {
        if (m.row == sel.row && m.col == sel.col) {
          rect = Rect.fromLTRB(g.x(m.col), g.y(m.row), g.x(m.lastCol + 1), g.y(m.lastRow + 1));
          break;
        }
        if (m.row > sel.row) break;
      }
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / z
          ..color = _colors.selection,
      );
    }
    canvas.restore();
  }

  void _borders(Canvas canvas, DocCellStyle st, Rect r) {
    final paint = Paint()..style = PaintingStyle.stroke;
    void side(DocBorder? b, Offset a, Offset c) {
      if (b == null) return;
      paint
        ..color = _colors
            .text(b.color ?? _colors.onSurface.toARGB32(), null)
            .withValues(alpha: b.color == null ? 0.8 : 1)
        ..strokeWidth = b.width / _zoom;
      canvas.drawLine(a, c, paint);
    }

    side(st.top, r.topLeft, r.topRight);
    side(st.bottom, r.bottomLeft, r.bottomRight);
    side(st.left, r.topLeft, r.bottomLeft);
    side(st.right, r.topRight, r.bottomRight);
  }

  /// Текст ячейки [cell] строки [r]: выравнивание, перенос, «залезание» в
  /// пустые соседние ячейки (как в Excel), «###» у не влезающего числа.
  void _cellText(Canvas canvas, int r, DocCell cell, List<DocMerge> vis, List<DocCell> row) {
    final g = _geo;
    final c = cell.col;
    if (g.w(c) <= 0) return;
    final m = vis.isEmpty ? null : _mergeAt(vis, r, c);
    if (m != null && (m.row != r || m.col != c)) return;
    final st = _style(cell);
    final rect = m != null
        ? Rect.fromLTRB(g.x(m.col), g.y(m.row), g.x(m.lastCol + 1), g.y(m.lastRow + 1))
        : Rect.fromLTWH(g.x(c), g.y(r), g.w(c), g.h(r));
    if (rect.height <= 0) return;
    final align = st.hAlign != DocHAlign.general
        ? st.hAlign
        : switch (cell.kind) {
            DocCellKind.number => DocHAlign.right,
            DocCellKind.text => DocHAlign.left,
            _ => DocHAlign.center,
          };
    final wrap = st.wrap || align == DocHAlign.justify;
    final multi = !wrap && cell.text.contains('\n');
    final inner = math.max(1.0, rect.width - 2 * _pad - st.indent);
    final bg = _colors.fill(st.fill);
    final key = r * 0x10000 + c;
    final tp = cache.cell(key, () {
      final style = TextStyle(
        fontFamily: _colors.font,
        fontSize: st.fontSize ?? 13,
        fontWeight: st.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: st.italic ? FontStyle.italic : FontStyle.normal,
        decoration: TextDecoration.combine([
          if (st.underline) TextDecoration.underline,
          if (st.strike) TextDecoration.lineThrough,
        ]),
        color: _colors.text(st.color, bg),
      );
      final ta = switch (align) {
        DocHAlign.center => TextAlign.center,
        DocHAlign.right => TextAlign.right,
        DocHAlign.justify => TextAlign.justify,
        _ => TextAlign.left,
      };
      var p = TextPainter(
        text: TextSpan(text: cell.text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: wrap ? ta : TextAlign.left,
        textScaler: TextScaler.noScaling,
      );
      if (wrap) {
        p.layout(minWidth: inner, maxWidth: inner);
      } else {
        p.layout();
        // Число не влезает в столбец — «###», как в Excel (полностью — в
        // строке над сеткой).
        if (cell.kind == DocCellKind.number && m == null && p.width > inner + _pad) {
          final n = math.max(1, (inner / ((st.fontSize ?? 13) * 0.6)).floor());
          p.dispose();
          p = TextPainter(
            text: TextSpan(text: '#' * n, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout();
        }
      }
      return p;
    });
    var clipL = rect.left, clipR = rect.right;
    double dx;
    switch (align) {
      case DocHAlign.right:
        dx = rect.right - _pad - tp.width;
      case DocHAlign.center:
        dx = rect.left + (rect.width - tp.width) / 2;
      default:
        dx = rect.left + _pad + st.indent;
    }
    if (wrap) dx = rect.left + _pad + (align == DocHAlign.left || align == DocHAlign.justify ? st.indent : 0);
    // Длинный текст без переноса заходит в пустые соседние ячейки.
    if (!wrap && !multi && cell.kind == DocCellKind.text && m == null) {
      bool free(int col) {
        if (_mergeAt(g.merges, r, col) != null) return false;
        final i = DocSheet.lowerBound(row, col);
        return !(i < row.length && row[i].col == col && row[i].text.isNotEmpty);
      }

      if (align != DocHAlign.right) {
        for (var k = c + 1; dx + tp.width > clipR && k < c + 24; k++) {
          if (!free(k)) break;
          clipR += g.w(k);
        }
      }
      if (align != DocHAlign.left) {
        for (var k = c - 1; dx < clipL && k >= 0 && k > c - 24; k--) {
          if (!free(k)) break;
          clipL -= g.w(k);
        }
      }
    }
    final dy = switch (st.vAlign) {
      DocVAlign.top => rect.top + 1,
      DocVAlign.center => rect.top + (rect.height - tp.height) / 2,
      DocVAlign.bottom => rect.bottom - tp.height - 1,
    };
    final clip = Rect.fromLTRB(clipL, rect.top, clipR, rect.bottom);
    final needClip = dx < clip.left || dx + tp.width > clip.right || dy < clip.top || dy + tp.height > clip.bottom;
    if (needClip) {
      canvas.save();
      canvas.clipRect(clip);
      tp.paint(canvas, Offset(dx, dy));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(dx, dy));
    }
  }

  // ── Доступность: видимые заголовки и ячейки — узлами семантики ──

  final Map<String, SemanticsNode> _nodes = {};

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
    config.explicitChildNodes = true;
    final s = _geo.sheet;
    config.label = '${s.name}: ${s.rowCount} × ${s.colCount}';
    config.textDirection = TextDirection.ltr;
  }

  @override
  void assembleSemanticsNode(SemanticsNode node, SemanticsConfiguration config, Iterable<SemanticsNode> children) {
    final v = _view();
    final z = _zoom, g = _geo, sheet = g.sheet, f = v.f;
    final out = <SemanticsNode>[];
    final used = <String>{};
    final bounds = Offset.zero & size;
    void add(String key, Rect rect, String label, {bool header = false, VoidCallback? onTap, bool selected = false}) {
      final r = rect.intersect(bounds);
      if (r.width <= 0 || r.height <= 0 || out.length > 800) return;
      final n = _nodes[key] ??= SemanticsNode();
      n.rect = r;
      final cfg = SemanticsConfiguration()
        ..label = label
        ..textDirection = TextDirection.ltr
        ..isHeader = header
        ..isSelected = selected;
      if (onTap != null) cfg.onTap = onTap;
      n.updateWith(config: cfg);
      used.add(key);
      out.add(n);
    }

    void cols(int c0, int c1, double tx) {
      for (var c = c0; c <= c1; c++) {
        if (g.w(c) <= 0) continue;
        add('c$c', Rect.fromLTWH(tx + g.x(c) * z, 0, g.w(c) * z, v.hh), SheetRef.colName(c), header: true);
      }
    }

    void rows(int r0, int r1, double ty) {
      for (var r = r0; r <= r1; r++) {
        if (g.h(r) <= 0) continue;
        add('r$r', Rect.fromLTWH(0, ty + g.y(r) * z, v.hw, g.h(r) * z), '${r + 1}', header: true);
      }
    }

    void cells(int r0, int r1, int c0, int c1, double tx, double ty, Rect clip) {
      for (var r = r0; r <= math.min(r1, sheet.rowCount - 1); r++) {
        if (g.h(r) <= 0) continue;
        final row = sheet.rows[r];
        for (var i = DocSheet.lowerBound(row, c0); i < row.length && row[i].col <= c1; i++) {
          final c = row[i].col;
          if (row[i].text.isEmpty || g.w(c) <= 0) continue;
          final rect = Rect.fromLTWH(tx + g.x(c) * z, ty + g.y(r) * z, g.w(c) * z, g.h(r) * z).intersect(clip);
          final cell = (row: r, col: c);
          add(
            '$r:$c',
            rect,
            row[i].text,
            selected: _sel == cell,
            onTap: onSelect == null ? null : () => onSelect!(cell),
          );
        }
      }
    }

    final hw = v.hw, hh = v.hh;
    cols(v.c0, v.c1, v.tx);
    if (f.fc > 0) cols(0, f.fc - 1, hw);
    rows(v.r0, v.r1, v.ty);
    if (f.fr > 0) rows(0, f.fr - 1, hh);
    cells(v.r0, v.r1, v.c0, v.c1, v.tx, v.ty, Rect.fromLTRB(f.left, f.top, size.width, size.height));
    if (f.fr > 0) cells(0, f.fr - 1, v.c0, v.c1, v.tx, hh, Rect.fromLTRB(f.left, hh, size.width, f.top));
    if (f.fc > 0) cells(v.r0, v.r1, 0, f.fc - 1, hw, v.ty, Rect.fromLTRB(hw, f.top, f.left, size.height));
    if (f.fr > 0 && f.fc > 0) cells(0, f.fr - 1, 0, f.fc - 1, hw, hh, Rect.fromLTRB(hw, hh, f.left, f.top));
    _nodes.removeWhere((k, _) => !used.contains(k));
    node.updateWith(config: config, childrenInInversePaintOrder: out);
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _nodes.clear();
  }
}

// lib/services/documents/doc_slides.dart
// Презентация после разбора (PPTX — pptx_reader.dart, ODP — odp_reader.dart):
// слайды с фигурами, которые рисует doc_slides_view.dart (1.11.x, предпросмотр
// документов, план владельца 04.11.2026).
//
// Модель — только простые данные: разбор идёт в фоновом изоляте, и результат
// переходит в главный. Поэтому здесь нет типов dart:ui и Flutter: цвета —
// int 0xAARRGGBB, размеры и координаты — double в пунктах (1/72 дюйма) от
// левого верхнего угла слайда, картинки — [OfficeImage] (байты PNG/JPEG/…).
//
// Фигура — уже в координатах слайда: группы при разборе «раскрываются»
// (смещение и масштаб группы применены к детям), наследование PowerPoint
// (макет, образец, тема) и стили OpenDocument — тоже разрешены. Показу
// остаётся только нарисовать.

import 'office_document.dart';
import 'office_package.dart' show OfficeImage;

/// Презентация: размер слайда и слайды по порядку показа (скрытые — без них).
class OfficeSlidesDoc extends OfficeDoc {
  /// Больше слайдов не разбирается — [truncated].
  static const maxSlides = 300;

  /// Больше фигур на слайде (вместе с фигурами образца и макета) —
  /// остальные пропускаются, [truncated].
  static const maxShapes = 500;

  /// Размер слайда в пунктах (4:3 — 720 × 540, 16:9 — 960 × 540).
  final double width;
  final double height;
  final List<DocSlide> slides;

  @override
  final bool truncated;

  const OfficeSlidesDoc({required this.width, required this.height, required this.slides, this.truncated = false});

  bool get isEmpty => slides.isEmpty;
}

class DocSlide {
  /// Фон слайда; null — белый.
  final DocFill? background;

  /// Фигуры снизу вверх: образец, макет, сам слайд.
  final List<DocShape> shapes;

  /// Заметки докладчика — простой текст, абзацы через «\n»; '' — нет.
  final String notes;

  const DocSlide({this.background, this.shapes = const [], this.notes = ''});

  /// Заметки докладчика не длиннее — дальше обрезаются.
  static const maxNotes = 20000;

  /// Текст заметок: переводы строк единые, пустые строки по краям и
  /// подряд — убраны; длиннее [maxNotes] — обрезан.
  static String cleanNotes(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp('[\r\u000B\u2028\u2029]'), '\n')
        .split('\n')
        .map((l) => l.trimRight())
        .toList();
    final out = <String>[];
    for (final l in lines) {
      if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
      out.add(l);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    final text = out.join('\n');
    return text.length > maxNotes ? text.substring(0, maxNotes) : text;
  }
}

/// Заливка: цвет, градиент или картинка.
class DocFill {
  final int? color;

  /// Градиент — цвета и места (0…1) по порядку, не меньше двух.
  final List<int> gradientColors;
  final List<double> gradientStops;

  /// Направление линейного градиента в градусах: 0 — слева направо,
  /// 90 — сверху вниз (по часовой стрелке, как в PowerPoint).
  final double gradientAngle;

  /// Радиальный градиент (от центра): «path» PowerPoint, radial/ellipsoid ODF.
  final bool radial;

  final OfficeImage? image;

  /// Картинка — плиткой, а не растянута; [tileScale] — во сколько раз
  /// увеличена плитка (её размер в точках = пиксели × 0.75 × масштаб).
  final bool tile;
  final double tileScale;

  const DocFill.solid(int this.color)
    : gradientColors = const [],
      gradientStops = const [],
      gradientAngle = 0,
      radial = false,
      image = null,
      tile = false,
      tileScale = 1;

  const DocFill.gradient(this.gradientColors, this.gradientStops, {this.gradientAngle = 0, this.radial = false})
    : color = null,
      image = null,
      tile = false,
      tileScale = 1;

  const DocFill.picture(OfficeImage this.image, {this.tile = false, this.tileScale = 1})
    : color = null,
      gradientColors = const [],
      gradientStops = const [],
      gradientAngle = 0,
      radial = false;

  bool get isGradient => gradientColors.length >= 2;

  /// Один цвет, которым можно заменить заливку (градиент — средний).
  int? get flatColor {
    if (color != null) return color;
    if (gradientColors.isNotEmpty) return gradientColors[gradientColors.length ~/ 2];
    return null;
  }
}

enum DocDash { solid, dash, dot, dashDot }

/// Линия контура.
class DocLine {
  final int color;

  /// Толщина в пунктах; 0 — самая тонкая (один пиксель).
  final double width;
  final DocDash dash;

  /// Стрелки в начале и в конце (линии и соединители).
  final bool headArrow;
  final bool tailArrow;

  const DocLine(this.color, this.width, {this.dash = DocDash.solid, this.headArrow = false, this.tailArrow = false});
}

/// Форма фигуры. Остальные заготовленные формы PowerPoint и ODF рисуются
/// прямоугольником ([rect]).
enum DocGeom {
  rect,
  roundRect,
  ellipse,

  /// Отрезок из левого верхнего угла в правый нижний (отражения фигуры —
  /// в [DocShape.flipH]/[DocShape.flipV]).
  line,
  triangle,
  rtTriangle,
  diamond,
  parallelogram,
  trapezoid,
  pentagon,
  hexagon,
  octagon,
  homePlate,
  chevron,
  rightArrow,
  leftArrow,
  upArrow,
  downArrow,
  leftRightArrow,
  plus,
  star5,

  /// Свой контур — [DocShape.path].
  path,
}

enum DocPathOp { move, line, cubic, close }

/// Контур фигуры: команды и точки в долях рамки фигуры (0…1 — от левого
/// верхнего до правого нижнего угла; выход за 0…1 допустим).
class DocPath {
  final List<DocPathOp> ops;

  /// Точки подряд (x, y): move и line — по одной, cubic — по три.
  final List<double> points;

  /// Залить контур (у ломаной PowerPoint и draw:polyline — нет).
  final bool filled;

  const DocPath(this.ops, this.points, {this.filled = true});

  bool get isEmpty => ops.isEmpty;
}

/// Картинка фигуры с обрезкой: доли ширины/высоты картинки, срезанные с
/// каждой стороны (отрицательные — поле вокруг).
class DocPicture {
  final OfficeImage image;
  final double cropLeft, cropTop, cropRight, cropBottom;
  const DocPicture(this.image, {this.cropLeft = 0, this.cropTop = 0, this.cropRight = 0, this.cropBottom = 0});
}

/// Чего предпросмотр не рисует, — нейтральная плашка с значком на месте
/// объекта.
enum DocEmbed { chart, diagram, object, media }

class DocShape {
  /// Рамка фигуры до поворота, в пунктах.
  final double x, y, w, h;

  /// Поворот вокруг центра рамки, градусы по часовой стрелке.
  final double rotation;
  final bool flipH, flipV;

  final DocGeom geom;

  /// Параметр формы в долях: [DocGeom.roundRect] — радиус угла от меньшей
  /// стороны (по умолчанию 1/6), стрелки и шеврон — глубина наконечника и т. п.
  final double? adjust;
  final DocPath? path;

  final DocFill? fill;
  final DocLine? line;
  final DocPicture? picture;
  final DocTextBody? text;
  final DocTable? table;
  final DocEmbed? embed;

  const DocShape({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.geom = DocGeom.rect,
    this.adjust,
    this.path,
    this.fill,
    this.line,
    this.picture,
    this.text,
    this.table,
    this.embed,
  });

  /// Весь текст фигуры (для тестов и подписи для чтения с экрана).
  String get plainText {
    final out = StringBuffer();
    void body(DocTextBody? b) {
      if (b == null) return;
      for (final p in b.paragraphs) {
        if (out.isNotEmpty) out.write('\n');
        out.write(p.text);
      }
    }

    body(text);
    for (final c in table?.cells ?? const <DocCell>[]) {
      body(c.text);
    }
    return out.toString();
  }
}

enum DocAnchor { top, middle, bottom }

enum DocAlign { left, center, right, justify }

/// Текст фигуры или ячейки.
class DocTextBody {
  /// Поля от рамки фигуры, в пунктах.
  final double insetLeft, insetTop, insetRight, insetBottom;
  final DocAnchor anchor;

  /// Перенос строк по ширине рамки; false — строка не переносится
  /// (wrap="none", надпись растёт вширь).
  final bool wrap;

  /// «Сжать текст при переполнении», как его сохранила программа:
  /// множитель размеров шрифта и уменьшение межстрочного интервала (0…1).
  final double fontScale;
  final double lineReduction;

  /// Автоподбор без сохранённого множителя: показ сам уменьшает текст,
  /// если тот не помещается в рамку.
  final bool shrink;

  final List<DocParagraph> paragraphs;

  const DocTextBody({
    this.insetLeft = 7.2,
    this.insetTop = 3.6,
    this.insetRight = 7.2,
    this.insetBottom = 3.6,
    this.anchor = DocAnchor.top,
    this.wrap = true,
    this.fontScale = 1,
    this.lineReduction = 0,
    this.shrink = false,
    this.paragraphs = const [],
  });

  bool get isEmpty => paragraphs.every((p) => p.runs.every((r) => r.text.trim().isEmpty));
}

/// Маркер абзаца: знак («•», «–») или номер («1.», «а)»).
class DocBullet {
  final String text;

  /// null — цвет первого фрагмента абзаца.
  final int? color;

  /// Размер относительно первого фрагмента (1 — такой же).
  final double sizeScale;

  /// Шрифт маркера, если он задан явно (Wingdings и Symbol уже заменены
  /// знаками Юникода).
  final String? font;

  const DocBullet(this.text, {this.color, this.sizeScale = 1, this.font});
}

class DocParagraph {
  final DocAlign align;

  /// Уровень списка (0 — первый).
  final int level;

  /// Отступ текста слева и сдвиг первой строки от него, в пунктах
  /// (отрицательный — «висячий»: маркер левее текста).
  final double marginLeft;
  final double indent;
  final DocBullet? bullet;

  /// Интервалы до и после абзаца, в пунктах.
  final double spaceBefore, spaceAfter;

  /// Межстрочный интервал: множитель одинарного (1 — одинарный) или
  /// точная высота строки в пунктах ([lineExact], тогда [lineSpacing]
  /// не используется).
  final double lineSpacing;
  final double? lineExact;

  /// Размер шрифта знака конца абзаца: высота пустой строки.
  final double endSize;

  final List<DocRun> runs;

  const DocParagraph({
    this.align = DocAlign.left,
    this.level = 0,
    this.marginLeft = 0,
    this.indent = 0,
    this.bullet,
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.lineSpacing = 1,
    this.lineExact,
    this.endSize = 18,
    this.runs = const [],
  });

  String get text => runs.map((r) => r.text).join();
}

/// Фрагмент текста с одним оформлением. Перенос строки внутри абзаца —
/// «\n» в [text].
class DocRun {
  final String text;

  /// Размер в пунктах.
  final double size;
  final int color;
  final bool bold, italic, underline, strike;

  /// Сдвиг строки в процентах размера: > 0 — верхний индекс, < 0 — нижний.
  final double baseline;

  /// Имя шрифта (шрифты темы уже подставлены); null — шрифт по умолчанию.
  final String? font;

  /// Цвет выделения (фона) текста.
  final int? highlight;

  /// Ссылка — только http, https и mailto.
  final String? href;

  const DocRun(
    this.text, {
    this.size = 18,
    this.color = 0xFF000000,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.baseline = 0,
    this.font,
    this.highlight,
    this.href,
  });
}

/// Таблица: ширины столбцов и высоты строк в пунктах; ячейки — только
/// «главные» (объединённые закрывают соседние, те в список не входят).
class DocTable {
  final List<double> columns;

  /// Наименьшая высота строки: строка выше, если текст в неё не помещается.
  final List<double> rows;
  final List<DocCell> cells;

  const DocTable({required this.columns, required this.rows, required this.cells});
}

class DocCell {
  final int row, col;
  final int rowSpan, colSpan;
  final DocFill? fill;
  final DocLine? left, top, right, bottom;
  final DocTextBody? text;

  const DocCell({
    required this.row,
    required this.col,
    this.rowSpan = 1,
    this.colSpan = 1,
    this.fill,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.text,
  });
}

/// Заготовки форм DrawingML (prstGeom PowerPoint; в ODP, сохранённом из
/// PPTX, — draw:type «ooxml-<имя>») → форма показа; остальные — прямоугольник.
const docPresetGeometry = {
  'rect': DocGeom.rect,
  'roundRect': DocGeom.roundRect,
  'round2SameRect': DocGeom.roundRect,
  'round1Rect': DocGeom.roundRect,
  'flowChartAlternateProcess': DocGeom.roundRect,
  'wedgeRoundRectCallout': DocGeom.roundRect,
  'ellipse': DocGeom.ellipse,
  'flowChartConnector': DocGeom.ellipse,
  'wedgeEllipseCallout': DocGeom.ellipse,
  'donut': DocGeom.ellipse,
  'cloud': DocGeom.ellipse,
  'cloudCallout': DocGeom.ellipse,
  'line': DocGeom.line,
  'straightConnector1': DocGeom.line,
  'triangle': DocGeom.triangle,
  'flowChartExtract': DocGeom.triangle,
  'rtTriangle': DocGeom.rtTriangle,
  'diamond': DocGeom.diamond,
  'flowChartDecision': DocGeom.diamond,
  'parallelogram': DocGeom.parallelogram,
  'flowChartInputOutput': DocGeom.parallelogram,
  'trapezoid': DocGeom.trapezoid,
  'pentagon': DocGeom.pentagon,
  'hexagon': DocGeom.hexagon,
  'octagon': DocGeom.octagon,
  'homePlate': DocGeom.homePlate,
  'chevron': DocGeom.chevron,
  'rightArrow': DocGeom.rightArrow,
  'leftArrow': DocGeom.leftArrow,
  'upArrow': DocGeom.upArrow,
  'downArrow': DocGeom.downArrow,
  'leftRightArrow': DocGeom.leftRightArrow,
  'plus': DocGeom.plus,
  'mathPlus': DocGeom.plus,
  'star5': DocGeom.star5,
};

/// Ссылка из документа, которую можно открыть: http, https, mailto
/// (остальное — file:, javascript:, переходы по слайдам — без ссылки).
String? docSafeHref(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final lower = s.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('mailto:')) return s;
  return null;
}

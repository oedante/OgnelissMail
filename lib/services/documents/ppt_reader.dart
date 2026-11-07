// lib/services/documents/ppt_reader.dart
// Презентация PowerPoint 97–2003 (.ppt, .pps, .pot) → слайды для показа
// (1.12.x, просьба владельца 04.11.2026: старые форматы Office в
// предпросмотре вложений). По открытым спецификациям Microsoft [MS-PPT] и
// [MS-ODRAW] (Open Specification Promise), без сторонних библиотек; модель
// и показ — общие с PPTX и ODP (doc_slides.dart).
//
// Главное — текст. Поток «PowerPoint Document» — записи (заголовок 8 байт,
// контейнеры с записями внутри). Где что лежит, говорят «правки»: поток
// «Current User» указывает на последнюю UserEditAtom, у неё — каталог
// «постоянных объектов» (persist id → смещение) и ссылка на предыдущую
// правку. По каталогу — документ (размер слайда, шрифты, хранилище
// картинок, список слайдов по порядку показа), образцы (схема цветов,
// стили текста по видам — заголовок, основной текст…, фон и свои фигуры)
// и слайды: их рисунок OfficeArt — фигуры с рамкой (ClientAnchor), заливкой
// и линией (свойства FOPT поверх умолчаний документа), картинкой из потока
// «Pictures» (PNG, JPEG, BMP) и текстом (ClientTextbox: TextCharsAtom или
// TextBytesAtom, оформление StyleTextPropAtom поверх стилей образца; текст
// заполнителя может лежать и в списке SlideListWithText — по
// OutlineTextRefAtom). Группы раскрываются в координаты слайда.
//
// Заметки докладчика (1.15.1): у слайда в SlideAtom — номер страницы
// заметок, по списку заметок (SlideListWithText, вид 2) — её постоянный
// объект NotesContainer; текст — в фигуре-заполнителе «текст заметок»
// (PT_NotesBody или TextHeaderAtom вида «заметки»).
//
// Диаграммы и внедрённые объекты (OLE): показывается их картинка-заменитель,
// если это PNG/JPEG; иначе (обычно EMF) — плашка со значком по виду объекта
// (1.15.1): ссылка фигуры ExObjRefAtom → объект из ExObjList → подвид
// ExOleObjAtom (Graph, ExcelChart, OrgChart, звук), имя программы
// (MSGraph.Chart, Excel.Chart) или, если их нет (так пишет LibreOffice), —
// поток CompObj внутри хранилища объекта (ExOleObjStg, сжатого zlib).
//
// Не показываются: анимация, гиперссылки в тексте, содержимое диаграмм и
// внедрённых объектов, свои контуры фигур (рисуются прямоугольником),
// EMF/WMF. Скрытые слайды — без них. Пароль — [OfficeDocError.encrypted]; PowerPoint 95 и старше —
// [OfficeDocError.legacy]. Смещения, длины и количества — из чужого файла:
// всё проверяется по границам, петли в цепочке правок и группах —
// с пределом.

import 'dart:io' show RawZLibFilter;
import 'dart:math' as math;
import 'dart:typed_data';

import 'cfb_reader.dart';
import 'doc_html.dart' show DocHtml;
import 'doc_slides.dart';
import 'office_art.dart';
import 'office_package.dart';

class PptReader {
  PptReader._();

  /// Похоже на презентацию PowerPoint: есть поток «PowerPoint Document».
  static bool isPresentation(CfbFile cfb) => cfb.hasStream('PowerPoint Document');

  /// Разобрать презентацию. Ошибки — только [OfficeDocException].
  static OfficeSlidesDoc read(CfbFile cfb) {
    try {
      return _Ppt(cfb).read();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, 'ppt: $e');
    }
  }
}

// Типы записей.
const _rtDocument = 0x03E8;
const _rtDocumentAtom = 0x03E9;
const _rtSlide = 0x03EE;
const _rtSlideAtom = 0x03EF;
const _rtMainMaster = 0x03F8;
const _rtSlideShowInfo = 0x03F9;
const _rtSlidePersist = 0x03F3;
const _rtEnvironment = 0x03F2;
const _rtFontCollection = 0x07D5;
const _rtFontEntity = 0x0FB7;
const _rtSlideList = 0x0FF0;
const _rtUserEdit = 0x0FF5;
const _rtPersistDir = 0x1772;
const _rtColorScheme = 0x07F0;
const _rtTxMasterStyle = 0x0FA3;
const _rtTextHeader = 0x0F9F;
const _rtTextChars = 0x0FA0;
const _rtTextBytes = 0x0FA8;
const _rtStyleTextProp = 0x0FA1;
const _rtOutlineTextRef = 0x0F9E;
const _rtDrawing = 0x040C;
const _rtDrawingGroup = 0x040B;
const _rtPlaceholder = 0x0BC3;
const _rtNotes = 0x03F0;
const _rtExObjList = 0x0409;
const _rtExEmbed = 0x0FCC;
const _rtExLink = 0x0FCE;
const _rtExControl = 0x0FEE;
const _rtExOleObjAtom = 0x0FC3;
const _rtExOleObjStg = 0x1011;
const _rtExObjRef = 0x0BC1;
const _rtCString = 0x0FBA;
const _rtExVideo = 0x1005;
const _rtExMediaAtom = 0x1004;

/// Звук и видео в ExObjList: ExAviMovie, ExMCIMovie, ExMIDIAudio,
/// ExCDAudio, ExWAVAudioLink, ExWAVAudioEmbedded.
const _rtMedia = {0x1006, 0x1007, 0x100D, 0x100E, 0x100F, 0x1010};

/// Свойства абзаца (TextPFException); null — не задано.
class _Pf {
  int? bulletFlags, bulletChar, bulletFont, bulletSize, bulletColor;
  int? align, lineSpacing, spaceBefore, spaceAfter, leftMargin, indent;

  _Pf over(_Pf? o) {
    if (o == null) return this;
    return _Pf()
      ..bulletFlags = o.bulletFlags ?? bulletFlags
      ..bulletChar = o.bulletChar ?? bulletChar
      ..bulletFont = o.bulletFont ?? bulletFont
      ..bulletSize = o.bulletSize ?? bulletSize
      ..bulletColor = o.bulletColor ?? bulletColor
      ..align = o.align ?? align
      ..lineSpacing = o.lineSpacing ?? lineSpacing
      ..spaceBefore = o.spaceBefore ?? spaceBefore
      ..spaceAfter = o.spaceAfter ?? spaceAfter
      ..leftMargin = o.leftMargin ?? leftMargin
      ..indent = o.indent ?? indent;
  }
}

/// Свойства знаков (TextCFException); цвет — ColorIndexStruct как есть.
class _Cf {
  bool? bold, italic, underline;
  int? font, size, color, position;

  _Cf over(_Cf? o) {
    if (o == null) return this;
    return _Cf()
      ..bold = o.bold ?? bold
      ..italic = o.italic ?? italic
      ..underline = o.underline ?? underline
      ..font = o.font ?? font
      ..size = o.size ?? size
      ..color = o.color ?? color
      ..position = o.position ?? position;
  }
}

/// Участок текста с одним набором свойств: [count] знаков.
class _PRun {
  final int count, level;
  final _Pf pf;
  const _PRun(this.count, this.level, this.pf);
}

class _CRun {
  final int count;
  final _Cf cf;
  const _CRun(this.count, this.cf);
}

/// Текст фигуры или заполнителя.
class _Text {
  int type = 4;
  String text = '';
  List<_PRun> pf = const [];
  List<_CRun> cf = const [];
}

class _Master {
  List<int> scheme = const [
    0xFFFFFFFF,
    0xFF000000,
    0xFF808080,
    0xFF000000,
    0xFFBBE0E3,
    0xFF333399,
    0xFF009999,
    0xFF99CC00,
  ];

  /// Стили текста образца: вид текста → уровни (0–4).
  final styles = <int, List<(_Pf, _Cf)>>{};
  DocFill? background;
  List<DocShape> shapes = const [];
}

/// Свойства фигуры OfficeArt (FOPT): номер → значение, сложные — байтами.
class _Opt {
  final values = <int, int>{};
  final complex = <int, Uint8List>{};
  _Opt over(_Opt? o) {
    final r = _Opt()
      ..values.addAll(values)
      ..complex.addAll(complex);
    if (o != null) {
      r.values.addAll(o.values);
      r.complex.addAll(o.complex);
    }
    return r;
  }
}

class _Ppt {
  _Ppt(this.cfb);

  final CfbFile cfb;
  late Uint8List s;
  late ByteData bd;
  final persist = <int, int>{};
  final fonts = <String>[];
  final blips = <int>[];
  Uint8List? pictures;
  _Opt defaults = _Opt();
  final masters = <int, _Master>{};
  final Map<int, OfficeImage?> _images = {};
  int _imagesTotal = 0;
  bool _truncated = false;
  double width = 720, height = 540;

  /// Страницы заметок: номер (slideId из списка заметок) → постоянный объект.
  final _notesIds = <int, int>{};

  /// Внедрённые и связанные объекты: exObjId → запись из ExObjList.
  final _exObjs = <int, ArtRecord>{};
  final _embedKinds = <int, DocEmbed>{};

  /// Знаков текста на всю презентацию: один и тот же текст списка слайдов
  /// могут показывать сотни фигур (OutlineTextRefAtom) — без предела это
  /// гигабайты строк из файла в мегабайт.
  int _textLeft = 2000000;

  int u16(int at) => bd.getUint16(at, Endian.little);
  int i16(int at) => bd.getInt16(at, Endian.little);
  int u32(int at) => bd.getUint32(at, Endian.little);
  int i32(int at) => bd.getInt32(at, Endian.little);

  ArtRecord? rec(int at, [int? end]) => OfficeArt.record(s, at, end);
  Iterable<ArtRecord> kids(ArtRecord r) => OfficeArt.children(s, r.at, r.end);
  ArtRecord? kid(ArtRecord r, int type, [int? inst]) {
    for (final k in kids(r)) {
      if (k.type == type && (inst == null || k.inst == inst)) return k;
    }
    return null;
  }

  OfficeSlidesDoc read() {
    if (cfb.hasStream('EncryptedSummary')) throw const OfficeDocException(OfficeDocError.encrypted, 'ppt');
    final head = cfb.readHead('PowerPoint Document', OfficeLimits.maxPartBytes)!;
    s = head.bytes;
    bd = ByteData.sublistView(s);
    if (head.truncated) _truncated = true;
    try {
      pictures = cfb.read('Pictures');
    } on OfficeDocException catch (e) {
      if (e.kind != OfficeDocError.damaged) rethrow;
    }

    _readPersist();
    final doc = _documentRecord();
    if (doc == null) throw const OfficeDocException(OfficeDocError.legacy, 'no document container');
    // Без каталога правок — слайды и образцы по порядку записей потока.
    final scan = persist.isEmpty;
    if (scan) {
      for (final r in OfficeArt.children(s, 0, s.length)) {
        if (r.type == _rtMainMaster) _scanMasters.add(r.at - 8);
      }
    }

    final atom = kid(doc, _rtDocumentAtom);
    if (atom != null && atom.len >= 8) {
      final w = i32(atom.at) / 8, h = i32(atom.at + 4) / 8;
      if (w >= 72 && h >= 72 && w <= 14400 && h <= 14400) {
        width = w;
        height = h;
      }
    }
    final env = kid(doc, _rtEnvironment);
    final fc = env == null ? null : kid(env, _rtFontCollection);
    if (fc != null) {
      for (final f in kids(fc)) {
        if (f.type != _rtFontEntity || f.len < 64) continue;
        final units = <int>[];
        for (var i = 0; i < 32; i++) {
          final c = u16(f.at + i * 2);
          if (c == 0) break;
          units.add(c);
        }
        fonts.add(String.fromCharCodes(units));
      }
    }
    _readDrawingGroup(doc);
    _readExObjs(doc);

    // Образцы: идентификатор слайда → постоянный объект.
    final masterIds = <int, int>{};
    final slideRefs = <(int persistId, List<_Text> texts)>[];
    for (final list in kids(doc)) {
      if (list.type != _rtSlideList) continue;
      if (list.inst == 1) {
        for (final a in kids(list)) {
          if (a.type == _rtSlidePersist && a.len >= 16) masterIds[u32(a.at + 12)] = u32(a.at);
        }
      } else if (list.inst == 0) {
        for (final a in kids(list)) {
          if (a.type == _rtSlidePersist && a.len >= 4) {
            slideRefs.add((u32(a.at), <_Text>[]));
          } else if (slideRefs.isNotEmpty) {
            _collectText(a, slideRefs.last.$2);
          }
        }
      } else if (list.inst == 2) {
        for (final a in kids(list)) {
          if (a.type == _rtSlidePersist && a.len >= 16 && _notesIds.length < 10000) {
            _notesIds[u32(a.at + 12)] = u32(a.at);
          }
        }
      }
    }
    final slides = <DocSlide>[];
    final seen = <int>{};
    final order = scan
        ? [
            for (final r in OfficeArt.children(s, 0, s.length))
              if (r.type == _rtSlide) (r.at - 8, <_Text>[]),
          ]
        : [for (final (id, texts) in slideRefs) (persist[id] ?? -1, texts)];
    for (final (off, texts) in order) {
      if (slides.length >= OfficeSlidesDoc.maxSlides) {
        _truncated = true;
        break;
      }
      if (off < 0 || !seen.add(off)) continue;
      final r = rec(off);
      if (r == null || r.type != _rtSlide) continue;
      try {
        final slide = _slide(r, texts, masterIds);
        if (slide != null) slides.add(slide);
      } on OfficeDocException catch (e) {
        if (e.kind != OfficeDocError.damaged) rethrow;
        _truncated = true;
      } on RangeError {
        _truncated = true;
      }
    }
    return OfficeSlidesDoc(width: width, height: height, slides: slides, truncated: _truncated);
  }

  // ── Правки и постоянные объекты ──

  void _readPersist() {
    Uint8List? cu;
    try {
      cu = cfb.read('Current User', max: 4096);
    } on OfficeDocException catch (e) {
      if (e.kind == OfficeDocError.tooLarge) cu = null;
      if (e.kind != OfficeDocError.damaged && e.kind != OfficeDocError.tooLarge) rethrow;
    }
    if (cu == null || cu.length < 24) return;
    final c = ByteData.sublistView(cu);
    final token = c.getUint32(12, Endian.little);
    if (token == 0xF3D1C4DF) throw const OfficeDocException(OfficeDocError.encrypted, 'ppt');
    if (token != 0xE391C05F) return;
    if (cu.length >= 24 && c.getUint16(22, Endian.little) != 0x03F4) {
      throw const OfficeDocException(OfficeDocError.legacy, 'ppt version');
    }
    var off = c.getUint32(16, Endian.little);
    final visited = <int>{};
    var newest = true;
    while (off != 0 && visited.add(off) && visited.length < 1000) {
      final edit = rec(off);
      if (edit == null || edit.type != _rtUserEdit || edit.len < 28) break;
      if (newest && edit.len >= 32 && u32(edit.at + 28) != 0) {
        throw const OfficeDocException(OfficeDocError.encrypted, 'ppt');
      }
      newest = false;
      final dir = rec(u32(edit.at + 12));
      if (dir != null && dir.type == _rtPersistDir) {
        var p = dir.at;
        while (p + 4 <= dir.end && persist.length < 200000) {
          final v = u32(p);
          final first = v & 0xFFFFF;
          final count = v >> 20;
          p += 4;
          for (var k = 0; k < count && p + 4 <= dir.end; k++) {
            persist.putIfAbsent(first + k, () => u32(p));
            p += 4;
          }
        }
      }
      _docRef ??= u32(edit.at + 16);
      off = u32(edit.at + 8);
    }
  }

  int? _docRef;

  /// Контейнер документа: по каталогу правок, иначе — первая такая запись
  /// верхнего уровня (каталог испорчен или его нет).
  ArtRecord? _documentRecord() {
    final off = _docRef == null ? null : persist[_docRef!];
    if (off != null) {
      final r = rec(off);
      if (r != null && r.type == _rtDocument) return r;
    }
    var i = 0;
    for (final r in OfficeArt.children(s, 0, s.length)) {
      if (r.type == _rtDocument) {
        // Каталог правок не сходится с файлом — по записям верхнего уровня.
        persist.clear();
        return r;
      }
      if (++i > 10000) break;
    }
    return null;
  }

  /// Образцы по порядку записей (когда каталога правок нет).
  final _scanMasters = <int>[];

  // ── Картинки ──

  void _readDrawingGroup(ArtRecord doc) {
    final dg = kid(doc, _rtDrawingGroup);
    if (dg == null) return;
    final dgg = kid(dg, 0xF000);
    if (dgg == null) return;
    for (final r in kids(dgg)) {
      if (r.type == 0xF001) {
        for (final b in kids(r)) {
          if (b.type == 0xF007 && b.len >= 36) {
            blips.add(u32(b.at + 28));
          } else {
            blips.add(-1);
          }
          if (blips.length > 10000) break;
        }
      } else if (r.type == 0xF00B) {
        defaults = _opt(r);
      }
    }
  }

  OfficeImage? _blip(int pib) {
    if (pib <= 0 || pib > blips.length) return null;
    if (_images.containsKey(pib)) return _images[pib];
    final pics = pictures;
    final off = blips[pib - 1];
    OfficeImage? img;
    if (pics != null && off >= 0 && _imagesTotal < OfficeLimits.maxImagesTotal) {
      final r = OfficeArt.record(pics, off);
      if (r != null) img = OfficeArt.blip(pics, r);
      if (img != null && _imagesTotal + img.bytes.length > OfficeLimits.maxImagesTotal) img = null;
      if (img != null) _imagesTotal += img.bytes.length;
    }
    return _images[pib] = img;
  }

  // ── Образец ──

  _Master _master(int slideId, Map<int, int> masterIds) {
    final hit = masters[slideId];
    if (hit != null) return hit;
    final m = _Master();
    masters[slideId] = m;
    var off = masterIds[slideId] == null ? null : persist[masterIds[slideId]!];
    if (off == null && _scanMasters.isNotEmpty) off = _scanMasters.first;
    final r = off == null ? null : rec(off);
    if (r == null || (r.type != _rtMainMaster && r.type != _rtSlide)) return m;
    if (r.type == _rtSlide) {
      // «Образец заголовков» PowerPoint 97 — слайд со ссылкой на главный образец.
      final atom = kid(r, _rtSlideAtom);
      if (atom != null && atom.len >= 16 && u32(atom.at + 12) != slideId && masterIds.length < 10000) {
        final main = _master(u32(atom.at + 12), masterIds);
        m.scheme = main.scheme;
        m.styles.addAll(main.styles);
        m.background = main.background;
      }
    }
    final scheme = kid(r, _rtColorScheme, 1);
    if (scheme != null) m.scheme = _scheme(scheme);
    for (final st in kids(r)) {
      if (st.type == _rtTxMasterStyle) {
        try {
          m.styles[st.inst] = _masterStyle(st);
        } on RangeError {
          // Испорченный стиль — умолчания.
        }
      }
    }
    final drawing = kid(r, _rtDrawing);
    if (drawing != null) {
      final shapes = <DocShape>[];
      m.background = _drawing(drawing, m, shapes, const [], master: true);
      m.shapes = shapes;
    }
    return m;
  }

  List<int> _scheme(ArtRecord r) => [
    for (var i = 0; i < 8; i++)
      if (r.len >= (i + 1) * 4)
        0xFF000000 | (s[r.at + i * 4] << 16) | (s[r.at + i * 4 + 1] << 8) | s[r.at + i * 4 + 2]
      else
        0xFF000000,
  ];

  List<(_Pf, _Cf)> _masterStyle(ArtRecord r) {
    var p = r.at;
    final levels = math.min(u16(p), 5);
    p += 2;
    final out = <(_Pf, _Cf)>[];
    for (var i = 0; i < levels && p < r.end; i++) {
      if (r.inst >= 5) p += 2;
      final pf = _readPf(p, r.end);
      p = pf.next;
      final cf = _readCf(p, r.end);
      p = cf.next;
      out.add((pf.pf, cf.cf));
    }
    return out;
  }

  ({_Pf pf, int next}) _readPf(int p, int end) {
    final pf = _Pf();
    final m = u32(p);
    p += 4;
    int take2() {
      if (p + 2 > end) throw RangeError('pf');
      final v = i16(p);
      p += 2;
      return v;
    }

    if (m & 0xF != 0) pf.bulletFlags = take2();
    if (m & (1 << 7) != 0) pf.bulletChar = take2() & 0xFFFF;
    if (m & (1 << 4) != 0) pf.bulletFont = take2();
    if (m & (1 << 6) != 0) pf.bulletSize = take2();
    if (m & (1 << 5) != 0) {
      if (p + 4 > end) throw RangeError('pf');
      pf.bulletColor = u32(p);
      p += 4;
    }
    if (m & (1 << 11) != 0) pf.align = take2();
    if (m & (1 << 12) != 0) pf.lineSpacing = take2();
    if (m & (1 << 13) != 0) pf.spaceBefore = take2();
    if (m & (1 << 14) != 0) pf.spaceAfter = take2();
    if (m & (1 << 8) != 0) pf.leftMargin = take2();
    if (m & (1 << 10) != 0) pf.indent = take2();
    if (m & (1 << 15) != 0) take2();
    if (m & (1 << 20) != 0) {
      final n = take2() & 0xFFFF;
      p += n * 4;
    }
    if (m & (1 << 16) != 0) take2();
    if (m & (7 << 17) != 0) take2();
    if (m & (1 << 21) != 0) take2();
    if (p > end) throw RangeError('pf');
    return (pf: pf, next: p);
  }

  ({_Cf cf, int next}) _readCf(int p, int end) {
    final cf = _Cf();
    if (p + 4 > end) throw RangeError('cf');
    final m = u32(p);
    p += 4;
    int take2() {
      if (p + 2 > end) throw RangeError('cf');
      final v = u16(p);
      p += 2;
      return v;
    }

    if (m & 0x3EB7 != 0) {
      final st = take2();
      if (m & 1 != 0) cf.bold = st & 1 != 0;
      if (m & 2 != 0) cf.italic = st & 2 != 0;
      if (m & 4 != 0) cf.underline = st & 4 != 0;
    }
    if (m & (1 << 16) != 0) cf.font = take2();
    if (m & (1 << 21) != 0) take2();
    if (m & (1 << 22) != 0) take2();
    if (m & (1 << 23) != 0) take2();
    if (m & (1 << 17) != 0) cf.size = take2();
    if (m & (1 << 18) != 0) {
      if (p + 4 > end) throw RangeError('cf');
      cf.color = u32(p);
      p += 4;
    }
    if (m & (1 << 19) != 0) cf.position = take2().toSigned(16);
    if (m & (1 << 20) != 0) p += 4;
    if (p > end) throw RangeError('cf');
    return (cf: cf, next: p);
  }

  // ── Слайд ──

  DocSlide? _slide(ArtRecord r, List<_Text> outline, Map<int, int> masterIds) {
    final info = kid(r, _rtSlideShowInfo);
    if (info != null && info.len >= 12 && u16(info.at + 10) & 0x4 != 0) return null;
    final atom = kid(r, _rtSlideAtom);
    var flags = 7;
    var masterId = 0;
    var notesId = 0;
    if (atom != null && atom.len >= 22) {
      masterId = u32(atom.at + 12);
      notesId = u32(atom.at + 16);
      flags = u16(atom.at + 20);
    }
    final m = _master(masterId, masterIds);
    final scheme = kid(r, _rtColorScheme, 1);
    final local = _Master()
      ..scheme = flags & 2 == 0 && scheme != null ? _scheme(scheme) : m.scheme
      ..styles.addAll(m.styles);
    final shapes = <DocShape>[];
    if (flags & 1 != 0) shapes.addAll(m.shapes);
    DocFill? bg = m.background;
    final drawing = kid(r, _rtDrawing);
    if (drawing != null) {
      final own = _drawing(drawing, local, shapes, outline);
      if (flags & 4 == 0 && own != null) bg = own;
    }
    return DocSlide(background: bg, shapes: shapes, notes: _notes(notesId));
  }

  // ── Заметки докладчика ──

  /// Текст заметок к слайду: страница заметок [notesId] → её фигуры →
  /// текст заполнителя «текст заметок». '' — заметок нет.
  String _notes(int notesId) {
    if (notesId == 0 || _textLeft <= 0) return '';
    final pid = _notesIds[notesId];
    final off = pid == null ? null : persist[pid];
    final r = off == null ? null : rec(off);
    if (r == null || r.type != _rtNotes) return '';
    final drawing = kid(r, _rtDrawing);
    final dg = drawing == null ? null : kid(drawing, 0xF002);
    if (dg == null) return '';
    final parts = <String>[];
    void walk(ArtRecord g, int depth) {
      if (depth > OfficeLimits.maxDepth) return;
      for (final k in kids(g)) {
        if (parts.length >= 50) return;
        if (k.type == 0xF003) {
          walk(k, depth + 1);
        } else if (k.type == 0xF004) {
          final t = _notesBody(k);
          if (t != null && t.trim().isNotEmpty) parts.add(t);
        }
      }
    }

    walk(dg, 0);
    final text = DocSlide.cleanNotes(parts.join('\n'));
    _textLeft -= text.length;
    return text;
  }

  /// Текст фигуры страницы заметок, если это «текст заметок»; иначе null
  /// (картинка слайда, номер страницы, колонтитулы).
  String? _notesBody(ArtRecord sp) {
    final box = kid(sp, 0xF00D);
    if (box == null) return null;
    final data = kid(sp, 0xF011);
    final ph = data == null ? null : kid(data, _rtPlaceholder);
    // OEPlaceholderAtom: положение (4 байта), вид заполнителя (1 байт).
    var notes = ph != null && ph.len >= 5 && s[ph.at + 4] == 0x0C;
    final out = StringBuffer();
    for (final k in kids(box)) {
      if (k.type == _rtTextHeader && k.len >= 4) {
        if (u32(k.at) == 2) notes = true;
      } else if (k.type == _rtTextChars || k.type == _rtTextBytes) {
        out.write(_chars(k));
      }
    }
    return notes ? out.toString() : null;
  }

  // ── Внедрённые объекты ──

  void _readExObjs(ArtRecord doc) {
    final list = kid(doc, _rtExObjList);
    if (list == null) return;
    for (final e in kids(list)) {
      if (_exObjs.length >= 10000) break;
      if (e.type == _rtExEmbed || e.type == _rtExLink || e.type == _rtExControl) {
        final a = kid(e, _rtExOleObjAtom);
        if (a != null && a.len >= 24) _exObjs.putIfAbsent(u32(a.at + 8), () => e);
      } else if (_rtMedia.contains(e.type)) {
        final video = kid(e, _rtExVideo);
        final a = kid(video ?? e, _rtExMediaAtom);
        if (a != null && a.len >= 4) _exObjs.putIfAbsent(u32(a.at), () => e);
      }
    }
  }

  /// Вид объекта [id] для плашки на месте его картинки.
  DocEmbed _embedKind(int id) => _embedKinds.putIfAbsent(id, () {
    final e = _exObjs[id];
    if (e == null) return DocEmbed.object;
    if (_rtMedia.contains(e.type)) return DocEmbed.media;
    final a = kid(e, _rtExOleObjAtom)!;
    // ExOleObjAtom.subType: 4 — Graph, 5 — OrgChart, 8 — звук,
    // 0x0E — диаграмма Excel, 0x0F — проигрыватель.
    switch (u32(a.at + 12)) {
      case 4 || 0x0E:
        return DocEmbed.chart;
      case 5:
        return DocEmbed.diagram;
      case 8 || 0x0F:
        return DocEmbed.media;
    }
    final names = StringBuffer();
    for (final k in kids(e)) {
      if (k.type == _rtCString) names.write(' ${_chars(k)}');
    }
    final byName = _kindByName(names.toString());
    if (byName != null) return byName;
    if (e.type == _rtExEmbed) {
      final off = persist[u32(a.at + 16)];
      final st = off == null ? null : rec(off);
      if (st != null && st.type == _rtExOleObjStg) {
        final kind = _kindByName(_compObj(st) ?? '');
        if (kind != null) return kind;
      }
    }
    return DocEmbed.object;
  });

  static DocEmbed? _kindByName(String name) {
    final n = name.toLowerCase();
    if (n.contains('orgchart') || n.contains('orgplus')) return DocEmbed.diagram;
    if (n.contains('chart') || n.contains('msgraph')) return DocEmbed.chart;
    return null;
  }

  /// Строки потока «\u0001CompObj» хранилища объекта (имя и вид
  /// программы); null — не прочитать.
  String? _compObj(ArtRecord st) {
    const limit = 8 * 1024 * 1024;
    Uint8List? raw;
    if (st.inst == 1) {
      // Сжатое: размер после распаковки (4 байта) и поток zlib.
      if (st.len < 6 || u32(st.at) > limit) return null;
      raw = _inflate(Uint8List.sublistView(s, st.at + 4, st.end), limit);
    } else {
      raw = Uint8List.sublistView(s, st.at, st.end);
    }
    if (raw == null) return null;
    try {
      final c = CfbFile.open(raw).read('\u0001CompObj', max: 4096);
      if (c == null) return null;
      return String.fromCharCodes([for (final b in c) b >= 0x20 && b < 0x7F ? b : 0x20]);
    } on OfficeDocException {
      return null;
    } on RangeError {
      return null;
    }
  }

  /// Распаковка zlib с пределом на результат; null — испорчено или больше.
  static Uint8List? _inflate(Uint8List b, int limit) {
    final filter = RawZLibFilter.inflateFilter();
    final out = BytesBuilder(copy: false);
    var total = 0;
    bool drain({bool end = false}) {
      while (true) {
        final chunk = filter.processed(flush: false, end: end);
        if (chunk == null || chunk.isEmpty) return true;
        total += chunk.length;
        if (total > limit) return false;
        out.add(chunk);
      }
    }

    try {
      const step = 16 * 1024;
      for (var i = 0; i < b.length; i += step) {
        filter.process(b, i, math.min(b.length, i + step));
        if (!drain()) return null;
      }
      if (!drain(end: true)) return null;
    } catch (_) {
      // Оборванный поток: что успели распаковать (каталог хранилища может
      // быть и в начале).
      if (total == 0) return null;
    }
    return out.takeBytes();
  }

  /// Текст заполнителя из списка слайдов (заголовок текста, знаки, стиль).
  void _collectText(ArtRecord a, List<_Text> out) {
    switch (a.type) {
      case _rtTextHeader:
        if (a.len >= 4 && out.length < 1000) out.add(_Text()..type = u32(a.at));
      case _rtTextChars || _rtTextBytes:
        if (out.isNotEmpty) out.last.text = _chars(a);
      case _rtStyleTextProp:
        if (out.isNotEmpty) _styleProps(a, out.last);
    }
  }

  String _chars(ArtRecord a) {
    final n = math.min(a.len, 128 * 1024);
    if (a.type == _rtTextBytes) return String.fromCharCodes(Uint8List.sublistView(s, a.at, a.at + n));
    return String.fromCharCodes([for (var i = 0; i + 1 < n; i += 2) u16(a.at + i)]);
  }

  void _styleProps(ArtRecord a, _Text t) {
    final total = t.text.length + 1;
    final pf = <_PRun>[];
    final cf = <_CRun>[];
    var p = a.at;
    try {
      var got = 0;
      while (got < total && p + 6 <= a.end && pf.length < 10000) {
        final count = u32(p);
        final level = u16(p + 4);
        final r = _readPf(p + 6, a.end);
        p = r.next;
        pf.add(_PRun(count, level, r.pf));
        got += count;
        if (count == 0) break;
      }
      got = 0;
      while (got < total && p + 4 <= a.end && cf.length < 10000) {
        final count = u32(p);
        final r = _readCf(p + 4, a.end);
        p = r.next;
        cf.add(_CRun(count, r.cf));
        got += count;
        if (count == 0) break;
      }
    } on RangeError {
      // Оформление обрезано — что успели прочитать, остальное — по образцу.
    }
    t.pf = pf;
    t.cf = cf;
  }

  // ── Рисунок ──

  /// Фигуры рисунка [drawing] в [out]; возвращает фон (фигура-фон).
  /// [master] — фигуры образца: заполнители (места для текста слайдов)
  /// не рисуются.
  DocFill? _drawing(ArtRecord drawing, _Master m, List<DocShape> out, List<_Text> outline, {bool master = false}) {
    final dg = kid(drawing, 0xF002);
    if (dg == null) return null;
    DocFill? bg;
    for (final r in kids(dg)) {
      if (r.type == 0xF003) {
        _group(r, m, out, outline, master, null, 0);
      } else if (r.type == 0xF004) {
        final f = _shape(r, m, out, outline, master, null);
        bg ??= f;
      }
    }
    return bg;
  }

  /// Группа: первая фигура — сама группа (её система координат и рамка).
  void _group(ArtRecord g, _Master m, List<DocShape> out, List<_Text> outline, bool master, _Xf? xf, int depth) {
    if (depth > OfficeLimits.maxDepth) {
      _truncated = true;
      return;
    }
    _Xf? inner = xf;
    var first = true;
    for (final r in kids(g)) {
      if (out.length >= OfficeSlidesDoc.maxShapes) {
        _truncated = true;
        return;
      }
      if (first && r.type == 0xF004) {
        first = false;
        final spgr = kid(r, 0xF009);
        final box = _anchor(r, xf);
        if (spgr != null && spgr.len >= 16 && box != null) {
          final l = i32(spgr.at), t = i32(spgr.at + 4), rr = i32(spgr.at + 8), b = i32(spgr.at + 12);
          if (rr != l && b != t) {
            inner = _Xf(
              (box.w) / (rr - l),
              (box.h) / (b - t),
              box.x - l * box.w / (rr - l),
              box.y - t * box.h / (b - t),
            );
          }
        }
        continue;
      }
      first = false;
      if (r.type == 0xF003) {
        _group(r, m, out, outline, master, inner, depth + 1);
      } else if (r.type == 0xF004) {
        _shape(r, m, out, outline, master, inner);
      }
    }
  }

  /// Рамка фигуры в пунктах: ClientAnchor (1/576 дюйма) у фигур верхнего
  /// уровня, ChildAnchor — в координатах группы.
  ({double x, double y, double w, double h})? _anchor(ArtRecord sp, _Xf? xf) {
    final child = kid(sp, 0xF00F);
    if (child != null && child.len >= 16 && xf != null) {
      final l = i32(child.at), t = i32(child.at + 4), r = i32(child.at + 8), b = i32(child.at + 12);
      return (x: xf.x(l.toDouble()), y: xf.y(t.toDouble()), w: (r - l) * xf.sx, h: (b - t) * xf.sy);
    }
    final a = kid(sp, 0xF010);
    if (a == null) return null;
    double top, left, right, bottom;
    if (a.len >= 16) {
      top = i32(a.at).toDouble();
      left = i32(a.at + 4).toDouble();
      right = i32(a.at + 8).toDouble();
      bottom = i32(a.at + 12).toDouble();
    } else if (a.len >= 8) {
      top = i16(a.at).toDouble();
      left = i16(a.at + 2).toDouble();
      right = i16(a.at + 4).toDouble();
      bottom = i16(a.at + 6).toDouble();
    } else {
      return null;
    }
    return (x: left / 8, y: top / 8, w: (right - left) / 8, h: (bottom - top) / 8);
  }

  _Opt _opt(ArtRecord r) {
    final o = _Opt();
    final n = r.inst;
    var complex = r.at + n * 6;
    for (var i = 0; i < n && r.at + (i + 1) * 6 <= r.end; i++) {
      final id = u16(r.at + i * 6);
      final v = u32(r.at + i * 6 + 2);
      final pid = id & 0x3FFF;
      if (id & 0x8000 != 0) {
        if (complex + v <= r.end) o.complex[pid] = Uint8List.sublistView(s, complex, complex + v);
        complex += v;
      } else {
        o.values[pid] = v;
      }
    }
    return o;
  }

  /// Цвет OfficeArtCOLORREF: RGB, номер схемы; системные — null.
  int? _artColor(int? v, _Master m) {
    if (v == null) return null;
    final flags = v >> 24;
    if (flags & 0x08 != 0) {
      final i = v & 0xFF;
      return i < m.scheme.length ? m.scheme[i] : null;
    }
    if (flags & 0x10 != 0) return null;
    return 0xFF000000 | ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF);
  }

  /// Цвет текста ColorIndexStruct: RGB (номер 0xFE) или номер схемы.
  int? _textColor(int? v, _Master m) {
    if (v == null) return null;
    final index = v >>> 24;
    if (index == 0xFE) return 0xFF000000 | ((v & 0xFF) << 16) | (v & 0xFF00) | ((v >> 16) & 0xFF);
    if (index < 8 && index < m.scheme.length) return m.scheme[index];
    return null;
  }

  static const _geoms = <int, DocGeom>{
    1: DocGeom.rect,
    2: DocGeom.roundRect,
    3: DocGeom.ellipse,
    4: DocGeom.diamond,
    5: DocGeom.triangle,
    6: DocGeom.rtTriangle,
    7: DocGeom.parallelogram,
    8: DocGeom.trapezoid,
    9: DocGeom.hexagon,
    10: DocGeom.octagon,
    11: DocGeom.plus,
    12: DocGeom.star5,
    13: DocGeom.rightArrow,
    15: DocGeom.homePlate,
    20: DocGeom.line,
    32: DocGeom.line,
    55: DocGeom.chevron,
    56: DocGeom.pentagon,
    66: DocGeom.leftArrow,
    67: DocGeom.downArrow,
    68: DocGeom.upArrow,
    69: DocGeom.leftRightArrow,
  };

  /// Фигура в [out]; у фигуры-фона — её заливка (сама фигура не рисуется).
  DocFill? _shape(ArtRecord sp, _Master m, List<DocShape> out, List<_Text> outline, bool master, _Xf? xf) {
    final fsp = kid(sp, 0xF00A);
    if (fsp == null || fsp.len < 8) return null;
    final type = fsp.inst;
    final flags = u32(fsp.at + 4);
    if (flags & 0x8 != 0) return null; // удалённая
    final own = kid(sp, 0xF00B);
    final o = defaults.over(own == null ? null : _opt(own));
    final explicit = own == null ? _Opt() : _opt(own);
    final data = kid(sp, 0xF011);
    final placeholder = data != null && kid(data, _rtPlaceholder) != null;
    final textBox = kid(sp, 0xF00D);

    // Заливка и линия: явные свойства фигуры поверх умолчаний документа; у
    // надписей и заполнителей — только явные (по умолчанию их не видно).
    final plain = type == 202 || placeholder;
    final src = plain ? explicit : o;
    final fillB = src.values[0x01BF];
    final filled = fillB == null ? (!plain && src.values.containsKey(0x0181)) : (fillB & 0x10 != 0);
    final lineB = src.values[0x01FF];
    final lined = lineB == null ? (!plain && src.values.containsKey(0x01C0)) : (lineB & 0x8 != 0);
    DocFill? fill;
    final pib = o.values[0x0104] ?? (o.values[0x0180] == 3 ? o.values[0x0186] : null);
    if (filled) {
      final ft = src.values[0x0180] ?? 0;
      if ((ft == 2 || ft == 3) && src.values[0x0186] != null) {
        final img = _blip(src.values[0x0186]!);
        if (img != null) fill = DocFill.picture(img, tile: ft == 2);
      }
      if (fill == null) {
        final c = _artColor(src.values[0x0181] ?? 0x00FFFFFF, m);
        if (c != null) fill = DocFill.solid(c);
      }
    }
    if (flags & 0x400 != 0) return fill;
    if (master && placeholder) return null;

    final box = _anchor(sp, xf);
    if (box == null || !box.w.isFinite || !box.h.isFinite) return null;
    DocLine? line;
    if (lined) {
      final c = _artColor(src.values[0x01C0] ?? 0, m) ?? 0xFF000000;
      final w = (src.values[0x01CB] ?? 9525) / 12700;
      final dash = switch (src.values[0x01CE] ?? 0) {
        0 => DocDash.solid,
        2 || 5 || 6 => DocDash.dot,
        3 || 4 || 8 || 9 => DocDash.dashDot,
        _ => DocDash.dash,
      };
      line = DocLine(c, w.clamp(0, 50).toDouble(), dash: dash);
    }
    DocPicture? picture;
    if (type == 75 || (pib != null && o.values[0x0104] != null)) {
      final img = pib == null ? null : _blip(pib);
      if (img != null) picture = DocPicture(img);
    }
    // Внедрённый объект без картинки, которую можно показать, — плашка.
    DocEmbed? embed;
    final ref = data == null || picture != null ? null : kid(data, _rtExObjRef);
    if (ref != null && ref.len >= 4) embed = _embedKind(u32(ref.at));

    _Text? text;
    if (textBox != null) {
      for (final k in kids(textBox)) {
        if (k.type == _rtOutlineTextRef && k.len >= 4) {
          final i = u32(k.at);
          if (i < outline.length) text = outline[i];
        } else if (k.type == _rtTextHeader && k.len >= 4) {
          text = _Text()..type = u32(k.at);
        } else if (text != null) {
          _collectText(k, [text]);
        }
      }
    }
    final rot = (o.values[0x0004] ?? 0).toSigned(32) / 65536;
    if (text != null && text.text.isNotEmpty && _textLeft <= 0) _truncated = true;
    final body = text == null || text.text.isEmpty || _textLeft <= 0 ? null : _body(text, o, m, placeholder);
    final geom = _geoms[type];
    // Линия не заливается; свой контур (так пишет и LibreOffice) — по вершинам.
    if (geom == DocGeom.line) fill = null;
    final path = geom == null && picture == null ? _path(src) : null;
    if (fill == null && line == null && picture == null && body == null && embed == null) return null;
    out.add(
      DocShape(
        x: box.x,
        y: box.y,
        w: box.w,
        h: box.h,
        rotation: rot.isFinite ? rot : 0,
        flipH: flags & 0x40 != 0,
        flipV: flags & 0x80 != 0,
        geom: path != null ? DocGeom.path : (geom ?? DocGeom.rect),
        path: path,
        fill: path != null && !path.filled ? null : fill,
        line: line,
        picture: picture,
        text: body,
        embed: embed,
      ),
    );
    return null;
  }

  /// Свой контур фигуры: вершины (pVertices) и сегменты (pSegmentInfo) в
  /// системе координат geoLeft…geoRight × geoTop…geoBottom ([MS-ODRAW]);
  /// null — контура нет или он испорчен (тогда — прямоугольник).
  DocPath? _path(_Opt o) {
    final v = o.complex[0x0145];
    if (v == null || v.length < 6) return null;
    final vb = ByteData.sublistView(v);
    final n = math.min(vb.getUint16(0, Endian.little), 10000);
    final cb = vb.getUint16(4, Endian.little);
    final size = cb == 0xFFF0 ? 4 : cb;
    if (size != 4 && size != 8) return null;
    final pts = <double>[];
    for (var i = 0; i < n && 6 + (i + 1) * size <= v.length; i++) {
      final at = 6 + i * size;
      if (size == 4) {
        pts
          ..add(vb.getInt16(at, Endian.little).toDouble())
          ..add(vb.getInt16(at + 2, Endian.little).toDouble());
      } else {
        // Вершина-формула (0x8000xxxx — ссылка на pGuides, так пишет
        // LibreOffice) не вычисляется: фигура — прямоугольником.
        final x = vb.getUint32(at, Endian.little), y = vb.getUint32(at + 4, Endian.little);
        if (x & 0x80000000 != 0 && x >= 0x80000000 && x < 0x80010000) return null;
        if (y & 0x80000000 != 0 && y >= 0x80000000 && y < 0x80010000) return null;
        pts
          ..add(x.toSigned(32).toDouble())
          ..add(y.toSigned(32).toDouble());
      }
    }
    if (pts.length < 4) return null;
    final left = (o.values[0x0140] ?? 0).toSigned(32), top = (o.values[0x0141] ?? 0).toSigned(32);
    final right = (o.values[0x0142] ?? 21600).toSigned(32), bottom = (o.values[0x0143] ?? 21600).toSigned(32);
    if (right == left || bottom == top) return null;
    final ops = <DocPathOp>[];
    final out = <double>[];
    var k = 0;
    var closed = false;
    bool take(int count) {
      if (k + count * 2 > pts.length) return false;
      for (var i = 0; i < count; i++) {
        out
          ..add((pts[k] - left) / (right - left))
          ..add((pts[k + 1] - top) / (bottom - top));
        k += 2;
      }
      return true;
    }

    final seg = o.complex[0x0146];
    if (seg == null || seg.length < 6) {
      // Без сегментов — ломаная по всем вершинам.
      ops.add(DocPathOp.move);
      take(1);
      while (k < pts.length) {
        ops.add(DocPathOp.line);
        take(1);
      }
      return DocPath(ops, out, filled: false);
    }
    final sb = ByteData.sublistView(seg);
    final count = math.min(sb.getUint16(0, Endian.little), 10000);
    for (var i = 0; i < count && 6 + (i + 1) * 2 <= seg.length && ops.length < 20000; i++) {
      final info = sb.getUint16(6 + i * 2, Endian.little);
      final kind = info >> 13;
      final num = info & 0x1FFF;
      switch (kind) {
        case 0:
          for (var j = 0; j < math.max(num, 1); j++) {
            if (!take(1)) break;
            ops.add(DocPathOp.line);
          }
        case 1:
          for (var j = 0; j < math.max(num, 1); j++) {
            if (!take(3)) break;
            ops.add(DocPathOp.cubic);
          }
        case 2:
          if (take(1)) ops.add(DocPathOp.move);
        case 3:
          ops.add(DocPathOp.close);
          closed = true;
        case 5:
          // Особые сегменты (дуги и т. п.): их вершины пропускаются.
          k = math.min(pts.length, k + (info & 0xFF) * 2);
      }
    }
    if (ops.isEmpty || ops.first != DocPathOp.move) return null;
    return DocPath(ops, out, filled: closed);
  }

  // ── Текст фигуры ──

  /// Стиль образца для вида текста [type] и уровня [level]: «по центру»,
  /// «половина», «четверть» — поверх основного; заголовки — поверх заголовка.
  (_Pf, _Cf) _style(_Master m, int type, int level) {
    final base = switch (type) {
      0 || 6 => 0,
      1 || 5 || 7 || 8 => 1,
      _ => type,
    };
    (_Pf, _Cf)? at(int t) {
      final l = m.styles[t];
      if (l == null || l.isEmpty) return null;
      return l[level.clamp(0, l.length - 1)];
    }

    final b = at(base);
    final own = type == base ? null : at(type);
    var pf = (b?.$1 ?? _Pf()).over(own?.$1);
    var cf = (b?.$2 ?? _Cf()).over(own?.$2);
    final title = base == 0;
    cf =
        (_Cf()
              ..size = title ? 44 : (base == 1 ? const [32, 28, 24, 20, 20][level.clamp(0, 4)] : 18)
              ..bold = false
              ..italic = false
              ..underline = false)
            .over(cf);
    pf = (_Pf()..align = title ? 1 : 0).over(pf);
    return (pf, cf);
  }

  DocTextBody _body(_Text t, _Opt o, _Master m, bool placeholder) {
    final paragraphs = <DocParagraph>[];
    var text = t.text;
    if (text.length > _textLeft) {
      text = text.substring(0, math.max(0, _textLeft));
      _truncated = true;
    }
    _textLeft -= text.length;
    final title = t.type == 0 || t.type == 6;
    var start = 0;
    var pIndex = 0, pLeft = t.pf.isEmpty ? 0 : t.pf.first.count;
    var cIndex = 0, cLeft = t.cf.isEmpty ? 0 : t.cf.first.count;
    while (start <= text.length && paragraphs.length < 2000) {
      var end = text.indexOf('\r', start);
      if (end < 0) end = text.length;
      // Свойства абзаца — участка, где он начинается.
      while (pIndex < t.pf.length - 1 && pLeft <= 0) {
        pIndex++;
        pLeft += t.pf[pIndex].count;
      }
      final pr = t.pf.isEmpty ? null : t.pf[pIndex];
      final level = (pr?.level ?? 0).clamp(0, 4);
      final st = _style(m, t.type, level);
      final pf = st.$1.over(pr?.pf);
      final runs = <DocRun>[];
      var i = start;
      var lastSize = (st.$2.size ?? 18).toDouble();
      while (i < end) {
        while (cIndex < t.cf.length - 1 && cLeft <= 0) {
          cIndex++;
          cLeft += t.cf[cIndex].count;
        }
        final take = t.cf.isEmpty || cLeft <= 0 ? end - i : math.min(end - i, cLeft);
        final cf = st.$2.over(t.cf.isEmpty ? null : t.cf[cIndex].cf);
        final piece = text.substring(i, i + take).replaceAll('\v', '\n');
        final size = (cf.size ?? 18).clamp(1, 400).toDouble();
        lastSize = size;
        final font = cf.font == null || cf.font! >= fonts.length ? null : fonts[cf.font!];
        runs.add(
          DocRun(
            DocHtml.symbols(piece, font),
            size: size,
            color: _textColor(cf.color, m) ?? (title ? m.scheme[3] : m.scheme[1]),
            bold: cf.bold ?? false,
            italic: cf.italic ?? false,
            underline: cf.underline ?? false,
            baseline: (cf.position ?? 0).toDouble(),
            font: font,
          ),
        );
        i += take;
        cLeft -= take;
      }
      // Знак конца абзаца — тоже знак участков.
      cLeft -= 1;
      pLeft -= end - start + 1;
      final bulletOn = (pf.bulletFlags ?? 0) & 1 != 0 && runs.any((r) => r.text.trim().isNotEmpty);
      DocBullet? bullet;
      if (bulletOn) {
        final hasFont = (pf.bulletFlags ?? 0) & 2 != 0;
        final bf = hasFont && pf.bulletFont != null && pf.bulletFont! < fonts.length ? fonts[pf.bulletFont!] : null;
        final ch = pf.bulletChar == null || pf.bulletChar == 0 ? '•' : String.fromCharCode(pf.bulletChar!);
        bullet = DocBullet(
          DocHtml.bullet(ch, bf),
          color: (pf.bulletFlags ?? 0) & 4 != 0 ? _textColor(pf.bulletColor, m) : null,
          sizeScale: (pf.bulletFlags ?? 0) & 8 != 0 && (pf.bulletSize ?? 0) > 0 ? pf.bulletSize! / 100 : 1,
        );
      }
      double spacing(int? v) => v == null ? 0 : (v >= 0 ? v / 100 * lastSize : -v / 8);
      final ls = pf.lineSpacing;
      final margin = (pf.leftMargin ?? level * 288) / 8;
      final indent = (pf.indent ?? pf.leftMargin ?? level * 288) / 8;
      paragraphs.add(
        DocParagraph(
          align: switch (pf.align ?? 0) {
            1 => DocAlign.center,
            2 => DocAlign.right,
            3 || 4 || 6 => DocAlign.justify,
            _ => DocAlign.left,
          },
          level: level,
          marginLeft: margin.clamp(0, 2000).toDouble(),
          indent: (indent - margin).clamp(-2000, 2000).toDouble(),
          bullet: bullet,
          spaceBefore: spacing(pf.spaceBefore).clamp(0, 400).toDouble(),
          spaceAfter: spacing(pf.spaceAfter).clamp(0, 400).toDouble(),
          lineSpacing: ls != null && ls > 0 ? (ls / 100).clamp(0.5, 5).toDouble() : 1,
          lineExact: ls != null && ls < 0 ? (-ls / 8).clamp(1, 400).toDouble() : null,
          endSize: lastSize,
          runs: runs,
        ),
      );
      if (end >= text.length) break;
      start = end + 1;
    }
    // Последний пустой абзац (знак конца текста) не нужен.
    while (paragraphs.length > 1 && paragraphs.last.runs.every((r) => r.text.isEmpty)) {
      paragraphs.removeLast();
    }
    double inset(int id, double def) {
      final v = o.values[id];
      return v == null ? def : (v / 12700).clamp(0, 500).toDouble();
    }

    final anchorV = o.values[0x0087];
    return DocTextBody(
      insetLeft: inset(0x0081, 7.2),
      insetTop: inset(0x0082, 3.6),
      insetRight: inset(0x0083, 7.2),
      insetBottom: inset(0x0084, 3.6),
      anchor: anchorV == null
          ? (title && placeholder ? DocAnchor.middle : DocAnchor.top)
          : switch (anchorV) {
              1 || 4 || 7 => DocAnchor.middle,
              2 || 5 || 8 => DocAnchor.bottom,
              _ => DocAnchor.top,
            },
      wrap: o.values[0x0085] != 2,
      shrink: placeholder,
      paragraphs: paragraphs,
    );
  }
}

/// Преобразование координат группы в пункты слайда.
class _Xf {
  final double sx, sy, dx, dy;
  const _Xf(this.sx, this.sy, this.dx, this.dy);
  double x(double v) => v * sx + dx;
  double y(double v) => v * sy + dy;
}

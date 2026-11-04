// lib/services/documents/rtf_reader.dart
// Документ RTF → HTML для просмотра вложения (1.11.x, предпросмотр
// документов, план владельца 04.11.2026). Формат — Microsoft RTF 1.9.1:
// группы {…}, управляющие слова со знаковым числом, управляющие символы,
// байты \'hh в кодовой странице шрифта или документа, \uN (отрицательные —
// +65536) с пропуском \ucN заменителей, \binN.
//
// Кодовая страница: у шрифта — по \fcharsetN (204 — 1251, 238 — 1250 …) или
// \cpgN, у документа — \ansicpgN; без них — по языку документа (\deflangN),
// а без него — по языку приложения (русский интерфейс — 1251: старые RTF из
// русского Word без \ansicpg иначе шли бы «Ïðèâåò»).
//
// Что показывается: абзацы с выравниванием, отступами, интервалами,
// заливкой и рамками; оформление текста (жирный, курсив, подчёркивание,
// зачёркивание, размер, цвет, маркер, над- и подстрочный, капитель, скрытый
// текст не виден); заголовки (стиль «heading N»/«Title» в таблице стилей или
// \outlinelevelN); номера списков — готовым текстом {\listtext …} /
// {\pntext …}; таблицы (\trowd, \cellx, объединения \clmgf/\clvmgf, заливка,
// рамки); ссылки HYPERLINK; картинки PNG и JPEG (\pngblip, \jpegblip);
// сноски — под чертой. Не показываются: колонтитулы, примечания, картинки
// WMF/EMF и объекты OLE (кроме их готовой картинки PNG/JPEG), вложенные
// таблицы (их текст — абзацами в ячейке), многобайтовые кодовые страницы без
// \uN, позиции табуляции и межстрочный интервал.

import 'dart:convert';
import 'dart:typed_data';

import 'doc_codepages.dart';
import 'doc_html.dart';
import 'office_document.dart';
import 'office_package.dart';

class RtfReader {
  RtfReader._();

  /// Похоже ли начало файла на RTF («{\rtf»).
  static bool looksLikeRtf(Uint8List head) {
    var i = 0;
    if (head.length >= 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF) i = 3;
    while (i < head.length && (head[i] == 0x20 || head[i] == 0x0D || head[i] == 0x0A || head[i] == 0x09)) {
      i++;
    }
    return i + 5 <= head.length && latin1.decode(head.sublist(i, i + 5)) == r'{\rtf';
  }

  /// Разобрать документ. [lang] — язык приложения: кодовая страница для
  /// документа, который её не объявил. Ошибки — только [OfficeDocException].
  static OfficeTextDoc read(Uint8List bytes, {String lang = 'en'}) {
    if (bytes.length > OfficeLimits.maxFileBytes) throw const OfficeDocException(OfficeDocError.tooLarge, 'file');
    if (!looksLikeRtf(bytes.length > 64 ? Uint8List.sublistView(bytes, 0, 64) : bytes)) {
      throw const OfficeDocException(OfficeDocError.damaged, 'not rtf');
    }
    try {
      return _Rtf(bytes, lang).run();
    } on OfficeDocException {
      rethrow;
    } catch (e) {
      throw OfficeDocException(OfficeDocError.damaged, '$e');
    }
  }
}

/// Куда идёт текст группы.
enum _Dest {
  text,
  skip,
  fonttbl,
  colortbl,
  stylesheet,
  listtext,
  fldinst,
  pict,

  /// Свойства фигуры (\shp, \shpinst, \sp …): текст не показывается, но
  /// картинка (\pict) и надпись (\shptxt) внутри — да.
  shape,
}

/// Линия рамки, которую сейчас описывают \brdr*.
enum _Side { none, pTop, pBottom, pLeft, pRight, pBox, cTop, cBottom, cLeft, cRight }

class _Para {
  int align = 0;
  int li = 0, ri = 0, fi = 0, sb = 0, sa = 0;
  bool sbAuto = false, saAuto = false;
  bool intbl = false;
  int style = 0;
  int? outline;
  bool rtl = false;
  int? shade;
  bool pageBefore = false;
  bool contextual = false;
  DocLine? top, bottom, left, right;

  _Para copy() => _Para()
    ..contextual = contextual
    ..align = align
    ..li = li
    ..ri = ri
    ..fi = fi
    ..sb = sb
    ..sa = sa
    ..sbAuto = sbAuto
    ..saAuto = saAuto
    ..intbl = intbl
    ..style = style
    ..outline = outline
    ..rtl = rtl
    ..shade = shade
    ..pageBefore = pageBefore
    ..top = top
    ..bottom = bottom
    ..left = left
    ..right = right;
}

/// Состояние группы: оформление текста, абзаца, назначение текста.
class _St {
  bool b = false, i = false, ul = false, strike = false, caps = false, scaps = false, hidden = false;
  DocVert vert = DocVert.none;
  int fs = 24;
  int cf = 0, cb = 0, hl = 0;
  int font = -1;
  int uc = 1;
  _Para para = _Para();
  _Dest dest = _Dest.text;
  String? href;
  _Field? field;

  _St copy() => _St()
    ..b = b
    ..i = i
    ..ul = ul
    ..strike = strike
    ..caps = caps
    ..scaps = scaps
    ..hidden = hidden
    ..vert = vert
    ..fs = fs
    ..cf = cf
    ..cb = cb
    ..hl = hl
    ..font = font
    ..uc = uc
    ..para = para
    ..dest = dest
    ..href = href
    ..field = field;

  void plain(int deff) {
    b = i = ul = strike = caps = scaps = hidden = false;
    vert = DocVert.none;
    fs = 24;
    cf = cb = hl = 0;
    font = deff;
  }
}

/// Оформление текста стиля абзаца из таблицы стилей.
class _StyleDef {
  int? fs, cf, basedOn;
  bool? b, i;
}

class _Field {
  final instr = StringBuffer();
}

class _Font {
  int charset = 1;
  int? cpg;
  bool fixed = false;
  final name = StringBuffer();
  String get family => name.toString().trim();
}

/// Ячейка в описании строки (\cellx и свойства перед ним).
class _CellDef {
  int right = 0;
  bool vFirst = false, vMerged = false, hFirst = false, hMerged = false;
  int? bg;
  int valign = 0;
  DocLine? top, bottom, left, right2;
}

class _Row {
  final List<_CellDef> defs;
  final List<List<DocBlock>> cells;
  final int left;
  final String? align;
  _Row(this.defs, this.cells, this.left, this.align);
}

/// Куда собирается текст: тело документа или сноска.
class _Sink {
  final blocks = <DocBlock>[];
  final inlines = <DocInline>[];
  final label = StringBuffer();
  DocFont? labelFont;
  final rows = <_Row>[];
  var cells = <List<DocBlock>>[];
  var cellBlocks = <DocBlock>[];
  bool lastTab = false;
  bool pageBefore = false;

  // Текущий фрагмент текста.
  final buf = StringBuffer();
  DocFont? font;
  String? fontName;
  String? href;

  /// Глубина группы, на которой кончается сноска (у тела — 0).
  final int depth;
  _Sink(this.depth);
}

class _Rtf {
  _Rtf(this.data, String lang) : appCp = DocCodePages.forLanguage(lang);

  final Uint8List data;
  final int appCp;
  final budget = DocBudget();
  final images = <String, String>{};
  int imagesTotal = 0;

  int? ansiCpg;
  int? defLang;
  int deff = -1;
  final fonts = <int, _Font>{};
  final colors = <int?>[];
  final headings = <int, int>{};
  final styleDefs = <int, _StyleDef>{};
  var styleDef = _StyleDef();

  // Таблица шрифтов, цветов, стилей — разбираемые записи.
  _Font? curFont;
  int red = 0, green = 0, blue = 0;
  bool colorSet = false;
  int curStyle = 0;
  bool styleIsPara = true;
  final styleName = StringBuffer();

  // Картинка.
  BytesBuilder? pict;
  String pictType = '';
  int picw = 0, pich = 0, goalW = 0, goalH = 0, scaleX = 100, scaleY = 100;
  bool pictTooBig = false;
  int hexHalf = -1;

  // Строка таблицы.
  var rowDefs = <_CellDef>[];
  var cellDef = _CellDef();
  int rowLeft = 0;
  int rowGaph = 108;
  String? rowAlign;
  _Side side = _Side.none;
  DocLine line = const DocLine();

  double pageWidth = 8640;
  int paperW = 12240, margL = 1800, margR = 1800;

  final notes = <DocBlock>[];
  int noteCount = 0;
  final sinks = <_Sink>[_Sink(0)];
  _Sink get sink => sinks.last;

  final stack = <_St>[];
  var st = _St();
  int skipDepth = 0;
  int pendingSkip = 0;
  bool starred = false;

  OfficeTextDoc run() {
    _parse();
    // Документ без закрывающих скобок (обрезан, испорчен) — что набралось.
    while (sinks.length > 1) {
      _closeNote();
    }
    _endPara(finalFlush: true);
    _flushTable();
    return DocHtml.render(sink.blocks, notes: notes, images: images, truncated: budget.truncated);
  }

  // ───────────────────────── разбор ─────────────────────────

  void _parse() {
    final d = data;
    var i = 0;
    final n = d.length;
    while (i < n) {
      if (budget.full) return;
      final c = d[i];
      if (c == 0x7B) {
        // {
        i++;
        pendingSkip = 0;
        if (skipDepth > 0 || stack.length >= OfficeLimits.maxDepth * 4) {
          // Слишком глубоко: группа пропускается целиком, состояний не
          // заводим.
          skipDepth++;
          continue;
        }
        stack.add(st);
        st = st.copy();
        continue;
      }
      if (c == 0x7D) {
        // }
        i++;
        pendingSkip = 0;
        if (skipDepth > 0) {
          skipDepth--;
          continue;
        }
        if (stack.isEmpty) continue; // лишняя скобка
        _endGroup();
        st = stack.removeLast();
        if (sinks.length > 1 && stack.length < sink.depth) _closeNote();
        continue;
      }
      if (skipDepth > 0 && c != 0x5C) {
        i++;
        continue;
      }
      if (c == 0x5C) {
        // \
        if (i + 1 >= n) break;
        final x = d[i + 1];
        if (_isLetter(x)) {
          var j = i + 1;
          while (j < n && j - i <= 32 && _isLetter(d[j])) {
            j++;
          }
          final word = latin1.decode(Uint8List.sublistView(d, i + 1, j));
          int? param;
          var k = j;
          var neg = false;
          if (k < n && d[k] == 0x2D) {
            neg = true;
            k++;
          }
          final ds = k;
          while (k < n && k - ds < 10 && d[k] >= 0x30 && d[k] <= 0x39) {
            k++;
          }
          if (k > ds) {
            param = int.parse(latin1.decode(Uint8List.sublistView(d, ds, k)));
            if (neg) param = -param;
          } else {
            k = j; // «-» без цифр — не параметр
          }
          if (k < n && d[k] == 0x20) k++;
          i = k;
          if (skipDepth > 0) continue;
          if (word == 'bin') {
            final len = (param ?? 0).clamp(0, n - i);
            if (st.dest == _Dest.pict) _pictBytes(Uint8List.sublistView(d, i, i + len));
            i += len;
            continue;
          }
          if (pendingSkip > 0 && word != 'u') pendingSkip = 0;
          _word(word, param);
          continue;
        }
        // Управляющий символ.
        i += 2;
        if (skipDepth > 0) continue;
        switch (x) {
          case 0x27: // \'hh
            if (i + 2 > n) break;
            final hex = int.tryParse(latin1.decode(Uint8List.sublistView(d, i, i + 2)), radix: 16);
            i += 2;
            if (hex == null) break;
            if (pendingSkip > 0) {
              pendingSkip--;
              break;
            }
            _byte(hex);
          case 0x2A: // \*
            starred = true;
          case 0x7E: // \~
            _char(0xA0);
          case 0x2D: // \-
            _char(0xAD);
          case 0x5F: // \_
            _char(0x2011);
          case 0x0A:
          case 0x0D:
            _word('par', null);
          case 0x09:
            _word('tab', null);
          case 0x5C:
          case 0x7B:
          case 0x7D:
            if (pendingSkip > 0) {
              pendingSkip--;
              break;
            }
            _char(x);
          default:
            break;
        }
        continue;
      }
      i++;
      if (c == 0x0D || c == 0x0A) continue;
      if (st.dest == _Dest.pict) {
        _pictHex(c);
        continue;
      }
      if (pendingSkip > 0) {
        pendingSkip--;
        continue;
      }
      if (c == 0x09) {
        _word('tab', null);
        continue;
      }
      if (c < 0x20) continue;
      _byte(c);
    }
  }

  static bool _isLetter(int c) => (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);

  // ───────────────────────── текст ─────────────────────────

  /// Кодовая страница текущего шрифта.
  int get _cp {
    final f = fonts[st.font];
    if (f != null) {
      if (f.cpg != null && DocCodePages.known(f.cpg!)) return f.cpg!;
      final byCharset = DocCodePages.forCharset(f.charset);
      if (byCharset != null) return byCharset;
    }
    return _docCp;
  }

  int get _docCp {
    if (ansiCpg != null && DocCodePages.known(ansiCpg!)) return ansiCpg!;
    // \ansicpg нет: по языку документа (у русского Word — \deflang1049), а
    // без него — по языку приложения.
    final byLang = defLang == null ? null : DocCodePages.forLcid(defLang!);
    return byLang ?? appCp;
  }

  bool get _symbolFont {
    final f = fonts[st.font];
    if (f == null) return false;
    if (f.charset == 2) return true;
    final n = f.family.toLowerCase();
    return n.contains('symbol') || n.contains('wingdings');
  }

  void _byte(int b) {
    // Символьный шрифт: байт — сам код знака (его заменит SymbolFonts).
    _char(b < 0x80 || _symbolFont ? b : DocCodePages.char(b, _cp));
  }

  void _char(int code) {
    switch (st.dest) {
      case _Dest.text:
        if (st.hidden) return;
        _text(String.fromCharCode(code));
      case _Dest.listtext:
        sink.label.writeCharCode(code);
        sink.labelFont ??= _font();
        _labelFontName ??= fonts[st.font]?.family;
      case _Dest.fldinst:
        if (st.field != null && st.field!.instr.length < 4096) st.field!.instr.writeCharCode(code);
      case _Dest.fonttbl:
        final f = curFont;
        if (f == null) return;
        if (code == 0x3B) {
          curFont = null;
        } else if (f.name.length < 128) {
          f.name.writeCharCode(code);
        }
      case _Dest.colortbl:
        if (code == 0x3B) {
          colors.add(colorSet ? (0xFF000000 | (red << 16) | (green << 8) | blue) : null);
          colorSet = false;
          red = green = blue = 0;
        }
      case _Dest.stylesheet:
        if (code == 0x3B) {
          _endStyle();
        } else if (styleName.length < 128) {
          styleName.writeCharCode(code);
        }
      case _Dest.skip:
      case _Dest.pict:
      case _Dest.shape:
        return;
    }
  }

  String? _labelFontName;

  DocFont _font() {
    final f = fonts[st.font];
    final name = f?.family.toLowerCase() ?? '';
    return DocFont(
      bold: st.b,
      italic: st.i,
      underline: st.ul,
      strike: st.strike,
      smallCaps: st.scaps && !st.caps,
      mono: (f?.fixed ?? false) || name.contains('courier') || name.contains('consolas') || name.contains('mono'),
      vert: st.vert,
      color: _color(st.cf),
      background: _color(st.hl) ?? _color(st.cb),
      size: st.fs > 0 ? (st.fs / 2).clamp(1, 400).toDouble() : null,
    );
  }

  int? _color(int index) => index > 0 && index < colors.length ? colors[index] : null;

  void _text(String s) {
    final k = sink;
    final f = _font();
    final name = fonts[st.font]?.family;
    if (k.buf.isNotEmpty && (k.font != f || k.href != st.href || k.fontName != name)) _flushRun();
    k.font = f;
    k.href = st.href;
    k.fontName = name;
    k.buf.write(st.caps ? s.toUpperCase() : s);
    if (s.trim().isNotEmpty) k.lastTab = false;
    if (k.buf.length > 4096) _flushRun();
  }

  void _flushRun() {
    final k = sink;
    if (k.buf.isEmpty) return;
    final raw = DocHtml.symbols(k.buf.toString(), k.fontName);
    k.buf.clear();
    final fit = budget.text(raw);
    if (fit.isEmpty) return;
    k.inlines.add(DocText(fit, k.font ?? DocFont.plain, k.href));
  }

  void _tab() {
    if (st.dest == _Dest.listtext) return; // табуляция после номера пункта
    if (st.dest != _Dest.text || st.hidden || sink.lastTab) return;
    _text('\u2003\u2003');
    sink.lastTab = true;
  }

  // ───────────────────────── управляющие слова ─────────────────────────

  static const _skipWords = {
    'info',
    'header',
    'headerl',
    'headerr',
    'headerf',
    'footer',
    'footerl',
    'footerr',
    'footerf',
    'ftnsep',
    'ftnsepc',
    'ftncn',
    'aftnsep',
    'aftnsepc',
    'aftncn',
    'annotation',
    'atnid',
    'atnauthor',
    'atndate',
    'atnref',
    'atnparent',
    'atnicn',
    'atntime',
    'comment',
    'xe',
    'tc',
    'tcn',
    'txe',
    'rxe',
    'bxe',
    'pn',
    'pntxta',
    'pntxtb',
    'nonshppict',
    'shprslt',
    'do',
    'falt',
    'panose',
    'fname',
    'template',
    'revtbl',
    'listtable',
    'listoverridetable',
    'rsidtbl',
    'objdata',
    'objclass',
    'objname',
    'objalias',
    'objsect',
    'fldtype',
    'datafield',
    'protusertbl',
    'userprops',
    'keycode',
    'sn',
    'mmathPr',
    'pgdsctbl',
    'xmlnstbl',
    'themedata',
    'colorschememapping',
    'datastore',
    'latentstyles',
    'generator',
    'fontemb',
    'fontfile',
    'bkmkstart',
    'bkmkend',
    'blipuid',
    'docvar',
    'formfield',
    'background',
    'pgdsc',
    'stylesheetlatent',
    'wgrffmtfilter',
  };

  void _word(String w, int? p) {
    final star = starred;
    starred = false;
    // В пропускаемой группе (колонтитул, примечание …) не действует ничего:
    // иначе результат поля номера страницы из колонтитула попал бы в текст.
    if (st.dest == _Dest.skip) return;
    switch (w) {
      // ── назначения групп ──
      case 'fonttbl':
        st.dest = _Dest.fonttbl;
        return;
      case 'colortbl':
        st.dest = _Dest.colortbl;
        colors.clear();
        return;
      case 'stylesheet':
        st.dest = _Dest.stylesheet;
        return;
      case 'listtext':
      case 'pntext':
        st.dest = _Dest.listtext;
        return;
      case 'field':
        st.field = _Field();
        return;
      case 'fldinst':
        st.dest = _Dest.fldinst;
        return;
      case 'fldrslt':
        if (st.dest != _Dest.text && st.dest != _Dest.shape && st.dest != _Dest.fldinst) return;
        st.dest = _Dest.text;
        final f = st.field;
        if (f != null) {
          final href = DocHtml.fieldLink(f.instr.toString());
          if (href != null) st.href = href;
        }
        return;
      case 'pict':
        _startPict();
        return;
      case 'shppict':
      case 'result':
      case 'shptxt':
      case 'ud':
        if (st.dest == _Dest.text || st.dest == _Dest.shape) st.dest = _Dest.text;
        return;
      case 'shp':
      case 'shpinst':
      case 'sp':
      case 'sv':
      case 'object':
      case 'upr':
        if (st.dest == _Dest.text || st.dest == _Dest.shape) st.dest = _Dest.shape;
        return;
      case 'footnote':
        _startNote();
        return;
    }
    if (_skipWords.contains(w) || (star && !_known(w))) {
      st.dest = _Dest.skip;
      return;
    }
    if (st.dest == _Dest.pict) {
      _pictWord(w, p);
      return;
    }
    if (st.dest == _Dest.fonttbl) {
      _fontWord(w, p);
      return;
    }
    if (st.dest == _Dest.colortbl) {
      final v = (p ?? 0).clamp(0, 255);
      switch (w) {
        case 'red':
          red = v;
          colorSet = true;
        case 'green':
          green = v;
          colorSet = true;
        case 'blue':
          blue = v;
          colorSet = true;
      }
      return;
    }
    if (st.dest == _Dest.stylesheet) {
      switch (w) {
        case 's':
          curStyle = p ?? 0;
          styleIsPara = true;
          styleDef = _StyleDef();
        case 'cs':
        case 'ds':
        case 'ts':
          styleIsPara = false;
        case 'sbasedon':
          styleDef.basedOn = p;
        case 'fs':
          styleDef.fs = p;
        case 'b':
          styleDef.b = p != 0;
        case 'i':
          styleDef.i = p != 0;
        case 'cf':
          styleDef.cf = p;
      }
      return;
    }

    switch (w) {
      // ── заголовок документа ──
      case 'ansicpg':
        ansiCpg = p;
      case 'deflang':
        defLang = p;
      case 'deff':
        deff = p ?? 0;
        st.font = deff;
      case 'paperw':
        paperW = p ?? paperW;
        _page();
      case 'margl':
        margL = p ?? margL;
        _page();
      case 'margr':
        margR = p ?? margR;
        _page();
      case 'uc':
        st.uc = (p ?? 1).clamp(0, 10);
      case 'u':
        var code = p ?? 0;
        if (code < 0) code += 65536;
        if (code > 0) _char(code);
        pendingSkip = st.uc;

      // ── знаки ──
      case 'par':
        _endPara();
      case 'sect':
        _endPara();
      case 'line':
        if (st.dest == _Dest.text && !st.hidden) {
          _flushRun();
          sink.inlines.add(const DocBreak());
          sink.lastTab = false;
        }
      case 'tab':
        _tab();
      case 'page':
        if (st.dest == _Dest.text) _pageBreak();
      case 'emdash':
        _char(0x2014);
      case 'endash':
        _char(0x2013);
      case 'emspace':
        _char(0x2003);
      case 'enspace':
        _char(0x2002);
      case 'qmspace':
        _char(0x2005);
      case 'bullet':
        _char(0x2022);
      case 'lquote':
        _char(0x2018);
      case 'rquote':
        _char(0x2019);
      case 'ldblquote':
        _char(0x201C);
      case 'rdblquote':
        _char(0x201D);
      case 'zwj':
        _char(0x200D);
      case 'zwnj':
        _char(0x200C);
      case 'chftn':
        _noteMark();

      // ── оформление текста ──
      case 'plain':
        st.plain(deff);
      case 'b':
        st.b = p != 0;
      case 'i':
        st.i = p != 0;
      case 'ul':
      case 'uld':
      case 'uldash':
      case 'uldashd':
      case 'uldashdd':
      case 'uldb':
      case 'ulhwave':
      case 'ulldash':
      case 'ulth':
      case 'ulthd':
      case 'ulthdash':
      case 'ulthdashd':
      case 'ulthdashdd':
      case 'ulthldash':
      case 'ululdbwave':
      case 'ulw':
      case 'ulwave':
        st.ul = p != 0;
      case 'ulnone':
        st.ul = false;
      case 'strike':
      case 'striked':
        st.strike = p != 0;
      case 'caps':
        st.caps = p != 0;
      case 'scaps':
        st.scaps = p != 0;
      case 'v':
      case 'deleted':
        st.hidden = p != 0;
      case 'super':
        st.vert = DocVert.sup;
      case 'sub':
        st.vert = DocVert.sub;
      case 'nosupersub':
        st.vert = DocVert.none;
      case 'up':
        st.vert = (p ?? 6) > 0 ? DocVert.sup : DocVert.none;
      case 'dn':
        st.vert = (p ?? 6) > 0 ? DocVert.sub : DocVert.none;
      case 'fs':
        st.fs = (p ?? 24).clamp(2, 800);
      case 'f':
        st.font = p ?? deff;
      case 'cf':
        st.cf = p ?? 0;
      case 'cb':
      case 'chcbpat':
        st.cb = p ?? 0;
      case 'highlight':
        st.hl = p ?? 0;

      // ── оформление абзаца ──
      case 'pard':
        st.para = _Para();
        side = _Side.none;
      case 's':
        _paraMut().style = p ?? 0;
        _styleChars(p ?? 0);
      case 'ql':
        _paraMut().align = 0;
      case 'qc':
        _paraMut().align = 1;
      case 'qr':
        _paraMut().align = 2;
      case 'qj':
      case 'qd':
        _paraMut().align = 3;
      case 'li':
      case 'lin':
        _paraMut().li = p ?? 0;
      case 'ri':
      case 'rin':
        _paraMut().ri = p ?? 0;
      case 'fi':
        _paraMut().fi = p ?? 0;
      case 'sb':
        _paraMut().sb = p ?? 0;
      case 'sa':
        _paraMut().sa = p ?? 0;
      case 'sbauto':
        _paraMut().sbAuto = p == 1;
      case 'saauto':
        _paraMut().saAuto = p == 1;
      case 'intbl':
        _paraMut().intbl = true;
      case 'outlinelevel':
        _paraMut().outline = p;
      case 'rtlpar':
        _paraMut().rtl = true;
      case 'ltrpar':
        _paraMut().rtl = false;
      case 'cbpat':
        _paraMut().shade = p;
      case 'pagebb':
        _paraMut().pageBefore = true;
      case 'contextualspace':
        _paraMut().contextual = true;

      // ── рамки ──
      case 'brdrt':
        _side(_Side.pTop);
      case 'brdrb':
        _side(_Side.pBottom);
      case 'brdrl':
        _side(_Side.pLeft);
      case 'brdrr':
        _side(_Side.pRight);
      case 'box':
        _side(_Side.pBox);
      case 'clbrdrt':
        _side(_Side.cTop);
      case 'clbrdrb':
        _side(_Side.cBottom);
      case 'clbrdrl':
        _side(_Side.cLeft);
      case 'clbrdrr':
        _side(_Side.cRight);
      case 'brdrs':
      case 'brdrth':
      case 'brdrsh':
      case 'brdrhair':
      case 'brdrdb':
      case 'brdrdot':
      case 'brdrdash':
      case 'brdrdashsm':
      case 'brdrdashd':
      case 'brdrdashdd':
      case 'brdrtriple':
      case 'brdrthtnsg':
      case 'brdrtnthsg':
      case 'brdrengrave':
      case 'brdremboss':
      case 'brdrwavy':
        line = DocLine(
          width: w == 'brdrth' ? 1.5 : line.width,
          style: switch (w) {
            'brdrdb' || 'brdrtriple' || 'brdrthtnsg' || 'brdrtnthsg' => 'double',
            'brdrdot' => 'dotted',
            'brdrdash' || 'brdrdashsm' || 'brdrdashd' || 'brdrdashdd' => 'dashed',
            _ => 'solid',
          },
          color: line.color,
        );
        _applyLine(line);
      case 'brdrnone':
      case 'brdrnil':
        _applyLine(null);
      case 'brdrw':
        line = DocLine(width: ((p ?? 10) / 20).clamp(0.25, 6).toDouble(), style: line.style, color: line.color);
        _applyLine(line, onlyIfSet: true);
      case 'brdrcf':
        line = DocLine(width: line.width, style: line.style, color: _color(p ?? 0));
        _applyLine(line, onlyIfSet: true);

      // ── таблицы ──
      case 'trowd':
        rowDefs = [];
        cellDef = _CellDef();
        rowLeft = 0;
        rowAlign = null;
        side = _Side.none;
      case 'trleft':
        rowLeft = p ?? 0;
      case 'trgaph':
        rowGaph = (p ?? 108).clamp(0, 1440);
      case 'trqc':
        rowAlign = 'center';
      case 'trqr':
        rowAlign = 'right';
      case 'trql':
        rowAlign = null;
      case 'clvmgf':
        cellDef.vFirst = true;
      case 'clvmrg':
        cellDef.vMerged = true;
      case 'clmgf':
        cellDef.hFirst = true;
      case 'clmrg':
        cellDef.hMerged = true;
      case 'clcbpat':
        cellDef.bg = _color(p ?? 0);
      case 'clvertalc':
        cellDef.valign = 1;
      case 'clvertalb':
        cellDef.valign = 2;
      case 'clvertalt':
        cellDef.valign = 0;
      case 'cellx':
        if (rowDefs.length < 64) {
          cellDef.right = (p ?? 0).clamp(-31680, 31680);
          rowDefs.add(cellDef);
        }
        cellDef = _CellDef();
        side = _Side.none;
      case 'cell':
        _endCell();
      case 'nestcell':
      case 'nestrow':
        // Вложенная таблица: её ячейки — абзацами в ячейке внешней.
        _endPara();
      case 'row':
        _endRow();
    }
  }

  /// Слова, которые бывают назначениями после \* и обрабатываются.
  static bool _known(String w) => const {
    'fldinst',
    'shppict',
    'footnote',
    'listtext',
    'pntext',
    'shpinst',
    'shptxt',
    'ud',
    'field',
    'fldrslt',
    'pict',
    'shp',
    'sp',
    'sv',
    'object',
    'result',
  }.contains(w);

  /// Свойства абзаца группы — своя копия (у вложенной группы — тоже своя,
  /// чтобы «}» вернул прежние).
  _Para _paraMut() {
    if (stack.isNotEmpty && identical(st.para, stack.last.para)) st.para = st.para.copy();
    return st.para;
  }

  /// Начало описания линии рамки стороны [s] (\brdrt, \clbrdrl …).
  void _side(_Side s) {
    side = s;
    line = const DocLine();
  }

  /// Линия для стороны [side]; [onlyIfSet] — толщина и цвет (\brdrw,
  /// \brdrcf) уточняют уже заданную линию, а «без линии» не превращают в
  /// линию.
  void _applyLine(DocLine? l, {bool onlyIfSet = false}) {
    if (onlyIfSet && _current == null) return;
    switch (side) {
      case _Side.none:
        return;
      case _Side.pTop:
        _paraMut().top = l;
      case _Side.pBottom:
        _paraMut().bottom = l;
      case _Side.pLeft:
        _paraMut().left = l;
      case _Side.pRight:
        _paraMut().right = l;
      case _Side.pBox:
        final pp = _paraMut();
        pp
          ..top = l
          ..bottom = l
          ..left = l
          ..right = l;
      case _Side.cTop:
        cellDef.top = l;
      case _Side.cBottom:
        cellDef.bottom = l;
      case _Side.cLeft:
        cellDef.left = l;
      case _Side.cRight:
        cellDef.right2 = l;
    }
  }

  DocLine? get _current => switch (side) {
    _Side.none => null,
    _Side.pTop || _Side.pBox => st.para.top,
    _Side.pBottom => st.para.bottom,
    _Side.pLeft => st.para.left,
    _Side.pRight => st.para.right,
    _Side.cTop => cellDef.top,
    _Side.cBottom => cellDef.bottom,
    _Side.cLeft => cellDef.left,
    _Side.cRight => cellDef.right2,
  };

  void _page() {
    final w = paperW - margL - margR;
    if (w > 1440) pageWidth = w.toDouble();
  }

  // ───────────────────────── таблица шрифтов и стилей ─────────────────────────

  void _fontWord(String w, int? p) {
    switch (w) {
      case 'f':
        final f = _Font();
        if (fonts.length < 4096) fonts[p ?? 0] = f;
        curFont = f;
      case 'fcharset':
        curFont?.charset = p ?? 1;
      case 'cpg':
        curFont?.cpg = p;
      case 'fprq':
        if (p == 1) curFont?.fixed = true;
      case 'fmodern':
        curFont?.fixed = true;
    }
  }

  void _endStyle() {
    final name = styleName.toString().trim().toLowerCase();
    styleName.clear();
    if (!styleIsPara) return;
    if (styleDefs.length < 4096) styleDefs[curStyle] = styleDef;
    final m = RegExp(r'^heading\s*(\d)$').firstMatch(name);
    if (m != null) {
      headings[curStyle] = int.parse(m.group(1)!).clamp(1, 6);
    } else if (name == 'title') {
      headings[curStyle] = 1;
    }
  }

  /// Оформление текста из стиля абзаца \sN (с цепочкой \sbasedon):
  /// LibreOffice не повторяет у абзаца то, что тот наследует от стиля
  /// («Абзац списка» — размер «Обычного»), а Word повторяет — явные слова
  /// после \s всё равно важнее.
  void _styleChars(int id) {
    if (st.dest != _Dest.text) return;
    final chain = <_StyleDef>[];
    int? cur = id;
    while (cur != null && chain.length < 16) {
      final d = styleDefs[cur];
      if (d == null || chain.contains(d)) break;
      chain.add(d);
      cur = d.basedOn == cur ? null : d.basedOn;
    }
    for (final d in chain.reversed) {
      if (d.fs != null) st.fs = d.fs!.clamp(2, 800);
      if (d.b != null) st.b = d.b!;
      if (d.i != null) st.i = d.i!;
      if (d.cf != null) st.cf = d.cf!;
    }
  }

  void _endGroup() {
    if (st.dest == _Dest.pict && (stack.isEmpty || stack.last.dest != _Dest.pict)) _endPict();
    if (st.dest == _Dest.stylesheet && styleName.isNotEmpty) styleName.clear();
  }

  // ───────────────────────── абзацы ─────────────────────────

  void _endPara({bool finalFlush = false}) {
    if (st.dest != _Dest.text && !finalFlush) return;
    _flushRun();
    final k = sink;
    final pp = st.para;
    final hasContent = k.inlines.isNotEmpty || k.label.isNotEmpty;
    if (finalFlush && !hasContent) return;
    if (!pp.intbl && (k.rows.isNotEmpty || k.cells.isNotEmpty || k.cellBlocks.isNotEmpty)) _flushTable();
    if (!budget.block()) return;
    final label = k.label.toString().replaceAll('\t', '').trim();
    final size = _sizeOf(k.inlines);
    final para = DocPara(
      _style(pp, size),
      List.of(k.inlines),
      label: label.isEmpty ? null : DocText(DocHtml.bullet(label, _labelFontName), _labelOnly(k.labelFont, size)),
    );
    k.inlines.clear();
    k.label.clear();
    k.labelFont = null;
    _labelFontName = null;
    k.lastTab = false;
    final target = pp.intbl ? k.cellBlocks : k.blocks;
    if (pp.pageBefore || k.pageBefore) target.add(const DocRule());
    k.pageBefore = false;
    // «Не добавлять интервал между абзацами одного стиля» (\contextualspace).
    final last = _last;
    var add = para;
    if (pp.contextual &&
        last != null &&
        last.style == pp.style &&
        target.isNotEmpty &&
        identical(target.last, last.para)) {
      target[target.length - 1] = DocPara(
        last.para.style.withSpacing(after: 0),
        last.para.inlines,
        label: last.para.label,
      );
      add = DocPara(para.style.withSpacing(before: 0), para.inlines, label: para.label);
    }
    target.add(add);
    _last = (para: add, style: pp.style);
  }

  ({DocPara para, int style})? _last;

  /// Оформление номера: жирность, курсив, цвет — его; размер — абзаца
  /// ({\listtext\pard\plain …} у LibreOffice сбрасывает размер к 12 pt).
  static DocFont _labelOnly(DocFont? f, double? size) =>
      f == null ? DocFont(size: size) : DocFont(bold: f.bold, italic: f.italic, color: f.color, size: size);

  /// Размер абзаца — каким набрано больше всего его текста (у пустого —
  /// текущий): заголовок получает размер тегом, фрагменты — только отличия.
  double? _sizeOf(List<DocInline> inlines) {
    final count = <double, int>{};
    for (final i in inlines) {
      if (i is DocText && i.font.size != null && i.font.vert == DocVert.none) {
        count[i.font.size!] = (count[i.font.size!] ?? 0) + i.text.length;
      }
    }
    if (count.isEmpty) return st.fs > 0 ? (st.fs / 2).clamp(1, 400).toDouble() : null;
    return count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  DocParaStyle _style(_Para p, double? size) {
    var heading = headings[p.style] ?? 0;
    if (heading == 0 && p.outline != null && p.outline! >= 0 && p.outline! < 6) heading = p.outline! + 1;
    final hasBorders = p.top != null || p.bottom != null || p.left != null || p.right != null;
    return DocParaStyle(
      heading: heading,
      align: const [null, 'center', 'right', 'justify'][p.align.clamp(0, 3)],
      before: p.sbAuto ? 14 : (p.sb / 20).clamp(0, 144).toDouble(),
      after: p.saAuto ? 14 : (p.sa / 20).clamp(0, 144).toDouble(),
      left: (p.li / 20).clamp(-144, 1440).toDouble(),
      right: (p.ri / 20).clamp(-144, 1440).toDouble(),
      firstLine: (p.fi / 20).clamp(-720, 720).toDouble(),
      background: p.shade == null ? null : _color(p.shade!),
      borders: hasBorders ? DocBorders(top: p.top, right: p.right, bottom: p.bottom, left: p.left) : DocBorders.none,
      rtl: p.rtl,
      size: size,
    );
  }

  void _pageBreak() {
    _flushRun();
    final k = sink;
    if (k.inlines.isNotEmpty || k.label.isNotEmpty) {
      _endPara();
      k.blocks.add(const DocRule());
    } else {
      k.pageBefore = true;
    }
  }

  // ───────────────────────── таблицы ─────────────────────────

  void _endCell() {
    if (st.dest != _Dest.text) return;
    _flushRun();
    final k = sink;
    // Последний абзац ячейки кончается \cell, а не \par.
    final save = st.para;
    if (!save.intbl) st.para = save.copy()..intbl = true;
    _endPara();
    st.para = save;
    if (!budget.block()) return;
    k.cells.add(k.cellBlocks);
    k.cellBlocks = [];
  }

  void _endRow() {
    final k = sink;
    _flushRun();
    k.inlines.clear();
    k.label.clear();
    if (k.cells.isEmpty) return;
    if (!budget.block()) return;
    k.rows.add(_Row(List.of(rowDefs), k.cells, rowLeft, rowAlign));
    k.cells = [];
    if (k.rows.length >= 20000) _flushTable();
  }

  void _flushTable() {
    final k = sink;
    if (k.cells.isNotEmpty || k.cellBlocks.isNotEmpty) {
      // Ячейки без \row (обрезанный файл) — последней строкой.
      if (k.cellBlocks.isNotEmpty) k.cells.add(k.cellBlocks);
      k.rows.add(_Row(List.of(rowDefs), k.cells, rowLeft, rowAlign));
      k.cells = [];
      k.cellBlocks = [];
    }
    if (k.rows.isEmpty) return;
    final rows = List.of(k.rows);
    k.rows.clear();
    k.blocks.add(_table(rows));
  }

  DocTable _table(List<_Row> rows) {
    // Сетка — все границы ячеек всех строк: ячейка, широкая в одной строке,
    // в другой занимает несколько колонок (так RTF пишет объединение).
    final edges = <int>{};
    for (final r in rows) {
      edges.add(r.left);
      for (final d in r.defs) {
        edges.add(d.right);
      }
    }
    final grid = edges.toList()..sort();
    final cols = <double>[for (var j = 1; j < grid.length; j++) (grid[j] - grid[j - 1]).toDouble()];
    final known = cols.isNotEmpty && cols.every((w) => w > 0);
    int colOf(int edge) {
      final i = grid.indexOf(edge);
      return i < 0 ? 0 : i;
    }

    final out = <List<_CellB>>[];
    final open = <int, _CellB>{};
    for (final r in rows) {
      final row = <_CellB>[];
      var leftEdge = r.left;
      for (var c = 0; c < r.cells.length; c++) {
        final def = c < r.defs.length ? r.defs[c] : (r.defs.isNotEmpty ? r.defs.last : _CellDef());
        final start = known ? colOf(leftEdge) : c;
        final end = known && c < r.defs.length ? colOf(def.right) : start + 1;
        final span = (end - start).clamp(1, 64);
        if (c < r.defs.length) leftEdge = def.right;
        if (def.hMerged && row.isNotEmpty) {
          row.last.colSpan += span;
          continue;
        }
        if (def.vMerged && open[start] != null) {
          open[start]!.rowSpan++;
          continue;
        }
        final b = _CellB(r.cells[c], def, span, rowGaph / 20);
        if (def.vFirst) {
          open[start] = b;
        } else {
          open.remove(start);
        }
        row.add(b);
      }
      out.add(row);
    }
    final first = rows.first;
    final total = known ? (grid.last - grid.first).toDouble() : 0.0;
    var pct = total > 0 ? total / pageWidth * 100 : null;
    if (pct != null && pct > 90) pct = 100;
    return DocTable(
      [
        for (final r in out) DocRow([for (final c in r) c.build()]),
      ],
      columns: known ? cols : const [],
      widthPct: pct,
      align: first.align,
    );
  }

  // ───────────────────────── сноски ─────────────────────────

  void _noteMark() {
    if (st.dest != _Dest.text) return;
    // В тексте — новый номер; в самой сноске (sinks > 1) — её номер.
    final n = sinks.length > 1 ? noteCount : ++noteCount;
    final saved = st.vert;
    st.vert = DocVert.sup;
    _text('$n');
    st.vert = saved;
  }

  void _startNote() {
    if (sinks.length > 4 || budget.full) {
      st.dest = _Dest.skip;
      return;
    }
    _flushRun();
    st.dest = _Dest.text;
    sinks.add(_Sink(stack.length));
  }

  void _closeNote() {
    final saved = st.para;
    st.para = _Para();
    _endPara(finalFlush: true);
    _flushTable();
    st.para = saved;
    final k = sinks.removeLast();
    notes.addAll(k.blocks);
  }

  // ───────────────────────── картинки ─────────────────────────

  void _startPict() {
    if (st.dest != _Dest.text && st.dest != _Dest.shape) {
      st.dest = _Dest.skip;
      return;
    }
    st.dest = _Dest.pict;
    pict = BytesBuilder(copy: false);
    pictType = '';
    picw = pich = goalW = goalH = 0;
    scaleX = scaleY = 100;
    pictTooBig = false;
    hexHalf = -1;
  }

  void _pictWord(String w, int? p) {
    switch (w) {
      case 'pngblip':
        pictType = 'png';
      case 'jpegblip':
        pictType = 'jpeg';
      case 'emfblip':
      case 'wmetafile':
      case 'macpict':
      case 'pmmetafile':
      case 'dibitmap':
      case 'wbitmap':
        pictType = 'other';
      case 'picw':
        picw = p ?? 0;
      case 'pich':
        pich = p ?? 0;
      case 'picwgoal':
        goalW = p ?? 0;
      case 'pichgoal':
        goalH = p ?? 0;
      case 'picscalex':
        scaleX = (p ?? 100).clamp(1, 1000);
      case 'picscaley':
        scaleY = (p ?? 100).clamp(1, 1000);
    }
  }

  void _pictHex(int c) {
    if (pictType == 'other' || pictTooBig) return;
    final v = c >= 0x30 && c <= 0x39
        ? c - 0x30
        : (c >= 0x61 && c <= 0x66 ? c - 0x57 : (c >= 0x41 && c <= 0x46 ? c - 0x37 : -1));
    if (v < 0) return;
    if (hexHalf < 0) {
      hexHalf = v;
      return;
    }
    pict?.addByte((hexHalf << 4) | v);
    hexHalf = -1;
    if ((pict?.length ?? 0) > OfficeLimits.maxImageBytes) pictTooBig = true;
  }

  void _pictBytes(Uint8List b) {
    if (pictType == 'other' || pictTooBig) return;
    if ((pict?.length ?? 0) + b.length > OfficeLimits.maxImageBytes) {
      pictTooBig = true;
      return;
    }
    pict?.add(Uint8List.fromList(b));
  }

  void _endPict() {
    final b = pict?.takeBytes();
    pict = null;
    if (b == null || b.isEmpty || pictTooBig || pictType == 'other') return;
    final mime = OfficeImage.sniff(b);
    if (mime == null || imagesTotal + b.length > OfficeLimits.maxImagesTotal) return;
    if (!budget.block()) return;
    imagesTotal += b.length;
    final key = 'img${images.length + 1}';
    images[key] = OfficeImage(mime, b).dataUri;
    // Размер: «желаемый» в twips (1/15 px), иначе в точках картинки.
    var w = goalW > 0 ? goalW / 15 : picw.toDouble();
    var h = goalH > 0 ? goalH / 15 : pich.toDouble();
    w = w * scaleX / 100;
    h = h * scaleY / 100;
    _flushRun();
    sink.inlines.add(
      DocPicture(
        key,
        width: w > 0 ? w.clamp(1, 4000).toDouble() : null,
        height: h > 0 ? h.clamp(1, 4000).toDouble() : null,
        href: st.href,
      ),
    );
  }
}

/// Ячейка таблицы RTF, пока строится сетка.
class _CellB {
  _CellB(this.blocks, this.def, this.colSpan, this.gap);
  final List<DocBlock> blocks;
  final _CellDef def;
  final double gap;
  int colSpan;
  int rowSpan = 1;

  DocCell build() => DocCell(
    blocks,
    colSpan: colSpan,
    rowSpan: rowSpan,
    background: def.bg,
    valign: def.valign,
    borders: DocBorders(top: def.top, right: def.right2, bottom: def.bottom, left: def.left),
    padding: [0, gap.clamp(0, 36).toDouble(), 0, gap.clamp(0, 36).toDouble()],
  );
}

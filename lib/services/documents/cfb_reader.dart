// lib/services/documents/cfb_reader.dart
// Составной файл OLE (Compound File Binary, MS-CFB) — контейнер старых
// документов Office 97–2003 (.doc, .xls, .ppt), писем Outlook (.msg) и
// документов OOXML с паролем (1.12.x, просьба владельца 04.11.2026: старые
// форматы Office в предпросмотре вложений).
//
// Устройство: файл поделён на секторы по 512 (версия 3) или 4096 байт
// (версия 4); таблица FAT — цепочки секторов («следующий сектор»), её
// секторы перечислены в DIFAT (109 номеров в заголовке, дальше — цепочкой
// секторов DIFAT). Каталог — тоже цепочка секторов: записи по 128 байт
// (имя, хранилище или поток, первый сектор, размер), братья в хранилище
// связаны красно-чёрным деревом — его не балансируем, просто обходим все
// записи. Потоки меньше 4096 байт лежат в «мини-потоке» (содержимое корня)
// секторами по 64 байта со своей таблицей mini FAT.
//
// Файл — из чужого письма, поэтому всё ограничено:
//  · файл — не больше [OfficeLimits.maxFileBytes];
//  · цепочки секторов — без петель (проверка каждого сектора) и не длиннее,
//    чем нужно для объявленного размера потока;
//  · записей каталога — не больше [CfbFile.maxEntries], глубина хранилищ —
//    [OfficeLimits.maxDepth];
//  · поток — не больше [OfficeLimits.maxPartBytes] (или своего предела),
//    всё прочитанное вместе — [OfficeLimits.maxTotalBytes]; объявленному
//    размеру не верим: память выделяется под него, только когда он в
//    пределах, а сам размер — не больше того, что умещается в файле.
// Испорченный файл — [OfficeDocError.damaged], больше пределов —
// [OfficeDocError.tooLarge]; других исключений чтение не бросает.
//
// Только чтение: файл не меняется, «грязные» секторы и время изменения не
// важны. По открытой спецификации Microsoft [MS-CFB] (Open Specification
// Promise), без сторонних библиотек.

import 'dart:math' as math;
import 'dart:typed_data';

import 'office_package.dart';

/// Запись каталога: хранилище (папка) или поток (файл).
class CfbEntry {
  CfbEntry._(this.id, this.name, this.type, this.start, this.size, this._left, this._right, this._child);

  final int id;
  final String name;

  /// 1 — хранилище, 2 — поток, 5 — корень.
  final int type;
  final int start;
  final int size;
  final int _left, _right, _child;

  /// Записи внутри хранилища (по порядку обхода дерева).
  final List<CfbEntry> children = [];

  bool get isStorage => type == 1 || type == 5;
  bool get isStream => type == 2;

  CfbEntry? child(String name) {
    final n = name.toLowerCase();
    for (final c in children) {
      if (c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  @override
  String toString() => 'CfbEntry($name, ${isStorage ? 'storage' : 'stream $size'})';
}

class CfbFile {
  CfbFile._(
    this._data,
    this._shift,
    this._sectorCount,
    this._fat,
    this._entries,
    this.root,
    this._miniFatStart,
    this._miniFatSectors,
  );

  /// Записей каталога больше — файл не разбирается: столько не бывает даже
  /// у письма Outlook с сотнями вложений (у каждого — десяток потоков).
  static const maxEntries = 65536;

  static const _endOfChain = 0xFFFFFFFE;
  static const _free = 0xFFFFFFFF;
  static const _maxRegSect = 0xFFFFFFFA;
  static const _noStream = 0xFFFFFFFF;
  static const _miniCutoff = 4096;
  static const _miniShift = 6;

  final Uint8List _data;
  final int _shift;
  final int _sectorCount;
  final Uint32List _fat;
  final List<CfbEntry> _entries;
  final CfbEntry root;
  final int _miniFatStart;
  final int _miniFatSectors;

  Uint32List? _miniFat;
  List<int>? _miniChain;
  int _readTotal = 0;

  int get _sectorSize => 1 << _shift;

  /// Все записи каталога (для отладки и тестов).
  List<CfbEntry> get entries => List.unmodifiable(_entries);

  /// Открыть файл: заголовок, DIFAT, FAT, каталог.
  static CfbFile open(Uint8List data) {
    if (data.length > OfficeLimits.maxFileBytes) throw const OfficeDocException(OfficeDocError.tooLarge, 'file');
    if (data.length < 512 || !OfficeZip.isOle(data)) {
      throw const OfficeDocException(OfficeDocError.damaged, 'not a compound file');
    }
    final bd = ByteData.sublistView(data);
    int u16(int at) => bd.getUint16(at, Endian.little);
    int u32(int at) => bd.getUint32(at, Endian.little);
    if (u16(0x1C) != 0xFFFE) throw const OfficeDocException(OfficeDocError.damaged, 'byte order');
    final shift = u16(0x1E);
    if (shift != 9 && shift != 12) throw OfficeDocException(OfficeDocError.damaged, 'sector shift $shift');
    if (u16(0x20) != _miniShift) throw const OfficeDocException(OfficeDocError.damaged, 'mini sector shift');
    final size = 1 << shift;
    if (data.length < size + 128) throw const OfficeDocException(OfficeDocError.damaged, 'short');
    // Последний сектор бывает обрезан (файл сохранён программой не до
    // конца) — он считается, недостающие байты — нули.
    final sectorCount = (data.length - size + size - 1) >> shift;
    final numFat = u32(0x2C);
    final firstDir = u32(0x30);
    final firstMiniFat = u32(0x3C);
    final numMiniFat = u32(0x40);
    final firstDifat = u32(0x44);
    final numDifat = u32(0x48);
    if (numFat == 0 || numFat > sectorCount) throw const OfficeDocException(OfficeDocError.damaged, 'fat count');

    // DIFAT: номера секторов FAT — в заголовке и цепочкой секторов DIFAT.
    final fatSectors = <int>[];
    for (var i = 0; i < 109 && fatSectors.length < numFat; i++) {
      final s = u32(0x4C + i * 4);
      if (s == _free || s == _endOfChain) break;
      fatSectors.add(s);
    }
    if (fatSectors.length < numFat) {
      final per = size ~/ 4 - 1;
      final seen = <int>{};
      var s = firstDifat;
      var n = 0;
      while (fatSectors.length < numFat && s != _endOfChain && s != _free) {
        if (s >= sectorCount || !seen.add(s) || n++ > numDifat + 1) {
          throw const OfficeDocException(OfficeDocError.damaged, 'difat chain');
        }
        final base = (s + 1) << shift;
        for (var i = 0; i < per && fatSectors.length < numFat; i++) {
          final at = base + i * 4;
          if (at + 4 > data.length) break;
          final f = u32(at);
          if (f == _free || f == _endOfChain) continue;
          fatSectors.add(f);
        }
        final next = base + per * 4;
        s = next + 4 <= data.length ? u32(next) : _endOfChain;
      }
    }
    if (fatSectors.isEmpty) throw const OfficeDocException(OfficeDocError.damaged, 'no fat');

    // FAT — только записи о секторах, которые есть в файле: объявленное
    // число секторов FAT бывает и в тысячи раз больше настоящего.
    final per = size ~/ 4;
    final fat = Uint32List(math.min(fatSectors.length * per, sectorCount));
    for (var k = 0; k < fatSectors.length; k++) {
      final s = fatSectors[k];
      if (s >= sectorCount) throw const OfficeDocException(OfficeDocError.damaged, 'fat sector');
      final base = (s + 1) << shift;
      for (var i = 0; i < per; i++) {
        final idx = k * per + i;
        if (idx >= fat.length) break;
        final at = base + i * 4;
        fat[idx] = at + 4 <= data.length ? u32(at) : _free;
      }
    }

    // Каталог.
    final perDir = size ~/ 128;
    final maxDirSectors = maxEntries ~/ perDir + 1;
    final dirChain = _chainOf(fat, sectorCount, firstDir, maxDirSectors + 1);
    if (dirChain.isEmpty) throw const OfficeDocException(OfficeDocError.damaged, 'no directory');
    if (dirChain.length > maxDirSectors) throw const OfficeDocException(OfficeDocError.tooLarge, 'directory');
    final entries = <CfbEntry>[];
    final raw = <CfbEntry?>[];
    final v3 = shift == 9;
    for (final s in dirChain) {
      final base = (s + 1) << shift;
      for (var i = 0; i < perDir; i++) {
        final at = base + i * 128;
        if (at + 128 > data.length) {
          raw.add(null);
          continue;
        }
        final type = data[at + 0x42];
        if (type != 1 && type != 2 && type != 5) {
          raw.add(null);
          continue;
        }
        final nameLen = u16(at + 0x40);
        final units = <int>[];
        for (var j = 0; j + 1 < math.min(nameLen, 64); j += 2) {
          final c = u16(at + j);
          if (c == 0) break;
          units.add(c);
        }
        final lo = u32(at + 0x78);
        final hi = u32(at + 0x7C);
        // У версии 3 старшая половина размера — мусор (так пишут старые
        // программы), у версии 4 размер больше файла — значит, испорчен.
        final sz = v3 ? lo : (hi == 0 ? lo : 0x7FFFFFFFFFFF);
        final e = CfbEntry._(
          raw.length,
          String.fromCharCodes(units),
          type,
          u32(at + 0x74),
          sz,
          u32(at + 0x44),
          u32(at + 0x48),
          u32(at + 0x4C),
        );
        raw.add(e);
        entries.add(e);
      }
    }
    final root = raw.isEmpty ? null : raw[0];
    if (root == null || root.type != 5) throw const OfficeDocException(OfficeDocError.damaged, 'no root entry');

    // Дерево: дети хранилища — все узлы дерева братьев под его child.
    // Запись принадлежит только одному хранилищу: петли и общие узлы
    // («дерево», испорченное нарочно) обходятся один раз.
    final placed = <int>{0};
    final storages = <(CfbEntry, int)>[(root, 0)];
    while (storages.isNotEmpty) {
      final (st, depth) = storages.removeLast();
      if (depth > OfficeLimits.maxDepth) continue;
      final stack = <int>[st._child];
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        if (id == _noStream || id >= raw.length) continue;
        final e = raw[id];
        if (e == null || e.type == 5 || !placed.add(id)) continue;
        st.children.add(e);
        stack
          ..add(e._right)
          ..add(e._left);
        if (e.isStorage) storages.add((e, depth + 1));
      }
    }
    return CfbFile._(data, shift, sectorCount, fat, entries, root, firstMiniFat, numMiniFat);
  }

  /// Цепочка секторов от [start] по таблице [table]: не длиннее [max], без
  /// повторов. Испорченная (сектор вне файла, петля) — [OfficeDocError.damaged].
  static List<int> _chainOf(Uint32List table, int count, int start, int max) {
    final out = <int>[];
    if (start == _endOfChain || start == _free) return out;
    // Короткие цепочки (почти все потоки письма) — множеством, длинные —
    // битовой картой: проверка петли не должна стоить памяти на каждый поток.
    final Set<int>? small = max <= 64 ? <int>{} : null;
    final Uint8List? bits = small == null ? Uint8List((count + 7) >> 3) : null;
    var s = start;
    while (out.length < max) {
      if (s > _maxRegSect || s >= count) throw OfficeDocException(OfficeDocError.damaged, 'chain $s');
      if (small != null) {
        if (!small.add(s)) throw const OfficeDocException(OfficeDocError.damaged, 'chain loop');
      } else {
        final m = 1 << (s & 7);
        if (bits![s >> 3] & m != 0) throw const OfficeDocException(OfficeDocError.damaged, 'chain loop');
        bits[s >> 3] |= m;
      }
      out.add(s);
      if (s >= table.length) break;
      final next = table[s];
      if (next == _endOfChain) break;
      s = next;
    }
    return out;
  }

  /// Запись по пути «хранилище/поток» (без учёта регистра); null — нет.
  CfbEntry? entry(String path) {
    var e = root;
    for (final part in path.split('/')) {
      if (part.isEmpty) continue;
      final c = e.child(part);
      if (c == null) return null;
      e = c;
    }
    return e;
  }

  /// Поток [path] есть.
  bool hasStream(String path) => entry(path)?.isStream ?? false;

  /// Поток [path] целиком; null — нет такого. Больше [max]
  /// (по умолчанию [OfficeLimits.maxPartBytes]) — [OfficeDocError.tooLarge].
  Uint8List? read(String path, {int? max}) {
    final e = entry(path);
    if (e == null || !e.isStream) return null;
    return readEntry(e, max: max);
  }

  /// Начало потока [path] — не больше [max] байт; [truncated] — поток длиннее.
  ({Uint8List bytes, bool truncated})? readHead(String path, int max) {
    final e = entry(path);
    if (e == null || !e.isStream) return null;
    final cap = math.min(max, OfficeLimits.maxPartBytes);
    final n = math.min(e.size, cap);
    return (bytes: _read(e, n), truncated: e.size > n);
  }

  Uint8List readEntry(CfbEntry e, {int? max}) {
    if (!e.isStream) throw OfficeDocException(OfficeDocError.damaged, 'not a stream ${e.name}');
    if (e.size > (max ?? OfficeLimits.maxPartBytes)) throw OfficeDocException(OfficeDocError.tooLarge, e.name);
    return _read(e, e.size);
  }

  /// Первые [n] байт потока [e].
  Uint8List _read(CfbEntry e, int n) {
    if (n <= 0) return Uint8List(0);
    // Больше, чем вообще есть в файле, поток быть не может — до выделения памяти.
    if (n > _data.length) throw OfficeDocException(OfficeDocError.damaged, 'size ${e.name}');
    if (_readTotal + n > OfficeLimits.maxTotalBytes) throw const OfficeDocException(OfficeDocError.tooLarge, 'total');
    _readTotal += n;
    final out = Uint8List(n);
    if (e.size < _miniCutoff) {
      _readMini(e.start, n, out, e.name);
    } else {
      final size = _sectorSize;
      final chain = _chainOf(_fat, _sectorCount, e.start, (n + size - 1) >> _shift);
      if (chain.length * size < n) throw OfficeDocException(OfficeDocError.damaged, 'short chain ${e.name}');
      var pos = 0;
      for (final s in chain) {
        pos += _copySector(s, out, pos, math.min(size, n - pos));
      }
    }
    return out;
  }

  /// Сектор [s] в [out] с [at], [len] байт; недостающее в конце файла — нули.
  int _copySector(int s, Uint8List out, int at, int len) {
    final from = (s + 1) << _shift;
    final avail = math.max(0, math.min(len, _data.length - from));
    if (avail > 0) out.setRange(at, at + avail, _data, from);
    return len;
  }

  void _readMini(int start, int n, Uint8List out, String name) {
    final miniFat = _miniFat ??= _loadMiniFat();
    final chainRoot = _miniChain ??= _rootChain();
    final miniSize = root.size;
    final count = math.min(miniFat.length, miniSize >> _miniShift);
    final chain = _chainOf(miniFat, count, start, (n + 63) >> _miniShift);
    if (chain.length * 64 < n) throw OfficeDocException(OfficeDocError.damaged, 'short mini chain $name');
    var pos = 0;
    for (final m in chain) {
      final off = m << _miniShift;
      final k = off >> _shift;
      if (k >= chainRoot.length) throw OfficeDocException(OfficeDocError.damaged, 'mini sector $name');
      final from = ((chainRoot[k] + 1) << _shift) + (off & (_sectorSize - 1));
      final len = math.min(64, n - pos);
      final avail = math.max(0, math.min(len, _data.length - from));
      if (avail > 0) out.setRange(pos, pos + avail, _data, from);
      pos += len;
    }
  }

  Uint32List _loadMiniFat() {
    if (_miniFatSectors == 0 || _miniFatStart == _endOfChain) return Uint32List(0);
    final chain = _chainOf(_fat, _sectorCount, _miniFatStart, math.min(_miniFatSectors, _sectorCount));
    final per = _sectorSize ~/ 4;
    // Записей не больше, чем мини-секторов в мини-потоке.
    final need = math.min(chain.length * per, (root.size >> _miniShift) + 1);
    final out = Uint32List(need);
    final bd = ByteData.sublistView(_data);
    for (var i = 0; i < need; i++) {
      final at = ((chain[i ~/ per] + 1) << _shift) + (i % per) * 4;
      out[i] = at + 4 <= _data.length ? bd.getUint32(at, Endian.little) : _free;
    }
    return out;
  }

  List<int> _rootChain() {
    if (root.size > _data.length) throw const OfficeDocException(OfficeDocError.damaged, 'mini stream size');
    final need = (root.size + _sectorSize - 1) >> _shift;
    final chain = _chainOf(_fat, _sectorCount, root.start, need);
    if (chain.length < need) throw const OfficeDocException(OfficeDocError.damaged, 'mini stream chain');
    return chain;
  }
}

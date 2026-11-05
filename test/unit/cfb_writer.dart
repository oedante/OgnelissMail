// Составной файл OLE (MS-CFB) для тестов (1.12.x, старые форматы Office и
// письма Outlook в предпросмотре): потоки по путям «хранилище/поток» →
// байты файла версии 3 (секторы 512 байт) или 4 (4096). Малые потоки
// (< 4096 байт) — в мини-потоке, как у Office. После [build] известны
// смещения FAT, каталога и первые секторы потоков — тесты портят по ним
// файл нарочно (петли в цепочках, испорченный каталог).

import 'dart:typed_data';

class CfbWriter {
  CfbWriter({this.v4 = false});

  final bool v4;
  final Map<String, Uint8List> _streams = {};

  /// Смещение в файле первого сектора FAT и каталога (после [build]).
  int fatAt = 0;
  int dirAt = 0;

  /// Номера записей каталога по пути (после [build]); корень — 0.
  final Map<String, int> ids = {};

  /// Первый сектор (обычный или мини) каждого потока (после [build]).
  final Map<String, int> starts = {};

  void add(String path, List<int> data) => _streams[path] = Uint8List.fromList(data);

  static const _end = 0xFFFFFFFE;
  static const _free = 0xFFFFFFFF;
  static const _fatSect = 0xFFFFFFFD;
  static const _none = 0xFFFFFFFF;

  Uint8List build() {
    final shift = v4 ? 12 : 9;
    final size = 1 << shift;
    // Дерево: корень, хранилища по префиксам путей, потоки.
    final root = _Node('Root Entry', 5, '');
    final byPath = <String, _Node>{'': root};
    for (final path in _streams.keys) {
      final parts = path.split('/');
      var parent = root;
      for (var i = 0; i < parts.length; i++) {
        final p = parts.sublist(0, i + 1).join('/');
        final last = i == parts.length - 1;
        var n = byPath[p];
        if (n == null) {
          n = _Node(parts[i], last ? 2 : 1, p);
          byPath[p] = n;
          parent.kids.add(n);
        }
        parent = n;
      }
    }
    final order = <_Node>[];
    final queue = [root];
    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      n.id = order.length;
      order.add(n);
      queue.addAll(n.kids);
    }
    for (final n in order) {
      ids[n.path] = n.id;
    }

    // Мини-поток.
    final mini = BytesBuilder();
    final miniFat = <int>[];
    for (final n in order.where((n) => n.type == 2)) {
      final data = _streams[n.path]!;
      n.size = data.length;
      if (data.length >= 4096) continue;
      if (data.isEmpty) {
        n.start = _end;
        continue;
      }
      n.start = mini.length >> 6;
      final count = (data.length + 63) >> 6;
      for (var i = 0; i < count; i++) {
        miniFat.add(i == count - 1 ? _end : n.start + i + 1);
      }
      mini.add(data);
      mini.add(Uint8List((count << 6) - data.length));
    }
    final miniBytes = mini.toBytes();

    // Обычные секторы: большие потоки, мини-поток, mini FAT, каталог, FAT.
    final sectors = <Uint8List>[];
    final fat = <int>[];
    int put(Uint8List data) {
      if (data.isEmpty) return _end;
      final start = sectors.length;
      final count = (data.length + size - 1) >> shift;
      for (var i = 0; i < count; i++) {
        final s = Uint8List(size);
        final from = i * size;
        s.setRange(0, (data.length - from).clamp(0, size), data, from);
        sectors.add(s);
        fat.add(i == count - 1 ? _end : start + i + 1);
      }
      return start;
    }

    for (final n in order.where((n) => n.type == 2 && n.size >= 4096)) {
      n.start = put(_streams[n.path]!);
    }
    root.start = put(miniBytes);
    root.size = miniBytes.length;
    final miniFatBytes = ByteData(miniFat.length * 4);
    for (var i = 0; i < miniFat.length; i++) {
      miniFatBytes.setUint32(i * 4, miniFat[i], Endian.little);
    }
    final miniFatStart = put(miniFatBytes.buffer.asUint8List());
    final miniFatCount = (miniFat.length * 4 + size - 1) >> shift;

    // Братья — сбалансированным деревом по порядку CFB (длина, затем имя
    // заглавными).
    for (final n in order) {
      final kids = [...n.kids]
        ..sort((a, b) {
          final d = a.name.length - b.name.length;
          return d != 0 ? d : a.name.toUpperCase().compareTo(b.name.toUpperCase());
        });
      n.child = _tree(kids);
    }
    final dir = ByteData(((order.length * 128 + size - 1) >> shift) << shift);
    for (final n in order) {
      final at = n.id * 128;
      final units = n.name.codeUnits.take(31).toList();
      for (var i = 0; i < units.length; i++) {
        dir.setUint16(at + i * 2, units[i], Endian.little);
      }
      dir.setUint16(at + 0x40, (units.length + 1) * 2, Endian.little);
      dir.setUint8(at + 0x42, n.type);
      dir.setUint8(at + 0x43, 1);
      dir.setUint32(at + 0x44, n.left?.id ?? _none, Endian.little);
      dir.setUint32(at + 0x48, n.right?.id ?? _none, Endian.little);
      dir.setUint32(at + 0x4C, n.child?.id ?? _none, Endian.little);
      dir.setUint32(at + 0x74, n.type == 1 ? 0 : n.start, Endian.little);
      dir.setUint32(at + 0x78, n.type == 1 ? 0 : n.size, Endian.little);
    }
    for (var i = order.length; i < dir.lengthInBytes ~/ 128; i++) {
      dir.setUint32(i * 128 + 0x44, _none, Endian.little);
      dir.setUint32(i * 128 + 0x48, _none, Endian.little);
      dir.setUint32(i * 128 + 0x4C, _none, Endian.little);
    }
    final dirStart = put(dir.buffer.asUint8List());
    final dirCount = dir.lengthInBytes >> shift;

    final per = size ~/ 4;
    var fatCount = 1;
    while ((sectors.length + fatCount) > fatCount * per) {
      fatCount++;
    }
    if (fatCount > 109) throw StateError('test file too large for header DIFAT');
    final fatStart = sectors.length;
    for (var i = 0; i < fatCount; i++) {
      sectors.add(Uint8List(size));
      fat.add(_fatSect);
    }
    final fatBytes = ByteData(fatCount * size);
    for (var i = 0; i < fatCount * per; i++) {
      fatBytes.setUint32(i * 4, i < fat.length ? fat[i] : _free, Endian.little);
    }
    for (var i = 0; i < fatCount; i++) {
      sectors[fatStart + i].setRange(0, size, fatBytes.buffer.asUint8List(), i * size);
    }

    final h = ByteData(size);
    const sig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    for (var i = 0; i < 8; i++) {
      h.setUint8(i, sig[i]);
    }
    h.setUint16(0x18, 0x3E, Endian.little);
    h.setUint16(0x1A, v4 ? 4 : 3, Endian.little);
    h.setUint16(0x1C, 0xFFFE, Endian.little);
    h.setUint16(0x1E, shift, Endian.little);
    h.setUint16(0x20, 6, Endian.little);
    h.setUint32(0x28, v4 ? dirCount : 0, Endian.little);
    h.setUint32(0x2C, fatCount, Endian.little);
    h.setUint32(0x30, dirStart, Endian.little);
    h.setUint32(0x38, 4096, Endian.little);
    h.setUint32(0x3C, miniFat.isEmpty ? _end : miniFatStart, Endian.little);
    h.setUint32(0x40, miniFat.isEmpty ? 0 : miniFatCount, Endian.little);
    h.setUint32(0x44, _end, Endian.little);
    h.setUint32(0x48, 0, Endian.little);
    for (var i = 0; i < 109; i++) {
      h.setUint32(0x4C + i * 4, i < fatCount ? fatStart + i : _free, Endian.little);
    }
    fatAt = (fatStart + 1) << shift;
    dirAt = (dirStart + 1) << shift;
    for (final n in order.where((n) => n.type == 2)) {
      starts[n.path] = n.start;
    }
    final out = BytesBuilder(copy: false)..add(h.buffer.asUint8List());
    for (final s in sectors) {
      out.add(s);
    }
    return out.toBytes();
  }

  static _Node? _tree(List<_Node> list) {
    if (list.isEmpty) return null;
    final mid = list.length ~/ 2;
    final n = list[mid];
    n.left = _tree(list.sublist(0, mid));
    n.right = _tree(list.sublist(mid + 1));
    return n;
  }
}

class _Node {
  _Node(this.name, this.type, this.path);

  final String name;
  final int type;
  final String path;
  final List<_Node> kids = [];
  int id = 0;
  int start = 0xFFFFFFFE;
  int size = 0;
  _Node? left, right, child;
}

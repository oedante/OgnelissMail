// lib/services/archive/archive_container.dart
// Файл архива Ogneliss (.ogna) для переноса: копия на флешку, в «Файлы», на
// Google Диск, iCloud Drive, Яндекс Диск — и подключение на другом
// устройстве или после переустановки (docs/plan/ARCHIVE_IDEA.md).
//
// Устройство файла (все числа — big-endian):
//   «OGNA» (4 байта) · версия формата (1 байт) · 3 нулевых байта ·
//   длина заголовка (uint32) · заголовок (JSON, UTF-8) · база архива
//   (SQLite3 Multiple Ciphers, зашифрована ключом архива).
// Заголовок открыт: в нём название, дата создания и ключ архива в двух
// конвертах — паролем и кодом восстановления (archive_crypto.dart). Без
// пароля или кода база не читается.
//
// На устройстве заголовок и база лежат двумя файлами (SQLite нужен файл
// базы как есть); файл .ogna собирается при сохранении копии и разбирается
// при подключении — потоком, без чтения гигабайтов в память.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Заголовок архива: открытая часть файла .ogna.
class ArchiveHeader {
  static const formatVersion = 1;

  final String id;
  final String name;
  final DateTime created;

  /// Версия приложения, создавшего архив.
  final String app;

  /// Ключ архива паролем (`password`) и кодом восстановления (`code`).
  final Map<String, Map<String, dynamic>> keys;

  const ArchiveHeader({
    required this.id,
    required this.name,
    required this.created,
    required this.app,
    required this.keys,
  });

  ArchiveHeader copyWith({String? name, Map<String, Map<String, dynamic>>? keys}) => ArchiveHeader(
        id: id,
        name: name ?? this.name,
        created: created,
        app: app,
        keys: keys ?? this.keys,
      );

  Map<String, dynamic> toJson() => {
        'format': 'ogna',
        'version': formatVersion,
        'id': id,
        'name': name,
        'created': created.millisecondsSinceEpoch,
        'app': app,
        'cipher': 'sqlite3mc',
        'keys': keys,
      };

  /// null — не заголовок архива Ogneliss.
  static ArchiveHeader? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['format'] != 'ogna') return null;
    final id = json['id'];
    final keys = json['keys'];
    if (id is! String || id.isEmpty || keys is! Map) return null;
    return ArchiveHeader(
      id: id,
      name: (json['name'] as String?) ?? '',
      created: DateTime.fromMillisecondsSinceEpoch((json['created'] as num?)?.toInt() ?? 0),
      app: (json['app'] as String?) ?? '',
      keys: {
        for (final e in keys.entries)
          if (e.key is String && e.value is Map) e.key as String: Map<String, dynamic>.from(e.value as Map),
      },
    );
  }

  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  static ArchiveHeader? decode(String text) {
    try {
      return fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }
}

class ArchiveFormatException implements Exception {
  /// Ключ строки для показа: archiveNotOgna, archiveNewerFormat, archiveBroken.
  final String key;
  const ArchiveFormatException(this.key);
  @override
  String toString() => 'ArchiveFormatException($key)';
}

abstract final class ArchiveContainer {
  static const magic = [0x4F, 0x47, 0x4E, 0x41]; // «OGNA»

  /// Начало файла .ogna: подпись, версия и заголовок.
  static Uint8List prefix(ArchiveHeader header) {
    final h = utf8.encode(header.encode());
    final out = BytesBuilder(copy: false)
      ..add(magic)
      ..add([ArchiveHeader.formatVersion, 0, 0, 0])
      ..add([(h.length >> 24) & 0xFF, (h.length >> 16) & 0xFF, (h.length >> 8) & 0xFF, h.length & 0xFF])
      ..add(h);
    return out.toBytes();
  }

  /// Разобрать начало файла: заголовок и смещение базы. Нужны первые
  /// 12 байт и сам заголовок — [head] может быть длиннее.
  static ({ArchiveHeader header, int dataOffset}) parsePrefix(Uint8List head) {
    if (head.length < 12) throw const ArchiveFormatException('archiveNotOgna');
    for (var i = 0; i < 4; i++) {
      if (head[i] != magic[i]) throw const ArchiveFormatException('archiveNotOgna');
    }
    if (head[4] > ArchiveHeader.formatVersion) throw const ArchiveFormatException('archiveNewerFormat');
    final len = (head[8] << 24) | (head[9] << 16) | (head[10] << 8) | head[11];
    if (len <= 0 || len > 1024 * 1024) throw const ArchiveFormatException('archiveBroken');
    if (head.length < 12 + len) throw const ArchiveFormatException('archiveBroken');
    final header = ArchiveHeader.decode(utf8.decode(head.sublist(12, 12 + len), allowMalformed: true));
    if (header == null) throw const ArchiveFormatException('archiveBroken');
    return (header: header, dataOffset: 12 + len);
  }

  /// Собрать файл .ogna [out] из заголовка и базы [db] (потоком).
  static Future<void> write(File out, ArchiveHeader header, File db) async {
    final sink = out.openWrite();
    try {
      sink.add(prefix(header));
      await sink.addStream(db.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Заголовок файла .ogna (база не читается).
  static Future<({ArchiveHeader header, int dataOffset})> readHeader(File file) async {
    final raf = await file.open();
    try {
      final first = await raf.read(12);
      if (first.length < 12) throw const ArchiveFormatException('archiveNotOgna');
      final len = (first[8] << 24) | (first[9] << 16) | (first[10] << 8) | first[11];
      if (len <= 0 || len > 1024 * 1024) {
        // Подпись проверит parsePrefix — сообщение точнее.
        return parsePrefix(first);
      }
      final rest = await raf.read(len);
      return parsePrefix(Uint8List.fromList([...first, ...rest]));
    } finally {
      await raf.close();
    }
  }

  /// Базу из файла .ogna — в файл [db] (потоком).
  static Future<void> extractDb(File file, int dataOffset, File db) async {
    final sink = db.openWrite();
    try {
      await sink.addStream(file.openRead(dataOffset));
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}

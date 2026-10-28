// lib/core/platform/file_pick.dart
// Выбор и сохранение файлов — единственное место, где приложение обращается
// к file_picker (1.7.2: file_picker 13, просьба владельца 23.10.2026 поднять
// плагины, которые сами подключают Kotlin Gradle Plugin).
//
// С 12-й версии file_picker устроен иначе: FilePickerResult нет, методы
// статические, PlatformFile — абстрактный (создать свой нельзя), байты —
// через readAsBytes(), размер — lengthSync()/length(), saveFile пишет файл сам
// и возвращает Uri. Экраны работают с [ChosenFile] и [FilePick] и про версию
// плагина не знают; при следующем обновлении file_picker меняется только
// этот файл.
//
// Байты не читаются заранее: сначала имя и размер (вложение больше лимита
// сервера или картинка больше 3 МБ отбрасываются без чтения), потом —
// [ChosenFile.readBytes] по необходимости.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

export 'package:file_picker/file_picker.dart' show FileType;

/// Файл, выбранный человеком или собранный приложением (вложение письма):
/// имя, размер, путь на устройстве (если есть) и байты (если файл в памяти).
class ChosenFile {
  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;

  /// Выбор file_picker, если ни пути, ни байтов нет (Android отдаёт часть
  /// файлов только как content://, без пути).
  final PlatformFile? _source;

  const ChosenFile({required this.name, required this.size, this.path, this.bytes}) : _source = null;

  const ChosenFile._picked(this.name, this.size, this.path, this._source) : bytes = null;

  /// Байты файла: из памяти, по пути или у системного выбора файлов.
  Future<Uint8List> readBytes() async {
    final b = bytes;
    if (b != null) return b;
    final pth = path;
    if (pth != null) return File(pth).readAsBytes();
    final s = _source;
    if (s != null) return s.readAsBytes();
    throw StateError('нет данных файла «$name»');
  }

  /// Для списка вложений: файл без пути — сразу в память (выбор системы
  /// живёт недолго), с путём — как есть.
  Future<ChosenFile> keepable() async {
    if (path != null || bytes != null) return this;
    final b = await readBytes();
    return ChosenFile(name: name, size: b.length, bytes: b);
  }
}

/// Куда сохранён файл: [shown] — для показа человеку (путь или имя), [path] —
/// путь на устройстве, где он есть (компьютер); на Android — null (документ
/// в выбранной папке, доступ через систему).
typedef SavedFile = ({String shown, String? path});

class FilePick {
  FilePick._();

  /// Несколько файлов. Пустой список — человек передумал.
  static Future<List<ChosenFile>> files({FileType type = FileType.any, List<String>? allowedExtensions}) async {
    final picked = await FilePicker.pickFiles(type: type, allowedExtensions: allowedExtensions);
    return [for (final f in picked) await _chosen(f)];
  }

  /// Один файл. null — человек передумал.
  static Future<ChosenFile?> file({FileType type = FileType.any, List<String>? allowedExtensions}) async {
    final f = await FilePicker.pickFile(type: type, allowedExtensions: allowedExtensions);
    return f == null ? null : _chosen(f);
  }

  static Future<ChosenFile> _chosen(PlatformFile f) async {
    String? path = kIsWeb ? null : f.path;
    if (path != null) {
      try {
        if (!File(path).existsSync()) path = null;
      } catch (_) {
        path = null;
      }
    }
    var size = f.lengthSync();
    size ??= await f.length();
    if (size == null && path != null) {
      try {
        size = await File(path).length();
      } catch (_) {}
    }
    return ChosenFile._picked(f.name, size ?? 0, path, f);
  }

  /// Системный диалог «Сохранить как»: file_picker сам записывает [bytes].
  /// null — человек передумал.
  static Future<SavedFile?> save({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    // type и allowedExtensions file_picker 13 в saveFile не использует
    // (устарели, уберут в 14): тип файла — по расширению в [fileName].
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: dialogTitle,
    );
    if (uri == null) return null;
    if (uri.scheme == 'file' || uri.scheme.isEmpty) {
      final path = uri.scheme.isEmpty ? uri.toString() : uri.toFilePath();
      // Прежние версии на компьютере возвращали путь, не записывая файл, —
      // на случай такой реализации платформы дописываем сами.
      try {
        final f = File(path);
        if (!f.existsSync() || f.lengthSync() == 0) await f.writeAsBytes(bytes, flush: true);
      } catch (_) {}
      return (shown: path, path: path);
    }
    // content:// (Android): из «…/document/primary%3ADownload%2Fотчёт.pdf» —
    // «отчёт.pdf».
    var shown = fileName;
    try {
      final last = uri.pathSegments.isEmpty ? '' : Uri.decodeComponent(uri.pathSegments.last);
      final tail = p.posix.basename(last.split(':').last);
      if (tail.isNotEmpty) shown = tail;
    } catch (_) {}
    return (shown: shown, path: null);
  }
}

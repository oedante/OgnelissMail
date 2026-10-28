// lib/services/mail/draft_files.dart
// Файлы черновика (1.7.2+111, план «вложения в черновиках»). Раньше черновик
// хранил только адресатов, тему и текст: приложенные файлы терялись при
// закрытии письма, на сервер черновик уходил без них, а прежняя серверная
// копия (с файлами, если черновик начат в Outlook) после выгрузки новой
// версии удалялась — файлы пропадали совсем.
//
// Хранение:
//  · свои файлы (выбранные, из «Поделиться», уже скачанные вложения
//    пересылки) — копией в `<Application Support>/draft_files/<черновик>/`:
//    эту папку система не чистит, в отличие от кэша вложений;
//  · не скачанные вложения письма (пересылка, черновик из Outlook) —
//    ссылкой: ящик, письмо, вложение; скачиваются при открытии черновика
//    или перед выгрузкой на сервер.
// Список — в attachments_json строки черновика:
//   {"id": "draft:<файл>", "name", "mimeType", "size", "draftFile": "<папка>/<файл>"}
//   {"id": "<id вложения>", "name", "mimeType", "size", "remoteAccount", "remoteEmail"}
// Путь — относительный: у iOS путь к папке приложения меняется при
// обновлении. «[]» — черновик этой версии без файлов; null — черновик
// прежних версий (файлов он не хранил).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

/// Файл черновика: свой (путь на телефоне или байты в памяти) или ссылка на
/// вложение письма на сервере.
class DraftFile {
  final String name;
  final int size;
  final String? mimeType;

  /// Файл на телефоне.
  final String? path;

  /// Байты в памяти (выбор файла системы без пути).
  final Uint8List? bytes;

  /// Не скачанное вложение: ящик, письмо и id вложения на сервере.
  final String? remoteAccountId;
  final String? remoteEmailId;
  final String? remoteId;

  const DraftFile.local({required this.name, required this.size, this.mimeType, this.path, this.bytes})
      : remoteAccountId = null,
        remoteEmailId = null,
        remoteId = null;

  const DraftFile.remote({
    required this.name,
    required this.size,
    this.mimeType,
    required String accountId,
    required String emailId,
    required String attachmentId,
  })  : path = null,
        bytes = null,
        remoteAccountId = accountId,
        remoteEmailId = emailId,
        remoteId = attachmentId;

  bool get isRemote => remoteId != null;
}

class DraftFiles {
  DraftFiles._();

  static Directory? _root;

  /// Источник файла → имя копии в папке черновика (в пределах запуска):
  /// автосохранение каждые 30 с не копирует один и тот же файл заново.
  static final Map<String, Map<String, String>> _copied = {};
  static int _seq = 0;

  /// Папка для тестов (вместо папки приложения).
  static Directory? debugRoot;

  static Future<Directory> _rootDir() async {
    final test = debugRoot;
    if (test != null) return test;
    return _root ??= Directory('${(await getApplicationSupportDirectory()).path}/draft_files');
  }

  static String _dirName(String draftId) => draftId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  /// Имя файла на диске: без символов, которые не любят файловые системы,
  /// не длиннее 80 знаков (расширение сохраняется).
  static String _safeName(String name) {
    var s = name.replaceAll(RegExp(r'[^\w.\-]'), '_');
    if (s.isEmpty) s = 'file';
    if (s.length > 80) {
      final dot = s.lastIndexOf('.');
      final ext = dot > 0 && s.length - dot <= 10 ? s.substring(dot) : '';
      s = s.substring(0, 80 - ext.length) + ext;
    }
    return s;
  }

  static String _lastSegment(String path) => path.split(RegExp(r'[\\/]')).last;

  /// Записать файлы черновика [draftId]: свои — копией в его папку, не
  /// скачанные — ссылкой; убранные из письма — из папки тоже. Возвращает
  /// JSON для attachments_json («[]» — файлов нет).
  static Future<String> store(String draftId, List<DraftFile> files) async {
    final root = await _rootDir();
    final dirName = _dirName(draftId);
    final dir = Directory('${root.path}/$dirName');
    final memo = _copied.putIfAbsent(draftId, () => {});
    final keep = <String>{};
    final out = <Map<String, Object?>>[];
    for (final f in files) {
      if (f.isRemote) {
        out.add({
          'id': f.remoteId,
          'name': f.name,
          'mimeType': f.mimeType ?? '',
          'size': f.size,
          'remoteAccount': f.remoteAccountId,
          'remoteEmail': f.remoteEmailId,
        });
        continue;
      }
      final src = f.path;
      final data = f.bytes;
      final String fileName;
      if (src != null && src.startsWith('${dir.path}/')) {
        // Файл уже в папке черновика (черновик открыт повторно).
        fileName = src.substring(dir.path.length + 1);
      } else {
        final key = src ?? 'mem:${identityHashCode(data)}:${f.size}:${f.name}';
        final known = memo[key];
        if (known != null && await File('${dir.path}/$known').exists()) {
          fileName = known;
        } else {
          if (src == null && data == null) continue;
          if (!await dir.exists()) await dir.create(recursive: true);
          final made = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_seq++}_${_safeName(f.name)}';
          final target = File('${dir.path}/$made');
          if (src != null) {
            await File(src).copy(target.path);
          } else if (data != null) {
            await target.writeAsBytes(data, flush: true);
          }
          memo[key] = made;
          fileName = made;
        }
      }
      keep.add(fileName);
      out.add({
        'id': 'draft:$fileName',
        'name': f.name,
        'mimeType': f.mimeType ?? '',
        'size': f.size,
        'draftFile': '$dirName/$fileName',
      });
    }
    if (await dir.exists()) {
      for (final e in await dir.list().toList()) {
        if (e is File && !keep.contains(_lastSegment(e.path))) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
      if (keep.isEmpty) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
    memo.removeWhere((_, v) => !keep.contains(v));
    return jsonEncode(out);
  }

  /// Файлы черновика из attachments_json. Свои — с путём на телефоне (файла
  /// нет — пропускается), не скачанные — ссылкой. null — список не в формате
  /// черновика (черновик прежних версий).
  static Future<List<DraftFile>?> load(String? json) async {
    if (json == null || json.isEmpty) return null;
    final List<dynamic> list;
    try {
      final v = jsonDecode(json);
      if (v is! List) return null;
      list = v;
    } catch (_) {
      return null;
    }
    final out = <DraftFile>[];
    if (list.isEmpty) return out;
    Directory? root;
    try {
      root = await _rootDir();
    } catch (e) {
      AppLogger.warning('Черновик: папка файлов недоступна — $e');
    }
    for (final m in list.whereType<Map>()) {
      final name = (m['name'] ?? 'file').toString();
      final size = (m['size'] as num?)?.toInt() ?? 0;
      final mt = m['mimeType'];
      final mime = mt is String && mt.isNotEmpty ? mt : null;
      final rel = m['draftFile'];
      if (rel is String && rel.isNotEmpty) {
        if (root == null) continue;
        final file = File('${root.path}/$rel');
        if (!await file.exists()) {
          AppLogger.warning('Черновик: файла «$name» нет на телефоне — пропущен');
          continue;
        }
        out.add(DraftFile.local(name: name, size: await file.length(), mimeType: mime, path: file.path));
        continue;
      }
      final acc = m['remoteAccount'], email = m['remoteEmail'], id = m['id'];
      if (acc is String && email is String && id is String && id.isNotEmpty) {
        out.add(DraftFile.remote(
            name: name, size: size, mimeType: mime, accountId: acc, emailId: email, attachmentId: id));
      }
    }
    return out;
  }

  /// Путь своего файла черновика по id вложения строки («draft:<файл>») —
  /// карточка письма по удержанию в «Черновиках». null — не свой файл или
  /// его нет.
  static Future<String?> pathFor(String draftId, String attachmentId) async {
    if (!attachmentId.startsWith('draft:')) return null;
    final name = attachmentId.substring(6);
    if (name.isEmpty || name.contains('/') || name.contains('\\')) return null;
    try {
      final f = File('${(await _rootDir()).path}/${_dirName(draftId)}/$name');
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  /// Удалить файлы черновика (отправлен, удалён, выгружен на сервер).
  static Future<void> remove(String draftId) async {
    _copied.remove(draftId);
    try {
      final dir = Directory('${(await _rootDir()).path}/${_dirName(draftId)}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLogger.debug('Черновик: файлы не удалены — $e');
    }
  }

  /// Убрать папки черновиков, которых больше нет (удалён ящик, сбой при
  /// удалении), — старше суток: свежая папка может принадлежать письму,
  /// которое пишется прямо сейчас.
  static Future<void> sweep(Set<String> liveDraftIds) async {
    try {
      final root = await _rootDir();
      if (!await root.exists()) return;
      final live = {for (final id in liveDraftIds) _dirName(id)};
      final old = DateTime.now().subtract(const Duration(days: 1));
      for (final e in await root.list().toList()) {
        if (e is! Directory || live.contains(_lastSegment(e.path))) continue;
        if ((await e.stat()).modified.isAfter(old)) continue;
        await e.delete(recursive: true);
        AppLogger.info('Черновик: удалены файлы черновика, которого больше нет');
      }
    } catch (e) {
      AppLogger.debug('Черновик: уборка файлов — $e');
    }
  }
}

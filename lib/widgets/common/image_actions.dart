// lib/widgets/common/image_actions.dart
// Картинка из письма: копировать, сохранить, поделиться (1.8.12, просьба
// владельца 30.10.2026: «картинки хорошо бы не только увеличивать, но и
// давать возможность скопировать или сохранить»).
//
//  · Копировать — Android: файл через FileProvider в буфер обмена
//    (FileOpenBridge.copyImage), iPhone и iPad: UIPasteboard (канал
//    ogneliss/platform). На компьютере картинку можно сохранить.
//  · Сохранить — «Загрузки» (DownloadSaver); на iPhone — лист «Поделиться»
//    с «Сохранить изображение».
//  · Поделиться — системный лист.

import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_logger.dart';
import '../../core/platform/download_saver.dart';

class ImageActions {
  ImageActions._();

  static const _files = MethodChannel('ogneliss/open_file');
  static const _platform = MethodChannel('ogneliss/platform');

  /// Копировать картинку можно (Android, iPhone, iPad).
  static bool get canCopy => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Тип картинки по первым байтам: расширение и MIME.
  static ({String ext, String mime}) typeOf(Uint8List b) {
    bool at(List<int> sig, [int off = 0]) {
      if (b.length < off + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[off + i] != sig[i]) return false;
      }
      return true;
    }

    if (at(const [0x89, 0x50, 0x4E, 0x47])) return (ext: 'png', mime: 'image/png');
    if (at(const [0xFF, 0xD8, 0xFF])) return (ext: 'jpg', mime: 'image/jpeg');
    if (at(const [0x47, 0x49, 0x46, 0x38])) return (ext: 'gif', mime: 'image/gif');
    if (at(const [0x52, 0x49, 0x46, 0x46]) && at(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return (ext: 'webp', mime: 'image/webp');
    }
    if (at(const [0x42, 0x4D])) return (ext: 'bmp', mime: 'image/bmp');
    return (ext: 'png', mime: 'image/png');
  }

  /// Имя файла для картинки: [name] (если есть) с верным расширением, иначе
  /// «image_ГГГГММДД_ччммсс».
  static String fileName(Uint8List b, {String? name}) {
    final ext = typeOf(b).ext;
    final base = (name ?? '').trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (base.isNotEmpty) {
      final dot = base.lastIndexOf('.');
      return '${dot > 0 ? base.substring(0, dot) : base}.$ext';
    }
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'image_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}.$ext';
  }

  static Future<String> _temp(Uint8List b, String name) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/images');
    await dir.create(recursive: true);
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(b, flush: true);
    return f.path;
  }

  /// Картинка из интернета (письмо с разрешёнными картинками) — не больше
  /// 25 МБ, за 20 с; null — не получилось.
  static Future<Uint8List?> download(String url) async {
    try {
      final uri = Uri.parse(url.startsWith('http://') ? 'https://${url.substring(7)}' : url);
      final r = await http.get(uri).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty || r.bodyBytes.length > 25 * 1024 * 1024) return null;
      return r.bodyBytes;
    } catch (e) {
      AppLogger.warning('Картинка: не загрузилась — ${e.runtimeType}');
      return null;
    }
  }

  /// Скопировать в буфер обмена. false — не получилось.
  static Future<bool> copy(Uint8List b, {String? name}) async {
    if (!canCopy) return false;
    try {
      if (Platform.isIOS) {
        return await _platform.invokeMethod<bool>('copyImage', b) ?? false;
      }
      final path = await _temp(b, fileName(b, name: name));
      return await _files.invokeMethod<bool>('copyImage', {'path': path, 'mime': typeOf(b).mime}) ?? false;
    } catch (e) {
      AppLogger.warning('Картинка: копирование не удалось — $e');
      return false;
    }
  }

  /// Сохранить: «Загрузки» (имя, под которым файл лёг) или лист
  /// «Поделиться» на iPhone (null).
  static Future<SavedDownload?> save(Uint8List b, {String? name}) async {
    final file = fileName(b, name: name);
    final path = await _temp(b, file);
    if (!DownloadSaver.supported) {
      await share(b, name: name);
      return null;
    }
    return DownloadSaver.save(path, file);
  }

  static Future<void> share(Uint8List b, {String? name}) async {
    final file = fileName(b, name: name);
    final path = await _temp(b, file);
    await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: typeOf(b).mime, name: file)]));
  }
}

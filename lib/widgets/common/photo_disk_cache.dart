// lib/widgets/common/photo_disk_cache.dart
// Фото людей по ссылке (профили Google, 2.6.5) — с копией на диске.
//
// Замечание владельца 18.11.2026 (снимки беседы): «фото было, а потом
// появляется — каждый раз запрашиваются через Google?». Да: фото по ссылке
// грузились NetworkImage — только в память, а при каждом сворачивании
// Android просит прибраться, и кэш картинок очищается (main_shell,
// didHaveMemoryPressure). После возврата все фото Google скачивались заново,
// и пока шла загрузка, на месте фото был пустой кружок.
//
// Теперь фото скачивается один раз и лежит в кэше приложения (папка
// photos, имя — SHA-256 ссылки): после возврата оно читается с диска за
// миллисекунды. Копия старше недели при показе обновляется в фоне (человек
// мог сменить фото); не скачалось — показываем старую. Новые ссылки Google
// дают при смене фото новый адрес — тогда это просто новое фото.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

abstract final class PhotoDiskCache {
  /// Копия старше — обновить в фоне при показе.
  static const refreshAfter = Duration(days: 7);

  /// Фото больше — не храним (портрет 96 dp — десятки КБ).
  static const maxBytes = 2 * 1024 * 1024;

  /// Для тестов: папка и клиент HTTP.
  @visibleForTesting
  static Directory? debugDir;
  @visibleForTesting
  static http.Client? debugClient;

  static Directory? _dir;
  static final Map<String, Future<Uint8List?>> _inflight = {};

  /// Для тестов: дождаться всех идущих загрузок (и фоновых обновлений).
  @visibleForTesting
  static Future<void> debugIdle() async {
    while (_inflight.isNotEmpty) {
      await Future.wait(_inflight.values.toList());
    }
  }

  static Future<Directory> _folder() async {
    final d = debugDir ?? (_dir ??= Directory('${(await getApplicationCacheDirectory()).path}/photos'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String fileName(String url) => sha256.convert(url.codeUnits).toString();

  /// Байты фото [url]: с диска, иначе из сети (и сохранить). null — нет.
  static Future<Uint8List?> bytes(String url) async {
    final f = File('${(await _folder()).path}/${fileName(url)}');
    if (f.existsSync()) {
      try {
        final data = await f.readAsBytes();
        if (data.isNotEmpty) {
          if (DateTime.now().difference(f.lastModifiedSync()) > refreshAfter) {
            unawaited(_download(url, f));
          }
          return data;
        }
      } catch (_) {}
    }
    return _download(url, f);
  }

  /// Скачать и сохранить; одновременные запросы одной ссылки — один.
  static Future<Uint8List?> _download(String url, File f) =>
      _inflight[url] ??= _fetch(url, f).whenComplete(() {
        // Без «=>»: remove вернул бы сам этот Future, и whenComplete ждал бы
        // его — вечно.
        _inflight.remove(url);
      });

  static Future<Uint8List?> _fetch(String url, File f) async {
    try {
      final c = debugClient ?? http.Client();
      try {
        final r = await c.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty || r.bodyBytes.length > maxBytes) return null;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsBytes(r.bodyBytes, flush: true);
        await tmp.rename(f.path);
        return r.bodyBytes;
      } finally {
        if (debugClient == null) c.close();
      }
    } catch (_) {
      // Нет сети — покажем старую копию (если есть) или букву.
      return f.existsSync() ? await f.readAsBytes() : null;
    }
  }
}

/// Картинка фото по ссылке через [PhotoDiskCache].
class CachedPhotoImage extends ImageProvider<CachedPhotoImage> {
  final String url;
  const CachedPhotoImage(this.url);

  @override
  Future<CachedPhotoImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedPhotoImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0, debugLabel: 'photo');

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final data = await PhotoDiskCache.bytes(url);
    if (data == null) throw StateError('Фото не загрузилось');
    return decode(await ui.ImmutableBuffer.fromUint8List(data));
  }

  @override
  bool operator ==(Object other) => other is CachedPhotoImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

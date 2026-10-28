// lib/services/mail/image_shrink.dart
// Уменьшение фото и картинок во вложениях перед отправкой (1.7.2+109,
// договорённость с владельцем: «предлагать сжатие — 75 %, 50 %, 25 % с
// приблизительным размером — или отправлять как есть»).
//
// Раньше фото больше 1,5 МБ молча ужимались до 1600 точек по длинной стороне
// (качество 82): человек не знал, что отправил не оригинал, и не мог
// отправить снимок целиком. Теперь решает человек — шторка при отправке
// (`image_size_sheet.dart`) или выбор «Размер фото при отправке» в
// «Настройки → Почта → Отправка».
//
// Процент — от ширины и высоты: 50 % — вдвое меньше по каждой стороне (в
// четыре раза меньше точек). Декодирует Flutter (быстро, с учётом поворота
// снимка из EXIF, HEIC — системным декодером iPhone и Android 9+);
// JPEG кодирует пакет image в отдельном изоляте, PNG (скриншоты, рисунки с
// прозрачностью) — Flutter. HEIC и HEIF после уменьшения — JPEG (Windows
// и многие почтовые программы их не открывают). Сведения EXIF — место
// съёмки, модель телефона — в уменьшенное фото не попадают. Не стало
// меньше или не получилось — уходит оригинал.
//
// 1.7.2+111: декодер Flutter не справился — JPEG и PNG уменьшает пакет image
// в изоляте (с поворотом из EXIF и без сведений EXIF). Так было в
// `flutter test` у владельца 25.10.2026: оба теста уменьшения получили
// оригинал. На телефоне запасной путь пишет предупреждение в журнал.
//
// 1.7.2+114: «Сжать» закрывало приложение (журнал владельца 25.10.2026,
// nubia, Android 15: crash_native). Причина — описатель картинки
// (ImageDescriptor) освобождался сразу после instantiateCodec, до
// getNextFrame: dispose() сбрасывает его декодер, а кодек декодирует через
// тот же описатель — на телефоне падение в движке, в `flutter test` —
// «нет точек» (те самые два упавших теста 111). Теперь описатель и буфер
// освобождаются после кадра.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/logging/app_logger.dart';

/// Сколько точек оставить: доля ширины и высоты.
class ImageShrink {
  ImageShrink._();

  /// Варианты в шторке и в настройках (доля стороны).
  static const scales = [0.75, 0.5, 0.25];

  /// Меньше этого (все фото письма вместе) — не спрашиваем: один скриншот в
  /// пару сотен килобайт уменьшать незачем.
  static const askFromBytes = 300 * 1024;

  /// Качество JPEG уменьшенного фото.
  static const jpegQuality = 85;

  static const _jpeg = {'jpg', 'jpeg'};
  static const _heic = {'heic', 'heif'};

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Фото или картинка, которую можно уменьшить. GIF (анимация), WebP и
  /// прочее уходят как есть.
  static bool isShrinkable(String name) {
    final e = _ext(name);
    return _jpeg.contains(e) || _heic.contains(e) || e == 'png';
  }

  /// Имя файла после уменьшения: HEIC и HEIF становятся JPEG.
  static String outName(String name) {
    if (!_heic.contains(_ext(name))) return name;
    return '${name.substring(0, name.lastIndexOf('.'))}.jpg';
  }

  /// Примерный размер после уменьшения до [scale] (для шторки — со знаком
  /// «≈»). Точек меньше в scale² раз; JPEG камеры (качество 90–95) при
  /// пересжатии с качеством 85 теряет ещё около трети, HEIC сжат плотнее
  /// JPEG примерно в полтора раза, у PNG уменьшенная картинка сжимается чуть
  /// хуже исходной. Больше оригинала не бывает — тогда уйдёт оригинал.
  static int estimate(String name, int bytes, double scale) {
    if (scale >= 1 || !isShrinkable(name)) return bytes;
    final e = _ext(name);
    final k = _heic.contains(e) ? 1.5 : (e == 'png' ? 1.2 : 0.65);
    final v = (bytes * scale * scale * k).round();
    return v < bytes ? v : bytes;
  }

  /// Уменьшить [bytes] файла [name] до [scale]. Не картинка, не получилось
  /// или не стало меньше — исходные имя и байты.
  static Future<({String name, Uint8List bytes})> shrink(String name, Uint8List bytes, double scale) async {
    final original = (name: name, bytes: bytes);
    if (scale >= 1 || !isShrinkable(name)) return original;
    Uint8List? out;
    try {
      out = await _withFlutter(name, bytes, scale);
    } catch (e) {
      AppLogger.warning('Фото «$name»: декодер Flutter не справился ($e) — уменьшает пакет image');
    }
    // Запасной путь: JPEG и PNG — пакетом image в изоляте. HEIC он не читает —
    // тогда уходит оригинал.
    if (out == null && !_heic.contains(_ext(name))) {
      try {
        out = await compute(_shrinkWithDart, (png: _ext(name) == 'png', scale: scale, bytes: bytes));
      } catch (e) {
        AppLogger.warning('Фото «$name» не уменьшено: $e');
      }
    }
    if (out == null || out.isEmpty || out.length >= bytes.length) return original;
    return (name: outName(name), bytes: out);
  }

  /// Запасной путь без Flutter — для тестов (в том же изоляте).
  @visibleForTesting
  static Uint8List? shrinkWithDart(String name, Uint8List bytes, double scale) =>
      _shrinkWithDart((png: _ext(name) == 'png', scale: scale, bytes: bytes));

  /// Декодер Flutter: быстро, с поворотом из EXIF, HEIC — системным
  /// декодером. null — Flutter не отдал точки; ошибка — исключение.
  static Future<Uint8List?> _withFlutter(String name, Uint8List bytes, double scale) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? frame;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      // Только ширина: высота — по пропорциям того же снимка (с поворотом
      // из EXIF Flutter разбирается сам).
      final w = math.max(1, (descriptor.width * scale).round());
      codec = await descriptor.instantiateCodec(targetWidth: w);
      frame = (await codec.getNextFrame()).image;
      if (_ext(name) == 'png') {
        final data = await frame.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return await compute(_encodeJpeg, (
        width: frame.width,
        height: frame.height,
        // toByteData отдаёт отдельный буфер — целиком, без смещения.
        rgba: data.buffer.asUint8List(),
      ));
    } finally {
      frame?.dispose();
      codec?.dispose();
      // Описатель — только после кадра: его dispose() сбрасывает декодер,
      // которым пользуется кодек (иначе падение в движке, см. 1.7.2+114).
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

/// Уменьшение пакетом image (в изоляте): поворот из EXIF, усреднение точек,
/// без сведений EXIF. null — не картинка.
Uint8List? _shrinkWithDart(({bool png, double scale, Uint8List bytes}) a) {
  final src = img.decodeImage(a.bytes);
  if (src == null) return null;
  final upright = img.bakeOrientation(src);
  final small = img.copyResize(upright,
      width: math.max(1, (upright.width * a.scale).round()), interpolation: img.Interpolation.average);
  // Место съёмки, модель телефона — в уменьшенное фото не переносим.
  small.exif = img.ExifData();
  return a.png ? img.encodePng(small) : img.encodeJpg(small, quality: ImageShrink.jpegQuality);
}

/// JPEG из точек RGBA (в изоляте: кодирование 12-мегапиксельного снимка
/// занимает секунду-другую). Фото непрозрачны — альфа отбрасывается.
Uint8List _encodeJpeg(({int width, int height, Uint8List rgba}) a) {
  final image = img.Image.fromBytes(
    width: a.width,
    height: a.height,
    bytes: a.rgba.buffer,
    numChannels: 4,
  );
  return img.encodeJpg(image, quality: ImageShrink.jpegQuality);
}

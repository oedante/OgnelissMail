// lib/services/mail/image_edit.dart
// Обрезка и поворот фото во вложениях письма (1.7.2+113, просьба владельца
// 25.10.2026: «небольшой редактор изображений — только обрезка и поворот»).
// Экран — `features/compose/screens/image_edit_screen.dart`, здесь —
// применение к файлу.
//
// Поворот — четвертями оборота по часовой стрелке ([turns] 0–3), рамка
// обрезки — доли (0..1) уже повёрнутого снимка. Рисует Flutter: снимок
// (с поворотом из EXIF, HEIC — системным декодером) в холст нужного размера
// — поворот на четверть оборота переставляет точки без размытия. JPEG
// кодирует пакет image в изоляте (качество 92 — правка не должна заметно
// портить снимок), PNG — Flutter; HEIC и HEIF становятся JPEG. Flutter не
// справился (очень большая панорама, отказ декодера) — JPEG и PNG
// обрабатывает пакет image. Сведения EXIF (место съёмки, модель телефона) в
// результат не попадают.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../core/logging/app_logger.dart';
import 'image_shrink.dart';

class ImageEdit {
  ImageEdit._();

  /// Качество JPEG после правки.
  static const jpegQuality = 92;

  /// Наибольшая сторона холста для правки средствами Flutter.
  static const _maxCanvas = 8192;

  /// Вся картинка — рамка «без обрезки».
  static const full = ui.Rect.fromLTRB(0, 0, 1, 1);

  /// Можно ли править: фото и картинки, которые Flutter умеет рисовать и
  /// сохранять (GIF — анимация, WebP — редкость: открываются как есть).
  static bool isEditable(String name) => ImageShrink.isShrinkable(name);

  static bool _isPng(String name) => name.toLowerCase().endsWith('.png');

  /// Рамка после поворота снимка на четверть оборота против часовой стрелки
  /// (кнопка «Повернуть»): точка (u, v) становится (v, 1 − u).
  static ui.Rect rotateLeft(ui.Rect r) => ui.Rect.fromLTRB(r.top, 1 - r.right, r.bottom, 1 - r.left);

  /// То же по часовой стрелке: (u, v) → (1 − v, u).
  static ui.Rect rotateRight(ui.Rect r) => ui.Rect.fromLTRB(1 - r.bottom, r.left, 1 - r.top, r.right);

  /// Рамка (доли [l], [t], [r], [b]) в точках снимка размером [w] × [h]
  /// (уже повёрнутого): целые, не меньше точки, в пределах снимка.
  static ({int x, int y, int w, int h}) pixels(double l, double t, double r, double b, int w, int h) {
    final x = math.min(math.max((l * w).round(), 0), w - 1);
    final y = math.min(math.max((t * h).round(), 0), h - 1);
    final right = math.min(math.max((r * w).round(), x + 1), w);
    final bottom = math.min(math.max((b * h).round(), y + 1), h);
    return (x: x, y: y, w: right - x, h: bottom - y);
  }

  /// Повернуть на [turns] четвертей по часовой стрелке и обрезать по [crop].
  /// null — не получилось (строку ошибки показывает экран).
  static Future<({String name, Uint8List bytes})?> apply(
      Uint8List bytes, String name, int turns, ui.Rect crop) async {
    final t = turns % 4;
    final out = ImageShrink.outName(name);
    try {
      final r = await _withFlutter(bytes, _isPng(name), t, crop);
      if (r != null && r.isNotEmpty) return (name: out, bytes: r);
    } catch (e) {
      AppLogger.warning('Правка фото «$name»: Flutter не справился ($e) — пакет image');
    }
    final lower = name.toLowerCase();
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return null;
    try {
      final r = await compute(_editWithDart, (png: _isPng(name), turns: t, crop: _box(crop), bytes: bytes));
      return r == null ? null : (name: out, bytes: r);
    } catch (e) {
      AppLogger.warning('Правка фото «$name» не удалась: $e');
      return null;
    }
  }

  /// Пакетом image, в том же изоляте — для тестов.
  @visibleForTesting
  static Uint8List? applyWithDart(Uint8List bytes, String name, int turns, ui.Rect crop) =>
      _editWithDart((png: _isPng(name), turns: turns % 4, crop: _box(crop), bytes: bytes));

  /// В изолят — четыре числа, без классов dart:ui.
  static (double, double, double, double) _box(ui.Rect r) => (r.left, r.top, r.right, r.bottom);

  static Future<Uint8List?> _withFlutter(Uint8List bytes, bool png, int turns, ui.Rect crop) async {
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? src;
    ui.Image? result;
    try {
      src = (await codec.getNextFrame()).image;
      final odd = turns.isOdd;
      final rw = odd ? src.height : src.width;
      final rh = odd ? src.width : src.height;
      final p = pixels(crop.left, crop.top, crop.right, crop.bottom, rw, rh);
      // Холст больше 8192 точек по стороне не на всех телефонах по силам
      // видеокарте (снимки 108–200 Мп) — такие правит пакет image.
      if (p.w > _maxCanvas || p.h > _maxCanvas) return null;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(-p.x.toDouble(), -p.y.toDouble());
      // Поворот на четверть оборота: точки встают ровно в клетки, без размытия.
      switch (turns) {
        case 1:
          canvas.translate(rw.toDouble(), 0);
          canvas.rotate(math.pi / 2);
        case 2:
          canvas.translate(rw.toDouble(), rh.toDouble());
          canvas.rotate(math.pi);
        case 3:
          canvas.translate(0, rh.toDouble());
          canvas.rotate(3 * math.pi / 2);
      }
      canvas.drawImage(src, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.none);
      final picture = recorder.endRecording();
      result = await picture.toImage(p.w, p.h);
      picture.dispose();
      if (png) {
        final data = await result.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return null;
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
      final data = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return await compute(_encodeJpeg, (width: result.width, height: result.height, rgba: data.buffer.asUint8List()));
    } finally {
      src?.dispose();
      result?.dispose();
      codec.dispose();
    }
  }
}

/// Правка пакетом image (в изоляте): поворот из EXIF, поворот, обрезка, без
/// сведений EXIF. null — не картинка.
Uint8List? _editWithDart(({bool png, int turns, (double, double, double, double) crop, Uint8List bytes}) a) {
  final src = img.decodeImage(a.bytes);
  if (src == null) return null;
  var im = img.bakeOrientation(src);
  if (a.turns != 0) im = img.copyRotate(im, angle: a.turns * 90);
  final (l, t, r, b) = a.crop;
  final p = ImageEdit.pixels(l, t, r, b, im.width, im.height);
  if (p.x != 0 || p.y != 0 || p.w != im.width || p.h != im.height) {
    im = img.copyCrop(im, x: p.x, y: p.y, width: p.w, height: p.h);
  }
  im.exif = img.ExifData();
  return a.png ? img.encodePng(im) : img.encodeJpg(im, quality: ImageEdit.jpegQuality);
}

/// JPEG из точек RGBA (в изоляте).
Uint8List _encodeJpeg(({int width, int height, Uint8List rgba}) a) {
  final image = img.Image.fromBytes(width: a.width, height: a.height, bytes: a.rgba.buffer, numChannels: 4);
  return img.encodeJpg(image, quality: ImageEdit.jpegQuality);
}

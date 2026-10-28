// test/unit/image_edit_test.dart
// 1.7.2+113: обрезка и поворот фото во вложениях (ImageEdit): рамка
// поворачивается вместе со снимком, рамка в точках, поворот по часовой
// стрелке и против, обрезка, поворот по EXIF и без сведений EXIF.
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/services/mail/image_edit.dart';

void main() {
  test('рамка поворачивается вместе со снимком', () {
    const r = Rect.fromLTRB(0.1, 0.2, 0.5, 0.6);
    // Против часовой: (u, v) → (v, 1 − u).
    expect(ImageEdit.rotateLeft(r), rectMoreOrLessEquals(const Rect.fromLTRB(0.2, 0.5, 0.6, 0.9)));
    var x = r;
    for (var i = 0; i < 4; i++) {
      x = ImageEdit.rotateLeft(x);
    }
    expect(x, rectMoreOrLessEquals(r), reason: 'четыре поворота — как было');
    expect(ImageEdit.rotateRight(ImageEdit.rotateLeft(r)), rectMoreOrLessEquals(r));
    expect(ImageEdit.rotateLeft(ImageEdit.full), ImageEdit.full);
  });

  test('рамка в точках: целые, не меньше точки, в пределах снимка', () {
    final p = ImageEdit.pixels(0.25, 0.5, 0.75, 1.0, 400, 200);
    expect((p.x, p.y, p.w, p.h), (100, 100, 200, 100));
    final tiny = ImageEdit.pixels(0.999, 0.999, 1.0, 1.0, 10, 10);
    expect(tiny.w, greaterThanOrEqualTo(1));
    expect(tiny.x + tiny.w, lessThanOrEqualTo(10));
    expect(tiny.y + tiny.h, lessThanOrEqualTo(10));
  });

  test('поворот и обрезка пакетом image: направление и точки (PNG)', () {
    final src = img.Image(width: 4, height: 2);
    img.fill(src, color: img.ColorRgb8(255, 255, 255));
    src.setPixelRgb(0, 0, 255, 0, 0); // красная точка слева вверху
    final png = img.encodePng(src);

    // Четверть оборота по часовой стрелке: 2 × 4, точка справа вверху.
    final cw = img.decodePng(ImageEdit.applyWithDart(png, 'a.png', 1, ImageEdit.full)!)!;
    expect((cw.width, cw.height), (2, 4));
    expect(cw.getPixel(1, 0).g, 0);
    expect(cw.getPixel(0, 0).g, 255);

    // Против часовой (три четверти по часовой): точка слева внизу.
    final ccw = img.decodePng(ImageEdit.applyWithDart(png, 'a.png', 3, ImageEdit.full)!)!;
    expect(ccw.getPixel(0, 3).g, 0);

    // Повернули и оставили правую половину: 1 × 4, точка вверху.
    final cut = img.decodePng(ImageEdit.applyWithDart(png, 'a.png', 1, const Rect.fromLTRB(0.5, 0, 1, 1))!)!;
    expect((cut.width, cut.height), (1, 4));
    expect(cut.getPixel(0, 0).g, 0);
  });

  test('снимок «на боку» (EXIF orientation 6): поворот по EXIF, без сведений EXIF', () {
    final side = img.Image(width: 80, height: 60)..exif.imageIfd.orientation = 6;
    final jpg = img.encodeJpg(side);
    // По EXIF снимок стоит (60 × 80); ещё четверть по часовой — снова 80 × 60.
    final out = img.decodeJpg(ImageEdit.applyWithDart(jpg, 'IMG.jpg', 1, ImageEdit.full)!)!;
    expect((out.width, out.height), (80, 60));
    expect(out.exif.isEmpty, isTrue);
  });

  test('что можно править', () {
    expect(ImageEdit.isEditable('IMG_0001.JPG'), isTrue);
    expect(ImageEdit.isEditable('shot.png'), isTrue);
    expect(ImageEdit.isEditable('IMG_0002.HEIC'), isTrue);
    expect(ImageEdit.isEditable('anim.gif'), isFalse);
    expect(ImageEdit.isEditable('Отчёт.pdf'), isFalse);
  });
}

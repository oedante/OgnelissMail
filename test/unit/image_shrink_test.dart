// test/unit/image_shrink_test.dart
// 1.7.2+109: фото во вложениях — как есть или 75 / 50 / 25 % по сторонам
// (ImageShrink): какие файлы уменьшаются, примерный размер, имя HEIC → JPG,
// настоящее уменьшение JPEG и PNG; запасной путь без Flutter (1.7.2+111).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/services/mail/image_shrink.dart';

/// Шумная картинка: сжимается плохо, как фото.
img.Image _noise(int w, int h) {
  final r = Random(7);
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return im;
}

void main() {
  test('уменьшаются JPEG, PNG и HEIC; GIF, WebP и документы — нет', () {
    expect(ImageShrink.isShrinkable('IMG_0001.JPG'), isTrue);
    expect(ImageShrink.isShrinkable('photo.jpeg'), isTrue);
    expect(ImageShrink.isShrinkable('Снимок экрана.png'), isTrue);
    expect(ImageShrink.isShrinkable('IMG_0002.HEIC'), isTrue);
    expect(ImageShrink.isShrinkable('anim.gif'), isFalse);
    expect(ImageShrink.isShrinkable('pic.webp'), isFalse);
    expect(ImageShrink.isShrinkable('Отчёт.pdf'), isFalse);
    expect(ImageShrink.isShrinkable('без расширения'), isFalse);
  });

  test('HEIC после уменьшения — .jpg, остальные имена не меняются', () {
    expect(ImageShrink.outName('IMG_0002.HEIC'), 'IMG_0002.jpg');
    expect(ImageShrink.outName('a.b.heif'), 'a.b.jpg');
    expect(ImageShrink.outName('photo.jpeg'), 'photo.jpeg');
    expect(ImageShrink.outName('shot.png'), 'shot.png');
  });

  test('примерный размер: меньше с каждым шагом, не больше оригинала', () {
    const mb4 = 4 * 1024 * 1024;
    final sizes = [for (final s in ImageShrink.scales) ImageShrink.estimate('IMG.jpg', mb4, s)];
    expect(sizes[0], lessThan(mb4));
    expect(sizes[1], lessThan(sizes[0]));
    expect(sizes[2], lessThan(sizes[1]));
    expect(ImageShrink.estimate('IMG.jpg', mb4, 1), mb4);
    expect(ImageShrink.estimate('doc.pdf', mb4, 0.5), mb4);
    expect(ImageShrink.estimate('IMG.heic', 1000, 0.75), lessThanOrEqualTo(1000));
  });

  testWidgets('JPEG 50% — вдвое меньше по сторонам и легче', (t) async {
    final src = Uint8List.fromList(img.encodeJpg(_noise(800, 600), quality: 100));
    final r = (await t.runAsync(() => ImageShrink.shrink('IMG.jpg', src, 0.5)))!;
    expect(r.name, 'IMG.jpg');
    expect(r.bytes.length, lessThan(src.length));
    final out = img.decodeJpg(r.bytes)!;
    expect(out.width, 400);
    expect(out.height, 300);
  });

  testWidgets('PNG 25% — остаётся PNG', (t) async {
    final src = Uint8List.fromList(img.encodePng(_noise(400, 200)));
    final r = (await t.runAsync(() => ImageShrink.shrink('shot.png', src, 0.25)))!;
    expect(r.name, 'shot.png');
    final out = img.decodePng(r.bytes)!;
    expect(out.width, 100);
    expect(out.height, 50);
  });

  test('запасной путь без Flutter: размеры, поворот из EXIF, без EXIF (1.7.2+111)', () {
    final jpg = Uint8List.fromList(img.encodeJpg(_noise(800, 600), quality: 100));
    final j = img.decodeJpg(ImageShrink.shrinkWithDart('IMG.jpg', jpg, 0.5)!)!;
    expect(j.width, 400);
    expect(j.height, 300);

    final png = Uint8List.fromList(img.encodePng(_noise(400, 200)));
    final p = img.decodePng(ImageShrink.shrinkWithDart('shot.png', png, 0.25)!)!;
    expect(p.width, 100);
    expect(p.height, 50);

    // Снимок «на боку» (EXIF orientation 6): уменьшенный — уже повёрнут, без EXIF.
    final side = _noise(80, 60)..exif.imageIfd.orientation = 6;
    final turned = img.decodeJpg(ImageShrink.shrinkWithDart('IMG.jpg', img.encodeJpg(side), 0.5)!)!;
    expect(turned.width, 30);
    expect(turned.height, 40);
    expect(turned.exif.isEmpty, isTrue);

    expect(ImageShrink.shrinkWithDart('broken.jpg', Uint8List.fromList(List.filled(1000, 7)), 0.5), isNull);
  });

  testWidgets('не картинка или как есть — без изменений', (t) async {
    final junk = Uint8List.fromList(List.filled(1000, 7));
    final bad = (await t.runAsync(() => ImageShrink.shrink('broken.jpg', junk, 0.5)))!;
    expect(identical(bad.bytes, junk), isTrue);
    final same = (await t.runAsync(() => ImageShrink.shrink('IMG.jpg', junk, 1)))!;
    expect(identical(same.bytes, junk), isTrue);
  });
}

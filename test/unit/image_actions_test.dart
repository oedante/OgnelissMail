// Картинка из письма: тип по первым байтам и имя файла для «Сохранить» и
// «Копировать» (1.8.12).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/widgets/common/image_actions.dart';

void main() {
  test('тип по сигнатуре', () {
    expect(ImageActions.typeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0])).mime, 'image/png');
    expect(ImageActions.typeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])).ext, 'jpg');
    expect(ImageActions.typeOf(Uint8List.fromList('GIF89a'.codeUnits)).ext, 'gif');
    expect(ImageActions.typeOf(Uint8List.fromList([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits])).ext, 'webp');
    expect(ImageActions.typeOf(Uint8List.fromList([1, 2, 3])).ext, 'png');
  });

  test('имя файла: своё с верным расширением, иначе по времени', () {
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    expect(ImageActions.fileName(jpg, name: 'image001.png'), 'image001.jpg');
    expect(ImageActions.fileName(jpg, name: 'a/b:c'), 'a_b_c.jpg');
    expect(ImageActions.fileName(jpg), matches(RegExp(r'^image_\d{8}_\d{6}\.jpg$')));
  });
}

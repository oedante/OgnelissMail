// test/unit/inline_image_cid_test.dart
// 1.6.23: шаблон CID был обычной строкой, «\s» превращался в «s» — CID с
// буквой «s» обрезался, «src = "cid:…"» с пробелами не находился.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/inline_image_handler.dart';

void main() {
  test('CID с буквой s и пробелы вокруг «=»', () {
    final cids = InlineImageHandler.extractCids(
        '<img src="cid:image001.png@01DASSSS"><img SRC = \'cid:sig_s1\'><img src=cid:logo>');
    expect(cids, ['image001.png@01DASSSS', 'sig_s1', 'logo']);
  });
}

// Большое вложение раскодируется вне главного потока (план 08.11.2026,
// п. 3): 20 МБ — 27 МБ текста base64, сотни миллисекунд главного потока.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart';

String _wrapped(Uint8List bytes) {
  final b64 = base64.encode(bytes);
  final out = StringBuffer();
  for (var i = 0; i < b64.length; i += 76) {
    out.write(b64.substring(i, i + 76 > b64.length ? b64.length : i + 76));
    out.write('\r\n');
  }
  return out.toString();
}

void main() {
  test('маленькое — сразу, с переводами строк', () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
    expect(await decodeBase64Off(_wrapped(bytes)), bytes);
  });

  test('большое — в изоляте, байты те же', () async {
    final bytes = Uint8List.fromList(List.generate(600 * 1024, (i) => (i * 31) % 256));
    final text = _wrapped(bytes);
    expect(text.length, greaterThan(256 * 1024));
    expect(await decodeBase64Off(text), bytes);
  });

  test('испорченный base64 — ошибка, как раньше', () async {
    expect(() => decodeBase64Off('не base64!'), throwsFormatException);
  });
}

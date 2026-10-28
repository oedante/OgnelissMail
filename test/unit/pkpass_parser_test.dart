// Электронный билет .pkpass: разбор pass.json, перевод строк, цвета.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/pkpass_parser.dart';

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, data) => a.addFile(ArchiveFile(name, data.length, data)));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

void main() {
  final pass = {
    'formatVersion': 1,
    'organizationName': 'Aeroflot',
    'description': 'Boarding pass',
    'foregroundColor': 'rgb(255, 255, 255)',
    'backgroundColor': 'rgb(16, 64, 128)',
    'labelColor': '#C0D0E0',
    'relevantDate': '2026-10-12T09:30:00+05:00',
    'barcodes': [
      {'format': 'PKBarcodeFormatQR', 'message': 'M1IVANOV/IVAN SU1402', 'altText': 'SU1402 12A'}
    ],
    'boardingPass': {
      'transitType': 'PKTransitTypeAir',
      'headerFields': [{'key': 'gate', 'label': 'gate', 'value': 'B12'}],
      'primaryFields': [
        {'key': 'from', 'label': 'SVX', 'value': 'Yekaterinburg'},
        {'key': 'to', 'label': 'SVO', 'value': 'Moscow'}
      ],
      'secondaryFields': [{'key': 'seat', 'label': 'seat', 'value': '12A'}],
      'auxiliaryFields': [{'key': 'boarding', 'label': 'Boarding', 'value': '2026-10-12T09:00:00Z'}],
      'backFields': [{'key': 'terms', 'label': 'Terms', 'value': 'Be on time'}],
    },
  };

  test('посадочный: поля, код, цвета, перевод', () {
    final bytes = _zip({
      'pass.json': utf8.encode(jsonEncode(pass)),
      'ru.lproj/pass.strings': utf8.encode('"gate" = "Выход";\n"seat" = "Место";\n'),
    });
    final p = PkPassParser.parse(bytes, lang: 'ru')!;
    expect(p.style, 'boardingPass');
    expect(p.organization, 'Aeroflot');
    expect(p.header.single.label, 'Выход');
    expect(p.header.single.value, 'B12');
    expect(p.primary.map((f) => f.value), ['Yekaterinburg', 'Moscow']);
    expect(p.secondary.single.label, 'Место');
    expect(p.barcodeMessage, 'M1IVANOV/IVAN SU1402');
    expect(p.barcodeFormat, 'QR');
    expect(p.barcodeAltText, 'SU1402 12A');
    expect(p.background, 0xFF104080);
    expect(p.foreground, 0xFFFFFFFF);
    expect(p.labelColor, 0xFFC0D0E0);
    expect(p.back.single.value, 'Be on time');
    expect(p.relevantDate, DateTime.utc(2026, 10, 12, 4, 30).toLocal());
    // Дата в поле — коротко, по местному времени.
    final l = DateTime.utc(2026, 10, 12, 9).toLocal();
    expect(p.auxiliary.single.value, contains('${l.hour.toString().padLeft(2, '0')}:00'));
  });

  test('UTF-16 pass.strings', () {
    final s16 = <int>[0xFF, 0xFE];
    for (final u in '"seat" = "Place";'.codeUnits) {
      s16..add(u & 0xFF)..add(u >> 8);
    }
    final p = PkPassParser.parse(_zip({'pass.json': utf8.encode(jsonEncode(pass)), 'fr.lproj/pass.strings': s16}), lang: 'fr')!;
    expect(p.secondary.single.label, 'Place');
  });

  test('не билет', () {
    expect(PkPassParser.parse(Uint8List.fromList([1, 2, 3])), isNull);
    expect(PkPassParser.parse(_zip({'readme.txt': utf8.encode('x')})), isNull);
  });

  test('цвета', () {
    expect(PkPassParser.parseColor('rgb(1,2,3)'), 0xFF010203);
    expect(PkPassParser.parseColor('#ABCDEF'), 0xFFABCDEF);
    expect(PkPassParser.parseColor('blue'), isNull);
  });
}

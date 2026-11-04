// Предпросмотр документов отключается целиком и по видам (1.11.x, просьба
// владельца 04.11.2026): выключенный вид открывается, как раньше, своей
// программой, а CSV — текстом в приложении.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/services/documents/doc_preview_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    DocPreviewSettings.load(prefs);
    dir = await Directory.systemTemp.createTemp('docprev_');
  });

  tearDown(() async {
    DocPreviewSettings.reset();
    await dir.delete(recursive: true);
  });

  Future<bool> inApp(String name, [List<int> bytes = const [0x50, 0x4B, 0x03, 0x04]]) async {
    final f = File('${dir.path}/$name')..writeAsBytesSync(bytes);
    return AttachmentPreviewScreen.opensInApp(PreviewItem(filePath: f.path, fileName: name));
  }

  test('виды документов по имени и MIME-типу, в том числе старые форматы', () {
    expect(DocPreviewSettings.typeOfName('Отчёт.docx'), DocPreviewType.text);
    expect(DocPreviewSettings.typeOfName('письмо.rtf'), DocPreviewType.text);
    expect(DocPreviewSettings.typeOfName('старый.doc'), DocPreviewType.text);
    expect(DocPreviewSettings.typeOfName('смета.xlsm'), DocPreviewType.sheets);
    expect(DocPreviewSettings.typeOfName('старая.xls'), DocPreviewType.sheets);
    expect(DocPreviewSettings.typeOfName('выгрузка.tsv'), DocPreviewType.csv);
    expect(DocPreviewSettings.typeOfName('показ.odp'), DocPreviewType.slides);
    expect(DocPreviewSettings.typeOfName('attachment', mimeType: 'text/csv'), DocPreviewType.csv);
    expect(DocPreviewSettings.typeOfName('фото.jpg'), isNull);
  });

  test('по умолчанию всё включено; настройки сохраняются и читаются снова', () async {
    expect(DocPreviewSettings.enabled, isTrue);
    expect(DocPreviewType.values.every(DocPreviewSettings.isOn), isTrue);
    await DocPreviewSettings.setType(prefs, DocPreviewType.sheets, false);
    await DocPreviewSettings.setEnabled(prefs, false);
    DocPreviewSettings.reset();
    expect(DocPreviewSettings.isOn(DocPreviewType.sheets), isTrue);
    DocPreviewSettings.load(prefs);
    expect(DocPreviewSettings.enabled, isFalse);
    expect(DocPreviewSettings.typeOn(DocPreviewType.sheets), isFalse);
    expect(DocPreviewSettings.typeOn(DocPreviewType.text), isTrue);
    expect(DocPreviewSettings.isOn(DocPreviewType.text), isFalse, reason: 'общий выключатель');
    expect(DocPreviewSettings.keys, containsAll([DocPreviewSettings.enabledKey, 'doc_preview_sheets']));
  });

  test('выключенный вид — своей программой, CSV — текстом в приложении', () async {
    expect(await inApp('договор.docx'), isTrue);
    expect(await inApp('смета.xlsx'), isTrue);
    expect(await inApp('доклад.pptx'), isTrue);
    expect(await inApp('выгрузка.csv', utf8.encode('a;b\n1;2\n')), isTrue);

    await DocPreviewSettings.setType(prefs, DocPreviewType.sheets, false);
    expect(await inApp('смета.xlsx'), isFalse);
    expect(await inApp('договор.docx'), isTrue, reason: 'другие виды остаются');

    await DocPreviewSettings.setType(prefs, DocPreviewType.csv, false);
    expect(await inApp('выгрузка.csv', utf8.encode('a;b\n1;2\n')), isTrue, reason: 'CSV — текстом, как до 1.11');

    await DocPreviewSettings.setEnabled(prefs, false);
    expect(await inApp('договор.docx'), isFalse);
    expect(await inApp('доклад.pptx'), isFalse);
  });

  test('старый .doc: RTF внутри — документом, настоящий .doc — своей программой', () async {
    expect(await inApp('письмо.doc', utf8.encode(r'{\rtf1\ansi Привет}')), isTrue);
    expect(await inApp('старый.doc', const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]), isFalse);
    await DocPreviewSettings.setType(prefs, DocPreviewType.text, false);
    expect(await inApp('письмо.doc', utf8.encode(r'{\rtf1\ansi Привет}')), isFalse);
  });
}

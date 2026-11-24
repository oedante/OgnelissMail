// Вложения: что приложение не откроет, о чём предупредит и под каким
// именем сохранит (2.7.2, внешний обзор безопасности 23.11.2026, п. 4).
// Символы направления и невидимые — кодами (\u…), не в тексте файла.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/file_opener.dart';
import 'package:ogneliss/core/security/attachment_safety.dart';

void main() {
  AttachmentRisk r(String n) => AttachmentSafety.riskOf(n);

  test('исполняемые и скрипты — не открываются', () {
    for (final n in [
      'setup.exe', 'SETUP.EXE', 'run.bat', 'x.cmd', 'x.ps1', 'x.vbs', 'x.js', 'x.hta', 'x.lnk', 'x.scr',
      'x.msi', 'x.jar', 'app.apk', 'x.reg', 'x.url', 'x.jnlp', 'x.ps1xml', 'x.appinstaller', 'x.diagcab',
      'x.ppkg', 'x.ws', 'x.msh', 'x.mde', 'x.sct', 'x.wsb',
    ]) {
      expect(r(n), AttachmentRisk.blocked, reason: n);
    }
  });

  test('двойное расширение: последнее решает', () {
    expect(r('счёт.pdf.exe'), AttachmentRisk.blocked);
    expect(r('счёт.pdf.js'), AttachmentRisk.blocked);
    expect(r('отчёт.docx.zip'), AttachmentRisk.safe);
    expect(r('отчёт.pdf.html'), AttachmentRisk.warn);
  });

  test('точки, пробелы и невидимые символы в конце не прячут расширение', () {
    expect(r('счёт.exe.'), AttachmentRisk.blocked);
    expect(r('счёт.exe  '), AttachmentRisk.blocked);
    expect(r('счёт.exe . .'), AttachmentRisk.blocked);
    expect(r('счёт.ex\u200Be'), AttachmentRisk.blocked);
    expect(r('счёт.exe\uFEFF'), AttachmentRisk.blocked);
    expect(r('счёт.exe\u0000'), AttachmentRisk.blocked);
  });

  test('символы направления текста — всегда запрет (маскировка)', () {
    for (final c in ['\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069']) {
      expect(r('doc${c}fdp.exe'), AttachmentRisk.blocked, reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
      expect(r('doc${c}xcod.pdf'), AttachmentRisk.blocked, reason: 'U+${c.codeUnitAt(0).toRadixString(16)}');
    }
  });

  test('макросы, образы дисков, HTML, сертификаты — с предупреждением', () {
    for (final n in ['план.docm', 'x.xlsm', 'disk.iso', 'x.img', 'x.vhdx', 'страница.html', 'x.svg', 'ca.cer', 'x.crt', 'x.py']) {
      expect(r(n), AttachmentRisk.warn, reason: n);
    }
  });

  test('документы и картинки — сразу', () {
    for (final n in ['акт.pdf', 'Договор.DOCX', 'фото.jpg', 'таблица.xlsx', 'архив.zip', 'без расширения']) {
      expect(r(n), AttachmentRisk.safe, reason: n);
    }
  });

  test('имя при сохранении: без путей, потоков NTFS, управляющих и невидимых символов', () {
    expect(FileOpener.safeName('../../shared_prefs/x.xml'), '_.._shared_prefs_x.xml');
    expect(FileOpener.safeName('..\\..\\Windows\\x.dll'), isNot(contains('\\')));
    expect(FileOpener.safeName('x.txt:evil.exe'), 'x.txt_evil.exe');
    expect(FileOpener.safeName('a\u0007b.pdf'), 'a_b.pdf');
    expect(FileOpener.safeName('doc\u202Efdp.exe'), 'docfdp.exe');
    expect(FileOpener.safeName('счёт.exe. . '), 'счёт.exe');
    expect(FileOpener.safeName('.hidden'), 'hidden');
    expect(FileOpener.safeName('CON.txt'), '_CON.txt');
    expect(FileOpener.safeName('nul'), '_nul');
    expect(FileOpener.safeName('com1.pdf'), '_com1.pdf');
    expect(FileOpener.safeName('console.pdf'), 'console.pdf');
    expect(FileOpener.safeName('${'а' * 200}.pdf').length, 120);
    expect(FileOpener.safeName('${'а' * 200}.pdf'), endsWith('.pdf'));
  });
}

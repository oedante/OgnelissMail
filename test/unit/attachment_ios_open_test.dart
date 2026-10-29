// Вложения на iPhone и iPad (1.8.12): что показывает «Просмотр» iOS, а что
// идёт в лист «Поделиться»; ZIP с паролем распознаётся по заголовку.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/file_opener.dart';
import 'package:ogneliss/core/security/attachment_safety.dart';

List<int> _zip({String? password}) {
  final a = Archive()..add(ArchiveFile.bytes('Расчётный листок.pdf', utf8.encode('%PDF-1.4 тест')));
  return ZipEncoder(password: password).encode(a);
}

void main() {
  test('«Просмотр» iOS: документы и картинки — да, архивы и неизвестное — нет', () {
    for (final n in ['Отчёт.PDF', 'смета.xlsx', 'фото.heic', 'запись.m4a', 'заметка.txt', 'приглашение.ics']) {
      expect(FileOpener.quickLookShows(n), isTrue, reason: n);
    }
    for (final n in [
      'Иванов Иван Иванович_Октябрь 2026 (За первую половину месяца).zip',
      'архив.rar',
      'данные.7z',
      'без расширения',
    ]) {
      expect(FileOpener.quickLookShows(n), isFalse, reason: n);
    }
  });

  test('ZIP с паролем — да, обычный ZIP и не ZIP — нет', () async {
    expect(AttachmentSafety.zipHeaderEncrypted(_zip()), isFalse);
    expect(AttachmentSafety.zipHeaderEncrypted(_zip(password: 'секрет')), isTrue);
    // ZipCrypto: тот же бит 0 флагов.
    expect(AttachmentSafety.zipHeaderEncrypted([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x09, 0x00]), isTrue);
    // Метка многотомного архива перед заголовком.
    expect(
        AttachmentSafety.zipHeaderEncrypted([0x50, 0x4B, 0x07, 0x08, 0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x01, 0x00]),
        isTrue);
    expect(AttachmentSafety.zipHeaderEncrypted(utf8.encode('%PDF-1.4')), isFalse);
    expect(AttachmentSafety.zipHeaderEncrypted(const []), isFalse);

    final dir = await Directory.systemTemp.createTemp('zip_');
    try {
      final f = File('${dir.path}/a.zip')..writeAsBytesSync(_zip(password: 'p'));
      expect(await AttachmentSafety.isEncryptedZip(f.path), isTrue);
      expect(await AttachmentSafety.isEncryptedZip('${dir.path}/нет.zip'), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

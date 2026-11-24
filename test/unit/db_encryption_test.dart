// База — только зашифрованная (2.7.2, внешний обзор безопасности
// 23.11.2026, п. 1): в выпуске библиотека без шифрования — понятная ошибка
// запуска, а не почта открытым текстом; старая открытая база переводится в
// зашифрованную без потери данных; чужой ключ — база в сторону, новая.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as s3;

void main() {
  late Directory dir;
  late File file;
  const key = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dbenc');
    file = File('${dir.path}/mail.db');
  });

  tearDown(() {
    DbEncryption.cipherProbe = DbEncryption.cipherAvailable;
    DbEncryption.requireCipher = false;
    dir.deleteSync(recursive: true);
  });

  bool plaintext(File f) => String.fromCharCodes(f.readAsBytesSync().take(15)) == 'SQLite format 3';

  test('в сборке для тестов шифрование есть (sqlite3mc)', () {
    expect(DbEncryption.cipherAvailable(), isTrue);
  });

  test('выпуск без шифрования — отказ открыть базу; отладка — без ключа, как раньше', () {
    DbEncryption.cipherProbe = () => false;
    DbEncryption.requireCipher = true;
    expect(DbEncryption.mustRefuse(), isTrue);
    expect(() => DbEncryption.prepare(file, key), throwsA(isA<DbEncryptionUnavailableException>()));
    expect('${const DbEncryptionUnavailableException()}', contains('Данные не потеряны'));

    DbEncryption.requireCipher = false;
    expect(DbEncryption.mustRefuse(), isFalse);
    expect(DbEncryption.prepare(file, key), isNull);
  });

  test('старая открытая база — шифруется на месте, данные целы', () {
    final db = s3.sqlite3.open(file.path);
    db.execute('CREATE TABLE t (v TEXT)');
    db.execute("INSERT INTO t VALUES ('письмо')");
    db.close();
    expect(plaintext(file), isTrue);

    expect(DbEncryption.prepare(file, key), key);
    expect(plaintext(file), isFalse, reason: 'на диске больше нет открытого текста');
    expect(File('${file.path}.plain-backup').existsSync(), isFalse, reason: 'открытая копия не остаётся');

    final again = s3.sqlite3.open(file.path);
    again.execute("PRAGMA key = '$key'");
    expect(again.select('SELECT v FROM t').single['v'], 'письмо');
    again.close();
  });

  test('зашифрованная база с чужим ключом — в сторону, новая база', () {
    final db = s3.sqlite3.open(file.path);
    db.execute("PRAGMA key = 'другой-ключ'");
    db.execute('CREATE TABLE t (v TEXT)');
    db.close();
    expect(DbEncryption.prepare(file, key), key);
    expect(file.existsSync(), isFalse);
    expect(dir.listSync().map((e) => e.path).any((p) => p.contains('.unreadable-')), isTrue);
  });
}

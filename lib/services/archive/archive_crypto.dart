// lib/services/archive/archive_crypto.dart
// Ключи архива Ogneliss (.ogna), 1.7.3 — по решению владельца 18.10.2026
// (docs/plan/ARCHIVE_IDEA.md, §5): пароль архива свой, не от почты, с
// возможностью восстановления.
//
// Архив шифруется случайным ключом архива (32 байта, база — SQLite3 Multiple
// Ciphers, как основная база приложения). Сам ключ хранится в заголовке
// архива в двух «конвертах»:
//  · паролем архива — PBKDF2-HMAC-SHA256 (150 000 итераций, случайная соль)
//    → ключ AES-256-GCM (подделка или неверный пароль обнаруживаются);
//  · кодом восстановления — 24 знака, показываются один раз при создании.
// Смена пароля перешифровывает только конверт — гигабайты архива не
// трогаются. На телефоне ключ архива лежит в защищённом хранилище системы:
// пароль спрашивается только при подключении архива на новом устройстве или
// после переустановки. Без пароля и без кода архив не открыть никому.

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Конверт ключа архива: соль, число итераций, вектор и шифротекст (base64).
typedef KeyEnvelope = Map<String, Object>;

abstract final class ArchiveCrypto {
  /// Итерации PBKDF2 для пароля (как у резервной копии приложения).
  static const passwordIterations = 150000;

  /// Для кода восстановления хватает меньшего: в нём 120 бит случайности.
  static const codeIterations = 20000;

  /// Буквы кода восстановления: без похожих (0/O, 1/I/L).
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static final _rnd = Random.secure();

  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rnd.nextInt(256)));

  /// Новый ключ архива.
  static Uint8List newArchiveKey() => randomBytes(32);

  static String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List unhex(String s) {
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Код восстановления: 24 знака группами по 4 («ABCD-EFGH-…»).
  static String newRecoveryCode() {
    final b = StringBuffer();
    for (var i = 0; i < 24; i++) {
      if (i > 0 && i % 4 == 0) b.write('-');
      b.write(_alphabet[_rnd.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  /// Код, как его ввели (строчные, пробелы, дефисы), → как при создании.
  /// Знаков, которых в коде нет (O, 0, I, 1, L), не бывает — они отбрасываются.
  static String normalizeCode(String input) =>
      input.toUpperCase().split('').where((c) => _alphabet.contains(c)).join();

  /// Похоже ли введённое на код восстановления (а не на пароль).
  static bool looksLikeCode(String input) => normalizeCode(input).length == 24 && input.trim().length >= 24;

  /// Ключ шифрования конверта из пароля или кода (в отдельном изоляте:
  /// 150 000 итераций — секунда-две на телефоне).
  static Future<Uint8List> kek(String secret, Uint8List salt, int iterations) => Isolate.run(() {
        final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
        return d.process(Uint8List.fromList(utf8.encode(secret)));
      });

  static Uint8List gcm(bool encrypt, Uint8List key, Uint8List iv, Uint8List data) {
    final c = GCMBlockCipher(AESEngine())..init(encrypt, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return c.process(data);
  }

  /// Положить ключ архива в конверт паролем или кодом.
  static Future<KeyEnvelope> wrap(Uint8List archiveKey, String secret, {required int iterations}) async {
    final salt = randomBytes(16);
    final iv = randomBytes(12);
    final k = await kek(secret, salt, iterations);
    final ct = gcm(true, k, iv, archiveKey);
    return {
      'salt': base64Encode(salt),
      'iter': iterations,
      'iv': base64Encode(iv),
      'ct': base64Encode(ct),
    };
  }

  /// Достать ключ архива. null — пароль (код) не подходит или конверт
  /// повреждён.
  static Future<Uint8List?> unwrap(Map<String, dynamic> env, String secret) async {
    try {
      final salt = base64Decode(env['salt'] as String);
      final iv = base64Decode(env['iv'] as String);
      final ct = base64Decode(env['ct'] as String);
      final iter = (env['iter'] as num).toInt();
      final k = await kek(secret, salt, iter);
      final key = gcm(false, k, iv, ct);
      return key.length == 32 ? key : null;
    } catch (_) {
      // Неверный пароль (проверка GCM не прошла) или повреждённый конверт.
      return null;
    }
  }
}

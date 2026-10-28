// lib/services/security/smime_service.dart
// S/MIME (подпись и шифрование писем, совместимо с Outlook):
// свой сертификат ящика (.p12/.pfx), сертификаты собеседников, настройки.
//
// Свой сертификат: файл .pfx и пароль — в защищённом хранилище телефона
// (как пароли ящиков); разобранный ключ держится в памяти до перезапуска.
// Сертификаты собеседников (открытые) запоминаются из проверенных подписей
// их писем — по ним письмо им можно зашифровать.
// Криптография — lib/services/security/cms/ (CMS, PKCS#12, RSA),
// письма — smime_mime.dart.

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'cms/cms.dart';
import 'mail_classification.dart' show MailLabel;
import 'cms/pkcs12.dart';
import 'cms/x509.dart';
import 'smime_mime.dart';

export 'cms/cms.dart' show CmsSignature;
export 'cms/pkcs12.dart' show SmimeIdentity, Pkcs12Exception;
export 'cms/x509.dart' show SmimeCert;
export 'smime_mime.dart' show SmimeOpenResult;

final smimeServiceProvider = Provider<SmimeService>(
    (ref) => SmimeService(ref.watch(secureStorageProvider), ref.watch(sharedPrefsProvider)));

/// Тяжёлые операции (RSA, разбор .pfx) — в отдельном изоляте.
Future<R> _heavy<R>(R Function() f) async {
  if (kIsWeb) return f();
  try {
    return await Isolate.run(f);
  } on UnsupportedError {
    return f();
  }
}

class SmimeService {
  final SecureStorageService _storage;
  final SharedPreferences _prefs;
  SmimeService(this._storage, this._prefs);

  final Map<String, SmimeIdentity> _identities = {};

  static String _pfxKey(String accountId) => 'smime_pfx_$accountId';
  static String _passKey(String accountId) => 'smime_pfx_pass_$accountId';

  // ─────────────────────────── свой сертификат ───────────────────────────

  /// Проверить и сохранить .pfx для ящика. Ошибка — Pkcs12Exception
  /// (code: password, nokey, unsupported, format).
  Future<SmimeCert> importPkcs12(String accountId, Uint8List pfx, String password) async {
    final id = await _heavy(() => Pkcs12.parse(pfx, password));
    await _storage.write(_pfxKey(accountId), base64.encode(pfx));
    await _storage.write(_passKey(accountId), password);
    _identities[accountId] = id;
    AppLogger.info('S/MIME: сертификат ящика — ${id.certificate.commonName}, '
        'до ${id.certificate.notAfter?.toIso8601String().substring(0, 10)}');
    return id.certificate;
  }

  /// Свой ключ и сертификат ящика (null — не загружен).
  Future<SmimeIdentity?> identity(String accountId) async {
    final cached = _identities[accountId];
    if (cached != null) return cached;
    final b64 = await _storage.read(_pfxKey(accountId));
    if (b64 == null) return null;
    final pass = await _storage.read(_passKey(accountId)) ?? '';
    try {
      final pfx = base64.decode(b64);
      final id = await _heavy(() => Pkcs12.parse(pfx, pass));
      _identities[accountId] = id;
      return id;
    } catch (e) {
      AppLogger.warning('S/MIME: сохранённый сертификат не читается — $e');
      return null;
    }
  }

  Future<SmimeCert?> certificate(String accountId) async => (await identity(accountId))?.certificate;

  Future<void> removeIdentity(String accountId) async {
    await _storage.delete(_pfxKey(accountId));
    await _storage.delete(_passKey(accountId));
    _identities.remove(accountId);
  }

  // ─────────────────────────── настройки ящика ───────────────────────────

  bool signByDefault(String accountId) => _prefs.getBool('smime_sign_$accountId') ?? false;
  bool encryptByDefault(String accountId) => _prefs.getBool('smime_encrypt_$accountId') ?? false;
  Future<void> setSignByDefault(String accountId, bool v) => _prefs.setBool('smime_sign_$accountId', v);
  Future<void> setEncryptByDefault(String accountId, bool v) => _prefs.setBool('smime_encrypt_$accountId', v);

  // ─────────────────────────── сертификаты собеседников ───────────────────────────

  static String _peerKey(String email) => 'smime_peer_${email.trim().toLowerCase()}';

  /// Запомнить сертификат собеседника (из проверенной подписи).
  Future<void> rememberPeer(SmimeCert cert) async {
    for (final e in cert.emails) {
      await _prefs.setString(_peerKey(e), base64.encode(cert.der));
    }
  }

  SmimeCert? peer(String email) {
    final b64 = _prefs.getString(_peerKey(email));
    if (b64 == null) return null;
    try {
      final c = SmimeCert.parse(base64.decode(b64));
      return c.isValidAt(DateTime.now()) ? c : null;
    } catch (_) {
      return null;
    }
  }

  /// Адреса, для которых нет сертификата (зашифровать им нельзя).
  List<String> missingPeers(Iterable<String> emails) =>
      [for (final e in emails) if (peer(e) == null) e];

  // ─────────────────────────── письма ───────────────────────────

  /// Подписать и (или) зашифровать готовое письмо [mime] (RFC 822).
  /// Шифруется для [recipients] и для себя.
  Future<Uint8List> protect(
    String accountId,
    Uint8List mime, {
    required bool sign,
    required bool encrypt,
    List<String> recipients = const [],
  }) async {
    final id = await identity(accountId);
    if (id == null) throw const CmsException('needKey', 'no certificate for this mailbox');
    final peers = <SmimeCert>[];
    if (encrypt) {
      final missing = <String>[];
      for (final r in recipients) {
        final c = peer(r);
        if (c == null) {
          missing.add(r);
        } else {
          peers.add(c);
        }
      }
      if (missing.isNotEmpty) throw CmsException('noPeer', missing.join(', '));
      peers.add(id.certificate);
    }
    return _heavy(() => SmimeMime.transformMessage(mime, (entity) {
          var e = entity;
          if (sign) e = SmimeMime.signEntity(e, id);
          if (encrypt) e = SmimeMime.encryptEntity(e, peers);
          return e;
        }));
  }

  /// Обработчик MIME для отправки по метке письма ([sensitivity], см.
  /// MailLabel): подписать и (или) зашифровать для [recipients]. null —
  /// S/MIME для письма не выбран.
  Future<Uint8List> Function(Uint8List mime)? senderFor(
      String accountId, String sensitivity, Iterable<String> recipients) {
    final l = MailLabel.decode(sensitivity);
    if (!l.smime) return null;
    final list = [for (final r in recipients) if (r.trim().isNotEmpty) r.trim()];
    return (mime) => protect(accountId, mime, sign: l.smimeSign, encrypt: l.smimeEncrypt, recipients: list);
  }

  /// Открыть S/MIME-письмо или smime.p7m: расшифровать своим ключом,
  /// проверить подпись; сертификат подписавшего запоминается.
  Future<SmimeOpenResult> open(String accountId, Uint8List data, {bool p7m = false}) async {
    final id = await identity(accountId);
    final r = await _heavy(() => p7m ? SmimeMime.openCms(data, identity: id) : SmimeMime.open(data, identity: id));
    final s = r.signature;
    if (s != null && s.valid && s.signer != null) {
      try {
        await rememberPeer(s.signer!);
      } catch (_) {}
    }
    return r;
  }
}

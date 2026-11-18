// lib/core/security/client_cert_store.dart
// Сертификаты клиента TLS (2.6.5, план владельца 17.11.2026: «клиентские
// сертификаты»): сервер Exchange, IMAP или SMTP организации требует, чтобы
// устройство предъявило свой сертификат (mTLS, «проверка подлинности по
// сертификату клиента» в IIS, обратный прокси со взаимным TLS).
//
// Сертификат с закрытым ключом — файл PKCS#12 (.p12, .pfx) с паролем:
// пользователь выбирает его в «Безопасности» и указывает домены серверов,
// для которых он нужен («corp.ru» — и все его поддомены), либо его задаёт
// организация ключами MDM client_cert_pkcs12 / client_cert_password /
// client_cert_domains. Привязка к домену, а не к ящику: сертификат нужен
// уже при добавлении ящика и в фоновой проверке почты.
//
// Файл и пароль — в защищённом хранилище (Keychain, Android Keystore,
// DPAPI, libsecret); в журнал и диагностику попадают только имя владельца
// сертификата, срок и домены. Сертификат предъявляется только серверам
// своих доменов — не всем.
//
// Подключение — NetProxy.clientContext (mail_engine): HTTPS (Exchange,
// EWS, Graph, DAV, вход — фабрика соединений приложения) и IMAP/SMTP
// (неявный TLS и STARTTLS). Форматы файла — все, что понимает BoringSSL
// Dart: ключ RSA и EC, старые файлы Windows (3DES, RC2) и новые (AES).

import 'dart:convert';
import 'dart:io' show SecurityContext, TlsException;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show listEquals, mapEquals, visibleForTesting;
import 'package:mail_engine/mail_engine.dart' show NetProxy;

import '../../services/security/cms/pkcs12.dart';
import '../../services/security/cms/x509.dart' show SmimeCert;
import '../../services/security/managed_config.dart' show ManagedPolicy;
import '../logging/app_logger.dart';
import 'secure_storage_service.dart';
import 'trusted_ca_store.dart';

/// Файл не подошёл: 'password' — неверный пароль, 'format' — не PKCS#12
/// или в нём нет ключа и сертификата.
class ClientCertException implements Exception {
  final String code;
  final String message;
  const ClientCertException(this.code, this.message);
  @override
  String toString() => message;
}

/// Сведения о сертификате клиента для экрана и журнала.
class ClientCertInfo {
  /// Отпечаток SHA-256 файла (hex) — ключ записи.
  final String id;

  /// Владелец сертификата (CN) или адрес из него.
  final String name;

  /// Издатель (CN или O).
  final String issuer;
  final DateTime? validTo;

  /// Домены серверов («corp.ru» — и поддомены).
  final List<String> domains;

  /// Задан организацией (MDM): удалить и изменить нельзя.
  final bool managed;

  const ClientCertInfo({
    required this.id,
    required this.name,
    required this.issuer,
    required this.validTo,
    required this.domains,
    this.managed = false,
  });

  bool get expired => validTo != null && validTo!.isBefore(DateTime.now());

  ClientCertInfo withDomains(List<String> d) =>
      ClientCertInfo(id: id, name: name, issuer: issuer, validTo: validTo, domains: d, managed: managed);

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'issuer': issuer,
        if (validTo != null) 'validTo': validTo!.toIso8601String(),
        'domains': domains,
      };

  static ClientCertInfo fromJson(Map<String, Object?> j, {bool managed = false}) => ClientCertInfo(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        issuer: '${j['issuer'] ?? ''}',
        validTo: DateTime.tryParse('${j['validTo'] ?? ''}'),
        domains: [for (final d in (j['domains'] as List?) ?? const []) '$d'],
        managed: managed,
      );

  @override
  String toString() => '$name (${domains.join(', ')})';
}

class _Entry {
  _Entry(this.info, this.p12, this.password);
  final ClientCertInfo info;
  final Uint8List p12;
  final String password;

  Map<String, Object?> toJson() => {...info.toJson(), 'p12': base64.encode(p12), 'pw': password};

  static _Entry? fromJson(Object? o, {bool managed = false}) {
    if (o is! Map) return null;
    try {
      final j = o.cast<String, Object?>();
      return _Entry(ClientCertInfo.fromJson(j, managed: managed), base64.decode('${j['p12']}'), '${j['pw'] ?? ''}');
    } catch (_) {
      return null;
    }
  }
}

class ClientCertStore {
  ClientCertStore._(this._storage);

  static ClientCertStore? _instance;
  static ClientCertStore? get instance => _instance;

  static const _kUser = 'client_certs_v1';
  static const _kManaged = 'client_cert_mdm_v1';

  final SecureStorageService _storage;
  List<_Entry> _user = [];
  _Entry? _managed;

  /// Контексты TLS по отпечатку (сборка — разбор PKCS#12, не на каждое
  /// соединение).
  final _contexts = <String, SecurityContext>{};

  /// Загрузить при запуске (основной и фоновый изоляты) и подключить к
  /// соединениям. Сбой хранилища — без сертификатов (как раньше).
  static Future<ClientCertStore> init(SecureStorageService storage, {ManagedPolicy? policy}) async {
    final s = ClientCertStore._(storage);
    try {
      final raw = await storage.read(_kUser);
      if (raw != null) {
        s._user = [
          for (final o in (jsonDecode(raw) as List? ?? const []))
            if (_Entry.fromJson(o) case final e?) e,
        ];
      }
      final m = await storage.read(_kManaged);
      if (m != null) s._managed = _Entry.fromJson(jsonDecode(m), managed: true);
    } catch (e) {
      AppLogger.warning('Сертификаты клиента не прочитаны: ${e.runtimeType}');
    }
    _instance = s;
    await s.applyPolicy(policy ?? ManagedPolicy.current);
    NetProxy.clientContext = s.contextFor;
    if (s.items.isNotEmpty) AppLogger.info('Сертификаты клиента: ${s.items.join('; ')}');
    return s;
  }

  /// Все сертификаты: организации — первым.
  List<ClientCertInfo> get items => [if (_managed != null) _managed!.info, for (final e in _user) e.info];

  /// Контекст TLS с сертификатом клиента для узла [host] или null.
  /// Из подходящих — с самым длинным (точным) доменом; организации — при
  /// равенстве первым.
  SecurityContext? contextFor(String host) {
    final e = _entryFor(host);
    if (e == null) return null;
    return _contexts[e.info.id] ??= buildContext(e.p12, e.password);
  }

  _Entry? _entryFor(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$|\.$'), '');
    _Entry? best;
    var bestLen = -1;
    for (final e in [if (_managed != null) _managed!, ..._user]) {
      for (final d in e.info.domains) {
        if (matches(h, d) && d.length > bestLen) {
          best = e;
          bestLen = d.length;
        }
      }
    }
    return best;
  }

  /// Сертификат для узла (экран ящика, диагностика).
  ClientCertInfo? infoFor(String host) => _entryFor(host)?.info;

  /// Добавить файл [p12] с паролем [password] для доменов [domains].
  /// Тот же файл ещё раз — замена доменов.
  Future<ClientCertInfo> importBytes(Uint8List p12, String password, List<String> domains) async {
    final info = inspect(p12, password, domains: domains);
    _user = [for (final e in _user) if (e.info.id != info.id) e, _Entry(info, p12, password)];
    _contexts.remove(info.id);
    await _saveUser();
    AppLogger.info('Сертификат клиента добавлен: $info');
    return info;
  }

  Future<void> remove(String id) async {
    _user = [for (final e in _user) if (e.info.id != id) e];
    _contexts.remove(id);
    await _saveUser();
    AppLogger.info('Сертификат клиента удалён');
  }

  Future<void> setDomains(String id, List<String> domains) async {
    _user = [
      for (final e in _user) e.info.id == id ? _Entry(e.info.withDomains(normalizeDomains(domains)), e.p12, e.password) : e,
    ];
    await _saveUser();
  }

  Future<void> _saveUser() async {
    try {
      await _storage.write(_kUser, jsonEncode([for (final e in _user) e.toJson()]));
    } catch (e) {
      AppLogger.warning('Сертификаты клиента не сохранены: ${e.runtimeType}');
    }
  }

  // ── Организация (MDM) ──

  /// Политика организации: сертификат из MDM — в защищённое хранилище (для
  /// фонового изолята: в копии политики в prefs его нет, только отпечаток).
  Future<void> applyPolicy(ManagedPolicy p) async {
    final sha = p.clientCertSha256;
    if (sha == null) {
      if (_managed != null) {
        _contexts.remove(_managed!.info.id);
        _managed = null;
        try {
          await _storage.delete(_kManaged);
        } catch (_) {}
        AppLogger.info('Сертификат клиента организации снят');
      }
      return;
    }
    final domains = normalizeDomains(_policyDomains(p));
    final b64 = p.clientCertPkcs12;
    if (b64 == null) {
      // Фон или запуск до ответа MDM: сохранённый — если отпечаток тот же.
      if (_managed != null && _managed!.info.id != sha) _managed = null;
      return;
    }
    if (_managed?.info.id == sha && listEquals(_managed!.info.domains, domains)) return;
    try {
      final bytes = base64.decode(b64);
      final info = inspect(bytes, p.clientCertPassword ?? '', domains: domains, managed: true);
      _managed = _Entry(info, bytes, p.clientCertPassword ?? '');
      _contexts.remove(info.id);
      await _storage.write(_kManaged, jsonEncode(_managed!.toJson()));
      AppLogger.info('Сертификат клиента организации: $info');
    } catch (e) {
      _managed = null;
      AppLogger.warning('Сертификат клиента организации не принят: $e');
    }
  }

  /// Домены сертификата организации: client_cert_domains или домен ящика
  /// организации и её серверы.
  static List<String> _policyDomains(ManagedPolicy p) {
    final explicit = parseDomains(p.clientCertDomains ?? '');
    if (explicit.isNotEmpty) return explicit;
    final email = p.accountEmail;
    return [
      if (email != null && email.contains('@')) email.split('@').last,
      for (final s in [p.accountServer, p.imapServer, p.smtpServer])
        if (s != null && s.trim().isNotEmpty) _hostOf(s),
    ];
  }

  static String _hostOf(String server) {
    final s = server.trim();
    final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    return (u?.host.isNotEmpty ?? false) ? u!.host : s;
  }

  // ── Разбор (проверяется тестами) ──

  /// Проверить файл и пароль, взять сведения о сертификате.
  static ClientCertInfo inspect(Uint8List p12, String password,
      {List<String> domains = const [], bool managed = false}) {
    try {
      buildContext(p12, password, withCas: false);
    } on TlsException catch (e) {
      final m = '$e'.toUpperCase();
      if (m.contains('PASSWORD') || m.contains('MAC') || m.contains('DECRYPT')) {
        throw const ClientCertException('password', 'wrong password');
      }
      throw ClientCertException('format', 'not a PKCS#12 certificate with a key: ${e.message}');
    } catch (e) {
      // Сертификат без ключа, PEM вместо PKCS#12 (ArgumentError BoringSSL).
      throw ClientCertException('format', 'not a PKCS#12 certificate with a key: ${e.runtimeType}');
    }
    var name = '';
    var issuer = '';
    DateTime? validTo;
    try {
      final certs = Pkcs12.certificates(p12, password);
      final leaf = _leaf(certs);
      if (leaf != null) {
        name = leaf.commonName;
        issuer = leaf.issuerName;
        validTo = leaf.notAfter;
      }
    } catch (_) {
      // Необычный формат, который BoringSSL принял, а свой разбор — нет:
      // без имени и срока.
    }
    return ClientCertInfo(
      id: sha256.convert(p12).toString(),
      name: name.isEmpty ? '—' : name,
      issuer: issuer,
      validTo: validTo,
      domains: normalizeDomains(domains),
      managed: managed,
    );
  }

  /// Сертификат владельца: тот, что не издал ни один другой в файле.
  static SmimeCert? _leaf(List<SmimeCert> certs) {
    for (final c in certs) {
      final issuesOther = certs.any((o) => !identical(o, c) && mapEquals(o.issuer, c.subject));
      if (!issuesOther) return c;
    }
    return certs.firstOrNull;
  }

  /// Контекст TLS: доверенные ЦС системы и приложения, сертификат и ключ
  /// из файла. Неверный пароль или формат — TlsException.
  static SecurityContext buildContext(Uint8List p12, String password, {bool withCas = true}) {
    final c = SecurityContext(withTrustedRoots: true);
    if (withCas) {
      for (final pem in TrustedCaStore.instance?.activePems ?? const <String>[]) {
        try {
          c.setTrustedCertificatesBytes(utf8.encode(pem));
        } catch (_) {
          // Уже в системном наборе.
        }
      }
    }
    c.useCertificateChainBytes(p12, password: password);
    c.usePrivateKeyBytes(p12, password: password);
    return c;
  }

  /// Узел [host] — домен [domain] или его поддомен.
  static bool matches(String host, String domain) {
    final h = host.toLowerCase();
    final d = domain.toLowerCase();
    return d.isNotEmpty && (h == d || h.endsWith('.$d'));
  }

  /// Домены из строки: через запятую, «;» или пробел; «*.corp.ru» и
  /// «https://mail.corp.ru/EWS» — тоже.
  static List<String> parseDomains(String text) => normalizeDomains(text.split(RegExp(r'[,;\s]+')));

  static List<String> normalizeDomains(Iterable<String> list) {
    final out = <String>[];
    for (var d in list) {
      d = d.trim().toLowerCase();
      if (d.isEmpty) continue;
      if (d.contains('://')) d = Uri.tryParse(d)?.host ?? d;
      d = d.replaceFirst(RegExp(r'^\*?\.'), '').replaceAll(RegExp(r'[/:].*$'), '').replaceAll(RegExp(r'\.$'), '');
      if (d.isNotEmpty && !out.contains(d)) out.add(d);
    }
    return out;
  }

  /// Домен по адресу почты: «ivanov@corp.ru» → «corp.ru».
  static String? domainOfEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    final at = e.lastIndexOf('@');
    return at > 0 && at < e.length - 1 ? e.substring(at + 1) : null;
  }

  /// Для тестов: хранилище без платформы.
  @visibleForTesting
  static void debugReset() {
    _instance = null;
    NetProxy.clientContext = null;
  }
}

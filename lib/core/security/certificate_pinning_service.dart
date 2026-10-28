// lib/core/security/certificate_pinning_service.dart
// Гибкий certificate pinning. НЕ привязан к конкретному домену:
// правила пиннинга настраиваются (домен -> список SHA-256 отпечатков),
// хранятся в SharedPreferences и могут редактироваться в настройках.
//
// Режимы:
//  - off:        принимать все сертификаты (dev / самоподписанные корп. CA)
//  - trustStore: стандартная системная проверка (по умолчанию для незнакомых хостов)
//  - pinned:     для доменов с заданными отпечатками — строгая сверка SHA-256
//
// Это даёт вариативность: одно приложение работает в любой организации,
// домен и отпечатки задаются администратором/пользователем, не зашиты в код.

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import 'trusted_ca_store.dart';

enum PinningMode { off, trustStore, pinned }

/// Правило пиннинга для домена (включая поддомены).
class PinRule {
  final String domain; // напр. example.com (включает *.example.com)
  final List<String> sha256Fingerprints; // base64 SHA-256 от DER-сертификата
  final bool includeSubdomains;

  const PinRule({
    required this.domain,
    required this.sha256Fingerprints,
    this.includeSubdomains = true,
  });

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'fingerprints': sha256Fingerprints,
        'includeSubdomains': includeSubdomains,
      };

  factory PinRule.fromJson(Map<String, dynamic> j) => PinRule(
        domain: j['domain'] as String,
        sha256Fingerprints:
            (j['fingerprints'] as List).map((e) => e.toString()).toList(),
        includeSubdomains: j['includeSubdomains'] as bool? ?? true,
      );
}

/// Сертификат, который не прошёл проверку (для диалога «доверять ли»).
class RejectedCertificate {
  final String host;
  final int port;
  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  /// base64 SHA-256 от DER — формат правил пиннинга.
  final String fingerprint;
  /// Тот же отпечаток в виде AB:CD:… — для сверки с ИТ-отделом.
  final String fingerprintHex;
  final DateTime seenAt;
  /// Отклонён из-за несовпадения с закреплённым отпечатком (возможен
  /// перехват) — такой сертификат доверять не предлагаем.
  final bool pinMismatch;

  const RejectedCertificate({
    required this.host,
    required this.port,
    required this.subject,
    required this.issuer,
    required this.validFrom,
    required this.validTo,
    required this.fingerprint,
    required this.fingerprintHex,
    required this.seenAt,
    this.pinMismatch = false,
  });

  bool get expired => DateTime.now().isAfter(validTo);
}

class CertificatePinningService {
  static const _kMode = 'cert_pinning_mode';
  static const _kRules = 'cert_pinning_rules';
  static const _kTrustedCaDomains = 'cert_trusted_ca_domains';

  final SharedPreferences _prefs;
  PinningMode _mode = PinningMode.trustStore;
  List<PinRule> _rules = [];
  // Домены, где принимаем пользовательские/самоподписанные CA (корп. сети)
  List<String> _trustedCaDomains = [];

  CertificatePinningService(this._prefs) {
    _load();
  }

  PinningMode get mode => _mode;
  List<PinRule> get rules => List.unmodifiable(_rules);
  List<String> get trustedCaDomains => List.unmodifiable(_trustedCaDomains);

  void _load() {
    final m = _prefs.getInt(_kMode);
    if (m != null) _mode = PinningMode.values[m.clamp(0, 2)];
    // «Принимать все сертификаты» в выпускаемой сборке недоступен: с ним
    // пароль домена и токены перехватываются в любой недоверенной сети
    // (гостевой Wi-Fi). Значение могло остаться от тестовой сборки или быть
    // записано в настройки извне.
    if (kReleaseMode && _mode == PinningMode.off) _mode = PinningMode.trustStore;
    final r = _prefs.getString(_kRules);
    if (r != null) {
      try {
        _rules = (jsonDecode(r) as List)
            .map((e) => PinRule.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final ca = _prefs.getStringList(_kTrustedCaDomains);
    if (ca != null) _trustedCaDomains = ca;
  }

  Future<void> setMode(PinningMode mode) async {
    if (kReleaseMode && mode == PinningMode.off) mode = PinningMode.trustStore;
    _mode = mode;
    await _prefs.setInt(_kMode, mode.index);
  }

  Future<void> setRules(List<PinRule> rules) async {
    _rules = rules;
    await _prefs.setString(
        _kRules, jsonEncode(rules.map((e) => e.toJson()).toList()));
  }

  Future<void> addRule(PinRule rule) async {
    final updated = [..._rules.where((r) => r.domain != rule.domain), rule];
    await setRules(updated);
  }

  Future<void> removeRule(String domain) async {
    await setRules(_rules.where((r) => r.domain != domain).toList());
  }

  Future<void> setTrustedCaDomains(List<String> domains) async {
    _trustedCaDomains = domains;
    await _prefs.setStringList(_kTrustedCaDomains, domains);
  }

  /// Добавить хост/домен в доверенные self-signed CA, если его ещё нет.
  /// [exactHost] — только этот хост, без поддоменов (запись «=host»).
  Future<void> ensureTrustedCaDomain(String domain, {bool exactHost = false}) async {
    final d = '${exactHost ? '=' : ''}${domain.trim().toLowerCase()}';
    if (d.isEmpty || _trustedCaDomains.contains(d)) return;
    _trustedCaDomains = [..._trustedCaDomains, d];
    await _prefs.setStringList(_kTrustedCaDomains, _trustedCaDomains);
  }

  /// Убрать хост/домен из доверенных self-signed CA.
  Future<void> removeTrustedCaDomain(String domain) async {
    final d = domain.trim().toLowerCase();
    if (!_trustedCaDomains.contains(d)) return;
    _trustedCaDomains = _trustedCaDomains.where((e) => e != d).toList();
    await _prefs.setStringList(_kTrustedCaDomains, _trustedCaDomains);
  }

  bool _domainMatches(String host, String domain, bool includeSub) {
    if (domain.startsWith('=')) return host == domain.substring(1);
    if (host == domain) return true;
    if (includeSub && host.endsWith('.$domain')) return true;
    return false;
  }

  /// Вычислить base64 SHA-256 отпечаток DER-сертификата.
  static String fingerprintOf(X509Certificate cert) {
    return base64.encode(sha256.convert(cert.der).bytes);
  }

  /// SHA-256 в виде «AB:CD:…» — так его показывают браузеры и certutil.
  static String fingerprintHexOf(List<int> der) => sha256
      .convert(der)
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');

  // Последние отклонённые сертификаты по хостам (в памяти, для диалога входа).
  final Map<String, RejectedCertificate> _rejected = {};

  void clearRejected() => _rejected.clear();

  /// Самый свежий отклонённый сертификат после [since] (вход начался тогда),
  /// только среди [hosts], если они заданы (фоновая синхронизация других
  /// ящиков и autodiscover не должны подменять причину отказа входа).
  RejectedCertificate? lastRejected({DateTime? since, Iterable<String>? hosts}) {
    final only = hosts?.map((h) => h.toLowerCase()).toSet();
    RejectedCertificate? best;
    for (final r in _rejected.values) {
      if (since != null && r.seenAt.isBefore(since)) continue;
      if (only != null && only.isNotEmpty && !only.contains(r.host)) continue;
      if (best == null || r.seenAt.isAfter(best.seenAt)) best = r;
    }
    return best;
  }

  void _remember(_CertInfo cert, String host, int port, {bool pinMismatch = false}) {
    _rejected[host.toLowerCase()] = RejectedCertificate(
      host: host.toLowerCase(),
      port: port,
      subject: cert.subject,
      issuer: cert.issuer,
      validFrom: cert.validFrom,
      validTo: cert.validTo,
      fingerprint: cert.fingerprint,
      fingerprintHex: fingerprintHexOf(cert.der),
      seenAt: DateTime.now(),
      pinMismatch: pinMismatch,
    );
  }

  /// Доверять ИМЕННО этому сертификату на ИМЕННО этом хосте (без поддоменов).
  /// В отличие от «доверенного домена» (принимает любой сертификат) подмена
  /// сертификата при перехвате трафика сюда не пройдёт: отпечаток не совпадёт.
  /// Сервер сменит сертификат — пользователь увидит тот же диалог снова.
  Future<void> trustCertificate(RejectedCertificate c) async {
    final domain = '=${c.host}';
    final existing = _rules.where((r) => r.domain == domain).expand((r) => r.sha256Fingerprints);
    await addRule(PinRule(
      domain: domain,
      sha256Fingerprints: {...existing, c.fingerprint}.toList(),
      includeSubdomains: false,
    ));
    _rejected.remove(c.host);
    AppLogger.warning('Сертификат ${c.host} принят пользователем по отпечатку ${c.fingerprintHex}');
  }

  /// Основной callback для HttpClient.badCertificateCallback (вызывается,
  /// только если сертификат НЕ прошёл системную проверку).
  /// Возвращает true, если сертификат следует принять.
  bool evaluate(X509Certificate cert, String host, int port) {
    // ЦС Минцифры, включённый для ящика этого хоста: сертификат выпущен им
    // (подпись, сроки, имя хоста). Правило с отпечатками для хоста главнее —
    // его проверяет _evaluateInfo.
    if (_mode != PinningMode.off &&
        !_hasRuleFor(host) &&
        (TrustedCaStore.instance?.acceptsByMincifry(cert.der, host) ?? false)) {
      return true;
    }
    return _evaluateInfo(_CertInfo(cert.der, cert.subject, cert.issuer,
        cert.startValidity, cert.endValidity), host, port);
  }

  bool _hasRuleFor(String rawHost) {
    final host = rawHost.toLowerCase();
    return _rules.any((r) => _domainMatches(host, r.domain, r.includeSubdomains));
  }

  /// То же для сертификата, отклонённого сетевым стеком Android (режим
  /// совместимости со шлюзом): решение уже принято на стороне Kotlin по
  /// [nativeTrustFor], здесь — запись отказа для диалога «Доверять?».
  bool evaluateDer({
    required List<int> der,
    required String subject,
    required String issuer,
    required DateTime validFrom,
    required DateTime validTo,
    required String host,
    required int port,
  }) =>
      _evaluateInfo(_CertInfo(der, subject, issuer, validFrom, validTo), host, port);

  /// Что сетевой стек Android может принять сверх системной проверки для
  /// [host]: отпечатки (base64 SHA-256) из правил хоста и признак «любой
  /// сертификат» (доверенный корпоративный домен; режим «принимать все» в
  /// отладочной сборке). Логика та же, что в [evaluate].
  ({List<String> fingerprints, bool acceptAny}) nativeTrustFor(String rawHost) {
    final host = rawHost.toLowerCase();
    if (_mode == PinningMode.off && !kReleaseMode) {
      return (fingerprints: const <String>[], acceptAny: true);
    }
    final fps = <String>{};
    var anyRule = false;
    for (final rule in _rules) {
      if (!_domainMatches(host, rule.domain, rule.includeSubdomains)) continue;
      anyRule = true;
      fps.addAll(rule.sha256Fingerprints);
    }
    if (anyRule) return (fingerprints: fps.toList(), acceptAny: false);
    final trustedDomain = _trustedCaDomains.any((d) => _domainMatches(host, d, true));
    return (fingerprints: const <String>[], acceptAny: trustedDomain);
  }

  bool _evaluateInfo(_CertInfo cert, String host, int port) {
    final byRule = _mode == PinningMode.off ? null : _matchRule(cert, host);
    final ok = _evaluate(host, byRule);
    if (!ok) _remember(cert, host, port, pinMismatch: byRule == false);
    return ok;
  }

  /// Правила с отпечатками для хоста: null — правил нет; true — сертификат
  /// есть в КАЖДОМ подходящем правиле. Правило администратора для домена
  /// не перекрывается правилом пользователя для отдельного хоста.
  bool? _matchRule(_CertInfo cert, String rawHost) {
    final host = rawHost.toLowerCase();
    String? fp;
    bool? result;
    for (final rule in _rules) {
      if (!_domainMatches(host, rule.domain, rule.includeSubdomains)) continue;
      fp ??= cert.fingerprint;
      if (!rule.sha256Fingerprints.contains(fp)) {
        AppLogger.warning(
            'Cert pinning MISMATCH для $host: получен $fp, ожидался один из ${rule.sha256Fingerprints}');
        return false;
      }
      result = true;
    }
    return result;
  }

  bool _evaluate(String host, bool? byRule) {
    switch (_mode) {
      case PinningMode.off:
        if (kReleaseMode) return false; // в выпускаемой сборке не бывает
        return true; // принимаем всё (отладка)
      case PinningMode.trustStore:
        // Сертификат, принятый пользователем по отпечатку для этого хоста.
        if (byRule != null) return byRule;
        // Для доверенных корп. доменов — принимаем (user CA уже в системе),
        // для остальных badCertificateCallback вызывается только при ошибке
        // проверки, поэтому здесь — отказ (стандартная строгая проверка).
        for (final d in _trustedCaDomains) {
          if (_domainMatches(host, d, true)) return true;
        }
        return false;
      case PinningMode.pinned:
        // Правило для хоста
        if (byRule != null) return byRule;
        // Нет правила для хоста — доверяем системному стору / trustedCa
        for (final d in _trustedCaDomains) {
          if (_domainMatches(host, d, true)) return true;
        }
        return false;
    }
  }
}

/// Данные сертификата, общие для dart:io и сетевого стека Android.
class _CertInfo {
  final List<int> der;
  final String subject;
  final String issuer;
  final DateTime validFrom;
  final DateTime validTo;
  _CertInfo(this.der, this.subject, this.issuer, this.validFrom, this.validTo);
  late final String fingerprint = base64.encode(sha256.convert(der).bytes);
}

final certPinningProvider = Provider<CertificatePinningService>((ref) {
  throw UnimplementedError('Override in main.dart with SharedPreferences');
});

// lib/core/security/trusted_ca_store.dart
// Дополнительные корневые/промежуточные центры сертификации (ЦС), которым
// доверяет приложение помимо системного хранилища:
//
//  · встроенные сертификаты Минцифры («Russian Trusted Root CA» и два
//    выпускающих «Russian Trusted Sub CA») — включаются для отдельных
//    ящиков (настройки ящика) или для всех серверов (общий переключатель,
//    по умолчанию выключен). Для ящика ЦС НЕ попадает в общее хранилище:
//    сертификат его сервера проверяется по подписи ЦС (CaChainVerifier);
//  · сертификаты ЦС, установленные на устройство (Настройки Android →
//    Безопасность → Шифрование и учётные данные) — требование ИБ ставить ЦС
//    на устройство. Сетевой стек Android доверяет им сам (network security
//    config), а Dart (BoringSSL) системное хранилище пользователя не читает —
//    поэтому они передаются в Dart явно;
//  · сертификаты ЦС, импортированные в приложение из файла (.cer/.crt/.pem).
//
// Сертификаты ЦС публичны (не секрет), поэтому хранятся в SharedPreferences.
// Действуют для всех подключений: EAS/EWS (dart:io и сетевой стек Android),
// IMAP/SMTP, OAuth, CalDAV/CardDAV.
//
// dart:io: сертификаты добавляются в SecurityContext.defaultContext. Удалить
// из него сертификат нельзя — выключение/удаление вступает в силу после
// перезапуска приложения (экран об этом предупреждает).

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SecurityContext, TlsException;
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart' show X509Utils;
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import 'ca_chain_verifier.dart';

/// Сведения о сертификате ЦС для экрана настроек.
class CaCertInfo {
  final Uint8List der;
  final String commonName;
  final String organization;
  final DateTime? validTo;

  /// SHA-256 в hex с двоеточиями (как в свойствах сертификата Windows/Android).
  final String fingerprint;

  const CaCertInfo({
    required this.der,
    required this.commonName,
    required this.organization,
    required this.validTo,
    required this.fingerprint,
  });

  bool get expired => validTo != null && DateTime.now().isAfter(validTo!);

  String get pem => TrustedCaStore.toPem(der);
}

class TrustedCaStore {
  TrustedCaStore._(this._prefs);

  static TrustedCaStore? _instance;
  static TrustedCaStore? get instance => _instance;

  final SharedPreferences _prefs;

  static const _kBundled = 'ca_bundled_mincifry';
  static const _kDevice = 'ca_device_user';
  static const _kImported = 'ca_imported_pem';

  /// Встроенные сертификаты Минцифры и их ожидаемые отпечатки SHA-256: если
  /// файл в сборке подменён, он не будет загружен.
  static const bundledAssets = <String, String>{
    'assets/certs/russian_trusted_root_ca.pem':
        'D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31',
    'assets/certs/russian_trusted_sub_ca.pem':
        'BB:BD:E2:10:3E:79:0B:99:9E:C6:2B:D0:3C:F6:25:A5:A2:E7:C3:16:E1:0A:FE:6A:49:0E:ED:EA:D8:B3:FD:9B',
    'assets/certs/russian_trusted_sub_ca_2024.pem':
        '21:55:78:50:36:C9:00:DB:B5:F1:BB:2A:15:69:C8:0C:55:59:5B:D6:BF:94:86:7A:29:BB:DD:BC:7D:88:A3:F2',
  };

  static const _native = MethodChannel('ogneliss/native_http');

  List<CaCertInfo> _bundled = const [];
  List<CaCertInfo> _device = const [];
  List<CaCertInfo> _imported = const [];

  /// Отпечатки, уже добавленные в SecurityContext.defaultContext (повторное
  /// добавление BoringSSL отвергает ошибкой).
  static final Set<String> _inDefaultContext = {};

  /// ЦС Минцифры «для всех серверов» (общий переключатель в «Защите»).
  /// По умолчанию выключен: тогда ЦС действует только для ящиков, где он
  /// включён в настройках ящика (см. [trustsMincifryFor]), и не становится
  /// доверенным для Google, Microsoft и остальных.
  bool get bundledEnabled => _prefs.getBool(_kBundled) ?? false;
  bool get deviceEnabled => _prefs.getBool(_kDevice) ?? true;

  List<CaCertInfo> get bundled => _bundled;
  List<CaCertInfo> get device => _device;
  List<CaCertInfo> get imported => _imported;

  /// Сертификаты, действующие сейчас (для сетевого стека Android передаются
  /// только встроенные и импортированные: установленным на устройство он
  /// доверяет сам).
  List<Uint8List> get extraForNative => [
        if (bundledEnabled) ..._bundled.map((c) => c.der),
        ..._imported.map((c) => c.der),
      ];

  /// То же для конкретного хоста: ЦС Минцифры — если он включён для ящика,
  /// которому принадлежит хост.
  List<Uint8List> extraForNativeHost(String host) => [
        if (trustsMincifryFor(host)) ..._bundled.map((c) => c.der),
        ..._imported.map((c) => c.der),
      ];

  // ───────────────────── ЦС Минцифры по ящикам ─────────────────────

  static String _accKey(String accountId) => 'ca_mincifry_acc_$accountId';

  /// Включён ли ЦС Минцифры для ящика.
  bool mincifryForAccount(String accountId) => _prefs.getBool(_accKey(accountId)) ?? false;

  Future<void> setMincifryForAccount(String accountId, bool v) async {
    await _prefs.setBool(_accKey(accountId), v);
    _rebuildHosts();
  }

  /// Хосты ящиков: id → (сервера ящика, домен адреса).
  Map<String, ({Set<String> hosts, String? domain})> _accountHosts = const {};

  /// Хосты и домены, для которых сейчас действует ЦС Минцифры.
  Set<String> _mincifryHosts = const {};
  Set<String> _mincifryDomains = const {};

  /// Идёт настройка нового ящика с включённым ЦС Минцифры (экран входа):
  /// адресов сервера ещё нет, поэтому доверие — на время настройки, а
  /// созданный ящик получает флаг (см. [syncAccounts]).
  bool setupTrust = false;
  Set<String>? _knownAccounts;

  /// Передать текущий список ящиков (при запуске и при каждом изменении).
  /// Хост ящика — серверы IMAP/SMTP, Exchange, EWS и любой адрес в домене
  /// почты (автообнаружение, CalDAV/CardDAV, OWA).
  void syncAccounts(List<({String id, Set<String> hosts, String email, bool oauth})> accounts) {
    final map = <String, ({Set<String> hosts, String? domain})>{};
    for (final a in accounts) {
      final at = a.email.lastIndexOf('@');
      final domain = at > 0 ? a.email.substring(at + 1).toLowerCase().trim() : null;
      map[a.id] = (
        hosts: {for (final h in a.hosts) if (_hostOf(h) case final x?) x},
        domain: (domain == null || domain.isEmpty) ? null : domain,
      );
    }
    // Новый ящик, созданный при включённом переключателе на экране входа.
    final known = _knownAccounts;
    if (known != null && setupTrust) {
      var added = false;
      for (final a in accounts) {
        final id = a.id;
        // Ящики Google, Яндекса, Mail.ru (OAuth) — на мировых ЦС; флаг им
        // не нужен и расширил бы доверие на весь домен gmail.com и т. п.
        if (a.oauth) continue;
        if (!known.contains(id)) {
          unawaited(_prefs.setBool(_accKey(id), true));
          added = true;
        }
      }
      // Доверие «на время настройки» — только до появления ящика.
      if (added) setupTrust = false;
    }
    _knownAccounts = map.keys.toSet();
    _accountHosts = map;
    _rebuildHosts();
  }

  void _rebuildHosts() {
    final hosts = <String>{};
    final domains = <String>{};
    for (final e in _accountHosts.entries) {
      if (!mincifryForAccount(e.key)) continue;
      hosts.addAll(e.value.hosts);
      if (e.value.domain != null) domains.add(e.value.domain!);
    }
    _mincifryHosts = hosts;
    _mincifryDomains = domains;
  }

  /// «mail.corp.ru», «https://mail.corp.ru/EWS/Exchange.asmx», «mail.corp.ru:443» → хост.
  static String? _hostOf(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('://')) {
      s = Uri.tryParse(s)?.host ?? '';
    } else {
      s = s.split('/').first.split(':').first;
    }
    return s.isEmpty ? null : s;
  }

  /// Действует ли ЦС Минцифры для [host].
  bool trustsMincifryFor(String host) {
    if (bundledEnabled || setupTrust) return true;
    final h = host.toLowerCase();
    if (_mincifryHosts.contains(h)) return true;
    for (final d in _mincifryDomains) {
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  /// Сертификат, отвергнутый общей проверкой (ЦС Минцифры в общем хранилище
  /// нет), выпущен ЦС Минцифры, и для хоста он включён? Проверяются подпись,
  /// сроки и имя хоста (ca_chain_verifier.dart).
  bool acceptsByMincifry(Uint8List der, String host) {
    if (_bundled.isEmpty || !trustsMincifryFor(host)) return false;
    final ok = CaChainVerifier.verify(
      leafDer: der,
      issuers: [for (final c in _bundled) c.der],
      host: host,
    );
    if (ok) AppLogger.debug('Сертификат $host принят: выпущен ЦС Минцифры (включён для ящика)');
    return ok;
  }

  /// Создать и применить при запуске — до первого сетевого запроса.
  static Future<TrustedCaStore> init(SharedPreferences prefs) async {
    final s = TrustedCaStore._(prefs);
    _instance = s;
    await s._loadBundled();
    s._imported = [
      for (final pem in prefs.getStringList(_kImported) ?? const <String>[])
        if (parse(utf8.encode(pem)) case final c?) c,
    ];
    if (s.deviceEnabled) await s._loadDevice();
    s._applyToDart();
    return s;
  }

  Future<void> _loadBundled() async {
    final out = <CaCertInfo>[];
    for (final e in bundledAssets.entries) {
      try {
        final data = await rootBundle.load(e.key);
        final c = parse(data.buffer.asUint8List());
        if (c == null) continue;
        if (c.fingerprint != e.value) {
          AppLogger.warning('Встроенный сертификат ${e.key}: отпечаток не совпал — не загружен');
          continue;
        }
        out.add(c);
      } catch (err) {
        AppLogger.warning('Встроенный сертификат ${e.key}: $err');
      }
    }
    _bundled = out;
  }

  /// Пользовательские ЦС из хранилища Android (AndroidCAStore, «user:…»).
  Future<void> _loadDevice() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final list = await _native.invokeListMethod<Uint8List>('deviceUserCas') ?? const [];
      _device = [
        for (final der in list)
          if (parse(der) case final c?) c,
      ];
      if (_device.isNotEmpty) {
        AppLogger.info('ЦС, установленные на устройство: ${_device.length}');
      }
    } catch (e) {
      AppLogger.warning('ЦС устройства недоступны: $e');
    }
  }

  void _applyToDart() {
    final all = <CaCertInfo>[
      if (bundledEnabled) ..._bundled,
      if (deviceEnabled) ..._device,
      ..._imported,
    ];
    for (final c in all) {
      if (!_inDefaultContext.add(c.fingerprint)) continue;
      try {
        SecurityContext.defaultContext.setTrustedCertificatesBytes(utf8.encode(c.pem));
      } on TlsException catch (e) {
        // Уже есть в системном наборе — не ошибка.
        AppLogger.debug('ЦС ${c.commonName}: $e');
      } catch (e) {
        AppLogger.warning('ЦС ${c.commonName} не добавлен: $e');
      }
    }
  }

  Future<void> setBundledEnabled(bool v) async {
    await _prefs.setBool(_kBundled, v);
    _applyToDart();
  }

  Future<void> setDeviceEnabled(bool v) async {
    await _prefs.setBool(_kDevice, v);
    if (v) {
      await _loadDevice();
      _applyToDart();
    }
  }

  /// Перечитать ЦС устройства (после установки сертификата в настройках).
  Future<void> reloadDevice() async {
    if (!deviceEnabled) return;
    await _loadDevice();
    _applyToDart();
  }

  /// Импорт из файла (.cer/.crt — DER или PEM; в PEM может быть цепочка).
  /// Возвращает добавленные сертификаты; пусто — сертификатов нет или все
  /// уже были импортированы.
  Future<List<CaCertInfo>> importBytes(Uint8List bytes) async {
    final found = <CaCertInfo>[];
    final text = _tryLatin1(bytes);
    final blocks = RegExp(r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----')
        .allMatches(text ?? '')
        .map((m) => m.group(0)!)
        .toList();
    final candidates = blocks.isEmpty ? [bytes] : [for (final b in blocks) utf8.encode(b)];
    for (final c in candidates) {
      final info = parse(Uint8List.fromList(c));
      if (info == null) continue;
      if (_imported.any((x) => x.fingerprint == info.fingerprint)) continue;
      found.add(info);
    }
    if (found.isEmpty) return found;
    _imported = [..._imported, ...found];
    await _prefs.setStringList(_kImported, [for (final c in _imported) c.pem]);
    _applyToDart();
    return found;
  }

  Future<void> removeImported(String fingerprint) async {
    _imported = _imported.where((c) => c.fingerprint != fingerprint).toList();
    await _prefs.setStringList(_kImported, [for (final c in _imported) c.pem]);
  }

  // ───────────────────────── разбор ─────────────────────────

  static String? _tryLatin1(Uint8List b) {
    try {
      return latin1.decode(b);
    } catch (_) {
      return null;
    }
  }

  static String toPem(Uint8List der) {
    final b64 = base64.encode(der);
    final lines = <String>[];
    for (var i = 0; i < b64.length; i += 64) {
      lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
    }
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
  }

  /// PEM или DER → сведения о сертификате. null — не сертификат X.509.
  static CaCertInfo? parse(List<int> bytes) {
    try {
      Uint8List der;
      final text = _tryLatin1(Uint8List.fromList(bytes)) ?? '';
      final m = RegExp(r'-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----')
          .firstMatch(text);
      if (m != null) {
        der = base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      } else {
        der = Uint8List.fromList(bytes);
      }
      final data = X509Utils.x509CertificateFromPem(toPem(der));
      final subject = data.tbsCertificate?.subject ?? const <String, String?>{};
      final hex = sha256
          .convert(der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(':');
      return CaCertInfo(
        der: der,
        commonName: subject['2.5.4.3'] ?? subject['CN'] ?? '—',
        organization: subject['2.5.4.10'] ?? subject['O'] ?? '',
        validTo: data.tbsCertificate?.validity.notAfter,
        fingerprint: hex,
      );
    } catch (e) {
      AppLogger.debug('Не сертификат X.509: $e');
      return null;
    }
  }
}

// lib/core/network/system_proxy.dart
// Какой прокси нужен почтовому серверу (2.6.5, план 08.11.2026 п. 1:
// «в корпоративном Wi-Fi с обязательным прокси EAS/EWS/IMAP не работают»).
//
// Порядок, как у Outlook и браузеров:
//  1. MDM: ключи http_proxy и proxy_bypass (ИТ-служба задаёт прокси явно)
//     или pac_url (сценарий PAC; выполняет система, кроме Android и Linux);
//  2. настройки системы, включая PAC и автообнаружение (WPAD):
//     Android — ProxySelector (прокси сети и PAC), iPhone и Mac — CFNetwork
//     (плагин ogneliss_native_http, метод proxyFor), Windows — WinHTTP
//     ([WindowsProxy]); на Linux — настройки GNOME (ручной прокси);
//  3. переменные окружения https_proxy / http_proxy / no_proxy (Linux,
//     запуск из терминала).
// Соединения через прокси — туннель CONNECT (NetProxy в mail_engine):
// HTTPS (Exchange, EWS, Graph, DAV, вход) и IMAP/SMTP.
//
// Ответ на узел запоминается на 2 минуты: PAC и WPAD на Windows считаются
// секунды, а синхронизация открывает соединения часто. Решение по узлу —
// в журнал один раз (без адресов почты: только узел сервера и прокси).

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:mail_engine/mail_engine.dart' show NetProxy, ProxyHop;

import '../../services/security/managed_config.dart' show ManagedPolicy;
import '../logging/app_logger.dart';
import 'windows_proxy.dart';

class SystemProxy {
  SystemProxy._();

  static const _ch = MethodChannel('ogneliss/native_http');
  static const _ttl = Duration(minutes: 2);
  static final _cache = <String, (ProxyHop?, String, DateTime)>{};
  static final _logged = <String>{};

  /// Подключить к движку (основной и фоновый изоляты).
  static void install() {
    NetProxy.lookup = lookup;
    NetProxy.onNote = (m) {
      if (_logged.add(m)) AppLogger.info(m);
    };
  }

  /// Забыть ответы (сменилась сеть или политика MDM).
  static void reset() {
    _cache.clear();
    NetProxy.resetFailures();
  }

  /// Последние решения для диагностики: «узел → прокси (откуда)».
  static List<String> summary() => [
        for (final e in _cache.entries) '${e.key} → ${e.value.$1 ?? 'напрямую'} (${e.value.$2})',
      ];

  static Future<ProxyHop?> lookup(String host, int port, {required bool secure}) async {
    final key = '$host:$port';
    final c = _cache[key];
    if (c != null && DateTime.now().difference(c.$3) < _ttl) return c.$1;
    final (hop, source) = await _resolve(host, port, secure: secure);
    _cache[key] = (hop, source, DateTime.now());
    if (_logged.add('$key|$hop')) {
      AppLogger.info('Прокси для $key: ${hop ?? 'напрямую'} ($source)');
    }
    return hop;
  }

  static Future<(ProxyHop?, String)> _resolve(String host, int port, {required bool secure}) async {
    final policy = ManagedPolicy.current;
    final mdm = parseProxy(policy.httpProxy);
    if (mdm != null) {
      return bypassed(host, policy.proxyBypass) ? (null, 'MDM, исключение') : (mdm, 'MDM');
    }
    final url = '${secure ? 'https' : 'http'}://$host:$port/';
    // Сценарий PAC организации (MDM pac_url): выполняет система — iPhone,
    // iPad, Mac и Windows. На Android PAC задаёт политика устройства, и он
    // приходит как прокси системы.
    final pac = policy.pacUrl;
    final orgPac = pac != null && !Platform.isAndroid && !Platform.isLinux;
    try {
      if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
        final list = await _ch.invokeListMethod<Object?>('proxyFor', {'url': url, if (orgPac) 'pac': pac});
        return (firstHop(list), orgPac ? 'MDM PAC' : 'система');
      }
      if (Platform.isWindows) {
        return (await WindowsProxy.forUrl(url, secure: secure, pacUrl: orgPac ? pac : null), orgPac ? 'MDM PAC' : 'Windows');
      }
    } on MissingPluginException {
      // Сборка без плагина (тесты) — дальше, к переменным окружения.
    } catch (e) {
      return (null, 'система: ${e.runtimeType}');
    }
    final env = fromEnvironment(Platform.environment, host, secure: secure);
    if (env != null) return (env, 'переменные окружения');
    if (Platform.isLinux) {
      final g = await _gnome();
      if (g != null && !bypassed(host, g.bypass)) return (g.hop, 'GNOME');
    }
    return (null, 'нет прокси');
  }

  // ── Linux: прокси GNOME (ручной режим) ──

  static Future<({ProxyHop hop, String bypass})?>? _gnomeOnce;

  static Future<({ProxyHop hop, String bypass})?> _gnome() => _gnomeOnce ??= () async {
        Future<String> get(String schema, String key) async {
          final r = await Process.run('gsettings', ['get', schema, key]).timeout(const Duration(seconds: 2));
          return '${r.stdout}'.trim().replaceAll("'", '');
        }

        try {
          if (await get('org.gnome.system.proxy', 'mode') != 'manual') return null;
          final host = await get('org.gnome.system.proxy.https', 'host');
          final port = int.tryParse(await get('org.gnome.system.proxy.https', 'port')) ?? 0;
          if (host.isEmpty || port <= 0) return null;
          final ignore = (await get('org.gnome.system.proxy', 'ignore-hosts')).replaceAll(RegExp(r'[\[\]]'), '');
          return (hop: ProxyHop(host, port), bypass: ignore);
        } catch (_) {
          return null;
        }
      }();

  // ── Разбор (проверяется тестами) ──

  /// «узел:порт», «http://узел:порт», «логин:пароль@узел:порт» → прокси.
  static ProxyHop? parseProxy(String? value) {
    var v = (value ?? '').trim();
    if (v.isEmpty) return null;
    v = v.replaceFirst(RegExp(r'^[a-z]+://', caseSensitive: false), '');
    v = v.split('/').first;
    String? creds;
    final at = v.lastIndexOf('@');
    if (at > 0) {
      creds = Uri.decodeComponent(v.substring(0, at));
      v = v.substring(at + 1);
    }
    final colon = v.lastIndexOf(':');
    if (colon <= 0 || v.endsWith(']')) return v.isEmpty ? null : ProxyHop(v, 8080, credentials: creds);
    final port = int.tryParse(v.substring(colon + 1));
    final host = v.substring(0, colon).replaceAll(RegExp(r'^\[|\]$'), '');
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return ProxyHop(host, port, credentials: creds);
  }

  /// Узел [host] — в списке исключений [list] (через «,», «;» или пробел):
  /// «*.corp.local», «.corp.local», «corp.local» (и его поддомены), «10.*»,
  /// «10.0.0.0/8», «<local>» — имена без точки.
  static bool bypassed(String host, String? list) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    for (var p in (list ?? '').toLowerCase().split(RegExp(r'[,;\s]+'))) {
      p = p.trim();
      if (p.isEmpty) continue;
      if (p == '<local>') {
        if (!h.contains('.') && !h.contains(':')) return true;
        continue;
      }
      if (p == '*') return true;
      if (p.contains('/')) {
        if (_inCidr(h, p)) return true;
        continue;
      }
      if (p.contains('*')) {
        final re = RegExp('^${RegExp.escape(p).replaceAll(r'\*', '.*')}\$');
        if (re.hasMatch(h)) return true;
        continue;
      }
      final d = p.startsWith('.') ? p.substring(1) : p;
      if (h == d || h.endsWith('.$d')) return true;
    }
    return false;
  }

  static bool _inCidr(String host, String cidr) {
    final parts = cidr.split('/');
    final bits = int.tryParse(parts.length == 2 ? parts[1] : '');
    final net = _ipv4(parts.first);
    final ip = _ipv4(host);
    if (bits == null || net == null || ip == null || bits < 0 || bits > 32) return false;
    final mask = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    return (ip & mask) == (net & mask);
  }

  static int? _ipv4(String s) {
    final p = s.split('.');
    if (p.length != 4) return null;
    var v = 0;
    for (final x in p) {
      final n = int.tryParse(x);
      if (n == null || n < 0 || n > 255) return null;
      v = (v << 8) | n;
    }
    return v;
  }

  /// Первый HTTP-прокси из ответа системы (список {type, host, port});
  /// первым стоит «напрямую» — без прокси.
  @visibleForTesting
  static ProxyHop? firstHop(List<Object?>? list) {
    for (final e in list ?? const <Object?>[]) {
      if (e is! Map) continue;
      final type = '${e['type'] ?? ''}'.toUpperCase();
      if (type == 'DIRECT') return null;
      if (type != 'HTTP' && type != 'HTTPS') continue;
      final host = '${e['host'] ?? ''}';
      final port = e['port'] is int ? e['port'] as int : int.tryParse('${e['port']}');
      if (host.isNotEmpty && port != null && port > 0) return ProxyHop(host, port);
    }
    return null;
  }

  /// Прокси из переменных окружения: https_proxy (для шифрованных),
  /// http_proxy, all_proxy; no_proxy — исключения.
  @visibleForTesting
  static ProxyHop? fromEnvironment(Map<String, String> env, String host, {required bool secure}) {
    String? get(String k) {
      final v = env[k] ?? env[k.toUpperCase()];
      return (v == null || v.trim().isEmpty) ? null : v;
    }

    if (bypassed(host, get('no_proxy'))) return null;
    final v = (secure ? get('https_proxy') : null) ?? get('http_proxy') ?? get('all_proxy');
    // SOCKS-прокси туннель CONNECT не понимает.
    if (v != null && v.trim().toLowerCase().startsWith('socks')) return null;
    return parseProxy(v);
  }
}

// lib/core/network/windows_proxy.dart
// Прокси Windows для почтовых серверов (2.6.5): как у Edge и Outlook —
// настройки «Прокси» пользователя (WinHttpGetIEProxyConfigForCurrentUser):
// автообнаружение (WPAD), сценарий автонастройки (PAC) и ручной прокси с
// исключениями. PAC и WPAD выполняет сама Windows (WinHttpGetProxyForUrl),
// без своего движка JavaScript. Вызовы WinHTTP блокируют поток (WPAD —
// секунды), поэтому — в отдельном изоляте.
//
// Только dart:ffi к winhttp.dll и kernel32.dll — без нативного кода в
// сборке Windows и без новых зависимостей (пакет ffi уже подключён).

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mail_engine/mail_engine.dart' show ProxyHop;

import 'system_proxy.dart';

final class _IeProxyConfig extends Struct {
  @Int32()
  external int fAutoDetect;
  external Pointer<Utf16> lpszAutoConfigUrl;
  external Pointer<Utf16> lpszProxy;
  external Pointer<Utf16> lpszProxyBypass;
}

final class _AutoProxyOptions extends Struct {
  @Uint32()
  external int dwFlags;
  @Uint32()
  external int dwAutoDetectFlags;
  external Pointer<Utf16> lpszAutoConfigUrl;
  external Pointer<Void> lpvReserved;
  @Uint32()
  external int dwReserved;
  @Int32()
  external int fAutoLogonIfChallenged;
}

final class _ProxyInfo extends Struct {
  @Uint32()
  external int dwAccessType;
  external Pointer<Utf16> lpszProxy;
  external Pointer<Utf16> lpszProxyBypass;
}

typedef _GetIeNative = Int32 Function(Pointer<_IeProxyConfig>);
typedef _GetIe = int Function(Pointer<_IeProxyConfig>);
typedef _OpenNative = IntPtr Function(Pointer<Utf16>, Uint32, Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _Open = int Function(Pointer<Utf16>, int, Pointer<Utf16>, Pointer<Utf16>, int);
typedef _ForUrlNative = Int32 Function(IntPtr, Pointer<Utf16>, Pointer<_AutoProxyOptions>, Pointer<_ProxyInfo>);
typedef _ForUrl = int Function(int, Pointer<Utf16>, Pointer<_AutoProxyOptions>, Pointer<_ProxyInfo>);
typedef _CloseNative = Int32 Function(IntPtr);
typedef _Close = int Function(int);
typedef _FreeNative = IntPtr Function(Pointer<Void>);
typedef _Free = int Function(Pointer<Void>);

const _accessNoProxy = 1;
const _accessNamedProxy = 3;
const _autoDetect = 0x1;
const _configUrl = 0x2;
const _detectDhcp = 0x1;
const _detectDnsA = 0x2;

class WindowsProxy {
  WindowsProxy._();

  /// Прокси для [url] по настройкам пользователя Windows; null — напрямую.
  /// [pacUrl] — сценарий PAC организации (MDM) вместо настроек пользователя.
  static Future<ProxyHop?> forUrl(String url, {required bool secure, String? pacUrl}) async {
    if (!Platform.isWindows) return null;
    final r = await Isolate.run(() => _query(url, pacUrl));
    if (r == null) return null;
    final host = Uri.tryParse(url)?.host ?? '';
    if (SystemProxy.bypassed(host, r.bypass)) return null;
    return parseList(r.proxy, secure: secure);
  }

  /// Ответ WinHTTP: список прокси и исключения (или null — напрямую).
  static ({String proxy, String? bypass})? _query(String url, String? orgPac) {
    final winhttp = DynamicLibrary.open('winhttp.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    final getIe = winhttp.lookupFunction<_GetIeNative, _GetIe>('WinHttpGetIEProxyConfigForCurrentUser');
    final open = winhttp.lookupFunction<_OpenNative, _Open>('WinHttpOpen');
    final forUrl = winhttp.lookupFunction<_ForUrlNative, _ForUrl>('WinHttpGetProxyForUrl');
    final close = winhttp.lookupFunction<_CloseNative, _Close>('WinHttpCloseHandle');
    final free = kernel.lookupFunction<_FreeNative, _Free>('GlobalFree');

    String? take(Pointer<Utf16> p) {
      if (p == nullptr) return null;
      final s = p.toDartString();
      free(p.cast());
      return s.isEmpty ? null : s;
    }

    final ie = calloc<_IeProxyConfig>();
    try {
      // PAC организации — только он; иначе настройки пользователя.
      final user = orgPac == null && getIe(ie) != 0;
      if (orgPac == null && !user) return null;
      final auto = user && ie.ref.fAutoDetect != 0;
      final pacUrl = orgPac ?? (user ? take(ie.ref.lpszAutoConfigUrl) : null);
      final manual = user ? take(ie.ref.lpszProxy) : null;
      final manualBypass = user ? take(ie.ref.lpszProxyBypass) : null;

      // Автообнаружение и PAC — сначала (так решает и Edge); не нашлось
      // сценария — ручной прокси.
      if (auto || pacUrl != null) {
        final agent = 'Ogneliss Mail'.toNativeUtf16();
        final session = open(agent, _accessNoProxy, nullptr, nullptr, 0);
        calloc.free(agent);
        if (session != 0) {
          final opts = calloc<_AutoProxyOptions>();
          final info = calloc<_ProxyInfo>();
          final u = url.toNativeUtf16();
          final pac = pacUrl?.toNativeUtf16();
          try {
            opts.ref
              ..dwFlags = (auto ? _autoDetect : 0) | (pac != null ? _configUrl : 0)
              ..dwAutoDetectFlags = auto ? (_detectDhcp | _detectDnsA) : 0
              ..lpszAutoConfigUrl = pac ?? nullptr
              ..fAutoLogonIfChallenged = 1;
            if (forUrl(session, u, opts, info) != 0) {
              final list = take(info.ref.lpszProxy);
              final bypass = take(info.ref.lpszProxyBypass);
              if (info.ref.dwAccessType == _accessNamedProxy && list != null) {
                return (proxy: list, bypass: bypass);
              }
              return null; // сценарий сказал «напрямую»
            }
          } finally {
            calloc.free(u);
            if (pac != null) calloc.free(pac);
            calloc.free(opts);
            calloc.free(info);
            close(session);
          }
        }
      }
      if (manual != null) return (proxy: manual, bypass: manualBypass);
      return null;
    } catch (_) {
      return null;
    } finally {
      calloc.free(ie);
    }
  }

  /// Список прокси Windows: «узел:порт», несколько через «;» или пробел,
  /// по протоколам — «http=узел:порт;https=узел:порт». Для шифрованного
  /// соединения — https=, иначе http=; без протокола — первый.
  @visibleForTesting
  static ProxyHop? parseList(String list, {required bool secure}) {
    String? plain, http, https;
    for (final raw in list.split(RegExp(r'[;\s]+'))) {
      final e = raw.trim();
      if (e.isEmpty) continue;
      final eq = e.indexOf('=');
      if (eq < 0) {
        plain ??= e;
        continue;
      }
      final scheme = e.substring(0, eq).toLowerCase();
      final v = e.substring(eq + 1);
      if (scheme == 'https') https ??= v;
      if (scheme == 'http') http ??= v;
    }
    return SystemProxy.parseProxy(secure ? (https ?? http ?? plain) : (http ?? plain));
  }
}

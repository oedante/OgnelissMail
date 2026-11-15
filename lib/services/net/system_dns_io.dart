// lib/services/net/system_dns_io.dart
// Системный DNS через функции ОС (dart:ffi) — см. system_dns.dart.

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'system_dns.dart';

/// null — у платформы нет системного DNS для записей (Android до 10).
Future<List<List<DnsRecord>?>?> platformLookup(List<DnsQuestion> questions) {
  final ask = [for (final q in questions) (q.name, q.type.index)];
  return Isolate.run(() => _run(ask));
}

List<List<DnsRecord>?>? _run(List<(String, int)> ask) {
  final b = _Backend.open();
  if (b == null) return null;
  return [
    for (final (name, t) in ask) _safe(() => b.query(name, DnsType.values[t])),
  ];
}

List<DnsRecord>? _safe(List<DnsRecord>? Function() f) {
  try {
    return f();
  } catch (_) {
    return null;
  }
}

const _bufSize = 16384;
const _classIn = 1;

abstract class _Backend {
  List<DnsRecord>? query(String name, DnsType type);

  static _Backend? open() {
    try {
      if (Platform.isAndroid) return _AndroidResolver.open();
      if (Platform.isWindows) return _WindowsResolver.open();
      if (Platform.isLinux || Platform.isMacOS || Platform.isIOS) return _ResQuery.open();
    } catch (_) {
      // Библиотеки или функции нет — записей нет.
    }
    return null;
  }
}

/// Сообщение DNS из буфера (копия: буфер освобождается).
List<DnsRecord>? _parse(Pointer<Uint8> buf, int len, DnsType type) {
  if (len <= 0) return null;
  final n = len > _bufSize ? _bufSize : len;
  return SystemDns.parseMessage(Uint8List.fromList(buf.asTypedList(n)), type);
}

// ── iOS, macOS, Linux: res_query ──

typedef _ResQueryC = Int32 Function(Pointer<Utf8>, Int32, Int32, Pointer<Uint8>, Int32);
typedef _ResQueryD = int Function(Pointer<Utf8>, int, int, Pointer<Uint8>, int);

class _ResQuery implements _Backend {
  final _ResQueryD _fn;
  _ResQuery(this._fn);

  static _ResQuery? open() {
    // В glibc 2.34+ res_query — в самой libc; раньше — в libresolv.so.2.
    // У Apple имя функции в libresolv — res_9_query (resolv.h).
    final libs = Platform.isLinux
        ? const ['libresolv.so.2', 'libc.so.6', null]
        : const ['/usr/lib/libresolv.9.dylib', 'libresolv.9.dylib', null];
    final names = Platform.isLinux ? const ['res_query', '__res_query'] : const ['res_9_query', 'res_query'];
    for (final path in libs) {
      DynamicLibrary lib;
      try {
        lib = path == null ? DynamicLibrary.process() : DynamicLibrary.open(path);
      } catch (_) {
        continue;
      }
      for (final n in names) {
        if (lib.providesSymbol(n)) return _ResQuery(lib.lookupFunction<_ResQueryC, _ResQueryD>(n));
      }
    }
    return null;
  }

  @override
  List<DnsRecord>? query(String name, DnsType type) {
    final buf = calloc<Uint8>(_bufSize);
    final n = name.toNativeUtf8();
    try {
      final len = _fn(n, _classIn, type.code, buf, _bufSize);
      // -1: имени или записей нет, либо DNS не ответил (h_errno) — для
      // проверки по адресу это одно и то же: доказательства нет.
      if (len < 0) return const [];
      return _parse(buf, len, type);
    } finally {
      calloc.free(n);
      calloc.free(buf);
    }
  }
}

// ── Android 10+: android_res_nquery (NDK, multinetwork.h) ──

typedef _NQueryC = Int32 Function(Uint64, Pointer<Utf8>, Int32, Int32, Uint32);
typedef _NQueryD = int Function(int, Pointer<Utf8>, int, int, int);
typedef _NResultC = Int32 Function(Int32, Pointer<Int32>, Pointer<Uint8>, Size);
typedef _NResultD = int Function(int, Pointer<Int32>, Pointer<Uint8>, int);
typedef _CancelC = Void Function(Int32);
typedef _CancelD = void Function(int);
typedef _PollC = Int32 Function(Pointer<_PollFd>, Uint32, Int32);
typedef _PollD = int Function(Pointer<_PollFd>, int, int);

final class _PollFd extends Struct {
  @Int32()
  external int fd;
  @Int16()
  external int events;
  @Int16()
  external int revents;
}

class _AndroidResolver implements _Backend {
  final _NQueryD _nquery;
  final _NResultD _nresult;
  final _CancelD _cancel;
  final _PollD _poll;
  _AndroidResolver(this._nquery, this._nresult, this._cancel, this._poll);

  static _AndroidResolver? open() {
    final android = DynamicLibrary.open('libandroid.so');
    // До Android 10 (API 29) функций нет.
    if (!android.providesSymbol('android_res_nquery')) return null;
    final libc = DynamicLibrary.open('libc.so');
    return _AndroidResolver(
      android.lookupFunction<_NQueryC, _NQueryD>('android_res_nquery'),
      android.lookupFunction<_NResultC, _NResultD>('android_res_nresult'),
      android.lookupFunction<_CancelC, _CancelD>('android_res_cancel'),
      libc.lookupFunction<_PollC, _PollD>('poll'),
    );
  }

  @override
  List<DnsRecord>? query(String name, DnsType type) {
    final n = name.toNativeUtf8();
    final buf = calloc<Uint8>(_bufSize);
    final rcode = calloc<Int32>();
    final pfd = calloc<_PollFd>();
    try {
      // Сеть 0 — сеть по умолчанию (NETWORK_UNSPECIFIED), флаги 0.
      final fd = _nquery(0, n, _classIn, type.code, 0);
      if (fd < 0) return null;
      pfd.ref
        ..fd = fd
        ..events = 1 // POLLIN
        ..revents = 0;
      if (_poll(pfd, 1, 3500) <= 0) {
        _cancel(fd); // закрывает fd
        return null;
      }
      final len = _nresult(fd, rcode, buf, _bufSize); // закрывает fd
      if (len < 0) return null;
      return _parse(buf, len, type);
    } finally {
      calloc.free(pfd);
      calloc.free(rcode);
      calloc.free(buf);
      calloc.free(n);
    }
  }
}

// ── Windows: DnsQuery_W ──

typedef _DnsQueryC = Int32 Function(Pointer<Utf16>, Uint16, Uint32, Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Void>);
typedef _DnsQueryD = int Function(Pointer<Utf16>, int, int, Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Void>);
typedef _DnsFreeC = Void Function(Pointer<Uint8>, Int32);
typedef _DnsFreeD = void Function(Pointer<Uint8>, int);

class _WindowsResolver implements _Backend {
  final _DnsQueryD _dnsQuery;
  final _DnsFreeD _dnsFree;
  _WindowsResolver(this._dnsQuery, this._dnsFree);

  static _WindowsResolver? open() {
    // Раскладка DNS_RECORDW ниже — для 64-разрядной Windows (Flutter
    // собирается только для x64 и arm64).
    if (sizeOf<IntPtr>() != 8) return null;
    final lib = DynamicLibrary.open('dnsapi.dll');
    return _WindowsResolver(
      lib.lookupFunction<_DnsQueryC, _DnsQueryD>('DnsQuery_W'),
      lib.lookupFunction<_DnsFreeC, _DnsFreeD>('DnsFree'),
    );
  }

  static const _errNameError = 9003; // DNS_ERROR_RCODE_NAME_ERROR (NXDOMAIN)
  static const _infoNoRecords = 9501; // DNS_INFO_NO_RECORDS
  static const _freeRecordList = 1; // DnsFreeRecordList
  static const _sectionAnswer = 1; // DnsSectionAnswer

  // DNS_RECORDW: pNext 0, pName 8, wType 16, wDataLength 18, Flags 20,
  // dwTtl 24, dwReserved 28, Data 32.
  //   DNS_MX_DATAW  — pNameExchange 32, wPreference 40;
  //   DNS_SRV_DATAW — pNameTarget 32, wPriority 40, wWeight 42, wPort 44;
  //   DNS_TXT_DATAW — dwStringCount 32, pStringArray 40.
  static int _u16(Pointer<Uint8> p, int off) => (p + off).cast<Uint16>().value;
  static int _u32(Pointer<Uint8> p, int off) => (p + off).cast<Uint32>().value;
  static Pointer<Uint8> _ptr(Pointer<Uint8> p, int off) => (p + off).cast<Pointer<Uint8>>().value;
  static String _str(Pointer<Uint8> p) => p == nullptr ? '' : p.cast<Utf16>().toDartString();

  /// Имя узла без завершающей точки («.» у SRV — пустое: службы нет).
  static String _host(Pointer<Uint8> p) {
    final s = _str(p);
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  @override
  List<DnsRecord>? query(String name, DnsType type) {
    final n = name.toNativeUtf16();
    final out = calloc<Pointer<Uint8>>();
    try {
      final status = _dnsQuery(n, type.code, 0, nullptr, out, nullptr);
      if (status == _errNameError || status == _infoNoRecords) return const [];
      if (status != 0) return null;
      final first = out.value;
      final records = <DnsRecord>[];
      try {
        for (var p = first; p != nullptr; p = _ptr(p, 0)) {
          if (_u16(p, 16) != type.code || (_u32(p, 20) & 0x3) != _sectionAnswer) continue;
          switch (type) {
            case DnsType.mx:
              records.add(DnsRecord(type, _host(_ptr(p, 32)), priority: _u16(p, 40)));
            case DnsType.srv:
              records.add(DnsRecord(type, _host(_ptr(p, 32)),
                  priority: _u16(p, 40), weight: _u16(p, 42), port: _u16(p, 44)));
            case DnsType.txt:
              final count = _u32(p, 32);
              final parts = StringBuffer();
              for (var i = 0; i < count && i < 64; i++) {
                parts.write(_str(_ptr(p, 40 + i * 8)));
              }
              records.add(DnsRecord(type, parts.toString()));
          }
        }
      } finally {
        if (first != nullptr) _dnsFree(first, _freeRecordList);
      }
      return records;
    } finally {
      calloc.free(out);
      calloc.free(n);
    }
  }
}

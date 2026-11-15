// lib/services/net/system_dns.dart
// Записи DNS (MX, SRV, TXT) через DNS самого устройства (2.6.0, вход в
// рабочую почту).
//
// Решение владельца 15.11.2026: для рабочей почты — никаких серверов
// Ogneliss и посторонних служб. Пакеты pub.dev для DNS либо спрашивают
// Google/Cloudflare по HTTPS (DoH), либо по умолчанию шлют запросы на
// 8.8.8.8 и требуют сборки на Rust, поэтому здесь — функции самой системы,
// тот же DNS, которым устройство находит любые адреса (DNS организации в её
// сети, VPN, профиль MDM):
//   · Android 10+ — android_res_nquery (libandroid, NDK API 29);
//   · iOS и macOS — res_query из системной libresolv;
//   · Linux — res_query из glibc (libresolv);
//   · Windows — DnsQuery_W (dnsapi.dll).
// Новых зависимостей нет (dart:ffi и уже подключённый пакет ffi). На
// Android 7–9 и в браузере записей нет — проверка по адресу работает как
// раньше, по именам узлов.
//
// Запросы идут по очереди в отдельном изоляте: системные функции
// блокирующие, а res_query на Apple не рассчитан на одновременные вызовы.

import 'dart:convert' show utf8;
import 'dart:typed_data';

import '../../core/logging/app_logger.dart';
import 'system_dns_stub.dart' if (dart.library.ffi) 'system_dns_io.dart' as backend;

/// Тип записи.
enum DnsType {
  mx(15),
  txt(16),
  srv(33);

  final int code;
  const DnsType(this.code);
}

/// Вопрос: имя и тип записи.
class DnsQuestion {
  final String name;
  final DnsType type;
  const DnsQuestion(this.name, this.type);

  @override
  String toString() => '${type.name.toUpperCase()} $name';
}

/// Запись ответа.
///   MX  — [target] узел почты, [priority] предпочтение;
///   SRV — [target] узел ('' — служба не предоставляется, RFC 2782 «.»),
///         [priority], [weight], [port];
///   TXT — [target] текст записи (части склеены).
class DnsRecord {
  final DnsType type;
  final String target;
  final int priority;
  final int weight;
  final int port;

  const DnsRecord(this.type, this.target, {this.priority = 0, this.weight = 0, this.port = 0});

  @override
  bool operator ==(Object other) =>
      other is DnsRecord &&
      other.type == type &&
      other.target == target &&
      other.priority == priority &&
      other.weight == weight &&
      other.port == port;

  @override
  int get hashCode => Object.hash(type, target, priority, weight, port);

  @override
  String toString() => switch (type) {
        DnsType.mx => 'MX $priority $target',
        DnsType.srv => 'SRV $priority $weight $port $target',
        DnsType.txt => 'TXT "$target"',
      };
}

/// Подмена DNS в тестах: ответ на каждый вопрос (null — DNS недоступен).
typedef DnsLookup = Future<List<List<DnsRecord>?>> Function(List<DnsQuestion> questions);

class SystemDns {
  SystemDns._();

  /// Ответы на вопросы в том же порядке. Для каждого: список записей
  /// (пустой — записей нет), null — системный DNS недоступен на этой
  /// платформе, не ответил за [timeout] или вернул ошибку. Ошибок не бросает.
  static Future<List<List<DnsRecord>?>> lookup(
    List<DnsQuestion> questions, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final none = List<List<DnsRecord>?>.filled(questions.length, null);
    if (questions.isEmpty) return none;
    final valid = [for (final q in questions) _validName(q.name)];
    final ask = [for (var i = 0; i < questions.length; i++) if (valid[i]) questions[i]];
    if (ask.isEmpty) return none;
    try {
      final got = await backend.platformLookup(ask).timeout(timeout, onTimeout: () => null);
      if (got == null) return none;
      final out = List<List<DnsRecord>?>.filled(questions.length, null);
      var j = 0;
      for (var i = 0; i < questions.length; i++) {
        if (valid[i]) out[i] = j < got.length ? got[j++] : null;
      }
      return out;
    } catch (e) {
      AppLogger.info('DNS устройства: запрос не удался — $e');
      return none;
    }
  }

  /// Узлы почты домена по предпочтению (пусто — нет записей или DNS
  /// недоступен).
  static Future<List<String>> mx(String domain) async {
    final r = (await lookup([DnsQuestion(domain, DnsType.mx)])).first;
    return mxHosts(r ?? const []);
  }

  /// Имя годится для запроса: буквы, цифры, «-», «_», «.»; не длиннее 253.
  static bool _validName(String n) =>
      n.isNotEmpty && n.length <= 253 && RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(n) && !n.contains('..');

  /// Узлы MX по предпочтению, строчными, без пустых.
  static List<String> mxHosts(List<DnsRecord> records) {
    final mx = records.where((r) => r.type == DnsType.mx && r.target.isNotEmpty).toList()
      ..sort((a, b) => a.priority.compareTo(b.priority));
    return [for (final r in mx) r.target.toLowerCase()];
  }

  /// Лучшая запись SRV (RFC 2782): меньший приоритет, при равном — больший
  /// вес. null — записей нет или служба явно не предоставляется («.»).
  static DnsRecord? bestSrv(List<DnsRecord>? records) {
    if (records == null) return null;
    final srv = records.where((r) => r.type == DnsType.srv).toList();
    if (srv.isEmpty) return null;
    // Одна запись с целью «.» — служба не предоставляется.
    if (srv.length == 1 && srv.first.target.isEmpty) return null;
    final ok = srv.where((r) => r.target.isNotEmpty && r.port > 0).toList()
      ..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        return p != 0 ? p : b.weight.compareTo(a.weight);
      });
    return ok.firstOrNull;
  }

  // ── Разбор ответа DNS (RFC 1035) ──

  /// Записи типа [type] из раздела ответа сообщения DNS. Пусто — имени нет
  /// (NXDOMAIN) или записей этого типа нет; null — ошибка сервера или
  /// испорченное сообщение.
  static List<DnsRecord>? parseMessage(Uint8List m, DnsType type) {
    if (m.length < 12) return null;
    final b = ByteData.sublistView(m);
    final rcode = b.getUint8(3) & 0x0F;
    if (rcode == 3) return const []; // NXDOMAIN
    if (rcode != 0) return null;
    final qd = b.getUint16(4);
    final an = b.getUint16(6);
    var off = 12;
    try {
      for (var i = 0; i < qd; i++) {
        off = _readName(m, off).next + 4;
      }
      final out = <DnsRecord>[];
      for (var i = 0; i < an; i++) {
        off = _readName(m, off).next;
        if (off + 10 > m.length) return null;
        final t = b.getUint16(off);
        final len = b.getUint16(off + 8);
        final data = off + 10;
        if (data + len > m.length) return null;
        if (t == type.code) {
          final r = _record(m, b, type, data, len);
          if (r != null) out.add(r);
        }
        off = data + len;
      }
      return out;
    } on RangeError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static DnsRecord? _record(Uint8List m, ByteData b, DnsType type, int data, int len) {
    switch (type) {
      case DnsType.mx:
        if (len < 3) return null;
        return DnsRecord(type, _readName(m, data + 2).name, priority: b.getUint16(data));
      case DnsType.srv:
        if (len < 7) return null;
        return DnsRecord(type, _readName(m, data + 6).name,
            priority: b.getUint16(data), weight: b.getUint16(data + 2), port: b.getUint16(data + 4));
      case DnsType.txt:
        final parts = <int>[];
        var p = data;
        while (p < data + len) {
          final l = m[p];
          if (p + 1 + l > data + len) return null;
          parts.addAll(m.sublist(p + 1, p + 1 + l));
          p += 1 + l;
        }
        return DnsRecord(type, utf8.decode(parts, allowMalformed: true));
    }
  }

  /// Имя со сжатием (RFC 1035, 4.1.4): [next] — смещение после имени в
  /// исходном месте сообщения.
  static ({String name, int next}) _readName(Uint8List m, int off) {
    final labels = <String>[];
    var p = off;
    int? next;
    var jumps = 0;
    while (true) {
      if (p >= m.length) throw RangeError('имя за пределами сообщения');
      final l = m[p];
      if (l == 0) {
        next ??= p + 1;
        break;
      }
      if (l & 0xC0 == 0xC0) {
        if (p + 1 >= m.length) throw RangeError('ссылка за пределами сообщения');
        if (++jumps > 64) throw const FormatException('петля ссылок в имени');
        next ??= p + 2;
        p = ((l & 0x3F) << 8) | m[p + 1];
        continue;
      }
      if (l & 0xC0 != 0) throw const FormatException('неизвестный тип метки');
      if (p + 1 + l > m.length) throw RangeError('метка за пределами сообщения');
      labels.add(String.fromCharCodes(m.sublist(p + 1, p + 1 + l)));
      p += 1 + l;
      if (labels.length > 127) throw const FormatException('слишком длинное имя');
    }
    return (name: labels.join('.'), next: next);
  }
}

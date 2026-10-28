// lib/services/security/smime_mime.dart
// S/MIME на уровне писем (RFC 8551): подпись multipart/signed, шифрование
// application/pkcs7-mime (smime.p7m) и обратное — проверка и расшифровка
// с разворачиванием вложенности (зашифрованное подписанное письмо).

import 'dart:convert';
import 'dart:typed_data';

import 'cms/cms.dart';
import 'cms/pkcs12.dart';
import 'cms/rsa.dart' show randomBytes;
import 'cms/x509.dart';

/// Итог открытия S/MIME-письма.
class SmimeOpenResult {
  /// Внутреннее письмо (MIME: заголовки содержимого и тело) — для показа.
  final Uint8List entity;

  /// Было зашифровано (и расшифровано).
  final bool decrypted;

  /// Подпись (если была).
  final CmsSignature? signature;

  /// Ошибка: 'needKey' — нет своего сертификата; 'notForMe'; 'unsupported';
  /// 'format'.
  final String? error;

  const SmimeOpenResult({required this.entity, this.decrypted = false, this.signature, this.error});

  bool get isSigned => signature != null;
}

class SmimeMime {
  SmimeMime._();

  /// Привести концы строк к CRLF (каноническая форма для подписи).
  static Uint8List canonical(Uint8List b) {
    final out = BytesBuilder(copy: false);
    var start = 0;
    for (var i = 0; i < b.length; i++) {
      if (b[i] == 10 && (i == 0 || b[i - 1] != 13)) {
        out.add(Uint8List.sublistView(b, start, i));
        out.add(const [13, 10]);
        start = i + 1;
      }
    }
    out.add(Uint8List.sublistView(b, start));
    return out.toBytes();
  }

  static String _b64Lines(List<int> data) {
    final s = base64.encode(data);
    final out = StringBuffer();
    for (var i = 0; i < s.length; i += 76) {
      out
        ..write(s.substring(i, i + 76 > s.length ? s.length : i + 76))
        ..write('\r\n');
    }
    return out.toString();
  }

  static String _boundary() =>
      '----=_smime_${randomBytes(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  /// Подписать MIME-часть [entity] (заголовки Content-* и тело, 7-бит).
  /// Возвращает новую часть multipart/signed.
  static Uint8List signEntity(Uint8List entity, SmimeIdentity id, {DateTime? now}) {
    final part = canonical(entity);
    final sig = Cms.signDetached(id, part, now: now);
    final b = _boundary();
    final out = BytesBuilder(copy: false)
      ..add(ascii.encode('Content-Type: multipart/signed; protocol="application/pkcs7-signature"; '
          'micalg=sha-256; boundary="$b"\r\n\r\n'
          'This is a cryptographically signed message in MIME format.\r\n\r\n'
          '--$b\r\n'))
      ..add(part)
      ..add(ascii.encode('\r\n--$b\r\n'
          'Content-Type: application/pkcs7-signature; name="smime.p7s"\r\n'
          'Content-Transfer-Encoding: base64\r\n'
          'Content-Disposition: attachment; filename="smime.p7s"\r\n'
          'Content-Description: S/MIME Cryptographic Signature\r\n\r\n'))
      ..add(ascii.encode(_b64Lines(sig)))
      ..add(ascii.encode('\r\n--$b--\r\n'));
    return out.toBytes();
  }

  /// Зашифровать MIME-часть [entity] для [recipients].
  static Uint8List encryptEntity(Uint8List entity, List<SmimeCert> recipients) {
    final cms = Cms.envelope(canonical(entity), recipients);
    return Uint8List.fromList(ascii.encode('Content-Type: application/pkcs7-mime; smime-type=enveloped-data; '
        'name="smime.p7m"\r\n'
        'Content-Transfer-Encoding: base64\r\n'
        'Content-Disposition: attachment; filename="smime.p7m"\r\n'
        'Content-Description: S/MIME Encrypted Message\r\n\r\n'
        '${_b64Lines(cms)}'));
  }

  /// Заменить содержимое письма [message]: заголовки Content-* уходят в
  /// часть, которую преобразует [transform], остальные (From, To, Subject,
  /// Date, Message-ID…) остаются у письма.
  static Uint8List transformMessage(Uint8List message, Uint8List Function(Uint8List entity) transform) {
    final m = canonical(message);
    final (headers, body) = _split(m);
    final outer = <String>[];
    final inner = <String>[];
    for (final h in headers) {
      final name = h.split(':').first.trim().toLowerCase();
      if (name.startsWith('content-')) {
        inner.add(h);
      } else if (name != 'mime-version') {
        outer.add(h);
      }
    }
    if (!inner.any((h) => h.toLowerCase().startsWith('content-type'))) {
      inner.insert(0, 'Content-Type: text/plain; charset=us-ascii');
    }
    final entity = BytesBuilder(copy: false)
      ..add(utf8.encode('${inner.join('\r\n')}\r\n\r\n'))
      ..add(body);
    final out = BytesBuilder(copy: false)
      ..add(utf8.encode('${outer.join('\r\n')}\r\nMIME-Version: 1.0\r\n'))
      ..add(transform(entity.toBytes()));
    return out.toBytes();
  }

  /// Письмо без заголовков [names] (без учёта регистра): «Bcc» не должен
  /// уходить получателям, когда письмо отправляется готовым текстом (SMTP,
  /// EWS MimeContent) — адреса скрытой копии передаются отдельно.
  static Uint8List withoutHeaders(Uint8List message, Set<String> names) {
    final lower = {for (final n in names) n.toLowerCase()};
    final s = latin1.decode(message);
    var end = s.indexOf('\r\n\r\n');
    if (end < 0) end = s.length;
    final out = <String>[];
    var skipping = false;
    for (final line in s.substring(0, end).split('\r\n')) {
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (!skipping) out.add(line);
        continue;
      }
      final i = line.indexOf(':');
      skipping = i > 0 && lower.contains(line.substring(0, i).trim().toLowerCase());
      if (!skipping) out.add(line);
    }
    return Uint8List.fromList(latin1.encode('${out.join('\r\n')}${s.substring(end)}'));
  }

  // ─────────────────────────── чтение ───────────────────────────

  /// Заголовки (развёрнутые) и тело.
  static (List<String>, Uint8List) _split(Uint8List m) {
    final s = latin1.decode(m);
    var end = s.indexOf('\r\n\r\n');
    int bodyStart;
    if (end < 0) {
      end = s.length;
      bodyStart = s.length;
    } else {
      bodyStart = end + 4;
    }
    final headers = <String>[];
    for (final line in s.substring(0, end).split('\r\n')) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && headers.isNotEmpty) {
        headers[headers.length - 1] = '${headers.last}\r\n$line';
      } else {
        headers.add(line);
      }
    }
    // Заголовки могут быть в UTF-8 — возвращаем к байтам и декодируем.
    final decoded = [for (final h in headers) utf8.decode(latin1.encode(h), allowMalformed: true)];
    return (decoded, Uint8List.sublistView(m, bodyStart));
  }

  static String? _header(List<String> headers, String name) {
    final n = name.toLowerCase();
    for (final h in headers) {
      final i = h.indexOf(':');
      if (i > 0 && h.substring(0, i).trim().toLowerCase() == n) {
        return h.substring(i + 1).replaceAll(RegExp(r'\r\n[ \t]+'), ' ').trim();
      }
    }
    return null;
  }

  static String? _param(String header, String name) {
    final m = RegExp('(?:^|;)\\s*$name\\s*=\\s*(?:"([^"]*)"|([^;\\s]+))', caseSensitive: false).firstMatch(header);
    return m == null ? null : (m.group(1) ?? m.group(2));
  }

  static Uint8List _decodeBody(String? cte, Uint8List body) {
    if ((cte ?? '').toLowerCase() == 'base64') {
      final s = latin1.decode(body).replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
      return base64.decode(s);
    }
    return body;
  }

  /// Похоже ли письмо (по Content-Type) на S/MIME.
  static bool isSmimeContentType(String? contentType) {
    final c = (contentType ?? '').toLowerCase();
    return c.contains('pkcs7-mime') ||
        (c.startsWith('multipart/signed') && c.contains('pkcs7-signature'));
  }

  /// Открыть письмо или часть: расшифровать и проверить подпись.
  static SmimeOpenResult open(Uint8List raw, {SmimeIdentity? identity, int depth = 0}) {
    final m = canonical(raw);
    final (headers, body) = _split(m);
    final ct = _header(headers, 'content-type') ?? 'text/plain';
    final lc = ct.toLowerCase();
    if (depth > 4) return SmimeOpenResult(entity: m);

    if (lc.contains('pkcs7-mime')) {
      final data = _decodeBody(_header(headers, 'content-transfer-encoding'), body);
      return openCms(data, identity: identity, depth: depth);
    }

    if (lc.startsWith('multipart/signed')) {
      final b = _param(ct, 'boundary');
      if (b == null) return SmimeOpenResult(entity: m, error: 'format');
      final s = latin1.decode(body);
      final delim = '--$b';
      final at = s.startsWith(delim) ? 0 : s.indexOf('\r\n$delim');
      if (at < 0) return SmimeOpenResult(entity: m, error: 'format');
      final p = at == 0 && s.startsWith(delim) ? 0 : at + 2;
      final firstStart = s.indexOf('\r\n', p) + 2;
      final next = s.indexOf('\r\n$delim', firstStart);
      if (firstStart < 2 || next < 0) return SmimeOpenResult(entity: m, error: 'format');
      final signedPart = Uint8List.sublistView(body, firstStart, next);
      // Вторая часть — подпись.
      final secondStart = s.indexOf('\r\n', next + 2) + 2;
      var secondEnd = s.indexOf('\r\n$delim', secondStart);
      if (secondEnd < 0) secondEnd = s.length;
      final sigPart = Uint8List.sublistView(body, secondStart, secondEnd);
      final (sh, sb) = _split(Uint8List.fromList(sigPart));
      CmsSignature sig;
      try {
        sig = Cms.verify(_decodeBody(_header(sh, 'content-transfer-encoding'), sb),
            detachedContent: Uint8List.fromList(signedPart));
      } catch (e) {
        sig = CmsSignature(valid: false, error: 'format: $e');
      }
      final inner = open(Uint8List.fromList(signedPart), identity: identity, depth: depth + 1);
      return SmimeOpenResult(
        entity: inner.entity,
        decrypted: inner.decrypted,
        signature: sig,
        error: inner.error,
      );
    }
    return SmimeOpenResult(entity: m);
  }

  /// Открыть содержимое smime.p7m (DER или base64).
  static SmimeOpenResult openCms(Uint8List p7m, {SmimeIdentity? identity, int depth = 0}) {
    var data = p7m;
    if (data.isNotEmpty && data[0] != 0x30) {
      try {
        data = base64.decode(latin1.decode(data).replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), ''));
      } catch (_) {}
    }
    final type = Cms.contentType(data);
    if (type == Oids.envelopedData) {
      if (identity == null) return SmimeOpenResult(entity: data, error: 'needKey');
      try {
        final inner = Cms.decrypt(data, identity);
        final r = open(inner, identity: identity, depth: depth + 1);
        return SmimeOpenResult(entity: r.entity, decrypted: true, signature: r.signature, error: r.error);
      } on CmsException catch (e) {
        return SmimeOpenResult(entity: data, error: e.code);
      } catch (_) {
        return SmimeOpenResult(entity: data, error: 'format');
      }
    }
    if (type == Oids.signedData) {
      final sig = Cms.verify(data);
      final content = sig.content;
      if (content == null) return SmimeOpenResult(entity: data, signature: sig, error: 'format');
      final r = open(content, identity: identity, depth: depth + 1);
      return SmimeOpenResult(entity: r.entity, decrypted: r.decrypted, signature: sig, error: r.error);
    }
    return SmimeOpenResult(entity: data, error: 'format');
  }

  /// Сделать из внутренней части письмо для просмотра (.eml): добавить
  /// заголовки исходного письма (тема, от кого), если части их не хватает.
  static Uint8List asMessage(Uint8List entity, {String? subject, String? from, String? to, DateTime? date}) {
    final m = canonical(entity);
    final (headers, _) = _split(m);
    final have = {for (final h in headers) h.split(':').first.trim().toLowerCase()};
    final add = <String>[
      if (subject != null && !have.contains('subject')) 'Subject: ${_enc(subject)}',
      if (from != null && !have.contains('from')) 'From: ${_enc(from)}',
      if (to != null && !have.contains('to')) 'To: ${_enc(to)}',
      if (date != null && !have.contains('date')) 'Date: ${_rfcDate(date)}',
    ];
    if (add.isEmpty) return m;
    return Uint8List.fromList([...utf8.encode('${add.join('\r\n')}\r\n'), ...m]);
  }

  static String _enc(String s) =>
      s.codeUnits.every((c) => c < 128) ? s : '=?utf-8?B?${base64.encode(utf8.encode(s))}?=';

  static String _rfcDate(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${days[u.weekday - 1]}, ${u.day} ${months[u.month - 1]} ${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} +0000';
  }
}

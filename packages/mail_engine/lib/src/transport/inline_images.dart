// lib/src/transport/inline_images.dart
// Картинки в тексте исходящего письма — встроенными частями MIME (2.7.2,
// замечание владельца 24.11.2026: в ответе картинка из цитаты пропала,
// у получателя — пустое место).
//
// Приложение кладёт в HTML картинки как data:image/…;base64 — вставленный
// скриншот и картинки цитаты (они были cid: исходного письма). Так их
// показывает не каждая программа: Outlook для Windows и Gmail картинки
// data: в письмах не показывают. Перед отправкой каждая такая картинка
// становится частью письма с Content-ID, а в HTML — ссылкой cid: на неё
// (multipart/related, RFC 2387) — так пишет и Outlook.

import 'dart:convert';
import 'dart:typed_data';

/// Встроенная картинка исходящего письма.
class InlineImagePart {
  /// Content-ID без угловых скобок (в HTML — `cid:<cid>`).
  final String cid;
  final String mimeType;
  final Uint8List bytes;

  /// Имя файла для части (image001.png — как у Outlook).
  final String name;
  const InlineImagePart({required this.cid, required this.mimeType, required this.bytes, required this.name});
}

/// HTML с картинками-ссылками cid: и сами картинки.
typedef InlinedHtml = ({String html, List<InlineImagePart> parts});

abstract final class MimeInlineImages {
  // src="data:image/png;base64,…" (кавычки двойные или одинарные).
  static final _dataSrc = RegExp(
    r'''(\bsrc\s*=\s*)(["'])\s*data:(image/(?:png|jpe?g|gif|webp|bmp))\s*;\s*base64\s*,([A-Za-z0-9+/=\s]+)\2''',
    caseSensitive: false,
  );

  static String _ext(String mime) {
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/bmp':
        return 'bmp';
      default:
        return 'png';
    }
  }

  /// Картинки data: в [html] — отдельными частями. Одинаковые картинки —
  /// одна часть. [domain] — правая часть Content-ID (домен отправителя).
  /// Нет таких картинок — HTML как есть и пустой список.
  static InlinedHtml extract(String html, {String domain = 'ogneliss', String? stamp}) {
    if (!html.contains('data:')) return (html: html, parts: const []);
    final parts = <InlineImagePart>[];
    final byData = <String, String>{}; // base64 → cid
    final st = stamp ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final dom = domain.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '');
    final out = html.replaceAllMapped(_dataSrc, (m) {
      var mime = m.group(3)!.toLowerCase();
      if (mime == 'image/jpg') mime = 'image/jpeg';
      final b64 = m.group(4)!.replaceAll(RegExp(r'\s'), '');
      var cid = byData[b64];
      if (cid == null) {
        final Uint8List bytes;
        try {
          bytes = base64.decode(base64.normalize(b64));
        } catch (_) {
          return m.group(0)!; // испорченная картинка — как есть
        }
        if (bytes.isEmpty) return m.group(0)!;
        final n = parts.length + 1;
        cid = 'image${n.toString().padLeft(3, '0')}.$st@${dom.isEmpty ? 'ogneliss' : dom}';
        parts.add(InlineImagePart(
          cid: cid,
          mimeType: mime,
          bytes: bytes,
          name: 'image${n.toString().padLeft(3, '0')}.${_ext(mime)}',
        ));
        byData[b64] = cid;
      }
      return '${m.group(1)}${m.group(2)}cid:$cid${m.group(2)}';
    });
    if (parts.isEmpty) return (html: html, parts: const []);
    return (html: out, parts: parts);
  }
}

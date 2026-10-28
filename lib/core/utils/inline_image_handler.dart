// lib/core/utils/inline_image_handler.dart
// Обработка inline-изображений в HTML-письмах:
// - Замена CID (Content-ID) ссылок на base64 data URI
// - Кеширование декодированных изображений
// - Поддержка: cid:xxx, src="cid:xxx"
// - Работает с вложениями, помеченными isInline=true

import 'dart:convert';
import 'dart:typed_data';

import '../../data/models/email_model.dart';
import '../logging/app_logger.dart';

class InlineImageHandler {
  InlineImageHandler._();

  /// Кеш CID → base64 data URI
  static final Map<String, String> _cache = {};

  /// Заменить CID-ссылки в HTML на base64 data URI
  static String processCidReferences({
    required String html,
    required List<EmailAttachment> attachments,
    Map<String, Uint8List>? attachmentData,
  }) {
    if (html.isEmpty || attachments.isEmpty) return html;

    var processed = html;

    for (final att in attachments) {
      if (!att.isInline) continue;

      // Извлекаем Content-ID из имени (может быть в формате <cid>)
      final cid = att.id.replaceAll('<', '').replaceAll('>', '');
      if (cid.isEmpty) continue;

      // Ищем src="cid:xxx" паттерны
      final patterns = [
        'src="cid:$cid"',
        "src='cid:$cid'",
        'src=cid:$cid',
        'src="CID:$cid"',
      ];

      // Проверяем кеш
      if (_cache.containsKey(cid)) {
        for (final pattern in patterns) {
          processed = processed.replaceAll(pattern, 'src="${_cache[cid]}"');
        }
        continue;
      }

      // Если есть данные вложения — конвертируем в data URI
      if (attachmentData != null && attachmentData.containsKey(att.id)) {
        final bytes = attachmentData[att.id]!;
        final mimeType = att.mimeType.isNotEmpty ? att.mimeType : 'image/png';
        final dataUri = 'data:$mimeType;base64,${base64.encode(bytes)}';

        _cache[cid] = dataUri;

        for (final pattern in patterns) {
          processed = processed.replaceAll(pattern, 'src="$dataUri"');
        }

        AppLogger.debug('InlineImage: replaced CID:$cid (${bytes.length} bytes)');
      } else {
        // Заменяем на placeholder
        final placeholder = 'data:image/svg+xml;base64,${base64.encode(utf8.encode(
          '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100">'
          '<rect fill="#f0f0f0" width="200" height="100"/>'
          '<text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#999" font-size="12">🖼️ ${att.name}</text>'
          '</svg>'
        ))}';

        for (final pattern in patterns) {
          processed = processed.replaceAll(pattern, 'src="$placeholder"');
        }
      }
    }

    return processed;
  }

  /// Извлечь список CID из HTML
  static List<String> extractCids(String html) {
    final cids = <String>[];
    final pattern = RegExp(r"""(?:src\s*=\s*["']?)cid:([^"'>\s]+)""", caseSensitive: false);
    for (final match in pattern.allMatches(html)) {
      final cid = match.group(1);
      if (cid != null && cid.isNotEmpty) cids.add(cid);
    }
    return cids;
  }

  /// Очистить кеш
  static void clearCache() {
    _cache.clear();
  }
}

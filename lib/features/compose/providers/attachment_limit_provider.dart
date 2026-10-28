// lib/features/compose/providers/attachment_limit_provider.dart
// Лимит суммарного размера вложений на письмо, ПО АККАУНТУ. Значение по умолчанию —
// AppConstants.maxAttachmentSize (25 МБ, типовой лимит Exchange/O365). Реальный лимит
// сервера узнаём из ошибки отправки («сообщение слишком большое») и запоминаем —
// EWS не отдаёт лимит отдельным запросом. Хранится в SharedPreferences (без миграции БД).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/providers/shared_prefs_provider.dart';

class AttachmentLimitStore {
  final SharedPreferences _p;
  AttachmentLimitStore(this._p);

  static String _key(String accountId) => 'attach_limit_$accountId';

  /// Лимит суммарного размера вложений (байт) для аккаунта.
  int limitFor(String accountId) {
    final v = _p.getInt(_key(accountId));
    if (v != null && v > 0) return v;
    return AppConstants.maxAttachmentSize;
  }

  /// Лимит известен от сервера ящика (политика Exchange или ответ на
  /// отправку), а не взят по умолчанию — для пояснения «?» у строки размера
  /// письма (1.7.2+110).
  bool isKnown(String accountId) => (_p.getInt(_key(accountId)) ?? 0) > 0;

  /// Запомнить лимит, обнаруженный по ответу сервера.
  Future<void> setLimit(String accountId, int bytes) async {
    if (bytes <= 0) return;
    await _p.setInt(_key(accountId), bytes);
  }

  /// Попытаться извлечь лимит (в байтах) из текста ошибки отправки. Возвращает
  /// null, если размер в сообщении не найден. Понимает форматы вида «25 MB»,
  /// «26214400 bytes», «size 35840 KB» и т. п.
  static int? parseLimitFromError(String? error) {
    if (error == null) return null;
    final lower = error.toLowerCase();
    // Не относится к размеру — не трогаем.
    if (!lower.contains('size') &&
        !lower.contains('large') &&
        !lower.contains('exceed') &&
        !lower.contains('quota')) {
      return null;
    }
    // Число + единица (MB/KB/GB/bytes). Берём первое похожее на лимит.
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(gb|mb|kb|bytes|b)\b').firstMatch(lower);
    if (m == null) return null;
    final num = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (num == null || num <= 0) return null;
    switch (m.group(2)) {
      case 'gb':
        return (num * 1024 * 1024 * 1024).round();
      case 'mb':
        return (num * 1024 * 1024).round();
      case 'kb':
        return (num * 1024).round();
      default: // bytes / b
        return num.round();
    }
  }
}

final attachmentLimitProvider = Provider<AttachmentLimitStore>((ref) {
  return AttachmentLimitStore(ref.watch(sharedPrefsProvider));
});

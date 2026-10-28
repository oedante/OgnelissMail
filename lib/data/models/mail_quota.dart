// lib/data/models/mail_quota.dart
// Квота почтового ящика на сервере (IMAP QUOTA, RFC 2087).

class MailQuota {
  /// Занято на сервере, байт.
  final int usedBytes;

  /// Лимит, байт. null — лимит не задан (безлимитный ящик).
  final int? limitBytes;

  /// Имя quota-root (для диагностики), например "" или "user/ivanov".
  final String? rootName;

  const MailQuota({
    required this.usedBytes,
    this.limitBytes,
    this.rootName,
  });

  /// Доля заполнения 0..1. null — если лимита нет.
  double? get usedFraction {
    final limit = limitBytes;
    if (limit == null || limit <= 0) return null;
    return (usedBytes / limit).clamp(0.0, 1.0);
  }

  /// Осталось байт. null — если лимита нет.
  int? get freeBytes {
    final limit = limitBytes;
    if (limit == null || limit <= 0) return null;
    final free = limit - usedBytes;
    return free < 0 ? 0 : free;
  }

  bool get isNearLimit {
    final f = usedFraction;
    return f != null && f >= 0.9;
  }
}

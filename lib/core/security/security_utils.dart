// lib/core/security/security_utils.dart
// Безопасность: rate limiting, HTML-санитизация, валидация, хеширование

import 'html_sanitizer.dart';
import 'dart:math';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityUtils {
  SecurityUtils._();

  // ════════════════════════ RATE LIMITING ════════════════════════
  //
  // ВАЖНО: лимит попыток авторизации определяется СЕРВЕРОМ (ответы
  // 401/403/429 + Retry-After), а не приложением. Корпоративная политика
  // блокировки задаётся на Exchange/почтовом сервере. Поэтому клиентская
  // блокировка отключена: приложение не должно само решать, когда
  // заблокировать вход — оно лишь показывает сообщение сервера.
  //
  // Методы сохранены для обратной совместимости вызовов, но всегда
  // разрешают попытку (мягкий учёт ведётся только для диагностики).

  static final Map<String, _RateLimit> _limits = {};

  /// Всегда true — решение о блокировке принимает сервер.
  static bool isAuthAllowed(String key) => true;

  /// Мягкий учёт неудач для диагностики/логов (не блокирует вход).
  static void recordFailedAttempt(String key) {
    final e = _limits[key] ?? _RateLimit();
    e.attempts++;
    _limits[key] = e;
  }

  static void resetAttempts(String key) => _limits.remove(key);

  /// Всегда 0 — клиентского лок-аута нет.
  static int getLockoutRemainingSeconds(String key) => 0;

  // ════════════════════════ HTML SANITIZATION ════════════════════════

  /// Очистка HTML письма — по белому списку на разборе DOM
  /// (см. HtmlSanitizer). Регулярные выражения, которые были здесь раньше,
  /// обходились (обработчики без кавычек, сущности в «javascript:»).
  static String sanitizeHtml(String html) {
    if (html.isEmpty) return html;
    try {
      return HtmlSanitizer.sanitize(html);
    } catch (_) {
      return _regexSanitize(html); // запасной путь, если разбор не удался
    }
  }

  static String _regexSanitize(String html) {
    var s = html;
    s = s.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+on\w+\s*=\s*"[^"]*"', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r"\s+on\w+\s*=\s*'[^']*'", caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<(iframe|embed|object|applet|form)[^>]*>[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<(iframe|embed|object|applet|form)[^>]*/?>',caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<meta[^>]*http-equiv[^>]*refresh[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<link[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'expression\s*\(', caseSensitive: false), '');
    return s;
  }

  static bool isHtmlSafe(String html) {
    final l = html.toLowerCase();
    return !l.contains('<script') && !l.contains('javascript:') && !l.contains('onerror=') && !l.contains('onclick=') && !l.contains('<iframe');
  }

  // ════════════════════════ VALIDATION ════════════════════════

  static bool isValidEmail(String email) => RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email);

  static PasswordStrength checkPasswordStrength(String p) {
    if (p.length < 6) return PasswordStrength.weak;
    int s = 0;
    if (p.length >= 8) s++;
    if (p.length >= 12) s++;
    if (RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9]').hasMatch(p)) s++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) s++;
    if (s <= 2) return PasswordStrength.weak;
    if (s <= 4) return PasswordStrength.medium;
    return PasswordStrength.strong;
  }

  // ════════════════════════ HASHING ════════════════════════

  static String hashString(String input) => sha256.convert(utf8.encode(input)).toString();
  static String hashWithSalt(String input, String salt) => hashString('$salt:$input');
  /// Сравнение строк за время, не зависящее от места первого расхождения.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String generateSalt() => base64Url.encode(List.generate(32, (_) => Random.secure().nextInt(256)));
  static String generateToken({int length = 32}) => base64Url.encode(List.generate(length, (_) => Random.secure().nextInt(256)));

  // ════════════════════════ MASKING ════════════════════════

  static String maskEmail(String email) {
    final p = email.split('@');
    if (p.length != 2 || p[0].length <= 2) return '***@${p.length > 1 ? p[1] : ""}';
    return '${p[0][0]}${'*' * (p[0].length - 2)}${p[0][p[0].length - 1]}@${p[1]}';
  }

  static String maskPhone(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.length < 7) return phone;
    return '+${d.substring(0, 2)}***${d.substring(d.length - 4)}';
  }
}

enum PasswordStrength { weak, medium, strong }

class _RateLimit {
  int attempts = 0;
  bool isLocked = false;
  DateTime? lockedAt;
}

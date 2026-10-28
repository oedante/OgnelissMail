// test/unit/security_utils_test.dart
// Unit-тесты безопасности: rate limiting, HTML-санитизация,
// валидация, хеширование, маскирование.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/security_utils.dart';

void main() {
  group('Rate Limiting', () {
    setUp(() {
      // Сбрасываем состояние перед каждым тестом
      SecurityUtils.resetAttempts('test@example.com');
    });

    test('Первая попытка разрешена', () {
      expect(SecurityUtils.isAuthAllowed('test@example.com'), isTrue);
    });

    // Блокировку входа решает сервер (Exchange/почтовый сервер), клиент
    // только учитывает неудачи для диагностики и не блокирует сам.
    test('5 неудачных попыток не блокируют вход на клиенте', () {
      for (int i = 0; i < 5; i++) {
        SecurityUtils.recordFailedAttempt('test@example.com');
      }
      expect(SecurityUtils.isAuthAllowed('test@example.com'), isTrue);
    });

    test('Успешный вход сбрасывает счётчик', () {
      SecurityUtils.recordFailedAttempt('test@example.com');
      SecurityUtils.recordFailedAttempt('test@example.com');
      SecurityUtils.resetAttempts('test@example.com');
      expect(SecurityUtils.isAuthAllowed('test@example.com'), isTrue);
    });

    test('Клиентского лок-аута нет: оставшееся время 0', () {
      for (int i = 0; i < 5; i++) {
        SecurityUtils.recordFailedAttempt('timeout@test.ru');
      }
      expect(SecurityUtils.getLockoutRemainingSeconds('timeout@test.ru'), 0);
    });
  });

  group('HTML-санитизация', () {
    test('Удаляет <script> теги', () {
      const html =
          '<p>Привет</p><script>alert("xss")</script><p>Мир</p>';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, isNot(contains('<script')));
      expect(sanitized, isNot(contains('alert')));
      expect(sanitized, contains('<p>Привет</p>'));
    });

    test('Удаляет onclick атрибуты', () {
      const html = '<a href="#" onclick="steal()">Ссылка</a>';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, isNot(contains('onclick')));
      expect(sanitized, contains('Ссылка'));
    });

    test('Удаляет javascript: в href', () {
      const html = '<a href="javascript:alert(1)">Клик</a>';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, isNot(contains('javascript:')));
    });

    test('Удаляет <iframe>', () {
      const html = '<p>Текст</p><iframe src="evil.com"></iframe>';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, isNot(contains('<iframe')));
      expect(sanitized, contains('<p>Текст</p>'));
    });

    test('Удаляет onerror в img', () {
      const html = '<img src="x" onerror="steal()" />';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, isNot(contains('onerror')));
    });

    test('Сохраняет безопасный HTML', () {
      const html =
          '<p>Добрый день,</p><br><b>Важно:</b> встреча в 15:00';
      final sanitized = SecurityUtils.sanitizeHtml(html);
      expect(sanitized, equals(html));
    });

    test('isHtmlSafe возвращает false для опасного HTML', () {
      expect(
          SecurityUtils.isHtmlSafe('<script>alert(1)</script>'), isFalse);
      expect(SecurityUtils.isHtmlSafe('<p onclick="x">'), isFalse);
      expect(SecurityUtils.isHtmlSafe('<iframe src="x">'), isFalse);
    });

    test('isHtmlSafe возвращает true для безопасного HTML', () {
      expect(SecurityUtils.isHtmlSafe('<p>Привет мир</p>'), isTrue);
      expect(SecurityUtils.isHtmlSafe('<b>Важно</b>'), isTrue);
    });
  });

  group('Валидация email', () {
    test('Правильные email', () {
      expect(SecurityUtils.isValidEmail('user@example.com'), isTrue);
      expect(SecurityUtils.isValidEmail('user@example.com'), isTrue);
      expect(SecurityUtils.isValidEmail('test.user+tag@gmail.com'), isTrue);
    });

    test('Неправильные email', () {
      expect(SecurityUtils.isValidEmail(''), isFalse);
      expect(SecurityUtils.isValidEmail('user'), isFalse);
      expect(SecurityUtils.isValidEmail('user@'), isFalse);
      expect(SecurityUtils.isValidEmail('@domain.com'), isFalse);
      expect(SecurityUtils.isValidEmail('user@domain'), isFalse);
    });
  });

  group('Сила пароля', () {
    test('Слабый пароль', () {
      expect(SecurityUtils.checkPasswordStrength('123'),
          equals(PasswordStrength.weak));
      expect(SecurityUtils.checkPasswordStrength('password'),
          equals(PasswordStrength.weak));
    });

    test('Средний пароль', () {
      expect(SecurityUtils.checkPasswordStrength('Password1'),
          equals(PasswordStrength.medium));
    });

    test('Сильный пароль', () {
      expect(SecurityUtils.checkPasswordStrength('P@ssw0rd!2026'),
          equals(PasswordStrength.strong));
    });
  });

  group('Маскирование', () {
    test('Маскирование email', () {
      expect(SecurityUtils.maskEmail('user@example.com'),
          equals('u**r@example.com'));
      expect(SecurityUtils.maskEmail('oleg.ivanov@example.com'),
          equals('o*********v@example.com'));
    });

    test('Маскирование телефона', () {
      expect(SecurityUtils.maskPhone('+79121234567'),
          equals('+79***4567'));
    });
  });

  group('Хеширование', () {
    test('Одинаковый вход = одинаковый хеш', () {
      final h1 = SecurityUtils.hashString('test');
      final h2 = SecurityUtils.hashString('test');
      expect(h1, equals(h2));
    });

    test('Разный вход = разный хеш', () {
      final h1 = SecurityUtils.hashString('test1');
      final h2 = SecurityUtils.hashString('test2');
      expect(h1, isNot(equals(h2)));
    });

    test('Соль меняет хеш', () {
      final h1 = SecurityUtils.hashWithSalt('password', 'salt1');
      final h2 = SecurityUtils.hashWithSalt('password', 'salt2');
      expect(h1, isNot(equals(h2)));
    });

    test('Генерация токена — уникальность', () {
      final t1 = SecurityUtils.generateToken();
      final t2 = SecurityUtils.generateToken();
      expect(t1, isNot(equals(t2)));
      expect(t1.length, greaterThan(20));
    });
  });
}

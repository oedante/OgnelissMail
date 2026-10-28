import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/dlp_service.dart';
import 'package:ogneliss/data/models/email_model.dart';

void main() {
  late DlpService dlp;

  setUp(() { dlp = DlpService(); });

  group('DLP outgoing check', () {
    test('clean email passes', () {
      final result = dlp.checkOutgoingEmail(
        senderEmail: 'me@example.com',
        recipients: [const EmailAddress(email: 'colleague@example.com')],
        subject: 'Привет', body: 'Как дела?',
      );
      expect(result.isAllowed, isTrue);
      expect(result.hasViolations, isFalse);
    });

    test('email with card number is flagged', () {
      final result = dlp.checkOutgoingEmail(
        senderEmail: 'me@example.com',
        recipients: [const EmailAddress(email: 'external@gmail.com')],
        subject: 'Оплата', body: 'Карта: 4111 1111 1111 1111',
      );
      expect(result.hasViolations, isTrue);
    });

    test('hasBlockingViolations works', () {
      final result = dlp.checkOutgoingEmail(
        senderEmail: 'me@example.com',
        recipients: [const EmailAddress(email: 'hacker@evil.com')],
        subject: 'Пароль', body: 'password: secret123 credentials: admin',
      );
      expect(result, isA<DlpCheckResult>());
      expect(result.hasBlockingViolations, isA<bool>());
    });

    test('гриф коллеге из своего домена — не блокируется', () {
      final result = dlp.checkOutgoingEmail(
        senderEmail: 'me@example.com',
        recipients: [const EmailAddress(email: 'colleague@example.com')],
        subject: 'Конфиденциально', body: 'Отчёт',
      );
      expect(result.hasBlockingViolations, isFalse);
    });

    test('violation blocking property', () {
      const violation = DlpViolation(
        type: 'test', description: 'test violation',
        severity: DlpSeverity.block,
      );
      expect(violation.blocking, isTrue);
      const warning = DlpViolation(
        type: 'test', description: 'warning', severity: DlpSeverity.warning,
      );
      expect(warning.blocking, isFalse);
    });
  });
}

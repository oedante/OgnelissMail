// Правило владельца 08.11.2026: пользователю — только критические ошибки
// (нужны его действия или есть риск потерять данные); временные сбои и
// пояснения — только в журнал, приложение повторит или пропустит.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/errors/app_exceptions.dart';
import 'package:ogneliss/widgets/common/inline_notice.dart';

void main() {
  test('временные сбои распознаются (журнал владельца 08.11.2026)', () {
    for (final e in [
      'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
      'SocketException: Connection failed (OS Error: Network is unreachable, errno = 101)',
      'Software caused connection abort',
      'TimeoutException after 0:00:30.000000: Future not completed',
      '[EAS] FolderSync: нет ответа (HTTP 502)',
      'EAS SendMail: HTTP 0 (письмо не отправлено)',
      'Не удалось обновить OAuth-токен: прокси недоступен (ClientException)',
    ]) {
      expect(looksTransientError(e), isTrue, reason: e);
    }
    for (final e in ['AUTHENTICATIONFAILED', 'Certificate verify failed', 'Folder not found', 'quota exceeded']) {
      expect(looksTransientError(e), isFalse, reason: e);
    }
  });

  test('некритичное — не на экран', () {
    appNotice.value = null;
    quietError('Не удалось перевести');
    quietNotice('Перевод…');
    expect(appNotice.value, isNull);
    showInlineError('Письмо не отправлено');
    expect(appNotice.value?.text, 'Письмо не отправлено');
    appNotice.value = null;
  });
}

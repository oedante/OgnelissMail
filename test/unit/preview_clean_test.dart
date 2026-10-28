// 1.8.0 (118): превью рассылок без «&zwnj; &zwnj; …» (замечание 27.10.2026:
// письмо Ozon в ленте начиналось строкой сущностей HTML).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/text_safe.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/notifications/notification_text.dart';

void main() {
  test('сущности и невидимые символы прехедера убираются', () {
    final junk = List.filled(120, '&zwnj; ').join();
    final text = '$junk‌͏­ Новые вопросы о ваших покупках &laquo;Ozon&raquo; &amp; ответы&nbsp;— здесь';
    expect(previewOf(text), 'Новые вопросы о ваших покупках «Ozon» & ответы — здесь');
    expect(cleanPreviewText('a&#8204;b&#x200C;c&zwnj;d'), 'abcd');
    expect(cleanPreviewText('Цена&nbsp;100&nbsp;&#8381;'), 'Цена 100 ₽');
  });

  test('переводы строк и составные эмодзи сохраняются', () {
    expect(previewKeepingLines('&zwnj; &zwnj;\nДобрый день,\n\nТекст'), 'Добрый день,\n\nТекст');
    expect(cleanPreviewText('👨‍👩‍👧 семья'), '👨‍👩‍👧 семья');
    expect(cleanPreviewText('&unknown; остаётся'), '&unknown; остаётся');
  });

  test('сохранённое превью из одних сущностей — текст письма', () {
    final e = EmailModel(
      id: '1',
      accountId: 'a',
      folderId: 'f',
      from: const EmailAddress(email: 'news@ozon.ru'),
      to: const [],
      subject: 'Новые вопросы',
      receivedAt: DateTime(2026, 10, 27),
      bodyPreview: List.filled(30, '&zwnj; ').join(),
      bodyPlain: '&zwnj; &zwnj; Новые вопросы от пользователей',
    );
    expect(e.preview, 'Новые вопросы от пользователей');
  });

  test('уведомление — без сущностей', () {
    expect(NotificationText.preview('&zwnj; &zwnj; Привет&nbsp;мир'), 'Привет мир');
  });
}

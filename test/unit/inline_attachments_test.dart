// Встроенные картинки письма и список вложений (1.5.7, замечание 11.10.2026:
// картинки подписи были и в тексте, и во вложениях). Запасные картинки
// Outlook (VML: .wmz/.emz) не показываются ни в тексте, ни в списке.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';

void main() {
  test('запасные картинки Outlook (VML) узнаются по имени и типу', () {
    expect(const EmailAttachment(id: '1', name: 'image001.wmz').isVmlPreview, isTrue);
    expect(const EmailAttachment(id: '2', name: 'IMAGE002.EMZ').isVmlPreview, isTrue);
    expect(const EmailAttachment(id: '3', name: 'x', mimeType: 'image/x-wmf').isVmlPreview, isTrue);
    expect(const EmailAttachment(id: '4', name: 'image013.png', mimeType: 'image/png').isVmlPreview, isFalse);
    expect(const EmailAttachment(id: '5', name: 'Отчёт.pdf', mimeType: 'application/pdf').isVmlPreview, isFalse);
  });
}

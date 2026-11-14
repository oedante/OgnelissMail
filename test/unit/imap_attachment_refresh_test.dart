// Письма IMAP, открытые до 2.4.0: тело на телефоне, а список вложений собран
// прежними правилами (13.11.2026, «Fwd: Занавеси» из веб-почты Яндекса —
// фото image0.jpeg «inline» без Content-ID). Когда уточнять список у сервера.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  const html = '<div>Ширина 5,7<br>Высота 4,3</div>';

  test('письмо 227 КБ с текстом в полкилобайта и без списка — спросить сервер', () {
    expect(
        ImapService.attachmentsMayBeMissing(size: 227438, attachmentsJson: null, bodyHtml: html, bodyPlain: null),
        isTrue);
    expect(
        ImapService.attachmentsMayBeMissing(size: 227438, attachmentsJson: '[]', bodyHtml: html, bodyPlain: null),
        isTrue);
  });

  test('список уже есть, письмо маленькое или размер неизвестен — не спрашивать', () {
    expect(
        ImapService.attachmentsMayBeMissing(
            size: 227438, attachmentsJson: '[{"id":"2","name":"a.jpg"}]', bodyHtml: html, bodyPlain: null),
        isFalse);
    expect(ImapService.attachmentsMayBeMissing(size: 9000, attachmentsJson: null, bodyHtml: html, bodyPlain: null),
        isFalse);
    expect(ImapService.attachmentsMayBeMissing(size: null, attachmentsJson: null, bodyHtml: html, bodyPlain: null),
        isFalse);
    // Скрепка в ленте есть, а списка нет — спросить, каким бы ни был размер.
    expect(
        ImapService.attachmentsMayBeMissing(
            size: null, attachmentsJson: '[]', bodyHtml: html, bodyPlain: null, hasAttachments: true),
        isTrue);
    // Большая рассылка: письмо большое, но это его же текст.
    final big = 'x' * 120000;
    expect(ImapService.attachmentsMayBeMissing(size: 150000, attachmentsJson: null, bodyHtml: big, bodyPlain: null),
        isFalse);
  });
}

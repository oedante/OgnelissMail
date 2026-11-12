// Файл «inline» без Content-ID — вложение (12.11.2026: фото с iPhone,
// пересланное из веб-почты Яндекса, в Gmail было, в приложении — нет).
import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

BodyPart _part(String type, {String? disposition, String? cid}) {
  final p = BodyPart()..contentType = ContentTypeHeader(type);
  if (disposition != null) p.contentDisposition = ContentDispositionHeader(disposition);
  p.cid = cid;
  return p;
}

void main() {
  test('image/jpeg; inline; filename без Content-ID — вложение, не встроенная', () {
    final root = _part('multipart/mixed');
    final alt = root.addPart(_part('multipart/alternative'));
    alt.addPart(_part('text/plain; charset=utf-8'));
    alt.addPart(_part('text/html; charset=utf-8'));
    root.addPart(_part('image/jpeg; name="image0.jpeg"', disposition: 'inline; filename="image0.jpeg"'));
    final list = <EmailAttachment>[];
    ImapService.collectAttachments(root, list);
    expect(list.map((a) => a.name), ['image0.jpeg']);
    expect(list.single.isInline, isFalse);
    expect(ImapService.hasFiles(root), isTrue);
  });

  test('картинка подписи с Content-ID — встроенная, тексты — не вложения', () {
    final root = _part('multipart/related');
    root.addPart(_part('text/html; charset=utf-8'));
    root.addPart(_part('image/png', disposition: 'inline', cid: '<logo@x>'));
    final list = <EmailAttachment>[];
    ImapService.collectAttachments(root, list);
    expect(list, hasLength(1));
    expect(list.single.isInline, isTrue);
    expect(ImapService.hasFiles(root), isFalse);
  });

  test('обычное письмо из одной части — без вложений', () {
    final root = _part('text/plain; charset=utf-8');
    final list = <EmailAttachment>[];
    ImapService.collectAttachments(root, list);
    expect(list, isEmpty);
  });
}

// Картинки в тексте исходящего письма — встроенными частями (2.7.2,
// замечание владельца 24.11.2026: в ответе картинка из цитаты пропала, у
// получателя — пустое место вместо скриншота). Картинки data: (вставленный
// скриншот, картинки цитаты) уходят частями multipart/related с Content-ID.

import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' show MediaSubtype;
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' as me;
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  // Картинка 1×1 PNG.
  const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg==';
  const html = '<p>Посмотрите</p><img src="data:image/png;base64,$png" width="600">'
      "<blockquote><img src='data:image/png;base64,$png'></blockquote>";

  test('data: → cid:, одинаковые картинки — одна часть', () {
    final r = me.MimeInlineImages.extract(html, domain: 'corp.example', stamp: 'x1');
    expect(r.parts, hasLength(1));
    expect(r.parts.single.cid, 'image001.x1@corp.example');
    expect(r.parts.single.mimeType, 'image/png');
    expect(r.parts.single.name, 'image001.png');
    expect(r.parts.single.bytes, base64.decode(png));
    expect(r.html, isNot(contains('data:')));
    expect(r.html, contains('src="cid:image001.x1@corp.example" width="600"'));
    expect(r.html, contains("src='cid:image001.x1@corp.example'"));
  });

  test('без картинок data: — HTML как есть; испорченная картинка — как есть', () {
    expect(me.MimeInlineImages.extract('<p>x</p><img src="cid:a@b">').parts, isEmpty);
    const bad = '<img src="data:image/png;base64,====">';
    final r = me.MimeInlineImages.extract(bad);
    expect(r.parts, isEmpty);
    expect(r.html, bad);
  });

  test('ActiveSync: multipart/related — HTML со ссылкой cid: и картинка с Content-ID', () {
    final mime = me.EasEngine().debugBuildMime(
      const me.AccountConfig(email: 'ivan@corp.example'),
      const me.OutgoingMessage(to: [me.MailAddress('anna@partner.example')], subject: 'RE: ФУЙ', bodyHtml: html),
    );
    expect(mime, contains('Content-Type: multipart/related; type="text/html"'));
    final cid = RegExp(r'Content-ID: <(image001\.[0-9a-z]+@corp\.example)>').firstMatch(mime)?.group(1);
    expect(cid, isNotNull);
    expect(mime, contains('Content-Disposition: inline; filename="image001.png"'));
    // HTML (base64) ссылается на ту же картинку.
    final htmlPart = RegExp(r'Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=\r\n]+)')
        .firstMatch(mime)!
        .group(1)!
        .replaceAll(RegExp(r'\s'), '');
    final body = utf8.decode(base64.decode(htmlPart));
    expect(body, contains('cid:$cid'));
    expect(body, isNot(contains('data:image')));
  });

  test('ActiveSync: с вложением — related внутри mixed', () {
    final mime = me.EasEngine().debugBuildMime(
      const me.AccountConfig(email: 'ivan@corp.example'),
      me.OutgoingMessage(
        to: const [me.MailAddress('anna@partner.example')],
        subject: 's',
        bodyHtml: html,
        attachments: [me.MailAttachment(id: 'a', name: 'отчёт.pdf', contentType: 'application/pdf', bytes: utf8.encode('%PDF'))],
      ),
    );
    final mixed = mime.indexOf('Content-Type: multipart/mixed');
    final related = mime.indexOf('Content-Type: multipart/related');
    expect(mixed, greaterThan(0));
    expect(related, greaterThan(mixed));
    expect(mime.indexOf('Content-Disposition: attachment'), greaterThan(related));
  });

  test('SMTP (IMAP): картинка — встроенной частью рядом с HTML', () {
    final m = ImapService.buildOutgoingMessage(
      fromName: 'Иван',
      fromEmail: 'ivan@corp.example',
      to: const [EmailAddress(email: 'anna@partner.example')],
      subject: 'RE: ФУЙ',
      bodyHtml: html,
    );
    final text = m.renderMessage();
    expect(text, contains('multipart/related'));
    expect(text, contains('Content-ID: <image001.'));
    expect(m.decodeTextHtmlPart(), contains('cid:image001.'));
    expect(m.decodeTextHtmlPart(), isNot(contains('data:image')));
    expect(m.decodeTextPlainPart(), contains('Посмотрите'));
    // Структура: alternative → (plain, related → (html, png)).
    expect(m.mediaType.sub, MediaSubtype.multipartAlternative);
  });

  test('SMTP (IMAP): без картинок — как раньше', () {
    final m = ImapService.buildOutgoingMessage(
      fromName: 'Иван',
      fromEmail: 'ivan@corp.example',
      to: const [EmailAddress(email: 'anna@partner.example')],
      subject: 's',
      bodyHtml: '<p>x</p>',
    );
    expect(m.renderMessage(), isNot(contains('multipart/related')));
  });
}

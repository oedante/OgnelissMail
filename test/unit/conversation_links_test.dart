// Ссылки беседы (2.2.0, план 08.11.2026 «из мессенджеров»: файлы и ссылки
// беседы).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/conversation_links.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/screens/conversation_files_screen.dart';

LinkSource _m(String id, int day, {String? html, String? plain, String from = 'Анна'}) =>
    (id: id, at: DateTime(2026, 11, day), from: from, html: html, plain: plain);

EmailModel _e(String id, int day, List<EmailAttachment> files) => EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'INBOX',
      from: const EmailAddress(email: 'anna@corp.example'),
      to: const [],
      subject: 'Отчёт',
      receivedAt: DateTime(2026, 11, day),
      attachments: files,
    );

void main() {
  test('ссылки HTML: текст ссылки, сайт; самые новые — первыми', () {
    final links = conversationLinks([
      _m('1', 1, html: '<p>Отчёт: <a href="https://docs.example.com/report?id=7">таблица</a></p>'),
      _m('2', 3, html: '<p>Сайт <a href="https://www.example.org/">https://www.example.org/</a></p>', from: 'Иван'),
    ]);
    expect([for (final l in links) l.url], ['https://www.example.org/', 'https://docs.example.com/report?id=7']);
    expect(links.first.text, isEmpty, reason: 'текст — сам адрес');
    expect(links.first.host, 'example.org');
    expect(links.first.from, 'Иван');
    expect(links.last.text, 'таблица');
    expect(links.last.emailId, '1');
  });

  test('ссылка из цитаты ответа — один раз, у письма, где появилась', () {
    const first = '<a href="https://example.com/plan">план</a>';
    final links = conversationLinks([
      _m('2', 5, html: '<p>Согласен</p><blockquote>$first</blockquote>'),
      _m('1', 2, html: '<p>Смотрите $first</p>'),
      _m('3', 6, html: '<blockquote><a href="HTTPS://EXAMPLE.COM/plan/#top">план</a></blockquote>'),
    ]);
    expect(links, hasLength(1));
    expect(links.single.emailId, '1');
  });

  test('не ссылки беседы: почта, телефон, картинки письма, люди и даты приложения', () {
    final links = conversationLinks([
      _m('1', 1,
          html: '<a href="mailto:anna@corp.example">Анна</a> <a href="tel:+74950000000">тел.</a> '
              '<a href="cid:image001.png">картинка</a> <a href="ogperson:anna%40corp.example">Анна</a> '
              '<a href="#top">наверх</a> <a href="javascript:void(0)">x</a>'),
    ]);
    expect(links, isEmpty);
  });

  test('письмо без HTML: адреса в тексте, без точки и скобки в конце', () {
    final links = conversationLinks([
      _m('1', 1, plain: 'Документ здесь: https://example.com/doc. И ещё (http://example.net/a?b=1), спасибо.'),
    ]);
    expect([for (final l in links) l.url], ['http://example.net/a?b=1', 'https://example.com/doc']);
  });

  test('файлы беседы: без картинок внутри текста, самые новые — первыми', () {
    final files = conversationFiles([
      _e('1', 1, const [
        EmailAttachment(id: 'a', name: 'отчёт.xlsx', size: 1000),
        EmailAttachment(id: 'b', name: 'image001.png', isInline: true, contentId: 'image001'),
      ]),
      _e('2', 4, const [EmailAttachment(id: 'c', name: 'договор.pdf', size: 2000)]),
    ]);
    expect([for (final f in files) f.file.name], ['договор.pdf', 'отчёт.xlsx']);
    expect(files.first.email.id, '2');
  });
}

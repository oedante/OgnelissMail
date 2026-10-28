// «К встрече» (MeetingPrep, 1.6.12): письма той же переписки, что и встреча,
// — тема как при группировке бесед, а не отдельные слова темы.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/calendar/meeting_prep.dart';

final _now = DateTime(2026, 10, 10, 12);

PrepCandidate _mail(String id, String subject,
        {int daysAgo = 1, List<EmailAttachment> files = const [], String? conv}) =>
    PrepCandidate(
      id: id,
      accountId: 'a',
      fromEmail: 'ivan@firm.ru',
      subject: subject,
      receivedAt: _now.subtract(Duration(days: daysAgo)),
      attachments: files,
      conversationId: conv,
    );

void main() {
  group('topicKey', () {
    test('приставки ответа, пересылки и приглашений срезаются', () {
      expect(MeetingPrep.topicKey('RE: FW: Графики ремонта 2027'), 'графики ремонта 2027');
      expect(MeetingPrep.topicKey('Приглашение: Графики ремонта 2027'), 'графики ремонта 2027');
      expect(MeetingPrep.topicKey('Updated invitation: Графики  ремонта 2027.'), 'графики ремонта 2027');
      expect(MeetingPrep.topicKey('Отв: Пересл: Ёлка'), 'елка');
    });
  });

  group('rank', () {
    final key = MeetingPrep.topicKey('Графики ремонта');

    test('только та же тема переписки, новые сверху; похожие темы — нет', () {
      final list = MeetingPrep.rank([
        _mail('old', 'Графики ремонта', daysAgo: 9),
        _mail('new', 'RE: Графики ремонта', daysAgo: 1),
        _mail('x', 'Ремонт кровли, графики', daysAgo: 2),
        _mail('y', 'Графики ремонта насосов', daysAgo: 3),
      ], key: key);
      expect(list.map((m) => m.id), ['new', 'old']);
    });

    test('письмо той же беседы с изменённой темой — тоже к встрече', () {
      final list = MeetingPrep.rank([
        _mail('a', 'Графики ремонта', conv: 'c1'),
        _mail('b', 'RE: Графики — правки Ивана', daysAgo: 2, conv: 'c1'),
        _mail('c', 'Другое', conv: 'c2'),
      ], key: key, conversations: {'c1'});
      expect(list.map((m) => m.id), ['a', 'b']);
    });

    test('пустая тема встречи — ничего', () {
      expect(MeetingPrep.rank([_mail('a', '')], key: ''), isEmpty);
    });
  });

  test('вложения без встроенных картинок и повторов', () {
    const doc = EmailAttachment(id: '1', name: 'График.xlsx');
    const logo = EmailAttachment(id: '2', name: 'image001.png', mimeType: 'image/png', isInline: true);
    const pdf = EmailAttachment(id: '4', name: 'Акт.pdf', mimeType: 'application/pdf', isInline: true);
    final files = MeetingPrep.files([
      _mail('a', 's', files: const [doc, logo, pdf]),
      _mail('b', 's2', files: const [EmailAttachment(id: '3', name: 'график.XLSX')]),
    ]);
    expect(files.map((f) => f.file.name), ['График.xlsx', 'Акт.pdf']);
  });
}

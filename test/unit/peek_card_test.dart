// Карточка письма по удержанию (1.6.46): «Ответить» или «Ответить всем»,
// удержание короче системного.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/widgets/mail_peek_card.dart';
import 'package:ogneliss/widgets/common/quick_long_press.dart';

EmailModel _mail({
  String from = 'boss@corp.ru',
  List<String> to = const ['me@corp.ru'],
  List<String> cc = const [],
}) =>
    EmailModel(
      id: 'm1',
      accountId: 'a1',
      folderId: 'inbox',
      subject: 'Отчёт',
      from: EmailAddress(email: from),
      to: [for (final t in to) EmailAddress(email: t)],
      cc: [for (final c in cc) EmailAddress(email: c)],
      bcc: const [],
      receivedAt: DateTime(2026, 10, 19, 12),
      hasAttachments: false,
      tags: const [],
      priority: EmailPriority.normal,
      isRead: false,
      isFlagged: false,
      isDraft: false,
    );

void main() {
  const own = {'me@corp.ru', 'me.alias@corp.ru'};

  group('Ответить или Ответить всем', () {
    test('письмо лично мне — «Ответить»', () {
      expect(peekWantsReplyAll(_mail(), own), isFalse);
      // Мой адрес другим регистром и вторым адресом ящика — всё равно я.
      expect(peekWantsReplyAll(_mail(to: ['Me@Corp.ru', 'me.alias@corp.ru']), own), isFalse);
      // Отправитель сам в копии — отвечать всё равно только ему.
      expect(peekWantsReplyAll(_mail(cc: ['boss@corp.ru']), own), isFalse);
    });

    test('есть ещё адресаты — «Ответить всем»', () {
      expect(peekWantsReplyAll(_mail(to: ['me@corp.ru', 'colleague@corp.ru']), own), isTrue);
      expect(peekWantsReplyAll(_mail(cc: ['colleague@corp.ru']), own), isTrue);
    });

    test('своё письмо — как раньше, «Ответить всем»', () {
      expect(peekWantsReplyAll(_mail(from: 'me@corp.ru', to: ['client@x.ru']), own), isTrue);
    });
  });

  test('удержание до карточки — вдвое короче системного', () {
    expect(HoldTiming.quick, const Duration(milliseconds: 250));
    expect(HoldTiming.peek, HoldTiming.quick);
  });
}

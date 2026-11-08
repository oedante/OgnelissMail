// Черновики беседы — экран перестраивается, только когда они изменились
// (2.0.0, план 08.11.2026).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/screens/conversation_screen.dart';

EmailModel _d(String id, String subject) => EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'drafts',
      from: const EmailAddress(email: 'me@example.com'),
      to: const [],
      subject: subject,
      receivedAt: DateTime(2026, 11, 8, 10),
      isDraft: true,
    );

void main() {
  test('те же черновики — без перестройки; другая тема или новый — с перестройкой', () {
    expect(sameDraftList([_d('1', 'Re: отчёт')], [_d('1', 'Re: отчёт')]), isTrue);
    expect(sameDraftList([_d('1', 'Re: отчёт')], [_d('1', 'Re: отчёт за ноябрь')]), isFalse);
    expect(sameDraftList([_d('1', 'Re: отчёт')], [_d('1', 'Re: отчёт'), _d('2', 'Re: план')]), isFalse);
    expect(sameDraftList(const [], const []), isTrue);
  });
}

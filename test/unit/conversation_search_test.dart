// Поиск по беседе (2.2.0, план 08.11.2026 «из мессенджеров»): тексты писем
// для поиска и открытие письма с тем же поиском.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/navigation/app_router.dart' show conversationMessagePath;
import 'package:ogneliss/features/mail/screens/conversation_screen.dart' show conversationSearchTexts;

void main() {
  test('текст письма для поиска: тема, отправитель, текст без разметки — строчными', () {
    final t = conversationSearchTexts([
      (id: '1', head: 'Отчёт\nАнна anna@corp.example', html: '<p>Смета <b>ГОТОВА</b></p><style>p{}</style>', plain: null),
      (id: '2', head: 'Re: Отчёт\nИван ivan@corp.example', html: null, plain: 'Принято, спасибо'),
    ]);
    expect(t['1'], contains('смета готова'));
    expect(t['1'], contains('anna@corp.example'));
    expect(t['2'], contains('принято, спасибо'));
    expect(t['2'], startsWith('re: отчёт'));
  });

  test('письмо из поиска по беседе открывается с тем же запросом', () {
    expect(conversationMessagePath('c 1', 'INBOX:5', accountId: 'a1', find: ' смета '),
        '/mail/conversation/c%201/INBOX%3A5?accountId=a1&find=%D1%81%D0%BC%D0%B5%D1%82%D0%B0');
    expect(conversationMessagePath('c1', 'e1', accountId: 'a1'), '/mail/conversation/c1/e1?accountId=a1');
    expect(conversationMessagePath('c1', 'e1', accountId: 'a1', find: '  '), '/mail/conversation/c1/e1?accountId=a1');
  });
}

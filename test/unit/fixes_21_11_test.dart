// Замечания владельца 21.11.2026: темы без RE/FW в списках, имена вложений
// RFC 2231, приветствия с переносами и время суток в меню, приветствия на
// других языках.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/subject_prefix.dart';
import 'package:ogneliss/l10n/strings_store.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';
import 'package:ogneliss/services/mail/mail_tags.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final l in ['ru', 'en', 'de', 'ja', 'ar', 'fr']) {
      await StringsStore.ensure(l);
    }
  });

  test('тема в списке — без RE/FW; один префикс — как есть', () {
    expect(SubjectPrefix.display('RE: Статусы задач ОПТиКР'), 'Статусы задач ОПТиКР');
    expect(SubjectPrefix.display('FW: RE: Бронирование'), 'Бронирование');
    expect(SubjectPrefix.display('Отв: Re[2]: Заезд'), 'Заезд');
    expect(SubjectPrefix.display('Беседа: Иванов'), 'Беседа: Иванов');
    expect(SubjectPrefix.display('RE:'), 'RE:');
    expect(SubjectPrefix.reply('RE: тема'), 'RE: тема', reason: 'в самом письме префикс остаётся');
  });

  test('имя вложения RFC 2231: utf-8\'\'%D0… и с потерянной кавычкой utf-8"%D0…', () {
    expect(ImapService.decodeFileName("utf-8''%D0%9A%D0%B0%D1%80%D1%82%D0%B0.pdf"), 'Карта.pdf');
    expect(ImapService.decodeFileName('utf-8"%D0%9A%D0%B0%D1%80%D1%82%D0%B0.pdf'), 'Карта.pdf');
    expect(ImapService.decodeFileName("UTF-8'ru'%D0%9A%D0%B0.txt"), 'Ка.txt');
    expect(ImapService.decodeFileName('=?UTF-8?B?0JrQsNGA0YLQsC5wZGY=?='), 'Карта.pdf');
    expect(ImapService.decodeFileName('report.pdf'), 'report.pdf');
  });

  final morning = DateTime(2026, 11, 19, 9, 33);

  test('приветствие: перенос строки сохраняется, время суток в меню — всеми вариантами', () {
    final v = MailTagValues(now: morning, lang: 'ru');
    expect(MailTags.apply('{время_суток}\n{дата}', v, cleanup: true), 'Доброе утро\n19.11.2026');
    final any = MailTagValues(now: morning, lang: 'ru', anyTime: true);
    expect(MailTags.apply('{время_суток}\n{дата}', any, cleanup: true), 'Доброе утро/Добрый день/Добрый вечер\n19.11.2026');
    expect(MailTags.partOfDayAll('en'), 'Good morning/Good afternoon/Good evening');
    expect(MailTags.partOfDayAll('ru', sep: ' / '), 'Доброе утро / Добрый день / Добрый вечер');
    // Первым в конструкторе — время суток.
    expect(MailTags.forGreeting.first.key, 'part_of_day');
  });

  test('приветствие на других языках: обращение, время суток, знаки без лишних запятых', () {
    String greet(String lang, String tpl, List<String> names, List<String> emails) => MailTags.apply(
        tpl,
        MailTagValues(
            recipient: MailTags.recipient(names: names, emails: emails, lang: lang), now: morning, lang: lang),
        cleanup: true);
    expect(greet('en', '{part_of_day}, {to_address}!', ['John Smith'], ['j@x.example']), 'Good morning, John!');
    expect(greet('en', '{part_of_day}, {to_address}!', [''], ['info@x.example']), 'Good morning!');
    expect(greet('de', '{part_of_day}, {to_address}!', [''], ['info@x.example']), startsWith('Guten Morgen'));
    expect(greet('ja', '{part_of_day}、{to_address}！', [''], ['info@x.example']), isNot(contains('、！')));
    expect(greet('ar', '{part_of_day}، {to_address}!', [''], ['info@x.example']), isNot(contains('،!')));
    expect(greet('fr', '{part_of_day}, {to_address} !', [''], ['info@x.example']), isNot(contains(', !')));
  });
}

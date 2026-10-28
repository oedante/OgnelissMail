// Чистые функции транспортов: имена папок IMAP (modified UTF-7) и адрес EWS.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/mail/ews/ews_service.dart';
import 'package:ogneliss/services/mail/imap/imap_service.dart';

void main() {
  group('IMAP modified UTF-7', () {
    test('кириллица', () {
      expect(ImapService.decodeMutf7('&BB4EQgQ,BEAEMAQyBDsENQQ9BD0ESwQ1-'), 'Отправленные');
      expect(ImapService.decodeMutf7('&BCMENAQwBDsEUQQ9BD0ESwQ1-'), 'Удалённые');
    });
    test('ASCII и амперсанд', () {
      expect(ImapService.decodeMutf7('INBOX'), 'INBOX');
      expect(ImapService.decodeMutf7('Q&-A'), 'Q&A');
    });
    test('смешанное имя', () {
      expect(ImapService.decodeMutf7('&BBAEQARFBDgEMg- 2024'), 'Архив 2024');
    });
  });

  group('Адрес EWS из поля «Сервер»', () {
    test('имя хоста', () {
      expect(EwsService.ewsUrlFromServer('mail.corp.ru'), 'https://mail.corp.ru/EWS/Exchange.asmx');
    });
    test('хост со схемой и слешем', () {
      expect(EwsService.ewsUrlFromServer('https://mail.corp.ru/'), 'https://mail.corp.ru/EWS/Exchange.asmx');
    });
    test('полный адрес не меняется', () {
      expect(EwsService.ewsUrlFromServer('https://mail.corp.ru/EWS/Exchange.asmx'),
          'https://mail.corp.ru/EWS/Exchange.asmx');
      expect(EwsService.ewsUrlFromServer('mail.corp.ru/EWS/Exchange.asmx'),
          'https://mail.corp.ru/EWS/Exchange.asmx');
    });
  });
}

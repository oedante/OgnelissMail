// 1.7.3: фильтры на сервере у каждого ящика — какой вид (Sieve, Exchange,
// только веб-почта) и запрос EWS для нового правила.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/services/mail/ews/ews_server_tools.dart';
import 'package:ogneliss/services/mail/server_filters.dart';
import 'package:ogneliss/services/mail/sieve/sieve_rules.dart';

AccountModel _acc(AccountType type, String email, {String? imap, String? parent, String id = 'a1'}) => AccountModel(
      id: id,
      type: type,
      email: email,
      displayName: email,
      username: email,
      imapServer: imap,
      parentAccountId: parent,
      createdAt: DateTime(2026),
    );

void main() {
  group('вид фильтров', () {
    test('IMAP своего сервера — Sieve', () {
      expect(ServerFilters.kindOf(_acc(AccountType.imap, 'me@corp.ru', imap: 'mail.corp.ru')), ServerFilterKind.sieve);
    });

    test('iCloud по паролю приложения — только веб-почта (порт 4190 закрыт)', () {
      final a = _acc(AccountType.imap, 'me@icloud.com', imap: 'imap.mail.me.com');
      expect(ServerFilters.kindOf(a), ServerFilterKind.webOnly);
      expect(ServerFilters.webHintKey(a), 'srvFiltersWeb_icloud');
    });

    test('свой домен на Яндекс 360 — по серверу IMAP', () {
      final a = _acc(AccountType.imap, 'me@firma.ru', imap: 'imap.yandex.ru');
      expect(ServerFilters.kindOf(a), ServerFilterKind.webOnly);
      expect(ServerFilters.webHintKey(a), 'srvFiltersWeb_yandex');
    });

    test('домены с разными зонами: yahoo.co.uk, gmx.net', () {
      expect(ServerFilters.knownWebOnly('x@yahoo.co.uk', null), 'yahoo');
      expect(ServerFilters.knownWebOnly('x@gmx.net', null), 'gmx');
      expect(ServerFilters.knownWebOnly('x@corp.ru', 'mail.corp.ru'), isNull);
    });

    test('вход через аккаунт службы — веб-почта', () {
      expect(ServerFilters.kindOf(_acc(AccountType.google, 'me@gmail.com')), ServerFilterKind.webOnly);
      expect(ServerFilters.webHintKey(_acc(AccountType.outlook, 'me@company.com')), 'srvFiltersWeb_outlook');
    });

    test('Exchange (ActiveSync и EWS) — правила Exchange', () {
      expect(ServerFilters.kindOf(_acc(AccountType.activesync, 'me@acme.example')), ServerFilterKind.exchange);
      expect(ServerFilters.kindOf(_acc(AccountType.exchange, 'me@corp.ru')), ServerFilterKind.exchange);
    });

    test('общий ящик и архив Exchange — без своего пункта', () {
      expect(ServerFilters.applies(_acc(AccountType.activesync, 'boss@corp.ru', parent: 'a0')), isFalse);
      expect(ServerFilters.applies(_acc(AccountType.exchange, 'me@corp.ru', id: 'archive_a1')), isFalse);
      expect(ServerFilters.applies(_acc(AccountType.exchange, 'me@corp.ru')), isTrue);
    });
  });

  group('новое правило Exchange (EWS)', () {
    test('отправитель содержит → переложить и остановить', () {
      const r = SieveRule(
        name: 'Отчёты',
        field: SieveField.from,
        value: 'reports@',
        action: SieveAction.move,
        arg: 'AAMkAD=',
        stop: true,
      );
      final body = EwsServerTools.createRuleBody(r, 3);
      expect(body, contains('<m:RemoveOutlookRuleBlob>false</m:RemoveOutlookRuleBlob>'));
      expect(body, contains('<t:DisplayName>Отчёты</t:DisplayName>'));
      expect(body, contains('<t:Priority>3</t:Priority>'));
      expect(body, contains('<t:ContainsSenderStrings><t:String>reports@</t:String></t:ContainsSenderStrings>'));
      expect(body, contains('<t:MoveToFolder><t:FolderId Id="AAMkAD="/></t:MoveToFolder><t:StopProcessingRules>true'));
    });

    test('отправитель совпадает — FromAddresses; тема — только «содержит»', () {
      const from = SieveRule(name: '', field: SieveField.from, op: SieveOp.isExactly, value: 'a@b.ru', action: SieveAction.markRead);
      expect(EwsServerTools.conditionsXml(from),
          '<t:FromAddresses><t:Address><t:EmailAddress>a@b.ru</t:EmailAddress></t:Address></t:FromAddresses>');
      const subj = SieveRule(name: '', field: SieveField.subject, op: SieveOp.isExactly, value: 'x & y', action: SieveAction.delete);
      expect(EwsServerTools.conditionsXml(subj), '<t:ContainsSubjectStrings><t:String>x &amp; y</t:String></t:ContainsSubjectStrings>');
      // Удаление всегда останавливает обработку.
      expect(EwsServerTools.actionsXml(subj), '<t:Delete>true</t:Delete><t:StopProcessingRules>true</t:StopProcessingRules>');
    });

    test('пересылка и имя по умолчанию — значение условия', () {
      const r = SieveRule(name: ' ', field: SieveField.any, value: 'счёт', action: SieveAction.forward, arg: 'buh@corp.ru');
      final body = EwsServerTools.createRuleBody(r, 0);
      expect(body, contains('<t:DisplayName>счёт</t:DisplayName>'));
      expect(body, contains('<t:Priority>1</t:Priority>'));
      expect(body, contains('<t:ContainsSubjectOrBodyStrings>'));
      expect(body, contains('<t:ForwardToRecipients><t:Address><t:EmailAddress>buh@corp.ru</t:EmailAddress>'));
    });
  });
}

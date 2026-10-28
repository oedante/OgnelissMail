// test/unit/own_addresses_rules_test.dart
// Свои адреса ящика, правила на телефоне, склейка копий писем Gmail,
// «На контроле» с несколькими своими адресами.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/services/mail/control_service.dart';
import 'package:ogneliss/services/mail/own_addresses.dart';
import 'package:ogneliss/services/rules/device_rules_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AccountModel _acc({String email = 'i.petrov@acmegrp.example'}) => AccountModel(
      id: 'a1',
      type: AccountType.activesync,
      email: email,
      displayName: 'i.petrov',
      username: 'i.petrov',
      createdAt: DateTime(2026),
    );

EmailModel _mail({
  String from = 'colleague@acmegroup.example',
  String subject = 'Отчёт',
  List<String> to = const ['i.petrov@acmegroup.example'],
  List<String> cc = const [],
  bool attachments = false,
  String? unsubscribe,
}) =>
    EmailModel(
      id: 'm1',
      accountId: 'a1',
      folderId: 'inbox',
      subject: subject,
      from: EmailAddress(email: from),
      to: [for (final t in to) EmailAddress(email: t)],
      cc: [for (final c in cc) EmailAddress(email: c)],
      bcc: const [],
      receivedAt: DateTime(2026, 10, 9, 12),
      hasAttachments: attachments,
      listUnsubscribe: unsubscribe,
      tags: const [],
      priority: EmailPriority.normal,
      isRead: false,
      isFlagged: false,
      isDraft: false,
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OwnAddresses.load(await SharedPreferences.getInstance());
  });

  group('OwnAddresses', () {
    test('адрес входа с опечаткой + основной с сервера — оба свои', () async {
      final a = _acc();
      expect(OwnAddresses.isMine(a, 'i.petrov@acmegroup.example'), isFalse);
      await OwnAddresses.remember('a1', ['I.Petrov@acmegroup.example']);
      expect(OwnAddresses.isMine(a, 'i.petrov@acmegroup.example'), isTrue);
      expect(OwnAddresses.isMine(a, 'i.petrov@acmegrp.example'), isTrue);
      expect(OwnAddresses.domains(a), containsAll(['acmegrp.example', 'acmegroup.example']));
      expect(OwnAddresses.primary(a), 'i.petrov@acmegroup.example');
    });

    test('забыть ящик', () async {
      await OwnAddresses.remember('a1', ['x@y.ru']);
      await OwnAddresses.forget('a1');
      expect(OwnAddresses.learned('a1'), isEmpty);
    });
  });

  group('DeviceRule', () {
    test('домен ловит и поддомены, адрес — только себя', () {
      expect(DeviceRule.senderMatches('firm.ru', 'a@firm.ru'), isTrue);
      expect(DeviceRule.senderMatches('@firm.ru', 'a@mail.firm.ru'), isTrue);
      expect(DeviceRule.senderMatches('firm.ru', 'a@notfirm.ru'), isFalse);
      expect(DeviceRule.senderMatches('boss@firm.ru', 'boss@firm.ru'), isTrue);
      expect(DeviceRule.senderMatches('boss@firm.ru', 'other@firm.ru'), isFalse);
    });

    test('все условия вместе; выключенное и без условий не срабатывают', () {
      final a = _acc();
      const r = DeviceRule(id: 'r', senders: ['acmegroup.example'], subject: 'отчёт', notify: RuleNotify.silent);
      expect(r.matches(_mail(), a), isTrue);
      expect(r.matches(_mail(subject: 'Привет'), a), isFalse);
      expect(r.copyWith(enabled: false).matches(_mail(), a), isFalse);
      expect(const DeviceRule(id: 'e', notify: RuleNotify.none).matches(_mail(), a), isFalse);
    });

    test('«я только в копии» — по всем своим адресам', () async {
      final a = _acc();
      await OwnAddresses.remember('a1', ['i.petrov@acmegroup.example']);
      const r = DeviceRule(id: 'r', ccOnly: true, markRead: true);
      expect(r.matches(_mail(to: const ['boss@acmegroup.example'], cc: const ['i.petrov@acmegroup.example']), a), isTrue);
      expect(r.matches(_mail(), a), isFalse);
    });

    test('рассылка: List-Unsubscribe или адрес рассылок', () {
      expect(DeviceRule.isMailingList(_mail(unsubscribe: '<https://x/u>')), isTrue);
      expect(DeviceRule.isMailingList(_mail(from: 'noreply@shop.ru')), isTrue);
      expect(DeviceRule.isMailingList(_mail()), isFalse);
    });

    test('JSON туда и обратно', () {
      const r = DeviceRule(
          id: 'r', name: 'N', accountId: 'a1', senders: ['x.ru'], subject: 's', ccOnly: true,
          hasAttachment: true, mailingList: true, notify: RuleNotify.always, moveFolderId: 'f',
          moveFolderName: 'Папка', markRead: true, flag: true, later: RuleLater.tomorrow, control: true,
          tag: 'T', highlight: true);
      final back = DeviceRule.fromJson(r.toJson());
      expect(back.toJson(), r.toJson());
    });

    test('«Позже»: вечер, завтра, понедельник', () {
      final mon = DateTime(2026, 10, 12, 10); // понедельник
      expect(DeviceRulesNotifier.laterTime(RuleLater.evening, mon), DateTime(2026, 10, 12, 18));
      expect(DeviceRulesNotifier.laterTime(RuleLater.evening, DateTime(2026, 10, 12, 19)), DateTime(2026, 10, 13, 18));
      expect(DeviceRulesNotifier.laterTime(RuleLater.tomorrow, mon), DateTime(2026, 10, 13, 9));
      expect(DeviceRulesNotifier.laterTime(RuleLater.nextWeek, mon), DateTime(2026, 10, 19, 9));
      expect(DeviceRulesNotifier.laterTime(RuleLater.nextWeek, DateTime(2026, 10, 10)), DateTime(2026, 10, 12, 9));
    });
  });

  group('ControlService со списком своих адресов', () {
    test('«Кому» без меня и состояние по отправителю', () {
      const mine = 'i.petrov@acmegrp.example,i.petrov@acmegroup.example';
      const toJson = '[{"email":"I.Petrov@acmegroup.example"},{"email":"boss@acmegroup.example"}]';
      expect(ControlService.toRecipients(toJson, mine), ['boss@acmegroup.example']);
      expect(ControlService.initialFor(fromEmail: 'i.petrov@acmegroup.example', myEmail: mine), ControlState.awaitingReply);
      expect(ControlService.initialFor(fromEmail: 'boss@acmegroup.example', myEmail: mine), ControlState.mustReply);
    });
  });
}

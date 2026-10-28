import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/rules/auto_rules_service.dart';
import 'package:ogneliss/data/models/email_model.dart';

void main() {
  group('RuleCondition', () {
    final testEmail = EmailModel(
      id: '1', accountId: 'acc1', folderId: 'inbox', internetMessageId: '<test@test>',
      subject: 'Тестовое письмо',
      from: const EmailAddress(email: 'sender@example.com', displayName: 'Иванов И.И.'),
      to: [const EmailAddress(email: 'me@example.com')], cc: [], bcc: [],
      receivedAt: DateTime.now(), size: 1024, hasAttachments: false,
      tags: [], priority: EmailPriority.normal, isRead: false, isFlagged: false,
      isDraft: false,
    );

    test('senderContains matches', () {
      const cond = RuleCondition(type: RuleConditionType.senderContains, value: 'example');
      expect(cond.matches(testEmail), isTrue);
    });

    test('senderContains no match', () {
      const cond = RuleCondition(type: RuleConditionType.senderContains, value: 'gmail');
      expect(cond.matches(testEmail), isFalse);
    });

    test('senderEquals matches', () {
      const cond = RuleCondition(type: RuleConditionType.senderEquals, value: 'sender@example.com');
      expect(cond.matches(testEmail), isTrue);
    });

    test('subjectContains matches', () {
      const cond = RuleCondition(type: RuleConditionType.subjectContains, value: 'тестовое');
      expect(cond.matches(testEmail), isTrue);
    });

    test('hasAttachments no match', () {
      const cond = RuleCondition(type: RuleConditionType.hasAttachments);
      expect(cond.matches(testEmail), isFalse);
    });
  });

  group('AutoRule', () {
    final testEmail = EmailModel(
      id: '1', accountId: 'acc1', folderId: 'inbox', internetMessageId: '<test@test>',
      subject: 'Отчёт за квартал',
      from: const EmailAddress(email: 'boss@example.com'),
      to: [const EmailAddress(email: 'me@example.com')], cc: [], bcc: [],
      receivedAt: DateTime.now(), size: 512, hasAttachments: false,
      tags: [], priority: EmailPriority.normal, isRead: false, isFlagged: false,
      isDraft: false,
    );

    test('matchAll AND logic', () {
      const rule = AutoRule(
        id: '1', name: 'Test',
        conditions: [
          RuleCondition(type: RuleConditionType.senderContains, value: 'example'),
          RuleCondition(type: RuleConditionType.subjectContains, value: 'отчёт'),
        ],
        matchAll: true,
      );
      expect(rule.matches(testEmail), isTrue);
    });

    test('matchAll AND fails if one condition fails', () {
      const rule = AutoRule(
        id: '1', name: 'Test',
        conditions: [
          RuleCondition(type: RuleConditionType.senderContains, value: 'example'),
          RuleCondition(type: RuleConditionType.subjectContains, value: 'срочно'),
        ],
        matchAll: true,
      );
      expect(rule.matches(testEmail), isFalse);
    });

    test('matchAll OR logic', () {
      const rule = AutoRule(
        id: '1', name: 'Test',
        conditions: [
          RuleCondition(type: RuleConditionType.senderContains, value: 'gmail'),
          RuleCondition(type: RuleConditionType.subjectContains, value: 'отчёт'),
        ],
        matchAll: false,
      );
      expect(rule.matches(testEmail), isTrue);
    });
  });
}

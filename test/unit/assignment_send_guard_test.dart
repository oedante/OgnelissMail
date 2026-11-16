// Поручения (15.11.2026): напоминание не уходит повторно чаще раза в
// полчаса (кнопку нажали 41 раз — 41 письмо), внешние адресаты рабочего
// ящика — та же проверка, что у обычного письма.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart' show AssignmentEvent;
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/features/compose/widgets/recipients_check.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart';

AssignmentEvent _ev(String type, DateTime at, {int direction = 0}) => AssignmentEvent(
      id: 'e${at.microsecondsSinceEpoch}$type$direction',
      assignmentId: 'A',
      type: type,
      authorEmail: 'boss@corp.example',
      direction: direction,
      createdAt: at,
      payloadJson: '{}',
      deliveryStatus: 0,
      signatureState: 0,
    );

void main() {
  final now = DateTime(2026, 11, 15, 18, 7);

  group('повтор напоминания', () {
    test('не напоминали — можно', () {
      expect(AssignmentService.lastReminder(const []), isNull);
      expect(AssignmentService.remindedRecently(const [], now: now), isFalse);
    });

    test('своё напоминание минуту назад — рано; через полчаса — можно', () {
      final events = [_ev('reminder', now.subtract(const Duration(minutes: 1)))];
      expect(AssignmentService.remindedRecently(events, now: now), isTrue);
      expect(AssignmentService.remindedRecently(events, now: now.add(const Duration(minutes: 30))), isFalse);
    });

    test('последнее из нескольких; чужие напоминания и другие события не считаются', () {
      final events = [
        _ev('reminder', now.subtract(const Duration(hours: 2))),
        _ev('reminder', now.subtract(const Duration(minutes: 5))),
        _ev('reminder', now.subtract(const Duration(minutes: 1)), direction: 1),
        _ev('status', now),
      ];
      expect(AssignmentService.lastReminder(events), now.subtract(const Duration(minutes: 5)));
      expect(AssignmentService.remindedRecently([events.first, events[2], events[3]], now: now), isFalse);
    });
  });

  group('внешние адресаты', () {
    AccountModel acc(AccountType type, String email) => AccountModel(
          id: 'a1',
          type: type,
          email: email,
          displayName: 'Клинов',
          username: email,
          createdAt: DateTime(2026),
        );

    test('рабочий ящик: личная почта и чужие домены — внешние, поддомены своего — нет', () {
      final work = acc(AccountType.exchange, 'a.klinov@yamalspg.ru');
      expect(
        externalDomainsOf(work, ['o.tostring@yandex.ru', 'r.k@msk.yamalspg.ru', 'x@YAMALSPG.ru', 'p@novatek.ru']),
        {'yandex.ru', 'novatek.ru'},
      );
    });

    test('личный ящик — без предупреждения (внешние все)', () {
      expect(externalDomainsOf(acc(AccountType.imap, 'me@gmail.com'), ['a@yandex.ru']), isEmpty);
      expect(externalDomainsOf(null, ['a@yandex.ru']), isEmpty);
    });
  });
}

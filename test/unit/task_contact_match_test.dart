// test/unit/task_contact_match_test.dart
// Человек в задаче: «позвонить Смирнову Андрею» → контакт «Смирнов Андрей».

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/tasks/task_contact_match.dart';

void main() {
  test('падежные формы фамилии и имени', () {
    expect(nameFormMatches('Смирнову', 'Смирнов'), isTrue);
    expect(nameFormMatches('Андрею', 'Андрей'), isTrue);
    expect(nameFormMatches('Ивановой', 'Иванова'), isTrue);
    expect(nameFormMatches('Ольге', 'Ольга'), isTrue);
    expect(nameFormMatches('Смирнов', 'Смирнов'), isTrue);
  });

  test('разные фамилии не совпадают', () {
    expect(nameFormMatches('Климову', 'Смирнов'), isFalse);
    expect(nameFormMatches('Иванову', 'Ивашов'), isFalse);
    expect(nameFormMatches('Ли', 'Лиханов'), isFalse);
  });

  test('слова с заглавной буквы', () {
    expect(mentionTokens('в 10 утра позвонить Смирнову Андрею'), ['Смирнову', 'Андрею']);
    expect(mentionTokens('купить хлеб'), isEmpty);
  });
}

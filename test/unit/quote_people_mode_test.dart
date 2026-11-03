// «Люди в цитатах» с 1.10.5 включены по умолчанию, имена — «Фамилия И.О.»
// (решение владельца 03.11.2026). Выключенные вручную в «Экспериментальном»
// (1.10.3–1.10.4) остаются выключенными.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/settings/widgets/feature_settings_sections.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<QuotePeopleMode> _mode(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  return quotePeopleMode(await SharedPreferences.getInstance());
}

void main() {
  test('по умолчанию — кратко', () async {
    expect(await _mode({}), QuotePeopleMode.short);
  });

  test('включённые в «Экспериментальном» — кратко, выключенные вручную — выключены', () async {
    expect(await _mode({ExperimentalKeys.quotePeople: true}), QuotePeopleMode.short);
    expect(await _mode({ExperimentalKeys.quotePeople: false}), QuotePeopleMode.off);
  });

  test('выбор в настройке важнее прежнего выключателя', () async {
    expect(await _mode({ExperimentalKeys.quotePeople: false, ExperimentalKeys.quotePeopleNames: 'full'}),
        QuotePeopleMode.full);
    expect(await _mode({ExperimentalKeys.quotePeopleNames: 'off'}), QuotePeopleMode.off);
    expect(await _mode({ExperimentalKeys.quotePeopleNames: 'мусор'}), QuotePeopleMode.short);
  });
}

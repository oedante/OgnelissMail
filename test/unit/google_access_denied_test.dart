// «Календарь и контакты Google» (2.6.8, случай пользователя 21.11.2026): на
// странице входа Google галочки календаря и контактов не отмечены — календарь
// и фото собеседников молчали, а настройки ящика писали «подключены».

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/settings/screens/account_screen.dart' show googleDenied;
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('чего Google не дал — словами; всё выдано — null', () async {
    SharedPreferences.setMockInitialValues({'people_photos_v2:a1:denied': true});
    final prefs = await SharedPreferences.getInstance();
    final l10n = AppLocalizations(const Locale('ru'));
    expect(
      googleDenied('a1', prefs, l10n, dav: (calendar: true, contacts: false)),
      'Google не дал доступ: календарь, фото собеседников. Нажмите, войдите и отметьте все галочки на странице Google',
    );
    expect(googleDenied('a2', prefs, l10n, dav: (calendar: false, contacts: false)), isNull);
  });
}

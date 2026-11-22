// Контакты и календарь ящиков в телефоне — по умолчанию (2.7.0, замечание
// владельца 22.11.2026: «у каждого аккаунта нужно всегда включать по
// умолчанию или вообще убрать из настроек»; «он ожидает, что приложение
// будет настроено и сразу будет работать»). Google (и iCloud на iPhone)
// телефон синхронизирует сам — не дублируются; включённый раньше вручную
// ящик остаётся включённым; общий выключатель — для всех.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/services/device/phone_mirror_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Accounts extends AccountsNotifier {
  _Accounts(AppDatabase db, this.list) : super(db, SecureStorageService());
  final List<AccountModel> list;

  /// После загрузки из (пустой) базы — свой список.
  void put() => state = list;
}

AccountModel _acc(String id, AccountType type, String email, {String? imap}) => AccountModel(
      id: id,
      type: type,
      email: email,
      displayName: id,
      username: email,
      imapServer: imap,
      createdAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final work = _acc('work', AccountType.activesync, 'me@corp.example');
  final yandex = _acc('ya', AccountType.yandex, 'me@yandex.ru');
  final gmail = _acc('gm', AccountType.google, 'me@gmail.com');
  final icloud = _acc('ic', AccountType.imap, 'me@icloud.com', imap: 'imap.mail.me.com');
  final archive = _acc('archive_work', AccountType.activesync, 'me@corp.example');

  Future<(ProviderContainer, PhoneMirrorService)> make([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final c = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      databaseProvider.overrideWithValue(db),
      accountsProvider.overrideWith((ref) => _Accounts(db, [work, yandex, gmail, icloud, archive])),
    ]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    c.read(accountsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    (c.read(accountsProvider.notifier) as _Accounts).put();
    return (c, c.read(phoneMirrorProvider));
  }

  test('кому по умолчанию: не Google, не iCloud на iPhone, не онлайн-архив', () {
    expect(PhoneMirrorService.eligible(work, ios: false), isTrue);
    expect(PhoneMirrorService.eligible(yandex, ios: false), isTrue);
    expect(PhoneMirrorService.eligible(gmail, ios: false), isFalse);
    expect(PhoneMirrorService.eligible(gmail, ios: true), isFalse);
    expect(PhoneMirrorService.eligible(icloud, ios: false), isTrue, reason: 'Android iCloud сам не знает');
    expect(PhoneMirrorService.eligible(icloud, ios: true), isFalse);
    expect(PhoneMirrorService.eligible(archive, ios: false), isFalse);
  });

  test('по умолчанию включено для подходящих ящиков', () async {
    final (_, m) = await make();
    expect(m.contactsEnabled, isTrue);
    expect(m.calendarEnabled, isTrue);
    expect(m.contactsOn('work'), isTrue);
    expect(m.calendarOn('ya'), isTrue);
    expect(m.contactsOn('gm'), isFalse);
    expect(m.calendarOn('archive_work'), isFalse);
    expect(m.contactsOn('unknown'), isFalse);
  });

  test('включённый раньше вручную ящик Google остаётся; общий выключатель выключает всё', () async {
    final (_, m) = await make({'mirror_calendar_gm': true});
    expect(m.calendarOn('gm'), isTrue);
    expect(m.contactsOn('gm'), isFalse);
    await m.setCalendarEnabled(false);
    expect(m.calendarEnabled, isFalse);
    expect(m.calendarOn('gm'), isFalse);
    expect(m.calendarOn('work'), isFalse);
    expect(m.contactsOn('work'), isTrue, reason: 'контакты — свой выключатель');
  });
}

// Звонок и SMS контактам с полным номером (2.7.5, просьба владельца
// 28.11.2026): SMS — только на полный номер (с кодом страны или города),
// звонок — на полный, если он есть; короткий внутренний — не для SMS.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/features/contacts/phone_actions.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('полный номер и короткий внутренний', () {
    expect(PhoneActions.isFull('+7 910 521-40-92'), isTrue);
    expect(PhoneActions.isFull('8 (3496) 39-397'), isTrue);
    expect(PhoneActions.isFull('+44 20 7946 0958'), isTrue);
    expect(PhoneActions.isFull('39-397'), isFalse);
    expect(PhoneActions.isFull('521-40-92'), isFalse);
    expect(PhoneActions.isFull(null), isFalse);
    expect(PhoneActions.isFull('39-397 доб. 1234567890'), isFalse, reason: 'добавочный — не часть номера');
  });

  test('добавочный в записи номера — после паузы, не слитно', () {
    expect(PhoneActions.clean('+7 (3496) 39-397 доб. 123'), '+7349639397');
    expect(PhoneActions.dialString('+7 (3496) 39-397 доб. 123'), '+7349639397,123');
    expect(PhoneActions.dialString('+1 212 555 0100 ext. 12'), '+12125550100,12');
    expect(PhoneActions.dialString('+7 910 521-40-92'), '+79105214092');
    expect(PhoneActions.canSms('+7 (3496) 39-397 доб. 123'), isFalse, reason: 'это коммутатор');
  });

  test('добавочный без основного номера — через основной номер организации', () {
    expect(PhoneActions.isExtension('39-397'), isTrue);
    expect(PhoneActions.isExtension('1234'), isTrue);
    expect(PhoneActions.isExtension('521-40-92'), isFalse, reason: 'городской, 7 цифр');
    expect(PhoneActions.isExtension('+7 910 521-40-92'), isFalse);
    expect(PhoneActions.viaMain('+7 (3496) 12-34-56', '39-397'), '+73496123456,39397');
  });

  test('основной номер — только для своей организации (рабочий ящик, свой домен)', () {
    AccountModel acc(String email, AccountType type, {String? kind}) =>
        AccountModel(id: email, type: type, email: email, displayName: '', username: email,
            accountKind: kind, createdAt: DateTime(2026));
    final exchange = acc('me@yamal.example', AccountType.activesync);
    final gmail = acc('me@gmail.com', AccountType.imap);
    final workImap = acc('me@factory.example', AccountType.imap, kind: 'work');
    final all = [exchange, gmail, workImap];
    expect(PhoneActions.orgDomainFor('ivan@yamal.example', all), 'yamal.example');
    expect(PhoneActions.orgDomainFor('ivan@factory.example', all), 'factory.example', reason: 'отмечен «рабочим»');
    expect(PhoneActions.orgDomainFor('friend@gmail.com', all), isNull, reason: 'общедоступная почта');
    expect(PhoneActions.orgDomainFor('ivan@partner.example', all), isNull, reason: 'чужая организация');
    expect(PhoneActions.orgDomainFor(null, all), isNull, reason: 'без адреса — как есть');
    expect(PhoneActions.orgDomainFor('ivan@yamal.example', [gmail]), isNull);
  });

  test('основной номер запоминается по домену организации', () async {
    SharedPreferences.setMockInitialValues({});
    await PhoneActions.setMainNumber('andrey@yamal.example', '+7 3496 12-34-56');
    expect(await PhoneActions.mainNumberFor('Ivan@Yamal.Example'), '+7 3496 12-34-56');
    expect(await PhoneActions.mainNumberFor('x@other.example'), isNull);
    await PhoneActions.setMainNumber('andrey@yamal.example', '');
    expect(await PhoneActions.mainNumberFor('ivan@yamal.example'), isNull);
    // Без адреса — общего номера нет.
    await PhoneActions.setMainNumber(null, '+7 3496 00-00-00');
    expect(await PhoneActions.mainNumberFor(null), isNull);
  });

  testWidgets('окно «Добавочный номер»: ввели основной — запомнили', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await PhoneActions.askMainNumber(context, '39-397', 'a@yamal.example'),
              child: const Text('открыть'),
            ),
          )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.textContaining('39-397'), findsOneWidget);
    expect(find.textContaining('yamal.example'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('phone_ext_main')), '+7 3496 12-34-56');
    await tester.tap(find.byKey(const ValueKey('phone_ext_call')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(result, '+7 3496 12-34-56');
    expect(await tester.runAsync(() => PhoneActions.mainNumberFor('b@yamal.example')), '+7 3496 12-34-56');

    // «Набрать как есть» — пустая строка, номер не меняется.
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phone_ext_as_is')));
    await tester.pumpAndSettle();
    expect(result, '');
  });

  test('номер для звонка и SMS', () {
    expect(PhoneActions.callNumber(['39-397', '+7 967 666-05-12']), '+7 967 666-05-12');
    expect(PhoneActions.callNumber(['39-397', null]), '39-397', reason: 'полного нет — какой есть');
    expect(PhoneActions.callNumber([null, '']), isNull);
    expect(PhoneActions.smsNumber(mobile: '+7 967 666-05-12', work: '+7 910 521-40-92'), '+7 967 666-05-12');
    expect(PhoneActions.smsNumber(mobile: null, work: '+7 910 521-40-92'), '+7 910 521-40-92');
    expect(PhoneActions.smsNumber(mobile: '', work: '39-397'), isNull);
  });
}

// Название ящика (2.6.1, просьба владельца 16.11.2026): не длиннее 24
// знаков, вместо логина в уведомлениях и под заголовком почты; после
// добавления ящика предлагается задать его.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/features/settings/widgets/account_label_dialog.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/accounts/account_labels.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _acc = AccountModel(
    id: 'a1', type: AccountType.yandex, email: 'o.ermishin@yandex.ru', displayName: 'Олег',
    username: 'o.ermishin', colorValue: 0xFF1D4F91, createdAt: DateTime(2026));

void main() {
  test('название: пробелы, управляющие знаки и длина', () {
    expect(AccountLabels.clean('  Работа  '), 'Работа');
    expect(AccountLabels.clean('Ра\nбо\tта'), 'Ра бо та');
    expect(AccountLabels.clean('   '), isNull);
    expect(AccountLabels.clean(null), isNull);
    expect(AccountLabels.clean('Почта\u202eанк'), 'Почта анк', reason: 'знак смены направления текста');
    final long = AccountLabels.clean('Очень длинное название рабочего ящика');
    expect(long!.length, lessThanOrEqualTo(AccountLabels.maxLength));
    expect(AccountLabels.clean('👨‍👩‍👧 Семья'), '👨‍👩‍👧 Семья', reason: 'эмодзи-семья — один знак');
  });

  test('сохранение по ящику и метка в «Вся почта» вместо логина', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await AccountLabels.write(prefs, 'a1', ' Дом ');
    expect(AccountLabels.of(prefs, 'a1'), 'Дом');
    expect(AccountLabels.read(prefs), {'a1': 'Дом'});
    expect(EmailListTile.accountMarkOf([_acc], 'a1', labels: AccountLabels.read(prefs))?.label, 'Дом');
    expect(EmailListTile.accountMarkOf([_acc], 'a1')?.label, 'yandex');
    await AccountLabels.write(prefs, 'a1', '');
    expect(AccountLabels.of(prefs, 'a1'), isNull);
  });

  Future<ProviderContainer> open(WidgetTester t, {required bool ask}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => showAccountLabelDialog(context, ref, _acc, ask: ask),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('после добавления ящика: вопрос, ввод не длиннее 24 знаков, сохранение', (t) async {
    final c = await open(t, ask: true);
    expect(find.text('Как назвать ящик?'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
    await t.enterText(find.byKey(const Key('account_label_field')), 'Рабочий ящик отдела закупок');
    await t.tap(find.byKey(const Key('account_label_save')));
    await t.pumpAndSettle();
    final saved = c.read(accountLabelsProvider)['a1'];
    expect(saved, isNotNull);
    expect(saved!.length, lessThanOrEqualTo(24));
    expect(saved, startsWith('Рабочий ящик'));
  });

  testWidgets('«Пропустить» — названия нет', (t) async {
    final c = await open(t, ask: true);
    await t.tap(find.text('Пропустить'));
    await t.pumpAndSettle();
    expect(c.read(accountLabelsProvider), isEmpty);
  });
}

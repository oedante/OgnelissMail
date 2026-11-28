// «Категории» (2.7.5): одно окно вместо тегов и категорий Outlook, у каждой
// категории — цвет. У ящика без серверных категорий (IMAP) — на телефоне.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show accountsProvider;
import 'package:ogneliss/features/mail/widgets/categories_sheet.dart';
import 'package:ogneliss/features/settings/providers/categories_provider.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('цвет категории: стандартная Outlook — своим, выбранный — выбранным', () {
    expect(categoryColor('Красная категория', const {}), categoryPalette[0]);
    expect(categoryColor('Blue category', const {}), categoryPalette[4]);
    expect(categoryColor('Проекты', const {}), categoryColor('Проекты', const {}), reason: 'постоянный');
    expect(categoryColor('Проекты', {'Проекты': 0xFF123456}), const Color(0xFF123456));
  });

  testWidgets('IMAP: отметить категорию — тег письма на телефоне', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Я',
          username: 'me', createdAt: DateTime(2026)));
      await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'm1', accountId: 'a1', folderId: 'inbox', fromEmail: 'x@example.com',
          toRecipients: '[]', subject: 'Смета', receivedAt: DateTime(2026, 11, 27)));
    });
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    final email = EmailModel(
      id: 'm1', accountId: 'a1', folderId: 'inbox',
      from: const EmailAddress(email: 'x@example.com'), to: const [], subject: 'Смета',
      receivedAt: DateTime(2026, 11, 27),
    );
    List<String>? result;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Consumer(builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async => result = await showCategoriesSheet(context, ref, email),
                child: const Text('открыть'),
              ),
            )),
      ),
    ));
    for (var i = 0; i < 20 && container.read(accountsProvider).isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    expect(find.text('Категории'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category_Проекты')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('categories_done')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    expect(result, ['Проекты']);
    final row = await tester.runAsync(() => (db.select(db.emails)..where((e) => e.id.equals('m1'))).getSingle());
    expect(row!.tagsStr, 'Проекты');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

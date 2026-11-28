// Выбор адресатов (4PDA, 28.11.2026: «нажимаю на значок человека — выбора
// контактов нет»): список контактов — сразу, без ввода; избранные и частые
// — первыми; уже выбранные в строке — не дублируются.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/compose/widgets/people_picker_sheet.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('контакты — сразу, избранные первыми', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.runAsync(() async {
      Future<void> c(String id, String email, String name, {bool fav = false, int n = 0}) =>
          db.into(db.contacts).insert(ContactsCompanion.insert(
                id: id, email: email, displayName: name,
                isFavorite: Value(fav), interactionCount: Value(n)));
      await c('c1', 'anna@partner.example', 'Анна Петрова', n: 3);
      await c('c2', 'boss@corp.example', 'Начальник Иван', fav: true);
      await c('c3', 'yuri@home.example', 'Юрий', n: 10);
    });
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => editRecipientsSheet(context, account: null, title: 'Кому', current: const []),
                child: const Text('открыть'),
              ),
            )),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('открыть'));
    for (var i = 0; i < 30 && find.text('Юрий').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    final boss = tester.getTopLeft(find.text('Начальник Иван')).dy;
    final yuri = tester.getTopLeft(find.text('Юрий')).dy;
    final anna = tester.getTopLeft(find.text('Анна Петрова')).dy;
    expect(boss < yuri && yuri < anna, isTrue, reason: 'избранный, затем по переписке');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}

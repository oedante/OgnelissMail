// Присланная группа контактов (21.11.2026): «Сохранить группу» кладёт её в
// «Группы рассылки», длинный список участников сворачивается.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/compose/providers/distribution_groups_provider.dart';
import 'package:ogneliss/features/mail/widgets/forwarded_contacts_card.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/dav/vcard_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('группа сохраняется в «Группы рассылки»', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);
    final group = DistributionGroup(name: 'Каталогеры', members: [
      for (var i = 0; i < 12; i++) GroupMember(email: 'u$i@example.com', name: 'Участник $i'),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.lightTheme(1.0),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ForwardedContactsCard(
              groups: [group],
              contacts: const [VCardData(fn: 'Анна Сидорова', email: 'a@example.com', org: 'Пример')],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Каталогеры'), findsOneWidget);
    expect(find.text('Участник 0'), findsOneWidget);
    expect(find.text('Участник 11'), findsNothing, reason: 'длинный список свёрнут');
    expect(find.text('Анна Сидорова'), findsOneWidget);

    await tester.ensureVisible(find.text('Показать все (12)'));
    await tester.tap(find.text('Показать все (12)'));
    await tester.pumpAndSettle();
    expect(find.text('Участник 11'), findsOneWidget);

    await tester.ensureVisible(find.text('Сохранить группу'));
    await tester.tap(find.text('Сохранить группу'));
    await tester.pumpAndSettle();
    final saved = container.read(distributionGroupsProvider);
    expect(saved.single.name, 'Каталогеры');
    expect(saved.single.members, hasLength(12));
    expect(find.text('Сохранить группу'), findsNothing);
    expect(find.textContaining('сохранена'), findsOneWidget);
  });
}

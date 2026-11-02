// Выбор ящика с портретами (1.10.3, замечание владельца 02.11.2026: «не
// только цвета, но и аватары»): в поле — портрет выбранного ящика, в меню —
// портрет, имя и адрес у каждого ящика.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/account_avatar.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';
import 'package:ogneliss/widgets/ui/app_menu_button.dart';

final _work = AccountModel(
    id: 'w', type: AccountType.exchange, email: 'o.ermishin@yamalspg.ru', displayName: 'Ермишин Олег Андреевич',
    username: 'o.ermishin', colorValue: 0xFF1D4F91, createdAt: DateTime(2026));
final _home = AccountModel(
    id: 'h', type: AccountType.google, email: 'oedante@gmail.com', displayName: 'oedante',
    username: 'oedante', colorValue: 0xFFE07B39, createdAt: DateTime(2026));

void main() {
  testWidgets('поле и меню выбора ящика — с портретами', (tester) async {
    String value = 'w';
    await tester.pumpWidget(ProviderScope(
      overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppSelectField<String>(
              value: value,
              entries: [accountMenuEntry(_work), accountMenuEntry(_home)],
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    // В поле — портрет выбранного ящика и его имя.
    expect(find.byType(AccountAvatar), findsOneWidget);
    expect(find.text('Ермишин Олег Андреевич'), findsOneWidget);

    await tester.tap(find.byType(AppSelectField<String>));
    await tester.pumpAndSettle();
    // В меню — у каждого ящика портрет; имя совпадает с логином — только адрес.
    expect(find.byType(AccountAvatar), findsNWidgets(3));
    expect(find.text('o.ermishin@yamalspg.ru'), findsOneWidget);
    expect(find.text('oedante@gmail.com'), findsOneWidget);
    expect(find.text('oedante'), findsNothing);

    await tester.tap(find.text('oedante@gmail.com'));
    await tester.pumpAndSettle();
    expect(value, 'h');
  });
}

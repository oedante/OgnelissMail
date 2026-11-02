// Плитки «Избранного» (1.10.3, просьба владельца 02.11.2026: «панелями в
// стиле пуска Windows 10», у каждого пункта — значок с подписью или только
// значок): ширина плитки, подпись, подсказка, число и нажатие.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/drawer_prefs.dart';
import 'package:ogneliss/widgets/common/tile_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('широкая — две клетки с подписью, маленькая — одна, без подписи', (tester) async {
    var tapped = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 304,
          child: TileGrid(items: [
            TileItem(id: 'allMail', icon: Icons.inbox, label: 'Вся почта', count: 12, onTap: () => tapped = 'allMail'),
            TileItem(id: 'flagged', icon: Icons.flag, label: 'С флажком', iconOnly: true, onTap: () => tapped = 'flagged'),
            const TileItem(id: 'vip', icon: Icons.star, label: 'VIP', iconOnly: true, selected: true),
          ]),
        ),
      ),
    ));
    final wide = tester.getSize(find.byKey(const ValueKey('tile_allMail')));
    final small = tester.getSize(find.byKey(const ValueKey('tile_flagged')));
    expect(wide.width, greaterThan(small.width * 2));
    expect(wide.height, small.height);
    // Широкая и обе маленькие — в одном ряду (4 клетки).
    expect(tester.getTopLeft(find.byKey(const ValueKey('tile_vip'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('tile_allMail'))).dy);
    expect(find.text('Вся почта'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('С флажком'), findsNothing);
    expect(find.byTooltip('С флажком'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tile_flagged')));
    expect(tapped, 'flagged');
    await tester.tap(find.byKey(const ValueKey('tile_allMail')));
    expect(tapped, 'allMail');
  });

  test('выбор «только значок» сохраняется', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final key = FavoriteIconOnlyNotifier.folderKey('a1', 'INBOX/Проекты');
    await c.read(favoriteIconOnlyProvider.notifier).set(key, true);
    await c.read(favoriteIconOnlyProvider.notifier).set('flagged', true);
    await c.read(favoriteIconOnlyProvider.notifier).set('flagged', false);
    expect(c.read(favoriteIconOnlyProvider), {key});
    final again = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(again.dispose);
    expect(again.read(favoriteIconOnlyProvider), {key});
  });
}

// Настройки на компьютере (2.6.4, проход по интерфейсу компьютера): пункты
// только для телефона скрыты, вместо жестов — сочетания клавиш.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/screens/accessibility_screen.dart';
import 'package:ogneliss/features/settings/screens/advanced_settings_screen.dart';
import 'package:ogneliss/features/settings/screens/mail_settings_screen.dart';
import 'package:ogneliss/features/settings/screens/notifications_settings_screen.dart';
import 'package:ogneliss/features/settings/screens/sync_settings_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/keyboard_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, Widget home, {Size size = const Size(1280, 3000)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({'s_locale': 'ru'});
  final sp = await SharedPreferences.getInstance();
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(sp)],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  final ru = AppLocalizations(const Locale('ru'));

  for (final (platform, desktop) in const [(TargetPlatform.windows, true), (TargetPlatform.android, false)]) {
    testWidgets('${platform.name}: вибрация, листание свайпом, жесты или клавиши', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(t, const NotificationsSettingsScreen());
        expect(find.text(ru.tr('vibration')), desktop ? findsNothing : findsOneWidget);

        await _pump(t, const MailSettingsScreen());
        expect(find.text(ru.tr('mailSwipePager')), desktop ? findsNothing : findsOneWidget);

        await _pump(t, const AccessibilityScreen());
        expect(find.text(ru.tr('kbdShortcuts')), desktop ? findsOneWidget : findsNothing);
        expect(find.text(ru.tr('gestureNav')), desktop ? findsNothing : findsOneWidget);
        if (desktop) {
          await t.tap(find.text(ru.tr('kbdShortcuts')));
          await t.pumpAndSettle();
          expect(find.textContaining('Ctrl+N — ${ru.compose}'), findsOneWidget);
          expect(find.textContaining('F4 — ${ru.tr('findInMail')}'), findsOneWidget);
        }
        await t.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('клавиши на Mac — значками, без Insert', () {
    final mac = desktopKeyList(ru, mac: true);
    expect(mac.map((k) => k.$1), containsAll(['⌘N', '⌘K', '⌫']));
    expect(mac.any((k) => k.$1 == 'Insert'), isFalse);
    final win = desktopKeyList(ru, mac: false);
    expect(win.map((k) => k.$1), containsAll(['Ctrl+N', 'Ctrl+K', 'Insert']));
  });

  // Замечание владельца 18.11.2026: «что в настройках лежит не там».
  testWidgets('«Лента и письма»: картинки из интернета, иконки организаций, область чтения (компьютер)', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pump(t, const MailSettingsScreen());
      expect(find.text(ru.tr('mailImagesSection')), findsOneWidget);
      expect(find.text(ru.tr('loadRemoteImages')), findsOneWidget);
      expect(find.text(ru.tr('orgIcons')), findsOneWidget);
      expect(find.text(ru.tr('readingPane')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('телефон: области чтения в «Ленте и письмах» нет', (t) async {
    // Высокое окно — вся страница построена (иначе «нет» могло бы значить
    // «ниже экрана»).
    await _pump(t, const MailSettingsScreen(), size: const Size(400, 12000));
    expect(find.text(ru.tr('loadRemoteImages')), findsOneWidget);
    expect(find.text(ru.tr('readingPane')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  // Конфликты синхронизации решаются сами — выбор в «Расширенных
  // настройках» (2.7.2, «пользователь добавил аккаунт — от него не должно
  // что-то ещё требоваться»).
  testWidgets('«Синхронизация» — отдельный экран: все ящики и расписание', (t) async {
    await _pump(t, const SyncSettingsScreen());
    expect(find.text(ru.tr('autoSyncAll')), findsOneWidget);
    expect(find.text(ru.tr('scheduleTitle')), findsOneWidget);
    expect(find.text(ru.tr('syncConflicts')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  // Перегруппировка 2.7.2 (замечание владельца 23.11.2026: «антифишинг и
  // блокировку можно объединить, размер фото — в "Загрузке и вложениях"»).
  testWidgets('«Защита писем»: антифишинг и блокировка трекеров одним экраном', (t) async {
    await _pump(t, const MailSettingsScreen(part: MailSettingsPart.safety));
    expect(find.text(ru.tr('mailProtection')), findsOneWidget);
    expect(find.text(ru.tr('dangerOnly')), findsOneWidget);
    expect(find.byKey(const ValueKey('safety_trackers')), findsOneWidget);
    expect(find.byKey(const ValueKey('safety_trackers_log')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('размер фото при отправке — в «Загрузке и вложениях», не в «Написании»', (t) async {
    await _pump(t, const MailSettingsScreen(part: MailSettingsPart.files));
    expect(find.text(ru.tr('photoSendSize')), findsOneWidget);
    await _pump(t, const MailSettingsScreen(part: MailSettingsPart.compose));
    expect(find.text(ru.tr('photoSendSize')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('«Расширенные»: конфликты, сертификаты и защита данных', (t) async {
    await _pump(t, const AdvancedSettingsScreen());
    expect(find.byKey(const ValueKey('adv_conflicts')), findsOneWidget);
    expect(find.byKey(const ValueKey('adv_conn_security')), findsOneWidget);
    expect(find.byKey(const ValueKey('adv_dlp')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

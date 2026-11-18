// Справка по пункту настроек (просьба владельца 18.11.2026): долгое нажатие
// (на компьютере — правая кнопка) открывает пояснение пункта и ответы из
// «Вопросов и ответов» про него; без текстов — ничего не открывается.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ogneliss/features/help/faq_content.dart';
import 'package:ogneliss/features/help/settings_help.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/ui/settings_group.dart';

Future<void> _pump(WidgetTester t, List<Widget> rows, {List<String>? opened}) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => Scaffold(body: ListView(children: rows))),
    GoRoute(
      path: '/settings/faq',
      builder: (_, s) {
        opened?.add(s.uri.toString());
        return const Scaffold(body: Text('FAQ'));
      },
    ),
  ]);
  addTearDown(router.dispose);
  await t.pumpWidget(MaterialApp.router(
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: router,
  ));
  await t.pumpAndSettle();
}

void main() {
  final ru = AppLocalizations(const Locale('ru'));
  String faq(String key, String part) => ru.tr('faq_${key}_$part');

  setUp(SettingsHelp.debugReset);

  testWidgets('долгое нажатие на переключатель — ответ из FAQ, переключатель не меняется', (t) async {
    var value = true;
    await _pump(t, [
      StatefulBuilder(
        builder: (_, set) => SettingsSwitchItem(
          title: ru.tr('mailSwipePager'),
          value: value,
          onChanged: (v) => set(() => value = v),
        ),
      ),
    ]);
    await t.longPress(find.text(ru.tr('mailSwipePager')));
    await t.pumpAndSettle();
    expect(find.text(faq('mail_7', 'q')), findsOneWidget);
    expect(find.text(faq('mail_7', 'a')), findsOneWidget);
    expect(value, isTrue);
  });

  testWidgets('пояснение «?» и вопросы — в одной шторке; кнопка ведёт в раздел FAQ', (t) async {
    final opened = <String>[];
    await _pump(t, [
      SettingsItem(title: ru.tr('undoSendWindow'), hint: 'Пояснение пункта', onTap: () {}),
    ], opened: opened);
    await t.longPress(find.text(ru.tr('undoSendWindow')));
    await t.pumpAndSettle();
    expect(find.text('Пояснение пункта'), findsOneWidget);
    expect(find.text(faq('drafts_5', 'q')), findsOneWidget);
    await t.tap(find.text(ru.tr('faqTitle')));
    await t.pumpAndSettle();
    expect(opened, ['/settings/faq?section=drafts']);
  });

  testWidgets('нет ни пояснения, ни вопросов — долгое нажатие ничего не открывает', (t) async {
    await _pump(t, [SettingsItem(title: 'Без справки', onTap: () {})]);
    await t.longPress(find.text('Без справки'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('компьютер: правая кнопка мыши открывает справку', (t) async {
    await _pump(t, [SettingsItem(title: ru.tr('logsTitle'), onTap: () {})]);
    await t.tap(find.text(ru.tr('logsTitle')), buttons: kSecondaryMouseButton);
    await t.pumpAndSettle();
    expect(find.text(faq('settings_2', 'q')), findsOneWidget);
  });

  testWidgets('подпись раздела без «?»: справка — долгим нажатием', (t) async {
    await _pump(t, [SettingsSectionTitle(ru.tr('readingPane'))]);
    expect(find.byType(HelpButton), findsNothing);
    await t.longPress(find.text(ru.tr('readingPane')));
    await t.pumpAndSettle();
    expect(find.text(faq('mail_14', 'q')), findsOneWidget);
  });

  for (final (platform, shown, hidden) in const [
    (TargetPlatform.android, 'notify_3', 'notify_1'),
    (TargetPlatform.iOS, 'notify_1', 'notify_3'),
  ]) {
    testWidgets('${platform.name}: ответы только про свою систему', (t) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(t, [SettingsItem(title: ru.tr('notifications'), onTap: () {})]);
        await t.longPress(find.text(ru.tr('notifications')));
        await t.pumpAndSettle();
        expect(find.text(faq(shown, 'q')), findsOneWidget);
        expect(find.text(faq(hidden, 'q')), findsNothing);
        expect(find.text(faq('notify_4', 'q')), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('таблица: названия и вопросы существуют', () {
    final en = File('assets/l10n/en.xml').readAsStringSync();
    final faqKeys = {for (final s in faqSections) ...s.items.map((i) => i.key)};
    for (final MapEntry(:key, :value) in settingsFaq.entries) {
      expect(en.contains('name="$key"'), isTrue, reason: 'нет строки $key');
      for (final k in value) {
        expect(faqKeys, contains(k), reason: '$key → $k: нет вопроса');
      }
    }
    expect(faqKeys, contains('settings_4'));
  });
}

// «Настройки → Перевод» (1.12.x, просьба владельца 04.11.2026): «Языки
// телефона — не предлагать перевод» (по умолчанию включено) и «Всегда
// переводить с языков»; движка нет — только пояснение. Движок — подделка.
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/features/settings/widgets/translation_settings_section.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/translation/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fake implements Translator {
  _Fake({this.available = true});
  final bool available;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> detectLanguage(String text) async => null;
  @override
  Future<LangDetection?> identifyLanguage(String text) async => null;
  @override
  Future<List<String>> supportedLanguages() async => const ['en', 'ru', 'de'];
  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async => {
    for (final c in codes) c: const {'en': 'английский', 'ru': 'русский', 'de': 'немецкий'}[c] ?? c,
  };
  @override
  Future<Set<String>?> downloadedModels() async => null;
  @override
  Future<List<String>> missingModels(String from, String to) async => const [];
  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) async {}
  @override
  Future<void> deleteModel(String lang) async {}
  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async => texts;
  @override
  bool get googleAttribution => false;
  @override
  int? get modelSizeMb => null;
  @override
  bool get canManageModels => false;
}

Future<ProviderContainer> _pump(WidgetTester t, {bool available = true, Map<String, Object> prefs = const {}}) async {
  debugTranslationPlatformOverride = true;
  addTearDown(() => debugTranslationPlatformOverride = null);
  t.platformDispatcher.localesTestValue = const [Locale('ru'), Locale('en', 'US')];
  addTearDown(t.platformDispatcher.clearLocalesTestValue);
  SharedPreferences.setMockInitialValues({'s_locale': 'ru', ...prefs});
  final sp = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      translatorProvider.overrideWithValue(_Fake(available: available)),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SingleChildScrollView(child: TranslationSettingsSection())),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

/// Подпись — по платформе, как в самой настройке (на Windows и Mac — свои;
/// тест проходил на GitHub (Linux) и падал у владельца на Windows, 10.11.2026).
final _phoneLangsTitle = AppLocalizations(const Locale('ru')).tr(Platform.isMacOS
    ? 'translatePhoneLangsMac'
    : Platform.isWindows
        ? 'translatePhoneLangsWindows'
        : 'translatePhoneLangs');

void main() {
  testWidgets('«Языки телефона» — включено по умолчанию, языки в подписи, переключается', (t) async {
    final c = await _pump(t);
    expect(find.text(_phoneLangsTitle), findsOneWidget);
    // Язык приложения (русский) в подписи не повторяется.
    expect(find.text('Английский'), findsOneWidget);
    final sw = find.descendant(of: find.byKey(const ValueKey('translate_phone_langs')), matching: find.byType(Switch));
    expect(t.widget<Switch>(sw).value, isTrue);
    await t.tap(find.byKey(const ValueKey('translate_phone_langs')));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider).translatePhoneLangs, isFalse);
    expect(t.widget<Switch>(sw).value, isFalse);
  });

  testWidgets('«Языки телефона» недоступно, когда перевод не предлагается', (t) async {
    await _pump(t, prefs: const {'s_translate_offer': false});
    final sw = find.descendant(of: find.byKey(const ValueKey('translate_phone_langs')), matching: find.byType(Switch));
    expect(t.widget<Switch>(sw).onChanged, isNull);
  });

  testWidgets('«Всегда переводить с языков»: выбор списком, язык уходит из «Не переводить»', (t) async {
    final c = await _pump(
      t,
      prefs: const {
        's_translate_never': ['de'],
      },
    );
    expect(find.text('Всегда переводить с языков'), findsOneWidget);
    expect(find.text('Письма на этих языках сразу открываются в переводе'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('translate_always')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(CheckboxListTile, 'Немецкий'));
    await t.pumpAndSettle();
    final s = c.read(settingsProvider);
    expect(s.translateAlways, ['de']);
    expect(s.translateNever, isEmpty);
    // Лист закрыт — подпись строки: выбранный язык.
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const ValueKey('translate_always')), matching: find.text('Немецкий')),
      findsOneWidget,
    );
  });

  testWidgets('движка нет — раздел только с пояснением, без переключателей', (t) async {
    await _pump(t, available: false);
    expect(find.text('Перевод'), findsOneWidget);
    expect(find.byKey(const ValueKey('translate_phone_langs')), findsNothing);
    expect(find.byKey(const ValueKey('translate_always')), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('крупный шрифт и узкий телефон — без переполнения', (t) async {
    t.view.physicalSize = const Size(320, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(t);
    expect(t.takeException(), isNull);
    expect(find.text(_phoneLangsTitle), findsOneWidget);
  });
}

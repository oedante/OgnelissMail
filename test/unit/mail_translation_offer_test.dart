// Предложение перевода входящего письма (1.12.x, просьба владельца
// 04.11.2026: плашка «сбоит и предлагает другие языки»): только при
// уверенном языке, языки телефона — знакомые, «Всегда переводить с …» —
// перевод сразу. Движок — подделка (заглавные буквы), определитель —
// заданный тестом ответ.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/widgets/mail_translation.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/translation/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Подделка движка: язык текста — [detection], перевод — заглавными.
class _Fake implements Translator {
  _Fake(this.detection, {this.missing = const [], this.available = true});

  LangDetection? detection;
  final List<String> missing;
  final bool available;
  int translateCalls = 0;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<String?> detectLanguage(String text) async => detection?.lang;
  @override
  Future<LangDetection?> identifyLanguage(String text) async => detection;
  @override
  Future<List<String>> supportedLanguages() async => const ['en', 'ru', 'de', 'uk'];
  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async => const {};
  @override
  Future<Set<String>?> downloadedModels() async => null;
  @override
  Future<List<String>> missingModels(String from, String to) async => missing;
  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) async {}
  @override
  Future<void> deleteModel(String lang) async {}
  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) async {
    translateCalls++;
    return [for (final t in texts) t.toUpperCase()];
  }

  @override
  bool get googleAttribution => false;
  @override
  int? get modelSizeMb => null;
  @override
  bool get canManageModels => false;
}

EmailModel _mail(String id, String html) => EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'INBOX',
      from: const EmailAddress(email: 'sender@example.org'),
      to: const [EmailAddress(email: 'me@example.org')],
      subject: 'Quarterly report',
      receivedAt: DateTime(2026, 11, 4, 10),
      bodyHtml: html,
    );

final _en = _mail('en1', '<p>Please find attached the quarterly report and let me know what you think about it.</p>');
final _de = _mail('de1', '<p>Anbei finden Sie den Quartalsbericht, bitte teilen Sie mir Ihre Meinung dazu mit.</p>');

typedef _Ctx = ({MailTranslationController c, BuildContext ctx, ProviderContainer container});

Future<_Ctx> _pump(WidgetTester t, Translator fake,
    {String app = 'ru', List<Locale> phone = const [Locale('ru')], Map<String, Object> prefs = const {}}) async {
  debugTranslationPlatformOverride = true;
  addTearDown(() => debugTranslationPlatformOverride = null);
  t.platformDispatcher.localesTestValue = phone;
  addTearDown(t.platformDispatcher.clearLocalesTestValue);
  SharedPreferences.setMockInitialValues({'s_locale': app, ...prefs});
  final sp = await SharedPreferences.getInstance();
  late MailTranslationController c;
  late BuildContext ctx;
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(sp),
    translatorProvider.overrideWithValue(fake),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: Locale(app),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          c = MailTranslationController(ref);
          ctx = context;
          return const SizedBox();
        }),
      ),
    ),
  ));
  await t.pumpAndSettle();
  addTearDown(c.dispose);
  return (c: c, ctx: ctx, container: container);
}

/// Определить язык письма и дождаться решения (работа — после вызова).
Future<void> _detect(WidgetTester t, MailTranslationController c, EmailModel e) async {
  await t.runAsync(() async {
    c.detect(e);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await t.pump();
}

void main() {
  testWidgets('уверенный язык — плашка «Перевести»', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: true)));
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.offer);
    expect(s.c.from, 'en');
    expect(s.c.unknownLang, isFalse);
    expect(s.c.engineAvailable, isTrue);
  });

  testWidgets('догадка — без плашки, «Перевести» из меню всё равно переводит с неё', (t) async {
    // Приложение по-английски, письмо по-немецки (тот же алфавит):
    // определитель не уверен — предложения нет.
    final fake = _Fake((lang: 'de', confident: false));
    final s = await _pump(t, fake, app: 'en', phone: const [Locale('en')]);
    await _detect(t, s.c, _de);
    expect(s.c.phase, MailTranslationPhase.none);
    expect(s.c.from, isNull, reason: 'по догадке язык письма не называем');
    await t.runAsync(() => s.c.translate(s.ctx, _de));
    expect(s.c.phase, MailTranslationPhase.translated);
    expect(s.c.from, 'de');
    expect(s.c.apply(_de).bodyHtml, contains('ANBEI FINDEN SIE'));
  });

  testWidgets('догадка, письмо другим алфавитом — «Письмо на другом языке»', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: false)));
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.offer);
    expect(s.c.unknownLang, isTrue);
  });

  testWidgets('языки телефона: не предлагать (по умолчанию), выключено — предлагать', (t) async {
    final on = await _pump(t, _Fake((lang: 'en', confident: true)), phone: const [Locale('ru'), Locale('en', 'US')]);
    await _detect(t, on.c, _en);
    expect(on.c.phase, MailTranslationPhase.none);
    // Язык известен — «Перевести» из меню переводит без вопроса.
    expect(on.c.from, 'en');
  });

  testWidgets('языки телефона: переключатель выключен — предлагать', (t) async {
    final off = await _pump(t, _Fake((lang: 'en', confident: true)),
        phone: const [Locale('ru'), Locale('en', 'US')], prefs: const {'s_translate_phone_langs': false});
    await _detect(t, off.c, _en);
    expect(off.c.phase, MailTranslationPhase.offer);
  });

  testWidgets('«Не переводить с …» — без плашки', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: true)), prefs: const {
      's_translate_never': ['en'],
    });
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.none);
  });

  testWidgets('«Всегда переводить с …» — перевод сразу, без предложения; «Оригинал» есть', (t) async {
    final fake = _Fake((lang: 'en', confident: true));
    final s = await _pump(t, fake, prefs: const {
      's_translate_always': ['en'],
    });
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.translated);
    expect(s.c.showing, isTrue);
    expect(s.c.autoTranslated, isTrue);
    expect(s.c.apply(_en).bodyHtml, contains('PLEASE FIND ATTACHED'));
    expect(s.c.subjectFor(_en).main, 'QUARTERLY REPORT');
    s.c.showOriginal();
    expect(s.c.apply(_en).bodyHtml, _en.bodyHtml);
    expect(s.c.phase, MailTranslationPhase.translated, reason: 'на плашке — «Показать перевод»');
  });

  testWidgets('«Всегда переводить» по догадке не переводит сам', (t) async {
    final fake = _Fake((lang: 'de', confident: false));
    final s = await _pump(t, fake, app: 'en', phone: const [Locale('en')], prefs: const {
      's_translate_always': ['de'],
    });
    await _detect(t, s.c, _de);
    expect(s.c.phase, MailTranslationPhase.none);
    expect(fake.translateCalls, 0);
  });

  testWidgets('«Всегда переводить», языков на устройстве нет — плашка, без окна скачивания', (t) async {
    final fake = _Fake((lang: 'en', confident: true), missing: const ['en']);
    final s = await _pump(t, fake, prefs: const {
      's_translate_always': ['en'],
    });
    // Своё письмо: переводы за запуск общие, переведённое раньше — из памяти.
    final mail = _mail('en2', _en.bodyHtml!);
    await _detect(t, s.c, mail);
    expect(s.c.phase, MailTranslationPhase.offer);
    expect(fake.translateCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('меню плашки: «Всегда переводить с …» переводит письмо и запоминает язык', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: true)), prefs: const {
      's_translate_never': ['de'],
    });
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.offer);
    expect(s.c.alwaysFromCurrent, isFalse);
    await t.runAsync(() => s.c.alwaysTranslateFrom('en', context: s.ctx, email: _en));
    expect(s.c.phase, MailTranslationPhase.translated);
    expect(s.c.showing, isTrue);
    final settings = s.container.read(settingsProvider);
    expect(settings.translateAlways, ['en']);
    expect(settings.translateNever, ['de']);
    expect(s.c.alwaysFromCurrent, isTrue);
    await t.runAsync(() => s.c.stopAlwaysTranslateFrom('en'));
    expect(s.container.read(settingsProvider).translateAlways, isEmpty);
    expect(s.c.showing, isTrue, reason: 'перевод на экране остаётся');
  });

  testWidgets('меню плашки: «Не переводить с …» — из «Всегда», плашка закрыта, оригинал', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: true)), prefs: const {
      's_translate_always': ['en', 'de'],
    });
    await _detect(t, s.c, _en);
    expect(s.c.showing, isTrue);
    await t.runAsync(() => s.c.neverTranslateFrom('en'));
    final settings = s.container.read(settingsProvider);
    expect(settings.translateNever, ['en']);
    expect(settings.translateAlways, ['de']);
    expect(s.c.dismissed, isTrue);
    expect(s.c.showing, isFalse);
    expect(s.c.apply(_en).bodyHtml, _en.bodyHtml);
  });

  testWidgets('движка нет — ни плашки, ни перевода; «Перевести» объясняет', (t) async {
    final s = await _pump(t, _Fake((lang: 'en', confident: true), available: false));
    await _detect(t, s.c, _en);
    expect(s.c.phase, MailTranslationPhase.none);
    expect(s.c.engineAvailable, isFalse);
    await t.runAsync(() => s.c.translate(s.ctx, _en));
    expect(s.c.phase, MailTranslationPhase.none);
  });
}

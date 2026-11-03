// Перевод входящего письма целиком (1.10.5, просьба владельца 03.11.2026):
// тема переводится (без «RE:»), «Показ перевода письма» — заменить или
// оставить оба. Движок — подделка (заглавные буквы).
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/widgets/mail_translation.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/translation/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translation_test.dart' show FakeTranslator;

final _mail = EmailModel(
  id: 'm1',
  accountId: 'a1',
  folderId: 'INBOX',
  from: const EmailAddress(email: 'ivan@example.org', displayName: 'Ivan N'),
  to: const [EmailAddress(email: 'me@example.org')],
  subject: 'RE: Selected for the Hub',
  receivedAt: DateTime(2026, 10, 31, 3, 33),
  bodyHtml: '<html><body><p>Thank you for the page and your work on it.</p></body></html>',
);

Future<(MailTranslationController, BuildContext)> _pump(WidgetTester t, String? mode) async {
  SharedPreferences.setMockInitialValues({'s_locale': 'ru', if (mode != null) 'tr_read_mode': mode});
  final prefs = await SharedPreferences.getInstance();
  late MailTranslationController c;
  late BuildContext ctx;
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      translatorProvider.overrideWithValue(FakeTranslator()),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Consumer(builder: (context, ref, _) {
        c = MailTranslationController(ref);
        ctx = context;
        return const SizedBox();
      }),
    ),
  ));
  await t.pumpAndSettle();
  return (c, ctx);
}

void main() {
  testWidgets('заменить (по умолчанию): тема и текст — перевод, «RE:» как есть', (t) async {
    final (c, ctx) = await _pump(t, null);
    await t.runAsync(() => c.translate(ctx, _mail));
    expect(c.subjectFor(_mail), (main: 'RE: SELECTED FOR THE HUB', second: null));
    final shown = c.apply(_mail);
    expect(shown.bodyHtml, contains('THANK YOU FOR THE PAGE'));
    expect(shown.bodyHtml, isNot(contains('Thank you for the page')));
    // «Показать оригинал» — тема и текст как были.
    c.showOriginal();
    expect(c.subjectFor(_mail), (main: 'RE: Selected for the Hub', second: null));
    expect(c.apply(_mail).bodyHtml, _mail.bodyHtml);
    c.dispose();
  });

  testWidgets('оставить оба, сначала перевод: тема второй строкой, оригинал под линией', (t) async {
    final (c, ctx) = await _pump(t, 'translationFirst');
    await t.runAsync(() => c.translate(ctx, _mail));
    expect(c.subjectFor(_mail), (main: 'RE: SELECTED FOR THE HUB', second: 'RE: Selected for the Hub'));
    final html = c.apply(_mail).bodyHtml!;
    final iTr = html.indexOf('THANK YOU'), iOrig = html.indexOf('Thank you');
    expect(iTr >= 0 && iOrig > iTr, isTrue, reason: html);
    expect(html.substring(iTr, iOrig), contains('<hr'));
    c.dispose();
  });

  testWidgets('оставить оба, сначала оригинал', (t) async {
    final (c, ctx) = await _pump(t, 'originalFirst');
    await t.runAsync(() => c.translate(ctx, _mail));
    expect(c.subjectFor(_mail), (main: 'RE: Selected for the Hub', second: 'RE: SELECTED FOR THE HUB'));
    final html = c.apply(_mail).bodyHtml!;
    expect(html.indexOf('Thank you') < html.indexOf('THANK YOU'), isTrue);
    c.dispose();
  });
}

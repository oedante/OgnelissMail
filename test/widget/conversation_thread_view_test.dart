// Беседа под текстом письма (1.10.5, просьба владельца 03.11.2026
// «проверь беседу, которая при открытии письма показывается»): нажатие
// открывает письмо (раньше только разворачивало превью), стрелка — больше
// текста, черновик — «Черновик» и кому, текущее письмо не открывается
// повторно.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/widgets/conversation_thread_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';

EmailModel _m(String id, String from, int day, String preview, {bool draft = false}) => EmailModel(
      id: id,
      accountId: 'a1',
      folderId: draft ? 'drafts' : 'INBOX',
      from: EmailAddress(email: '${from.toLowerCase().replaceAll(' ', '.')}@example.com', displayName: from),
      to: const [EmailAddress(email: 'ivan@example.com', displayName: 'Ivan N')],
      subject: 'Re: OgnelissDialer',
      receivedAt: DateTime(2026, 10, day, 21),
      bodyPreview: preview,
      isDraft: draft,
      isRead: true,
    );

void main() {
  testWidgets('нажатие открывает письмо; стрелка — превью; черновик — подпись и кому', (t) async {
    final opened = <String>[];
    final emails = [
      _m('1', 'Ivan N', 29, 'Hi Oedante,\nCongrats! Your page is up.'),
      _m('2', 'Олег Ермишин', 30, 'Hi Ivan,\nThanks a lot.'),
      _m('3', 'Ivan N', 31, 'Hi Oedante,\nOne more thing.'),
      _m('d', 'Олег Ермишин', 31, 'Тест', draft: true),
    ];
    await t.pumpWidget(ProviderScope(
      overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
      child: MaterialApp(
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
            child: ConversationThreadView(emails: emails, currentEmailId: '3', onEmailTap: (e) => opened.add(e.id)),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    // Портрет — тот же, что в шапке письма.
    expect(find.byType(HeroEmailAvatar), findsNWidgets(4));
    // Превью одной строкой, а не только «Hi Oedante,».
    expect(find.text('Hi Oedante, Congrats! Your page is up.'), findsOneWidget);

    await t.tap(find.text('Hi Ivan, Thanks a lot.'));
    expect(opened, ['2']);

    // Текущее письмо уже открыто.
    await t.tap(find.text('Hi Oedante, One more thing.'));
    expect(opened, ['2']);

    // Черновик: «Черновик» и кому; нажатие — наверх, экран откроет редактор.
    expect(find.textContaining('Черновик  Ivan N', findRichText: true), findsOneWidget);
    await t.tap(find.text('Тест'));
    expect(opened, ['2', 'd']);

    // Новые сверху (1.14.0): последнее письмо выше первого.
    expect(t.getTopLeft(find.text('Hi Oedante, One more thing.')).dy,
        lessThan(t.getTopLeft(find.text('Hi Oedante, Congrats! Your page is up.')).dy));

    // Стрелка — больше текста, письмо не открывается (самое старое — внизу).
    await t.tap(find.byTooltip('Развернуть').last);
    await t.pumpAndSettle();
    expect(find.text('Hi Oedante,\nCongrats! Your page is up.'), findsOneWidget);
    expect(opened, ['2', 'd']);
  });
}

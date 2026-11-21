// Беседа под текстом письма (1.10.5, просьба владельца 03.11.2026
// «проверь беседу, которая при открытии письма показывается»): нажатие
// открывает письмо (раньше только разворачивало превью), стрелка — больше
// текста, черновик — «Черновик» и кому, текущее письмо не открывается
// повторно.
//
// Блок «Беседа (N писем)» под письмом (2.6.8, владелец 21.11.2026: «при
// открытии длинных бесед подвисает»): строил все письма беседы сразу и
// каждое — через IntrinsicHeight. Замер на 400 письмах (отладочная сборка):
// первый кадр 3 283 мс → 126 мс, перерисовка письма 1 573 мс → 107 мс.
// Теперь — окно из 7 писем вокруг текущего, «Более новые» и «Более
// ранние» — по 20, «Вся беседа» — экран беседы.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
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

  setUpAll(() => initializeDateFormatting('ru'));

  group('threadWindow', () {
    test('короткая беседа — целиком', () {
      expect(threadWindow(count: 5, current: 3), (start: 0, end: 5));
    });
    test('текущее — самое новое: семь самых новых', () {
      expect(threadWindow(count: 400, current: 0), (start: 0, end: 7));
    });
    test('текущее в середине: два новее, само, четыре раньше', () {
      expect(threadWindow(count: 400, current: 200), (start: 198, end: 205));
    });
    test('текущее — самое старое: последние семь', () {
      expect(threadWindow(count: 400, current: 399), (start: 393, end: 400));
    });
    test('нет текущего — с самого нового', () {
      expect(threadWindow(count: 400, current: -1), (start: 0, end: 7));
    });
    test('«Более новые» и «Более ранние» расширяют окно до краёв', () {
      expect(threadWindow(count: 400, current: 200, moreNewer: 20, moreOlder: 20), (start: 178, end: 225));
      expect(threadWindow(count: 400, current: 3, moreNewer: 20, moreOlder: 1000), (start: 0, end: 400));
    });
  });

  List<EmailModel> mails(int n) => [
        for (var i = 0; i < n; i++)
          EmailModel(
            id: 'm$i',
            accountId: 'a1',
            folderId: 'INBOX',
            from: EmailAddress(email: 'p${i % 5}@corp.example', displayName: 'Человек ${i % 5}'),
            to: const [],
            subject: 'Отчёт',
            bodyPreview: 'Письмо номер $i',
            receivedAt: DateTime(2026, 11, 1).add(Duration(hours: i)),
            isRead: true,
          ),
      ];

  Future<void> pump(WidgetTester t, List<EmailModel> emails, String current, {VoidCallback? onOpenAll}) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
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
            child: ConversationThreadView(emails: emails, currentEmailId: current, onEmailTap: (_) {}, onOpenAll: onOpenAll),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('беседа из 400 писем: показаны 7 вокруг текущего, без IntrinsicHeight', (t) async {
    var opened = 0;
    // Письмо m200 — 200-е с конца (новые сверху): индекс 199.
    await pump(t, mails(400), 'm200', onOpenAll: () => opened++);
    expect(find.textContaining('Письмо номер'), findsNWidgets(7));
    expect(find.text('Письмо номер 200'), findsOneWidget);
    expect(find.text('Письмо номер 202'), findsOneWidget, reason: 'два письма новее текущего');
    expect(find.byType(IntrinsicHeight), findsNothing);
    expect(find.text('Более новые письма: 197'), findsOneWidget);
    expect(find.text('Более ранние письма: 196'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('thread_older')));
    await t.pump();
    expect(find.textContaining('Письмо номер'), findsNWidgets(27));
    expect(find.text('Более ранние письма: 176'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('thread_open_all')));
    expect(opened, 1);
  });

  testWidgets('короткая беседа — целиком, без кнопок', (t) async {
    await pump(t, mails(5), 'm4', onOpenAll: () {});
    expect(find.textContaining('Письмо номер'), findsNWidgets(5));
    expect(find.byKey(const ValueKey('thread_newer')), findsNothing);
    expect(find.byKey(const ValueKey('thread_older')), findsNothing);
    expect(find.byKey(const ValueKey('thread_open_all')), findsNothing);
  });
}

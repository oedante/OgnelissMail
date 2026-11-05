// Строка сведений письма (1.12.x, просьба владельца 04.11.2026: плашки
// «съедают место»): сведения — одной строкой чипов, нажатие раскрывает
// прежнюю плашку, раскрыта одна; перевод и изображения — действием сразу,
// остальное — «▾»; крупный шрифт и узкий телефон — без переполнения.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/delivery_status_provider.dart';
import 'package:ogneliss/features/mail/widgets/delivery_status_banner.dart';
import 'package:ogneliss/features/mail/widgets/mail_notice_bar.dart';
import 'package:ogneliss/features/mail/widgets/mail_translation.dart';
import 'package:ogneliss/features/mail/widgets/read_receipt_banner.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/translation/translator.dart';
import 'package:ogneliss/widgets/common/peek_card.dart' show AppMenuEntry;
import 'package:shared_preferences/shared_preferences.dart';

import '../unit/translation_test.dart' show FakeTranslator;

final _now = DateTime(2026, 11, 4, 12);

final _mail = EmailModel(
  id: 'Sent:5',
  accountId: 'a1',
  folderId: 'INBOX',
  internetMessageId: '<orig-1@example.com>',
  from: const EmailAddress(email: 'news@example.org', displayName: 'Example News'),
  to: const [EmailAddress(email: 'me@example.org')],
  subject: 'Weekly digest',
  receivedAt: _now,
  bodyHtml: '<html><body><p>Thank you for reading our weekly digest.</p></body></html>',
);

Future<void> _pump(
  WidgetTester t,
  Widget Function(BuildContext context) body, {
  Size size = const Size(390, 800),
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  List<DeliveryStatus> delivery = const [],
}) async {
  SharedPreferences.setMockInitialValues({'s_locale': 'ru'});
  final prefs = await SharedPreferences.getInstance();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      translatorProvider.overrideWithValue(FakeTranslator()),
      deliveryStatusesProvider.overrideWith((ref, k) => Stream.value(delivery)),
      deliveryReportOriginalProvider.overrideWith((ref, k) async => null),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      themeMode: themeMode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            body(context),
            const Text('ТЕЛО ПИСЬМА'),
          ])),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Нажать на чип: в строке телефона он может быть за краем — сначала
/// прокрутить строку к нему (шрифт тестов широкий: буква — квадрат 14 px).
Future<void> _tapChip(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
}

/// Набор сведений, как у рассылки с переводом, скрытыми картинками и
/// уведомлением о прочтении, «На контроле» и тегом.
List<MailNotice> _sample({
  VoidCallback? onTranslate,
  VoidCallback? onImages,
  ValueChanged<String>? onImagesMenu,
  VoidCallback? onReceipt,
}) =>
    [
      MailNotice(
        id: 'translate',
        icon: Icons.translate,
        label: 'Перевести · английский',
        detail: 'Язык письма: английский',
        tone: MailNoticeTone.info,
        onTap: onTranslate ?? () {},
      ),
      MailNotice(
        id: 'unsubscribe',
        icon: Icons.unsubscribe,
        label: 'Отписаться',
        detail: 'Рассылка · Example News',
        expanded: (_) => const Text('ПЛАШКА ОТПИСКИ'),
      ),
      MailNotice(
        id: 'images',
        icon: Icons.image_not_supported,
        label: 'Показать изображения',
        onTap: onImages ?? () {},
        menu: const [
          AppMenuEntry(value: 'always', icon: Icons.image, label: 'Всегда от этого домена'),
          AppMenuEntry(value: 'what', icon: Icons.info, label: 'Что заблокировано'),
        ],
        onMenu: onImagesMenu ?? (_) {},
      ),
      MailNotice(
        id: 'readReceipt',
        icon: Icons.mark_email_read,
        label: 'Уведомление о прочтении',
        detail: 'Example News запрашивает уведомление о прочтении',
        expanded: (_) => ReadReceiptBanner(senderName: 'Example News', onSend: onReceipt ?? () {}, onDismiss: () {}),
      ),
      MailNotice(
        id: 'control',
        icon: Icons.task_alt,
        label: 'Нужно ответить · срок завтра',
        expanded: (_) => const Text('ПЛАШКА КОНТРОЛЯ'),
      ),
      MailNotice(id: 'tag:work', label: 'Работа', color: Colors.teal, onTap: () {}),
    ];

void main() {
  testWidgets('несколько сведений — одна строка чипов, плашек нет', (t) async {
    await _pump(t, (_) => MailNoticeBar(notices: _sample()));
    final labels = ['Перевести · английский', 'Отписаться', 'Показать изображения', 'Уведомление о прочтении'];
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    // Одна строка: у всех видимых чипов один верх.
    final top = t.getTopLeft(find.text(labels.first)).dy;
    for (final l in labels.skip(1)) {
      expect(t.getTopLeft(find.text(l)).dy, moreOrLessEquals(top, epsilon: 1));
    }
    // Плашки не раскрыты: строка — одна высота чипа над телом письма.
    expect(find.byType(ReadReceiptBanner), findsNothing);
    expect(find.text('ПЛАШКА ОТПИСКИ'), findsNothing);
    expect(t.getTopLeft(find.text('ТЕЛО ПИСЬМА')).dy, lessThan(60));
    // Телефон: строка прокручивается вбок, последние чипы — за краем.
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    await t.drag(find.text('Перевести · английский'), const Offset(-2000, 0));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.text('Работа')).dx, lessThan(390));
    expect(t.takeException(), isNull);
  });

  testWidgets('нажатие раскрывает плашку, повторное сворачивает, раскрыта одна', (t) async {
    var sent = 0;
    await _pump(t, (_) => MailNoticeBar(notices: _sample(onReceipt: () => sent++)));
    final semantics = t.ensureSemantics();
    expect(t.getSemantics(find.bySemanticsLabel('Example News запрашивает уведомление о прочтении').first),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));

    await _tapChip(t, 'Уведомление о прочтении');
    await t.pumpAndSettle();
    expect(find.byType(ReadReceiptBanner), findsOneWidget);
    expect(t.getSemantics(find.bySemanticsLabel('Example News запрашивает уведомление о прочтении').first),
        isSemantics(isExpanded: true));
    // Кнопки прежней плашки работают в раскрытом виде.
    await t.tap(find.text('Отправить'));
    expect(sent, 1);

    // Другой чип — сворачивает первый и раскрывает свой.
    await _tapChip(t, 'Отписаться');
    await t.pumpAndSettle();
    expect(find.text('ПЛАШКА ОТПИСКИ'), findsOneWidget);
    expect(find.byType(ReadReceiptBanner), findsNothing);

    // Повторное нажатие — свернуть.
    await _tapChip(t, 'Отписаться');
    await t.pumpAndSettle();
    expect(find.text('ПЛАШКА ОТПИСКИ'), findsNothing);
    expect(find.byType(ReadReceiptBanner), findsNothing);
    semantics.dispose();
  });

  testWidgets('«Уменьшить движение» — раскрытие сразу, без анимации', (t) async {
    await _pump(t, (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: MailNoticeBar(notices: _sample()),
        ));
    await _tapChip(t, 'Отписаться');
    await t.pump();
    expect(find.text('ПЛАШКА ОТПИСКИ'), findsOneWidget);
    // Сразу раскрыта целиком (касание ещё рисует круг нажатия — его не считаем).
    expect(t.widget<SizeTransition>(find.byType(SizeTransition)).sizeFactor.value, 1.0);
  });

  testWidgets('чип с одним действием выполняет его сразу; варианты — «▾» и долгое нажатие', (t) async {
    var shown = 0;
    final picked = <String>[];
    await _pump(t, (_) => MailNoticeBar(notices: _sample(onImages: () => shown++, onImagesMenu: picked.add)));
    await _tapChip(t, 'Показать изображения');
    await t.pumpAndSettle();
    expect(shown, 1);
    expect(find.text('ПЛАШКА ОТПИСКИ'), findsNothing);

    // «▾» — меню с остальным.
    await t.ensureVisible(find.byTooltip('Ещё'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Ещё'));
    await t.pumpAndSettle();
    expect(find.text('Что заблокировано'), findsOneWidget);
    await t.tap(find.text('Всегда от этого домена'));
    await t.pumpAndSettle();
    expect(picked, ['always']);

    // Долгое нажатие на чип — то же меню.
    await t.ensureVisible(find.text('Показать изображения'));
    await t.pumpAndSettle();
    await t.longPress(find.text('Показать изображения'));
    await t.pumpAndSettle();
    await t.tap(find.text('Что заблокировано'));
    await t.pumpAndSettle();
    expect(picked, ['always', 'what']);
    expect(shown, 1);
  });

  testWidgets('перевод: «Перевести · …» переводит, чип становится «Оригинал» и обратно', (t) async {
    late MailTranslationController c;
    await _pump(t, (_) => _TranslateHost(onController: (x) => c = x));
    c
      ..phase = MailTranslationPhase.offer
      ..from = 'en'
      ..fromName = 'английский'
      // Перерисовать строку с предложением.
      ..showOriginal();
    await t.pump();
    expect(find.text('Перевести · английский'), findsOneWidget);

    await t.runAsync(() async {
      await t.tap(find.text('Перевести · английский'));
      for (var i = 0; i < 20 && c.phase != MailTranslationPhase.translated; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await t.pumpAndSettle();
    expect(c.phase, MailTranslationPhase.translated);
    expect(find.text('Оригинал'), findsOneWidget);
    expect(c.apply(_mail).bodyHtml, contains('THANK YOU'));

    await t.tap(find.text('Оригинал'));
    await t.pumpAndSettle();
    expect(c.showing, isFalse);
    expect(find.text('Оригинал'), findsNothing);
    expect(c.apply(_mail).bodyHtml, _mail.bodyHtml);
  });

  testWidgets('перевод: «▾» — «Не переводить с языка…» и «Закрыть»', (t) async {
    late MailTranslationController c;
    await _pump(t, (_) => _TranslateHost(onController: (x) => c = x));
    c
      ..phase = MailTranslationPhase.offer
      ..from = 'en'
      ..fromName = 'английский'
      ..showOriginal();
    await t.pump();
    await t.tap(find.byTooltip('Ещё'));
    await t.pumpAndSettle();
    expect(find.text('Не переводить с языка «английский»'), findsOneWidget);
    await t.tap(find.text('Закрыть'));
    await t.pumpAndSettle();
    expect(c.dismissed, isTrue);
    expect(find.textContaining('Перевести'), findsNothing);
  });

  testWidgets('доставка: «Не доставлено» цветом ошибки, раскрытие — прежняя плашка с действиями', (t) async {
    await _pump(
      t,
      (_) => Consumer(builder: (context, ref, _) {
        final n = DeliveryStatusBanner.noticeOf(context, ref, _mail);
        return MailNoticeBar(notices: [?n]);
      }),
      delivery: [
        DeliveryStatus(
          accountId: 'a1',
          messageId: 'orig-1@example.com',
          recipient: 'nobody@example.net',
          action: 'failed',
          status: '5.1.1',
          reportedAt: _now,
        ),
      ],
    );
    expect(find.text('Не доставлено'), findsOneWidget);
    expect(find.text('Отправить снова'), findsNothing);
    final chip = t.widget<Material>(
        find.ancestor(of: find.text('Не доставлено'), matching: find.byType(Material)).first);
    expect(chip.color!.a, lessThan(0.5));
    expect(chip.color!.r, greaterThan(chip.color!.b));
    await _tapChip(t, 'Не доставлено');
    await t.pumpAndSettle();
    expect(find.text('Отправить снова'), findsOneWidget);
    expect(find.textContaining('адрес не существует'), findsOneWidget);
  });

  for (final (name, size, scale, mode, wrap) in [
    ('узкий телефон 360, шрифт ×2', const Size(360, 800), 2.0, ThemeMode.light, false),
    ('тёмная тема, шрифт ×1,3', const Size(411, 800), 1.3, ThemeMode.dark, false),
    ('планшет — перенос строк, шрифт ×2', const Size(820, 1000), 2.0, ThemeMode.light, true),
  ]) {
    testWidgets('без переполнения: $name', (t) async {
      await _pump(t, (_) => MailNoticeBar(notices: _sample(), wrap: wrap, note: 'Переведено Google'),
          size: size, textScale: scale, themeMode: mode);
      expect(t.takeException(), isNull);
      await _tapChip(t, 'Уведомление о прочтении');
      await t.pumpAndSettle();
      expect(find.byType(ReadReceiptBanner), findsOneWidget);
      expect(t.takeException(), isNull);
      if (wrap) {
        // Перенос: все чипы видны без прокрутки, строк больше одной.
        expect(find.byType(Wrap), findsOneWidget);
        expect(t.getTopLeft(find.text('Работа')).dy, greaterThan(t.getTopLeft(find.text('Отписаться')).dy));
      }
    });
  }
}

/// Экран письма в миниатюре: контроллер перевода и строка с чипом перевода.
class _TranslateHost extends ConsumerStatefulWidget {
  final ValueChanged<MailTranslationController> onController;
  const _TranslateHost({required this.onController});

  @override
  ConsumerState<_TranslateHost> createState() => _TranslateHostState();
}

class _TranslateHostState extends ConsumerState<_TranslateHost> {
  late final MailTranslationController c = MailTranslationController(ref)..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    widget.onController(c);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      MailNoticeBar(notices: [?MailTranslateNotice.of(context, c, _mail)], note: MailTranslateNotice.note(context, c));
}

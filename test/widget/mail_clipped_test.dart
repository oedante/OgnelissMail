// Очень длинное письмо — начало и «Показать письмо целиком» (1.9.x, просьба
// владельца 31.10.2026): плашка под письмом, по кнопке — письмо целиком.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/mail_clip.dart';
import 'package:ogneliss/features/mail/widgets/desktop_mail_body.dart';
import 'package:ogneliss/features/mail/widgets/mail_clipped_bar.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/widgets/ui/banner_button.dart';

String paragraphs(int n) =>
    [for (var i = 0; i < n; i++) '<p>Абзац $i. ${'Текст очень длинного письма для проверки. ' * 2}</p>'].join();

bool _shown(WidgetTester t, String text) => find.textContaining(text, findRichText: true).evaluate().isNotEmpty;

void main() {
  testWidgets('длинное письмо: плашка, по кнопке — целиком', (t) async {
    final html = paragraphs(1500);
    expect(html.length, greaterThan(MailClip.textLimit));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DesktopMailBody(html: html, onLink: (_, _) {}),
          ),
        ),
      ),
    );
    // Разбор письма — в рабочем изоляте.
    for (var i = 0; i < 50 && find.byType(MailNativeBody).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump();
    }
    expect(find.byType(MailNativeBody), findsOneWidget);
    expect(find.byType(MailClippedBar), findsOneWidget);
    expect(_shown(t, 'Абзац 0.'), isTrue);
    expect(_shown(t, 'Абзац 1499.'), isFalse);

    await t.ensureVisible(find.byType(BannerButton));
    await t.tap(find.byType(BannerButton));
    await t.pump();
    expect(find.byType(MailClippedBar), findsNothing);
    expect(_shown(t, 'Абзац 1499.'), isTrue);
  });

  testWidgets('короткое письмо — без плашки', (t) async {
    final mail = buildNativeMail(paragraphs(10))!;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MailNativeBody(mail: mail.shortened, onLink: (_, _) {}),
          ),
        ),
      ),
    );
    expect(mail.shortened.clipped, isFalse);
    expect(find.byType(MailClippedBar), findsNothing);
  });

  testWidgets('письмо целиком собирается — кнопка неактивна', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MailClippedBar(onShowWhole: () => taps++, busy: true)),
      ),
    );
    await t.tap(find.byType(BannerButton));
    expect(taps, 0);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MailClippedBar(onShowWhole: () => taps++)),
      ),
    );
    await t.tap(find.byType(BannerButton));
    expect(taps, 1);
  });
}

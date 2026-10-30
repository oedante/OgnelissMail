// Картинка в письме по нажатию — на весь экран (1.8.12, замечание
// 30.10.2026: «иногда они мелкие»); картинка в ссылке открывает ссылку.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';

// PNG 1×1.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  testWidgets('картинка — на весь экран, картинка в ссылке — ссылка', (t) async {
    final links = <String>[];
    const html = '<p>Скрин:</p><img src="data:image/png;base64,$_png" width="40" height="40">'
        '<a href="https://example.com/x"><img src="data:image/png;base64,$_png" width="40" height="40"></a>';
    final mail = buildNativeMailForced(html)!;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MailNativeBody(mail: mail, onLink: (u, _) => links.add(u)),
        ),
      ),
    ));
    await t.pump();
    final imgs = find.byType(Image);
    expect(imgs, findsNWidgets(2));
    // Картинка в тесте не декодируется (высота 0) — касание через обработчик.
    GestureDetector detectorOf(Finder img) =>
        t.widget<GestureDetector>(find.ancestor(of: img, matching: find.byType(GestureDetector)).first);
    detectorOf(imgs.last).onTap!();
    await t.pump();
    expect(links, ['https://example.com/x']);
    detectorOf(imgs.first).onTap!();
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(base64.decode(_png), isNotEmpty);
  });
}

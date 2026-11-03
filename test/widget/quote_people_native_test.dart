// «Люди в цитатах» (1.10.4, замечание владельца 03.11.2026: «новая функция
// делает письмо очень мелким… сделать аналогично заголовку письма»). Простое
// письмо Outlook с цитатами после разбора остаётся «простым» (показ
// виджетами, в обычном размере), а люди в шапках цитат — плашками с тем же
// портретом, что в шапке письма. Нажатие — карточка человека.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/quote_people.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/features/mail/widgets/quote_person_chip.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';

const _outlook = '<div class="WordSection1"><p class="MsoNormal">Добрый день!</p>'
    '<p class="MsoNormal">&nbsp;</p>'
    '<div style="border:none;border-top:solid #E1E1E1 1.0pt;padding:3.0pt 0cm 0cm 0cm">'
    '<p class="MsoNormal"><b>From:</b> Петрякова Ирина Юрьевна &lt;petryakova@yamalspg.ru&gt;<br>'
    '<b>Sent:</b> Monday, November 2, 2026 1:42 PM<br>'
    '<b>To:</b> Хабиров Ренат Фанильевич &lt;r.khabirov@yamalspg.ru&gt;<br>'
    '<b>Cc:</b> Ермишин Олег Андреевич &lt;o.ermishin@yamalspg.ru&gt;; Мисюра Артем Александрович '
    '&lt;a.misura@yamalspg.ru&gt;<br><b>Subject:</b> RE: история</p></div>'
    '<p class="MsoNormal">Добрый день, в прошлом году делал Олег.</p></div>';

void main() {
  test('после разбора письмо остаётся простым (без окна браузера)', () {
    expect(buildNativeMail(_outlook), isNotNull);
    expect(buildNativeMail(QuotePeople.enrich(_outlook)), isNotNull);
  });

  testWidgets('люди в шапке цитаты — плашки с портретом; нажатие — ссылка человека', (t) async {
    final links = <String>[];
    final mail = buildNativeMail(QuotePeople.enrich(_outlook))!;
    await t.pumpWidget(ProviderScope(
      overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MailNativeBody(mail: mail, onLink: (u, _) => links.add(u))),
        ),
      ),
    ));
    await t.pump();
    expect(find.byType(QuotePersonChip), findsNWidgets(4));
    expect(find.byType(HeroEmailAvatar), findsNWidgets(4));
    expect(find.text('Мисюра Артем Александрович'), findsOneWidget);
    // Строки шапки, которые не люди, — как были.
    expect(find.textContaining('RE: история', findRichText: true), findsOneWidget);
    await t.tap(find.text('Хабиров Ренат Фанильевич'));
    expect(links.single, startsWith('ogperson:r.khabirov%40yamalspg.ru'));
  });
}

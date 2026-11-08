// Таблицы писем без браузера: колонка не уже своего самого длинного слова
// (2.2.0, замечание владельца 08.11.2026: подпись Outlook «С уважением…» в
// две колонки шириной 300 и 1614 точек — левая сжималась до букв:
// «Ожгибес|ов», «специал|ист», «Управле|ние»).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/features/mail/widgets/span_table.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';

// Письмо владельца «FW: Объявление» (Outlook): подпись — таблица шириной
// 1914 точек, колонки 300 и 1614.
const _signature = '<div class="WordSection1"><p class="MsoNormal"><b>Уважаемые коллеги!</b></p>'
    '<p class="MsoNormal">Спасибо за понимание!</p>'
    '<table class="MsoNormalTable" border="0" cellspacing="0" cellpadding="0" width="1914" '
    'style="width:1435.55pt;border-collapse:collapse"><tr>'
    '<td width="300" valign="top" style="width:225.15pt;padding:0cm 0cm 0cm 0cm">'
    '<p class="MsoNormal"><span style="color:#2F5496">С уважением,</span></p>'
    '<p class="MsoNormal"><b><span style="color:#2F5496">Алексей Ожгибесов</span></b></p>'
    '<p class="MsoNormal"><span style="color:#2F5496">Главный специалист,</span></p>'
    '<p class="MsoNormal"><span style="color:#2F5496">Управление по технической поддержке производства</span></p>'
    '<p class="MsoNormal"><b><span style="color:#2F5496">АО "Ямал СПГ"</span></b></p>'
    '<p class="MsoNormal"><span style="color:#2F5496">e-mail: </span>'
    '<a href="mailto:Aleksey.Ozhgibesov@yamalspg.ru">Aleksey.Ozhgibesov@yamalspg.ru</a></p></td>'
    '<td width="1614" valign="top" style="width:1210.4pt;padding:0cm 0cm 0cm 0cm">'
    '<p class="MsoNormal"><span lang="EN-US" style="color:#2F5496">Best regards,</span></p>'
    '<p class="MsoNormal"><b><span lang="EN-US" style="color:#2F5496">Aleksey Ozhgibesov</span></b></p>'
    '<p class="MsoNormal"><span lang="EN-US" style="color:#2F5496">Operations Technical Support</span></p>'
    '<p class="MsoNormal"><span lang="EN-US">e-mail: </span>'
    '<a href="mailto:Aleksey.Ozhgibesov@yamalspg.ru">Aleksey.Ozhgibesov@yamalspg.ru</a></p></td>'
    '</tr></table></div>';

Future<void> _show(WidgetTester t, String html, {double width = 400}) async {
  await t.binding.setSurfaceSize(Size(width, 1600));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final mail = buildNativeMail(html);
  expect(mail, isNotNull, reason: 'письмо показывается без браузера');
  await t.pumpWidget(ProviderScope(
    overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: MailNativeBody(mail: mail!, onLink: (_, _) {}))),
    ),
  ));
  await t.pump();
}

/// Слова абзаца [text], разорванные переносом строки посередине.
List<String> _brokenWords(WidgetTester t, String text) {
  final p = t.renderObject<RenderParagraph>(find.text(text, findRichText: true));
  final broken = <String>[];
  var start = 0;
  for (final w in text.split(' ')) {
    final first = p.getOffsetForCaret(TextPosition(offset: start), Rect.zero);
    final last = p.getOffsetForCaret(TextPosition(offset: start + w.length - 1), Rect.zero);
    if (first.dy != last.dy) broken.add(w);
    start += w.length + 1;
  }
  return broken;
}

BoxBorder? _border(SpanCell c) => ((c.child as Container).decoration as BoxDecoration?)?.border;

void main() {
  group('fitColumnWidths', () {
    test('доли из письма, когда слова помещаются, — как были', () {
      expect(fitColumnWidths([1, 1], [50, 60], 330), [165, 165]);
      expect(fitColumnWidths([100, 300], [40, 40], 400), [100, 300]);
    });

    test('узкой по письму колонке — её самое длинное слово, остальным — остаток', () {
      final w = fitColumnWidths([300, 1614], [133, 133], 330);
      expect(w[0], 133);
      expect(w[1], closeTo(197, 1e-9));
    });

    test('на минимумы не хватает — широкие колонки поровну, а не по долям из письма', () {
      expect(fitColumnWidths([300, 1614], [233, 233], 330), [165, 165]);
    });

    test('длинная ссылка в одной колонке не сжимает короткие слова в других', () {
      final w = fitColumnWidths([1, 1, 1], [600, 50, 50], 330);
      expect(w, [110, 110, 110]);
      final logo = fitColumnWidths([160, 400], [133, 236], 330);
      expect(logo[0], 133, reason: 'картинка-логотип целиком');
      expect(logo[1], closeTo(197, 1e-9));
    });

    test('на планшете — минимум узкой колонке, остальное широкой', () {
      final w = fitColumnWidths([300, 1614], [233, 233], 700);
      expect(w[0], 233);
      expect(w[1], closeTo(467, 1e-9));
    });

    test('ширина таблицы — вся ширина', () {
      for (final c in [
        ([1.0, 2.0, 3.0], [10.0, 300.0, 20.0], 320.0),
        ([5.0, 5.0], [400.0, 10.0], 300.0),
        ([1.0], [900.0], 300.0),
        ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], 90.0),
      ]) {
        final w = fitColumnWidths(c.$1, c.$2, c.$3);
        expect(w.fold<double>(0, (a, b) => a + b), closeTo(c.$3, 1e-6), reason: '$c → $w');
      }
    });
  });

  testWidgets('подпись Outlook в две колонки: слова левой колонки не рвутся', (t) async {
    await _show(t, _signature);
    for (final text in [
      'Алексей Ожгибесов',
      'Главный специалист,',
      'Управление по технической поддержке производства',
      'АО "Ямал СПГ"',
    ]) {
      expect(_brokenWords(t, text), isEmpty, reason: text);
    }
    expect(find.text('Operations Technical Support', findRichText: true), findsOneWidget);
    final cells = t.widgetList<SpanCell>(find.byType(SpanCell)).toList();
    expect(cells, hasLength(2));
    final left = t.getSize(find.byWidget(cells[0].child)).width;
    final right = t.getSize(find.byWidget(cells[1].child)).width;
    expect(left, greaterThan(right * 0.5), reason: 'раньше левой доставалось 300/1914 ширины');
  });

  testWidgets('рамки таблицы — одной линией между ячейками, как border-collapse', (t) async {
    await _show(t, '<table border="1"><tr><td>а</td><td>б</td></tr><tr><td>в</td><td>г</td></tr></table>');
    final cells = t.widgetList<SpanCell>(find.byType(SpanCell)).toList();
    expect(cells, hasLength(4));
    final none = BorderSide.none;
    final b0 = _border(cells[0])! as Border;
    expect(b0.top, isNot(none));
    expect(b0.left, isNot(none));
    expect(b0.right, none, reason: 'линию между «а» и «б» рисует «б»');
    expect(b0.bottom, none, reason: 'линию между «а» и «в» рисует «в»');
    final b3 = _border(cells[3])! as Border;
    expect([b3.top, b3.right, b3.bottom, b3.left].every((s) => s != none), isTrue);
  });

  testWidgets('рамка только у самой таблицы — по краям, без линий внутри', (t) async {
    await _show(t, '<table style="border:1px solid #000"><tr><td>а</td><td>б</td></tr></table>');
    final cells = t.widgetList<SpanCell>(find.byType(SpanCell)).toList();
    final a = _border(cells[0])! as Border;
    final b = _border(cells[1])! as Border;
    expect(a.left, isNot(BorderSide.none));
    expect(a.right, BorderSide.none);
    expect(b.left, BorderSide.none);
    expect(b.right, isNot(BorderSide.none));
  });
}

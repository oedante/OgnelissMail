// Поиск в письме (2.2.0, план 08.11.2026 «из мессенджеров»): совпадения
// подсвечиваются в простом показе и в письме без HTML, строка поиска
// показывает «n из m», ↑ ↓ ходят по совпадениям.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/linkified_text.dart';
import 'package:ogneliss/features/mail/widgets/mail_find.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';

/// Куски текста с фоном совпадения: (текст, текущее ли).
List<(String, bool)> _marks(WidgetTester t) {
  final out = <(String, bool)>[];
  bool visit(InlineSpan s) {
    final bg = s.style?.backgroundColor;
    if (s is TextSpan && s.text != null && bg != null) {
      if (bg == findMarkColor(current: true)) out.add((s.text!, true));
      if (bg == findMarkColor(current: false)) out.add((s.text!, false));
    }
    return true;
  }

  for (final p in t.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    p.text.visitChildren(visit);
  }
  // Письмо без HTML — SelectableText (RenderEditable, не RichText).
  for (final w in t.widgetList<SelectableText>(find.byType(SelectableText))) {
    w.textSpan?.visitChildren(visit);
  }
  return out;
}

void main() {
  test('места совпадений без учёта регистра', () {
    expect(findRanges('Отчёт и отчёт, ОТЧЁТ', 'отчёт'), [(0, 5), (8, 13), (15, 20)]);
    expect(findRanges('текст', ''), isEmpty);
    expect(findRanges('', 'а'), isEmpty);
  });

  test('совпадение через границу кусков текста — по частям каждого', () {
    final pieces = splitByMatches(['Алексей Ожги', 'бесов, главный'], findRanges('Алексей Ожгибесов, главный', 'ожгибесов'));
    expect([for (final p in pieces) (p.run, p.text, p.match)], [
      (0, 'Алексей ', null),
      (0, 'Ожги', 0),
      (1, 'бесов', 0),
      (1, ', главный', null),
    ]);
  });

  testWidgets('простой показ: все совпадения, и в таблице; текущее — ярче; «следующее»', (t) async {
    final mail = buildNativeMail('<p>План работ на неделю.</p><p>Второй <b>план</b> — запасной.</p>'
        '<table border="1"><tr><td>План А</td><td>Срок</td></tr></table>')!;
    final c = MailFindController();
    await t.pumpWidget(ProviderScope(
      overrides: [personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty())],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: MailNativeBody(mail: mail, onLink: (_, _) {}, find: c))),
      ),
    ));
    c.setQuery('план');
    await t.pump();
    await t.pump();
    expect(c.total, 3);
    expect(_marks(t), [('План', true), ('план', false), ('План', false)]);
    c.next();
    await t.pump();
    expect(c.current, 1);
    expect(_marks(t), [('План', false), ('план', true), ('План', false)]);
    c.prev();
    c.prev();
    await t.pump();
    expect(c.current, 2, reason: 'по кругу');
    c.setQuery('');
    await t.pump();
    expect(_marks(t), isEmpty);
  });

  testWidgets('письмо без HTML: совпадения и счёт', (t) async {
    final c = MailFindController();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LinkifiedText('Счёт № 5 и счёт № 6 приложены.\nСчёт оплатить до пятницы.', onLink: (_, _) {}, find: c),
        ),
      ),
    ));
    c.setQuery('счёт');
    await t.pump();
    await t.pump();
    expect(c.total, 3);
    expect([for (final m in _marks(t)) m.$2], [true, false, false]);
  });

  testWidgets('строка поиска: «n из m», «Не найдено», крестик', (t) async {
    final c = MailFindController();
    var closed = false;
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      home: Scaffold(appBar: AppBar(bottom: MailFindBar(controller: c, onClose: () => closed = true))),
    ));
    await t.enterText(find.byType(TextField), 'отчёт');
    await t.pump(const Duration(milliseconds: 300));
    expect(c.query, 'отчёт');
    c.report(4);
    await t.pump();
    expect(find.text('1 из 4'), findsOneWidget);
    c.report(0);
    await t.pump();
    expect(find.text('Не найдено'), findsOneWidget);
    await t.tap(find.byTooltip('Закрыть'));
    expect(closed, isTrue);
  });
}

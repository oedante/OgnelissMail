// Таблица во вложении сеткой (1.11.x, предпросмотр документов): заголовки
// столбцов и номера строк, значения ячеек, вкладки листов, полный текст
// ячейки в строке над сеткой, жест вбок листает сетку внутри PageView,
// щипок меняет масштаб.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/mail/widgets/doc_sheet_view.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/documents/doc_sheets.dart';

const _long = 'Очень длинный текст ячейки, который не помещается в ширину столбца и обрезается';

OfficeSheetsDoc _doc({int rows = 300, int cols = 40}) {
  final book = DocBookBuilder();
  final bold = book.style(const DocCellStyle(bold: true, fill: 0xFF1F4E79, color: 0xFFFFFFFF));
  final a = DocSheetBuilder(book, 'Продажи');
  a.add(0, 0, 'Товар', style: bold);
  a.add(0, 1, 'Сумма', style: bold);
  for (var r = 1; r < rows; r++) {
    a.add(r, 0, 'Строка $r');
    a.add(r, 1, '${r * 10},50', kind: DocCellKind.number);
    for (var c = 2; c < cols; c++) {
      a.add(r, c, '$r-$c', kind: DocCellKind.number);
    }
  }
  a.add(1, 2, _long);
  final b = DocSheetBuilder(book, 'Итоги');
  b.add(0, 0, 'Всего');
  b.add(0, 1, '42', kind: DocCellKind.number);
  return OfficeSheetsDoc(sheets: [a.build(), b.build()], styles: book.styles);
}

Widget _app(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.lightTheme(1.0),
  locale: const Locale('ru'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _barText(WidgetTester tester) => tester.widget<SelectableText>(find.byType(SelectableText)).data ?? '';

void main() {
  testWidgets('заголовки, номера строк, значения; касание — полный текст над сеткой', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(DocSheetView(doc: _doc())));
    await _settle(tester);

    expect(find.semantics.byLabel('A'), findsOne);
    expect(find.semantics.byLabel('C'), findsOne);
    expect(find.semantics.byLabel('1'), findsOne);
    expect(find.semantics.byLabel('12'), findsOne);
    expect(find.semantics.byLabel('Товар'), findsOne);
    expect(find.semantics.byLabel('20,50'), findsOne);
    // Строк 300 — нарисованы только видимые.
    expect(find.semantics.byLabel('Строка 250'), findsNothing);

    // Касание C2 — длинный текст целиком в строке над сеткой: строка 40,
    // заголовок 22, номера строк 36,5, столбцы по 64, строки по 20.
    await tester.tapAt(const Offset(36.5 + 64 * 2 + 10, 40 + 22 + 20 + 10));
    await _settle(tester);
    expect(_barText(tester), _long);
    expect(find.text('C2'), findsOneWidget);

    // Через доступность (двойное касание TalkBack) — то же.
    tester.semantics.tap(find.semantics.byLabel('Товар'));
    await _settle(tester);
    expect(_barText(tester), 'Товар');
    expect(find.text('A1'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('вкладки листов переключают лист', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(DocSheetView(doc: _doc())));
    await _settle(tester);
    expect(find.text('Продажи'), findsWidgets);
    expect(find.semantics.byLabel('Всего'), findsNothing);

    await tester.tap(find.text('Итоги'));
    await _settle(tester);
    expect(find.semantics.byLabel('Всего'), findsOne);
    expect(find.semantics.byLabel('Товар'), findsNothing);

    await tester.tap(find.text('Продажи').last);
    await _settle(tester);
    expect(find.semantics.byLabel('Товар'), findsOne);
    semantics.dispose();
  });

  testWidgets('жест вбок листает сетку, а не страницы PageView', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final pages = PageController();
    addTearDown(pages.dispose);
    await tester.pumpWidget(
      _app(
        PageView(
          controller: pages,
          children: [
            DocSheetView(doc: _doc()),
            const Center(child: Text('Вторая страница')),
          ],
        ),
      ),
    );
    await _settle(tester);
    expect(find.semantics.byLabel('A'), findsOne);

    await tester.dragFrom(const Offset(400, 400), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(pages.page, 0);
    // Столбец A ушёл за край — сетка прокрутилась.
    expect(find.semantics.byLabel('A'), findsNothing);
    expect(find.text('Вторая страница'), findsNothing);
    semantics.dispose();
  });

  testWidgets('щипок увеличивает, кнопка масштаба возвращает 100 %', (tester) async {
    tester.view.physicalSize = const Size(600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(DocSheetView(doc: _doc())));
    await _settle(tester);
    expect(find.textContaining('%'), findsNothing);

    const c = Offset(300, 400);
    final a = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await a.moveBy(const Offset(-10, 0));
      await b.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    final chip = find.textContaining('%');
    expect(chip, findsOneWidget);
    final pct = int.parse(tester.widget<Text>(chip).data!.replaceAll('%', ''));
    expect(pct, greaterThan(150));

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('пустой лист и тёмная тема', (tester) async {
    final book = DocBookBuilder();
    final empty = OfficeSheetsDoc(sheets: [DocSheetBuilder(book, 'Пусто').build()], styles: book.styles);
    await tester.pumpWidget(_app(DocSheetView(doc: empty), theme: AppTheme.darkTheme(1.0)));
    await _settle(tester);
    expect(find.text('Лист пуст'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_app(DocSheetView(doc: _doc(rows: 20, cols: 5)), theme: AppTheme.darkTheme(1.0)));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(DocSheetView), findsOneWidget);
    expect(RendererBinding.instance.renderViews, isNotEmpty);
  });
}

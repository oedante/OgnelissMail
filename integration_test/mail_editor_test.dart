// integration_test/mail_editor_test.dart
// Редактор письма (MailEditor: HugeRTE во встроенном окне, JavaScript) на
// эмуляторе Android (1.9.x, просьба владельца 31.10.2026): загружается,
// текст проходит туда и обратно (setHtml/getHtml), касание в строку ставит
// туда курсор — при масштабе интерфейса 1,0 и 0,85 (окно рисуется без него —
// UiZoomUndo, текст уменьшает textZoom). Курсор не там, где коснулись, — та
// же ошибка, что «капли» выделения в стороне от текста (замечания 28 и
// 29.10.2026).
//
// Отдельно: flutter test integration_test/mail_editor_test.dart -d <эмулятор>

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/widgets/mail_editor.dart';

import 'support/harness.dart';

void main() {
  ensureBinding();
  mailEditorTests();
}

/// Строки с метками: курсор ищется по ближайшему блоку «ogn-t…».
const _html =
    '<div id="ogn-t1">Первая строка письма.</div>'
    '<div id="ogn-t2">Вторая строка: «кавычки», &lt;угловые скобки&gt; и знак ✓.</div>'
    '<div id="ogn-t3">Третья строка — сюда касание.</div>'
    '<div id="ogn-t4">Четвёртая строка.</div>';

/// Скрипт в окне редактора; результат — строкой.
Future<String> _js(InAppWebViewController c, String body) async {
  final r = await c.evaluateJavascript(source: '(function(){$body})()');
  return r?.toString() ?? '';
}

/// Блок, в котором стоит курсор («ogn-t1»…; '' — вне их).
Future<String> _caretBlock(InAppWebViewController c) => _js(c, '''
  var ed = hugerte.activeEditor;
  var n = ed && ed.selection.getNode();
  var b = n && n.closest ? n.closest('[id^="ogn-t"]') : null;
  return b ? b.id : '';''');

/// Экран «Нового сообщения» в тесте: редактор во всю ширину. Клавиатура не
/// сдвигает окно — координаты касания не «уезжают».
Widget _composeScreen(
  MailEditorController controller, {
  required VoidCallback onReady,
  required VoidCallback onFailed,
}) {
  return Scaffold(
    resizeToAvoidBottomInset: false,
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [MailEditor(controller: controller, height: 420, onReady: onReady, onFailed: onFailed)],
      ),
    ),
  );
}

void mailEditorTests() {
  setUpAll(() async {
    await loadStrings();
  });

  tearDown(() => setUiZoom(1.0));

  for (final zoom in const [1.0, 0.85]) {
    testWidgets('редактор (масштаб интерфейса $zoom): загрузка, текст туда и обратно, курсор по касанию', (
      tester,
    ) async {
      setUiZoom(zoom);
      final controller = MailEditorController();
      final ready = Completer<void>();
      final failed = Completer<void>();
      await tester.pumpWidget(
        testApp(
          zoom: zoom,
          home: _composeScreen(
            controller,
            onReady: () {
              if (!ready.isCompleted) ready.complete();
            },
            onFailed: () {
              if (!failed.isCompleted) failed.complete();
            },
          ),
        ),
      );
      // Сторож самого редактора — 15 с (onFailed).
      await waitFor(
        tester,
        Future.any([ready.future, failed.future]),
        what: 'редактор загрузился (onReady)',
        timeout: const Duration(seconds: 40),
      );
      expect(failed.isCompleted, isFalse, reason: 'редактор сообщил об ошибке загрузки (onFailed)');
      expect(controller.isReady, isTrue);
      final c = controller.debugWebView!;

      // Окно — во всю ширину экрана и без масштаба Flutter: CSS-пиксель
      // страницы редактора = точка экрана.
      final rect = tester.getRect(find.byType(InAppWebView));
      expect(rect.width, closeTo(screenWidth(tester), 1));

      // Текст туда и обратно. Знаки вроде «» и — редактор может записать
      // сущностями HTML (&laquo;) — текст строк сверяется по DOM.
      await controller.setHtml(_html);
      final got = await controller.getHtml() ?? '';
      for (final id in const ['ogn-t1', 'ogn-t2', 'ogn-t3', 'ogn-t4']) {
        expect(got, contains('id="$id"'));
      }
      expect(got, contains('&lt;угловые скобки&gt;'));
      Future<String> text(String id) =>
          _js(c, "return hugerte.activeEditor.getBody().querySelector('#$id').textContent;");
      expect(await text('ogn-t2'), 'Вторая строка: «кавычки», <угловые скобки> и знак ✓.');
      expect(await text('ogn-t3'), 'Третья строка — сюда касание.');
      // Второй круг — без изменений.
      await controller.setHtml(got);
      expect(await controller.getHtml(), got);

      // Курсор — в первую строку: касание должно его перенести.
      await _js(c, '''
        var ed = hugerte.activeEditor;
        ed.selection.setCursorLocation(ed.getBody().querySelector('#ogn-t1'), 0);
        return 'ok';''');
      expect(await _caretBlock(c), 'ogn-t1');

      // Где текст третьей строки: прямоугольник текста во фрейме редактора
      // плюс место фрейма в окне — в CSS-пикселях окна.
      final pos =
          jsonDecode(
                await _js(c, '''
        var ed = hugerte.activeEditor;
        var el = ed.getBody().querySelector('#ogn-t3');
        var rg = ed.getDoc().createRange(); rg.selectNodeContents(el);
        var r = rg.getBoundingClientRect();
        var f = ed.iframeElement.getBoundingClientRect();
        return JSON.stringify({x: f.left + r.left + r.width / 2, y: f.top + r.top + r.height / 2,
          w: window.innerWidth});'''),
              )
              as Map<String, dynamic>;
      final k = rect.width / (pos['w'] as num);
      expect(k, closeTo(1.0, 0.02), reason: 'окно редактора не должно масштабироваться Flutter (UiZoomUndo)');
      final at = rect.topLeft + Offset((pos['x'] as num).toDouble(), (pos['y'] as num).toDouble()) * k;
      await tapAtGlobal(tester, at);
      await pollUntil(
        tester,
        () => _caretBlock(c),
        (b) => b == 'ogn-t3',
        what: 'курсор в третьей строке после касания в $at',
      );
    }, skip: !onAndroid);
  }
}

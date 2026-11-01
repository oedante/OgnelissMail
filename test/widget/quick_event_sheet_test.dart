// Встреча одной фразой (1.9.x): живой предпросмотр и «Создать» по Enter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/calendar/quick_event.dart';
import 'package:ogneliss/features/calendar/widgets/quick_event_sheet.dart';

void main() {
  testWidgets('предпросмотр по мере ввода, Enter — создать', (t) async {
    QuickEvent? created;
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        body: QuickEventPanel(
                          onCreate: (e) async {
                            created = e;
                            return true;
                          },
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    // Пустое поле — без предпросмотра, «Создать» неактивна.
    expect(find.byKey(const ValueKey('quickEventPreview')), findsNothing);

    await t.enterText(find.byKey(const ValueKey('quickEventField')), 'Обед завтра 13:00-14:00 в кафе «Ромашка»');
    await t.pumpAndSettle();
    final preview = find.byKey(const ValueKey('quickEventPreview'));
    expect(preview, findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('Обед')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.textContaining('13:00–14:00')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('кафе «Ромашка»')), findsOneWidget);

    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(created, isNotNull);
    expect(created!.title, 'Обед');
    expect(created!.end.difference(created!.start), const Duration(hours: 1));
    // Панель закрылась.
    expect(find.byType(QuickEventPanel), findsNothing);
    // Строка «Встреча создана» уходит сама.
    await t.pump(const Duration(seconds: 6));
  });
}

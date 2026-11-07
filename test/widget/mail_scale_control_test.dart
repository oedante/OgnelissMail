// Масштаб широкого письма — пилюлей в строке сведений (1.15.1, замечание
// владельца 07.11.2026): окно сообщает действие, экран рисует пилюлю.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';

void main() {
  testWidgets('действие окна — слушателям после кадра; снимает его только тот, кто сообщил', (tester) async {
    final c = MailScaleControl();
    addTearDown(c.dispose);
    var heard = 0;
    c.addListener(() => heard++);
    var runs = 0;
    final first = Object(), second = Object();

    c.report(first, MailScaleAction.actualSize, () => runs++);
    expect(c.action, MailScaleAction.actualSize);
    expect(heard, 0, reason: 'окно сообщает во время своей сборки — слушатели позже');
    await tester.pumpWidget(const SizedBox());
    expect(heard, 1);

    c.run();
    expect(runs, 1);

    // Новое окно (цитата раскрыта) сообщило раньше, чем закрылось прежнее.
    c.report(second, MailScaleAction.fitToWidth, () => runs += 10);
    c.release(first);
    expect(c.action, MailScaleAction.fitToWidth);
    c.run();
    expect(runs, 11);

    c.release(second);
    expect(c.action, MailScaleAction.none);
    c.run();
    expect(runs, 11, reason: 'действия нет — ничего не делается');
    await tester.pumpWidget(const SizedBox(width: 1));
    expect(heard, greaterThanOrEqualTo(2));
  });
}

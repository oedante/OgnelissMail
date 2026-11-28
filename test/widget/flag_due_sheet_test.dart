// «Флаг» со сроком — одной кнопкой (2.7.5, замечание владельца 28.11.2026):
// одно меню для экрана письма, карточки в ленте и панели широкого экрана.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/widgets/flag_due_sheet.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/flag_due.dart';

void main() {
  EmailModel mail({bool flagged = false}) => EmailModel(
        id: 'm1', accountId: 'a1', folderId: 'inbox',
        from: const EmailAddress(email: 'x@example.com'), to: const [], subject: 'Смета',
        receivedAt: DateTime(2026, 11, 27), isFlagged: flagged,
      );

  Future<FlagChoice?> pick(WidgetTester tester, EmailModel email, String tap) async {
    FlagChoice? result;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Builder(builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await pickFlagDue(context, email),
              child: const Text('открыть'),
            ),
          )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tap).first);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('флажок со сроком «Завтра»', (tester) async {
    final r = await pick(tester, mail(), 'Завтра');
    expect(r, (flagged: true, due: FlagDue.tomorrow));
    expect(find.text('Снять флажок'), findsNothing);
  });

  testWidgets('флажок стоит — «Снять флажок» в том же меню', (tester) async {
    final r = await pick(tester, mail(flagged: true), 'Снять флажок');
    expect(r, (flagged: false, due: FlagDue.none));
  });
}

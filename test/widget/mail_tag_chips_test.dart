// Кнопки полей {…} в конструкторах подписи и приветствия (18.11.2026):
// помещаются на узком телефоне, нажатие вставляет поле в место курсора.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/settings/widgets/mail_tag_chips.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/mail_tags.dart';

void main() {
  testWidgets('приветствие: группы и вставка в место курсора (русский)', (t) async {
    t.view.physicalSize = const Size(360 * 3, 800 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final c = TextEditingController(text: 'Здравствуйте, !');
    c.selection = const TextSelection.collapsed(offset: 14);
    await t.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: MailTagChips(tags: MailTags.forGreeting, onInsert: (s) => insertAtCursor(c, s)),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final ru = AppLocalizations(const Locale('ru'));
    expect(find.text(ru.tr('tagGroupRecipient')), findsOneWidget);
    expect(find.text(ru.tr('tagGroupSender')), findsOneWidget);
    await t.tap(find.text(ru.tr('tagToAddress')));
    await t.pump();
    expect(c.text, 'Здравствуйте, {обращение}!');
    expect(c.selection.baseOffset, 'Здравствуйте, {обращение}'.length);
    expect(t.takeException(), isNull);
  });
}

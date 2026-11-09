// Свайпы (2.2.0, замечания владельца 09.11.2026): в беседе «На контроль» не
// было видно, свайпам не хватало подтверждения; в беседе «Входящие» стояли
// на каждом письме, в том числе на своих, а «Sent» — именем с сервера.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/mail/screens/conversation_screen.dart' show conversationFolderChips;
import 'package:ogneliss/features/settings/providers/settings_provider.dart' show SwipeAction;
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/swipe_done.dart';

EmailModel _mail(String id, String folderId, {String? folderName, int control = 0, bool read = true}) => EmailModel(
      id: id,
      accountId: 'a',
      folderId: folderId,
      folderName: folderName,
      internetMessageId: '<$id@x>',
      subject: 'Тема',
      from: const EmailAddress(email: 'me@x.ru'),
      to: const [EmailAddress(email: 'you@x.ru')],
      cc: const [],
      bcc: const [],
      receivedAt: DateTime(2026, 11, 6),
      size: 10,
      hasAttachments: false,
      tags: const [],
      priority: EmailPriority.normal,
      isRead: read,
      isFlagged: false,
      isDraft: false,
      controlState: control,
    );

FolderModel _f(String id, String name, FolderType type) =>
    FolderModel(id: id, accountId: 'a', displayName: name, type: type, showInUnified: true, sortOrder: 0);

void main() {
  final ru = AppLocalizations(const Locale('ru'));
  final folders = {
    for (final f in [
      _f('INBOX', 'INBOX', FolderType.inbox),
      _f('Sent', 'Sent', FolderType.sent),
      _f('Archive', 'Archive', FolderType.archive),
      _f('Projects', 'Проекты', FolderType.custom),
    ])
      f.id: f,
  };

  test('папки в беседе: без «Входящих», своё — без «Отправленных», остальное — по типу', () {
    expect(conversationFolderChips([_mail('1', 'INBOX', folderName: 'INBOX')], folders, mine: false, l10n: ru), isEmpty);
    expect(conversationFolderChips([_mail('2', 'INBOX', folderName: 'INBOX')], folders, mine: true, l10n: ru), isEmpty,
        reason: 'копия своего письма во «Входящих»');
    expect(conversationFolderChips([_mail('3', 'Sent', folderName: 'Sent')], folders, mine: true, l10n: ru), isEmpty);
    expect(conversationFolderChips([_mail('4', 'Sent', folderName: 'Sent')], folders, mine: false, l10n: ru),
        [ru.tr('sent')],
        reason: '«Sent» — на языке приложения');
    expect(
        conversationFolderChips(
            [_mail('5', 'Archive'), _mail('5b', 'Projects'), _mail('5c', 'INBOX')], folders,
            mine: false, l10n: ru),
        [ru.tr('archive'), 'Проекты']);
    // Папки нет в списке (ещё не прочитан) — по имени с сервера.
    expect(conversationFolderChips([_mail('6', 'x', folderName: 'Sent Items')], const {}, mine: true, l10n: ru), isEmpty);
  });

  testWidgets('после свайпа — плашка с результатом на своей строке, через секунду исчезает', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const Column(children: [
            SwipeDoneOverlay(id: 'a/1', child: SizedBox(height: 60, child: Text('Письмо 1'))),
            SwipeDoneOverlay(id: 'a/2', child: SizedBox(height: 60, child: Text('Письмо 2'))),
          ]);
        }),
      ),
    ));
    showSwipeDone(ctx, SwipeAction.control, _mail('1', 'INBOX'), ru, id: 'a/1');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(ru.tr('swipeDoneControl')), findsOneWidget);
    expect(find.byKey(const ValueKey('swipe_done')), findsOneWidget, reason: 'только на строке a/1');

    showSwipeDone(ctx, SwipeAction.control, _mail('2', 'INBOX', control: 1), ru, id: 'a/2');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(ru.tr('swipeDoneControlOff')), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('swipe_done')), findsNothing);

    // Убирающие действия («Архив») — без плашки: у них «Вернуть».
    showSwipeDone(ctx, SwipeAction.archive, _mail('1', 'INBOX'), ru, id: 'a/1');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('swipe_done')), findsNothing);

    showSwipeDone(ctx, SwipeAction.markRead, _mail('1', 'INBOX', read: false), ru, id: 'a/1', read: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(ru.tr('swipeDoneRead')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });
}

// Плашка папки в ленте «Вся почта» — на языке приложения (2.3.2, замечание
// владельца 11.11.2026: у писем Яндекса плашка «Sent», а рядом «Входящие»).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/providers/folder_names.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('стандартные папки называются по-русски, свои — как на сервере', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('ru'));
    expect(localizedFolderLabel('INBOX', l10n), l10n.inbox);
    expect(localizedFolderLabel('Sent', l10n), l10n.tr('sent'));
    expect(localizedFolderLabel('Sent Messages', l10n), l10n.tr('sent'));
    expect(localizedFolderLabel('[Gmail]/Sent Mail', l10n), l10n.tr('sent'));
    expect(localizedFolderLabel('Drafts', l10n), l10n.tr('drafts'));
    expect(localizedFolderLabel('Deleted Items', l10n), l10n.tr('trash'));
    expect(localizedFolderLabel('Удалённые', l10n), l10n.tr('trash'));
    expect(localizedFolderLabel('Spam', l10n), l10n.tr('junk'));
    expect(localizedFolderLabel('Проекты', l10n), 'Проекты');
    expect(l10n.tr('sent'), isNot('Sent'));
  });
}

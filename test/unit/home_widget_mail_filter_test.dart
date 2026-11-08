// Виджет «Почта»: что показывать (08.11.2026, план п. 8.1) — все
// непрочитанные, VIP, с флажком; строка письма с id, ящиком, текстом и
// значками для кнопок «Прочитано» и «В архив».
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/account_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/home_widget_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: AccountType.imap.index, email: 'me@example.com', displayName: 'Me',
        username: 'me@example.com', createdAt: DateTime(2026)));
    await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'INBOX', accountId: 'a1', displayName: 'Inbox', type: Value(FolderType.inbox.index)));
    Future<void> mail(String id, String from, {bool read = false, bool flag = false, int h = 10}) =>
        db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a1',
              folderId: 'INBOX',
              fromEmail: from,
              toRecipients: '[]',
              subject: 'Тема $id',
              receivedAt: DateTime(2026, 11, 8, h),
              isRead: Value(read),
              isFlagged: Value(flag),
              hasAttachments: Value(id == 'm2'),
              bodyPlain: const Value('> цитата\nДобрый день!\nСмета во вложении.'),
            ));
    await mail('m1', 'colleague@corp.ru', h: 9);
    await mail('m2', 'boss@corp.ru', h: 10);
    await mail('m3', 'colleague@corp.ru', read: true, flag: true, h: 11);
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> run(String filter) async {
    SharedPreferences.setMockInitialValues({
      'widget_mail_filter': filter,
      'focus_mode': jsonEncode({'vipEmails': ['Boss@corp.ru']}),
    });
    await HomeWidgetService.update(db, ['a1'], AppLocalizations(const Locale('ru')), force: true);
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString(HomeWidgetService.mailKey)!) as Map<String, dynamic>;
  }

  List<String> ids(Map<String, dynamic> j) => [for (final it in j['items'] as List) it['id'] as String];

  test('все непрочитанные — новые сверху; строка с текстом без цитаты и значками', () async {
    final j = await run('all');
    expect(ids(j), ['m2', 'm1']);
    final first = (j['items'] as List).first as Map;
    expect(first['acc'], 'a1');
    expect(first['p'], 'Добрый день! Смета во вложении.');
    expect(first['att'], 1);
    expect(j['actRead'], isNotEmpty);
  });

  test('VIP, с флажком', () async {
    var j = await run('vip');
    expect(ids(j), ['m2']);
    expect(j['title'], contains('VIP'));
    expect(j['count'], '1');
    j = await run('flagged');
    expect(ids(j), ['m3']);
  });
}

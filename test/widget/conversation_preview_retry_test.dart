// Беседа (2.6.8, замечание владельца 21.11.2026): «карточки в беседах иногда
// новые верхние письма отображают пустыми, а потом подгружают». Текст письма
// приходит в базу «тихо» (storeBodiesQuietly — без оповещения списков), и
// карточка оставалась пустой до постороннего изменения таблицы. Теперь
// экран беседы сам перепроверяет пустые карточки.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/screens/conversation_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/person_photo.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('текст письма записан «тихо» — карточка беседы заполняется сама', (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await t.runAsync(() async {
      await db.into(db.accounts).insert(AccountsCompanion.insert(
          id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Я', username: 'me', createdAt: DateTime(2026)));
      await db.into(db.folders).insert(FoldersCompanion.insert(id: 'INBOX', accountId: 'a1', displayName: 'Входящие'));
      for (final (id, preview) in const [('INBOX:1', 'Первое письмо беседы'), ('INBOX:2', null)]) {
        await db.into(db.emails).insert(EmailsCompanion.insert(
              id: id,
              accountId: 'a1',
              folderId: 'INBOX',
              conversationId: const Value('c1'),
              fromEmail: 'anna@corp.example',
              fromName: const Value('Анна'),
              toRecipients: '[]',
              subject: 'Отчёт',
              bodyPreview: Value(preview),
              receivedAt: DateTime(2026, 11, 21, id == 'INBOX:1' ? 10 : 11),
              isRead: const Value(true),
            ));
      }
    });
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        personPhotosProvider.overrideWith((ref) => const Stream<Map<String, String>>.empty()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(1.0),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ConversationScreen(conversationId: 'c1', accountId: 'a1'),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await settle();
    expect(find.text('Первое письмо беседы'), findsOneWidget);
    expect(find.textContaining('Второе письмо'), findsNothing, reason: 'текста ещё нет');

    // «Письма на телефоне» записали текст без оповещения списков.
    await t.runAsync(() => db.storeBodiesQuietly('a1', {
          'INBOX:2': {'body_plain': 'Второе письмо: сроки и объёмы во вложении.'},
        }));
    await t.pump(const Duration(seconds: 3));
    await settle();
    expect(find.text('Второе письмо: сроки и объёмы во вложении.'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
    await t.runAsync(db.close);
  });
}

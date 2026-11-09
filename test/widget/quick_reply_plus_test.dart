// «+» в строке быстрого ответа (2.2.0, план 08.11.2026 «из мессенджеров»):
// фото, файл или шаблон. Шаблон — в поле, на место курсора; выбор файлов —
// системный, здесь не проверяется.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/compose/providers/templates_provider.dart';
import 'package:ogneliss/features/mail/widgets/quick_reply_bar.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _email = EmailModel(
  id: 'INBOX:1',
  accountId: 'a1',
  folderId: 'INBOX',
  from: const EmailAddress(email: 'anna@corp.example', displayName: 'Анна Петрова'),
  to: const [EmailAddress(email: 'me@corp.example', displayName: 'Я')],
  subject: 'Отчёт',
  receivedAt: DateTime(2026, 11, 8),
);

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      // Только свой шаблон: готовые уже «добавлены».
      'reply_templates_builtin_v1': true,
      'reply_templates_v1': '[{"title":"Принято","body":"Принято, {имя}."}]',
    });
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1', type: 7, email: 'me@corp.example', displayName: 'Иван', username: 'me', createdAt: DateTime(2026)));
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
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
        home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: QuickReplyBar(email: _email))),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('«+» — фото, файл или шаблон', (t) async {
    await pump(t);
    expect(find.byTooltip('Фото, файл или шаблон'), findsOneWidget);
    await t.tap(find.byIcon(AppIcons.add));
    await t.pumpAndSettle();
    expect(find.text('Фото'), findsOneWidget);
    expect(find.text('Прикрепить файл'), findsOneWidget);
    expect(find.text('Вставить шаблон'), findsOneWidget);
  });

  testWidgets('шаблон — в поле, с подстановкой имени', (t) async {
    await pump(t);
    expect(ProviderScope.containerOf(t.element(find.byType(QuickReplyBar))).read(templatesProvider), hasLength(1));
    await t.tap(find.byIcon(AppIcons.add));
    await t.pumpAndSettle();
    await t.tap(find.text('Вставить шаблон'));
    await t.pumpAndSettle();
    await t.tap(find.text('Принято'));
    await t.pumpAndSettle();
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Принято, Иван.');
    // Есть текст — круглая кнопка отправляет, а не открывает редактор.
    expect(find.byIcon(AppIcons.send), findsOneWidget);
  });
}

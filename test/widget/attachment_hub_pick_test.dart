// Файлы в письмо из «Вложений» (14.11.2026, просьба владельца): экран в
// режиме выбора — нажатие отмечает файл, «Приложить» возвращает отмеченные
// (уже на устройстве) редактору письма. Плюс «Ответить с вложениями» —
// пункт показывается только у писем с файлами (EmailModel.hasFiles).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/screens/attachment_hub_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/mail/attachment_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCache extends AttachmentCacheService {
  @override
  Future<String?> get(String attachmentId) async => '/tmp/hub/$attachmentId';
}

AttachmentHubItem _item(String id, String name) => AttachmentHubItem(
      attachmentId: id,
      name: name,
      mimeType: 'application/pdf',
      size: 1000,
      emailId: 'm$id',
      emailSubject: 'Прошу согласовать',
      senderName: 'Анна',
      senderEmail: 'anna@corp.example',
      receivedAt: DateTime(2026, 11, 10),
      accountId: 'a1',
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('выбор: отметить два файла, «Приложить» — оба уходят в письмо', (t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    List<PickedHubFile>? result;
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (ctx, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await ctx.push<List<PickedHubFile>>('/attachment-hub?pick=1'),
              child: const Text('ПРИЛОЖИТЬ ИЗ ПОЧТЫ'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/attachment-hub',
        builder: (_, st) => AttachmentHubScreen(pick: st.uri.queryParameters['pick'] == '1'),
      ),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
        attachmentCacheProvider.overrideWithValue(_FakeCache()),
        attachmentHubProvider.overrideWith((ref) async => [
              _item('1', 'Договор.pdf'),
              _item('2', 'Смета.pdf'),
              _item('3', 'Акт.pdf'),
            ]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme(1.0),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: router,
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('ПРИЛОЖИТЬ ИЗ ПОЧТЫ'));
    await t.pumpAndSettle();

    expect(find.text('Выберите вложения'), findsOneWidget);
    final attach = find.widgetWithText(FilledButton, 'Приложить');
    expect(t.widget<FilledButton>(attach).onPressed, isNull, reason: 'ничего не отмечено');

    await t.tap(find.text('Договор.pdf'));
    await t.pump();
    await t.tap(find.text('Акт.pdf'));
    await t.pump();
    expect(find.text('Выбрано файлов: 2'), findsOneWidget);
    // Снять и снова отметить — порядок по отметке.
    await t.tap(find.text('Договор.pdf'));
    await t.pump();
    expect(find.text('Выбрано файлов: 1'), findsOneWidget);
    await t.tap(find.text('Договор.pdf'));
    await t.pump();

    await t.tap(attach);
    await t.pumpAndSettle();
    expect(find.text('ПРИЛОЖИТЬ ИЗ ПОЧТЫ'), findsOneWidget, reason: 'экран закрылся');
    expect(result, isNotNull);
    expect([for (final f in result!) f.name], ['Акт.pdf', 'Договор.pdf']);
    // Путь — из кэша вложений (ключ: ящик, письмо, вложение).
    expect(result!.first.path, endsWith('m3|3'));
  });

  test('«Ответить с вложениями» — только у писем с файлами', () {
    EmailModel mail({List<EmailAttachment> files = const [], bool flag = false}) => EmailModel(
          id: 'x',
          accountId: 'a1',
          folderId: 'INBOX',
          subject: 'Прошу согласовать',
          from: const EmailAddress(email: 'anna@corp.example'),
          to: const [],
          receivedAt: DateTime(2026, 11, 14),
          attachments: files,
          hasAttachments: flag,
        );
    const pdf = EmailAttachment(id: '1', name: 'Договор.pdf', mimeType: 'application/pdf', size: 10);
    const pic = EmailAttachment(id: '2', name: 'logo.png', mimeType: 'image/png', size: 10, isInline: true);
    expect(mail().hasFiles, isFalse);
    expect(mail(flag: true).hasFiles, isTrue, reason: 'строка ленты: списка нет — по флагу');
    expect(mail(files: [pdf]).hasFiles, isTrue);
    expect(mail(files: [pic], flag: true).hasFiles, isFalse, reason: 'только картинка в тексте');
  });
}

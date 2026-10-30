// 1.8.12 (замечание владельца 29.10.2026): в одном архиве Ogneliss — данные
// нескольких ящиков. В меню ящика — только его архив; весь архив — на
// отдельном экране, ящики — отбором сверху.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/features/archive/archive_providers.dart';
import 'package:ogneliss/features/archive/screens/archive_hub_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/archive/archive_container.dart';
import 'package:ogneliss/services/archive/archive_db.dart';
import 'package:ogneliss/services/archive/archive_vault.dart';

class _OpenVault extends ArchiveVault {
  @override
  Future<ArchiveVaultState> build() async => ArchiveVaultState(ArchiveStatus.open,
      header: ArchiveHeader(id: 't', name: '', created: DateTime(2026), app: 'test', keys: const {}));
}

void main() {
  test('ящики архива: письма, встречи, задачи и контакты — у каждого свои', () async {
    final db = ArchiveDb(NativeDatabase.memory());
    try {
      await db.upsertAccount('p1', 'oleg@corp.ru', 'Олег', 'exchange', 1);
      await db.upsertAccount('p2', 'anna@corp.ru', '', 'imap', 2);
      await db.upsertAccount('p3', 'petr@corp.ru', 'Пётр', 'imap', 3);
      await db.addMessage(ArchiveMessageInput(
        accountId: 'p1',
        folderChain: const [(name: 'Входящие', type: 'inbox')],
        sourceId: 'm1',
        subject: 'Смета',
        fromName: 'Иван',
        fromEmail: 'ivan@corp.ru',
        date: DateTime(2025, 3, 1),
        bodyHtml: '<p>Смета</p>',
        searchText: 'Смета',
      ));
      await db.upsertEvent(
          accountId: 'p2', sourceId: 'e1', title: 'Планёрка', start: DateTime(2025), end: DateTime(2025), allDay: false);
      await db.upsertTask(accountId: 'p2', sourceId: 't1', title: 'Отчёт');
      await db.upsertContact(accountId: 'p2', sourceId: 'c1', name: 'Иван');

      final all = {for (final a in await db.accounts()) a.id: a};
      expect(all['p1']!.messages, 1);
      expect([all['p1']!.events, all['p1']!.tasks, all['p1']!.contacts], [0, 0, 0]);
      expect([all['p2']!.messages, all['p2']!.events, all['p2']!.tasks, all['p2']!.contacts], [0, 1, 1, 1]);
      expect(all['p1']!.isEmpty, isFalse);
      expect(all['p2']!.isEmpty, isFalse, reason: 'писем нет, но есть встречи, задачи и контакты');
      expect(all['p3']!.isEmpty, isTrue);
      expect(all['p2']!.label, 'anna@corp.ru');
    } finally {
      await db.close();
    }
  });

  test('ящик архива для ящика приложения: по id, иначе по адресу', () {
    const all = [
      ArchiveAccountInfo('d1', 'Oleg@Corp.ru', 'Олег', messages: 3),
      ArchiveAccountInfo('p2', 'anna@corp.ru', 'Анна', messages: 1),
    ];
    expect(archiveAccountOf(all, id: 'p2', email: 'other@corp.ru')?.id, 'p2');
    // Архив объединён с копией с другого устройства: у ящика там свой id.
    expect(archiveAccountOf(all, id: 'p1', email: ' oleg@corp.ru ')?.id, 'd1');
    expect(archiveAccountOf(all, id: 'p9', email: 'petr@corp.ru'), isNull);
    expect(archiveAccountOf(all, id: 'p9', email: ''), isNull);
  });

  testWidgets('весь архив: ящики со своими папками, отбор по ящику', (tester) async {
    const accounts = [
      ArchiveAccountInfo('p1', 'oleg@corp.ru', 'Олег', messages: 5),
      ArchiveAccountInfo('p2', 'anna@corp.ru', 'Анна', messages: 2, events: 1),
      ArchiveAccountInfo('p3', 'petr@corp.ru', 'Пётр'),
    ];
    const folders = [
      ArchiveFolder(id: 1, accountId: 'p1', path: 'Входящие', name: 'Входящие', parentId: null, type: 'inbox', count: 4),
      ArchiveFolder(
          id: 2, accountId: 'p1', path: 'Входящие/Проекты', name: 'Проекты', parentId: 1, type: 'custom', count: 1),
      ArchiveFolder(id: 3, accountId: 'p2', path: 'Отчёты', name: 'Отчёты', parentId: null, type: 'custom', count: 2),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        archiveVaultProvider.overrideWith(_OpenVault.new),
        archiveAccountsProvider.overrideWith((ref) async => accounts),
        archiveFoldersProvider.overrideWith((ref) async => folders),
        archiveStatsProvider.overrideWith((ref) async => const ArchiveStats(messages: 7, events: 1)),
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
        home: const ArchiveHubScreen(),
      ),
    ));
    for (var i = 0; i < 10 && find.text('Проекты').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Весь архив'), findsOneWidget);
    // Оба ящика с данными — разделами и отбором; пустой ящик не показан.
    expect(find.text('Олег'), findsNWidgets(2));
    expect(find.text('Анна'), findsNWidgets(2));
    expect(find.text('Пётр'), findsNothing);
    expect(find.text('Проекты'), findsOneWidget);
    expect(find.text('Отчёты'), findsOneWidget);
    expect(find.text('Встречи'), findsOneWidget);

    // Отбор: только Анна.
    await tester.tap(find.widgetWithText(FilterChip, 'Анна'));
    await tester.pump();
    expect(find.text('Проекты'), findsNothing);
    expect(find.text('Отчёты'), findsOneWidget);
    expect(find.text('Олег'), findsOneWidget, reason: 'остался только отбор');

    // Свернуть «Входящие» Олега — подпапка скрывается.
    await tester.tap(find.widgetWithText(FilterChip, 'Все ящики'));
    await tester.pump();
    expect(find.text('Проекты'), findsOneWidget);
    await tester.tap(find.byIcon(AppIcons.expand_less));
    await tester.pump();
    expect(find.text('Проекты'), findsNothing);
  });
}

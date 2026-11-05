// Планшет и компьютер ближе к Outlook (1.12.x, просьба владельца 04.11.2026,
// задание D2): выбор писем Ctrl/Shift/Ctrl+A/Esc в ленте, область чтения
// справа / снизу / скрыта, вложение из письма в панели — в той же панели.
//
// Лента — настоящая (MailListScreen) на базе в памяти; синхронизация с
// сервером подменена (refresh ничего не делает), письма приходят из базы.

import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';
import 'package:ogneliss/features/mail/screens/attachment_preview_screen.dart';
import 'package:ogneliss/features/mail/screens/mail_list_screen.dart';
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/adaptive_layout.dart';
import 'package:ogneliss/widgets/common/pane_navigator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _n = 8;

String _subject(int i) => 'Смета участка $i';

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1',
        type: 7,
        email: 'me@corp.example',
        displayName: 'Я',
        username: 'me',
        createdAt: DateTime(2026),
      ));
  await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'inbox',
        accountId: 'a1',
        displayName: 'Входящие',
        type: Value(FolderType.inbox.index),
      ));
  final now = DateTime.now();
  for (var i = 1; i <= _n; i++) {
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: 'm$i',
          accountId: 'a1',
          folderId: 'inbox',
          // Без «@»: строка не просит фото у адресной книги.
          fromEmail: 'sender-$i',
          fromName: Value('Отправитель $i'),
          toRecipients: '[]',
          subject: _subject(i),
          // m1 — самое новое, вверху ленты.
          receivedAt: now.subtract(Duration(minutes: i)),
          isRead: const Value(true),
        ));
  }
  return db;
}

/// Лента без сервера: письма — из базы, «Обновить» ничего не делает.
class _NoSyncEmails extends EmailsNotifier {
  _NoSyncEmails(Ref ref)
      : super(
          ref: ref,
          db: ref.watch(databaseProvider),
          account: ref.watch(activeAccountProvider),
          accounts: ref.watch(accountsProvider),
          folderId: ref.watch(selectedFolderIdProvider),
          isUnified: ref.watch(unifiedModeProvider),
          allAccountsMode: ref.watch(allAccountsModeProvider),
          groupByConversation: false,
        );

  @override
  Future<void> refresh() async {}
}

Future<SharedPreferences> _prefs({String pane = 'right'}) async {
  SharedPreferences.setMockInitialValues({
    // Экран разрешений после входа и листание соседних писем — не здесь.
    'perm_setup_shown_v2': true,
    'mail_swipe_pager': false,
    'reading_pane': pane,
  });
  return SharedPreferences.getInstance();
}

Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpList(WidgetTester tester, AppDatabase db, SharedPreferences prefs,
    {Size size = const Size(1280, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: '/mail', routes: [
    GoRoute(
      path: '/mail',
      builder: (_, __) => const MailListScreen(),
      routes: [
        GoRoute(
          path: 'detail/:id',
          builder: (_, s) => Scaffold(body: Text('ЭКРАН ПИСЬМА ${s.pathParameters['id']}')),
        ),
      ],
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      emailsProvider.overrideWith(_NoSyncEmails.new),
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
  await _settle(tester);
  expect(find.text(_subject(1)), findsOneWidget);
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  // Отложенный прогрев (движок письма, редактор) — после ухода экрана.
  await tester.pump(const Duration(seconds: 3));
  await tester.runAsync(db.close);
}

/// Отмеченные строки ленты (флажки режима выбора).
Set<int> _checked(WidgetTester tester) => {
      for (var i = 1; i <= _n; i++)
        if (tester
            .widgetList<EmailListTile>(find.byType(EmailListTile))
            .any((t) => t.email.id == 'm$i' && t.isChecked))
          i,
    };

bool _selecting(WidgetTester tester) =>
    tester.widgetList<EmailListTile>(find.byType(EmailListTile)).any((t) => t.isInSelectionMode);

Future<void> _click(WidgetTester tester, int i, {List<LogicalKeyboardKey> keys = const []}) async {
  for (final k in keys) {
    await tester.sendKeyDownEvent(k);
  }
  await tester.tap(find.text(_subject(i)), kind: PointerDeviceKind.mouse);
  for (final k in keys.reversed) {
    await tester.sendKeyUpEvent(k);
  }
  await tester.pump();
}

Future<void> _keys(WidgetTester tester, LogicalKeyboardKey key, {bool control = false}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('ru');
  });

  group('выбор писем как в Outlook', () {
    testWidgets('Ctrl — отметить и снять, Shift — подряд, Ctrl+Shift — добавить, Ctrl+A — все, Esc — снять',
        (tester) async {
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs());
      const ctrl = LogicalKeyboardKey.controlLeft;
      const shift = LogicalKeyboardKey.shiftLeft;

      await _click(tester, 2, keys: [ctrl]);
      expect(_selecting(tester), isTrue);
      expect(_checked(tester), {2});
      // Письмо не открылось: панель — с подсказкой «Выберите письмо».
      expect(find.text('Выберите письмо'), findsOneWidget);

      await _click(tester, 4, keys: [ctrl]);
      expect(_checked(tester), {2, 4});
      await _click(tester, 2, keys: [ctrl]);
      expect(_checked(tester), {4});

      // Shift — от последнего нажатого (4) до 6, прежний выбор заменяется.
      await _click(tester, 2, keys: [ctrl]);
      expect(_checked(tester), {2, 4});
      await _click(tester, 6, keys: [shift]);
      expect(_checked(tester), {2, 3, 4, 5, 6});
      await _click(tester, 7, keys: [shift]);
      expect(_checked(tester), {2, 3, 4, 5, 6, 7}, reason: 'начало диапазона не сдвигается');
      await _click(tester, 3, keys: [shift]);
      expect(_checked(tester), {2, 3});

      // Ctrl+Shift — диапазон добавляется к отмеченным.
      await _click(tester, 6, keys: [ctrl]);
      expect(_checked(tester), {2, 3, 6});
      await _click(tester, 8, keys: [ctrl, shift]);
      expect(_checked(tester), {2, 3, 6, 7, 8});

      // Ctrl+A — все загруженные письма; число — в шапке выбора.
      await _keys(tester, LogicalKeyboardKey.keyA, control: true);
      expect(_checked(tester), {for (var i = 1; i <= _n; i++) i});
      expect(find.text('$_n'), findsOneWidget);

      // Esc — выбор снят, лента — как была.
      await _keys(tester, LogicalKeyboardKey.escape);
      expect(_selecting(tester), isFalse);
      expect(_checked(tester), isEmpty);

      // Снова Ctrl — и последнее снятое закрывает режим выбора.
      await _click(tester, 5, keys: [ctrl]);
      expect(_checked(tester), {5});
      await _click(tester, 5, keys: [ctrl]);
      expect(_selecting(tester), isFalse);
      await _done(tester, db);
    });

    testWidgets('Ctrl+A сразу после нажатия в ленте; в поле поиска Ctrl+A — тексту', (tester) async {
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs());
      // Нажатие на полосу даты (не письмо) — фокус ленте.
      await tester.tap(find.text('СЕГОДНЯ'), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await _keys(tester, LogicalKeyboardKey.keyA, control: true);
      expect(_checked(tester), hasLength(_n));
      await _keys(tester, LogicalKeyboardKey.escape);
      expect(_selecting(tester), isFalse);

      // Поиск: Ctrl+A выделяет набранное, письма не отмечаются.
      await tester.tap(find.byKey(const ValueKey('mail_search_pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'смета');
      await tester.pump();
      await _keys(tester, LogicalKeyboardKey.keyA, control: true);
      expect(_selecting(tester), isFalse);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
      await _done(tester, db);
    });

    testWidgets('нажатие без клавиш — как раньше: открывает письмо, в режиме выбора — отмечает', (tester) async {
      final db = (await tester.runAsync(_db))!;
      // Область чтения скрыта — письмо открывается экраном, панель не нужна.
      await _pumpList(tester, db, await _prefs(pane: 'hidden'));
      await _click(tester, 3, keys: [LogicalKeyboardKey.controlLeft]);
      await _click(tester, 5);
      expect(_checked(tester), {3, 5});
      await _keys(tester, LogicalKeyboardKey.escape);
      await _click(tester, 5);
      await _settle(tester, rounds: 3);
      expect(find.text('ЭКРАН ПИСЬМА m5'), findsOneWidget);
      await _done(tester, db);
    });
  });

  group('область чтения', () {
    Future<Rect> rectOf(WidgetTester tester, Finder f) => Future.value(tester.getRect(f));

    testWidgets('справа: подсказка панели правее ленты', (tester) async {
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs());
      final row = await rectOf(tester, find.byType(EmailListTile).first);
      final pane = await rectOf(tester, find.text('Выберите письмо'));
      expect(pane.left, greaterThan(row.right));
      expect(tester.widget<PaneSplitter>(find.byType(PaneSplitter).last).axis, Axis.horizontal);
      await _done(tester, db);
    });

    testWidgets('снизу: лента во всю ширину сверху, панель под ней, разделитель тянется вверх-вниз',
        (tester) async {
      final db = (await tester.runAsync(_db))!;
      final prefs = await _prefs(pane: 'bottom');
      await _pumpList(tester, db, prefs);
      final layout = tester.getRect(find.byType(AdaptiveLayout));
      final row = tester.getRect(find.byType(EmailListTile).first);
      final pane = tester.getRect(find.text('Выберите письмо'));
      expect(row.width, closeTo(layout.width, 1));
      expect(pane.top, greaterThan(row.bottom));
      final splitter = find.byWidgetPredicate((w) => w is PaneSplitter && w.axis == Axis.vertical);
      expect(splitter, findsOneWidget);
      // Потянуть вниз — лента выше; высота запоминается.
      final before = tester.getRect(splitter).top;
      await tester.dragFrom(tester.getCenter(splitter), const Offset(0, 80), kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(tester.getRect(splitter).top, greaterThan(before + 40));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(prefs.getDouble('split_ratio_v_mail'), isNotNull);
      await _done(tester, db);
    });

    testWidgets('скрыта: лента во всю ширину, панели нет, письмо — отдельным экраном', (tester) async {
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs(pane: 'hidden'));
      final layout = tester.getRect(find.byType(AdaptiveLayout));
      expect(tester.getRect(find.byType(EmailListTile).first).width, closeTo(layout.width, 1));
      expect(find.text('Выберите письмо'), findsNothing);
      expect(find.byType(PaneNavigator), findsNothing);
      await _click(tester, 2);
      await _settle(tester, rounds: 3);
      expect(find.text('ЭКРАН ПИСЬМА m2'), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('снизу на низком окне — справа; телефон — без панели при любом выборе', (tester) async {
      final db = (await tester.runAsync(_db))!;
      await _pumpList(tester, db, await _prefs(pane: 'bottom'), size: const Size(1280, 420));
      final row = tester.getRect(find.byType(EmailListTile).first);
      expect(tester.getRect(find.text('Выберите письмо')).left, greaterThan(row.right));
      await _done(tester, db);

      final db2 = (await tester.runAsync(_db))!;
      await _pumpList(tester, db2, await _prefs(pane: 'bottom'), size: const Size(400, 800));
      expect(find.text('Выберите письмо'), findsNothing);
      await _done(tester, db2);
    });

    testWidgets('меню «⋮» ленты: «Область чтения» меняет положение', (tester) async {
      final db = (await tester.runAsync(_db))!;
      final prefs = await _prefs();
      await _pumpList(tester, db, prefs);
      final menu = MaterialLocalizations.of(tester.element(find.byType(MailListScreen))).showMenuTooltip;
      await tester.tap(find.byTooltip(menu).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Область чтения'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Снизу'));
      await _settle(tester, rounds: 3);
      expect(prefs.getString('reading_pane'), 'bottom');
      expect(find.byWidgetPredicate((w) => w is PaneSplitter && w.axis == Axis.vertical), findsOneWidget);
      await _done(tester, db);
    });
  });

  group('вложение в области чтения', () {
    late Directory dir;
    late String path;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('d2_att');
      // .log — простым текстом сразу (.txt с 1.14.0 разбирается документом
      // в отдельном потоке, а здесь проверяется только место показа).
      path = '${dir.path}/smeta.log';
      File(path).writeAsStringSync('Смета на ремонт кровли');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Widget host({required bool pane}) {
      final message = Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => openAttachment(context, PreviewItem(filePath: path, fileName: 'smeta.log')),
              child: const Text('ПИСЬМО: открыть smeta.log'),
            ),
          ),
        ),
      );
      return MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Row(children: [
            const SizedBox(width: 400, child: Center(child: Text('ЛЕНТА'))),
            Expanded(child: pane ? PaneNavigator(child: message) : message),
          ]),
        ),
      );
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('ПИСЬМО: открыть smeta.log'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('из письма в панели — в той же панели, «Назад» — к письму', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(pane: true));
      await open(tester);
      final preview = find.byType(AttachmentPreviewScreen);
      expect(find.descendant(of: find.byType(PaneNavigator), matching: preview), findsOneWidget);
      expect(find.text('Смета на ремонт кровли'), findsOneWidget);
      // Лента рядом осталась, просмотр — только в панели.
      expect(find.text('ЛЕНТА'), findsOneWidget);
      expect(tester.getRect(preview).left, greaterThanOrEqualTo(400));
      // Сохранить и «Открыть в другом приложении» — на месте.
      expect(find.byTooltip('Сохранить'), findsOneWidget);
      expect(find.byTooltip(AppLocalizations.of(tester.element(preview)).tr('openExternally')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(find.text('ПИСЬМО: открыть smeta.log'), findsOneWidget);
    });

    testWidgets('вне панели — отдельным экраном, как раньше', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(pane: false));
      await open(tester);
      expect(find.byType(AttachmentPreviewScreen), findsOneWidget);
      expect(find.byType(PaneNavigator), findsNothing);
      // Поверх всего окна: ленты под просмотром не видно.
      expect(tester.getRect(find.byType(AttachmentPreviewScreen)).left, 0);
      expect(find.text('ЛЕНТА'), findsNothing);
    });
  });
}

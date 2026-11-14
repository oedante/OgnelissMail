// Плотность ленты и анимация открытия письма (1.9.x, просьба владельца
// 31.10.2026): строки ленты в трёх плотностях (высота, портрет, область
// нажатия не меньше 48 dp), Hero строки — только с включённой анимацией,
// ноль лишних перестроений ленты, свайп вниз закрывает письмо только на
// телефоне и только от верха письма.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/core/theme/appearance.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/features/mail/widgets/preview_text.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';
import 'package:ogneliss/widgets/common/mail_open_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _preview = 'Добрый день, коллеги! Прошу до пятницы внести даты отпусков.';

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          id: 'a1',
          type: 7,
          email: 'me@corp.example',
          displayName: 'Я',
          username: 'me',
          createdAt: DateTime(2026),
        ),
      );
  await db
      .into(db.folders)
      .insert(
        FoldersCompanion.insert(
          id: 'inbox',
          accountId: 'a1',
          displayName: 'Входящие',
          type: Value(FolderType.inbox.index),
        ),
      );
  return db;
}

EmailModel _mail(String id, {bool read = true}) => EmailModel(
  id: id,
  accountId: 'a1',
  folderId: 'inbox',
  // Без «@»: строка не просит фото у адресной книги.
  from: EmailAddress(email: 'sender-$id', displayName: 'Отправитель $id'),
  to: const [],
  subject: 'График отпусков $id',
  bodyPreview: _preview,
  receivedAt: DateTime.now().subtract(const Duration(hours: 1)),
  isRead: read,
  hasAttachments: true,
);

Widget _app(AppDatabase db, SharedPreferences prefs, Appearance a, Widget home, {double textScale = 1}) =>
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.lightTheme(1.0, appearance: a),
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(db.close);
}

/// Лента и (по [_HostState.open]) письмо поверх неё страницей MailOpenPage
/// — как в приложении (go_router строит такие же страницы).
class _Host extends StatefulWidget {
  const _Host({super.key, required this.list, required this.mail});

  final Widget list;
  final Widget mail;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool open = false;

  void setOpen(bool v) => setState(() => open = v);

  @override
  Widget build(BuildContext context) => HeroControllerScope(
    controller: MaterialApp.createMaterialHeroController(),
    child: Navigator(
      pages: [
        MaterialPage<void>(key: const ValueKey('list'), child: widget.list),
        if (open) MailOpenPage<void>(key: const ValueKey('mail'), child: widget.mail),
      ],
      onDidRemovePage: (page) {
        if (page.key == const ValueKey('mail')) setState(() => open = false);
      },
    ),
  );
}

/// Письмо: шапка и длинный текст в прокрутке.
class _Mail extends StatelessWidget {
  const _Mail();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Письмо')),
    body: SingleChildScrollView(
      child: Column(children: [for (var i = 0; i < 60; i++) SizedBox(height: 40, child: Text('Строка $i'))]),
    ),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('ru');
  });

  group('плотность ленты', () {
    Future<(double, double)> rowAndAvatar(WidgetTester tester, ListDensity d, {double textScale = 1}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.pumpWidget(
        _app(
          db,
          prefs,
          Appearance(density: d),
          Scaffold(
            body: ListView(
              children: [EmailListTile(email: _mail('m1', read: false), onTap: () {})],
            ),
          ),
          textScale: textScale,
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final row = tester.getSize(find.byType(EmailListTile)).height;
      final avatar = tester.getSize(find.byType(CircleAvatar).first).width;
      if (d == ListDensity.compact) {
        // Тема и начало текста — одной строкой, отдельной строки превью нет.
        expect(find.byType(PreviewText), findsNothing);
        expect(find.textContaining(_preview, findRichText: true), findsOneWidget);
      } else {
        expect(find.byType(PreviewText), findsOneWidget);
      }
      await _done(tester, db);
      return (row, avatar);
    }

    testWidgets('непрочитанное заметно: точка, время цветом акцента, имя жирным (14.11.2026)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.pumpWidget(_app(
        db,
        prefs,
        const Appearance(),
        Scaffold(
          body: ListView(children: [
            EmailListTile(email: _mail('m1', read: false), onTap: () {}),
            EmailListTile(email: _mail('m2'), onTap: () {}),
          ]),
        ),
      ));
      await _settle(tester);
      final unread = find.byType(EmailListTile).at(0), read = find.byType(EmailListTile).at(1);
      expect(find.descendant(of: unread, matching: find.byKey(const ValueKey('unread_dot'))), findsOneWidget);
      expect(find.descendant(of: read, matching: find.byKey(const ValueKey('unread_dot'))), findsNothing);
      final primary = Theme.of(tester.element(unread)).colorScheme.primary;
      TextStyle styleOf(Finder row, String text) =>
          tester.widget<Text>(find.descendant(of: row, matching: find.text(text))).style!;
      final time = tester
          .widgetList<Text>(find.descendant(of: unread, matching: find.byType(Text)))
          .firstWhere((t) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t.data ?? ''));
      expect(time.style!.color, primary);
      expect(styleOf(unread, 'Отправитель m1').fontWeight, FontWeight.w700);
      expect(styleOf(read, 'Отправитель m2').fontWeight, FontWeight.w400);
      await _done(tester, db);
    });

    testWidgets('компактная ниже обычной, просторная выше; строки не ниже 48 dp', (tester) async {
      final compact = await rowAndAvatar(tester, ListDensity.compact);
      final normal = await rowAndAvatar(tester, ListDensity.normal);
      final roomy = await rowAndAvatar(tester, ListDensity.comfortable);
      expect(compact.$1, lessThan(normal.$1));
      expect(roomy.$1, greaterThan(normal.$1));
      expect(compact.$1, greaterThanOrEqualTo(48));
      expect(compact.$2, 36);
      expect(normal.$2, 48);
      expect(roomy.$2, 52);
    });

    testWidgets('компактная при крупном шрифте на узком экране — без переполнения', (tester) async {
      tester.view.physicalSize = const Size(320, 568) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final compact = await rowAndAvatar(tester, ListDensity.compact, textScale: 1.3);
      expect(compact.$1, greaterThanOrEqualTo(48));
    });

    testWidgets('удержание портрета в компактной — область 48 dp', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.pumpWidget(
        _app(
          db,
          prefs,
          const Appearance(density: ListDensity.compact),
          Scaffold(
            body: ListView(
              children: [EmailListTile(email: _mail('m1'), onTap: () {})],
            ),
          ),
        ),
      );
      await _settle(tester);
      final slot = find.ancestor(of: find.byType(CircleAvatar).first, matching: find.byType(SizedBox)).first;
      expect(tester.getSize(slot).height, greaterThanOrEqualTo(48));
      await _done(tester, db);
    });
  });

  group('анимация открытия письма', () {
    Future<void> pumpList(WidgetTester tester, AppDatabase db, Appearance a, {GlobalKey<_HostState>? host}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final list = Scaffold(
        body: ListView(
          children: [for (var i = 0; i < 5; i++) EmailListTile(email: _mail('m$i'), onTap: () {})],
        ),
      );
      await tester.pumpWidget(_app(db, prefs, a, _Host(key: host, list: list, mail: const _Mail())));
      await _settle(tester);
    }

    testWidgets('выключена — у строк нет Hero; включена — портрет и тема', (tester) async {
      final db = (await tester.runAsync(_db))!;
      await pumpList(tester, db, const Appearance());
      expect(find.byType(Hero), findsNothing);
      await pumpList(tester, db, const Appearance(openAnimation: true));
      expect(find.byType(Hero), findsNWidgets(10));
      // Компактная: тема и превью одной строкой — летит только портрет.
      await pumpList(tester, db, const Appearance(openAnimation: true, density: ListDensity.compact));
      expect(find.byType(Hero), findsNWidgets(5));
      await _done(tester, db);
    });

    for (final on in [false, true]) {
      testWidgets('открыть и закрыть письмо — строки ленты не перестраиваются (анимация: $on)', (tester) async {
        final db = (await tester.runAsync(_db))!;
        final host = GlobalKey<_HostState>();
        await pumpList(tester, db, Appearance(openAnimation: on), host: host);
        var rebuilds = 0;
        debugOnRebuildDirtyWidget = (element, builtOnce) {
          if (element.widget is EmailListTile) rebuilds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);
        host.currentState!.setOpen(true);
        await tester.pumpAndSettle();
        expect(find.text('Письмо'), findsOneWidget);
        expect(find.byType(MailSwipeToClose), on ? findsOneWidget : findsNothing);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('Письмо'), findsNothing);
        debugOnRebuildDirtyWidget = null;
        expect(rebuilds, 0);
        await _done(tester, db);
      });
    }
  });

  testWidgets('портрет и тема летят в шапку письма и обратно — без ошибок', (tester) async {
    final db = (await tester.runAsync(_db))!;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final host = GlobalKey<_HostState>();
    final m = _mail('m0');
    final list = Scaffold(
      body: ListView(
        children: [EmailListTile(email: m, onTap: () {})],
      ),
    );
    // Шапка письма как в MailDetailScreen: портрет в верхней панели, тема крупно.
    final mail = Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: HeroEmailAvatar(
            emailId: '${m.accountId}/${m.id}',
            initial: 'О',
            color: Colors.blue,
            email: m.from.email,
            radius: 16,
            openHero: true,
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: MailSubjectHero(
            tag: MailHeroTags.subject(m.accountId, m.id),
            enabled: true,
            child: Text(m.subject, maxLines: 3, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      _app(db, prefs, const Appearance(openAnimation: true), _Host(key: host, list: list, mail: mail)),
    );
    await _settle(tester);
    host.currentState!.setOpen(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Посреди полёта: тема — в оверлее полёта (строка ленты и шапка вместе).
    expect(find.text(m.subject), findsWidgets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(host.currentState!.open, isFalse);
    await _done(tester, db);
  });

  group('свайп вниз закрывает письмо', () {
    Future<GlobalKey<_HostState>> pumpOpen(WidgetTester tester, {Size size = const Size(393, 852)}) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final host = GlobalKey<_HostState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(1.0, appearance: const Appearance(openAnimation: true)),
          home: _Host(
            key: host,
            list: const Scaffold(body: Center(child: Text('Лента'))),
            mail: const _Mail(),
          ),
        ),
      );
      host.currentState!.setOpen(true);
      await tester.pumpAndSettle();
      expect(find.text('Строка 0'), findsOneWidget);
      return host;
    }

    bool isOpen(GlobalKey<_HostState> host) => host.currentState!.open;

    testWidgets('от верха письма дальше порога — закрывает', (tester) async {
      final host = await pumpOpen(tester);
      await tester.dragFrom(tester.getCenter(find.text('Строка 3')), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(isOpen(host), isFalse);
    });

    testWidgets('за шапку письма — закрывает', (tester) async {
      final host = await pumpOpen(tester);
      await tester.dragFrom(tester.getCenter(find.text('Письмо')), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(isOpen(host), isFalse);
    });

    testWidgets('немного — письмо возвращается на место, лента снова закрыта', (tester) async {
      final host = await pumpOpen(tester);
      final before = tester.getTopLeft(find.text('Строка 0'));
      final gesture = await tester.startGesture(tester.getCenter(find.text('Строка 3')));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Пока палец на экране — страница сдвинута, лента под ней видна.
      expect(tester.getTopLeft(find.text('Строка 0')).dy, greaterThan(before.dy));
      expect(find.text('Лента'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(isOpen(host), isTrue);
      expect(tester.getTopLeft(find.text('Строка 0')), before);
      expect(find.text('Лента'), findsNothing);
    });

    testWidgets('прокрученное письмо — свайп вниз только прокручивает', (tester) async {
      final host = await pumpOpen(tester);
      await tester.dragFrom(tester.getCenter(find.text('Строка 10')), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Строка 0')).dy, lessThan(0));
      await tester.dragFrom(tester.getCenter(find.text('Строка 15')), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(isOpen(host), isTrue);
    });

    testWidgets('свайп вбок — не закрывает', (tester) async {
      final host = await pumpOpen(tester);
      await tester.dragFrom(tester.getCenter(find.text('Строка 3')), const Offset(300, 20));
      await tester.pumpAndSettle();
      expect(isOpen(host), isTrue);
    });

    testWidgets('планшет — не закрывает', (tester) async {
      final host = await pumpOpen(tester, size: const Size(1194, 834));
      await tester.dragFrom(tester.getCenter(find.text('Строка 3')), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(isOpen(host), isTrue);
    });

    testWidgets('пока страница идёт за пальцем, окно письма закрыто (MailDragCover)', (tester) async {
      await pumpOpen(tester);
      final ctx = tester.element(find.text('Строка 0'));
      final cover = MailDragCover.of(ctx)!;
      expect(cover.value, isFalse);
      final gesture = await tester.startGesture(tester.getCenter(find.text('Строка 3')));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(cover.value, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(cover.value, isFalse);
    });
  });

  test('ярлыки Hero одинаковы у строки и шапки письма', () {
    expect(MailHeroTags.avatar('a1', 'INBOX:1'), 'avatar_a1/INBOX:1');
    expect(MailHeroTags.subject('a1', 'INBOX:1'), 'subject_a1/INBOX:1');
    expect(kDebugMode, isTrue);
  });

  test('шапка из ленты достаётся только своему письму и один раз', () {
    final m = _mail('m1');
    MailOpenHandoff.put(m);
    expect(MailOpenHandoff.take('a1', 'other'), isNull);
    MailOpenHandoff.put(m);
    expect(MailOpenHandoff.take('a1', 'm1'), same(m));
    expect(MailOpenHandoff.take('a1', 'm1'), isNull);
  });
}

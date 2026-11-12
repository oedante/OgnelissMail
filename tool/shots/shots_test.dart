// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
// tool/shots/shots_test.dart
// Снимки экранов в разных темах и языках — чтобы видеть вид без телефона
// (1.8.0: «воздушный» вид, длинные переводы, письмо справа налево).
//   flutter test tool/shots --update-goldens   → tool/shots/out/*.png
// Обычный `flutter test` (папка test/) эти снимки не запускает.

import 'dart:async';

import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/core/theme/appearance.dart';
import 'package:ogneliss/core/theme/tokens.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/archive/screens/archive_screen.dart';
import 'package:ogneliss/features/auth/screens/login_screen.dart';
import 'package:ogneliss/features/settings/screens/general_settings_screen.dart';
import 'package:ogneliss/features/settings/screens/appearance_screen.dart';
import 'package:ogneliss/features/compose/screens/compose_screen.dart';
import 'package:ogneliss/features/mail/screens/mail_detail_screen.dart';
import 'package:ogneliss/features/mail/screens/mail_list_screen.dart';
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/features/mail/widgets/mail_drawer.dart';
import 'package:ogneliss/features/settings/screens/settings_screen.dart';
import 'package:ogneliss/features/my_day/my_day_screen.dart';
import 'package:ogneliss/features/calendar/screens/calendar_screen.dart';
import 'package:ogneliss/features/tasks/screens/tasks_screen.dart';
import 'package:ogneliss/features/contacts/screens/contacts_screen.dart';
import 'package:ogneliss/features/notes/screens/notes_screen.dart';
import 'package:ogneliss/features/assignments/assignments_screen.dart';
import 'package:ogneliss/features/assignments/assignment_screen.dart';
import 'package:ogneliss/services/assignments/assignment_codec.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:ogneliss/features/my_day/weather_view.dart' show showWeatherSheet;
import 'package:ogneliss/services/weather/weather_service.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/archive/archive_container.dart';
import 'package:ogneliss/services/archive/archive_db.dart';
import 'package:ogneliss/services/archive/archive_vault.dart';
import 'package:ogneliss/services/background/work_scheduler.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';
import 'package:ogneliss/widgets/common/ui_zoom.dart';
import 'package:ogneliss/widgets/navigation/app_bottom_bar.dart';
import 'package:ogneliss/widgets/ui/action_sheet.dart';
import 'package:ogneliss/widgets/ui/app_menu_button.dart';
import 'package:ogneliss/widgets/ui/confirm_dialog.dart';
import 'package:ogneliss/widgets/ui/section_band.dart';
import 'package:ogneliss/widgets/ui/settings_group.dart';
import 'package:ogneliss/widgets/ui/wheel_pickers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Темы снимков: светлая, тёмная, AMOLED, высокий контраст.
final _themes = <String, ThemeData Function()>{
  'light': () => AppTheme.lightTheme(1.0),
  'dark': () => AppTheme.darkTheme(1.0),
  'amoled': () => AppTheme.amoledTheme(1.0),
  'contrast': () => AppTheme.lightTheme(1.0, highContrast: true),
};

/// Телефон 393 × 852 (Pixel 8 / iPhone 15), снимок вдвое плотнее.
const _phone = Size(393, 852);

Future<AppDatabase> _db() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'a1',
        type: 7,
        email: 'i.petrov@corp.example',
        displayName: 'Иван Петров',
        username: 'i.petrov',
        createdAt: DateTime(2026),
      ));
  await db.into(db.folders).insert(FoldersCompanion.insert(
        id: 'inbox',
        accountId: 'a1',
        displayName: 'Входящие',
        type: Value(FolderType.inbox.index),
      ));
  return db;
}

/// Письмо для снимков экрана письма и ответа.
Future<void> _letter(AppDatabase db) => db.into(db.emails).insert(EmailsCompanion.insert(
      id: 'e1',
      accountId: 'a1',
      folderId: 'inbox',
      fromEmail: 'anna.smirnova@corp.example',
      fromName: const Value('Анна Смирнова'),
      toRecipients: '[{"email":"i.petrov@corp.example","displayName":"Иван Петров"}]',
      ccJson: const Value('[{"email":"o.kuznetsov@corp.example","displayName":"Олег Кузнецов"}]'),
      subject: 'Смета по ремонту насосной станции',
      bodyPlain: const Value('Иван, добрый день!\n\nНаправляю смету по ремонту насосной станции № 3. '
          'Прошу согласовать до пятницы.\n\nС уважением,\nАнна Смирнова\nОтдел эксплуатации'),
      bodyPreview: const Value('Иван, добрый день! Направляю смету по ремонту насосной станции № 3.'),
      receivedAt: DateTime(2026, 10, 27, 9, 41),
      isRead: const Value(true),
    ));

/// Ещё письма во «Входящих» — для снимка ленты рядом с письмом.
Future<void> _inbox(AppDatabase db) async {
  final now = DateTime.now();
  final rows = [
    ('m1', 'Борис Орлов', 'b.orlov', 'Re: Договор поставки № 15', 'Иван Петрович, направляю исправленную редакцию договора.', 1, false, false),
    ('m2', 'Вера Белова', 'v.belova', 'Совещание в четверг', 'Переносим на 11:00, переговорная 4.', 3, true, true),
    ('m3', 'Сервис-деск', 'helpdesk', 'Заявка № 4821 выполнена', 'Ваша заявка на замену картриджа выполнена.', 26, true, false),
    ('m4', 'Олег Кузнецов', 'o.kuznetsov', 'График отпусков на 2027 год', 'Коллеги, прошу до пятницы внести даты отпусков.', 50, true, false),
  ];
  for (final (id, name, mail, subject, preview, hours, read, flagged) in rows) {
    await db.into(db.emails).insert(EmailsCompanion.insert(
          id: id,
          accountId: 'a1',
          folderId: 'inbox',
          fromEmail: '$mail@corp.example',
          fromName: Value(name),
          toRecipients: '[{"email":"i.petrov@corp.example","displayName":"Иван Петров"}]',
          subject: subject,
          bodyPreview: Value(preview),
          receivedAt: now.subtract(Duration(hours: hours)),
          isRead: Value(read),
          isFlagged: Value(flagged),
        ));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(
  WidgetTester tester,
  String name,
  Widget home, {
  required ThemeData theme,
  String lang = 'ru',
  Size size = _phone,
  AppDatabase? db,
  SharedPreferences? prefs,
  Future<void> Function(WidgetTester tester)? before,
  List<Override> extra = const [],
  // Системный шрифт и масштаб интерфейса, как в приложении (main.dart:
  // UiZoom.auto по ширине и шрифту, UiZoomBox) — 1.8.12, проверка экранов
  // на разных размерах. null — без них (прежние снимки).
  double? textScale,
  double dpr = 2,
  // Сгиб складного экрана в логических точках (снимки флипов и фолдов).
  Rect? fold,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  if (fold != null) {
    tester.view.displayFeatures = [
      ui.DisplayFeature(
        bounds: fold, // FlutterView.displayFeatures — в логических точках
        type: ui.DisplayFeatureType.fold,
        state: ui.DisplayFeatureState.postureHalfOpened,
      ),
    ];
  }
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (db != null) databaseProvider.overrideWithValue(db),
      if (prefs != null) sharedPrefsProvider.overrideWithValue(prefs),
      ...extra,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
      builder: textScale == null
          ? null
          : (context, child) {
              final mq = MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale));
              final zoom = UiZoom.auto(mq.size, textScale.clamp(0.8, 1.6));
              UiZoom.current = zoom;
              return MediaQuery(
                data: mq,
                child: UiZoomBox(
                  zoom: zoom,
                  child: MediaQuery(
                      data: UiZoom.scaleData(mq, zoom).copyWith(
                          textScaler: TextScaler.linear(textScale).clamp(maxScaleFactor: 1.6)),
                      child: child!),
                ),
              );
            },
    ),
  ));
  await _settle(tester);
  if (before != null) {
    await before(tester);
    await _settle(tester);
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  await tester.pumpWidget(const SizedBox());
  // Пауза фоновой работы на время открытия письма считается по настоящим
  // часам, а таймеры в тесте — поддельные: снять её сразу.
  WorkScheduler.instance.releaseHold();
  // Отложенные таймеры экранов (автосохранение, подсказки) — до конца.
  await tester.pump(const Duration(minutes: 1));
}

/// Образцы: подписи разделов, группа настроек, кружки с буквой, нижняя панель.
class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          SettingsSectionTitle(l10n.tr('sectionMail'), help: l10n.tr('greetingSettingDesc')),
          SettingsGroup(children: [
            SettingsItem(icon: AppIcons.mail, title: l10n.tr('emailSettings'), subtitle: l10n.tr('emailSettingsDesc'), onTap: () {}),
            SettingsItem(icon: AppIcons.swipe, title: l10n.tr('swipeSettings'), subtitle: l10n.tr('swipeHint'), onTap: () {}),
            SettingsSwitchItem(icon: AppIcons.draw, title: l10n.tr('autoSignature'), value: true, onChanged: (_) {}),
          ]),
          SettingsSectionTitle(l10n.tr('security')),
          SettingsGroup(children: [
            SettingsItem(icon: AppIcons.lock, title: l10n.tr('pinLock'), subtitle: l10n.tr('pinLockDesc'), onTap: () {}),
          ]),
          const SizedBox(height: 12),
          SectionBand(title: l10n.tr('folders')),
          SectionBand.light(title: l10n.tr('today'), count: 3),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 12, children: [
              for (final (i, n) in const ['Анна Смирнова', 'Борис Орлов', 'Вера Белова', 'Глеб Сафин'].indexed)
                HeroEmailAvatar(
                  emailId: 'a$i',
                  hero: false,
                  initial: n.substring(0, 1),
                  color: HeroEmailAvatar.colorForEmail('$n@corp.example'),
                ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomBar(
        selectedIndex: 0,
        onSelected: (_) {},
        destinations: [
          NavigationDestination(icon: const Icon(AppIcons.mail), label: l10n.mail),
          NavigationDestination(icon: const Icon(AppIcons.calendar_today), label: l10n.tr('calendar')),
          NavigationDestination(icon: const Icon(AppIcons.contacts), label: l10n.tr('contacts')),
          NavigationDestination(icon: const Icon(AppIcons.account_circle), label: l10n.tr('barMenu')),
        ],
        center: PanelAction(icon: AppIcons.edit, label: l10n.tr('compose'), onPressed: () {}),
      ),
    );
  }
}

/// Лента писем: подписи дат и строки (прочитанные, непрочитанные, с флажком).
class _MailRows extends StatelessWidget {
  const _MailRows();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    EmailModel m(String id, String name, String subject, String preview,
            {int hours = 1, bool read = true, bool flagged = false, bool att = false}) =>
        EmailModel(
          id: id,
          accountId: 'a1',
          folderId: 'inbox',
          from: EmailAddress(email: '$id@corp.example', displayName: name),
          to: const [EmailAddress(email: 'i.petrov@corp.example', displayName: 'Иван Петров')],
          subject: subject,
          bodyPreview: preview,
          receivedAt: now.subtract(Duration(hours: hours)),
          isRead: read,
          isFlagged: flagged,
          hasAttachments: att,
        );
    final rows = [
      m('m1', 'Анна Смирнова', 'График отпусков на 2027 год', 'Добрый день, коллеги! Прошу до пятницы внести даты…', read: false),
      m('m2', 'Борис Орлов', 'Re: Договор поставки № 15', 'Иван Петрович, направляю исправленную редакцию договора.', att: true),
      m('m3', 'Вера Белова', 'Совещание в четверг', 'Переносим на 11:00, переговорная 4.', flagged: true, hours: 26),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('inbox'))),
      body: ListView(children: [
        SectionBand.light(title: l10n.tr('today')),
        EmailListTile(email: rows[0], onTap: () {}),
        EmailListTile(email: rows[1], onTap: () {}),
        SectionBand.light(title: l10n.tr('yesterday')),
        EmailListTile(email: rows[2], onTap: () {}),
      ]),
    );
  }
}

/// Меню кнопки «⋮» (1.8.6) — в стиле карточки по удержанию: значки,
/// выбранный пункт с галочкой, черта между группами, «опасный» пункт.
class _MenuDemo extends StatelessWidget {
  const _MenuDemo();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('inbox')), actions: [
        AppMenuButton<String>(
          initialValue: 'all',
          onSelected: (_) {},
          itemBuilder: (_) => [
            AppMenuEntry(value: 'sort', icon: AppIcons.sort, label: l10n.tr('sortBy')),
            AppMenuEntry(value: 'all', icon: AppIcons.select_all, label: l10n.tr('selectAll')),
            AppMenuEntry(value: 'read', icon: AppIcons.done_all, label: l10n.tr('markAllRead')),
            const AppMenuEntry.divider(),
            AppMenuEntry(value: 'sync', icon: AppIcons.sync, label: l10n.tr('sync')),
            AppMenuEntry(value: 'empty', icon: AppIcons.delete_sweep, label: l10n.tr('emptyTrash'), destructive: true),
          ],
        ),
      ]),
      body: const _MailRows(),
    );
  }
}

/// Подтверждение необратимого действия (confirmDestructive) — фон диалога
/// как у карточек и меню (1.8.6).
class _ConfirmDemo extends StatelessWidget {
  const _ConfirmDemo();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('inbox'))),
      body: Center(
        child: FilledButton(
          onPressed: () => confirmDestructive(context, title: l10n.tr('emptyTrashTitle'), message: l10n.tr('emptyTrashBody')),
          child: Text(l10n.tr('emptyTrash')),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  for (final t in _themes.entries) {
    testWidgets('образцы — ${t.key}', (tester) async {
      await _shot(tester, 'components_${t.key}', const _Components(), theme: t.value());
    });
  }

  for (final lang in const ['de', 'ar', 'ja']) {
    testWidgets('образцы — light $lang', (tester) async {
      await _shot(tester, 'components_light_$lang', const _Components(), theme: AppTheme.lightTheme(1.0), lang: lang);
    });
  }

  for (final t in _themes.entries) {
    testWidgets('лента — ${t.key}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'mail_${t.key}', const _MailRows(), theme: t.value(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
  }

  for (final t in const ['light', 'dark']) {
    testWidgets('меню «⋮» — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'menu_$t', const _MenuDemo(), theme: _themes[t]!(), db: db, prefs: prefs,
          before: (tester) => tester.tap(find.byType(AppMenuButton<String>)));
      await tester.runAsync(db.close);
    });
  }

  for (final t in const ['light', 'dark']) {
    testWidgets('подтверждение — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'confirm_$t', const _ConfirmDemo(), theme: _themes[t]!(), db: db, prefs: prefs,
          before: (tester) => tester.tap(find.byType(FilledButton)));
      await tester.runAsync(db.close);
    });
  }

  // Письмо и ответ на него (28.10.2026: «перепроверь просмотр и создание
  // письма»). На Linux тело — без WebView: шапка, полосы и кнопки — как на
  // телефоне.
  for (final t in const ['light', 'dark']) {
    testWidgets('письмо — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await _shot(tester, 'letter_$t', const MailDetailScreen(emailId: 'e1', accountId: 'a1'),
          theme: _themes[t]!(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
    // «Ещё» в письме (1.8.8) — карточка, как по удержанию письма в ленте.
    testWidgets('письмо, ещё — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await _shot(tester, 'letter_more_$t', const MailDetailScreen(emailId: 'e1', accountId: 'a1'),
          theme: _themes[t]!(), db: db, prefs: prefs, before: (tester) async {
        await tester.tap(find.bySemanticsLabel('Ещё').last);
      });
      await tester.runAsync(db.close);
    });
    testWidgets('новое письмо — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'compose_$t', const ComposeScreen(accountId: 'a1'), theme: _themes[t]!(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
    testWidgets('ответ — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await _shot(tester, 'reply_$t', const ComposeScreen(accountId: 'a1', replyToId: 'e1', replyAll: true),
          theme: _themes[t]!(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
  }

  // «Мой день»: перелистывающиеся часы и погода (1.15.1).
  WeatherForecast fakeWeather() {
    final now = DateTime.now();
    return WeatherForecast(
      now: WeatherPoint(at: now, temp: 3.4, kind: WeatherKind.partlyCloudy),
      min: -1,
      max: 5,
      fetchedAt: now.subtract(const Duration(minutes: 4)),
      hours: [
        for (var i = 1; i <= 8; i++)
          WeatherPoint(
            at: DateTime(now.year, now.month, now.day, now.hour + i),
            temp: 3.4 + i * (i.isEven ? 0.6 : -0.4),
            kind: const [WeatherKind.cloudy, WeatherKind.lightRain, WeatherKind.rain, WeatherKind.partlyCloudy][i % 4],
          ),
      ],
    );
  }
  for (final t in const ['light', 'dark']) {
    testWidgets('мой день с погодой — $t', (tester) async {
      SharedPreferences.setMockInitialValues({
        's_active_account': 'a1',
        'weather_on': true,
        'weather_place_v1': '{"name":"Казань","region":"Республика Татарстан, Россия","lat":55.8,"lon":49.11}',
      });
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      final extra = [
        weatherApprovedProvider.overrideWithValue(true),
        weatherProvider.overrideWith((ref) async => fakeWeather()),
      ];
      await _shot(tester, 'my_day_weather_$t', const MyDayScreen(), theme: _themes[t]!(), db: db, prefs: prefs, extra: extra);
      await _shot(tester, 'weather_sheet_$t', const MyDayScreen(),
          theme: _themes[t]!(), db: db, prefs: prefs, extra: extra, before: (tt) async {
        unawaited(showWeatherSheet(tt.element(find.byType(MyDayScreen))));
      });
      await tester.runAsync(db.close);
    });
  }

  // Поручения (2.2.0): список и карточка.
  testWidgets('поручения', (tester) async {
    SharedPreferences.setMockInitialValues({'s_active_account': 'a1'});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(() async {
      final db = await _db();
      final now = DateTime.now();
      final d0 = DateTime(now.year, now.month, now.day);
      Future<void> a(String id, String title, String who, String name, DateTime? due, int status,
              {bool mine = true}) =>
          AssignmentStore.insert(db,
              id: id,
              accountId: 'a1',
              title: title,
              ownerEmail: mine ? 'i.petrov@corp.example' : who,
              ownerName: mine ? 'Иван Петров' : name,
              assigneeEmail: mine ? who : 'i.petrov@corp.example',
              assigneeName: mine ? name : 'Иван Петров',
              due: due,
              at: now.subtract(const Duration(days: 1)),
              outgoing: mine).then((_) => AssignmentStore.update(db, id, status: status));
      await a('AAAAAAAAAAAA', 'Согласовать договор поставки № 15', 'b.orlov@corp.example', 'Борис Орлов',
          d0.subtract(const Duration(days: 1)), AssignmentStatus.inProgress);
      await a('BBBBBBBBBBBB', 'Отчёт отдела за октябрь', 'v.belova@corp.example', 'Вера Белова', d0, AssignmentStatus.review);
      await a('CCCCCCCCCCCC', 'Собрать даты отпусков отдела', 'v.belova@corp.example', 'Вера Белова',
          d0.add(const Duration(days: 2)), AssignmentStatus.inProgress);
      await a('DDDDDDDDDDDD', 'Обновить договор аренды', 'e.sokolova@corp.example', 'Елена Соколова',
          d0.add(const Duration(days: 4)), AssignmentStatus.open);
      await a('EEEEEEEEEEEE', 'Инвентаризация склада', 'd.kuznetsov@corp.example', 'Дмитрий Кузнецов', null,
          AssignmentStatus.open);
      await a('FFFFFFFFFFFF', 'Подготовить справку для аудита', 'a.smirnova@corp.example', 'Анна Смирнова',
          d0.add(const Duration(days: 1)), AssignmentStatus.open, mine: false);
      await AssignmentStore.addEvent(db,
          id: 'm1', assignmentId: 'CCCCCCCCCCCC', type: 'message', author: 'v.belova@corp.example',
          at: now.subtract(const Duration(hours: 20)), outgoing: false,
          payload: {'text': 'Принято, сделаю к среде', 'status': AssignmentStatus.inProgress});
      return db;
    }))!;
    await _shot(tester, 'assignments_list', const AssignmentsScreen(), theme: _themes['light']!(), db: db, prefs: prefs);
    await _shot(tester, 'assignment_card', const AssignmentScreen(id: 'CCCCCCCCCCCC'),
        theme: _themes['light']!(), db: db, prefs: prefs);
    await tester.runAsync(db.close);
  });

  // «Мой день» доской и шкалой (решения владельца 09.11.2026): встречи,
  // задачи со временем и без, просроченная, письмо «Позже».
  for (final view in const ['board', 'timeline']) {
    testWidgets('мой день — $view', (tester) async {
      SharedPreferences.setMockInitialValues({'s_active_account': 'a1', 'myday_view': view});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(() async {
        final db = await _db();
        final now = DateTime.now();
        final d0 = DateTime(now.year, now.month, now.day);
        Future<void> ev(String id, String title, int h, int m, int len, int color) =>
            db.into(db.calendarEvents).insert(CalendarEventsCompanion.insert(
                  id: id,
                  accountId: 'a1',
                  title: title,
                  startTime: d0.add(Duration(hours: h, minutes: m)),
                  endTime: d0.add(Duration(hours: h, minutes: m + len)),
                  createdAt: now,
                  colorValue: Value(color),
                ));
        await ev('e1', 'Планёрка отдела', 10, 0, 90, 0xFF4A78B0);
        await ev('e2', 'Звонок поставщику', 10, 30, 30, 0xFF5B8C5A);
        await ev('e3', 'Созвон с ООО «Ромашка»', 13, 0, 60, 0xFF7E5E9E);
        await ev('e4', 'Обзор проекта «Склад»', 16, 0, 60, 0xFFB0703F);
        Future<void> task(String id, String title, DateTime? due) => db.into(db.tasks).insert(TasksCompanion.insert(
              id: id, accountId: 'a1', title: title, createdAt: now, dueDate: Value(due)));
        await task('t1', 'Отчёт за октябрь', d0);
        await task('t2', 'Ответить Борису по договору', d0);
        await task('t3', 'Подготовить презентацию', d0.add(const Duration(hours: 14, minutes: 30)));
        await task('t4', 'Узнать у коллеги про акт', d0.subtract(const Duration(days: 1)));
        return db;
      }))!;
      await _shot(tester, 'my_day_$view', const MyDayScreen(), theme: _themes['light']!(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
  }

  // Лента и письмо рядом на компьютере и планшете (1.10.5, по образцу
  // Outlook): панель папок, лента, письмо с панелью команд.
  for (final (name, size) in const [('desktop', Size(1440, 900)), ('tablet', Size(1194, 834))]) {
    testWidgets('лента и письмо — $name', (tester) async {
      SharedPreferences.setMockInitialValues({'s_active_account': 'a1'});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await tester.runAsync(() => _inbox(db));
      await _shot(tester, 'split_$name', const MailListScreen(),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, before: (t) async {
        await t.tap(find.text('Смета по ремонту насосной станции').first);
        if (name == 'desktop') {
          // Мышь над строкой — быстрые кнопки, как в Outlook.
          final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(t.getCenter(find.text('Совещание в четверг')));
        }
      });
      await tester.runAsync(db.close);
    });
  }

  // Складные (07.11.2026, пункт 10 владельца): Galaxy Z Fold — внешний
  // экран (узкий и высокий) и внутренний (почти квадрат, сгиб посередине, в
  // крупном и обычном масштабе), Pixel Fold — внутренний «альбомный»,
  // Z Flip — раскрыт (обычный высокий телефон) и полураскрыт «ноутбуком».
  for (final (name, size, fold) in const [
    ('fold_cover', Size(344, 882), null),
    ('fold_inner', Size(884, 1104), Rect.fromLTRB(442, 0, 442, 1104)),
    ('fold_inner_large', Size(673, 841), Rect.fromLTRB(336, 0, 336, 841)),
    ('pixel_fold', Size(841, 701), Rect.fromLTRB(420, 0, 420, 701)),
    ('flip_open', Size(412, 1006), null),
    ('flip_half', Size(412, 1006), Rect.fromLTRB(0, 503, 412, 503)),
  ]) {
    testWidgets('складные — $name', (tester) async {
      SharedPreferences.setMockInitialValues({'s_active_account': 'a1'});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await tester.runAsync(() => _inbox(db));
      await _shot(tester, '${name}_inbox', const MailListScreen(),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, fold: fold, textScale: 1.0, before: (t) async {
        if (size.width >= 600) await t.tap(find.text('Смета по ремонту насосной станции').first);
      });
      await _shot(tester, '${name}_letter', const MailDetailScreen(emailId: 'e1', accountId: 'a1'),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, fold: fold, textScale: 1.0);
      await _shot(tester, '${name}_reply', const ComposeScreen(accountId: 'a1', replyToId: 'e1', replyAll: true),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, fold: fold, textScale: 1.0);
      await tester.runAsync(db.close);
    });
  }

  // Ответ — прямо в панели письма рядом с лентой (1.11.0, как в Outlook).
  // Обзор интерфейса (12.11.2026, план 2026-11: «оценка UI всех экранов —
  // телефон, планшет, компьютер»): разделы приложения на трёх размерах.
  // Запуск: flutter test tool/shots --plain-name обзор --update-goldens
  for (final (size, dims) in const [('phone', _phone), ('tablet', Size(1194, 834)), ('desktop', Size(1440, 900))]) {
    for (final (name, screen) in <(String, Widget)>[
      ('inbox', const MailListScreen()),
      ('calendar', const CalendarScreen()),
      ('tasks', const TasksScreen()),
      ('contacts', const ContactsScreen()),
      ('notes', const NotesScreen()),
      ('settings', const SettingsScreen()),
      ('myday', const MyDayScreen()),
      ('assignments', const AssignmentsScreen()),
    ]) {
      testWidgets('обзор — $name $size', (tester) async {
        SharedPreferences.setMockInitialValues({'reading_pane_asked_v1': true});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await tester.runAsync(() async {
          await _letter(db);
          await _inbox(db);
        });
        await _shot(tester, 'review_${name}_$size', screen,
            theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: dims, textScale: 1.0);
        await tester.runAsync(db.close);
      });
    }
  }

  testWidgets('лента и ответ в панели — desktop', (tester) async {
    SharedPreferences.setMockInitialValues({'s_active_account': 'a1'});
    final prefs = await SharedPreferences.getInstance();
    final db = (await tester.runAsync(_db))!;
    await tester.runAsync(() => _letter(db));
    await tester.runAsync(() => _inbox(db));
    await _shot(tester, 'split_reply_desktop', const MailListScreen(),
        theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: const Size(1440, 900), before: (t) async {
      await t.tap(find.text('Смета по ремонту насосной станции').first);
      await _settle(t);
      await t.tap(find.text('Ответить').first);
    });
    await tester.runAsync(db.close);
  });

  // Письмо и ответ на планшете, компьютере и телефоне боком (1.8.13):
  // текст письма — одной колонкой с шапкой, строка ответа и кнопки — не
  // через весь экран.
  for (final (name, size) in const [('tablet', Size(1194, 834)), ('desktop', Size(1280, 800)), ('phoneland', Size(852, 393))]) {
    testWidgets('письмо — $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await _shot(tester, 'letter_$name', const MailDetailScreen(emailId: 'e1', accountId: 'a1'),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size);
      await tester.runAsync(db.close);
    });
    testWidgets('ответ — $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() => _letter(db));
      await _shot(tester, 'reply_$name', const ComposeScreen(accountId: 'a1', replyToId: 'e1', replyAll: true),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size);
      await tester.runAsync(db.close);
    });
  }

  // Архив Ogneliss (28.10.2026): кнопки на виду, ящики в архиве (один — с
  // другого устройства), «Другие устройства и облако».
  for (final (t, scroll) in const [('light', 0.0), ('light', 1100.0), ('light', 2400.0), ('dark', 0.0)]) {
    testWidgets('архив — $t $scroll', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      final adb = ArchiveDb(NativeDatabase.memory());
      await tester.runAsync(() async {
        await adb.upsertAccount('a1', 'i.petrov@corp.example', 'Иван Петров', 'exchange', 0);
        await adb.upsertAccount('d2', 'i.petrov@home.example', '', 'imap', 0);
        for (final (acc, n) in [('a1', 3), ('d2', 1)]) {
          for (var i = 0; i < n; i++) {
            await adb.addMessage(ArchiveMessageInput(
              accountId: acc,
              folderChain: const [(name: 'Входящие', type: 'inbox')],
              sourceId: '$acc$i',
              subject: 'Отчёт $i',
              fromName: 'Анна',
              fromEmail: 'anna@corp.example',
              date: DateTime(2025, 3, 1 + i),
              searchText: 'Отчёт',
            ));
          }
        }
      });
      await _shot(tester, 'archive_${t}_${scroll.round()}', const ArchiveScreen(),
          theme: _themes[t]!(), db: db, prefs: prefs, extra: [
        archiveVaultProvider.overrideWith(() => _ShotVault(adb)),
      ], before: scroll == 0
          ? null
          : (tester) async {
              // Ниже — расписание, ящики, «Другие устройства и облако».
              await tester.drag(find.byType(ListView), Offset(0, -scroll));
            });
      await tester.runAsync(adb.close);
      await tester.runAsync(db.close);
    });
  }

  // Вход (1.8.8): плитки способов входа; шаг 2 с переключателем
  // «Exchange | IMAP»; «Общие» со шрифтом Medeo Sans.
  for (final t in const ['light', 'dark']) {
    testWidgets('вход — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      await _shot(tester, 'login_$t', const LoginScreen(), theme: _themes[t]!(), db: db, prefs: prefs);
      await _shot(tester, 'login_exchange_$t', const LoginScreen(), theme: _themes[t]!(), db: db, prefs: prefs,
          before: (tester) async {
        await tester.enterText(find.byType(TextField).first, 'oedante@ogneliss.ru');
        await tester.ensureVisible(find.text('Exchange'));
        await tester.tap(find.text('Exchange'));
      });
      await tester.runAsync(db.close);
    });
  }

  // Шторки действий и выбор значения (1.8.8) — карточкой, как меню «⋮».
  for (final t in const ['light', 'dark']) {
    testWidgets('карточка действий — $t', (tester) async {
      await _shot(tester, 'action_card_$t', const _CardHost(choice: false), theme: _themes[t]!(),
          before: (tester) async => tester.tap(find.text('open')));
    });
    testWidgets('карточка выбора — $t', (tester) async {
      await _shot(tester, 'choice_card_$t', const _CardHost(choice: true), theme: _themes[t]!(),
          before: (tester) async => tester.tap(find.text('open')));
    });
  }

  // Телефоны разной ширины и плотности, обычный и крупный шрифт — с
  // масштабом интерфейса, как в приложении (1.8.12).
  for (final (dev, size, dpr) in const [
    ('320', Size(320, 568), 2.0),
    ('360', Size(360, 780), 3.0),
    ('412', Size(412, 915), 2.625),
  ]) {
    for (final ts in const [1.0, 1.3, 1.6]) {
      final tag = '${dev}_x${(ts * 10).round()}';
      testWidgets('размеры — лента $tag', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await _shot(tester, 'size_mail_$tag', const _MailRows(), theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs,
            size: size, dpr: dpr, textScale: ts);
        await tester.runAsync(db.close);
      });
      testWidgets('размеры — письмо $tag', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await tester.runAsync(() => _letter(db));
        await _shot(tester, 'size_letter_$tag', const MailDetailScreen(emailId: 'e1', accountId: 'a1'),
            theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, dpr: dpr, textScale: ts);
        await tester.runAsync(db.close);
      });
      testWidgets('размеры — новое письмо $tag', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await _shot(tester, 'size_compose_$tag', const ComposeScreen(accountId: 'a1'),
            theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, dpr: dpr, textScale: ts);
        await tester.runAsync(db.close);
      });
      testWidgets('размеры — настройки $tag', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await _shot(tester, 'size_settings_$tag', const SettingsScreen(), theme: AppTheme.lightTheme(1.0), db: db,
            prefs: prefs, size: size, dpr: dpr, textScale: ts);
        await tester.runAsync(db.close);
      });
      testWidgets('размеры — барабаны $tag', (tester) async {
        await _shot(tester, 'size_wheels_$tag', const _WheelHost(), theme: AppTheme.lightTheme(1.0),
            size: size, dpr: dpr, textScale: ts, before: (tester) async => tester.tap(find.text('open')));
      });
    }
  }

  // Меню с семью ящиками на узком экране (1.8.12, замечание 31.10.2026:
  // при пяти и больше ящиках выбор ящиков уходил за край панели).
  for (final (tag, size, ts) in const [('360', Size(360, 780), 1.0), ('320_x13', Size(320, 568), 1.3)]) {
    testWidgets('меню, семь ящиков — $tag', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await tester.runAsync(() async {
        for (var i = 2; i <= 7; i++) {
          await db.into(db.accounts).insert(AccountsCompanion.insert(
                id: 'a$i',
                type: 7,
                email: 'user$i@corp$i.example',
                displayName: 'Ящик $i',
                username: 'user$i',
                createdAt: DateTime(2026),
              ));
        }
      });
      await _shot(tester, 'drawer_7_$tag', const Scaffold(body: MailDrawer()), theme: AppTheme.lightTheme(1.0),
          db: db, prefs: prefs, size: size, textScale: ts);
      await tester.runAsync(db.close);
    });
  }

  // Барабаны даты и времени (1.8.12): одна полоса выбора, изгиб, затухание.
  for (final t in const ['light', 'dark']) {
    testWidgets('барабаны — $t', (tester) async {
      await _shot(tester, 'wheels_$t', const _WheelHost(), theme: _themes[t]!(),
          before: (tester) async => tester.tap(find.text('open')));
    });
  }

  // «Оформление» (1.9.x, просьба владельца 31.10.2026): экран целиком
  // (светлая и тёмная, узкий экран с крупным шрифтом), цветовые темы,
  // плотность ленты.
  for (final (t, scroll) in const [('light', 0.0), ('light', 1000.0), ('dark', 0.0), ('dark', 1000.0)]) {
    testWidgets('оформление — $t $scroll', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'appearance_${t}_${scroll.round()}', const AppearanceScreen(),
          theme: _themes[t]!(), db: db, prefs: prefs, before: scroll == 0
              ? null
              : (tester) async => tester.drag(find.byType(ListView).first, Offset(0, -scroll)));
      await tester.runAsync(db.close);
    });
  }
  for (final (dev, size, dpr, ts) in const [('320_x13', Size(320, 568), 2.0, 1.3), ('412', Size(412, 915), 2.625, 1.0)]) {
    testWidgets('оформление — размер $dev', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'appearance_size_$dev', const AppearanceScreen(),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, dpr: dpr, textScale: ts);
      await _shot(tester, 'appearance_size_${dev}_lower', const AppearanceScreen(),
          theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs, size: size, dpr: dpr, textScale: ts,
          before: (tester) async => tester.drag(find.byType(ListView).first, const Offset(0, -700)));
      await tester.runAsync(db.close);
    });
  }
  for (final (name, prefsMap, dark) in const [
    ('forest_light', {'s_theme_preset': 'forest'}, false),
    ('sunset_tint_light', {'s_theme_preset': 'sunset', 's_list_tint': 2}, false),
    ('sky_large_dark', {'s_theme_preset': 'sky', 's_corners': 2}, true),
    ('midnight_dark', {'s_theme_preset': 'midnight'}, true),
    ('accent_custom_light', {'s_theme_preset': 'classic', 's_accent': 0xFFC2185B, 's_corners': 0}, false),
  ]) {
    testWidgets('цветовая тема — $name', (tester) async {
      SharedPreferences.setMockInitialValues(prefsMap);
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      final a = SettingsNotifier(prefs).state.appearance();
      Radii.scale = a.radiusScale;
      addTearDown(() => Radii.scale = 1.0);
      final theme = !dark
          ? AppTheme.lightTheme(1.0, appearance: a)
          : (PresetSpec.of(a.preset).blackDark
              ? AppTheme.amoledTheme(1.0, appearance: a)
              : AppTheme.darkTheme(1.0, appearance: a));
      await _shot(tester, 'preset_${name}_appearance', const AppearanceScreen(), theme: theme, db: db, prefs: prefs);
      await _shot(tester, 'preset_${name}_mail', const _MailRows(), theme: theme, db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
  }
  for (final d in ListDensity.values) {
    for (final (dev, size, dpr, ts) in const [
      ('320_x13', Size(320, 568), 2.0, 1.3),
      ('360', Size(360, 780), 3.0, 1.0),
      ('412', Size(412, 915), 2.625, 1.0),
    ]) {
      testWidgets('плотность ${d.name} — $dev', (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final db = (await tester.runAsync(_db))!;
        await _shot(tester, 'density_${d.name}_$dev', const _MailRows(),
            theme: AppTheme.lightTheme(1.0, appearance: Appearance(density: d)),
            db: db, prefs: prefs, size: size, dpr: dpr, textScale: ts);
        await tester.runAsync(db.close);
      });
    }
  }

  for (final font in const ['roboto', 'medeo']) {
    testWidgets('общие — шрифт $font', (tester) async {
      SharedPreferences.setMockInitialValues({'s_ui_font': font});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      AppTheme.fontFamily = AppTheme.familyFor(font);
      addTearDown(() => AppTheme.fontFamily = AppTheme.robotoFamily);
      await _shot(tester, 'general_$font', const GeneralSettingsScreen(), theme: AppTheme.lightTheme(1.0), db: db, prefs: prefs,
          before: (tester) async {
        await tester.drag(find.byType(ListView), const Offset(0, -500));
      });
      await tester.runAsync(db.close);
    });
  }

  for (final t in const ['light', 'dark', 'contrast']) {
    testWidgets('настройки — $t', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = (await tester.runAsync(_db))!;
      await _shot(tester, 'settings_$t', const SettingsScreen(), theme: _themes[t]!(), db: db, prefs: prefs);
      await tester.runAsync(db.close);
    });
  }
}

/// Открытый архив для снимка: база в памяти, без ключей и файлов.
class _ShotVault extends ArchiveVault {
  _ShotVault(this._fake);
  final ArchiveDb _fake;

  @override
  ArchiveDb? get db => _fake;

  @override
  Future<ArchiveVaultState> build() async => ArchiveVaultState(
        ArchiveStatus.open,
        header: ArchiveHeader(id: 'shot', name: '', created: DateTime(2026, 10, 1), app: '1.8.7', keys: const {}),
      );
}

/// Экран для снимков карточек действий и выбора: кнопка «open».
class _CardHost extends StatelessWidget {
  final bool choice;
  const _CardHost({required this.choice});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ogneliss Mail')),
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => choice
                  ? showChoiceSheet<int>(
                      context,
                      title: 'Сортировка',
                      selected: 1,
                      entries: const [
                        AppMenuEntry(value: 0, label: 'Сначала новые'),
                        AppMenuEntry(value: 1, label: 'Сначала старые'),
                        AppMenuEntry(value: 2, label: 'По отправителю'),
                        AppMenuEntry(value: 3, label: 'По теме'),
                      ],
                    )
                  : showActionSheet<int>(
                      context,
                      title: 'Анна Смирнова',
                      subtitle: 'anna.smirnova@corp.example',
                      leading: const CircleAvatar(child: Text('А')),
                      items: const [
                        ActionSheetItem(icon: AppIcons.person, label: 'В «Кому»', value: 0),
                        ActionSheetItem(icon: AppIcons.group, label: 'В «Копию»', value: 1),
                        ActionSheetItem(icon: AppIcons.content_copy, label: 'Скопировать адрес', value: 2),
                        ActionSheetItem(icon: AppIcons.close, label: 'Убрать', value: 3, destructive: true),
                      ],
                      footer: const Padding(
                        padding: EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
                        child: Text('Адрес можно перетащить в другое поле'),
                      ),
                    ),
              child: const Text('open'),
            ),
          ),
        ),
      );
}

class _WheelHost extends StatelessWidget {
  const _WheelHost();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Создать встречу')),
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showWheelDateTimePicker(context, initial: DateTime(2026, 10, 30, 21, 30)),
              child: const Text('open'),
            ),
          ),
        ),
      );
}

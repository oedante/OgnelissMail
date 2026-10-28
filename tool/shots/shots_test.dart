// ignore_for_file: invalid_use_of_visible_for_testing_member
// tool/shots/shots_test.dart
// Снимки экранов в разных темах и языках — чтобы видеть вид без телефона
// (1.8.0: «воздушный» вид, длинные переводы, письмо справа налево).
//   flutter test tool/shots --update-goldens   → tool/shots/out/*.png
// Обычный `flutter test` (папка test/) эти снимки не запускает.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/core/theme/app_theme.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/features/settings/screens/settings_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/hero_email_transition.dart';
import 'package:ogneliss/widgets/navigation/app_bottom_bar.dart';
import 'package:ogneliss/widgets/ui/app_menu_button.dart';
import 'package:ogneliss/widgets/ui/confirm_dialog.dart';
import 'package:ogneliss/widgets/ui/section_band.dart';
import 'package:ogneliss/widgets/ui/settings_group.dart';
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
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (db != null) databaseProvider.overrideWithValue(db),
      if (prefs != null) sharedPrefsProvider.overrideWithValue(prefs),
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
    ),
  ));
  await _settle(tester);
  if (before != null) {
    await before(tester);
    await _settle(tester);
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
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

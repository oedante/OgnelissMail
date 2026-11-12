// Карточка поручения: связь «родитель — подзадача» (план 2026-11, п. 10).

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:ogneliss/features/assignments/assignment_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AssignmentView _v(String id, String title, {String? parent, int status = AssignmentStatus.open}) {
  final at = DateTime(2026, 11, 1);
  return AssignmentView(
    row: Assignment(
      id: id,
      accountId: 'a1',
      title: title,
      kind: 0,
      status: status,
      priority: 1,
      ownerEmail: 'boss@corp.example',
      parentAssignmentId: parent,
      isTemplate: false,
      autoDecideEnabled: true,
      createdAt: at,
      updatedAt: at,
      isArchived: false,
    ),
    assignee: AssignmentParticipant(
        assignmentId: id, email: 'vera@corp.example', displayName: 'Вера Белова', role: AssignmentRole.responsible, inviteStatus: 0),
    owner: AssignmentParticipant(
        assignmentId: id, email: 'boss@corp.example', displayName: 'Олег', role: AssignmentRole.owner, inviteStatus: 0),
    outgoing: true,
  );
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('ru');
  });

  Future<void> open(WidgetTester t) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = (await t.runAsync(() async => AppDatabase.forTesting(NativeDatabase.memory())))!;
  }

  // Убрать экран (потоки базы, фото людей) и закрыть базу — как в
  // my_day_screen_test.dart.
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    await t.runAsync(db.close);
  }

  Widget app(String id, List<AssignmentView> all) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          assignmentsProvider.overrideWith((ref) => Stream.value(all)),
          assignmentEventsProvider.overrideWith((ref, id) => Stream.value(const <AssignmentEvent>[])),
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
          home: AssignmentScreen(id: id),
        ),
      );

  // Поток поручений и фото из базы — настоящим временем; без pumpAndSettle
  // (на экране могут быть бесконечные анимации).
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 20 && find.text('История').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  final all = [
    _v('P', 'График отпусков'),
    _v('S1', 'Собрать даты', parent: 'P'),
    _v('S2', 'Сверить с кадрами', parent: 'P', status: AssignmentStatus.done),
    _v('X', 'Другое поручение'),
  ];

  testWidgets('родитель: список подзадач со счётом выполненных и «Добавить»', (t) async {
    await open(t);
    await t.pumpWidget(app('P', all));
    await settle(t);
    expect(find.text('Подзадачи · 1/2'), findsOneWidget);
    expect(find.text('Собрать даты'), findsOneWidget);
    expect(find.text('Сверить с кадрами'), findsOneWidget);
    expect(find.text('Другое поручение'), findsNothing);
    expect(find.byKey(const ValueKey('assign_add_subtask')), findsOneWidget);
    expect(find.text('Входит в'), findsNothing);
    await close(t);
  });

  testWidgets('подзадача: строка «Входит в» с названием родителя', (t) async {
    await open(t);
    await t.pumpWidget(app('S1', all));
    await settle(t);
    expect(find.text('Входит в'), findsOneWidget);
    expect(find.text('График отпусков'), findsOneWidget);
    // У подзадачи своих подзадач нет — только заголовок и «Добавить».
    expect(find.text('Подзадачи'), findsOneWidget);
    await close(t);
  });

  testWidgets('закрытое поручение без подзадач — раздела нет', (t) async {
    await open(t);
    await t.pumpWidget(app('S2', all));
    await settle(t);
    expect(find.text('Подзадачи'), findsNothing);
    expect(find.byKey(const ValueKey('assign_add_subtask')), findsNothing);
    await close(t);
  });
}

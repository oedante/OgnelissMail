// Проект с этапами (12.11.2026): карточка проекта — прогресс, этапы по
// плану, диаграмма Ганта; нажатие на этап на диаграмме.

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
import 'package:ogneliss/features/assignments/gantt_chart.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AssignmentView _v(String id, String title,
    {String? parent,
    int status = AssignmentStatus.open,
    bool project = false,
    String? after,
    int order = 0,
    DateTime? start,
    DateTime? due,
    String? checklist}) {
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
      isProject: project,
      startAt: start,
      dueAt: due,
      afterId: after,
      stageOrder: order,
      checklistJson: checklist,
      waiting: after != null && status != AssignmentStatus.done,
    ),
    assignee: project
        ? null
        : AssignmentParticipant(
            assignmentId: id, email: 'vera@corp.example', displayName: 'Вера', role: AssignmentRole.responsible, inviteStatus: 0),
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

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
    await t.runAsync(db.close);
  }

  Widget wrap(Widget home, List<AssignmentView> all) => ProviderScope(
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
          home: home,
        ),
      );

  Future<void> settle(WidgetTester t, String text) async {
    for (var i = 0; i < 20 && find.text(text).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  // Сроки — в будущем: без баннера опоздания.
  final all = [
    _v('P', 'Годовой отчёт', project: true, start: DateTime(2030, 3, 4), due: DateTime(2030, 3, 15)),
    _v('S1', 'Сбор данных', parent: 'P', status: AssignmentStatus.done, start: DateTime(2030, 3, 4), due: DateTime(2030, 3, 6)),
    _v('S2', 'Анализ', parent: 'P', status: AssignmentStatus.inProgress, after: 'S1', order: 1,
        start: DateTime(2030, 3, 7), due: DateTime(2030, 3, 11), checklist: '[{"t":"Продажи","d":true},{"t":"Склад"}]'),
    _v('S3', 'Слайды', parent: 'P', order: 2, start: DateTime(2030, 3, 4), due: DateTime(2030, 3, 15)),
  ];

  testWidgets('проект: прогресс, этапы по порядку, «после этапа», план — диаграмма', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1200));
    await open(t);
    await t.pumpWidget(wrap(const AssignmentScreen(id: 'P'), all));
    await settle(t, 'Годовой отчёт');
    expect(find.text('Годовой отчёт'), findsOneWidget);
    expect(find.textContaining('Этапы: 1 из 3'), findsOneWidget);
    expect(find.text('Сбор данных'), findsOneWidget);
    expect(find.text('Анализ'), findsOneWidget);
    expect(find.textContaining('После этапа 1'), findsOneWidget);
    expect(find.textContaining('☑ 1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('proj_card_add_stage')), findsOneWidget);
    expect(find.byKey(const ValueKey('proj_shift')), findsNothing);

    await t.tap(find.text('План'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(GanttChart), findsOneWidget);
    expect(find.text('2. Анализ'), findsOneWidget);
    await close(t);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('диаграмма: нажатие на название этапа', (t) async {
    await open(t);
    String? tapped;
    await t.pumpWidget(wrap(
        Scaffold(
          body: GanttChart(
            stages: [
              PlanStage(id: 'a', title: 'Сбор', start: DateTime(2030, 3, 4), due: DateTime(2030, 3, 6), status: 4, progress: 1),
              PlanStage(id: 'b', title: 'Анализ', start: DateTime(2030, 3, 7), due: DateTime(2030, 3, 11), after: 'a', status: 2),
            ],
            today: DateTime(2030, 3, 8),
            onTap: (id) => tapped = id,
          ),
        ),
        const []));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('2. Анализ'));
    expect(tapped, 'b');
    await close(t);
  });
}

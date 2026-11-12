// Сводка, «Результат» и ответы с файлами (12.11.2026).

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
import 'package:ogneliss/features/assignments/assignments_summary_screen.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/assignments/assignment_service.dart';
import 'package:ogneliss/services/assignments/assignment_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AssignmentView _v(String id, String title,
    {int status = AssignmentStatus.open, DateTime? due, DateTime? created, DateTime? updated, bool outgoing = true,
    String who = 'vera@corp.example', String name = 'Вера', String? files}) {
  final at = created ?? DateTime.now().subtract(const Duration(days: 3));
  return AssignmentView(
    row: Assignment(
      id: id,
      accountId: 'a1',
      title: title,
      kind: 0,
      status: status,
      priority: 1,
      ownerEmail: 'boss@corp.example',
      isTemplate: false,
      autoDecideEnabled: true,
      createdAt: at,
      updatedAt: updated ?? at,
      isArchived: false,
      isProject: false,
      dueAt: due,
      stageOrder: 0,
      waiting: false,
      filesJson: files,
    ),
    assignee: AssignmentParticipant(
        assignmentId: id, email: who, displayName: name, role: AssignmentRole.responsible, inviteStatus: 0),
    owner: AssignmentParticipant(
        assignmentId: id, email: 'boss@corp.example', displayName: 'Олег', role: AssignmentRole.owner, inviteStatus: 0),
    outgoing: outgoing,
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

  Widget wrap(Widget home, List<AssignmentView> all, {List<AssignmentEvent> events = const []}) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sharedPrefsProvider.overrideWithValue(prefs),
          assignmentsProvider.overrideWith((ref) => Stream.value(all)),
          assignmentEventsProvider.overrideWith((ref, id) => Stream.value(events)),
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
    for (var i = 0; i < 20 && find.textContaining(text).evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('сводка: показатели, статусы, исполнители, недели', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2000));
    await open(t);
    final all = [
      _v('A', 'Договор', status: AssignmentStatus.inProgress, due: today.subtract(const Duration(days: 2))),
      _v('B', 'Отчёт', status: AssignmentStatus.review, due: today.add(const Duration(days: 3))),
      _v('C', 'Справка', status: AssignmentStatus.done, due: today, updated: now, who: 'dmitry@corp.example', name: 'Дмитрий'),
      _v('D', 'Чужое', outgoing: false),
    ];
    await t.pumpWidget(wrap(const AssignmentsSummaryScreen(), all));
    await settle(t, 'Сводка');
    expect(find.text('Сводка'), findsOneWidget);
    // «Я поручил»: A, B, C; просрочено — A; в срок — C.
    Finder tile(String prefix) =>
        find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith(prefix));
    expect(tile('Действующие: 2'), findsOneWidget);
    expect(tile('Просрочено: 1'), findsOneWidget);
    expect(tile('В срок: 100%'), findsOneWidget);
    expect(find.text('Исполнители'), findsOneWidget);
    expect(find.text('Вера'), findsOneWidget);
    expect(find.text('Дмитрий'), findsOneWidget);
    expect(find.text('По неделям'), findsOneWidget);
    // «Мне поручили» — только D, человек — поручивший.
    await t.tap(find.text('Мне поручили'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Постановщики'), findsOneWidget);
    expect(find.text('Олег'), findsOneWidget);
    await close(t);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('карточка: «Результат» — текст и файлы ответа «Готово»', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 2000));
    await open(t);
    final v = _v('R', 'Отчёт за квартал',
        status: AssignmentStatus.review, files: '[{"n":"report.pdf","s":2048,"m":"mail1","a":"1"}]');
    final ev = AssignmentEvent(
      id: 'e1',
      assignmentId: 'R',
      type: 'message',
      authorEmail: 'vera@corp.example',
      direction: 1,
      createdAt: now.subtract(const Duration(hours: 1)),
      payloadJson: '{"text":"Готово\\nОтчёт приложен, цифры сверены","status":3,"files":["report.pdf"]}',
      deliveryStatus: 0,
      signatureState: 0,
    );
    await t.pumpWidget(wrap(const AssignmentScreen(id: 'R'), [v], events: [ev]));
    await settle(t, 'Результат');
    expect(find.text('Результат'), findsOneWidget);
    expect(find.text('Отчёт приложен, цифры сверены'), findsOneWidget);
    // В «Результате» и в общих файлах поручения.
    expect(find.text('report.pdf'), findsNWidgets(2));
    await close(t);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('«Вернуть на доработку» — только с причиной', (t) async {
    await open(t);
    final v = _v('W', 'Отчёт за квартал', status: AssignmentStatus.review);
    await t.pumpWidget(wrap(const AssignmentScreen(id: 'W'), [v]));
    await settle(t, 'Отчёт за квартал');
    await t.tap(find.byKey(const ValueKey('assign_return')));
    await t.pump(const Duration(milliseconds: 300));
    final send = find.byKey(const ValueKey('assign_reply_send'));
    expect(t.widget<FilledButton>(send).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('assign_reply_text')), 'Добавьте итоги по складу');
    await t.pump();
    expect(t.widget<FilledButton>(send).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('assign_reply_files')), findsOneWidget);
    await close(t);
  });
}

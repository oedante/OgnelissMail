// integration_test/perf_test.dart
// Замеры скорости на эмуляторе Android (1.9.x, просьба владельца 31.10.2026):
//  · открытие письма — от «нажатия» (OpenTrace.start и переход на экран
//    письма) до показа текста (MailHtmlView.onShown), с этапами OpenTrace
//    (окно, создано, загрузка, текст): первое в процессе — движок браузера
//    ещё не загружен; повторное (медиана трёх); с запасным окном
//    (MailWebViewPool — как при нажатии строки ленты, медиана трёх);
//  · «Новое сообщение» — от перехода до готового редактора
//    (MailEditor.onReady): первое (файлы редактора читаются и хэшируются),
//    повторное и с запасным окном (MailEditorPool), медианы трёх;
//  · запуск приложения без аккаунтов — от main() до первого кадра заставки
//    и до первого экрана после неё (лицензия, знакомство или вход; заставка
//    держится не меньше 1,8 с);
//  · прокрутка ленты во время синхронизации (2.6.8, план «Ж», просьба
//    владельца 22.11.2026): каждые 300 мс в базу приходит пачка писем и
//    меняются отметки прочитанного, лента перестраивается; считаются кадры,
//    не уложившиеся в 16 мс сборки (missed_frame_build_budget_count), и
//    худший кадр. Работа «синхронизации» — под метками производительности
//    (PerfMark): в Timeline их видно рядом с кадрами.
// Строки OGN_PERF (support/harness.dart) собирает tool/perf/perf_check.py,
// сравнение с tool/perf/baseline.json — в CI (задача «emulator»).
// Сборка отладочная (flutter test на устройстве — только она): числа
// больше, чем у выпуска, и годятся для сравнения между сборками, а не как
// время на телефоне.
//
// Отдельно: flutter test integration_test/perf_test.dart -d <эмулятор>

import 'dart:async';
import 'dart:io' show File;
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/logging/open_trace.dart';
import 'package:ogneliss/core/logging/perf_mark.dart';
import 'package:ogneliss/core/security/mail_body_processor.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/data/providers/shared_prefs_provider.dart';
import 'package:ogneliss/features/compose/widgets/mail_editor.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart' show emailModelFromRow;
import 'package:ogneliss/features/mail/widgets/email_list_tile.dart';
import 'package:ogneliss/features/mail/widgets/mail_html_view.dart';
import 'package:ogneliss/main.dart' as app;
import 'package:ogneliss/services/background/work_scheduler.dart';
import 'package:ogneliss/splash_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/harness.dart';

void main() {
  ensureBinding();
  perfTests();
  appStartTests();
}

const _runs = 3;

/// Обычное письмо средней длины; [n] делает документ каждого открытия
/// новым — иначе экран письма взял бы высоту из памяти прошлого открытия.
String _letter(int n) =>
    '''
<p>Добрый день!</p>
<p>Письмо №$n. Высылаю итоги совещания. Основные решения — ниже, подробности —
во вложении. Если что-то упустил, напишите, пожалуйста, до конца недели.</p>
<ol><li>Сроки проекта переносятся на две недели.</li><li>Отчёт готовит отдел аналитики.</li>
<li>Следующая встреча — в четверг в 11:00.</li></ol>
<table border="1" cellpadding="4"><tr><td>Задача</td><td>Ответственный</td><td>Срок</td></tr>
<tr><td>Отчёт</td><td>Аналитика</td><td>12.11</td></tr><tr><td>Макет</td><td>Дизайн</td><td>15.11</td></tr></table>
<p>Спасибо всем за участие!</p>
<blockquote><p>Коллеги, напоминаю о встрече в 15:00.</p></blockquote>
<p>С уважением,<br>Отдел проектов</p>
''';

/// Экран письма для замера: ширина окна задана тестом (как
/// MailHtmlView.bodyWidthOf у телефона) — документ запасного окна совпадает
/// с документом экрана.
class _MailPage extends StatelessWidget {
  const _MailPage({required this.doc, required this.width, required this.textScale, required this.onShown});

  final MailHtmlDocument doc;
  final double width;
  final double textScale;
  final VoidCallback onShown;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Письмо')),
    body: SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: MailHtmlView(
            document: doc,
            allowRemoteImages: false,
            textScale: textScale,
            pageColor: Colors.white,
            onShown: onShown,
            onLink: (_, __) {},
          ),
        ),
      ),
    ),
  );
}

/// «Новое сообщение» для замера: редактор во всю ширину.
class _ComposePage extends StatelessWidget {
  const _ComposePage({required this.controller, required this.usePool, required this.onReady, required this.onFailed});

  final MailEditorController controller;
  final bool usePool;
  final VoidCallback onReady;
  final VoidCallback onFailed;

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(title: const Text('Новое сообщение')),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MailEditor(controller: controller, usePool: usePool, height: 420, onReady: onReady, onFailed: onFailed),
      ],
    ),
  );
}

/// Лента-заглушка: с неё открываются экраны, как в приложении.
Future<GlobalKey<NavigatorState>> _home(WidgetTester tester) async {
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    testApp(
      navigatorKey: nav,
      home: const Scaffold(body: Center(child: Text('Лента'))),
    ),
  );
  await pumpUntil(tester, () => nav.currentState != null, what: 'лента показана');
  return nav;
}

/// Открыть письмо и дождаться текста: (мс от нажатия, этапы OpenTrace).
Future<({int ms, Map<String, int> marks})> _openMail(
  WidgetTester tester,
  GlobalKey<NavigatorState> nav,
  MailHtmlDocument doc, {
  required double width,
  required double textScale,
  bool spare = false,
}) async {
  if (spare) {
    // Запасное окно создаётся в простое после показа ленты — не в замере.
    MailWebViewPool.enabled = true;
    await waitFor(
      tester,
      MailWebViewPool.ensureSpare(width: width, textScale: textScale),
      what: 'запасное окно письма создано',
    );
  } else {
    MailWebViewPool.enabled = false;
  }
  return withAppFrames(() async {
    final shown = Completer<int>();
    final sw = Stopwatch();
    OpenTrace.start();
    sw.start();
    // Экран письма придерживает фоновую работу на время открытия
    // (mail_detail_screen → hold): иначе следующее запасное окно
    // создавалось бы прямо во время замера.
    WorkScheduler.instance.hold();
    if (spare) {
      // Нажатие строки ленты: письмо — в запасное окно (mail_open_cache).
      final fit = MailHtmlView.initialFit(doc, width);
      unawaited(
        MailWebViewPool.preload(
          MailHtmlView.composeHtml(
            doc,
            viewWidth: width,
            fitWidth: fit,
            dark: false,
            pageColor: Colors.white,
            textScale: textScale,
          ),
          textScale: textScale,
          heightScale: fit == null ? 1.0 : width / fit,
          width: width,
        ),
      );
    }
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => _MailPage(
            doc: doc,
            width: width,
            textScale: textScale,
            onShown: () {
              if (!shown.isCompleted) shown.complete(sw.elapsedMilliseconds);
            },
          ),
        ),
      ),
    );
    final ms = await waitFor(tester, shown.future, what: 'письмо показано', timeout: const Duration(seconds: 40));
    final marks = Map<String, int>.of(OpenTrace.lastMarks);
    if (spare) {
      expect(
        marks.containsKey('заранее'),
        isTrue,
        reason: 'окно письма не взято из запасного: ${MailWebViewPool.lastMiss}',
      );
    }
    nav.currentState!.pop();
    await pumpUntil(tester, () => find.byType(MailHtmlView).evaluate().isEmpty, what: 'экран письма закрыт');
    return (ms: ms, marks: marks);
  });
}

/// Открыть «Новое сообщение» и дождаться готового редактора: мс от нажатия.
Future<int> _openCompose(WidgetTester tester, GlobalKey<NavigatorState> nav, {required bool usePool}) {
  return withAppFrames(() async {
    final ready = Completer<int>();
    final failed = Completer<void>();
    final controller = MailEditorController();
    final sw = Stopwatch()..start();
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => _ComposePage(
            controller: controller,
            usePool: usePool,
            onReady: () {
              if (!ready.isCompleted) ready.complete(sw.elapsedMilliseconds);
            },
            onFailed: () {
              if (!failed.isCompleted) failed.complete();
            },
          ),
        ),
      ),
    );
    await waitFor(
      tester,
      Future.any([ready.future, failed.future]),
      what: 'редактор готов',
      timeout: const Duration(seconds: 40),
    );
    expect(failed.isCompleted, isFalse, reason: 'редактор не загрузился (onFailed)');
    final ms = await ready.future;
    nav.currentState!.pop();
    await pumpUntil(tester, () => find.byType(MailEditor).evaluate().isEmpty, what: 'экран нового сообщения закрыт');
    return ms;
  });
}

/// Письмо для ленты: адрес без «@» — строка не просит фото у адресной книги
/// и значок организации из сети (замер — только лента и база).
EmailsCompanion _row(int n, DateTime at) => EmailsCompanion.insert(
  id: 'perf_$n',
  accountId: 'a1',
  folderId: 'inbox',
  folderName: const Value('Входящие'),
  fromEmail: 'sender-${n % 37}',
  fromName: Value('Отправитель ${n % 37}'),
  toRecipients: '[]',
  subject: 'Итоги совещания №$n: сроки, задачи и ответственные',
  bodyPreview: Value('Добрый день! Письмо №$n. Высылаю итоги совещания, основные решения — ниже.'),
  receivedAt: at,
  isRead: Value(n.isEven),
  hasAttachments: Value(n % 5 == 0),
  loadedLevel: const Value(1),
);

/// Лента писем папки прямо из базы, как в приложении: поток запроса →
/// модели строк → EmailListTile.
class _SyncFeed extends StatefulWidget {
  const _SyncFeed({required this.db});

  final AppDatabase db;

  @override
  State<_SyncFeed> createState() => _SyncFeedState();
}

class _SyncFeedState extends State<_SyncFeed> {
  late final Stream<List<EmailModel>> _mails;

  @override
  void initState() {
    super.initState();
    final db = widget.db;
    _mails = db
        .customSelect(
          "SELECT * FROM emails WHERE account_id = 'a1' AND folder_id = 'inbox' ORDER BY received_at DESC LIMIT 600",
          readsFrom: {db.emails},
        )
        .watch()
        .map(
          (rows) => PerfMark.sync('лента: письма из базы', () => [for (final r in rows) emailModelFromRow(db.emails.map(r.data))]),
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Входящие')),
    body: StreamBuilder<List<EmailModel>>(
      stream: _mails,
      builder: (context, snap) {
        final list = snap.data ?? const <EmailModel>[];
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, i) => EmailListTile(key: ValueKey(list[i].id), email: list[i], onTap: () {}),
        );
      },
    ),
  );
}

/// «Синхронизация» для замера: каждые 300 мс — пачка из 20 новых писем
/// (тексты разбираются в главном потоке, как превью при синхронизации) и
/// отметки прочитанного у 40 старых.
Timer _fakeSync(AppDatabase db, {required int from}) {
  var n = from;
  var busy = false;
  final html = _letter(0);
  return Timer.periodic(const Duration(milliseconds: 300), (_) async {
    if (busy) return;
    busy = true;
    try {
      final now = DateTime.now();
      final rows = PerfMark.sync('тест: разбор пачки писем', () {
        final out = <EmailsCompanion>[];
        for (var i = 0; i < 20; i++) {
          final preview = MailBodyProcessor.htmlToPlain(html);
          out.add(
            _row(++n, now.subtract(Duration(seconds: i))).copyWith(bodyPreview: Value(preview.length > 120 ? preview.substring(0, 120) : preview)),
          );
        }
        return out;
      });
      await db.batch((b) => b.insertAllOnConflictUpdate(db.emails, rows));
      await db.customUpdate(
        "UPDATE emails SET is_read = NOT is_read WHERE account_id = 'a1' AND id IN "
        "(SELECT id FROM emails WHERE account_id = 'a1' ORDER BY random() LIMIT 40)",
        updates: {db.emails},
      );
    } finally {
      busy = false;
    }
  });
}

/// Прокрутка ленты во время синхронизации: сводка кадров (FrameTimingSummarizer).
Future<Map<String, dynamic>> _scrollDuringSync(WidgetTester tester) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ogn_perf_scroll.sqlite');
  if (file.existsSync()) file.deleteSync();
  // Как в приложении: база в своём изоляте (createInBackground).
  final db = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final start = DateTime.now();
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
  await db.batch((b) {
    b.insertAll(db.emails, [for (var i = 0; i < 400; i++) _row(i, start.subtract(Duration(minutes: 7 * i)))]);
  });
  Timer? sync;
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db), sharedPrefsProvider.overrideWithValue(prefs)],
        child: testApp(home: _SyncFeed(db: db)),
      ),
    );
    await pumpUntil(tester, () => find.byType(EmailListTile).evaluate().length > 3, what: 'лента показана');
    return await withAppFrames(() async {
      // Кадры показа ленты отчитываются с задержкой — до замера.
      await tester.pump(const Duration(seconds: 2));
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      sync = _fakeSync(db, from: 1000);
      final list = find.byType(Scrollable).first;
      for (var i = 0; i < 8; i++) {
        await tester.fling(list, Offset(0, i.isEven ? -900 : 700), 3000);
        await tester.pump(const Duration(milliseconds: 1200));
      }
      sync?.cancel();
      // Отчёт о кадрах приходит пачками до раза в секунду.
      await tester.pump(const Duration(seconds: 2));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      expect(timings, isNotEmpty, reason: 'кадров прокрутки не было');
      final n = await db.customSelect("SELECT count(*) AS c FROM emails WHERE account_id = 'a1'").getSingle();
      expect(n.read<int>('c'), greaterThan(400), reason: 'синхронизация не записала писем');
      final summary = FrameTimingSummarizer(timings).summary;
      final slow = [for (final t in timings) if (t.totalSpan > const Duration(milliseconds: 34)) t].length;
      return {
        ...summary,
        'slow_frames_34ms': slow,
        'worst_total_ms': timings.map((t) => t.totalSpan.inMilliseconds).reduce((a, b) => a > b ? a : b),
      };
    });
  } finally {
    sync?.cancel();
    await tester.pumpWidget(const SizedBox());
    await db.close();
    if (file.existsSync()) file.deleteSync();
  }
}

void perfTests() {
  // Свои setUp/tearDown — только для этих тестов (в emulator_test.dart все
  // файлы идут одним набором).
  group('Скорость', () {
    setUpAll(() async {
      await loadStrings();
    });

    setUp(() {
      setUiZoom(1.0);
      MailHtmlView.fitWide = false;
    });

    tearDown(() async {
      MailWebViewPool.enabled = false;
      await MailWebViewPool.release();
    });

    testWidgets('скорость: открытие письма — первое, повторное, с запасным окном', (tester) async {
      PerfLog.device(tester);
      final nav = await _home(tester);
      final width = screenWidth(tester) - 32;
      final ts = mailTextScaleFor(1.0);
      var n = 0;
      MailHtmlDocument next() => MailHtmlDocument.build(_letter(++n), allowRemoteImages: false);

      final first = await _openMail(tester, nav, next(), width: width, textScale: ts);
      PerfLog.record('mail_open_first_ms', first.ms, extra: {'marks': first.marks});

      final warm = <({int ms, Map<String, int> marks})>[];
      for (var i = 0; i < _runs; i++) {
        warm.add(await _openMail(tester, nav, next(), width: width, textScale: ts));
      }
      PerfLog.record(
        'mail_open_ms',
        median([for (final r in warm) r.ms]),
        extra: {
          'runs': [for (final r in warm) r.ms],
          'marks': warm.last.marks,
        },
      );

      final spare = <({int ms, Map<String, int> marks})>[];
      for (var i = 0; i < _runs; i++) {
        spare.add(await _openMail(tester, nav, next(), width: width, textScale: ts, spare: true));
      }
      PerfLog.record(
        'mail_open_spare_ms',
        median([for (final r in spare) r.ms]),
        extra: {
          'runs': [for (final r in spare) r.ms],
          'marks': spare.last.marks,
        },
      );
    }, skip: !onAndroid);

    testWidgets('скорость: прокрутка ленты во время синхронизации', (tester) async {
      final s = await _scrollDuringSync(tester);
      final pick = {
        for (final k in [
          'frame_count',
          'missed_frame_build_budget_count',
          'slow_frames_34ms',
          'average_frame_build_time_millis',
          '90th_percentile_frame_build_time_millis',
          'worst_frame_build_time_millis',
          'worst_total_ms',
        ])
          k: s[k],
      };
      PerfLog.record('scroll_sync_missed_frames', s['missed_frame_build_budget_count'] as num, extra: {'frames': pick});
      PerfLog.record('scroll_sync_build_p90_ms', s['90th_percentile_frame_build_time_millis'] as num);
      PerfLog.record('scroll_sync_worst_frame_ms', s['worst_total_ms'] as num);
    });

    testWidgets('скорость: «Новое сообщение» — первое, повторное, с запасным окном', (tester) async {
      final nav = await _home(tester);

      PerfLog.record('compose_first_ms', await _openCompose(tester, nav, usePool: false));

      final warm = <int>[];
      for (var i = 0; i < _runs; i++) {
        warm.add(await _openCompose(tester, nav, usePool: false));
      }
      PerfLog.record('compose_ms', median(warm), extra: {'runs': warm});

      // Запасное окно: первое открытие с usePool запоминает ключ (язык, тема,
      // подсказка, масштаб) и размер окна — дальше окно готовится заранее,
      // как после закрытия «Нового сообщения» в приложении.
      await _openCompose(tester, nav, usePool: true);
      final spare = <int>[];
      for (var i = 0; i < _runs; i++) {
        MailEditorPool.editorOpen = false;
        await waitFor(tester, MailEditorPool.ensureSpare(), what: 'запасное окно редактора создано');
        await pumpUntil(
          tester,
          () => MailEditorPool.debugSpareReady,
          what: 'редактор в запасном окне запущен',
          timeout: const Duration(seconds: 40),
        );
        spare.add(await _openCompose(tester, nav, usePool: true));
        expect(MailEditorPool.debugSpareReady, isFalse, reason: 'запасное окно не забрано');
      }
      PerfLog.record('compose_spare_ms', median(spare), extra: {'runs': spare});
      await MailEditorPool.release();
    }, skip: !onAndroid);
  });
}

/// Запуск приложения. Последним: main() ставит свои обработчики ошибок и
/// службы (база, уведомления, фоновые задачи) на весь процесс.
void appStartTests() {
  testWidgets('скорость: запуск приложения — первый кадр и первый экран', (tester) async {
    final onError = FlutterError.onError;
    final platformOnError = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = platformOnError;
    });
    late int firstFrame, firstScreen;
    await withAppFrames(() async {
      final sw = Stopwatch()..start();
      unawaited(app.main());
      await pumpUntil(
        tester,
        () => find.byType(SplashScreen).evaluate().isNotEmpty,
        what: 'заставка',
        timeout: const Duration(seconds: 60),
        step: const Duration(milliseconds: 10),
      );
      await waitFor(tester, SchedulerBinding.instance.endOfFrame, what: 'кадр с заставкой');
      firstFrame = sw.elapsedMilliseconds;
      await pumpUntil(
        tester,
        () => find.byType(SplashScreen).evaluate().isEmpty,
        what: 'первый экран после заставки',
        timeout: const Duration(seconds: 60),
      );
      await waitFor(tester, SchedulerBinding.instance.endOfFrame, what: 'кадр первого экрана');
      firstScreen = sw.elapsedMilliseconds;
    });
    PerfLog.record('app_first_frame_ms', firstFrame);
    PerfLog.record('app_first_screen_ms', firstScreen);
  }, skip: !onAndroid);
}

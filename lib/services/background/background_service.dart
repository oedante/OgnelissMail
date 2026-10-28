// lib/services/background/background_service.dart
// Координатор фоновых операций:
// - Инициализация уведомлений, WorkManager
// - Периодическое обновление OAuth-токенов
// - Автоочистка кеша и аудит-лога
// - Автоблокировка при бездействии
// - Синхронизация контактов/календаря с устройством
// - Регистрация всех фоновых задач

import '../push/push_wake_service.dart' show pushWakeServiceProvider;
import '../calendar/quick_create_service.dart' show quickCreateProvider;
import '../sync/sync_schedule.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import '../sync/imap_push_service.dart';
import '../sync/stale_watchdog.dart';
import '../mail/own_addresses.dart';
import '../../core/utils/text_safe.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/sync/sync_service.dart';
import '../../services/notifications/reminder_scheduler_service.dart' show reminderSchedulerProvider;
import 'foreground_sync_controller.dart';
import 'background_journal.dart';
import '../../core/platform/platform_diagnostics.dart';
import '../../core/platform/finish_in_background.dart';
import '../../services/mail/oauth/oauth_service.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../core/device/device_user_agent.dart';
import '../../core/network/app_http_overrides.dart';
import '../../core/network/certificate_pinning_bridge.dart';
import '../../core/security/certificate_pinning_service.dart';
import '../../core/security/trusted_ca_store.dart';
import '../../core/security/account_ca_sync.dart';

/// Провайдер фоновых сервисов
final backgroundServiceProvider = Provider<BackgroundService>((ref) {
  return BackgroundService(ref);
});

/// Имена фоновых задач
class _TaskNames {
  static const periodicSync = 'periodic_sync';
  /// iOS (1.6.42): BGProcessingTask — дополнительные пробуждения сверх
  /// BGAppRefresh (тот же идентификатор в Info.plist и AppDelegate).
  static const processingSync = 'processing_sync';
}

/// iOS: какая фоновая задача сейчас работает (мс эпохи) — чтобы две задачи
/// (обновление и обработка), запущенные системой разом, не синхронизировали
/// одновременно.
const _iosTaskRunningKey = 'bg_ios_task_at';

/// Имя порта главного изолята (1.6.43): по нему фоновая задача находит
/// живое приложение в этом же процессе (IsolateNameServer — общий для всех
/// изолятов процесса, в том числе движка WorkManager/BGTask).
const _mainPortName = 'ogneliss_main_tasks_v1';

/// Прежняя отметка «приложение работает само» (до 1.6.43) — только убрать.
const _legacyAliveKey = 'bg_main_alive_at';

/// Лимит фоновой задачи: WorkManager обрывает работу через ~10 мин; iOS даёт
/// «Обновлению контента» ~30 с, «Обработке» — минуты.
Duration _taskLimit(String taskName) {
  if (kIsWeb || !Platform.isIOS) return const Duration(minutes: 9);
  return taskName == _TaskNames.processingSync ? const Duration(minutes: 3) : const Duration(seconds: 27);
}

String _taskKind(String taskName) {
  if (kIsWeb || !Platform.isIOS) return 'WorkManager';
  return taskName == _TaskNames.processingSync ? 'BGProcessing iOS' : 'BGTask iOS';
}

/// Сколько осталось от лимита с момента пробуждения (не меньше 5 с).
Duration _leftOf(Duration limit, DateTime wokeAt) {
  final left = limit - DateTime.now().difference(wokeAt);
  return left < const Duration(seconds: 5) ? const Duration(seconds: 5) : left;
}

/// Процесс приложения жив — проверку делает оно, а фоновая задача ждёт итог
/// (1.6.43). Пока задача не завершилась, система держит процесс бодрым и даёт
/// ему сеть; поэтому задача не уходит сразу, как раньше, а ждёт.
///
/// Журналы тестировщиков 18–19.10.2026, почему «засыпает»:
///  · Android без службы (OnePlus, Android 16): свёрнутому приложению система
///    закрывает сеть — таймер главного изолята каждые 5 минут получал
///    «Unable to resolve host» (57 раз, и только в фоне). WorkManager, у
///    которого сеть есть, видел свежую отметку «приложение работает само» и
///    завершался, ничего не проверив. Отметка оставалась «свежей» и через
///    секунду после того, как процесс закрыли смахиванием.
///  · iPhone: iOS будила приложение, задача видела отметку и выходила, iOS
///    тут же замораживала процесс — синхронизация главного изолята, начатая
///    при пробуждении, висела до следующего пробуждения.
///
/// Один движок ActiveSync (главного изолята) — без гонки SyncKey, ради
/// которой отметка и появилась. Порт не найден (приложение выгружено) или
/// приложение не ответило — проверка в самой фоновой задаче, как раньше.
Future<bool> _delegateToMain(String kind, DateTime wokeAt, Duration limit) async {
  SendPort? main;
  try {
    main = IsolateNameServer.lookupPortByName(_mainPortName);
  } catch (_) {}
  if (main == null) return false;
  final inbox = ReceivePort('ogneliss-bg-task');
  final ack = Completer<void>();
  final done = Completer<String>();
  final sub = inbox.listen((m) {
    if (m is! Map) return;
    if (m['ack'] == true && !ack.isCompleted) ack.complete();
    if (m['done'] == true && !done.isCompleted) done.complete('${m['what'] ?? 'ok'}');
  });
  try {
    final left = _leftOf(limit, wokeAt);
    main.send(<String, Object?>{'kind': kind, 'limitMs': left.inMilliseconds, 'reply': inbox.sendPort});
    try {
      // iOS: у «Обновления контента» каждая секунда на счету.
      await ack.future.timeout(Duration(seconds: Platform.isIOS ? 3 : 8));
    } on TimeoutException {
      // Порт остался от закрытого движка приложения (процесс жив, окна и
      // Dart приложения уже нет) — имя убираем, проверяет сама задача.
      AppLogger.warning('$kind: приложение не ответило — проверка в фоновой задаче');
      try {
        IsolateNameServer.removePortNameMapping(_mainPortName);
      } catch (_) {}
      return false;
    }
    await BackgroundJournal.track(kind, () async {
      try {
        return await done.future.timeout(left + const Duration(seconds: 5));
      } on TimeoutException {
        return 'время вышло — остальное в следующий раз';
      }
    },
        withState: false,
        describe: (what) =>
            'проверило приложение: $what (от пробуждения ${DateTime.now().difference(wokeAt).inSeconds} с)');
    return true;
  } catch (e) {
    AppLogger.warning('$kind: передача приложению — $e');
    // Приложение уже взялось за проверку — вторую не запускаем.
    return ack.isCompleted;
  } finally {
    await sub.cancel();
    inbox.close();
  }
}

/// Callback WorkManager (top-level, entry-point для фонового ИЗОЛЯТА).
///
/// Фоновый изолят НЕ видит globalContainer приложения — поднимаем собственный
/// ProviderContainer с prefs и БД. База — та же зашифрованная `ogneliss.db`;
/// конструктор `AppDatabase()` сам берёт ключ SQLCipher из secure storage и
/// работает на своём drift-изоляте. Несколько соединений SQLite к одному файлу
/// безопасны (блокировки, а не повреждение; транзакции атомарны), поэтому даже
/// при открытом приложении данные не рушатся — худшее это SQLITE_BUSY, которое
/// перехватывается и приводит к повтору задачи.
///
/// Всё обёрнуто в try/finally: при любой ошибке возвращаем false (WorkManager
/// повторит по своей политике), контейнер и БД закрываются.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Время пробуждения — для журнала («от пробуждения N с»).
    final wokeAt = DateTime.now();
    // Журнал в фоновом изоляте раньше не открывался: всё, что делала фоновая
    // задача, терялось, и в журнале не было видно, запускалась ли она вообще.
    WidgetsFlutterBinding.ensureInitialized();
    AppLogger.setTag('фон');
    await AppLogger.init();
    AppLogger.info('WorkManager: $taskName (фоновый изолят)');
    // Процесс приложения жив — проверку делает оно, задача ждёт итог (раньше
    // в этом случае задача уходила сразу: «пропуск: приложение работает
    // само», а приложение без сети или замороженное ничего не проверяло).
    if (await _delegateToMain(_taskKind(taskName), wokeAt, _taskLimit(taskName))) {
      // Задача обработки iOS разовая — заявка на следующую.
      if (taskName == _TaskNames.processingSync) await BackgroundService.submitIosProcessing();
      AppLogger.flushNow();
      return true;
    }
    if (!kIsWeb && Platform.isIOS) {
      return _runIosTask(taskName, wokeAt);
    }
    try {
      await BackgroundJournal.track('WorkManager', () => runInBackgroundContainer((container) async {
        // Лимит задачи WorkManager ~10 мин — держим синк заведомо короче.
        await container
            .read(syncServiceProvider)
            .syncAll(scheduled: true, respectInterval: true)
            .timeout(const Duration(minutes: 9));
        // Напоминания встреч, пришедших с этим синком, проверка «нет ответа»
        // и виджет — до закрытия контейнера (их запускает syncAll; раньше
        // напоминания выставлялись здесь второй раз).
        await container.read(syncServiceProvider).settle();
        // После перезагрузки телефона напоминания перевыставляет эта задача
        // (приёмника загрузки нет, 1.6.12): планировщик сам узнаёт
        // перезагрузку, в остальное время проход короткий.
        try {
          await container.read(reminderSchedulerProvider).rescheduleAll();
        } catch (e) {
          AppLogger.warning('BG напоминания: $e');
        }
        // Встречи и задачи из виджета, не созданные сразу (не было сети).
        try {
          await container.read(quickCreateProvider).drain();
        } catch (e) {
          AppLogger.warning('BG виджет: $e');
        }
      }), withState: false);
      return true;
    } catch (e, stack) {
      AppLogger.error('WorkManager: фоновый синк не удался', e, stack);
      return false;
    }
  });
}

/// Фоновая задача iOS (1.6.42). Обе проверяют ВСЁ (решение владельца
/// 19.10.2026: «надо проверять все»): сначала «Входящие» всех ящиков — самое
/// срочное, затем полная проверка всех ящиков (остальные папки, календарь,
/// контакты), напоминания и очередь виджета — сколько успеем.
///
///  · BGAppRefresh (`periodic_sync`): у iOS на всё ~30 с — лимит 27 с, как
///    и раньше; не успели — остальное в следующий раз.
///  · BGProcessing (`processing_sync`): минуты — лимит 3 мин; потом — заявка
///    на следующую.
///
/// С 1.6.43 — только когда приложения в процессе нет (iOS запустила процесс
/// ради задачи) или оно не ответило; иначе то же самое делает приложение
/// ([_delegateToMain]).
Future<bool> _runIosTask(String taskName, DateTime wokeAt) async {
  final long = taskName == _TaskNames.processingSync;
  final kind = long ? 'BGProcessing iOS' : 'BGTask iOS';
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final other = prefs.getInt(_iosTaskRunningKey);
    if (other != null) {
      final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(other));
      if (!age.isNegative && age < const Duration(minutes: 4)) {
        await BackgroundJournal.note(kind, 'пропуск: уже работает другая фоновая задача');
        if (long) await BackgroundService.submitIosProcessing();
        AppLogger.flushNow();
        return true;
      }
    }
    await prefs.setInt(_iosTaskRunningKey, DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
  // Лимит — от пробуждения: запуск движка задачи и попытка передать
  // проверку приложению уже заняли часть времени iOS.
  final limit = _leftOf(_taskLimit(taskName), wokeAt);
  try {
    await BackgroundJournal.track(kind, () async {
      try {
        await runInBackgroundContainer((container) async {
          final sync = container.read(syncServiceProvider);
          // 1. «Входящие» всех ящиков — первыми.
          await sync.quickInboxSync();
          // 2. Всё остальное по всем ящикам — без пропуска «ещё не пора»:
          //    iOS будит редко, каждое пробуждение — полная проверка.
          await sync.syncAll(scheduled: true, respectInterval: false);
          await sync.settle(timeout: const Duration(seconds: 20));
          try {
            await container.read(reminderSchedulerProvider).rescheduleAll();
          } catch (e) {
            AppLogger.warning('BG напоминания: $e');
          }
          try {
            await container.read(quickCreateProvider).drain();
          } catch (e) {
            AppLogger.warning('BG виджет: $e');
          }
        }).timeout(limit);
      } on TimeoutException {
        // Не ошибка: что не успели — в следующее пробуждение.
        AppLogger.info('$kind: время вышло — остальное в следующий раз');
      }
    }, withState: false, describe: (_) => 'от пробуждения ${DateTime.now().difference(wokeAt).inSeconds} с');
    return true;
  } catch (e) {
    AppLogger.warning('$kind: $e (от пробуждения ${DateTime.now().difference(wokeAt).inSeconds} с)');
    return false;
  } finally {
    try {
      await prefs?.remove(_iosTaskRunningKey);
    } catch (_) {}
    // Задача обработки разовая — заявка на следующую (обновление iOS
    // перевыставляет сама).
    if (long) await BackgroundService.submitIosProcessing();
    AppLogger.flushNow();
  }
}

/// Поднять в фоновом изоляте (WorkManager, кнопка уведомления при выгруженном
/// приложении) всё, что нужно движку: prefs, доверие сертификатам (ЦС Минцифры,
/// ЦС устройства, правила), режим совместимости со шлюзом, БД, уведомления,
/// аккаунты. Фоновый изолят НЕ видит globalContainer приложения.
Future<void> runInBackgroundContainer(
    Future<void> Function(ProviderContainer container) body) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init(); // идемпотентно; в фоновом изоляте открывает журнал
  AppDatabase? db;
  ProviderContainer? container;
  try {
    final prefs = await SharedPreferences.getInstance();
    // Как в main(): режим совместимости со шлюзом (иначе фоновая задача
    // ходила бы на Exchange через dart:io и получала 403 шлюза), правила
    // доверия сертификатам и дополнительные центры сертификации.
    await DeviceUserAgent.warmUp();
    CertificatePinningBridge.instance ??= CertificatePinningService(prefs);
    HttpOverrides.global = AppHttpOverrides();
    await TrustedCaStore.init(prefs);
    OwnAddresses.load(prefs);
    SyncSchedule.load(prefs);
    db = AppDatabase();
    container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ]);

    // Уведомления в изоляте — иначе о новой почте пользователь не узнает до
    // открытия приложения. При сбое работа продолжается.
    try {
      await container.read(notificationServiceProvider).initialize();
    } catch (e) {
      AppLogger.warning('BG notifications init: $e');
    }

    // Аккаунты грузятся из БД асинхронно — в свежем контейнере провайдер пуст.
    await container.read(accountsProvider.notifier).reload();
    // ЦС Минцифры, включённый для отдельных ящиков, — по адресам их серверов.
    syncCaAccounts(container.read(accountsProvider));
    await container.read(connectivityServiceProvider.notifier).refresh();

    await body(container);
  } finally {
    container?.dispose();
    await db?.close();
  }
}

class BackgroundService {
  final Ref _ref;
  Timer? _autoLockTimer;
  Timer? _tokenRefreshTimer;
  Timer? _cacheCleanupTimer;
  Timer? _foregroundSyncTimer;
  DateTime _lastActivity = DateTime.now();
  DateTime _lastForegroundSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initialized = false;
  bool _autoLockLogged = false;

  BackgroundService(this._ref);

  /// Инициализировать все фоновые сервисы
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      AppLogger.info('BackgroundService: инициализация');

      // 0. Порт для фоновых задач — до регистрации WorkManager: задача может
      // запуститься сразу после неё (журнал: WorkManager в ту же секунду,
      // что и запуск приложения).
      _listenBackgroundTasks();
      try {
        unawaited(_ref.read(sharedPrefsProvider).remove(_legacyAliveKey));
      } catch (_) {}

      // 1. Уведомления
      try {
        final notificationService = _ref.read(notificationServiceProvider);
        await notificationService.initialize();
      } catch (e) {
        AppLogger.warning('Notifications init: $e');
      }

      // 2. WorkManager (только мобильные)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        try {
          await Workmanager().initialize(callbackDispatcher);
          // Периодическая синхронизация — по тем же правилам, что и при смене
          // интервала (раньше при запуске не учитывался резервный опрос EWS
          // в режиме «только push», и до первой смены настройки фонового
          // опроса не было).
          await _registerPeriodic();
          AppLogger.info('WorkManager: зарегистрировано');
        } catch (e) {
          AppLogger.warning('WorkManager init: $e');
        }
      }

      // 2a. iPhone: сигналы сервера «проверь почту» (1.7.2).
      unawaited(_ref.read(pushWakeServiceProvider).init());

      // 3. Таймеры в foreground
      _startTokenRefreshTimer();
      _startCacheCleanupTimer();
      // Ежеминутный таймер «автоблокировки» убран (аудит 11.10.2026): он
      // только писал строку в журнал, а будил процесс каждую минуту и в
      // фоне. Блокировка — pinLockProvider.onForeground при возврате;
      // запись в журнал — в recordActivity.
      _startForegroundSyncTimer();

      // Пульс от будильника ОС (Android, при работающем фоновом сервисе).
      _ref.read(foregroundSyncControllerProvider).setHeartbeatHandler(onHeartbeat);

      // Устройство и ограничения фоновой работы — в журнал (и причины,
      // по которым система завершала процесс с прошлого запуска).
      unawaited(() async {
        try {
          final prefs = _ref.read(sharedPrefsProvider);
          final exits = await PlatformDiagnostics.logStartup(prefs);
          for (final e in exits) {
            await BackgroundJournal.note('процесс завершён',
                '${PlatformDiagnostics.exitReasonText('${e['reason']}')} [${e['reason']}]',
                at: DateTime.fromMillisecondsSinceEpoch(e['ts'] as int));
          }
          await BackgroundJournal.note('запуск', 'приложение запущено');
        } catch (e) {
          AppLogger.debug('Диагностика платформы: $e');
        }
      }());

      _initialized = true;
      AppLogger.info('BackgroundService: все сервисы запущены');
    } catch (e, stack) {
      AppLogger.error('BackgroundService: ошибка', e, stack);
    }
  }

  /// Зафиксировать активность пользователя
  void recordActivity() {
    _checkAutoLock();
    _lastActivity = DateTime.now();
    _autoLockLogged = false;
  }

  /// iPhone свёрнут: система будит приложение только ради фоновой задачи, и
  /// в тот же миг в главном изоляте срабатывают просроченные таймеры (журнал
  /// 18–19.10.2026). Свою проверку они не начинают — её делает задача
  /// (через [_onTaskRequest]), иначе iOS заморозила бы процесс посреди неё.
  static bool get _iosAway =>
      !kIsWeb && Platform.isIOS && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;

  // ═══════════════ ФОНОВЫЕ ЗАДАЧИ → ПРИЛОЖЕНИЕ (1.6.43) ═══════════════

  /// Порт, через который фоновая задача (WorkManager, BGTask) просит живое
  /// приложение проверить почту — см. [_delegateToMain].
  ReceivePort? _taskPort;

  /// Идущая проверка по просьбе фоновой задачи: две задачи разом (iOS —
  /// обновление и обработка) ждут одну.
  Future<String>? _taskRun;

  /// Зарегистрировать порт (повторный вызов возвращает имя, если его убрала
  /// фоновая задача, не дождавшись ответа).
  void _listenBackgroundTasks() {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      var port = _taskPort;
      if (port == null) {
        port = ReceivePort('ogneliss-main-tasks');
        port.listen(_onTaskRequest);
        _taskPort = port;
      }
      final mine = port.sendPort;
      if (IsolateNameServer.lookupPortByName(_mainPortName) == mine) return;
      IsolateNameServer.removePortNameMapping(_mainPortName);
      IsolateNameServer.registerPortWithName(mine, _mainPortName);
    } catch (e) {
      AppLogger.debug('Порт фоновых задач: $e');
    }
  }

  void _onTaskRequest(dynamic msg) {
    if (msg is! Map) return;
    final reply = msg['reply'];
    if (reply is! SendPort) return;
    reply.send(const <String, Object?>{'ack': true});
    final kind = '${msg['kind'] ?? 'фоновая задача'}';
    final ms = msg['limitMs'];
    final limit = Duration(milliseconds: ms is int ? ms : 9 * 60 * 1000);
    var run = _taskRun;
    if (run == null) {
      run = _runForBackgroundTask(kind, limit).whenComplete(() => _taskRun = null);
      _taskRun = run;
    }
    unawaited(run.then(
      (what) => reply.send(<String, Object?>{'done': true, 'what': what}),
      onError: (Object e) =>
          reply.send(<String, Object?>{'done': true, 'what': 'ошибка: ${cutSafe('$e'.split('\n').first, 120)}'}),
    ));
  }

  /// Сигнал сервера на iPhone (1.7.2, `PushWakeService`): та же проверка,
  /// что по просьбе фоновой задачи; идущую проверку не дублирует.
  Future<String> runForPushWake(Duration limit) {
    _listenBackgroundTasks();
    var run = _taskRun;
    if (run == null) {
      run = _runForBackgroundTask('сигнал iOS', limit).whenComplete(() => _taskRun = null);
      _taskRun = run;
    }
    return run;
  }

  /// Проверка почты по просьбе фоновой задачи — то же, что задача сделала
  /// бы сама, но тёплым движком приложения (подключение к серверу, SyncKey,
  /// база уже открыты — на iPhone это секунды из ~30).
  Future<String> _runForBackgroundTask(String kind, Duration limit) async {
    // Приложение на экране — проверяет само (таймер, push), сеть у него есть.
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return 'пропуск: приложение открыто';
    }
    final started = DateTime.now();
    final ios = Platform.isIOS;
    var state = '';
    if (!ios) {
      try {
        state = PlatformDiagnostics.brief(await PlatformDiagnostics.collect(light: true));
      } catch (_) {}
    }
    AppLogger.info('$kind: проверку делает приложение (процесс жив)${state.isEmpty ? '' : ' ($state)'}');
    final sync = _ref.read(syncServiceProvider);
    Future<void> work() async {
      await _ref.read(connectivityServiceProvider.notifier).refresh();
      // Android: push мог умереть, пока сеть была закрыта или процесс стоял.
      if (!ios && _ref.read(settingsProvider).syncIntervalMinutes >= 0) {
        try {
          await _ref
              .read(imapPushServiceProvider)
              .ensureAlive(poke: true, reason: 'фоновая задача')
              .timeout(const Duration(seconds: 40));
        } catch (e) {
          AppLogger.warning('$kind: push — $e');
        }
      }
      if (ios) {
        // Как в самой задаче iOS (решение владельца 19.10): сначала
        // «Входящие» всех ящиков, затем всё — без пропуска по интервалу.
        await sync.quickInboxSync();
        await sync.syncAll(scheduled: true, respectInterval: false, fresh: true);
        await sync.settle(timeout: const Duration(seconds: 20));
      } else {
        await sync.syncAll(scheduled: true, respectInterval: true, fresh: true);
        await sync.settle();
      }
      try {
        await _ref.read(reminderSchedulerProvider).rescheduleAll();
      } catch (e) {
        AppLogger.warning('$kind: напоминания — $e');
      }
      try {
        await _ref.read(quickCreateProvider).drain();
      } catch (e) {
        AppLogger.warning('$kind: виджет — $e');
      }
    }

    try {
      await work().timeout(limit);
    } on TimeoutException {
      AppLogger.info('$kind: время вышло — остальное в следующий раз');
      return 'время вышло — остальное в следующий раз';
    } finally {
      // Строки журнала — на диск: после задачи система снова усыпит процесс.
      AppLogger.flushNow();
    }
    final s = DateTime.now().difference(started).inMilliseconds / 1000;
    return 'за ${s.toStringAsFixed(1)} с';
  }

  // ═══════════ Android: сеть свёрнутого приложения (1.6.43) ═══════════

  bool _netClosedNoted = false;

  /// Android: свёрнутому приложению без службы система закрывает сеть
  /// (журнал OnePlus 18.10.2026: «Unable to resolve host» каждые 5 минут и
  /// только в фоне). Таймеру тогда стучаться к серверу бесполезно — ошибки
  /// и красная точка; почту проверит фоновая задача, ей сеть система даёт.
  Future<bool> _networkClosedInBackground() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _netClosedNoted = false;
      return false;
    }
    final closed = await _ref.read(foregroundSyncControllerProvider).networkBlocked();
    if (!closed) {
      _netClosedNoted = false;
      return false;
    }
    if (!_netClosedNoted) {
      _netClosedNoted = true;
      AppLogger.info('Таймер синхронизации: система закрыла приложению сеть в фоне — '
          'почту проверит фоновая задача (WorkManager), ей сеть даётся');
    }
    return true;
  }

  /// Пульс фоновой работы (будильник ОС, ~раз в 10 мин, и в глубоком сне):
  /// процесс жив, но Dart-таймеры во сне не срабатывали, а соединения push
  /// могли умереть по таймауту NAT. Проверяем push, «толкаем» IDLE и
  /// выполняем плановую проверку ящиков, у которых подошёл интервал.
  Future<void> onHeartbeat() => BackgroundJournal.track('пульс', () async {
        try {
          await _ref.read(imapPushServiceProvider).ensureAlive(poke: true, reason: 'пульс');
        } catch (e) {
          AppLogger.warning('Пульс: push — $e');
        }
        if (_ref.read(settingsProvider).syncIntervalMinutes >= 0) {
          await _foregroundSync(respectInterval: true);
        }
      });

  /// Сворачивание (iPhone): заявки на пробуждение — заново от момента
  /// сворачивания (как в примере Apple): обновление «не раньше чем через
  /// 15 минут» и задача обработки. Так заявка точно есть, даже если прежнюю
  /// система сняла. Проснувшись, задача передаст проверку приложению.
  void onPaused() {
    if (kIsWeb || !Platform.isIOS) return;
    // Синхронизация или отправка ещё идёт — попросить у iOS время доделать
    // (1.6.44), иначе запрос замёрзнет до следующего открытия.
    unawaited(FinishInBackground.onPaused());
    if (_ref.read(settingsProvider).syncIntervalMinutes < 0) return;
    unawaited(() async {
      try {
        await Workmanager().registerPeriodicTask(
          _TaskNames.periodicSync,
          _TaskNames.periodicSync,
          initialDelay: const Duration(minutes: 15),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      } catch (e) {
        AppLogger.debug('iOS: заявка на обновление — $e');
      }
      await submitIosProcessing();
    }());
  }

  /// iOS: заявка на BGProcessingTask (нужна сеть, без зарядки; не раньше
  /// чем через 15 минут). Задача разовая — выставляется при запуске, при
  /// сворачивании и после каждого выполнения.
  static Future<void> submitIosProcessing() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await Workmanager().registerProcessingTask(
        _TaskNames.processingSync,
        _TaskNames.processingSync,
        initialDelay: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected, requiresCharging: false),
      );
    } catch (e) {
      AppLogger.debug('iOS: заявка на обработку — $e');
    }
  }

  /// Возврат в приложение: push проверяется сразу (за время в фоне он мог
  /// умереть), фоновый сервис поднимается снова, если система его остановила.
  Future<void> onResume() async {
    // Имя порта могла убрать фоновая задача, не дождавшись ответа.
    _listenBackgroundTasks();
    if (_ref.read(settingsProvider).syncIntervalMinutes < 0) return;
    try {
      await _ref.read(imapPushServiceProvider).ensureAlive(poke: true, reason: 'возврат в приложение');
    } catch (e) {
      AppLogger.warning('Resume: push — $e');
    }
  }

  // ════════════════════════ ТАЙМЕРЫ ════════════════════════

  /// Периодическая синхронизация почты, пока приложение открыто (foreground).
  /// Дополняет WorkManager/BGTask (которые работают, когда приложение свёрнуто).
  void _startForegroundSyncTimer() {
    _foregroundSyncTimer?.cancel();
    final settings = _ref.read(settingsProvider);
    // -1 = «Никогда»: периодический таймер не запускаем вовсе.
    if (settings.syncIntervalMinutes < 0) return;
    // Тикаем раз в 5 минут: у каждого аккаунта свой интервал (5/15/30/60),
    // а лишние аккаунты отсеивает syncAll(respectInterval: true). В режиме
    // push раньше тик был раз в 15 минут — теперь на каждом тике ещё и
    // сторож push, ему нужно чаще.
    _foregroundSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) async {
        // iPhone: просроченный таймер сработал при пробуждении свёрнутого
        // приложения ради фоновой задачи — почту проверяет она (её изолят),
        // вторая синхронизация рядом только мешает и всё равно будет
        // оборвана заморозкой.
        if (_iosAway) {
          AppLogger.debug('Таймер синхронизации: приложение свёрнуто (iOS) — проверку делает фоновая задача');
          return;
        }
        if (await _networkClosedInBackground()) return;
        try {
          await _ref.read(imapPushServiceProvider).ensureAlive();
        } catch (_) {}
        // Самовосстановление (1.6.48): ящик давно не обновлялся — проверка
        // и перезапуск push. До плановой проверки: та может ждать зависший
        // проход до 5 минут.
        unawaited(_ref.read(staleWatchdogProvider).check());
        await _foregroundSync();
      },
    );
  }

  Future<void> _foregroundSync({bool respectInterval = true}) async {
    _lastForegroundSync = DateTime.now();
    try {
      await _ref.read(syncServiceProvider)
          .syncAll(scheduled: true, respectInterval: respectInterval);
      AppLogger.debug('Foreground sync выполнен');
    } catch (e) {
      AppLogger.warning('Foreground sync error: $e');
    }
  }

  /// Немедленная синхронизация при возврате в приложение (resume), но не чаще
  /// раза в 2 минуты — чтобы частые переключения не били по сети/серверу.
  /// Раньше при возврате синк не запускался — свежая почта появлялась только на
  /// следующем тике таймера (до `syncIntervalMinutes` ожидания).
  Future<void> syncOnResume() async {
    if (DateTime.now().difference(_lastForegroundSync) < const Duration(minutes: 2)) {
      return;
    }
    // При возврате в приложение — свежая почта всех аккаунтов, кроме тех,
    // что настроены «только вручную» или «только по Wi‑Fi» без Wi‑Fi.
    await _foregroundSync(respectInterval: false);
  }

  /// Применить смену интервала синхронизации: перезапустить foreground-таймер и
  /// перерегистрировать периодическую задачу WorkManager под новый интервал
  /// (0 = только вручную/по push → снять задачу).
  Future<void> applySyncInterval() async {
    _startForegroundSyncTimer(); // перечитывает интервал, cancel + restart
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    await _registerPeriodic();

    // Режим «Никогда» (-1) выключает и push (IMAP IDLE / EAS Ping); во всех
    // остальных режимах push поддерживается включённым. start() идемпотентен
    // (пропускает аккаунты, для которых подписка уже есть).
    try {
      final push = _ref.read(imapPushServiceProvider);
      if (_ref.read(settingsProvider).syncIntervalMinutes < 0) {
        await push.stopAll();
      } else {
        await push.start();
      }
    } catch (e) {
      AppLogger.warning('applySyncInterval push: $e');
    }
  }

  /// Зарегистрировать (или снять) периодическую задачу WorkManager.
  Future<void> _registerPeriodic() async {
    try {
      final settings = _ref.read(settingsProvider);
      // Push есть у IMAP (IDLE), EAS (Ping) и EWS (Streaming Notifications).
      // Для EWS оставляем РЕЗЕРВНЫЙ фоновый опрос: подписка может не подняться
      // (старый Exchange, ограничения прав), и тогда без опроса письма в фоне
      // не пришли бы вовсе. Android всё равно не даёт период меньше 15 мин.
      // Резерв нужен ВСЕМ ящикам, не только EWS: push (IMAP IDLE, EAS Ping)
      // живёт, пока жив процесс. Смахнули приложение из недавних или система
      // выгрузила его — без опроса почта, календарь и напоминания не
      // обновлялись бы до следующего открытия. Свежие ящики синк пропустит
      // сам (respectInterval). Список аккаунтов при запуске может быть ещё
      // не загружен, поэтому от него не зависим: без ящиков задача пустая.
      final needsPollFallback = settings.syncIntervalMinutes == 0;
      final periodMinutes = settings.syncIntervalMinutes > 0
          ? settings.syncIntervalMinutes
          : (needsPollFallback ? 15 : 0);
      if (periodMinutes > 0) {
        await Workmanager().registerPeriodicTask(
          _TaskNames.periodicSync,
          _TaskNames.periodicSync,
          frequency: Duration(minutes: periodMinutes),
          constraints: Constraints(
            networkType: settings.syncOnlyWifi ? NetworkType.unmetered : NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
        await submitIosProcessing();
      } else {
        await Workmanager().cancelByUniqueName(_TaskNames.periodicSync);
        if (Platform.isIOS) await Workmanager().cancelByUniqueName(_TaskNames.processingSync);
      }
    } catch (e) {
      AppLogger.warning('WorkManager periodic: $e');
    }
  }

  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 25),
      (_) => _refreshTokens(),
    );
  }

  Future<void> _refreshTokens() async {
    try {
      final accounts = _ref.read(accountsProvider);
      final oauthService = _ref.read(oauthServiceProvider);

      for (final account in accounts) {
        if (!account.usesOAuthTokens) continue;
        // Ошибка одного аккаунта не должна мешать обновлению остальных.
        try {
          await oauthService.ensureValidToken(account);
        } catch (e) {
          AppLogger.warning('Token refresh ${account.email}: $e');
        }
      }
    } catch (e) {
      AppLogger.error('Token refresh error', e);
    }
  }

  void _startCacheCleanupTimer() {
    _cacheCleanupTimer?.cancel();
    _cacheCleanupTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => _cleanupCache(),
    );
  }

  Future<void> _cleanupCache() async {
    try {
      final db = _ref.read(databaseProvider);

      // Очистка старых аудит-логов
      final deletedAudit = await db.cleanupAuditLog();
      if (deletedAudit > 0) {
        AppLogger.info('Cache cleanup: удалено $deletedAudit аудит-записей');
      }

      // Очистка старых писем (по каждому аккаунту)
      final accounts = _ref.read(accountsProvider);
      for (final account in accounts) {
        final deleted = await db.cleanupOldEmails(account.id, account.syncDays);
        if (deleted > 0) {
          AppLogger.info('Cache cleanup: удалено $deleted старых писем (${account.email})');
        }
      }

      // Записи поискового индекса удалённых писем (удаления с сервера,
      // автоочистка выше) — иначе индекс растёт и в нём остаётся текст
      // писем, которых в приложении уже нет.
      try {
        final pruned = await db.pruneOrphanFts();
        if (pruned > 0) AppLogger.info('Cache cleanup: из индекса поиска удалено $pruned записей');
      } catch (_) {}

      // Очистка старых логов
      await AppLogger.clearLogs();

      AppLogger.info('Cache cleanup завершена');
    } catch (e) {
      AppLogger.error('Cache cleanup error', e);
    }
  }

  void _checkAutoLock() {
    final settings = _ref.read(settingsProvider);
    if (settings.autoLockMinutes <= 0) return;

    final elapsed = DateTime.now().difference(_lastActivity);
    if (elapsed.inMinutes >= settings.autoLockMinutes && !_autoLockLogged) {
      // Один раз за период бездействия (раньше — строка в журнал каждую
      // минуту, десятки строк за время в фоне).
      _autoLockLogged = true;
      AppLogger.info('Auto-lock: ${elapsed.inMinutes} мин бездействия');
      // Блокировка реализуется через UI (overlay или navigation)
    }
  }

  /// Остановить все таймеры
  void dispose() {
    _autoLockTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    _foregroundSyncTimer?.cancel();
    final port = _taskPort;
    if (port != null) {
      try {
        if (IsolateNameServer.lookupPortByName(_mainPortName) == port.sendPort) {
          IsolateNameServer.removePortNameMapping(_mainPortName);
        }
      } catch (_) {}
      port.close();
      _taskPort = null;
    }
  }
}

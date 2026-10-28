// lib/services/notifications/notification_router.dart
// Нажатие на уведомление → нужный экран: письмо, встреча, задача.
//
// Раньше нажатие только открывало приложение на том экране, где его
// оставили: обработчик получал пустой actionId и писал в журнал
// «Неизвестное действие уведомления». Теперь:
//  · приложение работает — переход сразу;
//  · приложение запускается с уведомления (холодный старт) — маршрут
//    запоминается и выполняется, когда откроется главный экран (MainShell),
//    иначе заставка перезаписала бы его своим переходом на /mail.

import 'dart:async' show unawaited;
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/app_router.dart';
import '../../features/mail/providers/mail_providers.dart' show allAccountsModeProvider, accountsProvider;
import '../../features/settings/providers/account_groups_provider.dart' show activeGroupIdProvider;
import '../../features/settings/providers/settings_provider.dart' show settingsProvider;
import '../../widgets/common/queue_sheet.dart' show showQueueSheet;
import 'notification_service.dart' show NotificationService;

final notificationRouterProvider = Provider<NotificationRouter>((ref) => NotificationRouter(ref));

class NotificationRouter {
  final Ref _ref;
  NotificationRouter(this._ref);

  /// Маршрут, отложенный до появления главного экрана.
  static String? _pending;

  /// Сколько главных экранов (MainShell) сейчас на месте. Счётчик, а не
  /// флаг (1.8.0, журнал 26.10.2026 18:47: нажатие на уведомление открыло
  /// приложение, а письмо — нет): при смене страницы новый MainShell
  /// успевал отметиться раньше, чем закрывался прежний, и флаг оставался
  /// «не готов» — переход ждал главного экрана, который уже был на месте.
  static int _shells = 0;

  /// Главный экран уже показывался в этом процессе: приложение запущено,
  /// заставка своим переходом на /mail маршрут не перезапишет.
  static bool _started = false;

  /// Главный экран открыт (переходить можно сразу).
  static bool get shellReady => _shells > 0;

  /// MainShell появился (initState).
  static void shellMounted() {
    _shells++;
  }

  /// MainShell закрыт (dispose).
  static void shellUnmounted() {
    if (_shells > 0) _shells--;
  }

  /// Маршрут для payload уведомления (null — открыть приложение как есть).
  static String? routeFor(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('summary:')) return '/mail';
    // «Письмо не отправлено» (1.7.2+114): почта и список очереди — там
    // «Отправить снова», «В черновики», «Удалить». Раньше нажатие ничего не
    // открывало («нет маршрута», журнал владельца 25.10.2026).
    if (payload.startsWith('outbox:')) return '/mail';
    if (payload.startsWith('event:')) {
      return eventDetailsPath(payload.substring(6), accountId: '');
    }
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final type = m['type'] as String? ?? 'email';
      final accountId = (m['accountId'] as String?) ?? '';
      switch (type) {
        case 'email':
          final id = m['emailId'] as String?;
          if (id == null || id.isEmpty) return '/mail';
          return mailDetailPath(id, accountId: accountId.isEmpty ? null : accountId);
        case 'mail_summary':
          return '/mail';
        case 'event':
          final id = m['id'] as String?;
          return id == null ? '/calendar' : eventDetailsPath(id, accountId: accountId);
        case 'task':
          final id = m['id'] as String?;
          return id == null ? '/tasks' : tasksPath(openTaskId: id, accountId: accountId);
        case 'myday':
          return '/my-day';
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Ящик, к которому относится уведомление о почте (письмо или сводка).
  static String? mailAccountFor(String? payload) {
    if (payload == null || payload.isEmpty || !payload.startsWith('{')) return null;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final type = m['type'] as String? ?? 'email';
      if (type != 'email' && type != 'mail_summary') return null;
      final id = m['accountId'] as String?;
      return id == null || id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Ящик, на который переключить список перед переходом.
  static String? _pendingAccount;

  /// После перехода открыть список очереди (уведомление «не отправлено»).
  static bool _openQueue = false;

  static bool _launchBusy = false;
  static bool _launchChecked = false;

  /// Проверить, не открыто ли приложение нажатием на уведомление: при
  /// запуске и при КАЖДОМ возврате на экран. Движок Android живёт дольше
  /// активности (MainActivity), и нажатие в шторке при закрытом окне
  /// создаёт новую активность — без колбэка нажатия. Раньше это проверялось
  /// только при запуске процесса, и письмо не открывалось.
  Future<void> checkLaunch(NotificationService service) async {
    if (_launchBusy) return;
    // iPhone помнит уведомление запуска до конца жизни процесса, а нажатия
    // при живом приложении и так приходят колбэком — там только при запуске.
    if (!Platform.isAndroid && _launchChecked) return;
    _launchChecked = true;
    _launchBusy = true;
    try {
      final p = await service.launchPayload();
      if (p != null) {
        AppLogger.info('Уведомление: открытие приложения нажатием');
        open(p);
      }
    } finally {
      _launchBusy = false;
    }
  }

  /// Нажатие на уведомление (не на кнопку).
  void open(String? payload) {
    final route = routeFor(payload);
    if (route == null) {
      AppLogger.info('Уведомление: нет маршрута для нажатия');
      return;
    }
    final account = mailAccountFor(payload);
    _openQueue = payload?.startsWith('outbox:') ?? false;
    // Ждать главного экрана нужно только при запуске процесса (заставка
    // ещё впереди). Приложение уже работало — переход сразу, даже если
    // сейчас открыт экран вне главного (настройки, письмо поверх).
    if (!shellReady && !_started) {
      _pending = route;
      _pendingAccount = account;
      AppLogger.info('Уведомление: переход — после запуска главного экрана');
      return;
    }
    _navigate(route, account);
  }

  /// Переход — после кадра: переключение ящика перестраивает список, и
  /// переход в том же кадре мог потеряться; при возврате из фона первый
  /// кадр ещё не нарисован.
  void _navigate(String route, String? account) {
    _switchAccount(account);
    final binding = WidgetsBinding.instance;
    var done = false;
    void go() {
      if (done) return;
      done = true;
      _go(route);
    }
    binding.addPostFrameCallback((_) => go());
    binding.scheduleFrame();
    // Страховка: окно ещё не видно, и кадр не рисуется.
    Future<void>.delayed(const Duration(milliseconds: 400), go);
  }

  /// Выполнить отложенный переход (вызывает MainShell после первого кадра).
  void consumePending() {
    _started = true;
    final route = _pending;
    final account = _pendingAccount;
    _pending = null;
    _pendingAccount = null;
    if (route != null) _navigate(route, account);
  }

  /// Уведомление о почте другого ящика: список переключается на этот ящик
  /// (раньше нажатие на сводку открывало активный ящик, и письма из шторки
  /// в нём не было). В режиме «Вся почта» / «Хаб» письма всех ящиков и так
  /// видны — режим не меняем.
  void _switchAccount(String? accountId) {
    if (accountId == null) return;
    try {
      if (_ref.read(allAccountsModeProvider)) return;
      if (!_ref.read(accountsProvider).any((a) => a.id == accountId)) return;
      if (_ref.read(settingsProvider).activeAccountId == accountId &&
          _ref.read(activeGroupIdProvider) == null) {
        return;
      }
      _ref.read(activeGroupIdProvider.notifier).state = null;
      _ref.read(settingsProvider.notifier).setActiveAccountId(accountId);
      AppLogger.info('Уведомление: переключение на ящик $accountId');
    } catch (e) {
      AppLogger.warning('Уведомление: переключение ящика — $e');
    }
  }

  void _go(String route) {
    try {
      final router = _ref.read(appRouterProvider);
      // Разделы нижней панели — переход, остальное — поверх текущего экрана,
      // чтобы «Назад» вернул туда, где человек был.
      if (route == '/mail' || route.startsWith('/tasks') || route == '/calendar') {
        router.go(route);
      } else {
        router.push(route);
      }
      AppLogger.info('Переход по уведомлению: $route');
      if (_openQueue) {
        _openQueue = false;
        // Шторка — когда экран почты уже построен.
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          final ctx = router.routerDelegate.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) unawaited(showQueueSheet(ctx));
        });
      }
    } catch (e) {
      AppLogger.warning('Переход по уведомлению: $e');
    }
  }
}

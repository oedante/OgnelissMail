// lib/services/sync/imap_push_service.dart
// PUSH для всех протоколов, которые его умеют: IMAP IDLE и EAS Ping.
//
// Оба механизма были реализованы в коде полностью, но НИ ОДИН не вызывался:
//  · IMAP IDLE (imap_service.startIdle) — личные ящики узнавали о письме только
//    при опросе по таймеру, до нескольких минут задержки;
//  · EAS Ping (eas_ping.dart, 164 строки) — то же самое для Exchange, то есть
//    для ОСНОВНОГО корпоративного сценария.
//
// Соединения у push отдельные: IDLE держит свой IMAP-клиент, Ping — свой
// длинный HTTP-запрос. Обычные операции им не мешают, а они — обычным.

import 'sync_schedule.dart';
import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart' show PushAuthFailure;
import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../mail/imap/imap_service.dart';
import 'sync_service.dart';
import '../mail/engine/mail_engine_service.dart';
import '../mail/ews/ews_service.dart';
import '../../data/database/app_database.dart' show Folder;
import 'push_health.dart';
import '../background/foreground_sync_controller.dart';

class ImapPushService {
  final Ref _ref;
  ImapPushService(this._ref);

  // IDLE отдаёт Stream<int>, Ping — Stream<EasPingResult>. Нам от подписки
  // нужен только cancel(), поэтому храним без конкретного типа события.
  final Map<String, StreamSubscription<dynamic>> _subs = {};
  /// Аккаунты, для которых подписка СЕЙЧАС создаётся (между проверкой и
  /// присвоением _subs есть await — без этой «резервации» два параллельных
  /// start() создали бы дублирующие подписки/соединения).
  final Set<String> _starting = {};

  bool _usesImap(AccountModel a) =>
      !a.usesEas && !a.usesEws && !a.isExchange;

  /// Включить push для всех активных ящиков: IMAP — IDLE, Exchange — EAS Ping.
  Future<void> start() async {
    // Без аккаунтов «требуется вход»: push со старым паролем — те же
    // неудачные входы, что ведут к блокировке учётной записи.
    // Push — только у ящиков с проверкой «Мгновенно» (экран аккаунта).
    // «По расписанию» — только в рабочие часы (sync_schedule.dart).
    final accounts = _ref.read(accountsProvider).where((a) =>
        a.isActive && a.authFailedAt == null && SyncSchedule.pushNow(a));
    for (final a in accounts) {
      await _startOne(a);
    }
  }

  /// EWS Streaming Notifications: сервер держит соединение и сообщает об
  /// изменениях сразу. Соединение живёт максимум 30 минут (ограничение
  /// протокола), после чего подписка создаётся заново — это штатный цикл.
  Future<void> _startEwsPush(AccountModel account) async {
    if (_subs.containsKey(account.id) || !_starting.add(account.id)) return;
    try {

    final db = _ref.read(databaseProvider);
    final folders = await (db.select(db.folders)
          ..where((f) => f.accountId.equals(account.id))
          ..where((f) => f.isSynced.equals(true)))
        .get();
    if (folders.isEmpty) return;

    final byId = {for (final f in folders) f.id: f};
    late final StreamSubscription<Set<String>> sub0;
    final sub = sub0 = _ewsEventLoop(account, byId.keys.toList()).listen(
      (changedFolderIds) async {
        AppLogger.info('EWS push: изменения в ${changedFolderIds.length} папках');
        for (final fid in changedFolderIds) {
          final row = byId[fid];
          // Уведомление может прийти по папке, которую мы не синхронизируем.
          if (row == null) continue;
          unawaited(_syncCoalesced(account, _toModel(row)));
        }
      },
      onError: (Object e) => AppLogger.warning('EWS push (${account.email}): $e'),
      onDone: () => _forget(account.id, sub0),
      cancelOnError: false,
    );
    _subs[account.id] = sub;
    _kind[account.id] = _PushKind.ews;
    AppLogger.info('EWS push: включён для ${account.email}');
    } finally {
      _starting.remove(account.id);
    }
  }

  /// Бесконечный цикл «подписка → слушаем события → переподписка».
  /// Прерывается отменой подписки (stopForAccount/stopAll).
  ///
  /// 1.6.44: цикл на StreamController с флагом остановки, а не async* —
  /// отмена async*-потока срабатывает лишь на следующем yield, то есть при
  /// следующем изменении в ящике. До тех пор stopForAccount ждал, а с ним
  /// стоял и сторож push всех ящиков («уже работает» — каждый вызов уходил
  /// сразу); прежний цикл тем временем продолжал переподписываться рядом с
  /// новым.
  Stream<Set<String>> _ewsEventLoop(AccountModel account, List<String> folderIds) {
    late final StreamController<Set<String>> ctrl;
    var stopped = false;
    StreamSubscription<Set<String>>? inner;
    Completer<void>? innerDone;

    Future<void> sleep(Duration d) async {
      final until = DateTime.now().add(d);
      while (!stopped && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    Future<void> loop() async {
      final ews = _ref.read(ewsServiceProvider);
      // Пауза растёт, если соединение рвётся сразу (сеть, 401, шлюз): раньше
      // переподписка шла каждые 2 секунды без конца.
      var pause = const Duration(seconds: 2);
      var hadGap = false;
      while (!stopped) {
        final startedAt = DateTime.now();
        markPushAlive(account.id);
        String? subscriptionId;
        try {
          subscriptionId = await ews.subscribeStreaming(account, folderIds);
        } catch (e) {
          // Раньше исключение здесь завершало цикл навсегда.
          AppLogger.warning('EWS push подписка (${account.email}): $e');
        }
        if (stopped) break;
        if (subscriptionId == null) {
          // Сервер не дал подписку (нет прав/старая версия/сеть) — не долбим его,
          // ждём и пробуем снова. Периодический синк тем временем работает.
          hadGap = true;
          await sleep(const Duration(minutes: 5));
          continue;
        }
        // Подписка после перерыва: изменения за время без неё сервер не
        // пришлёт — синхронизируем папки один раз.
        if (hadGap) {
          hadGap = false;
          if (!ctrl.isClosed) ctrl.add(folderIds.toSet());
        }
        final done = innerDone = Completer<void>();
        inner = ews.streamNotifications(account, subscriptionId).listen(
          (changed) {
            markPushAlive(account.id);
            if (!stopped && !ctrl.isClosed) ctrl.add(changed);
          },
          onError: (Object e) {
            hadGap = true;
            AppLogger.warning('EWS push поток (${account.email}): $e');
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        await done.future;
        inner = null;
        innerDone = null;
        if (stopped) break;
        markPushAlive(account.id);
        // Соединение закрылось — это норма (ConnectionTimeout). Переподписываемся.
        if (DateTime.now().difference(startedAt) < const Duration(minutes: 1)) {
          pause = pause * 2 > const Duration(minutes: 15) ? const Duration(minutes: 15) : pause * 2;
        } else {
          pause = const Duration(seconds: 2);
        }
        await sleep(pause);
      }
    }

    ctrl = StreamController<Set<String>>(
      onListen: () => unawaited(loop().catchError((Object e) {
        AppLogger.warning('EWS push ${account.email}: $e');
      }).whenComplete(() {
        if (!ctrl.isClosed) unawaited(ctrl.close());
      })),
      onCancel: () {
        stopped = true;
        // Соединение GetStreamingEvents — не ждём: отмена async*-потока
        // сработает при его следующем событии (или сторож тишины, 5 мин).
        final i = inner;
        inner = null;
        if (i != null) unawaited(i.cancel().catchError((Object _) {}));
        final d = innerDone;
        if (d != null && !d.isCompleted) d.complete();
      },
    );
    return ctrl.stream;
  }

  /// EAS Ping: сервер держит запрос открытым и отвечает, когда в папках
  /// появились изменения. Слушаем только синхронизируемые папки — их список
  /// сервер ограничивает (status 6 = «слишком много папок»).
  Future<void> _startEasPush(AccountModel account) async {
    if (_subs.containsKey(account.id) || !_starting.add(account.id)) return;
    try {

    final db = _ref.read(databaseProvider);
    final folders = await (db.select(db.folders)
          ..where((f) => f.accountId.equals(account.id))
          ..where((f) => f.isSynced.equals(true)))
        .get();
    if (folders.isEmpty) return;

    final byId = {for (final f in folders) f.id: f};
    // «Входящие» — первыми: при ограничении числа папок в Ping они не выпадут.
    final ids = [
      ...folders.where((f) => f.type == FolderType.inbox.index).map((f) => f.id),
      ...folders.where((f) => f.type != FolderType.inbox.index).map((f) => f.id),
    ];
    late final StreamSubscription<List<String>> sub0;
    final sub = sub0 = _ref
        .read(mailEngineServiceProvider)
        .easPushChanges(account, ids)
        .listen(
      (changedFolderIds) async {
        AppLogger.info('EAS push: изменения в ${changedFolderIds.length} папках');
        for (final fid in changedFolderIds) {
          final row = byId[fid];
          if (row == null) continue;
          unawaited(_syncCoalesced(account, _toModel(row)));
        }
      },
      onError: (Object e) {
        if (e is PushAuthFailure) {
          unawaited(_onPushAuthFailure(account));
        } else {
          AppLogger.warning('EAS push (${account.email}): $e');
        }
      },
      onDone: () => _forget(account.id, sub0),
      cancelOnError: false,
    );
    _subs[account.id] = sub;
    _kind[account.id] = _PushKind.eas;
    AppLogger.info('EAS push: включён для ${account.email}');
    } finally {
      _starting.remove(account.id);
    }
  }

  Future<void> startForAccount(AccountModel account) async {
    if (_subs.containsKey(account.id) || !_starting.add(account.id)) return; // уже слушаем/создаётся
    try {

    // Слушаем «Входящие»: остальные папки редко требуют мгновенности, а каждое
    // IDLE — это отдельное живое соединение (не стоит держать их пачками).
    final inbox = await _inboxOf(account);
    if (inbox == null) {
      AppLogger.info('IMAP push: у ${account.email} нет папки «Входящие» — пропуск');
      return;
    }

    final imap = _ref.read(imapServiceProvider);
    late final StreamSubscription<int> sub0;
    final sub = sub0 = imap.startIdle(account, inbox.id).listen(
      (count) async {
        // count >= 0 — пришло письмо; -1 — что-то удалили. В обоих случаях
        // достаточно синхронизировать эту папку: список сам обновится через
        // поток из БД (.watch()).
        AppLogger.info('IMAP push: событие в ${account.email} '
            '(${count >= 0 ? "EXISTS $count" : count == -1 ? "EXPUNGE" : "после переподключения"})');
        unawaited(_syncCoalesced(account, inbox));
      },
      onError: (Object e) {
        if (e is PushAuthFailure) {
          unawaited(_onPushAuthFailure(account));
        } else {
          AppLogger.warning('IMAP push (${account.email}): $e');
        }
      },
      onDone: () => _forget(account.id, sub0),
      cancelOnError: false,
    );
    _subs[account.id] = sub;
    _kind[account.id] = _PushKind.imap;
    AppLogger.info('IMAP push: включён для ${account.email}');
    } finally {
      _starting.remove(account.id);
    }
  }

  /// Поток push закончился сам (отказ во входе, ошибка) — убираем запись,
  /// чтобы следующий start() мог поднять его снова. Только если это та же
  /// подписка: после stop/start в _subs уже может лежать новая.
  void _forget(String accountId, StreamSubscription<dynamic> sub) {
    if (identical(_subs[accountId], sub)) {
      _subs.remove(accountId);
      _kind.remove(accountId);
    }
  }

  /// Когда push получал отказ во входе (по аккаунту) — не чаще двух
  /// перезапусков в час.
  final Map<String, List<DateTime>> _authStops = {};

  /// Ящики, где push только что получил отказ во входе: пока идёт пауза и
  /// проверка, сторож их не поднимает (иначе пульс или возврат в приложение
  /// сразу повторяли вход со старым паролем — риск блокировки учётной записи).
  final Set<String> _authPending = {};

  /// Push получил отказ во входе и остановился. Сам он вход не повторяет
  /// (блокировка учётной записи). Через минуту обычная синхронизация проверяет
  /// вход: если пароль действительно неверен — аккаунт помечается «требуется
  /// вход» (и push не поднимется до нового входа); если это был сбой шлюза —
  /// push включается снова.
  Future<void> _onPushAuthFailure(AccountModel account) async {
    if (!_authPending.add(account.id)) return;
    try {
      await _onPushAuthFailureInner(account);
    } finally {
      _authPending.remove(account.id);
    }
  }

  Future<void> _onPushAuthFailureInner(AccountModel account) async {
    await _subs.remove(account.id)?.cancel();
    final now = DateTime.now();
    final recent = [
      ...?_authStops[account.id]?.where((t) => now.difference(t) < const Duration(hours: 1)),
      now,
    ];
    _authStops[account.id] = recent;
    if (recent.length > 2) {
      AppLogger.warning('Push ${account.email}: повторные отказы во входе — выключен до перезапуска');
      return;
    }
    await Future<void>.delayed(const Duration(minutes: 1));
    try {
      await _ref.read(syncServiceProvider).syncAccount(account);
    } catch (e) {
      AppLogger.warning('Push ${account.email}: проверка входа — $e');
    }
    final fresh = _ref.read(accountsProvider).where((a) => a.id == account.id).toList();
    if (fresh.isEmpty || !fresh.first.isActive || fresh.first.authFailedAt != null) return;
    final a = fresh.first;
    if (_usesImap(a)) {
      await startForAccount(a);
    } else if (a.usesEas) {
      await _startEasPush(a);
    }
  }

  Future<void> stopForAccount(String accountId) async {
    _kind.remove(accountId);
    clearPushAlive(accountId);
    final sub = _subs.remove(accountId);
    // Сначала — сигнал циклу IMAP IDLE (выйти из ожидания сразу), затем
    // отмена подписки. Раньше порядок был обратный: отмена async*-потока IDLE
    // ждала следующего письма, сторож push всё это время стоял (1.6.44).
    // Гасим оба механизма: какой именно был поднят — не отслеживаем, а лишний
    // вызов безвреден (обе реализации проверяют, что останавливать).
    try {
      await _ref.read(imapServiceProvider).stopIdle(accountId).timeout(const Duration(seconds: 15));
    } catch (_) {}
    if (sub != null) {
      try {
        await sub.cancel().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
  }

  /// Синхронизация папки по событию push — со склейкой. Раньше каждое
  /// событие запускало свою синхронизацию: пачка писем давала очередь из
  /// десятка синхронизаций одной папки за одной арендой ящика. Теперь пока
  /// папка синхронизируется, новые события лишь отмечают «нужно ещё раз».
  final Map<String, bool> _folderSyncDirty = {};

  Future<void> _syncCoalesced(AccountModel account, FolderModel folder) async {
    final key = '${account.id}|${folder.id}';
    if (_folderSyncDirty.containsKey(key)) {
      _folderSyncDirty[key] = true;
      return;
    }
    _folderSyncDirty[key] = false;
    try {
      do {
        _folderSyncDirty[key] = false;
        // Короткая пауза собирает пачку событий (EXISTS по каждому письму).
        await Future<void>.delayed(const Duration(milliseconds: 800));
        try {
          await _ref.read(syncServiceProvider).syncSingleFolder(account, folder);
        } catch (e) {
          AppLogger.warning('Push ${account.email}: синхронизация «${folder.displayName}» — $e');
        }
      } while (_folderSyncDirty[key] == true);
    } finally {
      _folderSyncDirty.remove(key);
    }
  }

  final Map<String, _PushKind> _kind = {};

  /// Сколько push может молчать, прежде чем сторож сочтёт его зависшим.
  /// IMAP: цикл 9 мин + проверки; EAS: Ping 8 мин + 60 с; EWS: поток до
  /// 30 мин (ConnectionTimeout) + переподписка.
  static Duration _maxSilence(_PushKind k) => switch (k) {
        _PushKind.imap => const Duration(minutes: 25),
        _PushKind.eas => const Duration(minutes: 25),
        _PushKind.ews => const Duration(minutes: 45),
      };

  bool _ensuring = false;
  bool _ensureAgain = false;

  /// Сторож push. Вызывается по таймеру переднего плана, по будильнику ОС
  /// (каждые ~10 мин, в том числе в глубоком сне), при возврате в приложение
  /// и после смены сети.
  ///
  /// · Ящик в режиме «Мгновенно» без push (цикл завершился, push не поднялся
  ///   при запуске) — поднимает. Раньше push запускался ТОЛЬКО при старте
  ///   приложения и после смены настройки.
  /// · Push молчит дольше допустимого (зависший сокет) — перезапускает.
  /// · [poke] — «толкнуть» живые IMAP IDLE: проверить соединение сейчас (по
  ///   будильнику и при смене сети: в сне собственный таймер не срабатывает).
  Future<void> ensureAlive({bool poke = false, String reason = ''}) async {
    // Сторож уже работает — повторить после него (например, restartAll после
    // смены сети остановил push, пока шла проверка по пульсу).
    if (_ensuring) {
      _ensureAgain = true;
      return;
    }
    _ensuring = true;
    try {
      final now = DateTime.now();
      final active = _ref.read(accountsProvider).where((a) => a.isActive && a.authFailedAt == null).toList();
      // «По расписанию»: в рабочие часы push поднимается, после — гаснет.
      final wanted = active.where(SyncSchedule.pushNow).toList();
      final wantedIds = {for (final a in wanted) a.id};
      // Ни одного ящика с push или расписанием — фоновый сервис (и его строка
      // в шторке) не нужен. Останавливать можно и из фона; запускается он
      // только с переднего плана (main_shell), так требует Android 12+.
      // Ящики «По расписанию» держат службу и вне рабочих часов: утром
      // push поднимет её пульс.
      if (!active.any(SyncSchedule.needsService)) {
        unawaited(_ref.read(foregroundSyncControllerProvider).stop());
      }
      // Ящик удалили, перевели на интервал или рабочие часы закончились —
      // push больше не нужен.
      for (final id in _subs.keys.where((id) => !wantedIds.contains(id)).toList()) {
        await stopForAccount(id);
      }
      for (final a in wanted) {
        if (_authPending.contains(a.id)) continue;
        // Подряд три отказа во входе за час — ждём нового входа (см.
        // _onPushAuthFailure), сторож не поднимает push заново.
        final stops = _authStops[a.id]?.where((t) => now.difference(t) < const Duration(hours: 1));
        if (stops != null && stops.length > 2) continue;
        final kind = _kind[a.id];
        if (!_subs.containsKey(a.id) || kind == null) {
          if (_starting.contains(a.id)) continue;
          AppLogger.info('Push ${a.email}: не работал — запускаю${reason.isEmpty ? '' : ' ($reason)'}');
          await _startOne(a);
          continue;
        }
        final last = pushLastAlive(a.id);
        if (last != null && now.difference(last) > _maxSilence(kind)) {
          AppLogger.warning('Push ${a.email}: молчит ${now.difference(last).inMinutes} мин — перезапуск');
          await stopForAccount(a.id);
          await _startOne(a);
          continue;
        }
        // «Толкаем» IDLE, только если оно начато больше 4 минут назад:
        // свежее соединение NAT ещё помнит, а лишний DONE/IDLE — это
        // пробуждение радио ради ничего (экономия заряда на пульсе).
        if (poke && kind == _PushKind.imap &&
            (last == null || now.difference(last) > const Duration(minutes: 4))) {
          _ref.read(imapServiceProvider).pokeIdle(a.id);
        }
      }
    } catch (e) {
      AppLogger.warning('Push сторож: $e');
    } finally {
      _ensuring = false;
      if (_ensureAgain) {
        _ensureAgain = false;
        unawaited(ensureAlive(reason: 'повтор'));
      }
    }
  }

  /// Сеть сменилась (Wi-Fi ↔ мобильная, VPN): старые соединения push
  /// привязаны к прежнему адресу и молча умирают. Перезапускаем все.
  Future<void> restartAll({String reason = ''}) async {
    AppLogger.info('Push: перезапуск всех${reason.isEmpty ? '' : ' — $reason'}');
    for (final id in _subs.keys.toList()) {
      await stopForAccount(id);
    }
    await ensureAlive(reason: reason);
  }

  Future<void> _startOne(AccountModel a) async {
    if (_usesImap(a)) {
      await startForAccount(a);
    } else if (a.usesEas) {
      await _startEasPush(a);
    } else if (a.usesEws || a.isExchange) {
      await _startEwsPush(a);
    }
  }

  /// Выключить push везде (уход в фон на десктопе, выход, смена аккаунтов).
  Future<void> stopAll() async {
    for (final id in _subs.keys.toList()) {
      await stopForAccount(id);
    }
  }

  Future<FolderModel?> _inboxOf(AccountModel account) async {
    final db = _ref.read(databaseProvider);
    // Не getSingleOrNull: при двух папках типа «Входящие» (ярлык Gmail,
    // общий ящик) он бросал исключение, и push ящика не запускался никогда.
    // Берём настоящие «Входящие» (INBOX), иначе первую по порядку.
    final rows = await (db.select(db.folders)
          ..where((f) => f.accountId.equals(account.id))
          ..where((f) => f.type.equals(FolderType.inbox.index))
          ..orderBy([(f) => OrderingTerm(expression: f.sortOrder)]))
        .get();
    if (rows.isEmpty) return null;
    final inbox = rows.firstWhere((r) => r.id.toUpperCase() == 'INBOX', orElse: () => rows.first);
    return _toModel(inbox);
  }

  FolderModel _toModel(Folder row) => folderFromRow(row);
}

enum _PushKind { imap, eas, ews }

final imapPushServiceProvider = Provider<ImapPushService>((ref) {
  return ImapPushService(ref);
});

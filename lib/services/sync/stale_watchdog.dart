// lib/services/sync/stale_watchdog.dart
// Самовосстановление (1.6.48, решение владельца 19.10.2026): строка
// «Обновлено …» в шапке ленты показывает, что ящик давно не обновлялся, —
// теперь приложение и само это исправляет: запускает проверку почты и
// перезапускает мгновенную доставку (push) давнего ящика.
//
// Когда: приложение открыто (на экране), сеть есть, общая проверка не
// «Никогда», ящик «давно не обновлялся» по тем же правилам, что строка в
// шапке (MailFreshness: дольше двух интервалов проверки ящика и ещё 5
// минут; ящики «вручную» и с отказом входа — не трогаем: вход повторять
// нельзя, политика домена блокирует учётную запись после нескольких
// неудачных входов). Не чаще раза в 5 минут.
//
// Проверяется на тике таймера открытого приложения (раз в 5 минут) —
// отдельного таймера нет: ежеминутные таймеры будили процесс и в фоне
// (аудит 11.10.2026). Идёт обычный проход меньше 3 минут — не мешаем; идёт
// дольше — считаем зависшим: syncAll(fresh: true) подождёт его 20 секунд и
// сделает свой.
//
// Каждый случай — в журнал и в журнал фоновой работы («самовосстановление»):
// по пакету диагностики видно, как часто приложению приходилось себя чинить.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../features/settings/providers/settings_provider.dart';
import '../background/background_journal.dart';
import 'imap_push_service.dart';
import 'mail_freshness.dart';
import 'push_health.dart';
import 'sync_schedule.dart';
import 'sync_service.dart';

class StaleWatchdog {
  StaleWatchdog(this._ref);
  final Ref _ref;

  /// Не чаще раза в это время.
  static const minGap = Duration(minutes: 5);

  /// Обычный проход короче этого — не мешаем ему.
  static const normalPass = Duration(minutes: 3);

  DateTime? _lastKick;
  bool _busy = false;

  /// Давние ящики (по тем же правилам, что строка «Обновлено …»).
  static List<AccountModel> staleOf(
    Iterable<({AccountModel account, DateTime? last})> boxes, {
    required DateTime now,
    required DateTime? Function(String accountId) pushAlive,
  }) =>
      [
        for (final b in boxes)
          if (b.account.isActive &&
              b.account.authFailedAt == null &&
              b.last != null &&
              MailFreshness.of([b], now: now, pushAlive: pushAlive).stale)
            b.account,
      ];

  /// Проверить и при необходимости починить. Вызывается тиком таймера
  /// открытого приложения.
  Future<void> check() async {
    if (_busy) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    final last = _lastKick;
    if (last != null && now.difference(last) < minGap) return;
    if (!_ref.read(connectivityServiceProvider).isConnected) return;
    if (_ref.read(settingsProvider).syncIntervalMinutes < 0) return;
    final sync = _ref.read(syncServiceProvider);
    final running = sync.runningFor;
    if (running != null && running < normalPass) return;
    _busy = true;
    try {
      final db = _ref.read(databaseProvider);
      final boxes = <({AccountModel account, DateTime? last})>[];
      for (final a in _ref.read(accountsProvider)) {
        final row = await (db.select(db.accounts)..where((x) => x.id.equals(a.id))).getSingleOrNull();
        boxes.add((account: a, last: row?.lastSyncAt));
      }
      final stale = staleOf(boxes, now: now, pushAlive: pushLastAlive);
      if (stale.isEmpty) return;
      _lastKick = now;
      final who = stale.map((a) => a.email).join(', ');
      final hung = running == null ? '' : ', проход идёт ${running.inMinutes} мин';
      AppLogger.warning('Самовосстановление: давно не обновлялись $who$hung — проверка и перезапуск push');
      unawaited(BackgroundJournal.note('самовосстановление', 'давно не обновлялись: $who$hung'));
      final push = _ref.read(imapPushServiceProvider);
      try {
        for (final a in stale.where(SyncSchedule.pushNow)) {
          await push.stopForAccount(a.id);
        }
        await push.ensureAlive(reason: 'самовосстановление');
      } catch (e) {
        AppLogger.warning('Самовосстановление: push — $e');
      }
      await sync.syncAll(fresh: true);
    } catch (e) {
      AppLogger.warning('Самовосстановление: $e');
    } finally {
      _busy = false;
    }
  }
}

final staleWatchdogProvider = Provider<StaleWatchdog>((ref) => StaleWatchdog(ref));

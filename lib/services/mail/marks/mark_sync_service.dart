// lib/services/mail/marks/mark_sync_service.dart
// «На контроле» и «Позже» на всех устройствах (решения владельца
// 13.11.2026): сверка отметок с сервером. Правила — mark_sync.dart.
//
//  · IMAP: ключевые слова $OgnControl и $OgnLater на письме. С сервера —
//    при синхронизации папки (applyImap), на сервер — после синхронизации
//    и через несколько секунд после правки отметки (pushLocal).
//  · Exchange (ActiveSync): флажок «К исполнению» с текстом «… · OGN-C/L»,
//    сроком и напоминанием (applyEasFlag, pushLocal).
//  · EWS — пока только на устройстве.
// Снимок разосланного — в настройках, по ящику. Выключатель — «Отметки на
// всех устройствах» (s_mark_sync, включён).

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mail_engine/mail_engine.dart' as me;

import '../../../core/logging/app_logger.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../../features/settings/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../control_service.dart';
import '../email_actions_service.dart' show emailActionsProvider;
import '../engine/mail_engine_service.dart' show mailEngineServiceProvider;
import '../imap/imap_service.dart' show imapServiceProvider;
import '../own_addresses.dart';
import 'mark_sync.dart';

final markSyncProvider = Provider<MarkSyncService>((ref) => MarkSyncService(ref));

class MarkSyncService {
  MarkSyncService(this._ref);
  final Ref _ref;

  /// Выключатель в настройках почты.
  static const prefKey = 's_mark_sync';

  /// Сервер не хранит свои ключевые слова (ящик → да).
  static const _noKeywordsKey = 'mark_sync_no_keywords';

  bool get enabled => _ref.read(sharedPrefsProvider).getBool(prefKey) ?? true;

  AppDatabase get _db => _ref.read(databaseProvider);

  String _snapKey(String accountId) => 'mark_sync_snap_$accountId';

  Map<String, MarkState> _snap(String accountId) =>
      MarkSync.decodeSnapshot(_ref.read(sharedPrefsProvider).getString(_snapKey(accountId)));

  Future<void> _saveSnap(String accountId, Map<String, MarkState> s) =>
      _ref.read(sharedPrefsProvider).setString(_snapKey(accountId), MarkSync.encodeSnapshot(s));

  AccountModel? _account(String id) => _ref.read(accountsProvider).where((a) => a.id == id).firstOrNull;

  // ── Правка отметок у себя → на сервер через несколько секунд ──

  StreamSubscription<String>? _sub;
  final _timers = <String, Timer>{};

  /// Следить за правкой отметок (AppDatabase.markChanges). Вызывается при
  /// запуске приложения.
  void start() {
    _sub ??= AppDatabase.markChanges.stream.listen((accountId) {
      _timers[accountId]?.cancel();
      _timers[accountId] = Timer(const Duration(seconds: 4), () {
        _timers.remove(accountId);
        final a = _account(accountId);
        if (a != null) unawaited(pushLocal(a));
      });
    });
  }

  // ── Строки писем ──

  Future<List<Email>> _rows(String accountId, Iterable<String> ids) async {
    final list = ids.toList();
    final out = <Email>[];
    for (var i = 0; i < list.length; i += 500) {
      final part = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      out.addAll(await (_db.select(_db.emails)..where((e) => e.accountId.equals(accountId) & e.id.isIn(part))).get());
    }
    return out;
  }

  Future<List<Email>> _marked(String accountId) => (_db.select(_db.emails)
        ..where((e) =>
            e.accountId.equals(accountId) & (e.controlState.isBiggerThanValue(0) | e.laterState.isBiggerThanValue(0)))
        ..orderBy([(e) => OrderingTerm(expression: e.receivedAt)]))
      .get();

  static MarkState _stateOf(Email r) => MarkState.of(
      controlState: r.controlState, laterState: r.laterState, followUpAt: r.followUpAt, remindAt: r.remindAt);

  /// Вид контроля для письма, отмеченного на другом устройстве: своё —
  /// «жду ответа», чужое мне — «должен ответить».
  int _kind(Email r) {
    final a = _account(r.accountId);
    if (a == null) return 2;
    final to = <String>[];
    try {
      for (final m in (jsonDecode(r.toRecipients) as List).whereType<Map>()) {
        final e = '${m['email'] ?? ''}'.trim();
        if (e.isNotEmpty) to.add(e);
      }
    } catch (_) {}
    return ControlService.initialFor(fromEmail: r.fromEmail, myEmail: OwnAddresses.of(a).join(','), to: to);
  }

  /// Записать отметки у себя (уведомление «Позже» — планируется заново).
  Future<void> _write(Email r, MarkState to) async {
    final from = _stateOf(r);
    if (to.c != from.c || (to.c > 0 && !MarkState(c: 1, due: to.due).same(MarkState(c: 1, due: from.due), dates: true))) {
      await _db.setControlState(r.id, r.accountId, to.c, deadline: to.due);
    }
    if (to.l != from.l || (to.l > 0 && !MarkState(l: 1, at: to.at).same(MarkState(l: 1, at: from.at), dates: true))) {
      await _ref.read(emailActionsProvider).setLater(r.id, r.accountId, on: to.l > 0, at: to.at);
    }
  }

  // ── IMAP ──

  /// Отметки с сервера после синхронизации папки: письмо → флаги (1 — «На
  /// контроле», 2 — «Позже»). Флаги, которых нет у письма с отметкой,
  /// разосланной раньше, — её сняли на другом устройстве.
  Future<void> applyImap(AccountModel account, Map<String, int> marks) async {
    if (!enabled || marks.isEmpty) return;
    try {
      final snap = _snap(account.id);
      final ids = [for (final e in marks.entries) if (e.value != 0 || snap.containsKey(e.key)) e.key];
      if (ids.isEmpty) return;
      var changed = false;
      var applied = 0;
      for (final r in await _rows(account.id, ids)) {
        final local = _stateOf(r);
        final remote = marks[r.id];
        final action = MarkSync.planBits(local: local.bits, synced: snap[r.id]?.bits, remote: remote);
        if (action == MarkAction.apply && remote != null) {
          final to = MarkSync.fromBits(remote, local: local, kind: _kind(r));
          if (to.empty) {
            snap.remove(r.id);
          } else {
            snap[r.id] = to;
          }
          changed = true;
          await _saveSnap(account.id, snap);
          await _write(r, to);
          applied++;
        } else if (action == MarkAction.none && remote != null && remote == local.bits && snap[r.id]?.bits != remote) {
          if (local.empty) {
            snap.remove(r.id);
          } else {
            snap[r.id] = local;
          }
          changed = true;
        }
      }
      if (changed) await _saveSnap(account.id, snap);
      if (applied > 0) AppLogger.info('Отметки с сервера (${account.email}): $applied');
    } catch (e) {
      AppLogger.warning('Отметки с сервера (IMAP): $e');
    }
  }

  // ── Своё → на сервер ──

  /// Отметки, изменённые у себя после прошлой сверки, — на сервер.
  Future<void> pushLocal(AccountModel account) async {
    if (!enabled) return;
    try {
      if (account.usesEas) {
        await _pushEas(account);
      } else if (!(account.usesEws || account.isExchange)) {
        await _pushImap(account);
      }
    } catch (e) {
      AppLogger.warning('Отметки на сервер (${account.email}): $e');
    }
  }

  Future<List<Email>> _candidates(String accountId, Map<String, MarkState> snap) async {
    final marked = await _marked(accountId);
    final have = {for (final r in marked) r.id};
    final rest = [for (final k in snap.keys) if (!have.contains(k)) k];
    final others = rest.isEmpty ? const <Email>[] : await _rows(accountId, rest);
    // Письма из снимка, которых больше нет на устройстве, — забыть.
    final found = {...have, for (final r in others) r.id};
    snap.removeWhere((k, _) => !found.contains(k));
    return [...marked, ...others];
  }

  Future<void> _pushImap(AccountModel account) async {
    final prefs = _ref.read(sharedPrefsProvider);
    if ((prefs.getStringList(_noKeywordsKey) ?? const []).contains(account.id)) return;
    final snap = _snap(account.id);
    final before = MarkSync.encodeSnapshot(snap);
    final imap = _ref.read(imapServiceProvider);
    var pushed = 0;
    for (final r in await _candidates(account.id, snap)) {
      final local = _stateOf(r);
      final s = snap[r.id]?.bits ?? 0;
      if (local.bits == s) continue;
      final uid = r.id.substring(r.id.lastIndexOf(':') + 1);
      final ok = await imap.setMarks(account,
          folderId: r.folderId,
          uid: uid,
          control: (local.bits & 1) != (s & 1) ? (local.bits & 1) == 1 : null,
          later: (local.bits & 2) != (s & 2) ? (local.bits & 2) == 2 : null);
      if (!ok) {
        AppLogger.info('Отметки: ${account.email} — сервер не хранит свои флаги, отметки остаются на устройстве');
        await prefs.setStringList(_noKeywordsKey, [...?prefs.getStringList(_noKeywordsKey), account.id]);
        break;
      }
      if (local.empty) {
        snap.remove(r.id);
      } else {
        snap[r.id] = local;
      }
      pushed++;
    }
    if (MarkSync.encodeSnapshot(snap) != before) await _saveSnap(account.id, snap);
    if (pushed > 0) AppLogger.info('Отметки на сервер (${account.email}): $pushed');
  }

  // ── Exchange (ActiveSync) ──

  me.MailFollowUp _followUp(MarkState s) {
    final l10n = AppLocalizations(_ref.read(settingsProvider).locale);
    return me.MailFollowUp(
      flagType: MarkFlag.text(s, control: l10n.tr('controlFilter'), later: l10n.tr('laterTitle')),
      status: s.c == 3 && s.l == 0 ? 1 : 2,
      due: s.due,
      reminder: s.at,
    );
  }

  Future<void> _pushEas(AccountModel account) async {
    final snap = _snap(account.id);
    final before = MarkSync.encodeSnapshot(snap);
    final engine = _ref.read(mailEngineServiceProvider);
    var pushed = 0;
    for (final r in await _candidates(account.id, snap)) {
      final local = _stateOf(r);
      final s = snap[r.id];
      if (local.same(s ?? MarkState.none, dates: true)) continue;
      if (local.empty && s == null) continue;
      await engine.setFollowUp(account,
          folderId: r.folderId, serverId: r.id, followUp: local.empty ? null : _followUp(local));
      if (local.empty) {
        snap.remove(r.id);
      } else {
        snap[r.id] = local;
      }
      pushed++;
    }
    if (MarkSync.encodeSnapshot(snap) != before) await _saveSnap(account.id, snap);
    if (pushed > 0) AppLogger.info('Отметки на сервер (${account.email}): $pushed');
  }

  /// Флажок с сервера ActiveSync. true — флажок наш (отметки), не флажок
  /// пользователя: письмо не помечается флажком.
  Future<bool> applyEasFlag(String accountId, me.MailFlagChange c) async {
    final code = MarkFlag.codeOf(c.followUp?.flagType);
    if (!enabled) return code != null;
    try {
      final snap = _snap(accountId);
      if (code == null) {
        // Наш флажок сняли в Outlook — снять отметки и здесь.
        if (c.flagged == false && snap.containsKey(c.id)) {
          final rows = await _rows(accountId, [c.id]);
          final s = snap.remove(c.id)!;
          await _saveSnap(accountId, snap);
          for (final r in rows) {
            if (_stateOf(r).same(s, dates: true)) await _write(r, MarkState.none);
          }
        }
        return false;
      }
      final f = c.followUp!;
      for (final r in await _rows(accountId, [c.id])) {
        final local = _stateOf(r);
        final remote = MarkFlag.stateOf(code,
            complete: f.complete, due: f.due, reminder: f.reminder, local: local, kind: _kind(r));
        final action = MarkSync.planFlag(local: local, synced: snap[r.id], remote: remote);
        if (action == MarkAction.apply) {
          snap[r.id] = remote;
          await _saveSnap(accountId, snap);
          await _write(r, remote);
        } else if (action == MarkAction.none && local.same(remote, dates: true)) {
          snap[r.id] = remote;
          await _saveSnap(accountId, snap);
        }
      }
      return true;
    } catch (e) {
      AppLogger.warning('Отметки с сервера (ActiveSync): $e');
      return true;
    }
  }
}

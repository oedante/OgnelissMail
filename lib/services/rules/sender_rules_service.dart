// lib/services/rules/sender_rules_service.dart
//
// Блокировка отправителя и чистка по отправителю (1.10.x, просьба владельца
// 01.11.2026; как «Заблокировать» в Apple Mail и Gmail и «Очистка» (Sweep)
// в Outlook).
//
//  · Заблокировать — новые письма с адреса или домена сразу уходят в «Спам»
//    (нет папки «Спам» — в «Корзину»), без уведомления. Уже полученные — по
//    выбору человека тоже.
//  · Чистка — для писем отправителя во «Входящих»:
//      удалять будущие письма; оставлять только последнее письмо; удалять
//      письма старше N дней (по умолчанию 10). Разово — «Удалить все письма
//      от…» (экран действий, не правило).
//
// Правила работают на устройстве, как правила VIP (DeviceRules): при
// получении новых писем «Входящих» — до уведомления, в приложении и в
// фоновой проверке. Правило на сервере (Sieve, Exchange) к блокировке
// добавляет экран блокировки, если ящик это умеет (sender_block_server.dart).

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/models/folder_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../mail/email_actions_service.dart';
import '../mail/special_folders.dart';
import 'device_rules_service.dart' show DeviceRule, RuleNotify, RuleOutcome;

/// Что делать с письмами отправителя.
enum SenderAction {
  /// Новые письма — в «Спам», без уведомления.
  block,

  /// Новые письма — в «Корзину», без уведомления.
  deleteFuture,

  /// Во «Входящих» — только последнее письмо, прежние — в «Корзину».
  keepLatest,

  /// Во «Входящих» письма старше [SenderRule.days] дней — в «Корзину».
  olderThan,
}

class SenderRule {
  final String id;

  /// Адрес («news@shop.ru») или домен («shop.ru», «@shop.ru»).
  final String pattern;
  final SenderAction action;
  final int days;

  /// Ящик (null — все ящики).
  final String? accountId;
  final DateTime createdAt;

  const SenderRule({
    required this.id,
    required this.pattern,
    required this.action,
    this.days = 10,
    this.accountId,
    required this.createdAt,
  });

  bool get isDomain => !pattern.contains('@') || pattern.startsWith('@');

  /// Как показывать: адрес или «@домен».
  String get label {
    final p = pattern.trim().toLowerCase();
    return p.contains('@') ? p : '@$p';
  }

  bool appliesTo(String accountId) => this.accountId == null || this.accountId == accountId;

  bool matches(String fromEmail) => DeviceRule.senderMatches(pattern, fromEmail.toLowerCase().trim());

  Map<String, Object?> toJson() => {
        'id': id,
        'pattern': pattern,
        'action': action.name,
        'days': days,
        'accountId': accountId,
        'createdAt': createdAt.toIso8601String(),
      };

  static SenderRule? fromJson(Map<String, dynamic> m) {
    final action = SenderAction.values.where((a) => a.name == m['action']).firstOrNull;
    final pattern = '${m['pattern'] ?? ''}'.trim().toLowerCase();
    if (action == null || pattern.isEmpty) return null;
    return SenderRule(
      id: '${m['id'] ?? pattern}',
      pattern: pattern,
      action: action,
      days: (m['days'] as num?)?.toInt() ?? 10,
      accountId: m['accountId'] as String?,
      createdAt: DateTime.tryParse('${m['createdAt'] ?? ''}') ?? DateTime(2026, 11),
    );
  }
}

final senderRulesProvider =
    StateNotifierProvider<SenderRulesNotifier, List<SenderRule>>((ref) => SenderRulesNotifier(ref));

class SenderRulesNotifier extends StateNotifier<List<SenderRule>> {
  static const key = 'sender_rules_v1';
  final Ref _ref;

  SenderRulesNotifier(this._ref) : super(_load(_ref.read(sharedPrefsProvider)));

  static List<SenderRule> _load(SharedPreferences p) {
    try {
      final raw = p.getString(key);
      if (raw == null) return const [];
      return [
        for (final m in jsonDecode(raw) as List)
          if (SenderRule.fromJson(Map<String, dynamic>.from(m as Map)) case final r?) r,
      ];
    } catch (e) {
      AppLogger.warning('Правила отправителей: не прочитаны ($e)');
      return const [];
    }
  }

  /// Перечитать с диска (фоновая проверка могла работать со старой копией).
  Future<void> reload() async {
    final p = _ref.read(sharedPrefsProvider);
    await p.reload();
    state = _load(p);
  }

  void _save() => _ref.read(sharedPrefsProvider).setString(key, jsonEncode([for (final r in state) r.toJson()]));

  /// Правило для отправителя: одно на шаблон и ящик — новое заменяет
  /// прежнее с тем же действием (блокировка и чистка уживаются).
  SenderRule add(String pattern, SenderAction action, {int days = 10, String? accountId}) {
    final p = normalizePattern(pattern);
    final r = SenderRule(
      id: '${action.name}:${accountId ?? '*'}:$p',
      pattern: p,
      action: action,
      days: days,
      accountId: accountId,
      createdAt: DateTime.now(),
    );
    state = [for (final x in state) if (x.id != r.id) x, r];
    _save();
    return r;
  }

  void remove(String id) {
    state = [for (final r in state) if (r.id != id) r];
    _save();
  }

  /// Блокировка, под которую попадает адрес (null — не заблокирован).
  SenderRule? blockFor(String fromEmail, {String? accountId}) => state
      .where((r) => r.action == SenderAction.block && (accountId == null || r.appliesTo(accountId)) && r.matches(fromEmail))
      .firstOrNull;

  /// Снять все блокировки, под которые попадает адрес.
  void unblock(String fromEmail) {
    state = [for (final r in state) if (!(r.action == SenderAction.block && r.matches(fromEmail))) r];
    _save();
  }

  /// Адрес без пробелов и регистра; домен — без «@» в начале.
  static String normalizePattern(String p) {
    final s = p.trim().toLowerCase();
    return s.startsWith('@') ? s.substring(1) : s;
  }

  /// Новые письма «Входящих»: блокировка и «удалять будущие» — до уведомлений
  /// и правил VIP. Возвращает, о каких письмах не уведомлять. «Оставлять
  /// последнее» — прежние письма отправителя уходят в «Корзину».
  Future<Map<String, RuleOutcome>> apply(AccountModel account, String inboxFolderId, List<EmailModel> mails) async {
    final rules = [for (final r in state) if (r.appliesTo(account.id)) r];
    if (rules.isEmpty || mails.isEmpty) return const {};
    final out = <String, RuleOutcome>{};
    final actions = _ref.read(emailActionsProvider);
    String? junk;
    var junkResolved = false;
    final keepLatestDone = <String>{};
    for (final e in mails) {
      final from = e.from.email.toLowerCase().trim();
      final mine = [for (final r in rules) if (r.matches(from)) r];
      if (mine.isEmpty) continue;
      try {
        if (mine.any((r) => r.action == SenderAction.block)) {
          if (!junkResolved) {
            junkResolved = true;
            junk = await SpecialFolders.resolve(
                _ref.read(databaseProvider), _ref.read(sharedPrefsProvider), account.id, SpecialKind.junk);
          }
          if (junk != null && junk != e.folderId) {
            await actions.moveTo(account, e.id, e.folderId, junk);
          } else {
            await actions.delete(account, e.id, e.folderId);
          }
          out[e.id] = const RuleOutcome(RuleNotify.none, true);
          AppLogger.info('Заблокированный отправитель ${AppLogger.mask(from)}: письмо убрано');
          continue;
        }
        if (mine.any((r) => r.action == SenderAction.deleteFuture)) {
          await actions.delete(account, e.id, e.folderId);
          out[e.id] = const RuleOutcome(RuleNotify.none, true);
          continue;
        }
        final keep = mine.where((r) => r.action == SenderAction.keepLatest).firstOrNull;
        if (keep != null && keepLatestDone.add(keep.id)) {
          await keepOnlyLatest(account, keep.pattern, folderId: inboxFolderId);
        }
      } catch (err) {
        AppLogger.warning('Правило отправителя не применилось: $err');
      }
    }
    return out;
  }

  final Map<String, DateTime> _sweptAt = {};

  /// «Удалять старше N дней»: не чаще раза в час на ящик.
  Future<int> sweepOld(AccountModel account, String inboxFolderId) async {
    final rules = [for (final r in state) if (r.action == SenderAction.olderThan && r.appliesTo(account.id)) r];
    if (rules.isEmpty) return 0;
    final last = _sweptAt[account.id];
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 1)) return 0;
    _sweptAt[account.id] = DateTime.now();
    var n = 0;
    for (final r in rules) {
      try {
        n += await deleteOlderThan(account, r.pattern, r.days, folderId: inboxFolderId);
      } catch (e) {
        AppLogger.warning('Чистка по отправителю: $e');
      }
    }
    if (n > 0) AppLogger.info('Чистка по отправителю: удалено писем $n');
    return n;
  }

  // ── Разовые действия (экран чистки и блокировки) ──

  /// Письма отправителя в папке [folderId] (по умолчанию «Входящие»),
  /// новые — первыми.
  Future<List<({String id, String folderId, DateTime at})>> mailsFrom(AccountModel account, String pattern,
      {String? folderId}) async {
    final db = _ref.read(databaseProvider);
    final folder = folderId ?? await db.folderIdOfType(account.id, FolderType.inbox.index);
    if (folder == null) return const [];
    final p = normalizePattern(pattern);
    final rows = await (db.select(db.emails)
          ..where((e) => e.accountId.equals(account.id) & e.folderId.equals(folder) & senderFilter(e, p))
          ..orderBy([(e) => OrderingTerm.desc(e.receivedAt)])
          ..limit(5000))
        .get();
    return [for (final r in rows) (id: r.id, folderId: r.folderId, at: r.receivedAt)];
  }

  /// Условие отбора по отправителю для запроса к базе: адрес — точно,
  /// домен — сам домен и его поддомены.
  static Expression<bool> senderFilter($EmailsTable e, String pattern) {
    final p = normalizePattern(pattern);
    final from = e.fromEmail.lower();
    if (p.contains('@')) return from.equals(p);
    return from.like('%@$p') | from.like('%.$p');
  }

  /// Удалить все письма отправителя из папки (по умолчанию «Входящие»).
  Future<int> deleteAll(AccountModel account, String pattern, {String? folderId}) async {
    final list = await mailsFrom(account, pattern, folderId: folderId);
    return _ref.read(emailActionsProvider).cleanupDelete(account, [for (final m in list) (id: m.id, folderId: m.folderId)]);
  }

  /// Оставить только последнее письмо отправителя.
  Future<int> keepOnlyLatest(AccountModel account, String pattern, {String? folderId}) async {
    final list = await mailsFrom(account, pattern, folderId: folderId);
    if (list.length <= 1) return 0;
    return _ref
        .read(emailActionsProvider)
        .cleanupDelete(account, [for (final m in list.skip(1)) (id: m.id, folderId: m.folderId)]);
  }

  /// Удалить письма отправителя старше [days] дней.
  Future<int> deleteOlderThan(AccountModel account, String pattern, int days, {String? folderId}) async {
    final edge = DateTime.now().subtract(Duration(days: days));
    final list = [for (final m in await mailsFrom(account, pattern, folderId: folderId)) if (m.at.isBefore(edge)) m];
    if (list.isEmpty) return 0;
    return _ref.read(emailActionsProvider).cleanupDelete(account, [for (final m in list) (id: m.id, folderId: m.folderId)]);
  }

  /// Перенести уже полученные письма отправителя в «Спам» (блокировка).
  Future<int> moveAllToJunk(AccountModel account, String pattern) async {
    final db = _ref.read(databaseProvider);
    final junk = await SpecialFolders.resolve(db, _ref.read(sharedPrefsProvider), account.id, SpecialKind.junk);
    final list = await mailsFrom(account, pattern);
    final actions = _ref.read(emailActionsProvider);
    var n = 0;
    for (final m in list) {
      try {
        if (junk != null && junk != m.folderId) {
          await actions.moveTo(account, m.id, m.folderId, junk);
        } else {
          await actions.delete(account, m.id, m.folderId);
        }
        n++;
      } catch (_) {}
    }
    return n;
  }
}

/// Домены общих почтовых служб: заблокировать можно только адрес, не весь
/// домен (иначе ушли бы все письма с gmail.com).
const publicMailDomains = <String>{
  'gmail.com', 'googlemail.com', 'yandex.ru', 'ya.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'mail.ru',
  'bk.ru', 'inbox.ru', 'list.ru', 'internet.ru', 'rambler.ru', 'icloud.com', 'me.com', 'mac.com',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'yahoo.com', 'ymail.com', 'aol.com', 'gmx.com',
  'gmx.de', 'web.de', 'proton.me', 'protonmail.com', 'zoho.com', 'mail.com', 'qq.com', '163.com',
};

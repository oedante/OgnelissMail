// lib/services/rules/device_rules_service.dart
// Правила на устройстве (рядом с VIP): «если письмо такое — сделать так».
//
// Срабатывают на новые письма во «Входящих», когда телефон их получает (в
// приложении и при фоновой синхронизации), до уведомления. Серверные
// правила (Outlook/OWA) работают независимо и раньше — эти дополняют их там,
// где сервер не умеет: уведомления, «Позже», «На контроле», теги.
//
// Условия (все заданные должны совпасть): отправитель (адрес или домен),
// слово в теме, «я только в копии», есть вложение, рассылка.
// Действия: уведомление (как обычно / без звука / не уведомлять / всегда —
// как VIP, и в тихие часы), переложить в папку (на сервере), прочитать,
// флажок, «Позже», «На контроле», тег (и подсветка строки).

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../mail/control_service.dart' show ControlService;
import '../mail/email_actions_service.dart';
import '../mail/own_addresses.dart';

/// Что делать с уведомлением о письме.
enum RuleNotify { keep, silent, none, always }

/// Когда вернуть письмо из «Позже».
enum RuleLater { none, evening, tomorrow, nextWeek }

class DeviceRule {
  final String id;
  final String name;
  final bool enabled;

  /// Ящик (null — все). Перекладывать в папку можно только у правила с ящиком.
  final String? accountId;

  // ── Условия ──
  /// Адреса или домены («ivanov@firm.ru», «firm.ru», «@firm.ru»).
  final List<String> senders;
  final String subject;
  final bool ccOnly;
  final bool hasAttachment;
  final bool mailingList;

  // ── Действия ──
  final RuleNotify notify;
  final String? moveFolderId;
  final String? moveFolderName;
  final bool markRead;
  final bool flag;
  final RuleLater later;
  final bool control;
  final String tag;
  final bool highlight;

  const DeviceRule({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.accountId,
    this.senders = const [],
    this.subject = '',
    this.ccOnly = false,
    this.hasAttachment = false,
    this.mailingList = false,
    this.notify = RuleNotify.keep,
    this.moveFolderId,
    this.moveFolderName,
    this.markRead = false,
    this.flag = false,
    this.later = RuleLater.none,
    this.control = false,
    this.tag = '',
    this.highlight = false,
  });

  bool get hasCondition =>
      senders.isNotEmpty || subject.trim().isNotEmpty || ccOnly || hasAttachment || mailingList;

  bool get hasAction =>
      notify != RuleNotify.keep ||
      moveFolderId != null ||
      markRead ||
      flag ||
      later != RuleLater.none ||
      control ||
      tag.trim().isNotEmpty;

  DeviceRule copyWith({
    String? name,
    bool? enabled,
    String? accountId,
    bool clearAccount = false,
    List<String>? senders,
    String? subject,
    bool? ccOnly,
    bool? hasAttachment,
    bool? mailingList,
    RuleNotify? notify,
    String? moveFolderId,
    String? moveFolderName,
    bool clearMove = false,
    bool? markRead,
    bool? flag,
    RuleLater? later,
    bool? control,
    String? tag,
    bool? highlight,
  }) =>
      DeviceRule(
        id: id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        senders: senders ?? this.senders,
        subject: subject ?? this.subject,
        ccOnly: ccOnly ?? this.ccOnly,
        hasAttachment: hasAttachment ?? this.hasAttachment,
        mailingList: mailingList ?? this.mailingList,
        notify: notify ?? this.notify,
        moveFolderId: clearMove ? null : (moveFolderId ?? this.moveFolderId),
        moveFolderName: clearMove ? null : (moveFolderName ?? this.moveFolderName),
        markRead: markRead ?? this.markRead,
        flag: flag ?? this.flag,
        later: later ?? this.later,
        control: control ?? this.control,
        tag: tag ?? this.tag,
        highlight: highlight ?? this.highlight,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'on': enabled,
        if (accountId != null) 'acc': accountId,
        'from': senders,
        'subj': subject,
        'cc': ccOnly,
        'att': hasAttachment,
        'list': mailingList,
        'notify': notify.name,
        if (moveFolderId != null) 'move': moveFolderId,
        if (moveFolderName != null) 'moveName': moveFolderName,
        'read': markRead,
        'flag': flag,
        'later': later.name,
        'control': control,
        'tag': tag,
        'hl': highlight,
      };

  static DeviceRule fromJson(Map<String, dynamic> m) => DeviceRule(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? '',
        enabled: (m['on'] as bool?) ?? true,
        accountId: m['acc'] as String?,
        senders: [for (final s in (m['from'] as List?) ?? const []) '$s'],
        subject: (m['subj'] as String?) ?? '',
        ccOnly: (m['cc'] as bool?) ?? false,
        hasAttachment: (m['att'] as bool?) ?? false,
        mailingList: (m['list'] as bool?) ?? false,
        notify: RuleNotify.values.where((v) => v.name == m['notify']).firstOrNull ?? RuleNotify.keep,
        moveFolderId: m['move'] as String?,
        moveFolderName: m['moveName'] as String?,
        markRead: (m['read'] as bool?) ?? false,
        flag: (m['flag'] as bool?) ?? false,
        later: RuleLater.values.where((v) => v.name == m['later']).firstOrNull ?? RuleLater.none,
        control: (m['control'] as bool?) ?? false,
        tag: (m['tag'] as String?) ?? '',
        highlight: (m['hl'] as bool?) ?? false,
      );

  /// Подходит ли письмо ящика [account] под условия правила.
  bool matches(EmailModel e, AccountModel account) {
    if (!enabled || !hasCondition) return false;
    if (accountId != null && accountId != account.id) return false;
    final from = e.from.email.trim().toLowerCase();
    if (senders.isNotEmpty && !senders.any((s) => senderMatches(s, from))) return false;
    final subj = subject.trim().toLowerCase();
    if (subj.isNotEmpty && !e.subject.toLowerCase().contains(subj)) return false;
    if (ccOnly) {
      final inTo = e.to.any((a) => OwnAddresses.isMine(account, a.email));
      final inCc = e.cc.any((a) => OwnAddresses.isMine(account, a.email));
      if (inTo || !inCc) return false;
    }
    if (hasAttachment && !e.hasAttachments) return false;
    if (mailingList && !isMailingList(e)) return false;
    return true;
  }

  /// «firm.ru», «@firm.ru» — домен (и его поддомены); иначе — адрес целиком.
  static bool senderMatches(String pattern, String from) {
    final p = pattern.trim().toLowerCase();
    if (p.isEmpty || from.isEmpty) return false;
    if (p.contains('@') && !p.startsWith('@')) return from == p;
    final domain = p.startsWith('@') ? p.substring(1) : p;
    final fd = from.contains('@') ? from.split('@').last : from;
    return fd == domain || fd.endsWith('.$domain');
  }

  static const _bulkLocal = {
    'noreply', 'no-reply', 'donotreply', 'do-not-reply', 'newsletter', 'news', 'mailer', 'digest',
    'notifications', 'notification', 'info', 'promo', 'marketing', 'rassylka', 'subscribe',
  };

  /// Рассылка: есть List-Unsubscribe, а если заголовок ещё не загружен
  /// (ActiveSync берёт его при открытии) — типичный адрес рассылок.
  static bool isMailingList(EmailModel e) {
    if ((e.listUnsubscribe ?? '').isNotEmpty) return true;
    final local = e.from.email.split('@').first.toLowerCase();
    return _bulkLocal.contains(local);
  }
}

/// Итог правил для письма: что сделано и как уведомлять.
class RuleOutcome {
  final RuleNotify notify;
  /// Письмо переложено или прочитано — уведомление не нужно (если не «всегда»).
  final bool quietlyHandled;
  const RuleOutcome(this.notify, this.quietlyHandled);
}

final deviceRulesProvider =
    StateNotifierProvider<DeviceRulesNotifier, List<DeviceRule>>((ref) => DeviceRulesNotifier(ref));

/// Теги, которыми правила подсвечивают строку в ленте.
final highlightTagsProvider = Provider<Set<String>>((ref) => {
      for (final r in ref.watch(deviceRulesProvider))
        if (r.enabled && r.highlight && r.tag.trim().isNotEmpty) r.tag.trim(),
    });

class DeviceRulesNotifier extends StateNotifier<List<DeviceRule>> {
  static const key = 'device_rules_v1';
  final Ref _ref;

  DeviceRulesNotifier(this._ref) : super(_load(_ref.read(sharedPrefsProvider)));

  static List<DeviceRule> _load(SharedPreferences p) {
    try {
      final raw = p.getString(key);
      if (raw == null) return const [];
      return [for (final m in jsonDecode(raw) as List) DeviceRule.fromJson(Map<String, dynamic>.from(m as Map))];
    } catch (e) {
      AppLogger.warning('Правила: не прочитаны ($e)');
      return const [];
    }
  }

  /// Перечитать с диска (фоновый процесс мог работать со старой копией).
  Future<void> reload() async {
    final p = _ref.read(sharedPrefsProvider);
    await p.reload();
    state = _load(p);
  }

  void _save() => _ref.read(sharedPrefsProvider).setString(key, jsonEncode([for (final r in state) r.toJson()]));

  void upsert(DeviceRule r) {
    final i = state.indexWhere((x) => x.id == r.id);
    final next = [...state];
    if (i < 0) {
      next.add(r);
    } else {
      next[i] = r;
    }
    state = next;
    _save();
  }

  void remove(String id) {
    state = [for (final r in state) if (r.id != id) r];
    _save();
  }

  void toggle(String id) {
    state = [for (final r in state) r.id == id ? r.copyWith(enabled: !r.enabled) : r];
    _save();
  }

  void reorder(int from, int to) {
    final list = [...state];
    if (to > from) to--;
    list.insert(to, list.removeAt(from));
    state = list;
    _save();
  }

  /// Правила, подходящие письму, по порядку.
  List<DeviceRule> matching(EmailModel e, AccountModel account) =>
      [for (final r in state) if (r.matches(e, account)) r];

  /// Применить правила к новым письмам «Входящих». Возвращает, как
  /// уведомлять о письмах, к которым правила применились (по id письма).
  Future<Map<String, RuleOutcome>> apply(AccountModel account, String inboxFolderId, List<EmailModel> mails) async {
    if (state.isEmpty || mails.isEmpty) return const {};
    // Выключено в «Экспериментальных функциях».
    if (_ref.read(sharedPrefsProvider).getBool('device_rules_on') == false) return const {};
    final out = <String, RuleOutcome>{};
    final actions = _ref.read(emailActionsProvider);
    final db = _ref.read(databaseProvider);
    for (final e in mails) {
      final rules = matching(e, account);
      if (rules.isEmpty) continue;
      var notify = RuleNotify.keep;
      var handled = false;
      String? move;
      var read = false, flag = false, control = false;
      var later = RuleLater.none;
      final tags = <String>{};
      for (final r in rules) {
        // Самое «громкое» решение об уведомлении побеждает: всегда > без
        // звука > не уведомлять > как обычно.
        if (r.notify == RuleNotify.always ||
            (r.notify == RuleNotify.silent && notify != RuleNotify.always) ||
            (r.notify == RuleNotify.none && notify == RuleNotify.keep)) {
          notify = r.notify;
        }
        move ??= r.accountId == account.id ? r.moveFolderId : null;
        read |= r.markRead;
        flag |= r.flag;
        control |= r.control;
        if (later == RuleLater.none) later = r.later;
        if (r.tag.trim().isNotEmpty) tags.add(r.tag.trim());
      }
      try {
        if (tags.isNotEmpty) {
          await actions.setTags(e.id, {...e.tags, ...tags}.toList(), accountId: account.id);
        }
        // Я только в копии — «жду ответа», а не «должен ответить».
        if (control) {
          await db.setControlState(e.id, account.id, ControlService.initialFor(
              fromEmail: e.from.email, myEmail: OwnAddresses.of(account).join(','),
              to: [for (final a in e.to) a.email]));
        }
        if (later != RuleLater.none) {
          await actions.setLater(e.id, account.id, on: true, at: laterTime(later, DateTime.now()));
        }
        if (flag) await actions.setFlag(account, e.id, e.folderId, true);
        if (read) {
          await actions.setRead(account, e.id, e.folderId, true);
          handled = true;
        }
        // Перекладываем последним: у ActiveSync после переноса меняется id.
        // «Уведомлять всегда» — не перекладываем до уведомления: иначе
        // нажатие на уведомление не нашло бы письмо (у него новый id).
        if (move != null && notify != RuleNotify.always && move != e.folderId && move != inboxFolderId) {
          await actions.moveTo(account, e.id, e.folderId, move);
          handled = true;
        }
      } catch (err) {
        AppLogger.warning('Правило не применилось к письму: $err');
      }
      AppLogger.info('Правила: ${rules.length} для письма от ${AppLogger.mask(e.from.email)}');
      out[e.id] = RuleOutcome(notify, handled || later != RuleLater.none);
    }
    return out;
  }

  /// Когда вернуть письмо, отложенное правилом.
  static DateTime laterTime(RuleLater l, DateTime now) {
    // Календарная арифметика (а не Duration): при переходе на летнее/зимнее
    // время «завтра в 9» не съезжает на 8 или 10.
    switch (l) {
      case RuleLater.evening:
        final ev = DateTime(now.year, now.month, now.day, 18);
        return ev.isAfter(now.add(const Duration(minutes: 30)))
            ? ev
            : DateTime(now.year, now.month, now.day + 1, 18);
      case RuleLater.tomorrow:
        return DateTime(now.year, now.month, now.day + 1, 9);
      case RuleLater.nextWeek:
        final days = (DateTime.monday - now.weekday + 7) % 7;
        return DateTime(now.year, now.month, now.day + (days == 0 ? 7 : days), 9);
      case RuleLater.none:
        return now;
    }
  }
}

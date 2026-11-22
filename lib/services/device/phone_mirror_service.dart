// lib/services/device/phone_mirror_service.dart
// Контакты и календарь ящиков — в телефоне.
//
// 2.7.0 (замечание владельца 22.11.2026: «контакты и календарь на устройстве
// у каждого аккаунта нужно всегда включать по умолчанию или вообще убрать из
// настроек»): включено по умолчанию для всех ящиков, без переключателей у
// ящика; один выключатель — в «Настройки → Контакты» и «Настройки →
// Календарь». Не дублируются ящики, которые телефон синхронизирует сам:
// Google (аккаунт Google есть в телефоне), iCloud на iPhone; онлайн-архив
// Exchange — тоже нет. Ящик, включённый раньше вручную, остаётся включённым.
// Нет разрешения — запись пропускается молча, спросит «Разрешения».
//
// Зачем: определитель номера (звонит коллега из адресной книги — «Телефон» и
// Ogneliss Dialer показывают имя и должность), встречи в системном календаре,
// его виджетах и на часах.
//
// Как: Android — учётная запись «Ogneliss Mail» в системе, под ней у каждого
// ящика свои контакты и календарь (только для чтения); iOS — группа в
// «Контактах» и отдельный календарь. Направление — из приложения в телефон.
// Выключение переключателя или удаление ящика удаляет его данные из
// телефона. Нативная часть — PhoneMirrorPlugin (Kotlin/Swift).
//
// Обновление — после синхронизации ящика (не чаще раза в 10 минут) и сразу
// при включении. Неизменённые записи не переписываются (хэш полей).
// Только при запущенном приложении: в фоновой задаче канала нет — пропуск.

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/models/contact_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../mail/dav/dav_pim_service.dart' show DavPimService;
import '../notifications/reminder_scheduler_service.dart';

final phoneMirrorProvider = Provider<PhoneMirrorService>((ref) => PhoneMirrorService(ref));

class PhoneMirrorService {
  final Ref _ref;
  PhoneMirrorService(this._ref);

  static const _ch = MethodChannel('ogneliss/phone_mirror');
  static final Map<String, DateTime> _last = {};

  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Прежние переключатели у ящика: включённый вручную ящик (например,
  // Google) остаётся включённым.
  static String _kContacts(String id) => 'mirror_contacts_$id';
  static String _kCalendar(String id) => 'mirror_calendar_$id';
  static const kContactsAll = 'mirror_contacts_all';
  static const kCalendarAll = 'mirror_calendar_all';

  /// Контакты ящиков в телефоне (по умолчанию — да).
  bool get contactsEnabled => _ref.read(sharedPrefsProvider).getBool(kContactsAll) ?? true;

  /// Встречи ящиков в календаре телефона (по умолчанию — да).
  bool get calendarEnabled => _ref.read(sharedPrefsProvider).getBool(kCalendarAll) ?? true;

  /// Ящик пишется в телефон по умолчанию: не Google (его контакты и
  /// календарь телефон синхронизирует сам — были бы дубли), не iCloud на
  /// iPhone, не онлайн-архив.
  static bool eligible(AccountModel a, {required bool ios}) {
    if (a.isOnlineArchive) return false;
    final p = DavPimService.providerOf(a);
    if (p == 'google') return false;
    if (ios && p == 'icloud') return false;
    return true;
  }

  AccountModel? _account(String id) {
    for (final a in _ref.read(accountsProvider)) {
      if (a.id == id) return a;
    }
    return null;
  }

  bool _on(String accountId, String legacyKey, bool enabled) {
    if (!enabled) return false;
    final prefs = _ref.read(sharedPrefsProvider);
    if (prefs.getBool(legacyKey) == true) return true;
    final a = _account(accountId);
    return a != null && eligible(a, ios: !kIsWeb && Platform.isIOS);
  }

  /// Список ящиков уже загружен.
  bool get accountsLoaded => _ref.read(accountsProvider).isNotEmpty;

  /// Есть ящик, контакты которого пишутся в телефон (нужно разрешение).
  bool get wantsContacts => isAvailable && _ref.read(accountsProvider).any((a) => contactsOn(a.id));

  /// Есть ящик, встречи которого пишутся в календарь телефона.
  bool get wantsCalendar => isAvailable && _ref.read(accountsProvider).any((a) => calendarOn(a.id));

  bool contactsOn(String accountId) => _on(accountId, _kContacts(accountId), contactsEnabled);
  bool calendarOn(String accountId) => _on(accountId, _kCalendar(accountId), calendarEnabled);

  /// Включить/выключить контакты всех ящиков в телефоне. Выключение
  /// убирает их из телефона.
  Future<void> setContactsEnabled(bool on) async {
    final before = _ref.read(accountsProvider).where((a) => contactsOn(a.id)).toList();
    await _ref.read(sharedPrefsProvider).setBool(kContactsAll, on);
    if (on) {
      await syncAll(force: true);
      return;
    }
    for (final a in before) {
      await _invoke('remove', {'account': a.email, 'contacts': true, 'removeAccount': !calendarOn(a.id)});
    }
  }

  /// Включить/выключить встречи всех ящиков в календаре телефона.
  Future<void> setCalendarEnabled(bool on) async {
    final before = _ref.read(accountsProvider).where((a) => calendarOn(a.id)).toList();
    await _ref.read(sharedPrefsProvider).setBool(kCalendarAll, on);
    if (on) {
      await syncAll(force: true);
      return;
    }
    for (final a in before) {
      await _invoke('remove', {'account': a.email, 'calendar': true, 'removeAccount': !contactsOn(a.id)});
    }
  }

  /// Ящик удалён из приложения — убрать его данные из телефона.
  Future<void> forget(AccountModel a) async {
    final prefs = _ref.read(sharedPrefsProvider);
    await prefs.remove(_kContacts(a.id));
    await prefs.remove(_kCalendar(a.id));
    if (!isAvailable) return;
    await _invoke('remove', {'account': a.email, 'removeAccount': true});
  }

  /// Обновить все ящики с включённой связью (после синхронизации).
  Future<void> syncAll({bool force = false}) async {
    if (!isAvailable) return;
    final accounts = _ref.read(accountsProvider);
    // Список ящиков ещё не загружен — ничего не трогаем (иначе «лишними»
    // оказались бы все ящики в телефоне).
    if (accounts.isEmpty) return;
    final on =[for (final a in accounts) if (contactsOn(a.id) || calendarOn(a.id)) a];
    // Ящики, удалённые в обход приложения, — убрать из телефона.
    await _invoke('prune', {'keep': [for (final a in on) a.email]});
    for (final a in on) {
      await syncAccount(a, force: force);
    }
  }

  /// Записать контакты и встречи ящика в телефон.
  Future<bool> syncAccount(AccountModel a, {bool force = false}) async {
    if (!isAvailable) return false;
    final last = _last[a.id];
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return true;
    _last[a.id] = DateTime.now();
    final db = _ref.read(databaseProvider);
    final label = 'Ogneliss — ${a.displayName.trim().isEmpty ? a.email : a.displayName.trim()}';
    var ok = true;
    // Нет разрешения — пропуск без записи в журнал при каждой проверке:
    // спросит «Разрешения» (первая настройка, «Разрешить всё»).
    if (contactsOn(a.id) && await Permission.contacts.isGranted) {
      final items = await _contacts(db, a.id);
      final n = await _invoke('syncContacts', {'account': a.email, 'groupName': label, 'contacts': items});
      ok = ok && n != null;
      if (n is int && n > 0) AppLogger.info('В телефоне: контактов записано $n (${a.email})');
    }
    if (calendarOn(a.id) && await Permission.calendarFullAccess.isGranted) {
      final items = await _events(db, a.id);
      final n = await _invoke('syncEvents', {
        'account': a.email,
        'calendarName': label,
        'color': a.colorValue,
        'events': items,
      });
      ok = ok && n != null;
      if (n is int && n > 0) AppLogger.info('В телефоне: встреч записано $n (${a.email})');
    }
    return ok;
  }

  Future<Object?> _invoke(String method, Map<String, Object?> args) async {
    try {
      return await _ch.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      // Фоновая задача (свой движок без каналов приложения) — пропуск.
      return null;
    } on PlatformException catch (e) {
      AppLogger.warning('В телефоне ($method): ${e.code} ${e.message ?? ''}');
      return null;
    }
  }

  /// Личные контакты ящика (с сервера). Собранные из переписки, адресная
  /// книга организации и импортированные из телефона — не пишутся.
  Future<List<Map<String, Object?>>> _contacts(AppDatabase db, String accountId) async {
    final rows = await (db.select(db.contacts)
          ..where((c) => c.accountId.equals(accountId))
          ..where((c) => c.source.equals(ContactSource.personal.index)))
        .get();
    return [
      for (final r in rows.map(contactFromRow))
        if (r.email.isNotEmpty || (r.phoneMobile ?? '').isNotEmpty || (r.phoneWork ?? '').isNotEmpty)
          _withHash({
            'id': r.id,
            'displayName': r.fullName.isNotEmpty ? r.fullName : r.displayName,
            'givenName': r.firstName,
            'familyName': r.lastName,
            'middleName': r.middleName,
            'emails': [if (r.email.isNotEmpty) r.email, ...r.additionalEmails],
            'phoneMobile': r.phoneMobile,
            'phoneWork': r.phoneWork,
            'company': r.company,
            'department': r.department,
            'jobTitle': r.jobTitle,
          }),
    ];
  }

  /// Встречи ящика: месяц назад — год вперёд (вхождения повторяющихся серий
  /// уже развёрнуты в базе), без отменённых.
  Future<List<Map<String, Object?>>> _events(AppDatabase db, String accountId) async {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 31));
    final to = now.add(const Duration(days: 366));
    final rows = await (db.select(db.calendarEvents)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.isCancelled.equals(false))
          ..where((e) => e.endTime.isBiggerThanValue(from))
          ..where((e) => e.startTime.isSmallerThanValue(to)))
        .get();
    return [
      for (final e in rows)
        _withHash({
          'id': e.id,
          'title': e.title,
          'description': e.description,
          'location': e.location,
          // Весь день — полночь UTC (так требует календарь Android).
          'start': e.isAllDay ? _utcMidnight(e.startTime.toLocal()) : e.startTime.millisecondsSinceEpoch,
          'end': e.isAllDay ? _utcMidnight(e.endTime.toLocal()) : e.endTime.millisecondsSinceEpoch,
          'allDay': e.isAllDay,
          // 1.8.13: на iPhone конец события на весь день — включительно;
          // отметка меняет хэш, и уже записанные события перезаписываются.
          if (e.isAllDay) 'fmt': 2,
          'reminderMinutes': ReminderSchedulerService.remindersOf(e.remindersJson)?.firstOrNull,
        }),
    ];
  }

  static int _utcMidnight(DateTime local) =>
      DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch;

  /// Хэш полей (FNV-1a, 32 бит): неизменённые записи нативная часть пропускает.
  static Map<String, Object?> _withHash(Map<String, Object?> m) {
    final s = jsonEncode(m);
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return {...m, 'hash': h.toRadixString(16)};
  }
}

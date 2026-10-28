// lib/services/device/phone_mirror_service.dart
// Контакты и календарь ящиков — в телефоне (Настройки ящика → «В телефоне»).
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
import '../notifications/reminder_scheduler_service.dart';

final phoneMirrorProvider = Provider<PhoneMirrorService>((ref) => PhoneMirrorService(ref));

class PhoneMirrorService {
  final Ref _ref;
  PhoneMirrorService(this._ref);

  static const _ch = MethodChannel('ogneliss/phone_mirror');
  static final Map<String, DateTime> _last = {};

  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String _kContacts(String id) => 'mirror_contacts_$id';
  static String _kCalendar(String id) => 'mirror_calendar_$id';

  bool contactsOn(String accountId) => _ref.read(sharedPrefsProvider).getBool(_kContacts(accountId)) ?? false;
  bool calendarOn(String accountId) => _ref.read(sharedPrefsProvider).getBool(_kCalendar(accountId)) ?? false;

  /// Включить/выключить контакты ящика в телефоне. false — нет разрешения
  /// или нативной части (переключатель остаётся выключенным).
  Future<bool> setContacts(AccountModel a, bool on) async {
    final prefs = _ref.read(sharedPrefsProvider);
    if (on) {
      if (!await Permission.contacts.request().isGranted) return false;
      await prefs.setBool(_kContacts(a.id), true);
      return syncAccount(a, force: true);
    }
    await prefs.setBool(_kContacts(a.id), false);
    await _invoke('remove', {'account': a.email, 'contacts': true, 'removeAccount': !calendarOn(a.id)});
    return true;
  }

  /// Включить/выключить календарь ящика в телефоне.
  Future<bool> setCalendar(AccountModel a, bool on) async {
    final prefs = _ref.read(sharedPrefsProvider);
    if (on) {
      if (!await Permission.calendarFullAccess.request().isGranted) return false;
      await prefs.setBool(_kCalendar(a.id), true);
      return syncAccount(a, force: true);
    }
    await prefs.setBool(_kCalendar(a.id), false);
    await _invoke('remove', {'account': a.email, 'calendar': true, 'removeAccount': !contactsOn(a.id)});
    return true;
  }

  /// Ящик удалён из приложения — убрать его данные из телефона.
  Future<void> forget(AccountModel a) async {
    final prefs = _ref.read(sharedPrefsProvider);
    if (!contactsOn(a.id) && !calendarOn(a.id)) return;
    await prefs.remove(_kContacts(a.id));
    await prefs.remove(_kCalendar(a.id));
    await _invoke('remove', {'account': a.email, 'removeAccount': true});
  }

  /// Обновить все ящики с включённой связью (после синхронизации).
  Future<void> syncAll() async {
    if (!isAvailable) return;
    final accounts = _ref.read(accountsProvider);
    // Список ящиков ещё не загружен — ничего не трогаем (иначе «лишними»
    // оказались бы все ящики в телефоне).
    if (accounts.isEmpty) return;
    final on =[for (final a in accounts) if (contactsOn(a.id) || calendarOn(a.id)) a];
    // Ящики, удалённые в обход приложения, — убрать из телефона.
    await _invoke('prune', {'keep': [for (final a in on) a.email]});
    for (final a in on) {
      await syncAccount(a);
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
    if (contactsOn(a.id)) {
      final items = await _contacts(db, a.id);
      final n = await _invoke('syncContacts', {'account': a.email, 'groupName': label, 'contacts': items});
      ok = ok && n != null;
      if (n is int && n > 0) AppLogger.info('В телефоне: контактов записано $n (${a.email})');
    }
    if (calendarOn(a.id)) {
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

// lib/services/archive/archive_settings.dart
// Настройки архивации в архив Ogneliss (1.7.3) и правило «какое письмо
// архивировать» — отдельно от выполнения, чтобы проверять тестами.
//
// По образцу автоархивации Outlook: письма старше N месяцев, раз в N дней.
// Решения владельца 25.10.2026: письма с флажком и «На контроле» по
// умолчанию НЕ архивируются (флажок в настройках); исходные письма после
// архивации — в «Удалённые» на сервере (18.10.2026, §5.1 ARCHIVE_IDEA).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' show Email;
import '../../data/models/folder_model.dart';
import '../../data/providers/shared_prefs_provider.dart';

class ArchiveSettings {
  /// Архивировать по расписанию (при работе приложения).
  final bool auto;

  /// Письма (встречи, выполненные задачи) старше стольких месяцев.
  final int months;

  /// Как часто: раз в столько дней.
  final int everyDays;

  /// Архивировать и письма с флажком и «На контроле».
  final bool includeFlagged;

  /// После архивации — исходное письмо в «Удалённые» на сервере. Выключено —
  /// в архив кладётся копия, письмо остаётся в ящике.
  final bool deleteFromServer;

  /// Только по Wi‑Fi (вложения писем скачиваются).
  final bool wifiOnly;

  final bool mail;
  final bool events;
  final bool tasks;
  final bool contacts;

  /// Ящики, которые не архивируются.
  final Set<String> skipAccounts;

  /// Сохранять в архив настройки приложения (ящики, настройки, подписи,
  /// заметки) — при каждой архивации.
  final bool appSettings;

  /// И пароли ящиков (архив зашифрован — на новом устройстве не нужно
  /// входить в ящики заново).
  final bool appSettingsSecrets;

  final DateTime? lastRun;

  const ArchiveSettings({
    this.auto = false,
    this.months = 6,
    this.everyDays = 14,
    this.includeFlagged = false,
    this.deleteFromServer = true,
    this.wifiOnly = true,
    this.mail = true,
    this.events = true,
    this.tasks = true,
    this.contacts = true,
    this.skipAccounts = const {},
    this.appSettings = true,
    this.appSettingsSecrets = true,
    this.lastRun,
  });

  static const monthOptions = [1, 3, 6, 12, 24, 36];
  static const dayOptions = [1, 7, 14, 30];

  /// Граница возраста: что старше — архивируется.
  DateTime cutoff(DateTime now) => DateTime(now.year, now.month - months, now.day, now.hour, now.minute);

  /// Пора ли архивировать по расписанию.
  bool due(DateTime now) => auto && (lastRun == null || now.difference(lastRun!) >= Duration(days: everyDays));
}

final archiveSettingsProvider =
    NotifierProvider<ArchiveSettingsNotifier, ArchiveSettings>(ArchiveSettingsNotifier.new);

class ArchiveSettingsNotifier extends Notifier<ArchiveSettings> {
  static const _p = 'ogna_set_';

  @override
  ArchiveSettings build() {
    final s = ref.read(sharedPrefsProvider);
    final last = s.getInt('${_p}last_run');
    return ArchiveSettings(
      auto: s.getBool('${_p}auto') ?? false,
      months: s.getInt('${_p}months') ?? 6,
      everyDays: s.getInt('${_p}every') ?? 14,
      includeFlagged: s.getBool('${_p}flagged') ?? false,
      deleteFromServer: s.getBool('${_p}delete') ?? true,
      wifiOnly: s.getBool('${_p}wifi') ?? true,
      mail: s.getBool('${_p}mail') ?? true,
      events: s.getBool('${_p}events') ?? true,
      tasks: s.getBool('${_p}tasks') ?? true,
      contacts: s.getBool('${_p}contacts') ?? true,
      skipAccounts: (s.getStringList('${_p}skip') ?? const []).toSet(),
      appSettings: s.getBool('${_p}app') ?? true,
      appSettingsSecrets: s.getBool('${_p}app_secrets') ?? true,
      lastRun: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  Future<void> _b(String k, bool v) => ref.read(sharedPrefsProvider).setBool('$_p$k', v);
  Future<void> _i(String k, int v) => ref.read(sharedPrefsProvider).setInt('$_p$k', v);

  ArchiveSettings _with({
    bool? auto,
    int? months,
    int? everyDays,
    bool? includeFlagged,
    bool? deleteFromServer,
    bool? wifiOnly,
    bool? mail,
    bool? events,
    bool? tasks,
    bool? contacts,
    Set<String>? skipAccounts,
    bool? appSettings,
    bool? appSettingsSecrets,
    DateTime? lastRun,
  }) =>
      ArchiveSettings(
        auto: auto ?? state.auto,
        months: months ?? state.months,
        everyDays: everyDays ?? state.everyDays,
        includeFlagged: includeFlagged ?? state.includeFlagged,
        deleteFromServer: deleteFromServer ?? state.deleteFromServer,
        wifiOnly: wifiOnly ?? state.wifiOnly,
        mail: mail ?? state.mail,
        events: events ?? state.events,
        tasks: tasks ?? state.tasks,
        contacts: contacts ?? state.contacts,
        skipAccounts: skipAccounts ?? state.skipAccounts,
        appSettings: appSettings ?? state.appSettings,
        appSettingsSecrets: appSettingsSecrets ?? state.appSettingsSecrets,
        lastRun: lastRun ?? state.lastRun,
      );

  Future<void> setAuto(bool v) async {
    state = _with(auto: v);
    await _b('auto', v);
  }

  Future<void> setMonths(int v) async {
    state = _with(months: v);
    await _i('months', v);
  }

  Future<void> setEveryDays(int v) async {
    state = _with(everyDays: v);
    await _i('every', v);
  }

  Future<void> setIncludeFlagged(bool v) async {
    state = _with(includeFlagged: v);
    await _b('flagged', v);
  }

  Future<void> setDeleteFromServer(bool v) async {
    state = _with(deleteFromServer: v);
    await _b('delete', v);
  }

  Future<void> setWifiOnly(bool v) async {
    state = _with(wifiOnly: v);
    await _b('wifi', v);
  }

  Future<void> setKind(String kind, bool v) async {
    state = switch (kind) {
      'mail' => _with(mail: v),
      'events' => _with(events: v),
      'tasks' => _with(tasks: v),
      _ => _with(contacts: v),
    };
    await _b(kind, v);
  }

  Future<void> setAppSettings(bool v) async {
    state = _with(appSettings: v);
    await _b('app', v);
  }

  Future<void> setAppSettingsSecrets(bool v) async {
    state = _with(appSettingsSecrets: v);
    await _b('app_secrets', v);
  }

  Future<void> setAccount(String accountId, bool archive) async {
    final next = {...state.skipAccounts};
    archive ? next.remove(accountId) : next.add(accountId);
    state = _with(skipAccounts: next);
    await ref.read(sharedPrefsProvider).setStringList('${_p}skip', next.toList());
  }

  Future<void> markRun(DateTime at) async {
    state = _with(lastRun: at);
    await ref.read(sharedPrefsProvider).setInt('${_p}last_run', at.millisecondsSinceEpoch);
  }
}

/// Какие письма, встречи и задачи архивируются.
abstract final class ArchiveRules {
  /// Папки, из которых архивируются письма. Черновики, исходящие, корзина и
  /// спам — нет (как у автоархивации Outlook: «Удалённые» не архивируются).
  static const mailFolders = {FolderType.inbox, FolderType.sent, FolderType.archive, FolderType.custom};

  /// Письмо есть только на телефоне (черновик приложения, быстрый ответ в
  /// очереди) — в архив не идёт.
  static bool deviceOnly(String emailId) => emailId.startsWith('draft-') || emailId.startsWith('qr_');

  /// Письмо «в работе»: флажок или «На контроле» (жду ответа / должен
  /// ответить). «Исполнено» (3) — уже не в работе.
  static bool active(Email e) => e.isFlagged || e.controlState == 1 || e.controlState == 2;

  /// Архивировать ли письмо при архивации «старше [cutoff]».
  /// [manual] — человек сам отправил письмо в архив: возраст и папка не
  /// проверяются (флажок и «На контроле» — тоже: выбор сделан явно).
  static bool mailEligible(
    Email e, {
    required FolderType? folderType,
    required DateTime cutoff,
    required bool includeFlagged,
    required DateTime now,
    bool manual = false,
  }) {
    if (deviceOnly(e.id) || e.isDraft) return false;
    if (manual) return true;
    if (folderType == null || !mailFolders.contains(folderType)) return false;
    if (!e.receivedAt.isBefore(cutoff)) return false;
    if (!includeFlagged && active(e)) return false;
    // «Посмотреть позже» и напоминания ещё впереди — письмо вернётся в
    // ленту, архивировать его рано.
    if (e.laterState != 0) return false;
    if (e.remindAt != null && e.remindAt!.isAfter(now)) return false;
    if (e.followUpAt != null && e.followUpAt!.isAfter(now)) return false;
    return true;
  }
}

// lib/services/security/managed_config.dart
//
// Управление со стороны организации через MDM (1.10.5, просьба владельца
// 03.11.2026). Настройки приходят от системы управления устройствами:
//   · Android — управляемые настройки Android Enterprise
//     (RestrictionsManager; список ключей — android/app/src/main/res/xml/
//     app_restrictions.xml, MdmBridge.kt);
//   · iPhone и iPad — Managed App Configuration (словарь
//     com.apple.configuration.managed в UserDefaults, AppDelegate.swift).
// Компьютеры MDM не поддерживают — политика пустая.
//
// Ключи и что они делают — docs/guides/MDM.md (для ИТ-службы). Политика
// дублируется в настройках телефона (prefs): её читают фоновые задачи и
// уведомления, где канала к нативу нет, и первый кадр до ответа натива.
// Политику сняли в MDM — копия очищается при следующем запуске или сразу,
// если приложение открыто.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/common/inline_notice.dart';

/// Ключи управляемых настроек — те же имена в app_restrictions.xml (Android)
/// и в конфигурации для iOS. Не менять: их вводят в консолях MDM.
class ManagedKeys {
  ManagedKeys._();

  // Организация
  static const orgName = 'org_name';
  static const supportContact = 'support_contact';

  // Ящик (заранее заполненный вход)
  static const accountEmail = 'account_email';
  static const accountProtocol = 'account_protocol'; // auto | exchange | imap (eas, ews — как exchange)
  static const accountServer = 'account_server';
  static const accountUsername = 'account_username';
  static const accountDomain = 'account_domain';
  static const imapServer = 'imap_server';
  static const imapPort = 'imap_port';
  static const smtpServer = 'smtp_server';
  static const smtpPort = 'smtp_port';
  static const allowedDomains = 'allowed_domains';

  // Защита
  static const requireAppLock = 'require_app_lock';
  static const minPinLength = 'min_pin_length';
  static const blockScreenshots = 'block_screenshots';
  static const blockShare = 'block_share';
  static const blockOpenIn = 'block_open_in';
  static const blockCopy = 'block_copy';
  static const hideNotificationContent = 'hide_notification_content';

  /// Погода в «Моём дне» — запрос к внешним сервисам (MET Norway,
  /// OpenStreetMap); 1.15.1.
  static const blockWeather = 'block_weather';

  static const all = [
    orgName, supportContact, accountEmail, accountProtocol, accountServer, accountUsername, accountDomain,
    imapServer, imapPort, smtpServer, smtpPort, allowedDomains, requireAppLock, minPinLength,
    blockScreenshots, blockShare, blockOpenIn, blockCopy, hideNotificationContent, blockWeather,
  ];
}

/// Что запрещает политика — для проверки в местах действий.
enum ManagedRule { share, openIn, copy }

@immutable
class ManagedPolicy {
  const ManagedPolicy({
    this.orgName,
    this.supportContact,
    this.accountEmail,
    this.accountProtocol,
    this.accountServer,
    this.accountUsername,
    this.accountDomain,
    this.imapServer,
    this.imapPort,
    this.smtpServer,
    this.smtpPort,
    this.allowedDomains = const [],
    this.requireAppLock = false,
    this.minPinLength = 4,
    this.blockScreenshots = false,
    this.blockShare = false,
    this.blockOpenIn = false,
    this.blockCopy = false,
    this.hideNotificationContent = false,
    this.blockWeather = false,
  });

  static const none = ManagedPolicy();

  final String? orgName;
  final String? supportContact;
  final String? accountEmail;
  final String? accountProtocol;
  final String? accountServer;
  final String? accountUsername;
  final String? accountDomain;
  final String? imapServer;
  final int? imapPort;
  final String? smtpServer;
  final int? smtpPort;

  /// Домены, ящики которых можно добавить (пусто — любые). Поддомены
  /// подходят: «example.ru» разрешает и «mail.example.ru».
  final List<String> allowedDomains;
  final bool requireAppLock;

  /// Длина PIN приложения: 4–6 (поле ввода рассчитано на 6 цифр).
  final int minPinLength;
  final bool blockScreenshots;

  /// «Поделиться», сохранить в файлы, PDF и печать — данные уходят из
  /// приложения.
  final bool blockShare;

  /// Открыть вложение в другом приложении.
  final bool blockOpenIn;

  /// Копировать текст писем (выделение и «Копировать»).
  final bool blockCopy;

  /// Уведомление без отправителя, темы и текста — «Новое сообщение».
  final bool hideNotificationContent;

  /// Погоды в «Моём дне» нет (запросы к внешним сервисам запрещены).
  final bool blockWeather;

  /// Организация задала хоть что-то.
  bool get isManaged => this != none;

  /// Ящик настроен организацией (вход заполнен заранее).
  bool get hasAccount => (accountEmail ?? '').contains('@');

  bool blocks(ManagedRule r) => switch (r) {
        ManagedRule.share => blockShare,
        ManagedRule.openIn => blockOpenIn,
        ManagedRule.copy => blockCopy,
      };

  /// Можно ли добавить ящик [email].
  bool allowsAccount(String email) {
    if (allowedDomains.isEmpty) return true;
    final at = email.lastIndexOf('@');
    if (at < 0) return false;
    final d = email.substring(at + 1).trim().toLowerCase();
    return allowedDomains.any((a) => d == a || d.endsWith('.$a'));
  }

  // ── Разбор: значения из Bundle (Android) и plist (iOS) ──

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  static bool _bool(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '${v ?? ''}'.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'да' || s == 'on';
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim());
  }

  static List<String> _domains(Object? v) {
    final parts = v is List ? [for (final x in v) '$x'] : '${v ?? ''}'.split(RegExp(r'[,;\s]+'));
    return [
      for (final p in parts)
        if (p.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase().contains('.'))
          p.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase(),
    ];
  }

  /// Протокол ящика: exchange — ActiveSync или EWS (какой — приложение
  /// выбирает само, как при обычном входе), imap — IMAP/SMTP.
  static String? _protocol(String? v) => switch (v) {
        'exchange' || 'eas' || 'ews' => 'exchange',
        'imap' => 'imap',
        'auto' => 'auto',
        _ => null,
      };

  factory ManagedPolicy.fromMap(Map<Object?, Object?>? m) {
    if (m == null || m.isEmpty) return none;
    Object? v(String k) => m[k];
    final proto = _str(v(ManagedKeys.accountProtocol))?.toLowerCase();
    final pin = _int(v(ManagedKeys.minPinLength));
    return ManagedPolicy(
      orgName: _str(v(ManagedKeys.orgName)),
      supportContact: _str(v(ManagedKeys.supportContact)),
      accountEmail: _str(v(ManagedKeys.accountEmail))?.toLowerCase(),
      accountProtocol: _protocol(proto),
      accountServer: _str(v(ManagedKeys.accountServer)),
      accountUsername: _str(v(ManagedKeys.accountUsername)),
      accountDomain: _str(v(ManagedKeys.accountDomain)),
      imapServer: _str(v(ManagedKeys.imapServer)),
      imapPort: _int(v(ManagedKeys.imapPort)),
      smtpServer: _str(v(ManagedKeys.smtpServer)),
      smtpPort: _int(v(ManagedKeys.smtpPort)),
      allowedDomains: _domains(v(ManagedKeys.allowedDomains)),
      requireAppLock: _bool(v(ManagedKeys.requireAppLock)),
      minPinLength: (pin ?? 4).clamp(4, 6),
      blockScreenshots: _bool(v(ManagedKeys.blockScreenshots)),
      blockShare: _bool(v(ManagedKeys.blockShare)),
      blockOpenIn: _bool(v(ManagedKeys.blockOpenIn)),
      blockCopy: _bool(v(ManagedKeys.blockCopy)),
      hideNotificationContent: _bool(v(ManagedKeys.hideNotificationContent)),
      blockWeather: _bool(v(ManagedKeys.blockWeather)),
    );
  }

  Map<String, Object?> toJson() => {
        if (orgName != null) ManagedKeys.orgName: orgName,
        if (supportContact != null) ManagedKeys.supportContact: supportContact,
        if (accountEmail != null) ManagedKeys.accountEmail: accountEmail,
        if (accountProtocol != null) ManagedKeys.accountProtocol: accountProtocol,
        if (accountServer != null) ManagedKeys.accountServer: accountServer,
        if (accountUsername != null) ManagedKeys.accountUsername: accountUsername,
        if (accountDomain != null) ManagedKeys.accountDomain: accountDomain,
        if (imapServer != null) ManagedKeys.imapServer: imapServer,
        if (imapPort != null) ManagedKeys.imapPort: imapPort,
        if (smtpServer != null) ManagedKeys.smtpServer: smtpServer,
        if (smtpPort != null) ManagedKeys.smtpPort: smtpPort,
        if (allowedDomains.isNotEmpty) ManagedKeys.allowedDomains: allowedDomains.join(','),
        if (requireAppLock) ManagedKeys.requireAppLock: true,
        if (minPinLength != 4) ManagedKeys.minPinLength: minPinLength,
        if (blockScreenshots) ManagedKeys.blockScreenshots: true,
        if (blockShare) ManagedKeys.blockShare: true,
        if (blockOpenIn) ManagedKeys.blockOpenIn: true,
        if (blockCopy) ManagedKeys.blockCopy: true,
        if (hideNotificationContent) ManagedKeys.hideNotificationContent: true,
        if (blockWeather) ManagedKeys.blockWeather: true,
      };

  @override
  bool operator ==(Object other) =>
      other is ManagedPolicy && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().entries.map((e) => Object.hash(e.key, e.value)));

  // ── Копия в prefs: фон, уведомления, первый кадр ──

  static const prefKey = 'mdm_policy_v1';

  static ManagedPolicy fromPrefs(SharedPreferences? p) {
    final raw = p?.getString(prefKey);
    if (raw == null || raw.isEmpty) return none;
    try {
      return ManagedPolicy.fromMap(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return none;
    }
  }

  /// Нынешняя политика — для кода без дерева виджетов (открыть файл,
  /// «Поделиться»). Обновляет [ManagedPolicyNotifier].
  static ManagedPolicy current = none;

  /// Список разрешённых доменов изменился (план 08.11.2026 п. 1): список
  /// ящиков перечитывается — `allowed_domains` действует и на добавленные.
  static final allowedDomainsChanged = ValueNotifier<int>(0);

  /// Действие запрещено политикой: строка «Запрещено организацией» вверху
  /// экрана; true — действие не выполнять.
  static bool deny(ManagedRule rule) {
    if (!current.blocks(rule)) return false;
    AppLogger.info('MDM: действие запрещено политикой (${rule.name})');
    unawaited(_showDenied());
    return true;
  }

  static String _lang = PlatformDispatcher.instance.locale.languageCode;

  /// Язык приложения — для строки запрета без дерева виджетов.
  static set language(String code) => _lang = code;

  static Future<void> _showDenied() async {
    try {
      final l10n = await AppLocalizations.load(_lang);
      showInlineError(l10n.tr('mdmBlocked'));
    } catch (_) {}
  }
}

/// Чтение управляемых настроек у натива и слежение за изменениями.
class ManagedConfigService {
  ManagedConfigService(this._prefs);

  final SharedPreferences _prefs;
  static const _channel = MethodChannel('ogneliss/mdm');

  static bool get supported => debugSupported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

  /// Для тестов: считать платформу поддерживающей MDM.
  @visibleForTesting
  static bool? debugSupported;

  /// Политика из MDM (сейчас); копия — в prefs.
  Future<ManagedPolicy> load() async {
    if (!supported) return _store(ManagedPolicy.none);
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('get');
      return _store(ManagedPolicy.fromMap(raw));
    } on MissingPluginException {
      return ManagedPolicy.fromPrefs(_prefs);
    } catch (e) {
      AppLogger.warning('MDM: настройки организации не прочитаны: $e');
      return ManagedPolicy.fromPrefs(_prefs);
    }
  }

  ManagedPolicy _store(ManagedPolicy p) {
    final prev = ManagedPolicy.fromPrefs(_prefs);
    if (p != prev) {
      if (p.isManaged) {
        unawaited(_prefs.setString(ManagedPolicy.prefKey, jsonEncode(p.toJson())));
        AppLogger.info('MDM: политика организации — ${p.toJson().keys.join(', ')}');
      } else {
        unawaited(_prefs.remove(ManagedPolicy.prefKey));
        if (prev.isManaged) AppLogger.info('MDM: политика организации снята');
      }
    }
    return p;
  }

  /// Натив сообщает об изменении настроек (MDM прислал новые).
  void listen(void Function() onChanged) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') onChanged();
      return null;
    });
  }

  /// Запрет снимков экрана (Android — FLAG_SECURE окна; iPhone такого
  /// запрета не даёт — там заслонка в списке недавних приложений).
  static Future<void> setSecureWindow(bool on) => secureFor('mdm', on);

  /// Причины запрета снимков: организация (MDM) и PIN приложения
  /// (08.11.2026, аудит безопасности: с PIN почта была видна в списке
  /// недавних приложений). Запрет действует, пока есть хоть одна причина.
  static final Set<String> _secureReasons = {};

  static Future<void> secureFor(String reason, bool on) async {
    final before = _secureReasons.isNotEmpty;
    if (on) {
      _secureReasons.add(reason);
    } else {
      _secureReasons.remove(reason);
    }
    final now = _secureReasons.isNotEmpty;
    if (now == before || kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await const MethodChannel('ogneliss/secure_window').invokeMethod<void>('setSecure', now);
    } catch (e) {
      AppLogger.debug('Запрет снимков экрана: $e');
    }
  }
}

class ManagedPolicyNotifier extends Notifier<ManagedPolicy> {
  late ManagedConfigService _svc;

  @override
  ManagedPolicy build() {
    final prefs = ref.watch(sharedPrefsProvider);
    _svc = ManagedConfigService(prefs);
    final cached = ManagedPolicy.fromPrefs(prefs);
    ManagedPolicy.current = cached;
    _svc.listen(() => unawaited(refresh()));
    unawaited(Future.microtask(refresh));
    return cached;
  }

  /// Запрет снимков уже выставлен окну (снимаем только свой).
  bool _secure = false;

  Future<void> refresh() async {
    final p = await _svc.load();
    final domainsChanged = !listEquals(ManagedPolicy.current.allowedDomains, p.allowedDomains);
    ManagedPolicy.current = p;
    if (domainsChanged) ManagedPolicy.allowedDomainsChanged.value++;
    if (p.blockScreenshots != _secure) {
      _secure = p.blockScreenshots;
      await ManagedConfigService.setSecureWindow(_secure);
    }
    if (p != state) state = p;
  }
}

final managedPolicyProvider = NotifierProvider<ManagedPolicyNotifier, ManagedPolicy>(ManagedPolicyNotifier.new);

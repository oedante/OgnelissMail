// lib/services/security/managed_feedback.dart
//
// Отчёт приложения для консоли MDM (2.2.0, план 08.11.2026 п. 1, запросы
// ИТ-служб): Android Enterprise «app feedback» — KeyedAppStates
// (androidx.enterprise:enterprise-feedback, Apache-2.0). Консоль показывает
// ИТ-службе, что настройки приняты, какие значения не распознаны, добавлен
// ли ящик организации и задан ли PIN приложения. На iPhone и iPad такого
// канала у Managed App Configuration нет.
//
// Тексты — по-английски (их читает ИТ-служба в консоли, не пользователь);
// адресов, имён и содержимого почты в отчёте нет.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/trusted_ca_store.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import 'managed_config.dart';
import 'pin_lock_service.dart' show pinLockProvider;

/// Важность записи (KeyedAppState.SEVERITY_INFO / SEVERITY_ERROR).
enum FeedbackSeverity { info, error }

@immutable
class FeedbackState {
  final String key;
  final FeedbackSeverity severity;
  final String message;
  final String? data;
  const FeedbackState(this.key, this.severity, this.message, [this.data]);

  /// Пределы KeyedAppState: ключ — 100 символов, текст и данные — 1000.
  Map<String, Object?> toMap() => {
        'key': _cut(key, 100),
        'severity': severity == FeedbackSeverity.error ? 2 : 1,
        'message': _cut(message, 1000),
        if (data != null) 'data': _cut(data!, 1000),
      };

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

  @override
  bool operator ==(Object other) =>
      other is FeedbackState &&
      other.key == key &&
      other.severity == severity &&
      other.message == message &&
      other.data == data;

  @override
  int get hashCode => Object.hash(key, severity, message, data);

  @override
  String toString() => '$key[${severity.name}]: $message';
}

const _boolKeys = {
  ManagedKeys.requireAppLock, ManagedKeys.blockScreenshots, ManagedKeys.blockShare, ManagedKeys.blockOpenIn,
  ManagedKeys.blockCopy, ManagedKeys.hideNotificationContent, ManagedKeys.blockWeather,
  ManagedKeys.blockAttachmentDownload, ManagedKeys.allowBiometrics, ManagedKeys.blockExternalServices,
  ManagedKeys.accountLocked, ManagedKeys.requireTls, ManagedKeys.allowUserCertTrust,
  ManagedKeys.blockDeviceContacts, ManagedKeys.blockDeviceCalendar,
};

const _boolWords = {'true', 'false', '1', '0', 'yes', 'no', 'да', 'нет', 'on', 'off'};

bool _isBool(Object? v) => v is bool || v is num || _boolWords.contains('$v'.trim().toLowerCase());

int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));

/// Что сообщить консоли: [raw] — настройки, как их прислал MDM; [policy] —
/// разобранные; [pinSet] и [accountAdded] — состояние на устройстве.
List<FeedbackState> managedFeedback(
  Map<Object?, Object?> raw,
  ManagedPolicy policy, {
  required bool pinSet,
  required bool accountAdded,
}) {
  final out = <FeedbackState>[];
  String? str(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  void bad(String key, String message) => out.add(FeedbackState(key, FeedbackSeverity.error, message));

  final known = <String>[
    for (final k in raw.keys)
      if (ManagedKeys.all.contains('$k') && raw[k] != null) '$k',
  ]..sort();
  final unknown = <String>[
    for (final k in raw.keys)
      if (!ManagedKeys.all.contains('$k')) '$k',
  ]..sort();
  out.add(FeedbackState('policy', FeedbackSeverity.info,
      'Managed configuration applied: ${known.length} key(s)', known.join(',')));
  if (unknown.isNotEmpty) {
    out.add(FeedbackState('unknown_keys', FeedbackSeverity.error,
        'Unknown keys ignored: ${unknown.join(', ')}', unknown.join(',')));
  }

  for (final k in _boolKeys) {
    if (raw[k] != null && !_isBool(raw[k])) bad(k, 'Not a boolean: "${raw[k]}" — treated as false');
  }

  void range(String k, int min, int max, String fallback) {
    if (raw[k] == null) return;
    final n = _int(raw[k]);
    if (n == null || n < min || n > max) bad(k, 'Must be $min–$max, got "${raw[k]}" — $fallback');
  }

  range(ManagedKeys.minPinLength, 4, 6, 'using ${policy.minPinLength}');
  range(ManagedKeys.pinTimeoutMinutes, 0, 60,
      policy.pinTimeoutMinutes == null ? 'not applied' : 'using ${policy.pinTimeoutMinutes}');
  range(ManagedKeys.maxSyncDays, 0, 3650, policy.maxSyncDays == null ? 'no limit' : 'using ${policy.maxSyncDays}');
  range(ManagedKeys.imapPort, 1, 65535, 'default port used');
  range(ManagedKeys.smtpPort, 1, 65535, 'default port used');

  final proto = str(ManagedKeys.accountProtocol)?.toLowerCase();
  if (proto != null && policy.accountProtocol == null) {
    bad(ManagedKeys.accountProtocol, 'Unknown value "$proto" (auto, exchange, imap) — ignored');
  }
  final transport = str(ManagedKeys.accountTransport)?.toLowerCase();
  if (transport != null && transport != 'auto' && policy.accountTransport == null) {
    bad(ManagedKeys.accountTransport, 'Unknown value "$transport" (auto, eas, ews) — ignored');
  }

  final email = str(ManagedKeys.accountEmail);
  // Подстановка консоли не раскрылась ($EMAIL$, {{mail}}) — адрес без «@».
  if (email != null && !policy.hasAccount) {
    bad(ManagedKeys.accountEmail, 'Not an email address (unexpanded variable?) — ignored');
  }
  if (str(ManagedKeys.allowedDomains) != null && policy.allowedDomains.isEmpty) {
    bad(ManagedKeys.allowedDomains, 'No valid domains — any domain allowed');
  }
  if (policy.hasAccount && policy.allowedDomains.isNotEmpty && !policy.allowsAccount(policy.accountEmail!)) {
    bad(ManagedKeys.allowedDomains, 'The account_email domain is not in allowed_domains — the mailbox cannot be added');
  }
  if (policy.accountLocked && !policy.hasAccount) {
    bad(ManagedKeys.accountLocked, 'Needs account_email — nothing locked');
  }

  final pem = str(ManagedKeys.trustedCaPem);
  if (pem != null) {
    final blocks = RegExp('-----BEGIN CERTIFICATE-----').allMatches(pem).length;
    final parsed = TrustedCaStore.parsePemList(pem).length;
    if (parsed == 0) {
      bad(ManagedKeys.trustedCaPem, 'No valid PEM certificates — none trusted');
    } else if (parsed < blocks) {
      bad(ManagedKeys.trustedCaPem, '${blocks - parsed} of $blocks certificate(s) could not be read');
    } else {
      out.add(FeedbackState(ManagedKeys.trustedCaPem, FeedbackSeverity.info, 'Trusted organization CAs: $parsed'));
    }
  }

  if (policy.hasAccount) {
    out.add(FeedbackState('account', FeedbackSeverity.info,
        accountAdded ? 'Organization mailbox is set up' : 'Organization mailbox is not set up yet',
        accountAdded ? 'added' : 'missing'));
  }
  if (policy.requireAppLock) {
    out.add(FeedbackState('app_lock', FeedbackSeverity.info,
        pinSet ? 'App PIN is set' : 'App PIN is not set yet — required when the app is opened',
        pinSet ? 'set' : 'missing'));
  }
  return out;
}

/// Отправка отчёта: при изменении политики, ящиков и PIN — с паузой, только
/// изменившийся, только на Android под управлением MDM.
class ManagedFeedbackReporter {
  ManagedFeedbackReporter(this._ref);
  final Ref _ref;

  static const _channel = MethodChannel('ogneliss/mdm');
  Timer? _debounce;
  String? _lastSent;

  @visibleForTesting
  static bool? debugSupported;

  static bool get _supported => debugSupported ?? (!kIsWeb && Platform.isAndroid);

  void start() {
    if (!_supported) return;
    _ref.listen(managedPolicyProvider, (_, _) => _schedule(), fireImmediately: true);
    _ref.listen(accountsProvider, (_, _) => _schedule());
    _ref.listen(pinLockProvider.select((s) => s.isPinSet), (_, _) => _schedule());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => unawaited(_send()));
  }

  Future<void> _send() async {
    final raw = ManagedConfigService.lastRaw;
    final policy = ManagedPolicy.current;
    // Не управляется — отчитываться некому.
    if (raw.isEmpty || !policy.isManaged) return;
    final email = policy.accountEmail;
    final states = managedFeedback(
      raw,
      policy,
      pinSet: _ref.read(pinLockProvider).isPinSet,
      accountAdded: email != null && _ref.read(accountsProvider).any((a) => a.email.trim().toLowerCase() == email),
    );
    final payload = [for (final s in states) s.toMap()];
    final json = jsonEncode(payload);
    if (json == _lastSent) return;
    try {
      await _channel.invokeMethod<void>('report', payload);
      _lastSent = json;
      AppLogger.info('MDM: отчёт консоли — ${states.length} записей'
          '${states.any((s) => s.severity == FeedbackSeverity.error) ? ' (есть ошибки настроек)' : ''}');
    } on MissingPluginException {
      // Старая сборка без канала — молча.
    } catch (e) {
      AppLogger.warning('MDM: отчёт консоли не отправлен: $e');
    }
  }

  void dispose() => _debounce?.cancel();
}

final managedFeedbackProvider = Provider<ManagedFeedbackReporter>((ref) {
  final r = ManagedFeedbackReporter(ref)..start();
  ref.onDispose(r.dispose);
  return r;
});

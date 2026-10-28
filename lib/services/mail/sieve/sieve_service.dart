// lib/services/mail/sieve/sieve_service.dart
// Фильтры на сервере IMAP (Sieve): прочитать правила ящика и записать.
//
// Только ящики IMAP с паролем: у Gmail, Яндекса, Mail.ru, Outlook.com
// ManageSieve нет. Сервер — тот же, что IMAP, порт 4190; другой адрес или
// порт задаётся на экране фильтров и хранится в настройках телефона.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/certificate_pinning_bridge.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import 'managesieve_client.dart';
import 'sieve_rules.dart';

/// Состояние фильтров ящика.
class SieveState {
  /// Имя скрипта, где лежат правила (активный или «ogneliss»).
  final String scriptName;

  /// Активный скрипт на сервере уже есть.
  final bool hasActive;

  final List<SieveRule> rules;
  final SieveScriptParts parts;

  /// Текст скрипта целиком (как на сервере).
  final String script;

  /// Расширения Sieve сервера.
  final Set<String> extensions;

  /// Сервер и порт, к которым подключались.
  final String host;
  final int port;

  const SieveState({
    required this.scriptName,
    required this.hasActive,
    required this.rules,
    required this.parts,
    required this.script,
    required this.extensions,
    required this.host,
    required this.port,
  });
}

final sieveServiceProvider = Provider<SieveService>(
    (ref) => SieveService(ref.watch(secureStorageProvider), ref.watch(sharedPrefsProvider)));

class SieveService {
  final SecureStorageService _storage;
  final SharedPreferences _prefs;
  SieveService(this._storage, this._prefs);

  /// Ящики, где Sieve возможен.
  static bool supports(AccountModel a) => a.isActive && a.isImap && !a.isOAuth;

  String hostOf(AccountModel a) {
    final saved = _prefs.getString('sieve_host_${a.id}')?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    final imap = a.imapServer?.trim() ?? '';
    if (imap.isNotEmpty) return imap;
    return (AppConstants.serverConfigForEmail(a.email)?['imap'] as String?) ?? 'imap.${a.email.split('@').last}';
  }

  int portOf(AccountModel a) => _prefs.getInt('sieve_port_${a.id}') ?? 4190;

  Future<void> setServer(AccountModel a, String host, int port) async {
    await _prefs.setString('sieve_host_${a.id}', host.trim());
    await _prefs.setInt('sieve_port_${a.id}', port);
  }

  Future<T> _session<T>(AccountModel a, Future<T> Function(ManageSieveClient c) body) async {
    final host = hostOf(a);
    final port = portOf(a);
    final password = await _storage.getAccountPassword(a.id);
    if (password == null) throw const SieveException('no password', code: 'NO-PASSWORD');
    final c = ManageSieveClient(
      host: host,
      port: port,
      onBadCertificate: (cert) => CertificatePinningBridge.instance?.evaluate(cert, host, port) ?? false,
    );
    try {
      await c.connect(a.username.isNotEmpty ? a.username : a.email, password);
      return await body(c);
    } finally {
      unawaited(c.logout());
    }
  }

  /// Прочитать правила.
  Future<SieveState> load(AccountModel a) => _session(a, (c) async {
        final scripts = await c.listScripts();
        final active = scripts.where((s) => s.active).firstOrNull;
        final name = active?.name ?? SieveRules.defaultScriptName;
        final exists = scripts.any((s) => s.name == name);
        final text = exists ? await c.getScript(name) : '';
        final parts = SieveRules.parse(text);
        AppLogger.info('Sieve ${a.email}: скриптов ${scripts.length}, активный «${active?.name ?? '—'}», '
            'наших правил ${parts.rules.length}');
        return SieveState(
          scriptName: name,
          hasActive: active != null,
          rules: parts.rules,
          parts: parts,
          script: text,
          extensions: c.extensions,
          host: c.host,
          port: c.port,
        );
      });

  /// Записать правила в скрипт (остальное содержимое скрипта сохраняется).
  /// Возвращает новый текст скрипта.
  Future<String> saveRules(AccountModel a, SieveState st, List<SieveRule> rules) => _session(a, (c) async {
        // Перечитать: скрипт могли изменить в веб-почте, пока открыт экран.
        final scripts = await c.listScripts();
        final active = scripts.where((s) => s.active).firstOrNull;
        final name = active?.name ?? st.scriptName;
        final current = scripts.any((s) => s.name == name) ? await c.getScript(name) : '';
        final text = SieveRules.build(rules, SieveRules.parse(current).foreign, c.extensions);
        await c.putScript(name, text);
        if (active == null) await c.setActive(name);
        AppLogger.info('Sieve ${a.email}: записано правил ${rules.length} в «$name»');
        return text;
      });

  /// Записать скрипт целиком (правка вручную).
  Future<void> saveRaw(AccountModel a, String name, String text, {bool activate = false}) =>
      _session(a, (c) async {
        await c.putScript(name, text);
        if (activate) await c.setActive(name);
      });
}

// lib/src/engine_factory.dart
// Фабрика: создаёт движок и выполняет автоопределение для Exchange.
// Единый DebugLog прокидывается во все движки — весь обмен в одном логе.

import 'package:http/http.dart' as http;
import 'debug_log.dart';
import 'mail_engine.dart';
import 'models/models.dart';
import 'transport/eas_engine.dart';
import 'transport/ews_engine.dart';
import 'transport/imap_smtp_engine.dart';

class EngineFactory {
  /// Подключиться, выбрав транспорт. Возвращает (движок, результат).
  /// [logger] — общий подробный лог (если null, создаётся новый verbose).
  static Future<(MailEngine?, ConnectResult)> connect(AccountConfig cfg, {DebugLog? logger, http.Client? httpClient}) async {
    final log = logger ?? DebugLog(verbose: true, echo: true);

    if (cfg.forceTransport != null) {
      log.info('AUTO', 'Принудительный транспорт: ${cfg.forceTransport!.name}');
      final engine = _create(cfg.forceTransport!, log, httpClient);
      final res = await engine.connect(cfg);
      return (res.success ? engine : null, res);
    }

    if (cfg.authKind == AuthKind.oauth2 || cfg.imapHost != null) {
      log.info('AUTO', 'OAuth/IMAP — транспорт IMAP/SMTP');
      final engine = ImapSmtpEngine(logger: log);
      final res = await engine.connect(cfg);
      return (res.success ? engine : null, res);
    }

    // Профиль «Почта iPhone» (1.6.17): только ActiveSync, как у Почты iOS.
    // EWS не опрашивается: за шлюзом ServicePipe каждый POST к EWS получал 403,
    // и эти отказы с того же адреса шли прямо перед входом по ActiveSync.
    if (cfg.appleMailProfile) {
      log.info('AUTO', 'Профиль «Почта iPhone»: только ActiveSync (EWS не опрашивается)');
      final eas = EasEngine(logger: log, httpClient: httpClient);
      final res = await eas.connect(cfg);
      return (res.success ? eas : null, res);
    }

    // Exchange-автоопределение: EWS → EAS.
    log.info('AUTO', 'Exchange: пробуем EWS, затем EAS');
    final ews = EwsEngine(logger: log, httpClient: httpClient);
    final ewsRes = await ews.connect(cfg);
    if (ewsRes.success) {
      log.info('AUTO', 'Выбран транспорт: EWS');
      return (ews, ewsRes);
    }
    log.info('AUTO', 'EWS недоступен (${ewsRes.error}) → пробуем EAS');

    final eas = EasEngine(logger: log, httpClient: httpClient);
    final easRes = await eas.connect(cfg);
    if (easRes.success) {
      log.info('AUTO', 'Выбран транспорт: EAS');
      return (eas, easRes);
    }

    log.error('AUTO', 'Exchange недоступен: EWS=${ewsRes.error}, EAS=${easRes.error}');
    return (null, ConnectResult(
      success: false,
      error: 'Exchange недоступен: EWS (${ewsRes.error}), EAS (${easRes.error})',
      log: [log.dump()],
    ));
  }

  static MailEngine _create(MailTransportKind kind, DebugLog log, http.Client? httpClient) {
    switch (kind) {
      case MailTransportKind.eas:
        return EasEngine(logger: log, httpClient: httpClient);
      case MailTransportKind.ews:
        return EwsEngine(logger: log, httpClient: httpClient);
      case MailTransportKind.imapSmtp:
        return ImapSmtpEngine(logger: log);
    }
  }
}

// lib/services/mail/mail_provider_detect.dart
// Почта по адресу (1.8.0, п. 6 плана: «адрес почты первым, тип ящика по
// домену»). Человек вводит только адрес — приложение само выбирает способ
// входа: Google, Microsoft и Яндекс — страница входа службы с уже
// подставленным адресом, Mail.ru и iCloud — пароль приложения, известные
// почтовые службы — IMAP с готовыми серверами, рабочая почта — Exchange.
//
// Известные домены узнаются сразу. Для остальных — короткая проверка без
// учётных данных (не дольше нескольких секунд):
//  · настройки почты на сервере самого домена (autoconfig —
//    autoconfig.<домен>/mail/config-v1.1.xml и
//    <домен>/.well-known/autoconfig/mail/config-v1.1.xml);
//  · имена в DNS устройства: autodiscover.<домен> (Exchange), imap.<домен>,
//    smtp.<домен>, mail.<домен>, узел почты Microsoft 365 для домена
//    (<домен-через-дефисы>.mail.protection.outlook.com).
// Адрес и домен не уходят посторонним службам — только DNS устройства и
// сервер самого домена. Узнать не удалось — Exchange с выбором «Другой
// способ» (приложение — прежде всего для рабочей почты).

import 'dart:async';
import 'dart:io' show InternetAddress;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/account_model.dart' show EncryptionType;

/// Способ входа.
enum MailKind {
  /// Exchange (EWS и ActiveSync): пароль, сервер — автообнаружение.
  exchange,
  /// Google (Gmail и Google Workspace): страница входа Google.
  google,
  /// Microsoft (Outlook.com, Hotmail, Live, Microsoft 365): страница входа Microsoft.
  microsoft,
  /// Яндекс: страница входа Яндекса.
  yandex,
  /// Mail.ru: пароль для внешнего приложения.
  mailru,
  /// iCloud: пароль приложения Apple.
  icloud,
  /// Любая другая почта по IMAP и SMTP.
  imap,
}

/// Серверы IMAP и SMTP.
class ImapPreset {
  final String imapHost;
  final int imapPort;
  final EncryptionType imapEncryption;
  final String smtpHost;
  final int smtpPort;
  final EncryptionType smtpEncryption;

  const ImapPreset({
    required this.imapHost,
    required this.imapPort,
    required this.imapEncryption,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpEncryption,
  });

  /// Шифрование по стандартному порту.
  static EncryptionType imapEncryptionFor(int port) =>
      port == 143 ? EncryptionType.starttls : EncryptionType.ssl;
  static EncryptionType smtpEncryptionFor(int port) =>
      port == 465 ? EncryptionType.ssl : (port == 25 ? EncryptionType.none : EncryptionType.starttls);

  /// Из таблицы известных служб ([AppConstants.imapServers]).
  static ImapPreset? fromTable(Map<String, dynamic>? cfg) {
    if (cfg == null) return null;
    final imap = cfg['imap'] as String?;
    final smtp = cfg['smtp'] as String?;
    if (imap == null || smtp == null) return null;
    final ip = (cfg['imapPort'] as int?) ?? 993;
    final sp = (cfg['smtpPort'] as int?) ?? 587;
    return ImapPreset(
      imapHost: imap,
      imapPort: ip,
      imapEncryption: imapEncryptionFor(ip),
      smtpHost: smtp,
      smtpPort: sp,
      smtpEncryption: smtpEncryptionFor(sp),
    );
  }

  @override
  String toString() => 'IMAP $imapHost:$imapPort ${imapEncryption.name}, SMTP $smtpHost:$smtpPort ${smtpEncryption.name}';
}

/// Что узнали по адресу.
class MailGuess {
  final MailKind kind;

  /// Узнали уверенно (известный домен, настройки на сервере домена, узел
  /// Microsoft 365). Иначе — догадка: экран входа предлагает выбрать тип.
  final bool sure;

  /// Серверы IMAP и SMTP (для [MailKind.imap]).
  final ImapPreset? imap;

  /// Служба принимает только пароль приложения (Yahoo, AOL, iCloud,
  /// Mail.ru, QQ…) — подсказка у поля пароля.
  final bool appPassword;

  /// Домен — на Microsoft 365 (не Outlook.com): подпись «Microsoft 365».
  final bool microsoft365;

  const MailGuess(
    this.kind, {
    this.sure = true,
    this.imap,
    this.appPassword = false,
    this.microsoft365 = false,
  });

  @override
  String toString() => 'MailGuess(${kind.name}${sure ? '' : ', догадка'}${imap != null ? ', $imap' : ''}'
      '${appPassword ? ', пароль приложения' : ''}${microsoft365 ? ', Microsoft 365' : ''})';
}

typedef HostResolver = Future<bool> Function(String host);
typedef TextFetcher = Future<String?> Function(Uri url);

class MailProviderDetect {
  MailProviderDetect._();

  static const _google = {'gmail.com', 'googlemail.com'};
  static const _yandex = {
    'yandex.ru', 'ya.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua', 'yandex.uz', 'yandex.com.tr',
    'narod.ru',
  };
  static const _mailru = {'mail.ru', 'bk.ru', 'inbox.ru', 'list.ru', 'internet.ru'};
  static const _icloud = {'icloud.com', 'me.com', 'mac.com'};

  /// Outlook.com и его старые домены: outlook.com, hotmail.co.uk, live.fr,
  /// msn.com…
  static final _microsoft = RegExp(r'^(outlook|hotmail|live)\.(com|[a-z]{2}|co\.[a-z]{2}|com\.[a-z]{2})$');

  /// Службы, которые пускают сторонние программы только по паролю
  /// приложения.
  static const _appPasswordDomains = {
    'yahoo.com', 'ymail.com', 'rocketmail.com', 'aol.com', 'qq.com', 'foxmail.com',
    '163.com', '126.com', 'yeah.net', 'yahoo.co.jp', 'gmx.net', 'gmx.de', 'gmx.at', 'gmx.ch',
    'gmx.com', 'web.de',
  };

  /// Домен адреса (строчными) или null.
  static String? domainOf(String email) {
    final e = email.trim().toLowerCase();
    final at = e.lastIndexOf('@');
    if (at <= 0 || at == e.length - 1) return null;
    final d = e.substring(at + 1);
    if (!d.contains('.') || d.startsWith('.') || d.endsWith('.') || d.contains('..')) return null;
    if (!RegExp(r'^[a-z0-9.\-]+$').hasMatch(d)) return null;
    return d;
  }

  /// Известный домен — сразу, без сети. null — домен не известен.
  static MailGuess? byDomain(String email) {
    final d = domainOf(email);
    if (d == null) return null;
    if (_google.contains(d)) return const MailGuess(MailKind.google);
    if (_microsoft.hasMatch(d) || d == 'msn.com' || d == 'office365.com') return const MailGuess(MailKind.microsoft);
    if (_yandex.contains(d)) return const MailGuess(MailKind.yandex);
    if (_mailru.contains(d)) return const MailGuess(MailKind.mailru, appPassword: true);
    if (_icloud.contains(d)) return const MailGuess(MailKind.icloud, appPassword: true);
    final preset = ImapPreset.fromTable(AppConstants.imapServers[d]);
    if (preset != null) {
      return MailGuess(MailKind.imap,
          imap: preset, appPassword: _appPasswordDomains.contains(d) || d.startsWith('yahoo.'));
    }
    if (d.startsWith('yahoo.')) {
      return const MailGuess(MailKind.imap,
          appPassword: true,
          imap: ImapPreset(
            imapHost: 'imap.mail.yahoo.com',
            imapPort: 993,
            imapEncryption: EncryptionType.ssl,
            smtpHost: 'smtp.mail.yahoo.com',
            smtpPort: 465,
            smtpEncryption: EncryptionType.ssl,
          ));
    }
    return null;
  }

  /// Страница службы, где создают пароль приложения (null — не знаем).
  static String? appPasswordUrl(String email) {
    final d = domainOf(email);
    if (d == null) return null;
    if (_mailru.contains(d)) return 'https://account.mail.ru/user/2-step-auth/passwords/';
    if (_icloud.contains(d)) return 'https://account.apple.com/account/manage';
    if (_yandex.contains(d)) return 'https://id.yandex.ru/security/app-passwords';
    if (_google.contains(d)) return 'https://myaccount.google.com/apppasswords';
    if (d.startsWith('yahoo.') || d == 'ymail.com' || d == 'rocketmail.com') {
      return 'https://login.yahoo.com/account/security';
    }
    if (d == 'aol.com') return 'https://login.aol.com/account/security';
    return null;
  }

  /// Где у службы включают доступ почтовых программ (IMAP).
  static String? imapSettingsUrl(String email) {
    final d = domainOf(email);
    if (d == null) return null;
    if (_yandex.contains(d)) return 'https://mail.yandex.ru/#setup/client';
    if (_mailru.contains(d)) return 'https://e.mail.ru/settings/security';
    return null;
  }

  /// Узнать способ входа по адресу. Известный домен — сразу; иначе —
  /// проверка не дольше [timeout]. Ошибок не бросает: не узнали — Exchange
  /// с `sure: false`. [resolve] и [fetch] — подмена сети в тестах.
  static Future<MailGuess> detect(
    String email, {
    Duration timeout = const Duration(seconds: 5),
    HostResolver? resolve,
    TextFetcher? fetch,
  }) async {
    final known = byDomain(email);
    if (known != null) return known;
    final d = domainOf(email);
    if (d == null || (kIsWeb && resolve == null)) return const MailGuess(MailKind.exchange, sure: false);
    final res = resolve ?? _resolve;
    final get = fetch ?? _fetch;
    try {
      return await _probe(d, res, get).timeout(timeout,
          onTimeout: () => const MailGuess(MailKind.exchange, sure: false));
    } catch (e) {
      AppLogger.info('Почта по адресу: проверка $d не удалась — $e');
      return const MailGuess(MailKind.exchange, sure: false);
    }
  }

  static Future<MailGuess> _probe(String d, HostResolver res, TextFetcher get) async {
    Future<bool> safe(String host) async {
      try {
        return await res(host).timeout(const Duration(seconds: 3), onTimeout: () => false);
      } catch (_) {
        return false;
      }
    }

    final dashed = d.replaceAll('.', '-');
    final undashed = d.replaceAll('-', '').replaceAll('.', '-');
    // Случайное имя в той же зоне: если оно тоже находится, зона отвечает
    // на любые имена и узел Microsoft 365 ничего не доказывает.
    final probe = 'ogn${Random().nextInt(1 << 30).toRadixString(36)}-check';
    final results = await Future.wait<Object?>([
      autoconfig(d, get),
      safe('autodiscover.$d'),
      safe('imap.$d'),
      safe('smtp.$d'),
      safe('mail.$d'),
      safe('$dashed.mail.protection.outlook.com'),
      if (undashed != dashed) safe('$undashed.mail.protection.outlook.com') else Future.value(false),
      safe('$probe.mail.protection.outlook.com'),
    ]);
    final cfg = results[0] as ImapPreset?;
    final autodiscover = results[1] as bool;
    final imap = results[2] as bool;
    final smtp = results[3] as bool;
    final mail = results[4] as bool;
    final m365 = ((results[5] as bool) || (results[6] as bool)) && !(results[7] as bool);
    final guess = decide(
      domain: d,
      autoconfig: cfg,
      autodiscover: autodiscover,
      imap: imap,
      smtp: smtp,
      mail: mail,
      microsoft365: m365,
    );
    AppLogger.info('Почта по адресу: $d → $guess');
    return guess;
  }

  /// Решение по результатам проверки (отдельно — для тестов).
  @visibleForTesting
  static MailGuess decide({
    required String domain,
    ImapPreset? autoconfig,
    bool autodiscover = false,
    bool imap = false,
    bool smtp = false,
    bool mail = false,
    bool microsoft365 = false,
  }) {
    // Почта домена — у Microsoft 365: вход через Microsoft.
    if (microsoft365) return const MailGuess(MailKind.microsoft, microsoft365: true);
    // Сервер домена сам сообщил настройки IMAP.
    if (autoconfig != null) {
      // Gmail и Яндекс на своём домене публикуют свои серверы — вход
      // через страницу службы надёжнее пароля.
      final h = autoconfig.imapHost.toLowerCase();
      if (h.endsWith('.gmail.com') || h.endsWith('.googlemail.com')) return const MailGuess(MailKind.google);
      if (h.endsWith('.yandex.ru') || h.endsWith('.yandex.com') || h.endsWith('.yandex.net')) {
        return const MailGuess(MailKind.yandex);
      }
      if (h.endsWith('.office365.com') || h.endsWith('.outlook.com')) {
        return const MailGuess(MailKind.microsoft, microsoft365: true);
      }
      return MailGuess(MailKind.imap, imap: autoconfig);
    }
    // Есть autodiscover — почти наверняка Exchange.
    if (autodiscover) return const MailGuess(MailKind.exchange);
    // Есть imap.<домен> — IMAP; SMTP — smtp.<домен> или тот же узел.
    if (imap) {
      return MailGuess(MailKind.imap,
          sure: false,
          imap: ImapPreset(
            imapHost: 'imap.$domain',
            imapPort: 993,
            imapEncryption: EncryptionType.ssl,
            smtpHost: smtp ? 'smtp.$domain' : (mail ? 'mail.$domain' : 'imap.$domain'),
            smtpPort: 587,
            smtpEncryption: EncryptionType.starttls,
          ));
    }
    // mail.<домен> есть у Exchange (Outlook в браузере) и у IMAP — не знаем.
    return const MailGuess(MailKind.exchange, sure: false);
  }

  /// Настройки IMAP с сервера домена (формат autoconfig Thunderbird).
  @visibleForTesting
  static Future<ImapPreset?> autoconfig(String domain, TextFetcher get) async {
    final urls = [
      Uri.parse('https://autoconfig.$domain/mail/config-v1.1.xml'),
      Uri.parse('https://$domain/.well-known/autoconfig/mail/config-v1.1.xml'),
    ];
    for (final u in urls) {
      try {
        final body = await get(u).timeout(const Duration(seconds: 4), onTimeout: () => null);
        if (body == null || body.isEmpty) continue;
        final p = parseAutoconfig(body, domain);
        if (p != null) return p;
      } catch (_) {
        // Нет сервера, нет сертификата, не XML — следующий адрес.
      }
    }
    return null;
  }

  /// Разбор config-v1.1.xml: первый сервер IMAP и первый SMTP.
  @visibleForTesting
  static ImapPreset? parseAutoconfig(String xml, String domain) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (_) {
      return null;
    }
    String sub(String v) => v
        .replaceAll('%EMAILDOMAIN%', domain)
        .replaceAll('%EMAILLOCALPART%', '')
        .trim()
        .toLowerCase();
    XmlElement? server(String tag, String type) {
      for (final e in doc.findAllElements(tag)) {
        if ((e.getAttribute('type') ?? '').toLowerCase() == type) return e;
      }
      return null;
    }

    String? text(XmlElement e, String name) {
      final n = e.findElements(name).firstOrNull;
      final t = n?.innerText.trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    EncryptionType enc(String? socket, EncryptionType fallback) => switch ((socket ?? '').toUpperCase()) {
          'SSL' => EncryptionType.ssl,
          'STARTTLS' => EncryptionType.starttls,
          'PLAIN' => EncryptionType.none,
          _ => fallback,
        };

    final inc = server('incomingServer', 'imap');
    final out = server('outgoingServer', 'smtp');
    if (inc == null || out == null) return null;
    final ih = text(inc, 'hostname');
    final oh = text(out, 'hostname');
    if (ih == null || oh == null) return null;
    final ip = int.tryParse(text(inc, 'port') ?? '') ?? 993;
    final op = int.tryParse(text(out, 'port') ?? '') ?? 587;
    final imapHost = sub(ih);
    final smtpHost = sub(oh);
    final hostOk = RegExp(r'^[a-z0-9.\-]+$');
    if (!hostOk.hasMatch(imapHost) || !hostOk.hasMatch(smtpHost)) return null;
    return ImapPreset(
      imapHost: imapHost,
      imapPort: ip,
      imapEncryption: enc(text(inc, 'socketType'), ImapPreset.imapEncryptionFor(ip)),
      smtpHost: smtpHost,
      smtpPort: op,
      smtpEncryption: enc(text(out, 'socketType'), ImapPreset.smtpEncryptionFor(op)),
    );
  }

  static Future<bool> _resolve(String host) async {
    final r = await InternetAddress.lookup(host);
    return r.isNotEmpty;
  }

  static Future<String?> _fetch(Uri url) async {
    final client = http.Client();
    try {
      final r = await client.get(url, headers: const {'Accept': 'application/xml, text/xml'});
      if (r.statusCode != 200 || r.bodyBytes.length > 64 * 1024) return null;
      return r.body;
    } finally {
      client.close();
    }
  }
}

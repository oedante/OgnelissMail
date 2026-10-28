// lib/core/constants/app_constants.dart

class AppConstants {
  AppConstants._();

  // ═══════════════ APP ═══════════════
  /// Название приложения на всех платформах (окно, лаунчер, «О приложении»).
  /// Пакет/bundle id — com.ogneliss.mail. В User-Agent остаётся токен
  /// «Ogneliss/<версия>»: пробелы в имени продукта UA недопустимы.
  static const appName = 'Ogneliss Mail';
  static const appNameEn = 'Ogneliss Mail';
  /// Идентификатор пакета (Android applicationId, iOS/macOS bundle id).
  static const packageId = 'com.ogneliss.mail';
  /// Версия из сборки (pubspec, PackageInfo) — заполняется при запуске
  /// (main.dart). Раньше здесь была константа '1.0.0', и «О приложении» в
  /// настройках всегда показывало 1.0.0.
  static String appVersion = '';

  /// Адрес ИТ-поддержки для «Журнал → Отправить в поддержку»
  /// (config/dart_defines.json → SUPPORT_EMAIL). Пусто — адресат
  /// вписывается вручную.
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: '');
  static const appBuild = '1';
  /// Правообладатель — как в лицензионном соглашении (ogneliss.ru/mail/eula).
  /// Латиницей: строка видна и в английском, немецком, французском интерфейсе.
  static const copyrightHolder = 'Ermishin Oleg';
  // Опубликованные документы (site/mail_src → ogneliss.ru/mail). Адреса не менять:
  // они указаны в Google Play и в уже установленных версиях.
  static const termsUrl = 'https://ogneliss.ru/mail/terms';
  static const eulaUrl = 'https://ogneliss.ru/mail/eula';
  // Открытый исходный код (Apache 2.0, с 1.8.6).
  static const sourceUrl = 'https://github.com/oedante/OgnelissMail';
  static const licenseUrl = 'https://github.com/oedante/OgnelissMail/blob/main/LICENSE';
  static const privacyUrl = 'https://ogneliss.ru/mail/privacy';
  static const licensesUrl = 'https://ogneliss.ru/mail/licenses';

  // ═══════════════ EXCHANGE ═══════════════
  static const defaultExchangeServer = '';
  static const defaultDomain = '';
  static const defaultEncryption = 'SSL/TLS';
  static const ewsPath = '/EWS/Exchange.asmx';
  static const autodiscoverPath = '/autodiscover/autodiscover.xml';
  static const activeSyncPath = '/Microsoft-Server-ActiveSync';
  // Серверы для автоперебора при входе (по умолчанию пусто — вводит пользователь).
  static const owaBackendServer = '';
  static const probeServers = <String>[];
  static const defaultServerDomain = '';
  static const ewsTimeoutSeconds = 30;

  // ═══════════════ IMAP/SMTP ═══════════════
  static const defaultImapPort = 993;
  static const defaultSmtpPort = 587;

  // ═══════════════ SYNC ═══════════════
  static const emailsPerPage = 50;
  static const maxCachedEmails = 5000;
  static const cachedCalendarDays = 60;
  static const maxAttachmentSize = 25 * 1024 * 1024; // 25 MB
  static const searchDebounceMs = 300;

  // ═══════════════ ОРГАНИЗАЦИИ (опционально) ═══════════════
  // Предустановленные домены организаций. По умолчанию пусто — приложение
  // универсальное; при необходимости заполняется под конкретную организацию.
  static const Map<String, String> subsidiaryDomains = {};

  // ═══════════════ ВНУТРЕННИЕ ДОМЕНЫ (DLP) ═══════════════
  // По умолчанию пусто; «свои» домены определяются доменом аккаунта.
  static const List<String> internalDomains = <String>[];

  // ═══════════════ КАТЕГОРИИ ПО УМОЛЧАНИЮ ═══════════════
  static const List<String> industrialTags = [
    'Работа', 'Финансы', 'Кадры', 'Проекты', 'Логистика',
    'Руководство', 'IT', 'Задачи', 'Рассылки', 'Личное',
  ];

  // ═══════════════ OAUTH ═══════════════
  // ClientID — публичные идентификаторы (не секреты). Секреты в код НЕ зашиваем:
  // desktop/web используют PKCE (публичный клиент), мобильные — flutter_appauth.
  static const googleClientId = '718225007579-sq6rbslq822om45rlmh9h75s56a38h82.apps.googleusercontent.com';
  // Схема redirect должна совпадать с настройками OAuth-клиента приложения.
  /// Адрес возврата запасного пути входа без прокси (flutter_appauth).
  /// Схема совпадает с appAuthRedirectScheme в android/app/build.gradle.kts.
  static const googleRedirectUri = 'com.ogneliss.mail.appauth:/oauth2redirect';
  static const yandexClientId = '3c992385b6a24ce1992a7937d5954877';
  // Yahoo Consumer Key (публичный client_id). Секрет — только на прокси.
  static const yahooClientId =
      'dj0yJmk9SDA5blF1OVhLRlZ5JmQ9WVdrOWRXdE9WakJGWTFVbWNHbzlNQT09JnM9Y29uc3VtZXJzZWNyZXQmc3Y9MCZ4PWRi';
  static const mailruClientId = '019f9df891d57637bce39e9b2471898b';
  // Mail.ru требует client_secret при обмене кода на токен. В распространяемом
  // клиенте секрет извлекается реверсом — поэтому В ИСХОДНИКАХ ЕГО НЕТ.
  // Штатный путь — OAuth-прокси (секрет живёт на сервере, см. oauth_proxy_flow.dart).
  // Легаси-путь без прокси возможен только со сборочным ключом:
  //   --dart-define=MAILRU_CLIENT_SECRET=...
  static const mailruClientSecret =
      String.fromEnvironment('MAILRU_CLIENT_SECRET', defaultValue: '');

  // ═══════════════ OAUTH-ПРОКСИ (server/oauth-proxy) ═══════════════
  // Если задан baseUrl — обмен/refresh токенов идёт через корпоративный прокси
  // (секреты на сервере, пользователь не логинится заново). Пусто = выключено.
  static const oauthProxyBaseUrl = String.fromEnvironment('OAUTH_PROXY_URL', defaultValue: 'https://ogneliss.ru');
  static const oauthProxyApiKey = String.fromEnvironment('OAUTH_PROXY_KEY', defaultValue: '');
  static const oauthProxyRedirect = 'com.ogneliss.mail://oauth';

  // ═══════════════ СИГНАЛЫ СЕРВЕРА НА IPHONE (server/push-relay, 1.7.2) ═══════════════
  // «Будильник» на сервере сайта: раз в 15–60 минут присылает через Apple
  // пустой сигнал «проверь почту». Сервер знает только токен уведомлений
  // установки; ключ — тот же, что у OAuth-прокси (заголовок x-api-key).
  // Пусто = выключено. silent — тихие сигналы (до одобрения права Apple на
  // фильтрацию уведомлений), alert — обычные, их принимает расширение
  // уведомлений (этап 2).
  static const pushRelayUrl = String.fromEnvironment('PUSH_RELAY_URL', defaultValue: 'https://www.ogneliss.ru/push');
  static const pushWakeMode = String.fromEnvironment('PUSH_WAKE_MODE', defaultValue: 'silent');

  /// Exchange Online (Microsoft 365): ActiveSync и EWS — на этом узле, вход
  /// только по OAuth (1.6.2).
  static const exchangeOnlineHost = 'outlook.office365.com';

  // ═══════════════ IMAP серверы ═══════════════
  static const Map<String, Map<String, dynamic>> imapServers = {
    'gmail.com': {'imap': 'imap.gmail.com', 'imapPort': 993, 'smtp': 'smtp.gmail.com', 'smtpPort': 587, 'oauth': true},
    'googlemail.com': {'imap': 'imap.gmail.com', 'imapPort': 993, 'smtp': 'smtp.gmail.com', 'smtpPort': 587, 'oauth': true},
    'yandex.ru': {'imap': 'imap.yandex.ru', 'imapPort': 993, 'smtp': 'smtp.yandex.ru', 'smtpPort': 465},
    'ya.ru': {'imap': 'imap.yandex.ru', 'imapPort': 993, 'smtp': 'smtp.yandex.ru', 'smtpPort': 465},
    'yandex.com': {'imap': 'imap.yandex.com', 'imapPort': 993, 'smtp': 'smtp.yandex.com', 'smtpPort': 465},
    'mail.ru': {'imap': 'imap.mail.ru', 'imapPort': 993, 'smtp': 'smtp.mail.ru', 'smtpPort': 465},
    'bk.ru': {'imap': 'imap.mail.ru', 'imapPort': 993, 'smtp': 'smtp.mail.ru', 'smtpPort': 465},
    'inbox.ru': {'imap': 'imap.mail.ru', 'imapPort': 993, 'smtp': 'smtp.mail.ru', 'smtpPort': 465},
    'list.ru': {'imap': 'imap.mail.ru', 'imapPort': 993, 'smtp': 'smtp.mail.ru', 'smtpPort': 465},
    'yahoo.com': {'imap': 'imap.mail.yahoo.com', 'imapPort': 993, 'smtp': 'smtp.mail.yahoo.com', 'smtpPort': 587},
    'outlook.com': {'imap': 'outlook.office365.com', 'imapPort': 993, 'smtp': 'smtp.office365.com', 'smtpPort': 587, 'oauth': true},
    'hotmail.com': {'imap': 'outlook.office365.com', 'imapPort': 993, 'smtp': 'smtp.office365.com', 'smtpPort': 587, 'oauth': true},
    'live.com': {'imap': 'outlook.office365.com', 'imapPort': 993, 'smtp': 'smtp.office365.com', 'smtpPort': 587, 'oauth': true},
    'office365.com': {'imap': 'outlook.office365.com', 'imapPort': 993, 'smtp': 'smtp.office365.com', 'smtpPort': 587, 'oauth': true},
    'icloud.com': {'imap': 'imap.mail.me.com', 'imapPort': 993, 'smtp': 'smtp.mail.me.com', 'smtpPort': 587},
    'me.com': {'imap': 'imap.mail.me.com', 'imapPort': 993, 'smtp': 'smtp.mail.me.com', 'smtpPort': 587},
    'mac.com': {'imap': 'imap.mail.me.com', 'imapPort': 993, 'smtp': 'smtp.mail.me.com', 'smtpPort': 587},
    'rambler.ru': {'imap': 'imap.rambler.ru', 'imapPort': 993, 'smtp': 'smtp.rambler.ru', 'smtpPort': 465},
    // 1.8.0: вход по адресу (mail_provider_detect.dart) — частые службы
    // стран, на языках которых теперь есть интерфейс. Порты — из справки
    // служб: IMAP 993 (SSL), SMTP 465 (SSL) или 587 (STARTTLS).
    'lenta.ru': {'imap': 'imap.rambler.ru', 'imapPort': 993, 'smtp': 'smtp.rambler.ru', 'smtpPort': 465},
    'autorambler.ru': {'imap': 'imap.rambler.ru', 'imapPort': 993, 'smtp': 'smtp.rambler.ru', 'smtpPort': 465},
    'myrambler.ru': {'imap': 'imap.rambler.ru', 'imapPort': 993, 'smtp': 'smtp.rambler.ru', 'smtpPort': 465},
    'ro.ru': {'imap': 'imap.rambler.ru', 'imapPort': 993, 'smtp': 'smtp.rambler.ru', 'smtpPort': 465},
    'ukr.net': {'imap': 'imap.ukr.net', 'imapPort': 993, 'smtp': 'smtp.ukr.net', 'smtpPort': 465},
    'aol.com': {'imap': 'imap.aol.com', 'imapPort': 993, 'smtp': 'smtp.aol.com', 'smtpPort': 465},
    'comcast.net': {'imap': 'imap.comcast.net', 'imapPort': 993, 'smtp': 'smtp.comcast.net', 'smtpPort': 587},
    'att.net': {'imap': 'imap.mail.att.net', 'imapPort': 993, 'smtp': 'smtp.mail.att.net', 'smtpPort': 465},
    'sbcglobal.net': {'imap': 'imap.mail.att.net', 'imapPort': 993, 'smtp': 'smtp.mail.att.net', 'smtpPort': 465},
    'btinternet.com': {'imap': 'mail.btinternet.com', 'imapPort': 993, 'smtp': 'mail.btinternet.com', 'smtpPort': 465},
    'fastmail.com': {'imap': 'imap.fastmail.com', 'imapPort': 993, 'smtp': 'smtp.fastmail.com', 'smtpPort': 465},
    'zoho.com': {'imap': 'imap.zoho.com', 'imapPort': 993, 'smtp': 'smtp.zoho.com', 'smtpPort': 465},
    'zohomail.com': {'imap': 'imap.zoho.com', 'imapPort': 993, 'smtp': 'smtp.zoho.com', 'smtpPort': 465},
    'zoho.eu': {'imap': 'imap.zoho.eu', 'imapPort': 993, 'smtp': 'smtp.zoho.eu', 'smtpPort': 465},
    'mail.com': {'imap': 'imap.mail.com', 'imapPort': 993, 'smtp': 'smtp.mail.com', 'smtpPort': 587},
    'gmx.net': {'imap': 'imap.gmx.net', 'imapPort': 993, 'smtp': 'mail.gmx.net', 'smtpPort': 587},
    'gmx.de': {'imap': 'imap.gmx.net', 'imapPort': 993, 'smtp': 'mail.gmx.net', 'smtpPort': 587},
    'gmx.at': {'imap': 'imap.gmx.net', 'imapPort': 993, 'smtp': 'mail.gmx.net', 'smtpPort': 587},
    'gmx.ch': {'imap': 'imap.gmx.net', 'imapPort': 993, 'smtp': 'mail.gmx.net', 'smtpPort': 587},
    'gmx.com': {'imap': 'imap.gmx.com', 'imapPort': 993, 'smtp': 'mail.gmx.com', 'smtpPort': 587},
    'web.de': {'imap': 'imap.web.de', 'imapPort': 993, 'smtp': 'smtp.web.de', 'smtpPort': 587},
    't-online.de': {'imap': 'secureimap.t-online.de', 'imapPort': 993, 'smtp': 'securesmtp.t-online.de', 'smtpPort': 465},
    'posteo.de': {'imap': 'posteo.de', 'imapPort': 993, 'smtp': 'posteo.de', 'smtpPort': 587},
    'mailbox.org': {'imap': 'imap.mailbox.org', 'imapPort': 993, 'smtp': 'smtp.mailbox.org', 'smtpPort': 465},
    'orange.fr': {'imap': 'imap.orange.fr', 'imapPort': 993, 'smtp': 'smtp.orange.fr', 'smtpPort': 465},
    'wanadoo.fr': {'imap': 'imap.orange.fr', 'imapPort': 993, 'smtp': 'smtp.orange.fr', 'smtpPort': 465},
    'free.fr': {'imap': 'imap.free.fr', 'imapPort': 993, 'smtp': 'smtp.free.fr', 'smtpPort': 465},
    'laposte.net': {'imap': 'imap.laposte.net', 'imapPort': 993, 'smtp': 'smtp.laposte.net', 'smtpPort': 465},
    'libero.it': {'imap': 'imapmail.libero.it', 'imapPort': 993, 'smtp': 'smtp.libero.it', 'smtpPort': 465},
    'virgilio.it': {'imap': 'in.virgilio.it', 'imapPort': 993, 'smtp': 'out.virgilio.it', 'smtpPort': 465},
    'ziggo.nl': {'imap': 'imap.ziggo.nl', 'imapPort': 993, 'smtp': 'smtp.ziggo.nl', 'smtpPort': 587},
    'seznam.cz': {'imap': 'imap.seznam.cz', 'imapPort': 993, 'smtp': 'smtp.seznam.cz', 'smtpPort': 465},
    'email.cz': {'imap': 'imap.seznam.cz', 'imapPort': 993, 'smtp': 'smtp.seznam.cz', 'smtpPort': 465},
    'post.cz': {'imap': 'imap.seznam.cz', 'imapPort': 993, 'smtp': 'smtp.seznam.cz', 'smtpPort': 465},
    'wp.pl': {'imap': 'imap.wp.pl', 'imapPort': 993, 'smtp': 'smtp.wp.pl', 'smtpPort': 465},
    'o2.pl': {'imap': 'poczta.o2.pl', 'imapPort': 993, 'smtp': 'poczta.o2.pl', 'smtpPort': 465},
    'onet.pl': {'imap': 'imap.poczta.onet.pl', 'imapPort': 993, 'smtp': 'smtp.poczta.onet.pl', 'smtpPort': 465},
    'op.pl': {'imap': 'imap.poczta.onet.pl', 'imapPort': 993, 'smtp': 'smtp.poczta.onet.pl', 'smtpPort': 465},
    'interia.pl': {'imap': 'poczta.interia.pl', 'imapPort': 993, 'smtp': 'poczta.interia.pl', 'smtpPort': 465},
    'naver.com': {'imap': 'imap.naver.com', 'imapPort': 993, 'smtp': 'smtp.naver.com', 'smtpPort': 465},
    'daum.net': {'imap': 'imap.daum.net', 'imapPort': 993, 'smtp': 'smtp.daum.net', 'smtpPort': 465},
    'hanmail.net': {'imap': 'imap.daum.net', 'imapPort': 993, 'smtp': 'smtp.daum.net', 'smtpPort': 465},
    'qq.com': {'imap': 'imap.qq.com', 'imapPort': 993, 'smtp': 'smtp.qq.com', 'smtpPort': 465},
    'foxmail.com': {'imap': 'imap.qq.com', 'imapPort': 993, 'smtp': 'smtp.qq.com', 'smtpPort': 465},
    '163.com': {'imap': 'imap.163.com', 'imapPort': 993, 'smtp': 'smtp.163.com', 'smtpPort': 465},
    '126.com': {'imap': 'imap.126.com', 'imapPort': 993, 'smtp': 'smtp.126.com', 'smtpPort': 465},
    'yeah.net': {'imap': 'imap.yeah.net', 'imapPort': 993, 'smtp': 'smtp.yeah.net', 'smtpPort': 465},
    'yahoo.co.jp': {'imap': 'imap.mail.yahoo.co.jp', 'imapPort': 993, 'smtp': 'smtp.mail.yahoo.co.jp', 'smtpPort': 465},
  };

  /// Возвращает конфигурацию серверов по домену email (или null).
  static Map<String, dynamic>? serverConfigForEmail(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0) return null;
    final domain = email.substring(at + 1).toLowerCase().trim();
    return imapServers[domain];
  }
}

/// Правила обработки писем (автоматизация, правила ящика) и свои категории.
/// Скрыты 09.10.2026 по решению владельца: в нынешнем виде пользы мало, а
/// правила нужно продумать отдельно для личной и рабочей почты. Код сохранён:
/// экраны, сервис правил, маршруты — вернуть, поставив true. Пока выключено,
/// правила при синхронизации НЕ применяются (раньше встроенные правила тихо
/// ставили теги и категории).
const bool kRulesAndCategoriesEnabled = false;

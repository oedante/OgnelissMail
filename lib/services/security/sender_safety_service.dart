// lib/services/security/sender_safety_service.dart
// Локальный антифишинг: анализ письма по данным EmailModel (без облака).
// SPF/DKIM/DMARC — по заголовку Authentication-Results, который поставил
// сервер получателя (IMAP — уже в списке писем, EWS — из заголовков письма;
// ActiveSync заголовков не отдаёт). Плюс эвристики из полей письма:
// внешний отправитель, спуфинг
// отображаемого имени, похожие/поддельные домены (punycode, кириллица в
// домене, близость к домену организации), опасные вложения, несовпадение
// видимого текста ссылки и её реального адреса, «первый контакт».

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/account_model.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../mail/own_addresses.dart';

/// Уровень риска письма (для цвета баннера).
enum SafetyLevel { none, info, warning, danger }

/// Конкретный сигнал (UI сам мапит reason → локализованный текст).
enum SafetyReason {
  externalSender,     // отправитель вне домена организации
  firstContact,       // ранее переписки с этим адресом не было
  displayNameSpoof,   // отображаемое имя маскирует другой адрес/домен
  lookalikeDomain,    // домен похож на легитимный (punycode/кириллица/близость)
  dangerousAttachment,// исполняемое/опасное вложение
  linkMismatch,       // видимый текст ссылки не совпадает с реальным адресом
  authenticationFail, // SPF/DKIM/DMARC не прошли (из Authentication-Results)
  contactImpersonation, // имя как у контакта, а адрес другой (1.10.x)
  replyToMismatch,    // ответ уйдёт на адрес другой организации (1.10.x)
}

class SafetySignal {
  final SafetyReason reason;
  final SafetyLevel level;
  final String? detail; // напр. имя вложения или домен — подставляется в UI

  /// Второе значение для текста (1.5.10): у «имя похоже на адрес» — адрес,
  /// с которого письмо пришло на самом деле.
  final String? extra;
  const SafetySignal(this.reason, this.level, [this.detail, this.extra]);
}

class SenderSafetyReport {
  final List<SafetySignal> signals;
  const SenderSafetyReport(this.signals);

  bool get isEmpty => signals.isEmpty;

  SafetyLevel get level {
    var max = SafetyLevel.none;
    for (final s in signals) {
      if (s.level.index > max.index) max = s.level;
    }
    return max;
  }
}

final senderSafetyServiceProvider =
    Provider<SenderSafetyService>((ref) => SenderSafetyService(ref));

class SenderSafetyService {
  final Ref _ref;
  SenderSafetyService(this._ref);

  static const _dangerousExt = {
    'exe', 'scr', 'com', 'pif', 'bat', 'cmd', 'js', 'jse', 'vbs', 'vbe',
    'wsf', 'wsh', 'hta', 'jar', 'msi', 'ps1', 'reg', 'lnk', 'cpl', 'scf',
  };
  // Форматы, которые сами по себе не «опасны», но в письме от внешнего лица
  // требуют осторожности (макросы/скрипты внутри).
  static const _riskyDocExt = {'docm', 'xlsm', 'pptm', 'htm', 'html'};

  /// Последние проверки (1.5.9). Экран письма спрашивал проверку до трёх раз
  /// подряд (плашка безопасности, плашка отписки, карточка бронирования) —
  /// каждый раз заново: разбор ссылок всего HTML регулярным выражением на
  /// главном изоляте и запрос «первый контакт» в базу. Теперь одна проверка
  /// на письмо; ключ меняется, когда приходит то, от чего она зависит.
  final Map<String, Future<SenderSafetyReport>> _recent = {};
  static const _recentMax = 8;

  Future<SenderSafetyReport> analyze(AccountModel account, EmailModel email) {
    final key = '${account.id}|${account.isWork}|${email.id}|${email.from.email}'
        '|${email.bodyHtml?.length ?? email.bodyPlain?.length ?? 0}'
        '|${email.attachments.length}|${email.authResults?.length ?? 0}';
    final hit = _recent.remove(key);
    if (hit != null) return _recent[key] = hit;
    final f = _analyze(account, email);
    _recent[key] = f;
    if (_recent.length > _recentMax) _recent.remove(_recent.keys.first);
    f.catchError((Object _) {
      _recent.remove(key);
      return const SenderSafetyReport([]);
    });
    return f;
  }

  Future<SenderSafetyReport> _analyze(AccountModel account, EmailModel email) async {
    final signals = <SafetySignal>[];

    final fromDomain = _domainOf(email.from.email);
    // Домены организации — по всем адресам ящика (адрес входа, основной
    // адрес с сервера, алиасы): вход под «…@acmegrp.example» при ящике
    // «…@acmegroup.example» превращал всю почту коллег в «поддельный домен».
    final orgDomains = OwnAddresses.domains(account);
    final orgDomain = _domainOf(OwnAddresses.primary(account));
    bool ours(String d) => orgDomains.any((o) => d == o || d.endsWith('.$o'));

    // 1. Внешний отправитель — только для рабочего ящика. У личного (Gmail,
    // Яндекс…) «своего» домена организации нет: плашка висела на каждом письме.
    final isExternal = account.isWork && fromDomain.isNotEmpty && orgDomains.isNotEmpty && !ours(fromDomain);
    if (isExternal) {
      signals.add(const SafetySignal(SafetyReason.externalSender, SafetyLevel.info));
    }

    // 1b. Аутентификация отправителя из Authentication-Results (SPF/DKIM/DMARC).
    final authFail = _authFailure(email.authResults);
    if (authFail != null) {
      signals.add(SafetySignal(SafetyReason.authenticationFail, SafetyLevel.danger, authFail));
    }

    // 2. Похожий/поддельный домен.
    // Сравнение с доменом ящика имеет смысл только для домена организации.
    // Свой домен (любой из доменов ящика) похожим на поддельный не бывает;
    // сравниваем с каждым доменом организации.
    String? lookalike;
    if (account.isWork && !ours(fromDomain)) {
      lookalike = _lookalikeReason(fromDomain, orgDomain);
      for (final o in orgDomains) {
        lookalike ??= _lookalikeReason(fromDomain, o);
      }
    }
    // 1.10.x (просьба владельца 01.11.2026): и у личных ящиков — домен в
    // punycode или с кириллицей, и домен, похожий на домен ваших контактов
    // или известного банка, магазина, госслужбы («sberbank-secure.ru»,
    // «paypa1.com»). Раньше похожие домены искались только у рабочего ящика
    // и только рядом с доменом организации.
    String? like;
    if (lookalike == null && fromDomain.isNotEmpty && !ours(fromDomain)) {
      if (fromDomain.contains('xn--') || _hasCyrillic(fromDomain)) {
        lookalike = fromDomain;
      } else {
        like = lookalikeOf(fromDomain, {...knownBrandDomains, ...await _contactDomains(account.id)});
        if (like != null) lookalike = fromDomain;
      }
    }
    if (lookalike != null) {
      signals.add(SafetySignal(SafetyReason.lookalikeDomain, SafetyLevel.danger, lookalike, like));
    }

    // 3. Спуфинг отображаемого имени: в display name «спрятан» другой адрес/домен,
    //    отличный от реального адреса отправителя.
    //    Коллеги (свой домен организации) не проверяются: имя служебного
    //    ящика задаёт своя служба, а подделку своего домена ловят SPF/DMARC
    //    (1.5.10: «1c.base.svc» — имя ящика 1С — давало «Признаки фишинга»).
    final internal = account.isWork && fromDomain.isNotEmpty && ours(fromDomain);
    //    Адрес в имени — признак фишинга; имя-сайт («Wildberries.ru» с
    //    адреса рассылки wb.ru) — бывает и у честных рассылок: «будьте
    //    внимательны», а не «признаки фишинга».
    final spoof = internal ? null : displayNameSpoof(email.from.displayName, email.from.email);
    if (spoof != null) {
      signals.add(SafetySignal(SafetyReason.displayNameSpoof, spoof.address ? SafetyLevel.danger : SafetyLevel.warning,
          spoof.found, email.from.email));
    }

    // 3b. Имя как у вашего контакта, а адрес чужой (подмена руководителя,
    //     коллеги, бухгалтерии — 1.10.x). Свой домен — не проверяем: там
    //     подделку ловят SPF/DMARC.
    if (!internal) {
      final imp = await _contactWithSameName(account.id, email.from.displayName, email.from.email);
      if (imp != null) {
        signals.add(SafetySignal(SafetyReason.contactImpersonation, SafetyLevel.danger, imp, email.from.email));
      }
    }

    // 3c. Ответ уйдёт на адрес другой организации (Reply-To). У рассылок
    //     так бывает честно (ответы — в службу поддержки), поэтому только
    //     у писем без List-Unsubscribe.
    final rt = replyToElsewhere(email.from.email, [for (final a in email.replyTo) a.email],
        mailingList: (email.listUnsubscribe ?? '').isNotEmpty);
    if (rt != null) {
      signals.add(SafetySignal(SafetyReason.replyToMismatch, SafetyLevel.warning, rt));
    }

    // 4. Опасные вложения.
    for (final att in email.attachments) {
      final ext = _extOf(att.name);
      if (_dangerousExt.contains(ext) || _looksDoubleExt(att.name)) {
        signals.add(SafetySignal(SafetyReason.dangerousAttachment, SafetyLevel.danger, att.name));
      } else if (isExternal && _riskyDocExt.contains(ext)) {
        signals.add(SafetySignal(SafetyReason.dangerousAttachment, SafetyLevel.warning, att.name));
      }
    }

    // 5. Несовпадение ссылок (видимый текст vs href) в HTML-теле.
    final mismatch = _linkMismatch(email.bodyHtml);
    if (mismatch != null) {
      signals.add(SafetySignal(SafetyReason.linkMismatch, SafetyLevel.warning, mismatch));
    }

    // 6. Первый контакт (только для внешних — от коллег плашка не нужна).
    if (isExternal && await _isFirstContact(account.id, email)) {
      signals.add(const SafetySignal(SafetyReason.firstContact, SafetyLevel.info));
    }

    return SenderSafetyReport(signals);
  }

  // ─────────────────────────── эвристики ───────────────────────────

  /// Домены известных служб, под которые чаще всего подделываются письма:
  /// банки, магазины, госслужбы, почта, доставка, платежи (1.10.x).
  static const knownBrandDomains = <String>{
    // Россия
    'sberbank.ru', 'sber.ru', 'tbank.ru', 'tinkoff.ru', 'vtb.ru', 'alfabank.ru', 'gazprombank.ru',
    'raiffeisen.ru', 'rshb.ru', 'pochtabank.ru', 'sovcombank.ru', 'open.ru', 'psbank.ru', 'mkb.ru',
    'gosuslugi.ru', 'nalog.gov.ru', 'nalog.ru', 'mos.ru', 'pfr.gov.ru', 'sfr.gov.ru', 'cbr.ru',
    'pochta.ru', 'cdek.ru', 'ozon.ru', 'wildberries.ru', 'wb.ru', 'avito.ru', 'yandex.ru', 'ya.ru',
    'mail.ru', 'vk.com', 'mts.ru', 'megafon.ru', 'beeline.ru', 'rt.ru', 'rzd.ru', 'aeroflot.ru',
    'kaspersky.ru', 'kaspersky.com', '1c.ru', 'hh.ru', 'dns-shop.ru', 'mvideo.ru',
    // Мир
    'google.com', 'gmail.com', 'apple.com', 'icloud.com', 'microsoft.com', 'outlook.com', 'live.com',
    'office.com', 'microsoftonline.com', 'paypal.com', 'amazon.com', 'ebay.com', 'aliexpress.com',
    'aliexpress.ru', 'facebook.com', 'instagram.com', 'whatsapp.com', 'telegram.org', 'linkedin.com',
    'netflix.com', 'spotify.com', 'dhl.com', 'fedex.com', 'ups.com', 'booking.com', 'airbnb.com',
    'binance.com', 'coinbase.com', 'docusign.com', 'docusign.net', 'dropbox.com', 'adobe.com',
    'github.com', 'zoom.us', 'steampowered.com', 'visa.com', 'mastercard.com', 'americanexpress.com',
    // Почтовые службы — и как цели подделки, и как честные домены с похожими
    // именами (ymail.com рядом с gmail.com, email.com, inbox.ru).
    'ymail.com', 'yahoo.com', 'hotmail.com', 'msn.com', 'aol.com', 'mail.com', 'email.com', 'gmx.com',
    'gmx.de', 'gmx.net', 'web.de', 'inbox.ru', 'list.ru', 'bk.ru', 'internet.ru', 'rambler.ru',
    'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua', 'proton.me', 'protonmail.com', 'zoho.com',
    'me.com', 'mac.com', 'qq.com', '163.com', 'naver.com', 'googlemail.com',
  };

  /// Домен, на который [domain] похож, но им не является, или null.
  /// Сравниваются имена до зоны («sberbank» из sberbank.ru): одна опечатка
  /// или подмена похожих знаков (0→o, 1→l, rn→m, vv→w) при длине от 5
  /// знаков, или имя бренда с добавкой через дефис («paypal-secure.com»,
  /// «sberbank-online.ru»). Разные зоны одного имени (yandex.ru и
  /// yandex.by) — не подделка: так устроены честные службы.
  static String? lookalikeOf(String domain, Set<String> legit) {
    final d = domain.toLowerCase().trim().replaceAll(RegExp(r'\.$'), '');
    if (d.isEmpty || legit.contains(d)) return null;
    final dl = _label(d);
    if (dl.length < 4) return null;
    final dSkel = _skeleton(dl);
    for (final l in legit) {
      if (_sameOrg(d, l)) return null; // поддомен самой службы
    }
    for (final l in legit) {
      final ll = _label(l);
      if (ll.length < 4 || ll == dl) continue;
      final lSkel = _skeleton(ll);
      if (dSkel == lSkel) return l; // paypa1 → paypal, rnail → mail
      if (ll.length >= 5 && _lev(dl, ll) == 1) return l; // sberbamk → sberbank
      // Бренд с добавкой: «paypal-support», «secure-sberbank».
      if (ll.length >= 5 && (dl.startsWith('$ll-') || dl.endsWith('-$ll') || dl.contains('-$ll-'))) return l;
    }
    return null;
  }

  /// Имя домена без зоны: «online.sberbank.ru» → «sberbank»,
  /// «mail.example.co.uk» → «example».
  static String _label(String domain) {
    final p = domain.split('.');
    if (p.length < 2) return domain;
    const second = {'co', 'com', 'org', 'net', 'gov', 'ac', 'edu', 'msk', 'spb'};
    if (p.length >= 3 && second.contains(p[p.length - 2]) && p.last.length == 2) return p[p.length - 3];
    return p[p.length - 2];
  }

  /// «Скелет» имени: похожие знаки сведены к одному (1.10.x).
  static String _skeleton(String s) => s
      .replaceAll('rn', 'm')
      .replaceAll('vv', 'w')
      .replaceAll('0', 'o')
      .replaceAll('1', 'l')
      .replaceAll('3', 'e')
      .replaceAll('5', 's')
      .replaceAll('i', 'l');

  static int _lev(String a, String b) {
    final m = a.length, n = b.length;
    if ((m - n).abs() > 1) return 2;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final c = a[i - 1] == b[j - 1] ? 0 : 1;
        final x = cur[j - 1] + 1, y = prev[j] + 1, z = prev[j - 1] + c;
        cur[j] = x < y ? (x < z ? x : z) : (y < z ? y : z);
      }
      final tmp = prev;
      prev = cur;
      cur = tmp;
    }
    return prev[n];
  }

  /// Адрес из Reply-To другой организации, чем отправитель, или null.
  static String? replyToElsewhere(String from, List<String> replyTo, {bool mailingList = false}) {
    if (mailingList || replyTo.isEmpty) return null;
    final f = from.toLowerCase().trim();
    final fd = f.contains('@') ? f.substring(f.lastIndexOf('@') + 1) : '';
    if (fd.isEmpty) return null;
    for (final r in replyTo) {
      final a = r.toLowerCase().trim();
      if (!a.contains('@') || a == f) continue;
      final d = a.substring(a.lastIndexOf('@') + 1);
      if (!_sameOrg(d, fd)) return a;
    }
    return null;
  }

  /// Нормализованное имя для сравнения: без кавычек, регистра и лишних
  /// пробелов, «ё» как «е».
  static String normalizeName(String? s) => (s ?? '')
      .toLowerCase()
      .replaceAll(RegExp('["\'«»]'), '')
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Имя годится для сравнения с контактами: два слова или от 6 знаков, без
  /// адреса внутри (адрес в имени ловит [displayNameSpoof]).
  static bool comparableName(String n) =>
      !n.contains('@') && (n.contains(' ') ? n.length >= 5 : n.length >= 6);

  /// Домены контактов ящика — для «похожего домена» (кэш на 10 минут).
  final Map<String, ({DateTime at, Set<String> domains})> _contactDomainsCache = {};

  Future<Set<String>> _contactDomains(String accountId) async {
    final hit = _contactDomainsCache[accountId];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 10)) return hit.domains;
    final out = <String>{};
    try {
      final db = _ref.read(databaseProvider);
      final q = db.selectOnly(db.contacts, distinct: true)
        ..addColumns([db.contacts.email])
        ..where(db.contacts.accountId.equals(accountId) | db.contacts.accountId.isNull())
        ..limit(5000);
      for (final r in await q.get()) {
        final e = (r.read(db.contacts.email) ?? '').toLowerCase().trim();
        final at = e.lastIndexOf('@');
        if (at > 0 && at < e.length - 1) out.add(e.substring(at + 1));
      }
    } catch (_) {}
    // Почтовые службы — не «домены контактов»: у gmail.com тысячи похожих
    // честных доменов не бывает, но сравнивать письма с ними — дело списка брендов.
    _contactDomainsCache[accountId] = (at: DateTime.now(), domains: out);
    return out;
  }

  /// Контакт с тем же именем, что у отправителя, но без его адреса и не из
  /// его организации — имя контакта (как в адресной книге) или null.
  Future<String?> _contactWithSameName(String accountId, String? displayName, String fromEmail) async {
    final n = normalizeName(displayName);
    if (!comparableName(n)) return null;
    final from = fromEmail.toLowerCase().trim();
    final fromDomain = from.contains('@') ? from.substring(from.lastIndexOf('@') + 1) : '';
    try {
      final db = _ref.read(databaseProvider);
      final rows = await (db.select(db.contacts)
            ..where((c) =>
                (c.accountId.equals(accountId) | c.accountId.isNull()) &
                c.displayName.lower().equals(displayName!.toLowerCase().trim()))
            ..limit(20))
          .get();
      // Сравнение — по нормализованному имени (ё/е, пробелы); запрос выше —
      // быстрый отбор по точному имени без регистра.
      final same = [for (final c in rows) if (normalizeName(c.displayName) == n) c];
      if (same.isEmpty) return null;
      for (final c in same) {
        final emails = {
          c.email.toLowerCase().trim(),
          for (final a in (c.additionalEmails ?? '').split(RegExp(r'[,;\s]+'))) a.toLowerCase().trim(),
        }..remove('');
        if (emails.contains(from)) return null; // это он и есть
        for (final e in emails) {
          final d = e.contains('@') ? e.substring(e.lastIndexOf('@') + 1) : '';
          if (d.isNotEmpty && fromDomain.isNotEmpty && _sameOrg(d, fromDomain)) return null; // новый адрес той же организации
        }
      }
      return same.first.displayName;
    } catch (_) {
      return null;
    }
  }

  /// Разбор Authentication-Results: возвращает краткое описание провала
  /// (напр. "SPF: fail, DMARC: fail") или null, если проверки прошли/нет данных.
  /// Явный fail/softfail/permerror по SPF или DMARC — сильный сигнал подделки.
  String? _authFailure(String? authResults) {
    if (authResults == null || authResults.isEmpty) return null;
    final a = authResults.toLowerCase();
    final failed = <String>[];
    // SPF
    final spf = RegExp(r'spf\s*=\s*(\w+)').firstMatch(a)?.group(1);
    if (spf == 'fail' || spf == 'softfail' || spf == 'permerror') failed.add('SPF');
    // DKIM
    final dkim = RegExp(r'dkim\s*=\s*(\w+)').firstMatch(a)?.group(1);
    if (dkim == 'fail' || dkim == 'permerror') failed.add('DKIM');
    // DMARC — самый весомый
    final dmarc = RegExp(r'dmarc\s*=\s*(\w+)').firstMatch(a)?.group(1);
    if (dmarc == 'fail') failed.add('DMARC');
    return failed.isEmpty ? null : failed.join(', ');
  }

  String _domainOf(String email) {
    final at = email.lastIndexOf('@');
    return at >= 0 ? email.substring(at + 1).toLowerCase().trim() : '';
  }

  String _extOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase().trim() : '';
  }

  bool _looksDoubleExt(String name) {
    // Напр. «отчёт.pdf.exe», «фото.jpg.scr».
    final parts = name.toLowerCase().split('.');
    if (parts.length < 3) return false;
    final last = parts.last;
    final prev = parts[parts.length - 2];
    const docLike = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'txt'};
    return _dangerousExt.contains(last) && docLike.contains(prev);
  }

  /// Причина «похожего домена» или null. Ловит: punycode (xn--), наличие
  /// кириллицы в домене (гомоглиф-атака — легитимные домены на проводе в
  /// ASCII/punycode), и близость к домену организации (Левенштейн ≤2, но ≠).
  String? _lookalikeReason(String fromDomain, String orgDomain) {
    if (fromDomain.isEmpty) return null;
    if (fromDomain.contains('xn--')) return fromDomain;
    if (_hasCyrillic(fromDomain)) return fromDomain;
    if (orgDomain.isNotEmpty && fromDomain != orgDomain) {
      final d = _levenshtein(fromDomain, orgDomain);
      if (d > 0 && d <= 2) return fromDomain; // почти как у организации
    }
    // Смешение кириллицы и латиницы в адресной книге не проверяем здесь —
    // достаточно наличия кириллицы выше.
    return null;
  }

  bool _hasCyrillic(String s) => RegExp(r'[а-яё]', caseSensitive: false).hasMatch(s);

  /// В отображаемом имени «спрятан» адрес или домен другой организации:
  /// «support@bank.ru <x@evil.com>», «bank.ru <x@evil.com>». Возвращает
  /// найденный адрес или домен ([address] — найден именно адрес) или null.
  ///
  /// Не подделка (1.5.10):
  ///  · имя — это сам адрес отправителя или его часть до «@» («1c.base.svc»
  ///    у ящика 1c.base.svc@…: так подписываются служебные ящики);
  ///  · адрес в имени — того же домена, что и отправитель (старый адрес
  ///    коллеги, псевдоним);
  ///  · «домен» с несуществующей зоной («1c.base.svc», «v1.2.3»): зона —
  ///    из списка общих (com, net, org…) или двухбуквенная страны, или .рф.
  static ({String found, bool address})? displayNameSpoof(String? displayName, String realEmail) {
    if (displayName == null || displayName.trim().isEmpty) return null;
    final dn = displayName.toLowerCase().trim();
    final real = realEmail.toLowerCase().trim();
    final at = real.lastIndexOf('@');
    final realLocal = at > 0 ? real.substring(0, at) : real;
    final realDomain = at > 0 ? real.substring(at + 1) : '';
    if (dn == real || dn == realLocal) return null;

    // Адрес в имени — другого домена.
    final emailInName = RegExp(r'[\w.+-]+@[\w.-]+\.[a-zа-яё]{2,}').firstMatch(dn)?.group(0);
    if (emailInName != null) {
      if (emailInName == real) return null;
      final d = emailInName.substring(emailInName.lastIndexOf('@') + 1);
      if (realDomain.isNotEmpty && _sameOrg(d, realDomain)) return null;
      return (found: emailInName, address: true);
    }
    // Имя похоже на домен (сайт) другой организации.
    for (final m in RegExp(r'(?<![\w@.-])(?:[\wа-яё-]+\.)+([a-zа-яё]{2,})(?![\w.-])').allMatches(dn)) {
      final host = m.group(0)!;
      if (!_realTld(m.group(1)!)) continue;
      // Часть адреса отправителя («ivanov.petr» у ivanov.petr@…) — не домен.
      if (realLocal.contains(host)) continue;
      if (realDomain.isNotEmpty && _sameOrg(host, realDomain)) continue;
      return (found: host, address: false);
    }
    return null;
  }

  static const _gTlds = {
    'com', 'net', 'org', 'info', 'biz', 'edu', 'gov', 'mil', 'int', 'io', 'app', 'dev', 'online', 'site',
    'shop', 'store', 'xyz', 'top', 'club', 'pro', 'cloud', 'tech', 'email', 'link', 'live', 'mobi', 'name',
    'рф', 'рус', 'москва', 'дети', 'орг', 'сайт', 'онлайн',
  };

  static bool _realTld(String tld) =>
      _gTlds.contains(tld) || (tld.length == 2 && RegExp(r'^[a-z]{2}$').hasMatch(tld));

  /// Один домен организации: совпадает или один — поддомен другого, или
  /// одинаковы последние две части («mail.acmegroup.example» и «acmegroup.example»).
  static bool _sameOrg(String a, String b) {
    if (a == b || a.endsWith('.$b') || b.endsWith('.$a')) return true;
    String reg(String h) {
      final p = h.split('.');
      return p.length <= 2 ? h : p.sublist(p.length - 2).join('.');
    }
    return reg(a) == reg(b);
  }

  /// Возвращает пример несовпадающей ссылки: видимый текст — это домен/URL,
  /// а реальный href ведёт на другой домен.
  String? _linkMismatch(String? html) {
    if (html == null || html.isEmpty) return null;
    final re = RegExp(
        "<a\\s[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
        caseSensitive: false, dotAll: true);
    for (final m in re.allMatches(html)) {
      final href = m.group(1) ?? '';
      final text = (m.group(2) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      // Интересуют только случаи, когда видимый текст сам похож на URL/домен.
      if (!RegExp(r'[\w-]+\.\w{2,}').hasMatch(text)) continue;
      final hrefHost = _hostOfUrl(href);
      final textHost = _hostOfUrl(text);
      if (hrefHost.isEmpty || textHost.isEmpty) continue;
      if (!_sameRegistrable(hrefHost, textHost)) {
        return '$textHost → $hrefHost';
      }
    }
    return null;
  }

  String _hostOfUrl(String url) {
    var u = url.trim().toLowerCase();
    u = u.replaceFirst(RegExp(r'^[a-z]+://'), '');
    u = u.split('/').first.split('?').first.split('#').first;
    // отрезаем возможный user@host и порт
    if (u.contains('@')) u = u.split('@').last;
    u = u.split(':').first;
    return u;
  }

  bool _sameRegistrable(String a, String b) {
    if (a == b) return true;
    List<String> reg(String h) {
      final p = h.split('.');
      return p.length <= 2 ? p : p.sublist(p.length - 2);
    }
    return reg(a).join('.') == reg(b).join('.');
  }

  Future<bool> _isFirstContact(String accountId, EmailModel email) async {
    try {
      final db = _ref.read(databaseProvider);
      // Только id (1.5.9): раньше читалась вся строка письма — с телом,
      // которое с 1.5.5 хранится в базе и расшифровывается постранично.
      // Поиск — по индексу idx_emails_sender (account_id, from_email);
      // без него для действительно первого контакта просматривались все
      // письма ящика.
      final q = db.selectOnly(db.emails)
        ..addColumns([db.emails.id])
        ..where(db.emails.accountId.equals(accountId) &
            db.emails.fromEmail.equals(email.from.email) &
            db.emails.id.equals(email.id).not())
        ..limit(1);
      final rows = await q.get();
      return rows.isEmpty;
    } catch (_) {
      return false; // при ошибке не пугаем ложным «первым контактом»
    }
  }

  int _levenshtein(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    var cur = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev; prev = cur; cur = tmp;
    }
    return prev[n];
  }
}

// lib/services/mail/delivery/delivery_report.dart
// Отчёты о доставке (1.9.x, просьба владельца 31.10.2026): разбор DSN по
// RFC 3464 (multipart/report; report-type=delivery-status) и типичных
// нестандартных «недоставленных» (Postfix, Exim, Exchange, Яндекс, Mail.ru).
//
// Разбор осторожный: письмо считается отчётом, только если в нём есть
// машинная часть message/delivery-status с полем Action у адресата, либо его
// прислал почтовый робот (MAILER-DAEMON, postmaster) и в тексте есть фраза о
// недоставке и адрес получателя. Обычное письмо со словом «не доставлено» в
// теме отчётом не станет.

import 'package:enough_mail/enough_mail.dart';

/// Что сервер сделал с письмом для адресата (RFC 3464, поле Action);
/// [read] — адресат открыл письмо (отчёт о прочтении, RFC 8098, 2.2.0).
enum DeliveryAction { failed, delayed, delivered, relayed, expanded, read }

/// Причина простыми словами — по коду статуса и ответу сервера.
enum DeliveryReason { noSuchUser, domainNotFound, mailboxFull, blocked, tooLarge, delayed, delivered, read, other }

/// Отчёт об одном адресате.
class RecipientDelivery {
  /// Адрес, нижний регистр.
  final String recipient;
  final DeliveryAction action;

  /// Расширенный код статуса (RFC 3463): «5.1.1».
  final String? status;

  /// Ответ сервера получателя («550 5.1.1 User unknown»).
  final String? diagnostic;

  const RecipientDelivery({required this.recipient, required this.action, this.status, this.diagnostic});

  DeliveryReason get reason => DeliveryReport.reasonOf(action, status, diagnostic);

  /// Окончательный ответ (не «задерживается»): его более поздний отчёт о
  /// задержке не отменяет.
  bool get isFinal => action != DeliveryAction.delayed;
}

class DeliveryReport {
  /// Message-ID исходного письма: без <>, нижний регистр.
  final String? originalMessageId;

  /// ENVID отправки (Original-Envelope-Id). Ogneliss передаёт в нём
  /// Message-ID письма — второй способ найти исходное письмо.
  final String? envelopeId;
  final List<RecipientDelivery> recipients;

  /// Машинный отчёт RFC 3464 (а не разбор текста).
  final bool standard;

  const DeliveryReport({this.originalMessageId, this.envelopeId, required this.recipients, required this.standard});

  /// Message-ID для поиска исходного письма: из вложенных заголовков, затем ENVID.
  List<String> get messageIds => [
        if (originalMessageId != null) originalMessageId!,
        if (envelopeId != null && envelopeId != originalMessageId && envelopeId!.contains('@')) envelopeId!,
      ];

  /// Message-ID в виде для сравнения: первый <…>, без скобок, нижний регистр.
  /// null — не похоже на Message-ID.
  static String? normalizeMessageId(String? raw) {
    if (raw == null) return null;
    var v = raw.trim();
    final m = RegExp(r'<([^<>\s]+)>').firstMatch(v);
    if (m != null) v = m.group(1)!;
    v = v.trim().toLowerCase();
    return v.contains('@') && !v.contains(' ') ? v : null;
  }

  static DeliveryAction? actionOf(String? raw) => switch ((raw ?? '').trim().toLowerCase()) {
        'failed' => DeliveryAction.failed,
        'delayed' => DeliveryAction.delayed,
        'delivered' => DeliveryAction.delivered,
        'relayed' => DeliveryAction.relayed,
        'expanded' => DeliveryAction.expanded,
        'read' => DeliveryAction.read,
        _ => null,
      };

  /// Причина по коду статуса (он точнее), затем по тексту ответа сервера.
  static DeliveryReason reasonOf(DeliveryAction action, String? status, String? diagnostic) {
    if (action == DeliveryAction.read) return DeliveryReason.read;
    if (action != DeliveryAction.failed && action != DeliveryAction.delayed) return DeliveryReason.delivered;
    if (action == DeliveryAction.delayed) return DeliveryReason.delayed;
    final s = status ?? '';
    final detail = s.length > 2 ? s.substring(2) : '';
    switch (detail) {
      case '1.1' || '1.0' || '1.10' || '2.1':
        return DeliveryReason.noSuchUser;
      case '1.2' || '4.4':
        return DeliveryReason.domainNotFound;
      case '2.2':
        return DeliveryReason.mailboxFull;
      case '2.3' || '3.4':
        return DeliveryReason.tooLarge;
    }
    final d = (diagnostic ?? '').toLowerCase();
    bool has(List<String> words) => words.any(d.contains);
    if (has(['domain not found', 'host or domain name not found', 'no mx', 'name or service not known', 'nxdomain',
      'домен не найден'])) {
      return DeliveryReason.domainNotFound;
    }
    if (has(['mailbox full', 'mailbox is full', 'quota', 'insufficient storage', 'переполнен'])) {
      return DeliveryReason.mailboxFull;
    }
    if (has(['too large', 'too big', 'size limit', 'exceeds the maximum size', 'слишком больш'])) {
      return DeliveryReason.tooLarge;
    }
    if (has(['user unknown', 'unknown user', 'no such user', 'does not exist', 'doesn\'t exist', 'not exist',
      'recipient not found', 'invalid recipient', 'address rejected', 'mailbox unavailable', 'mailbox not found',
      'no mailbox', 'не существует', 'нет такого'])) {
      return DeliveryReason.noSuchUser;
    }
    if (s.startsWith('5.7.') ||
        has(['spam', 'blocked', 'blacklist', 'block list', 'blocklist', 'denylist', 'policy', 'спам', 'заблокир'])) {
      return DeliveryReason.blocked;
    }
    return DeliveryReason.other;
  }
}

/// Подсказка IMAP: по BODYSTRUCTURE письмо — multipart/report с отчётом о
/// доставке. Ставится при разборе списка писем, читается синхронизацией —
/// письмо от необычного отправителя тоже проверяется.
class DeliveryReportHints {
  static final _ids = <String>[];

  static void add(String accountId, String emailId) {
    _ids.add('$accountId|$emailId');
    if (_ids.length > 300) _ids.removeRange(0, _ids.length - 300);
  }

  static bool take(String accountId, String emailId) => _ids.remove('$accountId|$emailId');

  /// Корень письма — отчёт о доставке или о прочтении (content-type и
  /// параметр report-type).
  static bool isReportType(String? mediaType, String? reportType) =>
      (mediaType ?? '').toLowerCase() == 'multipart/report' &&
      RegExp('delivery-status|disposition-notification').hasMatch((reportType ?? '').toLowerCase());
}

class DeliveryReportParser {
  static const _robotLocals = {
    'mailer-daemon', 'mailerdaemon', 'mail-daemon', 'maildaemon', 'postmaster', 'mdaemon', 'mail.daemon',
  };

  /// Отправитель — почтовый робот: MAILER-DAEMON, postmaster, «Mail Delivery
  /// System/Subsystem», служебный адрес Exchange Online (MicrosoftExchange…).
  static bool isRobotSender(String email, [String? name]) {
    final e = email.trim().toLowerCase();
    final at = e.indexOf('@');
    final local = at < 0 ? e : e.substring(0, at);
    if (_robotLocals.contains(local) || local.startsWith('microsoftexchange')) return true;
    final n = (name ?? '').toLowerCase();
    return n.contains('mail delivery') || n.contains('mailer-daemon') || n.contains('mailer daemon');
  }

  static final _subject = RegExp(
      r'undeliver|mail delivery failed|delivery status notification|delivery failure|returned mail|'
      r'failure notice|delivery has failed|not delivered|mail system error|delayed mail|delivery delayed|'
      r'message delayed|mail failure|^delivered:|^relayed:|недоставлен|не доставлен|не удается доставить|'
      r'не удалось доставить|задерживается|^доставлено:',
      caseSensitive: false);

  /// Стоит ли скачать письмо целиком и проверить: робот-отправитель, тема
  /// отчёта или (IMAP) структура multipart/report.
  static bool isCandidate({required String fromEmail, String? fromName, required String subject, bool reportType = false}) =>
      reportType ||
      isRobotSender(fromEmail, fromName) ||
      _subject.hasMatch(subject.trim()) ||
      _readSubject.hasMatch(subject.trim());

  /// Тема отчёта о прочтении (2.2.0): «Прочитано: …» (Outlook, Exchange),
  /// «Read: …», «Отчёт о прочтении» и на других частых языках.
  static final _readSubject = RegExp(
      r'^(прочитано|прочтено|read|gelesen|lu|leído|letto|lido|gelezen|odczytano|přečteno|okundu)\s*:|'
      r'read receipt|return receipt|disposition notification|отч[её]т о прочтении|уведомление о прочтении',
      caseSensitive: false);

  /// Фраза «прочитано» в тексте отчёта без машинной части (Exchange).
  static final _readPhrase = RegExp(
      r'was read on|has been read|been displayed|было прочитано|прочитано\s|прочитал|wurde gelesen|a été lu|fue leído',
      caseSensitive: false);

  static final _failPhrase = RegExp(
      r"could not be delivered|couldn't be delivered|wasn't delivered|was not delivered|undeliverable|"
      r'delivery to the following recipient|delivery has failed|following address(es)? failed|permanent error|'
      r'returned to sender|mail delivery failed|unable to deliver|not be delivered|'
      r'не может быть доставлено|не было доставлено|не доставлено|не удалось доставить|недоставленное|'
      r'не удается доставить|не смогли доставить',
      caseSensitive: false);

  static final _delayPhrase = RegExp(
      r'delayed|will (continue|keep) trying|will retry|still trying|has not yet been delivered|'
      r'задерживается|задержано|будут продолжаться|повторит попытку',
      caseSensitive: false);

  /// Начало копии исходного письма в тексте отчёта: адреса ниже — не адресаты отчёта.
  static final _copyMarker = RegExp(
      r'this is a copy of the message|below this line is a copy|original message follows|'
      r'^-+\s*original message|message headers follow|исходное сообщение|копия сообщения|'
      r'заголовки (исходного )?сообщения|^received:',
      caseSensitive: false,
      multiLine: true);

  static final _email = RegExp(r"[A-Za-z0-9._%+'=-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}");
  static final _statusCode = RegExp(r'\b([245])\.(\d{1,3})\.(\d{1,3})\b');
  static final _smtpLine = RegExp(r'\b[45]\d\d[ -][^\n]{3,}');

  /// Разобрать письмо (MIME целиком). null — не отчёт о доставке или в нём
  /// нет ни одного адресата. [own] — адреса ящика: их в адресатах не бывает.
  static DeliveryReport? parse(String raw, {Iterable<String> own = const []}) {
    final MimeMessage msg;
    try {
      msg = MimeMessage.parseFromText(raw);
    } catch (_) {
      return null;
    }
    String? statusText;
    String? mdnText;
    String? origHeaders;
    final texts = <String>[];
    void walk(MimePart p, int depth) {
      if (depth > 6) return;
      final type = p.mediaType.text.toLowerCase();
      if (type == 'message/delivery-status' || type == 'message/global-delivery-status') {
        statusText ??= _safeText(p);
        return;
      }
      // Отчёт о прочтении (RFC 8098, 2.2.0).
      if (type == 'message/disposition-notification' || type == 'message/global-disposition-notification') {
        mdnText ??= _safeText(p);
        return;
      }
      if (type == 'message/rfc822' || type == 'message/global' || type == 'text/rfc822-headers' ||
          type == 'message/global-headers') {
        origHeaders ??= _headerBlock(_safeText(p) ?? '');
        return;
      }
      final children = p.parts;
      if (children != null && children.isNotEmpty) {
        for (final c in children) {
          walk(c, depth + 1);
        }
        return;
      }
      if (p.mediaType.top == MediaToptype.text && texts.length < 3) {
        final t = _safeText(p) ?? '';
        texts.add(type == 'text/html' ? _stripHtml(t) : t);
      }
    }

    walk(msg, 0);

    final ownSet = {for (final o in own) o.trim().toLowerCase()};
    final text = texts.join('\n\n');
    final fromAddr = msg.from?.firstOrNull;
    final fromEmail = fromAddr?.email ?? '';
    final subject = msg.decodeSubject() ?? '';

    // Исходное письмо: Message-ID вложенных заголовков, затем копия письма в
    // тексте (Exim, Mail.ru), затем In-Reply-To/References отчёта.
    String? origId = DeliveryReport.normalizeMessageId(_field(origHeaders, 'message-id'));
    origId ??= DeliveryReport.normalizeMessageId(
        RegExp(r'^message-id:\s*(<[^>\s]+>)', caseSensitive: false, multiLine: true).firstMatch(text)?.group(1));
    origId ??= DeliveryReport.normalizeMessageId(msg.getHeaderValue('in-reply-to'));
    if (origId == null) {
      final refs = msg.getHeaderValue('references');
      final all = RegExp(r'<[^<>\s]+>').allMatches(refs ?? '').toList();
      if (all.isNotEmpty) origId = DeliveryReport.normalizeMessageId(all.last.group(0));
    }

    // Отчёт о прочтении (2.2.0, план 08.11.2026: ✓✓ «прочитано»): «открыл»
    // (displayed) — прочитано; «удалил, не читая» и прочее — не отметка.
    final mdn = mdnText;
    if (mdn != null) {
      final g = <String, String>{for (final m in _fieldGroups(mdn)) ...m};
      final disposition = (g['disposition'] ?? '').toLowerCase();
      final rcpt = _address(g['final-recipient'] ?? g['original-recipient']) ?? fromEmail.toLowerCase();
      final mid = DeliveryReport.normalizeMessageId(g['original-message-id']) ?? origId;
      if (!disposition.contains('displayed') || rcpt.isEmpty || ownSet.contains(rcpt) || mid == null) return null;
      return DeliveryReport(
        originalMessageId: mid,
        recipients: [RecipientDelivery(recipient: rcpt, action: DeliveryAction.read)],
        standard: true,
      );
    }
    // Отчёт о прочтении без машинной части (Exchange внутри организации):
    // «Прочитано: тема» от самого адресата, ссылка на письмо — в
    // In-Reply-To или References, в тексте — «было прочитано».
    if (statusText == null &&
        origId != null &&
        _readSubject.hasMatch(subject.trim()) &&
        !isRobotSender(fromEmail, fromAddr?.personalName) &&
        fromEmail.isNotEmpty &&
        !ownSet.contains(fromEmail.toLowerCase()) &&
        (_readPhrase.hasMatch(text) || _readPhrase.hasMatch(subject))) {
      return DeliveryReport(
        originalMessageId: origId,
        recipients: [RecipientDelivery(recipient: fromEmail.toLowerCase(), action: DeliveryAction.read)],
        standard: false,
      );
    }

    final st = statusText;
    if (st != null) {
      final groups = _fieldGroups(st);
      String? envId;
      final recipients = <RecipientDelivery>[];
      for (final g in groups) {
        envId ??= g['original-envelope-id'];
        final rcpt = _address(g['final-recipient'] ?? g['original-recipient']);
        final action = DeliveryReport.actionOf(g['action']);
        if (rcpt == null || action == null || ownSet.contains(rcpt)) continue;
        if (recipients.any((r) => r.recipient == rcpt)) continue;
        recipients.add(RecipientDelivery(
          recipient: rcpt,
          action: action,
          status: _statusCode.firstMatch(g['status'] ?? '')?.group(0),
          diagnostic: _diagnostic(g['diagnostic-code']),
        ));
      }
      if (recipients.isNotEmpty) {
        return DeliveryReport(
          originalMessageId: origId,
          envelopeId: _xtextDecode(envId)?.trim().toLowerCase(),
          recipients: recipients,
          standard: true,
        );
      }
    }

    // Нестандартный отчёт — только от робота и с фразой о недоставке или задержке.
    if (!isRobotSender(fromEmail, fromAddr?.personalName)) return null;
    final failed = _failPhrase.hasMatch(text) || _failPhrase.hasMatch(subject);
    final delayed = !failed && (_delayPhrase.hasMatch(text) || _delayPhrase.hasMatch(subject));
    if (!failed && !delayed) return null;
    final cut = _copyMarker.firstMatch(text);
    final body = cut == null ? text : text.substring(0, cut.start);
    final robots = {fromEmail.toLowerCase()};
    final found = <String, int>{};
    for (final m in _email.allMatches(body)) {
      final a = m.group(0)!.toLowerCase().replaceAll(RegExp(r'^[.]+|[.]+$'), '');
      if (ownSet.contains(a) || robots.contains(a) || isRobotSender(a)) continue;
      found.putIfAbsent(a, () => m.start);
      if (found.length >= 20) break;
    }
    if (found.isEmpty) {
      // Адреса в тексте нет — берём единственного адресата исходного письма.
      final to = _addresses(_field(origHeaders, 'to'));
      if (to.length == 1 && !ownSet.contains(to.single)) found[to.single] = -1;
    }
    if (found.isEmpty) return null;
    final recipients = <RecipientDelivery>[];
    found.forEach((addr, at) {
      // Ответ сервера — ближайший после адреса, иначе первый в тексте.
      final near = at < 0 ? body : body.substring(at, (at + 700).clamp(0, body.length));
      final code = _statusCode.firstMatch(near) ?? _statusCode.firstMatch(body);
      final line = _smtpLine.firstMatch(near) ?? _smtpLine.firstMatch(body);
      final status = code?.group(0);
      recipients.add(RecipientDelivery(
        recipient: addr,
        action: delayed || ((status?.startsWith('4.') ?? false) && !failed)
            ? DeliveryAction.delayed
            : DeliveryAction.failed,
        status: status,
        diagnostic: _diagnostic(line?.group(0)),
      ));
    });
    return DeliveryReport(originalMessageId: origId, recipients: recipients, standard: false);
  }

  static String? _safeText(MimePart p) {
    try {
      return p.decodeContentText();
    } catch (_) {
      return null;
    }
  }

  /// Заголовки письма — до первой пустой строки.
  static String _headerBlock(String text) {
    final t = text.replaceAll('\r\n', '\n');
    final i = t.indexOf('\n\n');
    return i < 0 ? t : t.substring(0, i);
  }

  /// Значение поля заголовков (с продолжениями строк).
  static String? _field(String? headers, String name) {
    if (headers == null) return null;
    for (final g in _fieldGroups(headers)) {
      final v = g[name];
      if (v != null) return v;
    }
    return null;
  }

  /// Группы полей «Имя: значение», разделённые пустыми строками; строка,
  /// начинающаяся с пробела, — продолжение предыдущего поля.
  static List<Map<String, String>> _fieldGroups(String text) {
    final groups = <Map<String, String>>[];
    var cur = <String, String>{};
    String? last;
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      if (line.trim().isEmpty) {
        if (cur.isNotEmpty) groups.add(cur);
        cur = <String, String>{};
        last = null;
        continue;
      }
      if ((line.startsWith(' ') || line.startsWith('\t')) && last != null) {
        cur[last] = '${cur[last]} ${line.trim()}';
        continue;
      }
      final i = line.indexOf(':');
      if (i <= 0) continue;
      last = line.substring(0, i).trim().toLowerCase();
      cur.putIfAbsent(last, () => line.substring(i + 1).trim());
    }
    if (cur.isNotEmpty) groups.add(cur);
    return groups;
  }

  /// «rfc822; user@example.com» → «user@example.com».
  static String? _address(String? v) {
    if (v == null) return null;
    final s = v.contains(';') ? v.substring(v.indexOf(';') + 1) : v;
    final m = _email.firstMatch(s);
    return m?.group(0)?.toLowerCase();
  }

  static List<String> _addresses(String? v) =>
      {for (final m in _email.allMatches(v ?? '')) m.group(0)!.toLowerCase()}.toList();

  /// «smtp; 550 5.1.1 …» → «550 5.1.1 …», не длиннее 300 знаков.
  static String? _diagnostic(String? v) {
    if (v == null) return null;
    var s = v.trim();
    final semi = s.indexOf(';');
    if (semi > 0 && semi < 12) s = s.substring(semi + 1).trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return null;
    return s.length > 300 ? '${s.substring(0, 300)}…' : s;
  }

  /// xtext (RFC 3461): «+2B» → «+».
  static String? _xtextDecode(String? v) => v?.replaceAllMapped(
      RegExp(r'\+([0-9A-Fa-f]{2})'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));

  static String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<(br|/p|/div|/tr|/li)[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

// lib/services/mail/ews/ews_mail_tips.dart
// Подсказки Exchange для адресатов (MailTips, EWS GetMailTips; 1.6.49), как
// в Outlook: у адресата включён автоответ (в отпуске, на больничном) — его
// текст виден ещё до отправки; ящик адресата переполнен; адресат —
// большая рассылка или в ней есть внешние получатели.
//
// Запрос и разбор — отдельно от больших EwsXmlBuilder/EwsXmlParser. Разбор —
// по локальным именам элементов: префиксы пространств имён у серверов разные.

import 'package:xml/xml.dart';

class MailTip {
  /// Адрес адресата (нижний регистр).
  final String email;
  final String name;

  /// Текст автоответа без разметки; null — автоответ не включён.
  final String? autoReply;

  /// Ящик адресата переполнен — письмо может не дойти.
  final bool mailboxFull;

  /// Получателей в рассылке (у обычного ящика — 1).
  final int? totalMembers;

  /// Внешних получателей в рассылке.
  final int? externalMembers;

  const MailTip({
    required this.email,
    this.name = '',
    this.autoReply,
    this.mailboxFull = false,
    this.totalMembers,
    this.externalMembers,
  });

  /// Большая рассылка — подсказка, как у Outlook (порог по умолчанию — 25).
  static const bigList = 25;

  bool get isBigList => (totalMembers ?? 0) >= bigList;
  bool get hasExternal => (totalMembers ?? 0) > 1 && (externalMembers ?? 0) > 0;

  /// Есть что показать.
  bool get notable => autoReply != null || mailboxFull || isBigList || hasExternal;
}

abstract final class EwsMailTips {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Тело запроса GetMailTips (без конверта SOAP).
  static String buildRequest(String sender, List<String> recipients) {
    final mailboxes = recipients
        .map((r) => '<t:Mailbox><t:EmailAddress>${_esc(r)}</t:EmailAddress></t:Mailbox>')
        .join();
    return '<m:GetMailTips>'
        '<m:SendingAs><t:EmailAddress>${_esc(sender)}</t:EmailAddress></m:SendingAs>'
        '<m:Recipients>$mailboxes</m:Recipients>'
        '<m:MailTipsRequested>OutOfOfficeMessage MailboxFullStatus TotalMemberCount ExternalMemberCount</m:MailTipsRequested>'
        '</m:GetMailTips>';
  }

  static Iterable<XmlElement> _all(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static XmlElement? _first(XmlNode n, String local) {
    for (final e in _all(n, local)) {
      return e;
    }
    return null;
  }

  static List<MailTip> parse(XmlDocument doc) {
    final out = <MailTip>[];
    for (final tips in _all(doc, 'MailTips')) {
      final addr = _first(tips, 'RecipientAddress');
      if (addr == null) continue;
      final email = (_first(addr, 'EmailAddress')?.innerText ?? '').trim().toLowerCase();
      if (!email.contains('@')) continue;
      final name = (_first(addr, 'Name')?.innerText ?? '').trim();
      String? reply;
      final oof = _first(tips, 'OutOfOffice');
      if (oof != null) {
        final text = plain(_first(oof, 'Message')?.innerText ?? '');
        if (text.isNotEmpty) reply = text;
      }
      int? n(String local) => int.tryParse((_first(tips, local)?.innerText ?? '').trim());
      out.add(MailTip(
        email: email,
        name: name,
        autoReply: reply,
        mailboxFull: (_first(tips, 'MailboxFull')?.innerText ?? '').trim().toLowerCase() == 'true',
        totalMembers: n('TotalMemberCount'),
        externalMembers: n('ExternalMemberCount'),
      ));
    }
    return out;
  }

  /// Текст автоответа без разметки, одной строкой, не длиннее 240 знаков.
  static String plain(String html) {
    var s = html
        .replaceAll(RegExp(r'<(br|/p|/div|/li)[^>]*>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (s.length > 240) s = '${s.substring(0, 239).trimRight()}…';
    return s;
  }
}

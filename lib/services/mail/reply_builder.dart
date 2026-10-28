// lib/services/mail/reply_builder.dart
// Ответ и пересылка как в Outlook (1.5.12): кому отвечать и шапка цитаты.
//
// Раньше:
//  · ответ всегда уходил отправителю — Reply-To не учитывался (рассылки,
//    ящики поддержки, письма «от имени» отвечали не туда);
//  · «Ответить всем» переносило всех получателей оригинала в копию —
//    в Outlook адресаты из «Кому» остаются в «Кому»;
//  · шапка цитаты была в стиле Gmail («12.10.2026 16:38, Иван пишет:»,
//    «---------- Пересылаемое сообщение ----------») с отступом-цитатой.
//    У адресатов на Outlook переписка выглядела чужеродно, а свёртка цитат
//    в Outlook её не узнавала.

import 'package:intl/intl.dart';

import '../../data/models/email_model.dart';

class ReplyBuilder {
  ReplyBuilder._();

  /// Получатели ответа, как в Outlook.
  ///
  /// «Ответить»: Reply-To, если он есть (и это не свой адрес), иначе
  /// отправитель. «Ответить всем»: то же плюс «Кому» оригинала — в «Кому»,
  /// «Копия» оригинала — в «Копию». Свои адреса и повторы убираются.
  /// Ответ на своё письмо (из «Отправленных») — тем, кому оно ушло.
  static ({List<EmailAddress> to, List<EmailAddress> cc}) recipients({
    required EmailAddress from,
    List<EmailAddress> replyTo = const [],
    List<EmailAddress> to = const [],
    List<EmailAddress> cc = const [],
    required bool all,
    required bool Function(String email) mine,
  }) {
    final seen = <String>{};
    final outTo = <EmailAddress>[];
    final outCc = <EmailAddress>[];
    void add(List<EmailAddress> into, EmailAddress a) {
      final key = a.email.trim().toLowerCase();
      if (key.isEmpty || mine(a.email) || !seen.add(key)) return;
      into.add(a);
    }

    if (mine(from.email)) {
      for (final a in to) {
        add(outTo, a);
      }
      if (all) {
        for (final a in cc) {
          add(outCc, a);
        }
      }
      if (outTo.isEmpty && outCc.isEmpty) outTo.add(from);
      return (to: outTo, cc: outCc);
    }

    final rt = [for (final a in replyTo) if (a.email.trim().isNotEmpty && !mine(a.email)) a];
    for (final a in rt.isNotEmpty ? rt : [from]) {
      add(outTo, a);
    }
    if (all) {
      for (final a in to) {
        add(outTo, a);
      }
      for (final a in cc) {
        add(outCc, a);
      }
    }
    if (outTo.isEmpty) outTo.add(from);
    return (to: outTo, cc: outCc);
  }

  /// Дата в шапке цитаты, как пишет Outlook: «понедельник, 12 октября
  /// 2026 г. 16:38», «Monday, October 12, 2026 4:38 PM».
  static String sentDate(DateTime d, String locale) {
    final l = d.toLocal();
    final day = DateFormat.yMMMMEEEEd(locale);
    return (locale.startsWith('en') ? day.add_jm() : day.add_Hm()).format(l);
  }

  /// «Имя <адрес>» (или только адрес), через «; » — как в Outlook.
  static String addresses(List<EmailAddress> list) => list.map((a) {
        final name = (a.displayName ?? '').trim();
        final email = a.email.trim();
        if (name.isEmpty || name.toLowerCase() == email.toLowerCase()) return _esc(email);
        if (email.isEmpty) return _esc(name);
        return '${_esc(name)} &lt;${_esc(email)}&gt;';
      }).join('; ');

  /// Шапка цитаты Outlook: линия сверху и строки «От / Отправлено / Кому /
  /// Копия / Тема» с жирными подписями. Одинакова для ответа и пересылки.
  /// [labels] — подписи с двоеточием на языке интерфейса (from, sent, to,
  /// cc, subject). Пустые «Кому» и «Копия» не выводятся.
  static String header({
    required Map<String, String> labels,
    required EmailAddress from,
    required String sent,
    List<EmailAddress> to = const [],
    List<EmailAddress> cc = const [],
    required String subject,
  }) {
    String line(String key, String value) => '<b>${_esc(labels[key] ?? '')}</b> $value';
    final lines = [
      line('from', addresses([from])),
      line('sent', _esc(sent)),
      if (to.isNotEmpty) line('to', addresses(to)),
      if (cc.isNotEmpty) line('cc', addresses(cc)),
      line('subject', _esc(subject)),
    ];
    // id="divRplyFwdMsg" — как у Outlook в вебе: по нему Outlook и другие
    // клиенты узнают начало цитаты и сворачивают её.
    return '<div id="divRplyFwdMsg" style="border:none;border-top:solid #E1E1E1 1.0pt;'
        'padding:3.0pt 0cm 0cm 0cm"><p style="margin:0 0 12px 0">${lines.join('<br>')}</p></div>';
  }

  /// Шапка и исходное письмо целиком — без отступа-цитаты, как в Outlook.
  static String quote(String header, String originalHtml) => '$header<div>$originalHtml</div>';

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

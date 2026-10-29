// lib/services/notifications/notification_text.dart
// Тексты уведомления о письме. 1.8.13 (замечание владельца 29.10.2026:
// «много жирного шрифта, непонятно, на что смотреть»): жирным — одна
// короткая строка, кто написал, как в Почте iPhone, Gmail и Telegram.
// Раньше жирной была тема — длинная («RE: FW: Согласование…»), и в шторке с
// несколькими письмами и сводкой жирные строки шли одна за другой.
// Раскладка:
//   заголовок (жирный)   — отправитель (★ у VIP, 👥 у общего ящика);
//   строка (свёрнуто)    — тема;
//   раскрыто             — тема, ниже текст без цитаты и подписи;
//   шапка уведомления    — 📁 папка (если не «Входящие») и короткая подпись
//                          ящика вместо полного адреса;
//   сводка «N новых писем» — строки «Отправитель — тема» обычным шрифтом.
// iPhone: отправитель — заголовок, тема — подзаголовок, текст — ниже.
// Чистые функции — проверяются тестом notification_text_test.dart.

import '../../core/utils/text_safe.dart' show cleanPreviewText;

class NotificationText {
  NotificationText._();

  /// Начало цитаты или подписи — дальше текст в уведомлении не нужен
  /// («From: … Sent: …» в ответах Outlook занимал все строки уведомления).
  static final _cut = RegExp(
    r'(\s|^)(From:|Sent:|От:|Отправлено:|Von:|Gesendet:|De :|Envoyé :|'
    r'-{2,}\s*(Original Message|Исходное сообщение|Ursprüngliche Nachricht|Message d.origine)|'
    r'_{5,}|'
    r'С уважением|С наилучшими пожеланиями|Best regards|Kind regards|Regards,|'
    r'Mit freundlichen Grüßen|Cordialement|Sent from my|Отправлено с|'
    r'On .{5,60} wrote:|.{0,60} пишет:)',
    caseSensitive: false,
  );

  /// Текст письма для уведомления: без цитаты, подписи и лишних пробелов.
  /// Если после обрезки ничего не осталось — исходный текст (сжатый).
  static String preview(String? raw, {int max = 300}) {
    if (raw == null) return '';
    final flat = cleanPreviewText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.isEmpty) return '';
    final m = _cut.firstMatch(flat);
    var text = m == null ? flat : flat.substring(0, m.start).trim();
    if (text.isEmpty) text = flat;
    if (text.length > max) text = '${text.substring(0, max).trimRight()}…';
    return text;
  }

  /// Заголовок — единственное жирное: кто написал, ★ у VIP, 👥 у общего
  /// ящика.
  static String title(String sender, {bool vip = false, bool shared = false}) =>
      '${shared ? '👥 ' : ''}${vip ? '★ ' : ''}${sender.trim()}';

  /// Тема (или «без темы») — строка под отправителем.
  static String subject(String subject, {required String noSubject}) {
    final s = subject.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? noSubject : s;
  }

  /// Раскрытый текст: тема, ниже — начало текста.
  static String big(String subject, String preview) => preview.isEmpty ? subject : '$subject\n$preview';

  /// Короткая подпись ящика: имя до «@»; если у другого подключённого ящика
  /// такое же имя — домен («i.petrov» / «gmail.com»).
  static String shortMailbox(String email, Iterable<String> otherEmails) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at).toLowerCase();
    final clash = otherEmails.any((o) {
      final i = o.indexOf('@');
      return i > 0 && o.toLowerCase() != email.toLowerCase() && o.substring(0, i).toLowerCase() == local;
    });
    return clash ? email.substring(at + 1) : email.substring(0, at);
  }

  /// Шапка уведомления (рядом с названием приложения): папка и ящик.
  static String? subText({String? folder, String? mailbox}) {
    final parts = [
      if (folder != null && folder.trim().isNotEmpty) '📁 ${folder.trim()}',
      if (mailbox != null && mailbox.trim().isNotEmpty) mailbox.trim(),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Строка сводки группы — обычным шрифтом: «Отправитель — тема». Жирной
  /// темы в каждой строке (до 1.8.13) больше нет: жирный в сводке — только
  /// её заголовок «N новых писем».
  static String summaryLine(String sender, String subject) => '${sender.trim()} — ${subject.trim()}';
}

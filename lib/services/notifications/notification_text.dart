// lib/services/notifications/notification_text.dart
// Тексты уведомления о письме (10.10.2026, по замечанию: «всё в одну строку,
// не понятно о чём, адрес ящика занимает много места, жирным — тема, а не
// отправитель»). Раскладка:
//   заголовок (жирный)   — тема письма (★ у VIP, 👥 у общего ящика);
//   строка (свёрнуто)    — «Отправитель — начало текста»;
//   раскрыто             — отправитель, ниже текст без цитаты и подписи;
//   шапка уведомления    — 📁 папка (если не «Входящие») и короткая подпись
//                          ящика вместо полного адреса;
//   сводка «N новых»     — строки «Отправитель — тема» без жирного (1.8.12).
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

  /// Заголовок: тема (или «без темы»), ★ у VIP, 👥 у общего ящика.
  static String title(String subject, {required String noSubject, bool vip = false, bool shared = false}) {
    final s = subject.trim().isEmpty ? noSubject : subject.trim();
    return '${shared ? '👥 ' : ''}${vip ? '★ ' : ''}$s';
  }

  /// Свёрнутая строка: «Отправитель — начало текста».
  static String line(String sender, String preview) =>
      preview.isEmpty ? sender : '$sender — $preview';

  /// Раскрытый текст: отправитель, ниже — текст.
  static String big(String sender, String preview) => preview.isEmpty ? sender : '$sender\n$preview';

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

  /// Строка сводки группы: «Отправитель — тема», без жирного (1.8.12,
  /// замечание 29.10.2026: «много жирного шрифта, непонятно на что
  /// смотреть» — тема жирным была в каждой из шести строк сводки, рядом с
  /// жирными заголовками уведомлений). Жирное в шторке — только заголовки.
  static String summaryLine(String subject, String sender) => '$sender — $subject';

  static String esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

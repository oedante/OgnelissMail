// lib/core/utils/conversation_links.dart
// Ссылки беседы (2.2.0, план 08.11.2026 «из мессенджеров»: файлы и ссылки
// беседы, как «Ссылки» в профиле чата Telegram и WhatsApp).
//
// Из каждого письма — адреса http(s) ссылок HTML (<a href>) или, у письма
// без HTML, адреса в тексте. Одна ссылка, повторённая в цитатах ответов, —
// один раз, у письма, где она появилась впервые. Служебное приложения
// (люди и даты в тексте, cid:, mailto:, tel:) — не ссылки беседы.

import 'package:html/parser.dart' as html_parser;

/// Письмо беседы для поиска ссылок.
typedef LinkSource = ({String id, DateTime at, String from, String? html, String? plain});

/// Ссылка беседы: адрес, текст ссылки (пусто — текстом был сам адрес или
/// картинка) и письмо, где она появилась впервые.
class ConversationLink {
  final String url;
  final String text;
  final String emailId;
  final DateTime at;
  final String from;
  const ConversationLink({
    required this.url,
    required this.text,
    required this.emailId,
    required this.at,
    required this.from,
  });

  /// Сайт ссылки без «www.» — подпись в списке.
  String get host {
    final h = Uri.tryParse(url)?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : h;
  }
}

final _plainUrl = RegExp(r'''https?://[^\s<>"'«»]+''', caseSensitive: false);
final _trailing = RegExp(r'''[.,;:!?)\]}'"»]+$''');
final _spaces = RegExp(r'\s+');

/// Ключ для склейки повторов: без регистра схемы и сайта, без «/» в конце
/// и без якоря «#…» (та же страница).
String _key(String url) {
  final u = url.trim();
  final uri = Uri.tryParse(u);
  if (uri == null || uri.host.isEmpty) return u;
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}${uri.hasPort ? ':${uri.port}' : ''}'
      '$path${uri.hasQuery ? '?${uri.query}' : ''}';
}

bool _isWeb(String url) {
  final l = url.toLowerCase();
  return (l.startsWith('http://') || l.startsWith('https://')) && (Uri.tryParse(url)?.host.isNotEmpty ?? false);
}

/// Ссылки писем [mails], самые новые — первыми.
List<ConversationLink> conversationLinks(Iterable<LinkSource> mails) {
  final sorted = [...mails]..sort((a, b) => a.at.compareTo(b.at));
  final seen = <String>{};
  final out = <ConversationLink>[];
  void add(LinkSource m, String url, String text) {
    final u = url.trim();
    if (!_isWeb(u) || !seen.add(_key(u))) return;
    final t = text.replaceAll(_spaces, ' ').trim();
    // Текст ссылки — это и есть адрес: подписи не нужно.
    final same = t.isEmpty || _key(t) == _key(u) || u.contains(t);
    out.add(ConversationLink(url: u, text: same ? '' : t, emailId: m.id, at: m.at, from: m.from));
  }

  for (final m in sorted) {
    final html = m.html;
    if (html != null && html.trim().isNotEmpty) {
      final doc = html_parser.parse(html);
      for (final a in doc.querySelectorAll('a[href]')) {
        add(m, a.attributes['href'] ?? '', a.text);
      }
      continue;
    }
    final plain = m.plain;
    if (plain == null) continue;
    for (final match in _plainUrl.allMatches(plain)) {
      add(m, match.group(0)!.replaceAll(_trailing, ''), '');
    }
  }
  return out.reversed.toList();
}

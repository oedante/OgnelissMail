// lib/services/mail/unsubscribe_service.dart
// Отписка от рассылок по стандартным заголовкам письма:
//  · List-Unsubscribe (RFC 2369): <https://…>, <mailto:…?subject=…>;
//  · List-Unsubscribe-Post: List-Unsubscribe=One-Click (RFC 8058) — отписка
//    одним POST-запросом, без страниц и подтверждений на сайте;
//  · List-Id — имя рассылки.
//
// Только по нажатию пользователя. «В одно нажатие» — лишь при пройденной
// проверке отправителя (DKIM/DMARC pass в Authentication-Results): отписка от
// поддельной «рассылки» подтвердила бы мошенникам, что адрес живой. Иначе —
// страница отписки в браузере или письмо для отписки (пользователь видит,
// куда уходит запрос). Текст письма («нажмите, чтобы отписаться») не
// разбираем: только заголовки.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';

/// Заголовки рассылки одной строкой JSON для базы (null — не рассылка).
String? encodeListUnsubscribe({String? unsubscribe, String? post, String? listId}) {
  final u = unsubscribe?.trim();
  if (u == null || u.isEmpty) return null;
  return jsonEncode({
    'u': u,
    if ((post ?? '').trim().isNotEmpty) 'p': post!.trim(),
    if ((listId ?? '').trim().isNotEmpty) 'id': listId!.trim(),
  });
}

class ListUnsubscribe {
  final List<Uri> web;
  final List<Uri> mail;
  final bool oneClick;
  final String? listName;

  const ListUnsubscribe({this.web = const [], this.mail = const [], this.oneClick = false, this.listName});

  bool get isEmpty => web.isEmpty && mail.isEmpty;

  /// Разбор сохранённого JSON (см. [encodeListUnsubscribe]).
  static ListUnsubscribe? parse(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return fromHeaders(m['u'] as String?, post: m['p'] as String?, listId: m['id'] as String?);
    } catch (_) {
      return null;
    }
  }

  /// Разбор заголовков. В List-Unsubscribe адреса — в угловых скобках через
  /// запятую; учитываются только https и mailto (http — нет: запрос шёл бы
  /// открытым текстом).
  static ListUnsubscribe? fromHeaders(String? unsubscribe, {String? post, String? listId}) {
    if (unsubscribe == null || unsubscribe.trim().isEmpty) return null;
    final web = <Uri>[];
    final mail = <Uri>[];
    for (final m in RegExp(r'<([^>]+)>').allMatches(unsubscribe.replaceAll(RegExp(r'\s+'), ''))) {
      final uri = Uri.tryParse(m.group(1)!);
      if (uri == null) continue;
      if (uri.scheme == 'https' && uri.host.isNotEmpty) web.add(uri);
      if (uri.scheme == 'mailto' && uri.path.contains('@')) mail.add(uri);
    }
    final r = ListUnsubscribe(
      web: web,
      mail: mail,
      oneClick: web.isNotEmpty && (post ?? '').toLowerCase().replaceAll(' ', '').contains('list-unsubscribe=one-click'),
      listName: _listName(listId),
    );
    return r.isEmpty ? null : r;
  }

  /// «Новости магазина <news.shop.ru>» → «Новости магазина»; без описания —
  /// идентификатор в скобках.
  static String? _listName(String? listId) {
    final s = listId?.trim();
    if (s == null || s.isEmpty) return null;
    final i = s.indexOf('<');
    final name = (i > 0 ? s.substring(0, i) : s).trim().replaceAll('"', '');
    if (name.isNotEmpty && i > 0) return name;
    return s.replaceAll(RegExp(r'[<>]'), '');
  }
}

/// Проверка отправителя пройдена: DKIM или DMARC = pass и нет провалов.
bool senderAuthenticated(String? authResults) {
  final a = (authResults ?? '').toLowerCase();
  if (a.isEmpty) return false;
  if (a.contains('dkim=fail') || a.contains('dmarc=fail') || a.contains('spf=fail')) return false;
  return a.contains('dkim=pass') || a.contains('dmarc=pass');
}

class UnsubscribeService {
  /// Отписка «в одно нажатие» (RFC 8058): POST с телом
  /// `List-Unsubscribe=One-Click`. true — сервер рассылки принял (2xx).
  static Future<bool> oneClick(Uri uri) async {
    try {
      final r = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'List-Unsubscribe=One-Click',
          )
          .timeout(const Duration(seconds: 20));
      AppLogger.info('Отписка (${uri.host}): HTTP ${r.statusCode}');
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (e) {
      AppLogger.warning('Отписка (${uri.host}): $e');
      return false;
    }
  }
}

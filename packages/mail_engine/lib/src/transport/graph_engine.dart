// lib/src/transport/graph_engine.dart
// Microsoft Graph для ящиков Exchange Online (1.8.11, решение владельца
// 29.10.2026: Graph — часть движка, как EAS и EWS).
//
// Microsoft выключает EWS в Exchange Online: с 1 октября 2026 — по
// организациям, окончательно — в апреле 2027. Почта, календарь, контакты и
// автоответ ящика Exchange Online идут по ActiveSync (EasEngine), а то, что
// шло по EWS, — здесь:
//   • своя карточка и фото — User.Read (/me);
//   • должность, отдел, кабинет и телефоны коллег — People.Read
//     (/me/people); с User.Read.All (выдаёт администратор) — ещё каталог
//     (/users) и руководитель;
//   • фото коллег — User.ReadBasic.All;
//   • подсказки MailTips — Mail.Read / Mail.ReadWrite (/me/getMailTips);
//   • переговорные — Place.Read.All (администратор, /places);
//   • состав рассылок — GroupMember.Read.All (администратор);
//   • категории Outlook и правила «Входящих» — MailboxSettings.ReadWrite;
//   • «Восстановить удалённые» — Mail.ReadWrite (recoverableitemsdeletions).
//
// Токен. Отдельный от токена ActiveSync (у токена Microsoft один ресурс):
// права — [consentScopes] при входе, сам токен — [tokenScopes]. Получает и
// обновляет его приложение, движок просит его через [GraphTokenSource]
// (при первом запросе и после ответа 401 — с force), как EasEngine просит
// токен ActiveSync (AccountConfig.oauthTokenSource).
//
// Нет токена или права — GraphException (forbidden): приложение берёт то же
// из EWS (пока он открыт) или обходится без этого.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../debug_log.dart';
import '../models/graph_models.dart';

/// Действующий токен Graph; null — Graph для ящика недоступен (нет
/// согласия, нет токена). [force] — прежний токен сервер отверг.
typedef GraphTokenSource = Future<String?> Function({bool force});

/// Ответ Graph с ошибкой. [status] 0 — токена нет, запрос не отправлялся.
class GraphException implements Exception {
  final int status;
  final String code;
  final String message;
  const GraphException(this.status, this.code, [this.message = '']);

  /// Нет прав или токена — функцию стоит взять из EWS.
  bool get forbidden => status == 403 || status == 0;
  bool get notFound => status == 404;

  @override
  String toString() => 'Graph $status $code${message.isEmpty ? '' : ': $message'}';
}

class GraphEngine {
  final GraphTokenSource _token;
  final http.Client? _httpOverride;
  final DebugLog? _log;

  GraphEngine({required GraphTokenSource tokenSource, http.Client? httpClient, DebugLog? logger})
      : _token = tokenSource,
        _httpOverride = httpClient,
        _log = logger;

  static const base = 'https://graph.microsoft.com/v1.0';

  /// Права, на которые просится согласие при входе в Exchange Online. Все —
  /// без согласия администратора (иначе обычный сотрудник не смог бы войти).
  static const consentScopes = [
    'https://graph.microsoft.com/User.Read',
    'https://graph.microsoft.com/User.ReadBasic.All',
    'https://graph.microsoft.com/People.Read',
    'https://graph.microsoft.com/Mail.ReadWrite',
    'https://graph.microsoft.com/MailboxSettings.ReadWrite',
  ];

  /// Токен Graph — со всеми правами, на которые есть согласие (свои при входе
  /// и выданные администратором организации).
  static const tokenScopes = ['https://graph.microsoft.com/.default', 'offline_access'];

  static const _userSelect =
      'displayName,givenName,surname,mail,userPrincipalName,jobTitle,department,companyName,officeLocation,'
      'businessPhones,mobilePhone,city';

  /// Путь пользователя по адресу.
  static String userPath(String email) => '/users/${Uri.encodeComponent(email.trim().toLowerCase())}';

  // ════════════════════════ Адресная книга ════════════════════════

  /// Своя карточка (User.Read).
  Future<GraphUser?> me() async {
    final m = await get('/me', query: {r'$select': _userSelect});
    return m is Map<String, dynamic> ? parseUser(m) : null;
  }

  /// Карточка коллеги: люди организации (People.Read), поверх — каталог
  /// (/users), если право на него есть, тогда и руководитель
  /// ([withManager]). null — такого адреса не нашлось.
  Future<GraphUser?> person(String email, {bool withManager = true}) async {
    final e = email.trim().toLowerCase();
    if (!e.contains('@')) return null;
    GraphUser? out;
    try {
      final list = await list_('/me/people', query: {r'$search': '"$e"', r'$top': '10'}, maxPages: 1);
      out = pickPerson(list, e);
    } on GraphException catch (err) {
      if (!err.forbidden && !err.notFound && err.status != 400) rethrow;
    }
    try {
      final m = await get(userPath(e), query: {r'$select': _userSelect});
      if (m is Map<String, dynamic>) {
        final u = parseUser(m);
        if (u != null) out = out == null ? u : out.mergedWith(u);
      }
      final found = out;
      if (withManager && found != null) {
        final mgr = await get('${userPath(e)}/manager', query: {r'$select': 'displayName,mail'});
        final name = mgr is Map ? '${mgr['displayName'] ?? ''}'.trim() : '';
        if (name.isNotEmpty) out = found.withManager(name);
      }
    } on GraphException catch (err) {
      // Нет права на каталог (только User.ReadBasic.All) или руководителя нет.
      if (!err.forbidden && !err.notFound && err.status != 400) rethrow;
    }
    return out;
  }

  /// Фото в высоком качестве; [own] — своё (/me). null — фото нет.
  Future<Uint8List?> photo(String email, {bool own = false}) async {
    final root = own ? '/me' : userPath(email);
    final big = await getBytes('$root/photos/240x240/\$value');
    if (big != null) return big;
    return getBytes('$root/photo/\$value');
  }

  /// Подсказки MailTips для адресатов (до 100 за раз).
  Future<List<GraphMailTip>> mailTips(List<String> emails) async => parseMailTips(await post('/me/getMailTips', {
        'EmailAddresses': emails.take(100).toList(),
        'MailTipsOptions': 'automaticReplies, mailboxFullStatus, totalMemberCount, externalMemberCount',
      }));

  /// Списки переговорных (здания, этажи) — Place.Read.All.
  Future<List<GraphPlace>> roomLists() async =>
      parsePlaces(await list_('/places/microsoft.graph.roomlist', query: {r'$top': '100'}));

  /// Переговорные списка [listEmail].
  Future<List<GraphPlace>> rooms(String listEmail) async => parsePlaces(await list_(
      '/places/${Uri.encodeComponent(listEmail.trim())}/microsoft.graph.roomlist/rooms',
      query: {r'$top': '100'}));

  /// Участники рассылки [email] (GroupMember.Read.All). null — такой группы
  /// в каталоге нет.
  Future<List<GraphUser>?> groupMembers(String email) async {
    final e = email.trim().toLowerCase().replaceAll("'", "''");
    final groups = await list_('/groups', query: {r'$filter': "mail eq '$e'", r'$select': 'id'}, maxPages: 1);
    final id = groups.isEmpty ? null : groups.first['id'];
    if (id is! String || id.isEmpty) return null;
    final members = await list_('/groups/${Uri.encodeComponent(id)}/transitiveMembers',
        query: {r'$select': 'displayName,mail,jobTitle,department,officeLocation', r'$top': '999'});
    return [
      for (final m in members)
        if (parseUser(m) case final u?) u,
    ];
  }

  /// Главный список категорий Outlook (MailboxSettings.Read).
  Future<List<GraphCategory>> masterCategories() async =>
      parseCategories(await list_('/me/outlook/masterCategories', maxPages: 2));

  // ════════════════════════ Правила «Входящих» ════════════════════════

  static const _rules = '/me/mailFolders/inbox/messageRules';

  Future<List<GraphRule>> rules() async => parseRules(await list_(_rules));

  /// Включить или выключить правило (меняется только isEnabled — правило не
  /// заменяется целиком, как в EWS).
  Future<void> setRuleEnabled(String id, bool enabled) async {
    await patch('$_rules/${Uri.encodeComponent(id)}', {'isEnabled': enabled});
  }

  Future<void> createRule(GraphRuleSpec spec) async {
    await post(_rules, spec.toJson());
  }

  Future<void> deleteRule(String id) => delete('$_rules/${Uri.encodeComponent(id)}');

  /// Папки почты для «Переложить в папку»: путь «Папка/Подпапка», без
  /// «Черновиков» и «Исходящих», не глубже 4 уровней и не больше 300.
  Future<List<GraphFolder>> mailFolders() async {
    final skip = <String>{};
    for (final name in const ['drafts', 'outbox']) {
      try {
        final f = await get('/me/mailFolders/$name', query: {r'$select': 'id'});
        if (f is Map && f['id'] is String) skip.add(f['id'] as String);
      } catch (_) {}
    }
    final out = <GraphFolder>[];
    var level = <GraphFolder>[];
    void take(List<Map<String, dynamic>> list, String prefix, List<GraphFolder> next) {
      for (final f in list) {
        final id = f['id'];
        if (id is! String) continue;
        final path = '$prefix${f['displayName'] ?? ''}';
        if (!skip.contains(id)) out.add(GraphFolder(id: id, path: path));
        if ((f['childFolderCount'] as num? ?? 0) > 0) next.add(GraphFolder(id: id, path: path));
      }
    }

    const sel = {r'$select': 'id,displayName,childFolderCount', r'$top': '100'};
    take(await list_('/me/mailFolders', query: sel), '', level);
    for (var depth = 0; depth < 3 && level.isNotEmpty && out.length < 300; depth++) {
      final next = <GraphFolder>[];
      for (final p in level) {
        take(await list_('/me/mailFolders/${Uri.encodeComponent(p.id)}/childFolders', query: sel, maxPages: 2),
            '${p.path}/', next);
      }
      level = next;
    }
    out.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return out;
  }

  // ════════════════════════ Восстановить удалённые ════════════════════════

  /// Письма, удалённые из «Удалённых» (Exchange хранит их ~14 дней).
  Future<List<GraphMessageInfo>> recoverableItems({int max = 100}) async =>
      parseMessages(await list_('/me/mailFolders/recoverableitemsdeletions/messages',
          query: {
            r'$select': 'subject,from,receivedDateTime',
            r'$orderby': 'receivedDateTime desc',
            r'$top': '${max.clamp(1, 100)}',
          },
          maxPages: 1));

  /// Вернуть письма во «Входящие». Возвращает, сколько вернулось.
  Future<int> restoreToInbox(List<String> ids) async {
    var n = 0;
    for (final id in ids) {
      try {
        await post('/me/messages/${Uri.encodeComponent(id)}/move', {'destinationId': 'inbox'});
        n++;
      } catch (e) {
        _log?.warn('GRAPH', 'письмо не восстановлено: $e');
      }
    }
    return n;
  }

  // ════════════════════════ Запросы ════════════════════════

  Future<Object?> get(String path, {Map<String, String>? query}) async =>
      _json(await _send('GET', path, query: query));

  /// Двоичный ответ (фото). null — нет (404).
  Future<Uint8List?> getBytes(String path) async {
    try {
      final r = await _send('GET', path);
      return r.bodyBytes.isEmpty ? null : r.bodyBytes;
    } on GraphException catch (e) {
      if (e.notFound) return null;
      rethrow;
    }
  }

  Future<Object?> post(String path, Object body) async => _json(await _send('POST', path, body: body));

  Future<Object?> patch(String path, Object body) async => _json(await _send('PATCH', path, body: body));

  Future<void> delete(String path) async {
    await _send('DELETE', path);
  }

  /// Все страницы списка (@odata.nextLink), не больше [maxPages].
  Future<List<Map<String, dynamic>>> list_(String path, {Map<String, String>? query, int maxPages = 5}) async {
    final out = <Map<String, dynamic>>[];
    var r = await get(path, query: query);
    for (var page = 0; page < maxPages; page++) {
      if (r is! Map) break;
      final v = r['value'];
      if (v is List) out.addAll(v.whereType<Map<String, dynamic>>());
      final next = r['@odata.nextLink'];
      if (next is! String || !next.startsWith(base) || page == maxPages - 1) break;
      r = await get(next.substring(base.length));
    }
    return out;
  }

  static Object? _json(http.Response r) => r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));

  Future<http.Response> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    var at = await _token();
    if (at == null || at.isEmpty) throw const GraphException(0, 'unavailable');
    // Путь уже со строкой запроса (@odata.nextLink) — как есть.
    final uri = query == null || query.isEmpty
        ? Uri.parse('$base$path')
        : Uri.parse('$base$path').replace(queryParameters: query);
    Future<http.Response> once(String t) async {
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer $t'
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final client = _httpOverride ?? http.Client();
      try {
        final s = await client.send(req).timeout(const Duration(seconds: 30));
        return await http.Response.fromStream(s);
      } finally {
        if (_httpOverride == null) client.close();
      }
    }

    final t0 = DateTime.now();
    var r = await once(at);
    if (r.statusCode == 401) {
      at = await _token(force: true);
      if (at == null || at.isEmpty) throw const GraphException(0, 'unavailable');
      r = await once(at);
    }
    // Ограничение запросов (429) и перегрузка сервиса (503, 504): Graph
    // сообщает, сколько подождать (Retry-After, секунды), — одна повторная
    // попытка, не дольше 30 с (1.8.13; раньше ошибка сразу).
    final wait = retryDelay(r.statusCode, r.headers['retry-after']);
    if (wait != null) {
      _log?.info('GRAPH', '$method ${uri.path} → ${r.statusCode}, повтор через ${wait.inSeconds} с');
      await Future<void>.delayed(wait);
      r = await once(at);
    }
    final ms = DateTime.now().difference(t0).inMilliseconds;
    if (r.statusCode >= 200 && r.statusCode < 300) {
      _log?.debug('GRAPH', '$method ${uri.path} → ${r.statusCode} (${ms}ms)');
      return r;
    }
    final err = parseError(r.body);
    final e = GraphException(r.statusCode, err.code, err.message);
    _log?.info('GRAPH', '$method ${uri.path} → $e (${ms}ms)');
    throw e;
  }

  /// Пауза перед повтором для ответа [status]: 429, 503, 504 — по
  /// Retry-After (секунды; без заголовка — 2 с), не больше 30 с. null —
  /// повторять не нужно.
  static Duration? retryDelay(int status, String? retryAfter) {
    if (status != 429 && status != 503 && status != 504) return null;
    final sec = int.tryParse(retryAfter?.trim() ?? '') ?? 2;
    return Duration(seconds: sec.clamp(0, 30));
  }

  // ════════════════════════ Разбор ответов ════════════════════════

  /// Ошибка Graph: {"error": {"code": "...", "message": "..."}}.
  static ({String code, String message}) parseError(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['error'] is Map) {
        final e = m['error'] as Map;
        var msg = '${e['message'] ?? ''}'.trim();
        if (msg.length > 200) msg = '${msg.substring(0, 200)}…';
        return (code: '${e['code'] ?? ''}', message: msg);
      }
    } catch (_) {}
    return (code: '', message: '');
  }

  static String? _s(Object? v) {
    final t = v is String ? v.trim() : '';
    return t.isEmpty ? null : t;
  }

  /// Пользователь каталога (/me, /users, участник группы). null — без адреса.
  static GraphUser? parseUser(Map<String, dynamic> m) {
    final email = (_s(m['mail']) ?? _s(m['userPrincipalName']) ?? '').toLowerCase();
    if (!email.contains('@')) return null;
    final phones = m['businessPhones'];
    String? work;
    if (phones is List) {
      for (final p in phones.whereType<String>()) {
        if (p.trim().isNotEmpty) {
          work = p.trim();
          break;
        }
      }
    }
    return GraphUser(
      email: email,
      displayName: _s(m['displayName']) ?? email,
      givenName: _s(m['givenName']),
      surname: _s(m['surname']),
      jobTitle: _s(m['jobTitle']),
      department: _s(m['department']),
      company: _s(m['companyName']),
      office: _s(m['officeLocation']),
      businessPhone: work,
      mobilePhone: _s(m['mobilePhone']),
      city: _s(m['city']),
    );
  }

  /// Человек из /me/people с адресом [email]: сначала сотрудник организации.
  static GraphUser? pickPerson(List<Map<String, dynamic>> people, String email) {
    final e = email.trim().toLowerCase();
    Map<String, dynamic>? hit;
    for (final p in people) {
      final addrs = p['scoredEmailAddresses'];
      final has = addrs is List && addrs.whereType<Map>().any((x) => '${x['address'] ?? ''}'.trim().toLowerCase() == e);
      if (!has) continue;
      final type = p['personType'];
      final org = type is Map && type['subclass'] == 'OrganizationUser';
      if (hit == null || org) hit = p;
      if (org) break;
    }
    final h = hit;
    if (h == null) return null;
    String? phone(String type) {
      final list = h['phones'];
      if (list is! List) return null;
      for (final x in list.whereType<Map>()) {
        if (x['type'] == type) return _s(x['number']);
      }
      return null;
    }

    return GraphUser(
      email: e,
      displayName: _s(h['displayName']) ?? e,
      givenName: _s(h['givenName']),
      surname: _s(h['surname']),
      jobTitle: _s(h['jobTitle']),
      department: _s(h['department']),
      company: _s(h['companyName']),
      office: _s(h['officeLocation']),
      businessPhone: phone('business'),
      mobilePhone: phone('mobile'),
    );
  }

  /// Ответ /me/getMailTips → подсказки.
  static List<GraphMailTip> parseMailTips(Object? r) {
    final list = r is Map ? r['value'] : null;
    if (list is! List) return const [];
    final out = <GraphMailTip>[];
    for (final t in list.whereType<Map>()) {
      final addr = t['emailAddress'];
      final email = (addr is Map ? '${addr['address'] ?? ''}' : '').trim().toLowerCase();
      if (!email.contains('@')) continue;
      final ar = t['automaticReplies'];
      final text = ar is Map ? plainText('${ar['message'] ?? ''}') : '';
      int? n(Object? v) => v is num ? v.toInt() : null;
      out.add(GraphMailTip(
        email: email,
        name: addr is Map ? '${addr['name'] ?? ''}'.trim() : '',
        autoReply: text.isEmpty ? null : text,
        mailboxFull: t['mailboxFull'] == true,
        totalMembers: n(t['totalMemberCount']),
        externalMembers: n(t['externalMemberCount']),
      ));
    }
    return out;
  }

  /// Текст из HTML одной строкой, не длиннее 240 знаков (автоответ).
  static String plainText(String html) {
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

  /// Места (/places) → переговорные или их списки.
  static List<GraphPlace> parsePlaces(List<Map<String, dynamic>> list) => [
        for (final p in list)
          if (_s(p['emailAddress']) case final email?) GraphPlace(name: _s(p['displayName']) ?? email, email: email),
      ];

  static List<GraphCategory> parseCategories(List<Map<String, dynamic>> list) => [
        for (final c in list)
          if (_s(c['displayName']) case final name?)
            GraphCategory(name: name, color: int.tryParse('${c['color'] ?? ''}'.replaceFirst('preset', '')) ?? -1),
      ];

  /// Действия messageRule → коды.
  static const _actionMap = {
    'moveToFolder': 'move',
    'copyToFolder': 'copy',
    'delete': 'delete',
    'permanentDelete': 'delete',
    'forwardTo': 'forward',
    'forwardAsAttachmentTo': 'forward',
    'redirectTo': 'redirect',
    'markAsRead': 'read',
    'markImportance': 'importance',
    'assignCategories': 'category',
    'stopProcessingRules': 'stop',
  };

  /// messageRules → правила по порядку выполнения.
  static List<GraphRule> parseRules(List<Map<String, dynamic>> list) {
    final out = <GraphRule>[];
    for (final r in list) {
      final id = r['id'];
      if (id is! String || id.isEmpty) continue;
      final actions = <String>{};
      final a = r['actions'];
      if (a is Map) {
        for (final e in a.entries) {
          final v = e.value;
          final on = v == true || (v is String && v.isNotEmpty) || (v is List && v.isNotEmpty);
          final code = _actionMap[e.key];
          if (on && code != null) actions.add(code);
        }
      }
      out.add(GraphRule(
        id: id,
        name: '${r['displayName'] ?? ''}',
        enabled: r['isEnabled'] != false,
        sequence: (r['sequence'] as num?)?.toInt() ?? 1,
        readOnly: r['isReadOnly'] == true,
        hasError: r['hasError'] == true,
        actions: actions,
        raw: r,
      ));
    }
    out.sort((a, b) => a.sequence.compareTo(b.sequence));
    return out;
  }

  /// Письма (subject, from, receivedDateTime).
  static List<GraphMessageInfo> parseMessages(List<Map<String, dynamic>> list) => [
        for (final m in list)
          if (m['id'] case final String id when id.isNotEmpty)
            GraphMessageInfo(
              id: id,
              subject: '${m['subject'] ?? ''}',
              from: () {
                final f = m['from'];
                final e = f is Map ? f['emailAddress'] : null;
                if (e is! Map) return '';
                final name = '${e['name'] ?? ''}'.trim();
                return name.isNotEmpty ? name : '${e['address'] ?? ''}'.trim();
              }(),
              received: DateTime.tryParse('${m['receivedDateTime'] ?? ''}')?.toLocal(),
            ),
      ];
}

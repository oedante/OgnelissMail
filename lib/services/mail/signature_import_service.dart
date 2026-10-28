// lib/services/mail/signature_import_service.dart
// Импорт подписи из почтового ящика (где возможно):
//  • Gmail        → Gmail REST API (settings/sendAs), берём signature (HTML) у isPrimary.
//  • Exchange on-prem → EWS GetUserConfiguration (OWA.UserOptions → signaturehtml).
//  • Exchange Online (M365) → Microsoft Graph (mailboxSettings.owaSettings.signatureHtml).
//  • Все прочие (Яндекс/Mail.ru/IMAP) → эвристика: разбор «хвоста» последних писем в
//    папке «Отправленные» (локальный кэш). Также служит универсальным фолбэком.
// Всё клиентское, XML EWS парсится во Flutter (пакет xml, как в ews_xml_parser).

import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import 'ews/ews_service.dart';
import 'oauth/oauth_proxy_client.dart';

typedef ImportedSignature = ({String html, String plain});

class SignatureImportService {
  final AppDatabase _db;
  final EwsService _ews;
  final OAuthProxyClient _oauth;
  SignatureImportService(this._db, this._ews, this._oauth);

  /// Импортировать подпись для аккаунта. Пытается провайдер-специфичный способ,
  /// затем универсальную эвристику по «Отправленным». null — если не удалось.
  Future<ImportedSignature?> importSignature(AccountModel account) async {
    try {
      if (account.type == AccountType.google) {
        final r = await _fromGmail(account);
        if (r != null) return r;
      } else if (account.usesEws) {
        final html = await _ews.getOwaSignatureHtml(account);
        if (html != null && html.trim().isNotEmpty) {
          return (html: html, plain: _stripHtml(html));
        }
      } else if (account.type == AccountType.exchange) {
        final r = await _fromGraph(account);
        if (r != null) return r;
      }
    } catch (_) {}
    return _fromSentEmails(account.id);
  }

  // ── Gmail REST: GET users/me/settings/sendAs ──
  // Требует OAuth-scope https://www.googleapis.com/auth/gmail.settings.basic
  // (добавляется на стороне OAuth-прокси). Без него вернётся 403 → фолбэк.
  Future<ImportedSignature?> _fromGmail(AccountModel account) async {
    final token = await _oauth.getAccessToken(account.id);
    if (token == null) return null;
    final resp = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/settings/sendAs'),
      headers: {'Authorization': 'Bearer ${token.accessToken}'},
    );
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['sendAs'] as List?) ?? [];
    Map<String, dynamic>? primary;
    for (final e in list) {
      if (e is Map<String, dynamic> && e['isPrimary'] == true) {
        primary = e;
        break;
      }
    }
    primary ??= list.isNotEmpty ? list.first as Map<String, dynamic> : null;
    final html = primary?['signature'] as String?;
    if (html == null || html.trim().isEmpty) return null;
    return (html: html, plain: _stripHtml(html));
  }

  // ── Microsoft Graph: GET /me/mailboxSettings ──
  // Требует scope MailboxSettings.Read. owaSettings/signatureHtml (beta-поле).
  Future<ImportedSignature?> _fromGraph(AccountModel account) async {
    final token = await _oauth.getAccessToken(account.id);
    if (token == null) return null;
    final resp = await http.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me/mailboxSettings'),
      headers: {'Authorization': 'Bearer ${token.accessToken}'},
    );
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final owa = data['owaSettings'] as Map<String, dynamic>?;
    final signWithHtml = owa?['signWithHtml'];
    final html = owa?['signatureHtml'] as String?;
    if (html == null || html.trim().isEmpty) return null;
    // Если сервер сообщает, что подпись не в HTML — всё равно вернём как есть.
    if (signWithHtml == false) {
      final plainOwa = owa?['signatureText'] as String? ?? _stripHtml(html);
      return (html: _plainToHtml(plainOwa), plain: plainOwa);
    }
    return (html: html, plain: _stripHtml(html));
  }

  // ── Эвристика: подпись из «хвоста» последних отправленных писем ──
  Future<ImportedSignature?> _fromSentEmails(String accountId) async {
    final rows = await _db.customSelect(
      'SELECT body_plain, body_html FROM emails WHERE account_id = ? '
      "AND (lower(folder_name) LIKE '%sent%' OR folder_name LIKE '%тправл%') "
      'AND (body_plain IS NOT NULL OR body_html IS NOT NULL) '
      'ORDER BY received_at DESC LIMIT 5',
      variables: [Variable.withString(accountId)],
      readsFrom: {_db.emails},
    ).get();
    for (final r in rows) {
      final sig = _extractSignature(
          r.data['body_plain'] as String?, r.data['body_html'] as String?);
      if (sig != null) return sig;
    }
    return null;
  }

  /// Выделить блок подписи из тела письма (снизу вверх).
  ImportedSignature? _extractSignature(String? bodyPlain, String? bodyHtml) {
    final text = (bodyPlain != null && bodyPlain.trim().isNotEmpty)
        ? bodyPlain
        : _stripHtml(bodyHtml ?? '');
    if (text.trim().isEmpty) return null;
    final lines = text.split('\n');

    // 1) Стандартный разделитель RFC 3676 «-- ».
    for (int i = lines.length - 1; i >= 0; i--) {
      final t = lines[i].trimRight();
      if (t == '--' || t == '-- ') {
        final sig = lines.sublist(i + 1).join('\n').trim();
        if (sig.isNotEmpty) return (html: _plainToHtml(sig), plain: sig);
      }
    }

    // 2) Эвристика: хвостовой блок с типичными маркерами подписи.
    final markers = RegExp(
        r'(С уважением|Best regards|Regards|Sincerely|тел\.?|phone|моб\.?|mobile|@|https?:)',
        caseSensitive: false);
    int start = -1;
    for (int i = lines.length - 1; i >= 0 && i >= lines.length - 8; i--) {
      if (markers.hasMatch(lines[i])) {
        start = i;
      }
    }
    if (start >= 0) {
      int top = start;
      while (top > 0 && lines[top - 1].trim().isNotEmpty && (lines.length - top) < 10) {
        top--;
      }
      final sig = lines.sublist(top).join('\n').trim();
      if (sig.isNotEmpty && sig.length < 800) {
        return (html: _plainToHtml(sig), plain: sig);
      }
    }
    return null;
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'</p>|</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  String _plainToHtml(String text) {
    final esc = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\n', '<br>');
    return '<div>$esc</div>';
  }
}

final signatureImportServiceProvider = Provider<SignatureImportService>((ref) {
  return SignatureImportService(
    ref.watch(databaseProvider),
    ref.watch(ewsServiceProvider),
    ref.watch(oauthProxyClientProvider),
  );
});

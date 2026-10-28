// lib/core/security/link_opener.dart
// Открытие ссылок из писем.
//
// Раньше нажатие на ссылку в письме ничего не делало (onLinkTap был пустым).
// Теперь:
// - mailto: открывает новое письмо этому адресату;
// - tel: — звонилку;
// - http(s): — диалог с НАСТОЯЩИМ адресом (жирным — домен), с
//   предупреждениями, если текст ссылки показывает другой домен (типичный
//   фишинг), если адрес без шифрования, по IP или в punycode (xn--);
// - всё остальное (javascript:, file:, cid: …) не открывается.

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/integration/mailto_service.dart' show MailtoRequest;

class LinkCheck {
  final Uri uri;
  final bool textMismatch;
  final String? shownDomain;
  final bool insecure;
  final bool suspiciousHost;

  const LinkCheck({
    required this.uri,
    this.textMismatch = false,
    this.shownDomain,
    this.insecure = false,
    this.suspiciousHost = false,
  });

  bool get hasWarning => textMismatch || insecure || suspiciousHost;
}

class LinkOpener {
  LinkOpener._();

  static final _domainInText =
      RegExp(r'(?:https?://)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?:[/:?#]|$|\s)', caseSensitive: false);
  static final _ipHost = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// Проверка ссылки (без UI) — отдельно, чтобы покрыть тестами.
  static LinkCheck? check(String url, {String? linkText}) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    String? shown;
    var mismatch = false;
    final text = (linkText ?? '').trim().toLowerCase();
    if (text.isNotEmpty) {
      final m = _domainInText.firstMatch(text);
      if (m != null) {
        shown = m.group(1)!;
        final s = shown.startsWith('www.') ? shown.substring(4) : shown;
        final h = host.startsWith('www.') ? host.substring(4) : host;
        // Совпадение — тот же домен или поддомен в любую сторону.
        mismatch = !(h == s || h.endsWith('.$s') || s.endsWith('.$h'));
      }
    }
    return LinkCheck(
      uri: uri,
      textMismatch: mismatch,
      shownDomain: shown,
      insecure: uri.scheme == 'http',
      suspiciousHost: _ipHost.hasMatch(host) || host.split('.').any((p) => p.startsWith('xn--')) ||
          uri.userInfo.isNotEmpty,
    );
  }

  static Future<void> open(BuildContext context, String? url,
      {String? linkText, String? accountId}) async {
    if (url == null) return;
    final raw = url.trim();
    if (raw.isEmpty || raw.startsWith('#')) return;
    final lower = raw.toLowerCase();

    if (lower.startsWith('mailto:')) {
      // Тема, копия и текст из ссылки — тоже (mailto:кому?subject=…&body=…).
      final q = <String, String>{...?MailtoRequest.parse(raw)?.toQuery()};
      if (accountId != null) q['accountId'] = accountId;
      unawaited(context.push(Uri(path: '/compose', queryParameters: q).toString()));
      return;
    }
    if (lower.startsWith('tel:')) {
      final uri = Uri.tryParse(raw);
      if (uri != null) await launchUrl(uri);
      return;
    }

    final c = check(raw, linkText: linkText);
    if (c == null) return; // javascript:, file:, data:, cid: — не открываем
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LinkDialog(check: c),
    );
    if (ok == true) {
      await launchUrl(c.uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _LinkDialog extends StatelessWidget {
  final LinkCheck check;
  const _LinkDialog({required this.check});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final warn = theme.colorScheme.error;
    Widget warning(String text) => Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(AppIcons.warning, size: 18, color: warn),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(color: warn))),
          ]),
        );
    return AlertDialog(
      title: Text(l10n.tr('openLinkTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(check.uri.host,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: Space.xs),
            SelectableText(check.uri.toString(),
                maxLines: 4, style: theme.textTheme.bodySmall),
            if (check.textMismatch)
              warning(l10n.tr('linkMismatch').replaceAll('{shown}', check.shownDomain ?? '')),
            if (check.insecure) warning(l10n.tr('linkInsecure')),
            if (check.suspiciousHost) warning(l10n.tr('linkSuspicious')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: check.uri.toString()));
            Navigator.of(context).pop(false);
          },
          child: Text(l10n.tr('copyLink')),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(
          style: check.hasWarning ? FilledButton.styleFrom(backgroundColor: warn) : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.tr('openLink')),
        ),
      ],
    );
  }
}

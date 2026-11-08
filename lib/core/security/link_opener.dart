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

  /// Домен, похожий на чужой (план 08.11.2026 п. 2): в одной части адреса
  /// латиница вместе с кириллицей («paypаl.com» с русской «а»), буквы других
  /// алфавитов, или кириллическая часть под латинской зоной («аррlе.com»
  /// русскими буквами). Кириллический сайт в кириллической зоне («сайт.рф»)
  /// — обычный. Части в punycode (xn--…) раскодируются; не раскодировались —
  /// подозрительно. Раньше подозрительной считалась любая часть xn--, в том
  /// числе каждый сайт .рф, а домен кириллицей без punycode — нет.
  @visibleForTesting
  static bool confusableHost(String host) {
    final labels = <String>[];
    for (final raw in host.toLowerCase().split('.')) {
      var label = raw;
      if (label.startsWith('xn--')) {
        final d = _punyDecode(label.substring(4));
        if (d == null) return true;
        label = d;
      } else if (label.contains('%')) {
        try {
          label = Uri.decodeComponent(label);
        } catch (_) {
          return true;
        }
      }
      labels.add(label);
    }
    if (labels.isEmpty) return false;
    final tldCyrillic = _cyr.hasMatch(labels.last);
    for (final l in labels) {
      final latin = _latin.hasMatch(l);
      final cyr = _cyr.hasMatch(l);
      if (latin && cyr) return true;
      if (_otherScript.hasMatch(l)) return true;
      if (cyr && !tldCyrillic) return true;
    }
    return false;
  }

  static final _latin = RegExp('[a-z]');
  static final _cyr = RegExp('[Ѐ-ӿ]');
  // Не ASCII и не кириллица (греческий, армянский, полноширинные и т. п.).
  static final _otherScript = RegExp('[^\u0000-\u007FЀ-ӿ]');

  /// Punycode (RFC 3492) → строка; null — неверная запись.
  static String? _punyDecode(String input) {
    const base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700;
    var n = 128, i = 0, bias = 72;
    final out = <int>[];
    final delim = input.lastIndexOf('-');
    if (delim > 0) {
      for (final c in input.substring(0, delim).codeUnits) {
        if (c >= 0x80) return null;
        out.add(c);
      }
    }
    var pos = delim > 0 ? delim + 1 : 0;
    int adapt(int delta, int numPoints, bool first) {
      delta = first ? delta ~/ damp : delta ~/ 2;
      delta += delta ~/ numPoints;
      var k = 0;
      while (delta > ((base - tMin) * tMax) ~/ 2) {
        delta ~/= base - tMin;
        k += base;
      }
      return k + (base - tMin + 1) * delta ~/ (delta + skew);
    }

    while (pos < input.length) {
      final oldi = i;
      var w = 1;
      for (var k = base;; k += base) {
        if (pos >= input.length) return null;
        final c = input.codeUnitAt(pos++);
        final digit = c >= 0x30 && c <= 0x39
            ? c - 22
            : c >= 0x61 && c <= 0x7a
                ? c - 0x61
                : c >= 0x41 && c <= 0x5a
                    ? c - 0x41
                    : -1;
        if (digit < 0) return null;
        i += digit * w;
        final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
        if (digit < t) break;
        w *= base - t;
        if (w > 0x7fffffff) return null;
      }
      bias = adapt(i - oldi, out.length + 1, oldi == 0);
      n += i ~/ (out.length + 1);
      i %= out.length + 1;
      if (n > 0x10FFFF) return null;
      out.insert(i, n);
      i++;
    }
    return String.fromCharCodes(out);
  }

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
      suspiciousHost: _ipHost.hasMatch(host) || confusableHost(host) || uri.userInfo.isNotEmpty,
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

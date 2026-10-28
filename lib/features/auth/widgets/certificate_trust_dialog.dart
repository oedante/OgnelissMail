// lib/features/auth/widgets/certificate_trust_dialog.dart
// «Сертификат сервера не подтверждён» — показать, кем выдан сертификат, и
// его отпечаток SHA-256, чтобы сверить с ИТ-отделом перед тем, как доверять.
//
// Так ведут себя корпоративные серверы с сертификатом внутреннего центра или
// без промежуточного сертификата (Outlook для Android в таком случае
// пишет «Trust anchor for certification path not found»). Доверие выдаётся
// одному сертификату на одном хосте — не «принимать любые», как в
// BlackBerry Hub с параметром «Небезопасные соединения: принять».

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/security/certificate_pinning_service.dart';
import '../../../l10n/app_localizations.dart';

/// true — пользователь решил доверять сертификату.
Future<bool> showCertificateTrustDialog(BuildContext context, RejectedCertificate c) async {
  final l10n = AppLocalizations.of(context);
  final date = DateFormat.yMMMd(Localizations.localeOf(context).languageCode);
  final theme = Theme.of(context);
  Widget row(String label, String value, {bool mono = false}) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            SelectableText(value,
                style: mono
                    ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                    : theme.textTheme.bodyMedium),
          ],
        ),
      );

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(AppIcons.gpp_maybe, color: theme.colorScheme.error),
      title: Text(l10n.tr('certUntrustedTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('certUntrustedBody').replaceAll('{host}', c.host)),
            if (c.expired)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(l10n.tr('certExpired'),
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
              ),
            row(l10n.tr('certSubject'), c.subject),
            row(l10n.tr('certIssuer'), c.issuer),
            row(l10n.tr('certValidity'), '${date.format(c.validFrom)} — ${date.format(c.validTo)}'),
            row(l10n.tr('certFingerprint'), c.fingerprintHex, mono: true),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Clipboard.setData(ClipboardData(text: c.fingerprintHex)),
          child: Text(l10n.tr('copy')),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('certTrust'))),
      ],
    ),
  );
  return ok == true;
}

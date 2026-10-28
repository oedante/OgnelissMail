// lib/features/mail/widgets/email_header_expanded.dart

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class EmailHeaderExpanded extends StatelessWidget {
  final EmailModel email;
  final AppLocalizations l10n;

  const EmailHeaderExpanded({super.key, required this.email, required this.l10n});

  @override
  Widget build(BuildContext context) {

    return Card(
      margin: const EdgeInsets.only(top: Space.s),
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(l10n.tr('from'), '${email.from.displayName ?? ""} <${email.from.email}>', context),
            if (email.to.isNotEmpty)
              _row(l10n.tr('to'), email.to.map((r) => '${r.displayName ?? ""} <${r.email}>').join(', '), context),
            if (email.cc.isNotEmpty)
              _row(l10n.tr('cc'), email.cc.map((r) => '${r.displayName ?? ""} <${r.email}>').join(', '), context),
            if (email.bcc.isNotEmpty)
              _row(l10n.tr('bcc'), email.bcc.map((r) => '${r.displayName ?? ""} <${r.email}>').join(', '), context),
            _row(l10n.tr('date'), _formatFull(email.receivedAt), context),
            if (email.internetMessageId != null)
              _row('Message-ID', email.internetMessageId!, context, copyable: true),
            if (email.size != null)
              _row(l10n.tr('size'), _formatSize(email.size!), context),

            const SizedBox(height: Space.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(AppIcons.expand_less, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, BuildContext context, {bool copyable = false}) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: GestureDetector(
              onLongPress: copyable ? () {
                Clipboard.setData(ClipboardData(text: value));
                showInlineNotice(l10n.copied, duration: const Duration(seconds: 2));
              } : null,
              child: Text(value, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ],
      ),
    );
  }

  /// Полная дата на языке интерфейса: «7 октября 2026, 14:30» / «7 October 2026, 14:30».
  String _formatFull(DateTime date) =>
      DateFormat('d MMMM y, HH:mm', l10n.localeCode).format(date.toLocal());

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes ${l10n.tr('unitB')}';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ${l10n.tr('unitKB')}';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ${l10n.tr('unitMB')}';
  }
}
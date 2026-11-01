// lib/features/mail/widgets/delivery_status_banner.dart
// Доставка своего письма (1.9.x, просьба владельца 31.10.2026): под шапкой
// письма — строка на адресата из отчётов сервера: «Не доставлено:
// user@x — адрес не существует (5.1.1)» с кнопками «Отправить снова» и
// «Изменить адрес»; «Задерживается…»; «Доставлено на сервер получателя»
// (с оговоркой: это не уведомление о прочтении). На самом письме-отчёте —
// чип «Отчёт о доставке», он открывает своё письмо.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_router.dart' show messagePath;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/delivery/delivery_report.dart';
import '../../../services/mail/delivery/delivery_report_service.dart';
import '../providers/delivery_status_provider.dart';

class DeliveryStatusBanner extends ConsumerWidget {
  final EmailModel email;

  const DeliveryStatusBanner({super.key, required this.email});

  /// Строка статуса адресата: «Не доставлено: user@x — адрес не существует (5.1.1)».
  static String lineFor(AppLocalizations l10n, DeliveryStatus s) {
    final action = DeliveryReport.actionOf(s.action) ?? DeliveryAction.failed;
    final reason = DeliveryReport.reasonOf(action, s.status, s.diagnostic);
    final code = s.status == null || action != DeliveryAction.failed ? '' : ' (${s.status})';
    return switch (action) {
      DeliveryAction.failed =>
        '${l10n.tr('dsnFailed').replaceAll('{addr}', s.recipient)} — ${l10n.tr(reason.l10nKey)}$code',
      DeliveryAction.delayed =>
        '${l10n.tr('dsnDelayed').replaceAll('{addr}', s.recipient)} — ${l10n.tr(reason.l10nKey)}',
      _ => l10n.tr('dsnDelivered').replaceAll('{addr}', s.recipient),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = deliveryKeyOf(email);
    final rows = key == null ? const <DeliveryStatus>[] : (ref.watch(deliveryStatusesProvider(key)).value ?? const []);
    if (rows.isEmpty) return _ReportChip(email: email);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final failed = [for (final r in rows) if (r.action == 'failed') r.recipient];
    final delivered = rows.any((r) => r.action != 'failed' && r.action != 'delayed');
    final color = failed.isNotEmpty ? AppColors.errorRed : theme.colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows) _row(context, l10n, r),
          if (delivered)
            Padding(
              padding: const EdgeInsets.only(left: Sizes.iconInline + Space.s, bottom: Space.xs),
              child: Text(l10n.tr('dsnDeliveredNote'),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ),
          if (failed.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Space.xs,
              children: [
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _compose(context, failed),
                  child: Text(l10n.tr('dsnResend')),
                ),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => _changeAddress(context, l10n, failed),
                  child: Text(l10n.tr('dsnChangeAddress')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n, DeliveryStatus s) {
    final theme = Theme.of(context);
    final (icon, color) = switch (s.action) {
      'failed' => (AppIcons.error, AppColors.errorRed),
      'delayed' => (AppIcons.schedule, AppColors.accentOrangeText(context)),
      _ => (AppIcons.mark_email_read, AppColors.successText(context)),
    };
    final diag = s.diagnostic;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: Sizes.iconInline, color: color),
          const SizedBox(width: Space.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lineFor(l10n, s), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                // Ответ сервера — мелко: по нему администратор поймёт причину.
                if (s.action != 'delivered' && s.action != 'relayed' && diag != null && diag.isNotEmpty)
                  Text(diag,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: AppColors.mutedText(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Письмо заново — пересылкой своего письма (текст и вложения) по адресам.
  void _compose(BuildContext context, List<String> to) {
    context.push(Uri(path: '/compose', queryParameters: {
      'forwardFromId': email.id,
      'accountId': email.accountId,
      'to': to.join(', '),
    }).toString());
  }

  Future<void> _changeAddress(BuildContext context, AppLocalizations l10n, List<String> failed) async {
    final controller = TextEditingController(text: failed.join(', '));
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('dsnChangeAddress')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(l10n.tr('dsnResend'))),
        ],
      ),
    );
    controller.dispose();
    final list = [
      for (final a in (value ?? '').split(RegExp(r'[,;\s]+')))
        if (a.contains('@')) a.trim(),
    ];
    if (list.isEmpty || !context.mounted) return;
    _compose(context, list);
  }
}

/// Чип «Отчёт о доставке» на письме-отчёте: открывает своё письмо.
class _ReportChip extends ConsumerWidget {
  final EmailModel email;
  const _ReportChip({required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original =
        ref.watch(deliveryReportOriginalProvider((accountId: email.accountId, emailId: email.id))).value;
    if (original == null || original.id == email.id) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: const Icon(AppIcons.report, size: 16),
          label: Text(l10n.tr('dsnReportChip')),
          tooltip: original.subject,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => context.push(messagePath(original.id, accountId: original.accountId)),
        ),
      ),
    );
  }
}

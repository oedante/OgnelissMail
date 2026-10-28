// lib/widgets/common/dlp_warning_dialog.dart
// Диалог предупреждения DLP перед отправкой письма.
// Показывает найденные нарушения, позволяет отправить или отменить.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/security/dlp_service.dart';

/// Показать диалог DLP перед отправкой
/// Возвращает true если пользователь подтвердил отправку
Future<bool> showDlpWarningDialog(
  BuildContext context,
  DlpCheckResult result,
) async {
  final hasBlocking = result.hasBlockingViolations;

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final l10n = AppLocalizations.of(ctx);

      return AlertDialog(
        icon: Icon(
          hasBlocking ? AppIcons.block : AppIcons.warning,
          color: hasBlocking
              ? AppColors.errorRed
              : AppColors.warningYellow,
          size: 48,
        ),
        title: Text(
          hasBlocking
              ? l10n.tr('dlpSendBlocked')
              : l10n.tr('dlpSecurityWarning'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasBlocking
                    ? l10n.tr('dlpBlockedBody')
                    : l10n.tr('dlpWarningBody'),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Space.l),

              // Список нарушений
              ...result.violations.map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: Space.s),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          v.blocking
                              ? AppIcons.dangerous
                              : AppIcons.info,
                          size: 20,
                          color: v.blocking
                              ? AppColors.errorRed
                              : AppColors.warningYellow,
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.description,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (v.matchedText?.isNotEmpty == true)
                                Text(
                                  l10n.tr('dlpFound').replaceAll('{text}', v.matchedText ?? ''),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),

              // Классификация
              const SizedBox(height: Space.s),
              Container(
                padding: const EdgeInsets.all(Space.s),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(AppIcons.security, size: 18),
                    const SizedBox(width: Space.s),
                    Text(
                      l10n.tr('dlpClassification')
                          .replaceAll('{label}', _classLabel(result.highestClassification, l10n)),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!hasBlocking)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.tr('dlpSendAnyway')),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(hasBlocking ? l10n.tr('gotIt') : l10n.tr('dlpCancel')),
          ),
        ],
      );
    },
  );

  return confirmed ?? false;
}

String _classLabel(DataClassification c, AppLocalizations l10n) {
  switch (c) {
    case DataClassification.public:
      return l10n.tr('dlpClassPublic');
    case DataClassification.internal:
      return l10n.tr('dlpClassInternal');
    case DataClassification.confidential:
      return l10n.tr('sensitivityConfidential');
    case DataClassification.secret:
      return l10n.tr('dlpClassSecret');
  }
}

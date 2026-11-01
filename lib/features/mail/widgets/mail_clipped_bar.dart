// lib/features/mail/widgets/mail_clipped_bar.dart
// Плашка под очень длинным письмом, показанным началом (1.9.x, просьба
// владельца 31.10.2026; пороги — MailClip): «Письмо очень длинное — показано
// начало» и «Показать письмо целиком». Одна на экран письма, письмо архива и
// письмо на компьютере.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/banner_button.dart';

class MailClippedBar extends StatelessWidget {
  const MailClippedBar({super.key, required this.onShowWhole, this.busy = false});

  /// «Показать письмо целиком».
  final VoidCallback onShowWhole;

  /// Письмо целиком уже собирается — кнопка неактивна.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // Подпись и кнопка — двумя строками: «Показать письмо целиком» на многих
    // языках длинное, в одной строке с подписью не помещалось бы на телефоне.
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.xs),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.article, size: 18, color: muted),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(l10n.tr('mailClipped'), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: BannerButton(
              label: l10n.tr('mailShowWhole'),
              icon: AppIcons.unfold_more,
              onPressed: busy ? null : onShowWhole,
            ),
          ),
        ],
      ),
    );
  }
}

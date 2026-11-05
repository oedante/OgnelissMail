// lib/features/mail/widgets/read_receipt_banner.dart

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';

class ReadReceiptBanner extends StatelessWidget {
  final String senderName;
  final VoidCallback onSend;
  final VoidCallback onDismiss;

  const ReadReceiptBanner({
    super.key,
    required this.senderName,
    required this.onSend,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final text = Row(
      children: [
        Icon(AppIcons.mark_email_read, size: Sizes.iconInline, color: primary),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            l10n.tr('readReceiptRequested').replaceAll('{name}', senderName),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
    final buttons = [
      TextButton(
        onPressed: onDismiss,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: Text(l10n.no),
      ),
      TextButton(
        onPressed: onSend,
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        child: Text(l10n.send),
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
        border: Border.all(color: primary.withValues(alpha: 0.2)),
      ),
      // Узко (телефон, крупный шрифт; 1.12.x — плашка раскрывается из чипа
      // строки сведений) — кнопки под текстом: в одну строку с текстом они
      // не помещались и вылезали за край.
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= MediaQuery.textScalerOf(context).scale(440)) {
          return Row(children: [Expanded(child: text), ...buttons]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          text,
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: Space.xs,
            children: buttons,
          ),
        ]);
      }),
    );
  }
}

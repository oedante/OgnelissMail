// lib/features/settings/widgets/mail_tag_chips.dart
// Кнопки полей {…} в конструкторах подписи и приветствия (18.11.2026,
// просьба владельца: «в конструкторе подписи и приветствия можно сделать
// набор таких тэгов»). Нажатие вставляет поле в место курсора; на русском
// — русское написание ({обращение}), на других языках — английское.

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/mail_tags.dart';

class MailTagChips extends StatelessWidget {
  const MailTagChips({super.key, required this.tags, required this.onInsert});

  final List<MailTag> tags;

  /// Текст поля для вставки («{обращение}»).
  final ValueChanged<String> onInsert;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = <MailTagGroup, List<MailTag>>{};
    for (final t in tags) {
      (groups[t.group] ??= []).add(t);
    }
    String title(MailTagGroup g) => l10n.tr(switch (g) {
          MailTagGroup.recipient => 'tagGroupRecipient',
          MailTagGroup.time => 'tagGroupTime',
          MailTagGroup.sender => 'tagGroupSender',
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.tr('tagsInsert'), style: theme.textTheme.labelLarge),
        for (final MapEntry(key: g, value: list) in groups.entries) ...[
          const SizedBox(height: Space.xs),
          Text(title(g), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: Space.xxs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              for (final t in list)
                Tooltip(
                  message: t.insertText(l10n.localeCode),
                  child: ActionChip(
                    label: Text(l10n.tr(t.label)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onInsert(t.insertText(l10n.localeCode)),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Вставить [text] в поле [c] вместо выделения (или в конец).
void insertAtCursor(TextEditingController c, String text) {
  final v = c.value;
  final sel = v.selection;
  final start = sel.isValid ? sel.start : v.text.length;
  final end = sel.isValid ? sel.end : v.text.length;
  c.value = TextEditingValue(
    text: v.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

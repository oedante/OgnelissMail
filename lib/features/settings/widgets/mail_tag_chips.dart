// lib/features/settings/widgets/mail_tag_chips.dart
// Кнопки полей {…} в конструкторах подписи и приветствия (18.11.2026,
// просьба владельца: «в конструкторе подписи и приветствия можно сделать
// набор таких тэгов»). Нажатие вставляет поле в место курсора; на русском
// — русское написание ({обращение}), на других языках — английское.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/mail_tags.dart';

class MailTagChips extends StatelessWidget {
  const MailTagChips({super.key, required this.tags, required this.onInsert, this.newLine = false});

  final List<MailTag> tags;

  /// Кнопка «Новая строка» (приветствие в несколько строк, 21.11.2026).
  final bool newLine;

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
        Row(children: [
          Expanded(child: Text(l10n.tr('tagsInsert'), style: theme.textTheme.labelLarge)),
          if (newLine)
            ActionChip(
              avatar: const Icon(AppIcons.keyboard_return, size: 16),
              label: Text(l10n.tr('tagNewLine')),
              visualDensity: VisualDensity.compact,
              onPressed: () => onInsert('\n'),
            ),
        ]),
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
                    // Время суток — всеми вариантами словами приветствия.
                    label: Text(t.key == 'part_of_day'
                        ? MailTags.partOfDayAll(l10n.localeCode, sep: ' / ')
                        : l10n.tr(t.label)),
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
  // Поле вплотную к тексту — через пробел (21.11.2026: «Доброе утро» и дата
  // склеивались).
  final insert = text.startsWith('{') && start > 0 && !RegExp(r'\s').hasMatch(v.text[start - 1]) ? ' $text' : text;
  c.value = TextEditingValue(
    text: v.text.replaceRange(start, end, insert),
    selection: TextSelection.collapsed(offset: start + insert.length),
  );
}

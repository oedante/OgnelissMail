// lib/widgets/common/rich_text_toolbar.dart
// Toolbar форматирования текста для compose:
// Bold, Italic, Underline, Lists, Link, Color, Size.
// Работает через HTML-теги (обёртка вокруг TextField).

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// Callback для применения форматирования
typedef FormatCallback = void Function(String tag, {String? value});

class RichTextToolbar extends StatelessWidget {
  final FormatCallback onFormat;
  final VoidCallback? onInsertLink;
  final VoidCallback? onInsertImage;

  const RichTextToolbar({
    super.key,
    required this.onFormat,
    this.onInsertLink,
    this.onInsertImage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        children: [
          _toolBtn(AppIcons.format_bold, l10n.tr('bold'), () {
            HapticFeedback.selectionClick();
            onFormat('b');
          }),
          _toolBtn(AppIcons.format_italic, l10n.tr('italic'), () {
            HapticFeedback.selectionClick();
            onFormat('i');
          }),
          _toolBtn(AppIcons.format_underlined, l10n.tr('underline'), () {
            HapticFeedback.selectionClick();
            onFormat('u');
          }),
          _divider(),
          _toolBtn(AppIcons.format_list_bulleted, l10n.tr('bulletList'), () {
            HapticFeedback.selectionClick();
            onFormat('ul');
          }),
          _toolBtn(AppIcons.format_list_numbered, l10n.tr('numberedList'), () {
            HapticFeedback.selectionClick();
            onFormat('ol');
          }),
          _divider(),
          _toolBtn(AppIcons.link, l10n.tr('insertLink'), () {
            HapticFeedback.selectionClick();
            onInsertLink?.call();
          }),
          _divider(),
          // Размер шрифта
          PopupMenuButton<int>(
            icon: const Icon(AppIcons.format_size, size: 20),
            tooltip: l10n.tr('fontSize'),
            itemBuilder: (_) => [
              PopupMenuItem(value: 1, child: Text(l10n.tr('fontSmall'), style: const TextStyle(fontSize: 12))),
              PopupMenuItem(value: 3, child: Text(l10n.tr('fontNormal'), style: const TextStyle(fontSize: 14))),
              PopupMenuItem(value: 5, child: Text(l10n.tr('fontLarge'), style: const TextStyle(fontSize: 18))),
              PopupMenuItem(value: 7, child: Text(l10n.tr('fontHuge'), style: const TextStyle(fontSize: 24))),
            ],
            onSelected: (size) {
              HapticFeedback.selectionClick();
              onFormat('font', value: 'size="$size"');
            },
          ),
          // Цвет текста
          PopupMenuButton<Color>(
            icon: const Icon(AppIcons.format_color_text, size: 20),
            tooltip: l10n.tr('textColor'),
            itemBuilder: (_) => [
              // Тёмные насыщенные тона, читаемые на белом у получателя
              // (≥ 4.5:1): прежние Material 500 — оранжевый 2.2:1, зелёный
              // 2.8:1 — плохо читались и выглядели кричаще (аудит 10.10.2026).
              _colorItem(Colors.black, l10n.tr('colorBlack')),
              _colorItem(const Color(0xFFC62828), l10n.tr('colorRed')),
              _colorItem(const Color(0xFF1565C0), l10n.tr('colorBlue')),
              _colorItem(const Color(0xFF2E7D32), l10n.tr('colorGreen')),
              _colorItem(const Color(0xFFB45309), l10n.tr('colorOrange')),
              _colorItem(const Color(0xFF6A1B9A), l10n.tr('colorPurple')),
            ],
            onSelected: (color) {
              HapticFeedback.selectionClick();
              final hex = '#${color.toARGB32().toRadixString(16).substring(2)}';
              onFormat('font', value: 'color="$hex"');
            },
          ),
          _divider(),
          _toolBtn(AppIcons.format_clear, l10n.tr('clearFormatting'), () {
            HapticFeedback.selectionClick();
            onFormat('clear');
          }),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: const EdgeInsets.all(6),
    );
  }

  Widget _divider() {
    return const SizedBox(
      height: Sizes.icon,
      child: VerticalDivider(width: Space.s + 1, thickness: 1),
    );
  }

  PopupMenuItem<Color> _colorItem(Color color, String label) {
    return PopupMenuItem(
      value: color,
      child: Row(
        children: [
          Container(width: 16, height: 16, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: Space.s),
          Text(label),
        ],
      ),
    );
  }
}

/// Хелпер для применения HTML-тегов к тексту
class RichTextHelper {
  /// Обернуть выделенный текст тегом
  static String applyTag(String fullText, int selectionStart, int selectionEnd, String tag, {String? value}) {
    if (tag == 'clear') {
      // Удалить все HTML-теги из выделения
      final selected = fullText.substring(selectionStart, selectionEnd);
      final cleaned = selected.replaceAll(RegExp(r'<[^>]*>'), '');
      return fullText.replaceRange(selectionStart, selectionEnd, cleaned);
    }

    if (tag == 'ul' || tag == 'ol') {
      // Списки
      final selected = fullText.substring(selectionStart, selectionEnd);
      final lines = selected.split('\n');
      final listItems = lines.map((l) => '<li>${l.trim()}</li>').join('\n');
      final replacement = '<$tag>\n$listItems\n</$tag>';
      return fullText.replaceRange(selectionStart, selectionEnd, replacement);
    }

    if (tag == 'font') {
      // С атрибутами
      final selected = fullText.substring(selectionStart, selectionEnd);
      final replacement = '<font $value>$selected</font>';
      return fullText.replaceRange(selectionStart, selectionEnd, replacement);
    }

    // Простое обёртывание
    final selected = fullText.substring(selectionStart, selectionEnd);
    final replacement = '<$tag>$selected</$tag>';
    return fullText.replaceRange(selectionStart, selectionEnd, replacement);
  }
}

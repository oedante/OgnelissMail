// lib/widgets/ui/file_type_icon.dart
// Значок типа файла — один для письма, списка вложений и «Всех вложений».
// Раньше три копии с цветами Material (Colors.red/green/blue/orange/grey):
// мимо фирменной палитры и без учёта тёмной темы (серый на тёмном фоне).

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

class FileTypeStyle {
  final IconData icon;
  final Color color;
  const FileTypeStyle(this.icon, this.color);

  /// Категория по MIME-типу и имени (как EmailAttachment.category, плюс текст).
  static String categoryOf(String mime, [String name = '']) {
    final m = mime.toLowerCase();
    final n = name.toLowerCase();
    // Сначала — по расширению: сервер часто отдаёт тип
    // application/octet-stream, и файл попадал в «Прочее».
    final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1) : '';
    const byExt = {
      'pdf': 'pdf',
      'doc': 'document', 'docx': 'document', 'odt': 'document', 'rtf': 'document', 'dotx': 'document',
      'xls': 'spreadsheet', 'xlsx': 'spreadsheet', 'xlsm': 'spreadsheet', 'ods': 'spreadsheet', 'csv': 'spreadsheet',
      'ppt': 'presentation', 'pptx': 'presentation', 'odp': 'presentation',
      'jpg': 'image', 'jpeg': 'image', 'png': 'image', 'gif': 'image', 'webp': 'image', 'heic': 'image', 'bmp': 'image', 'tif': 'image', 'tiff': 'image',
      'zip': 'archive', 'rar': 'archive', '7z': 'archive', 'gz': 'archive', 'tar': 'archive',
      'ics': 'calendar',
      'txt': 'text', 'log': 'text', 'md': 'text',
    };
    final known = byExt[ext];
    if (known != null) return known;
    if (m.contains('pdf') || n.endsWith('.pdf')) return 'pdf';
    if (m.startsWith('image/') || m.contains('image')) return 'image';
    if (m.contains('word') || m.contains('document') || n.endsWith('.doc') || n.endsWith('.docx')) return 'document';
    if (m.contains('excel') || m.contains('sheet') || n.endsWith('.xls') || n.endsWith('.xlsx')) return 'spreadsheet';
    if (m.contains('presentation') || m.contains('powerpoint') || n.endsWith('.ppt') || n.endsWith('.pptx')) return 'presentation';
    if (m.contains('zip') || m.contains('rar') || m.contains('7z')) return 'archive';
    if (m.contains('calendar') || n.endsWith('.ics')) return 'calendar';
    if (m.startsWith('text/')) return 'text';
    return 'other';
  }

  static FileTypeStyle of(BuildContext context, String category) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Цвета значков — варианты «для текста» (≥ 4.5:1 к фону): прежние
    // янтарный, оранжевый и тёмно-синий были бледными на светлой теме или
    // пропадали на тёмной (аудит цветов 10.10.2026).
    return switch (category) {
      'pdf' => FileTypeStyle(AppIcons.picture_as_pdf, AppColors.errorText(context)),
      'image' => FileTypeStyle(AppIcons.image, dark ? const Color(0xFFB59AD0) : AppColors.tagMaintenance),
      'document' => FileTypeStyle(AppIcons.description, scheme.primary),
      'spreadsheet' => FileTypeStyle(AppIcons.table_chart, AppColors.successText(context)),
      'presentation' => FileTypeStyle(AppIcons.slideshow, AppColors.accentOrangeText(context)),
      'archive' => FileTypeStyle(AppIcons.folder_zip, AppColors.warningText(context)),
      'calendar' => FileTypeStyle(AppIcons.event, AppColors.infoText(context)),
      'text' => FileTypeStyle(AppIcons.text_snippet, muted),
      _ => FileTypeStyle(AppIcons.insert_drive_file, muted),
    };
  }
}

/// Плашка 40×40 со значком типа файла.
class FileTypeIcon extends StatelessWidget {
  final String category;
  const FileTypeIcon({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final s = FileTypeStyle.of(context, category);
    return Container(
      width: Sizes.avatar,
      height: Sizes.avatar,
      decoration: BoxDecoration(color: s.color.withValues(alpha: 0.12), borderRadius: Radii.chipAll),
      child: Icon(s.icon, color: s.color, size: Sizes.iconRow + 2),
    );
  }
}

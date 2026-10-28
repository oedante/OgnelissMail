// lib/features/compose/widgets/image_size_sheet.dart
// Шторка «Размер фото» при отправке письма с фото (1.7.2+109): «Как есть»
// с настоящим размером и 75 %, 50 %, 25 % — с примерным («≈ 2,1 МБ»).
// Нажатие — выбор и отправка; смахнули шторку — письмо не уходит, можно
// продолжить правку. Как уменьшается — `ImageShrink`.

import 'package:flutter/material.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/utils/format_bytes.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/image_shrink.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/help_hint.dart' show HelpButton;

/// Подпись варианта: «Как есть», «75%»…; [percent] 100 — как есть, 0 — «Спрашивать».
String photoSizeLabel(AppLocalizations l10n, int percent) => switch (percent) {
      0 => l10n.tr('photoSizeAsk'),
      100 => l10n.tr('imageSizeAsIs'),
      _ => l10n.tr('imageSizePercent').replaceAll('{p}', '$percent'),
    };

/// Шторка выбора. [images] — фото письма (имя и размер в байтах), [other] —
/// остальное письмо (другие файлы, текст, цитата), [limit] — лимит размера
/// письма у ящика. Размеры в вариантах — всего письма (как в Почте iPhone):
/// так видно, уложится ли оно в лимит; не укладывается — «больше лимита»
/// красным (выбрать всё равно можно: лимит по умолчанию — догадка, у
/// сервера он бывает больше). Возвращает долю стороны (1 — как есть) или
/// null — человек передумал отправлять.
Future<double?> showImageSizeSheet(
  BuildContext context,
  List<({String name, int size})> images, {
  int other = 0,
  int? limit,
}) {
  final l10n = AppLocalizations.of(context);
  final photos = images.fold<int>(0, (s, f) => s + f.size);
  int about(double scale) => images.fold<int>(0, (s, f) => s + ImageShrink.estimate(f.name, f.size, scale));
  return showAppSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final muted = TextStyle(color: AppColors.mutedText(ctx));
      Widget option({required String title, required int bytes, required bool approx, required double scale, required IconData icon}) {
        final total = other + bytes;
        final over = limit != null && total > limit;
        final size = '${approx ? '≈ ' : ''}${formatBytes(total, l10n)}';
        return ListTile(
          leading: Icon(icon),
          title: Text(title),
          trailing: Text(
            over ? '$size · ${l10n.tr('imageSizeOverLimit')}' : size,
            style: theme.textTheme.bodyMedium?.merge(over ? TextStyle(color: AppColors.errorTextOn(theme)) : muted),
          ),
          onTap: () => Navigator.pop(ctx, scale),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.tr('imageSizeTitle'), style: theme.textTheme.titleMedium),
                subtitle: Text(
                  l10n
                      .tr('imageSizeSummary')
                      .replaceAll('{n}', '${images.length}')
                      .replaceAll('{size}', formatBytes(other + photos, l10n))
                      .replaceAll('{limit}', limit == null ? '' : formatBytes(limit, l10n)),
                  style: muted,
                ),
                trailing: HelpButton(text: l10n.tr('imageSizeHelp'), title: l10n.tr('imageSizeTitle')),
              ),
              option(
                title: l10n.tr('imageSizeAsIs'),
                bytes: photos,
                approx: false,
                scale: 1,
                icon: AppIcons.photo_size_select_actual,
              ),
              for (final s in ImageShrink.scales)
                option(
                  title: l10n.tr('imageSizePercent').replaceAll('{p}', '${(s * 100).round()}'),
                  bytes: about(s),
                  approx: true,
                  scale: s,
                  icon: s >= 0.5 ? AppIcons.photo_size_select_large : AppIcons.photo_size_select_small,
                ),
            ],
          ),
        ),
      );
    },
  );
}

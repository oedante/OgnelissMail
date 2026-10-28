// lib/features/archive/widgets/archive_search_strip.dart
// Поиск почты ищет и в архиве Ogneliss (1.7.3, просьба владельца
// 25.10.2026): над результатами — строка «В архиве Ogneliss: N писем ›»,
// нажатие открывает найденное в архиве. Архива нет, он закрыт или в нём
// ничего не нашлось — строки нет.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../archive_providers.dart';

class ArchiveSearchStrip extends ConsumerWidget {
  final String query;
  const ArchiveSearchStrip({super.key, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim();
    if (q.length < 2) return const SizedBox.shrink();
    final n = ref.watch(archiveSearchCountProvider(q)).value ?? 0;
    if (n <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: Space.l, top: Space.s, right: Space.l),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: Radii.chipAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Uri(path: '/archive/search', queryParameters: {'q': q}).toString()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: Row(children: [
              Icon(AppIcons.inventory_2, size: Sizes.iconInline, color: scheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  l10n.tr('archiveFoundStrip').replaceAll('{n}', l10n.plural('archiveNMails', n)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
                ),
              ),
              Icon(AppIcons.chevron_right, size: Sizes.iconInline, color: scheme.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

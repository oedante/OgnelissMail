// lib/widgets/common/section_search_button.dart
// Поиск раздела в шапке (просьба владельца 12.11.2026: «на компьютере
// везде строка, на телефоне везде значок»). Компьютер и планшет (нижней
// панели нет) — строка «Поиск» в шапке, как в почте; телефон — значок.
// Нажатие в обоих случаях открывает поиск раздела.

import 'package:flutter/material.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'adaptive_layout.dart' show Breakpoints;
import '../../l10n/app_localizations.dart';
import '../navigation/app_bottom_bar.dart';

class SectionSearchButton extends StatelessWidget {
  final VoidCallback onTap;
  const SectionSearchButton({super.key, required this.onTap});

  /// Показывать ли строку (а не значок) в этом окне.
  static bool wide(BuildContext context) =>
      !AppBottomBar.inUse(context) && MediaQuery.sizeOf(context).width >= Breakpoints.phone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!wide(context)) {
      return IconButton(icon: const Icon(AppIcons.search), tooltip: l10n.search, onPressed: onTap);
    }
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs),
      child: Material(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('section_search_pill'),
          onTap: onTap,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width >= 1200 ? 240 : 160,
            height: 36,
            child: Row(children: [
              const SizedBox(width: Space.m),
              Icon(AppIcons.search, size: 18, color: muted),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(l10n.search,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

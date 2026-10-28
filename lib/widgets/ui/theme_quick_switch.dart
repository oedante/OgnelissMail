// lib/widgets/ui/theme_quick_switch.dart
// Быстрый выбор темы в меню «Ещё»: «Авто» · «Светлая» · «Тёмная» · «Чтение»
// (просьба 10.10.2026 — не ходить за этим в Настройки → Общие). Тема
// меняется сразу, шторка остаётся открытой — видно, как выглядит.
// «Тёмная» — переключатель тёмной и AMOLED (1.5.11): первое нажатие —
// тёмная тема, а подпись становится «AMOLED» (что будет при следующем
// нажатии); второе — AMOLED, подпись — снова «Тёмная».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';

class ThemeQuickSwitch extends ConsumerWidget {
  const ThemeQuickSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(settingsProvider.select((s) => s.themeChoice));
    final selected = current == AppThemeChoice.amoled ? AppThemeChoice.dark : current;
    final options = [
      (AppThemeChoice.system, AppIcons.brightness_auto, l10n.tr('themeAutoShort')),
      (AppThemeChoice.light, AppIcons.light_mode, l10n.tr('lightTheme')),
      // Подпись — то, что включит следующее нажатие.
      (AppThemeChoice.dark, AppIcons.dark_mode,
          current == AppThemeChoice.dark ? 'AMOLED' : l10n.tr('darkTheme')),
      (AppThemeChoice.reading, AppIcons.menu_book, l10n.tr('readingThemeShort')),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xs),
      child: Row(children: [
        for (final o in options)
          Expanded(
            child: _Choice(
              icon: o.$2,
              label: o.$3,
              selected: o.$1 == selected,
              onTap: () {
                final n = ref.read(settingsProvider.notifier);
                if (o.$1 == AppThemeChoice.dark) {
                  // Тёмная ↔ AMOLED по очереди.
                  n.setThemeChoice(current == AppThemeChoice.dark ? AppThemeChoice.amoled : AppThemeChoice.dark);
                  return;
                }
                if (o.$1 == selected) return;
                n.setThemeChoice(o.$1);
              },
            ),
          ),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs / 2),
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.chipAll,
            side: BorderSide(color: selected ? Colors.transparent : scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Sizes.tapTarget + Space.m),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s, horizontal: Space.xs),
                child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: Sizes.iconRow, color: fg, fill: selected ? 1.0 : 0.0),
                  const SizedBox(height: Space.xs),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: fg)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

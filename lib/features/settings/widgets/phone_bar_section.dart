// lib/features/settings/widgets/phone_bar_section.dart
// «Общие → Нижняя панель» (2.2.0, просьба пользователя 10.11.2026: «контакты
// редко нужны — в избранное, а „Мой день“ — в нижний бар»). Макет панели:
// четыре места по краям от «Создать»; нажал место — выбрал раздел. Раздел,
// который уже на панели, меняется местами; убранный — появляется в
// «Избранном» меню. «Меню» убрать нельзя — только переставить.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/navigation/phone_bar.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/drawer_prefs.dart' show BarItem, PhoneBarNotifier, phoneBarProvider;

class PhoneBarSection extends ConsumerWidget {
  const PhoneBarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = barAvailability(ref);
    final bar = ref.watch(phoneBarProvider);
    final shown = PhoneBarNotifier.visible(bar, available);
    final notifier = ref.read(phoneBarProvider.notifier);

    Widget slot(int i) {
      final item = shown[i];
      final label = barLabel(item, l10n);
      return Expanded(
        child: Semantics(
          button: true,
          label: '${l10n.tr('barSlot')} ${i + 1}: $label',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('bar_slot_$i'),
            borderRadius: BorderRadius.circular(Radii.chip),
            onTap: () => _pick(context, ref, i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 48,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(barIcon(item), size: Sizes.iconInline + 4, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(height: Space.xs),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall),
              ]),
            ),
          ),
        ),
      );
    }

    // «Создать» — всегда в центре; в макете — только для наглядности.
    final center = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Icon(AppIcons.add, color: scheme.onPrimaryContainer),
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('barSettingsTitle'), help: l10n.tr('barSettingsHelp')),
      SettingsGroup(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            slot(0),
            slot(1),
            center,
            slot(2),
            slot(3),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.m),
          child: Text(l10n.tr('barSettingsHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        if (notifier.customized)
          SettingsItem(
            key: const ValueKey('bar_reset'),
            icon: AppIcons.restart_alt,
            title: l10n.tr('barReset'),
            onTap: notifier.reset,
          ),
      ]),
    ]);
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, int slot) async {
    final l10n = AppLocalizations.of(context);
    final available = barAvailability(ref);
    final bar = PhoneBarNotifier.visible(ref.read(phoneBarProvider), available);
    final current = bar[slot];
    final isMenu = current == BarItem.menu;
    final picked = await showActionSheet<BarItem>(
      context,
      title: l10n.tr('barSlotPick'),
      subtitle: isMenu ? l10n.tr('barMenuStays') : null,
      items: [
        for (final item in BarItem.values)
          if (available(item) && (!isMenu || bar.contains(item)))
            ActionSheetItem(
              icon: barIcon(item),
              label: barLabel(item, l10n),
              subtitle: item == current
                  ? null
                  : bar.contains(item)
                      ? l10n.tr('barSwap')
                      : null,
              checked: item == current,
              value: item,
            ),
      ],
    );
    if (picked == null || picked == current) return;
    // Место — по сохранённому порядку: подставленный вместо выключенного
    // раздел меняем как есть.
    final notifier = ref.read(phoneBarProvider.notifier);
    final saved = ref.read(phoneBarProvider);
    if (saved[slot] != current) {
      // На этом месте показан заменитель выключенного раздела: сначала
      // фиксируем то, что видно, потом ставим выбранное.
      await notifier.place(slot, current);
    }
    await notifier.place(slot, picked);
  }
}

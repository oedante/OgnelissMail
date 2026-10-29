// lib/features/settings/screens/accessibility_screen.dart
// Полный экран специальных возможностей (Экран 10 из ТЗ).
// Высокая контрастность, крупный текст, дальтонизм, дислексия,
// экранный диктор, голосовое управление, уменьшение движения.

import 'dart:async';

import '../../../widgets/ui/action_sheet.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

class AccessibilityScreen extends ConsumerWidget {
  const AccessibilityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('accessibility')),
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // ── ВИЗУАЛЬНЫЕ ──
          SettingsSectionTitle(l10n.tr('a11yVisual')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.contrast,
              title: l10n.tr('highContrast'),
              subtitle: l10n.tr('highContrastDesc'),
              value: settings.highContrast,
              onChanged: (v) => notifier.setHighContrast(v),
            ),
            // Крупный текст
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              leading: Icon(AppIcons.text_fields, color: theme.colorScheme.primary),
              title: Text(l10n.tr('largeText')),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${l10n.tr('currentScale')}: ${(settings.fontScale * 100).round()}%'),
                  Slider(
                    value: settings.fontScale.clamp(0.8, 1.6),
                    min: 0.8,
                    // Как в «Общих»: выше ×1,6 вёрстка не держится (общий предел
                    // приложения, TextScaleLimits.app) — ползунок дальше не ведёт.
                    max: 1.6,
                    divisions: 8,
                    label: '${(settings.fontScale * 100).round()}%',
                    onChanged: (v) => notifier.setFontScale(v),
                  ),
                ],
              ),
            ),
            SettingsItem(
              icon: AppIcons.palette,
              title: l10n.tr('colorBlind'),
              subtitle: _colorBlindLabel(settings.colorBlindMode, l10n),
              onTap: () => _showColorBlindPicker(context, ref, settings),
            ),
            SettingsSwitchItem(
              icon: AppIcons.font_download,
              title: l10n.tr('dyslexiaFont'),
              subtitle: l10n.tr('dyslexiaFontDesc'),
              value: settings.dyslexiaFont,
              onChanged: (v) => notifier.setDyslexiaFont(v),
            ),
          ]),

          // ── ДВИЖЕНИЕ ──
          SettingsSectionTitle(l10n.tr('a11yMotion')),
          SettingsGroup(children: [
            // «Анимации интерфейса» убраны (решение 09.10.2026): движение
            // отдельных элементов дёргалось на тестовых телефонах. Остались
            // только выезд, сдвиг и раскрытие панелей.
            SettingsSwitchItem(
              icon: AppIcons.animation,
              title: l10n.tr('reduceMotion'),
              subtitle: l10n.tr('reduceMotionDesc'),
              value: settings.reduceMotion,
              onChanged: (v) => notifier.setReduceMotion(v),
            ),
          ]),

          // ── УПРАВЛЕНИЕ ──
          SettingsSectionTitle(l10n.tr('a11yControl')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.gesture,
              title: l10n.tr('gestureNav'),
              subtitle: l10n.tr('gestureNavDesc'),
              onTap: () => _showGestureHelp(context),
            ),
          ]),

          // «Экранный диктор» (строка без действия) и плашка «соответствует
          // WCAG 2.1 AA» убраны (10.10.2026): обещали больше, чем проверено.
          // «Размер кнопок» и «Моно-звук» убраны раньше: ничего не меняли.
        ],
      ),
    );
  }

  String _colorBlindLabel(int mode, AppLocalizations l10n) {
    switch (mode) {
      case 0: return l10n.tr('cbDisabled');
      case 1: return l10n.tr('cbProtanopiaFull');
      case 2: return l10n.tr('cbDeuteranopiaFull');
      case 3: return l10n.tr('cbTritanopiaFull');
      default: return l10n.tr('cbDisabled');
    }
  }

  void _showColorBlindPicker(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    // Карточкой (1.8.8), как меню «⋮»; текущий — с галочкой.
    unawaited(showChoiceSheet<int>(
      context,
      title: l10n.tr('colorBlindMode'),
      selected: settings.colorBlindMode,
      entries: [
        AppMenuEntry(value: 0, label: l10n.tr('cbDisabled')),
        AppMenuEntry(value: 1, label: l10n.tr('cbProtanopia'), subtitle: l10n.tr('cbProtanopiaDesc')),
        AppMenuEntry(value: 2, label: l10n.tr('cbDeuteranopia'), subtitle: l10n.tr('cbDeuteranopiaDesc')),
        AppMenuEntry(value: 3, label: l10n.tr('cbTritanopia'), subtitle: l10n.tr('cbTritanopiaDesc')),
      ],
    ).then((v) {
      if (v != null) ref.read(settingsProvider.notifier).setColorBlindMode(v);
    }));
  }


  void _showGestureHelp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showHelpSheet(context, title: l10n.tr('gesturesTitle'), text: l10n.tr('gesturesBody'));
  }
}

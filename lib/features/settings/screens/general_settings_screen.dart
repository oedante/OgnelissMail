// lib/features/settings/screens/general_settings_screen.dart
// Общие настройки: тема, язык, масштаб шрифта. Реальное применение через settingsProvider.

import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import 'dart:io' show Platform;
import '../../../core/theme/app_icons.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../providers/widget_prefs.dart';
import '../../mail/providers/drawer_prefs.dart' show menuOnRightProvider;
import '../../../widgets/navigation/app_bottom_bar.dart' show AppBottomBar;
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/languages.g.dart' show kAppLanguages;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/ui_zoom.dart';

class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('general')), actions: const [FaqButton(section: 'widgets')])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // ── Тема ──
          SettingsSectionTitle(l10n.tr('theme')),
          SettingsGroup(children: [
            for (final t in [
              (AppThemeChoice.system, l10n.tr('systemTheme'), null),
              (AppThemeChoice.light, l10n.tr('lightTheme'), null),
              (AppThemeChoice.dark, l10n.tr('darkTheme'), null),
              (AppThemeChoice.amoled, l10n.tr('amoledTheme'), l10n.tr('amoledThemeHint')),
              (AppThemeChoice.reading, l10n.tr('readingTheme'), l10n.tr('readingThemeHint')),
            ])
              AppRadioTile<AppThemeChoice>(
                title: Text(t.$2),
                subtitle: t.$3 == null ? null : Text(t.$3!),
                value: t.$1,
                groupValue: settings.themeChoice,
                onChanged: (v) => notifier.setThemeChoice(v!),
              ),
            // Цвета от обоев — Android 12+ (на iOS и старых Android системной
            // палитры нет, переключатель не показывается).
            if (!kIsWeb && Platform.isAndroid)
              SettingsSwitchItem(
                icon: AppIcons.palette,
                title: l10n.tr('dynamicColor'),
                subtitle: l10n.tr(settings.highContrast
                    ? 'dynamicColorHc'
                    : (settings.reading ? 'dynamicColorReading' : 'dynamicColorDesc')),
                value: settings.dynamicColor,
                onChanged: (settings.highContrast || settings.reading) ? null : notifier.setDynamicColor,
              ),
          ]),

          // ── Экран ──
          SettingsSectionTitle(l10n.tr('sectionScreen')),
          SettingsGroup(children: [
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))
              SettingsSwitchItem(
                icon: AppIcons.screen_rotation,
                title: l10n.tr('allowRotation'),
                subtitle: l10n.tr('allowRotationShort'),
                hint: l10n.tr('allowRotationDesc'),
                value: settings.allowRotation,
                onChanged: notifier.setAllowRotation,
              ),
            // В теме «Чтение» тёплый фон и так во всём приложении.
            if (!settings.reading)
              SettingsSwitchItem(
                icon: AppIcons.wb_sunny,
                title: l10n.tr('warmPage'),
                subtitle: l10n.tr('warmPageDesc'),
                value: settings.warmPage,
                onChanged: notifier.setWarmPage,
              ),
          ]),

          // ── Виджеты на рабочем столе: тема (Android и iPhone, 1.7.0) и
          // фон (Android, 1.6.49) ──
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
            SettingsSectionTitle(l10n.tr('widgetThemeTitle'), help: l10n.tr('widgetThemeHelp')),
            SettingsGroup(children: [
              for (final o in [
                (0, l10n.tr('widgetThemeSystem')),
                (1, l10n.tr('widgetThemeLight')),
                (2, l10n.tr('widgetThemeDark')),
              ])
                AppRadioTile<int>(
                  title: Text(o.$2),
                  value: o.$1,
                  groupValue: ref.watch(widgetThemeProvider),
                  onChanged: (v) => ref.read(widgetThemeProvider.notifier).set(v ?? 0),
                ),
            ]),
          ],
          if (!kIsWeb && Platform.isAndroid) ...[
            SettingsSectionTitle(l10n.tr('widgetBgTitle'), help: l10n.tr('widgetBgHelp')),
            SettingsGroup(children: [
              for (final o in [
                (0, l10n.tr('widgetBgNormal'), null),
                (1, l10n.tr('widgetBgSoft'), l10n.tr('widgetBgSoftHint')),
                (2, l10n.tr('widgetBgNone'), l10n.tr('widgetBgNoneHint')),
              ])
                AppRadioTile<int>(
                  title: Text(o.$2),
                  subtitle: o.$3 == null ? null : Text(o.$3!),
                  value: o.$1,
                  groupValue: ref.watch(widgetBackgroundProvider),
                  onChanged: (v) => ref.read(widgetBackgroundProvider.notifier).set(v ?? 0),
                ),
            ]),
          ],

          // ── Меню ящиков и папок (телефон, 1.6.40) ──
          // Слева (по умолчанию) или справа: портрет «Меню» внизу и свайп от
          // края — с выбранной стороны.
          if (AppBottomBar.inUse(context)) ...[
            SettingsSectionTitle(l10n.tr('menuSideTitle')),
            SettingsGroup(children: [
              for (final o in [
                (false, l10n.tr('menuSideLeft'), l10n.tr('menuSideLeftHint')),
                (true, l10n.tr('menuSideRight'), l10n.tr('menuSideRightHint')),
              ])
                AppRadioTile<bool>(
                  title: Text(o.$2),
                  subtitle: Text(o.$3),
                  value: o.$1,
                  groupValue: ref.watch(menuOnRightProvider),
                  onChanged: (v) => ref.read(menuOnRightProvider.notifier).set(v ?? false),
                ),
            ]),
          ],

          // ── Язык ──
          SettingsSectionTitle(l10n.tr('language')),
          // Все языки приложения (kAppLanguages, 27) — строкой с выбором в
          // шторке (замечание владельца 27.10.2026: «переключатель языков
          // по-прежнему всего на четыре языка» — список был вписан в код).
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.language,
              title: AppLocalizations.languageOf(settings.locale.languageCode)?.name ??
                  settings.locale.languageCode,
              subtitle: AppLocalizations.languageOf(settings.locale.languageCode)?.english,
              onTap: () => _pickLanguage(context, settings.locale.languageCode, notifier.setLocale),
            ),
          ]),

          // ── Шрифт интерфейса (1.8.8) ──
          // Каждый вариант подписан своим шрифтом — видно, как он выглядит.
          SettingsSectionTitle(l10n.tr('uiFontTitle')),
          SettingsGroup(children: [
            for (final o in [
              ('roboto', 'Roboto', l10n.tr('uiFontRobotoHint'), AppTheme.robotoFamily),
              ('medeo', 'Medeo Sans', l10n.tr('uiFontMedeoHint'), AppTheme.medeoFamily),
            ])
              AppRadioTile<String>(
                title: Text(o.$2, style: TextStyle(fontFamily: o.$4)),
                subtitle: Text(o.$3, style: TextStyle(fontFamily: o.$4)),
                value: o.$1,
                groupValue: settings.uiFont,
                onChanged: (v) => notifier.setUiFont(v ?? 'roboto'),
              ),
            if (settings.dyslexiaFont)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
                child: Text(l10n.tr('uiFontDyslexiaNote'), style: Theme.of(context).textTheme.bodySmall),
              ),
          ]),

          // ── Масштаб шрифта ──
          SettingsSectionTitle('${l10n.tr('fontSize')} · ${(settings.fontScale * 100).round()}%'),
          SettingsGroup(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
              child: Slider(
                min: 0.8,
                max: 1.6,
                divisions: 8,
                value: settings.fontScale.clamp(0.8, 1.6),
                label: '${(settings.fontScale * 100).round()}%',
                onChanged: (v) => notifier.setFontScale(v),
              ),
            ),
          ]),

          // ── Масштаб интерфейса (1.6.12) ──
          SettingsSectionTitle(l10n.tr('uiScaleTitle')),
          SettingsGroup(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xs),
              child: Wrap(
                spacing: Space.s,
                runSpacing: Space.xs,
                children: [
                  for (final v in [0.0, ...UiZoom.manual])
                    ChoiceChip(
                      label: Text(v == 0 ? l10n.tr('uiScaleAuto') : '${(v * 100).round()}%'),
                      selected: settings.uiScale == v ||
                          (v != 0 && settings.uiScale > 0 && (settings.uiScale - v).abs() < 0.001),
                      onSelected: (_) => notifier.setUiScale(v),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
              child: Text(
                l10n.tr('uiScaleHint').replaceAll('{n}', '${(UiZoom.current * 100).round()}'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Выбор языка: все языки приложения, у каждого — название на нём самом и
  /// по-английски.
  Future<void> _pickLanguage(BuildContext context, String current, void Function(Locale) set) async {
    // Карточкой (1.8.8), как меню «⋮»; текущий — с галочкой.
    final picked = await showChoiceSheet<String>(
      context,
      title: AppLocalizations.of(context).tr('language'),
      selected: current,
      entries: [
        for (final lang in kAppLanguages)
          AppMenuEntry(value: lang.code, label: lang.name, subtitle: lang.name == lang.english ? null : lang.english),
      ],
    );
    if (picked != null && picked != current) set(Locale(picked));
  }
}

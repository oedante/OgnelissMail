// lib/features/settings/screens/general_settings_screen.dart
// Общие настройки: язык, поворот экрана, что показывает виджет «Почта».
// Тема, шрифт, масштаб, панели телефона и вид виджетов — на экране
// «Оформление» (с 12.11.2026), здесь — строка-ссылка.

import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import 'dart:io' show Platform;
import 'package:go_router/go_router.dart';
import 'appearance_screen.dart' show presetLabel;
import '../../../core/theme/app_icons.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../providers/widget_prefs.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../l10n/languages.g.dart' show kAppLanguages;
import '../../../widgets/common/text_scale_cap.dart';

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

          // ── Экран ──
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
          SettingsSectionTitle(l10n.tr('sectionScreen')),
          SettingsGroup(children: [
              SettingsSwitchItem(
                icon: AppIcons.screen_rotation,
                title: l10n.tr('allowRotation'),
                subtitle: l10n.tr('allowRotationShort'),
                hint: l10n.tr('allowRotationDesc'),
                value: settings.allowRotation,
                onChanged: notifier.setAllowRotation,
              ),
          ]),
          ],

          // Что показывает виджет «Почта» (08.11.2026).
          if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
            SettingsSectionTitle(l10n.tr('widgetMailTitle'), help: l10n.tr('widgetMailHelp')),
            SettingsGroup(children: [
              for (final o in [
                ('all', l10n.tr('widgetMailAll')),
                ('vip', l10n.tr('widgetMailVip')),
                ('flagged', l10n.tr('widgetMailFlagged')),
                ('control', l10n.tr('widgetMailControl')),
                for (final a in ref.watch(accountsProvider).where((a) => a.isActive))
                  ('acc:${a.id}', a.email),
              ])
                AppRadioTile<String>(
                  title: Text(o.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                  value: o.$1,
                  groupValue: ref.watch(widgetMailFilterProvider),
                  onChanged: (v) => ref.read(widgetMailFilterProvider.notifier).set(v ?? 'all'),
                ),
            ]),
          ],

          // ── Оформление ──
          // Тема, цвета, шрифт, размер шрифта, масштаб, панели телефона и
          // вид виджетов — на экране «Оформление» (1.9.x; с 12.11.2026 туда
          // же перенесено и остальное «видимое» из «Общих»).
          SettingsSectionTitle(l10n.tr('theme')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.palette,
              title: l10n.tr('appearanceTitle'),
              subtitle: '${_themeLabel(l10n, settings.themeChoice)} · ${presetLabel(l10n, settings.themePreset)}',
              onTap: () => context.push('/settings/appearance'),
            ),
          ]),

        ],
      ),
    );
  }

  static String _themeLabel(AppLocalizations l10n, AppThemeChoice c) => l10n.tr(switch (c) {
        AppThemeChoice.system => 'systemTheme',
        AppThemeChoice.light => 'lightTheme',
        AppThemeChoice.dark => 'darkTheme',
        AppThemeChoice.amoled => 'amoledTheme',
        AppThemeChoice.reading => 'readingTheme',
      });

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

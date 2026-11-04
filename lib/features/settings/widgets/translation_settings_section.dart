// lib/features/settings/widgets/translation_settings_section.dart
// Настройки → Почта → «Перевод» (1.9.x, просьба владельца 31.10.2026):
// предлагать ли перевод писем, с каких языков не переводить, скачивание
// языков только по Wi-Fi, скачанные языки (Android; на iPhone ими управляет
// iOS). На компьютере и в вебе перевода нет — раздела тоже.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/translation/translation_languages.dart';
import '../../../services/translation/translation_prefs.dart';
import '../../../services/translation/translation_text.dart' show ComposeTranslateMode;
import '../../../services/translation/translator.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/inline_notice.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../translation/translation_ui.dart';
import '../providers/settings_provider.dart';

class TranslationSettingsSection extends ConsumerStatefulWidget {
  const TranslationSettingsSection({super.key});

  @override
  ConsumerState<TranslationSettingsSection> createState() => _TranslationSettingsSectionState();
}

class _TranslationSettingsSectionState extends ConsumerState<TranslationSettingsSection> {
  bool? _available;
  List<String> _languages = const [];
  Map<String, String> _names = const {};
  Set<String>? _downloaded;

  @override
  void initState() {
    super.initState();
    if (translationPlatformSupported) unawaited(_load());
  }

  Future<void> _load() async {
    final t = ref.read(translatorProvider);
    try {
      final ok = await t.isAvailable();
      if (!ok) {
        if (mounted) setState(() => _available = false);
        return;
      }
      final langs = await t.supportedLanguages();
      final display = ref.read(settingsProvider).locale.languageCode;
      final names = await TranslationNames.load(t, langs, display);
      final downloaded = t.canManageModels ? await t.downloadedModels() : null;
      if (!mounted) return;
      setState(() {
        _available = true;
        _languages = [...langs]..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
        _names = names;
        _downloaded = downloaded;
      });
    } catch (e) {
      AppLogger.debug('Перевод: настройки: $e');
      if (mounted) setState(() => _available = false);
    }
  }

  String _name(String c) => capitalizeLangName(_names[c] ?? c);

  /// Выбор языков «не переводить» — списком с галочками.
  Future<void> _pickNever(AppLocalizations l10n) async {
    final selected = {...ref.read(settingsProvider).translateNever};
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SettingsSectionTitle(l10n.tr('translateNeverSetting')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in _languages)
                  CheckboxListTile(
                    title: Text(_name(c)),
                    value: selected.contains(c),
                    onChanged: (v) {
                      setSt(() => v == true ? selected.add(c) : selected.remove(c));
                      unawaited(ref.read(settingsProvider.notifier).setTranslateNever(selected.toList()..sort()));
                    },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// Скачанные языки: удалить или скачать ещё один.
  Future<void> _models(AppLocalizations l10n) async {
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final have = (_downloaded ?? const <String>{}).toList()..sort((a, b) => _name(a).compareTo(_name(b)));
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SettingsSectionTitle(l10n.tr('translateModelsSetting')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                if (have.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Text(l10n.tr('translateNoModels')),
                  ),
                for (final c in have)
                  ListTile(
                    leading: const Icon(AppIcons.translate),
                    title: Text(_name(c)),
                    trailing: IconButton(
                      tooltip: l10n.tr('delete'),
                      icon: const Icon(AppIcons.delete),
                      onPressed: () async {
                        try {
                          await ref.read(translatorProvider).deleteModel(c);
                        } catch (e) {
                          AppLogger.warning('Перевод: удаление языка $c: $e');
                          showInlineError(l10n.tr('translateFailed'));
                        }
                        // Лист или раздел могли закрыть, пока шло удаление
                        // (журнал 02.11.2026: setState после закрытия).
                        if (!mounted) return;
                        await _load();
                        if (ctx.mounted) setSt(() {});
                      },
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: FilledButton.icon(
                icon: const Icon(AppIcons.download),
                label: Text(l10n.tr('translateAddModel')),
                onPressed: () async {
                  final lang = await pickTranslationTarget(ctx, ref);
                  if (lang == null || !ctx.mounted) return;
                  // Модели скачиваются парой; английский — опорный язык ML Kit.
                  final app = normalizeLang(ref.read(settingsProvider).locale.languageCode) ?? 'en';
                  final other = lang == 'en' ? (app == 'en' ? 'ru' : app) : 'en';
                  await ensureTranslationModels(ctx, ref, from: lang, to: other);
                  // Скачивание долгое — лист могли закрыть (журнал 02.11.2026).
                  if (!mounted) return;
                  await _load();
                  if (ctx.mounted) setSt(() {});
                },
              ),
            ),
          ]),
        );
      }),
    );
  }

  static String _modeKey(ComposeTranslateMode m) => switch (m) {
        ComposeTranslateMode.replace => 'translateModeReplace',
        ComposeTranslateMode.originalFirst => 'translateModeOrigFirst',
        ComposeTranslateMode.translationFirst => 'translateModeTransFirst',
      };

  Future<void> _pickReadMode(AppLocalizations l10n) async {
    final prefs = ref.read(sharedPrefsProvider);
    final cur = TranslationMemory.readMode(prefs);
    final picked = await showActionSheet<ComposeTranslateMode>(
      context,
      title: l10n.tr('translateReadMode'),
      items: [
        for (final m in ComposeTranslateMode.values)
          ActionSheetItem(
            icon: m == cur ? AppIcons.radio_button_checked : AppIcons.radio_button_unchecked,
            label: l10n.tr(_modeKey(m)),
            value: m,
          ),
      ],
    );
    if (picked == null || !mounted) return;
    await TranslationMemory.setReadMode(prefs, picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!translationPlatformSupported || _available == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final t = ref.read(translatorProvider);
    if (_available == false) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SettingsSectionTitle(l10n.tr('translateSection')),
        SettingsIntro(l10n.tr(translateUnavailableKey())),
      ]);
    }
    final never = settings.translateNever;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSectionTitle(l10n.tr('translateSection')),
      // Условия ML Kit: в справке приложения — что перевод от Google.
      SettingsIntro(l10n.tr(t.googleAttribution ? 'translateEngineGoogle' : 'translateEngineApple')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.translate,
          title: l10n.tr('translateOfferSetting'),
          subtitle: l10n.tr('translateOfferDesc'),
          value: settings.translateOffer,
          onChanged: notifier.setTranslateOffer,
        ),
        // Показ перевода входящего письма (1.10.5, просьба владельца
        // 03.11.2026: «оставлять два варианта, если пользователь это
        // выбирает») — тема и текст.
        SettingsItem(
          key: const ValueKey('translate_read_mode'),
          icon: AppIcons.view_agenda,
          title: l10n.tr('translateReadMode'),
          subtitle: l10n.tr(_modeKey(TranslationMemory.readMode(ref.read(sharedPrefsProvider)))),
          onTap: () => unawaited(_pickReadMode(l10n)),
        ),
        SettingsItem(
          icon: AppIcons.block,
          title: l10n.tr('translateNeverSetting'),
          subtitle: never.isEmpty ? l10n.tr('none') : never.map(_name).join(', '),
          onTap: () => unawaited(_pickNever(l10n)),
        ),
        if (t.canManageModels) ...[
          SettingsSwitchItem(
            icon: AppIcons.wifi,
            title: l10n.tr('translateWifiOnly'),
            value: settings.translateWifiOnly,
            onChanged: notifier.setTranslateWifiOnly,
          ),
          SettingsItem(
            icon: AppIcons.download,
            title: l10n.tr('translateModelsSetting'),
            subtitle: (_downloaded ?? const <String>{}).isEmpty
                ? l10n.tr('translateModelsDesc')
                : (_downloaded!.map(_name).toList()..sort()).join(', '),
            onTap: () => unawaited(_models(l10n)),
          ),
        ],
      ]),
      if (!t.canManageModels)
        SettingsIntro(l10n.tr(!kIsWeb && Platform.isMacOS ? 'translateModelsMac' : 'translateModelsIos')),
    ]);
  }
}

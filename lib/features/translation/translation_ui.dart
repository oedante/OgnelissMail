// lib/features/translation/translation_ui.dart
//
// Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026): общие
// окна — скачивание языков, выбор языка и способа вставки перевода, названия
// языков. Используют экран письма, экран «Написать» и «Настройки → Почта».

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/translation/translation_languages.dart';
import '../../services/translation/translation_prefs.dart';
import '../../services/translation/translation_text.dart';
import '../../services/translation/translator.dart';
import '../../widgets/common/inline_notice.dart';
import '../../widgets/ui/action_sheet.dart';
import '../settings/providers/settings_provider.dart';

/// Названия языков на языке приложения — от системы (Android, iOS), один
/// раз за запуск. Нет названия — код.
class TranslationNames {
  TranslationNames._();

  static final Map<String, Map<String, String>> _cache = {};

  static Future<Map<String, String>> load(Translator t, Iterable<String> codes, String display) async {
    final have = _cache.putIfAbsent(display, () => {});
    final need = codes.where((c) => !have.containsKey(c)).toList();
    if (need.isNotEmpty) {
      final r = await t.languageNames(need, display);
      for (final c in need) {
        have[c] = r[c]?.trim().isNotEmpty == true ? r[c]!.trim() : c.toUpperCase();
      }
    }
    return {for (final c in codes) c: have[c] ?? c.toUpperCase()};
  }

  static Future<String> one(Translator t, String code, String display) async =>
      (await load(t, [code], display))[code]!;
}

/// Языки пары скачаны; нет — спросить и скачать. true — можно переводить.
Future<bool> ensureTranslationModels(BuildContext context, WidgetRef ref,
    {required String from, required String to}) async {
  final t = ref.read(translatorProvider);
  final l10n = AppLocalizations.of(context);
  List<String> missing;
  try {
    missing = await t.missingModels(from, to);
  } catch (e) {
    AppLogger.warning('Перевод: языки $from → $to: $e');
    quietError(l10n.tr('translateFailed'));
    return false;
  }
  if (missing.isEmpty) return true;
  if (!t.canManageModels) {
    // iOS: окно «Скачать языки?» показывает сама система.
    try {
      await t.download(from, to, wifiOnly: false);
      return true;
    } catch (e) {
      AppLogger.warning('Перевод: скачивание языков iOS: $e');
      return false;
    }
  }
  if (!context.mounted) return false;
  final names = await TranslationNames.load(t, missing, l10n.locale.languageCode);
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ModelDownloadDialog(from: from, to: to, names: names.values.toList()),
  );
  return ok == true;
}

/// Окно «Скачать языки для перевода»: какие языки и сколько весят, «Только
/// по Wi-Fi», ход скачивания.
class _ModelDownloadDialog extends ConsumerStatefulWidget {
  final String from;
  final String to;
  final List<String> names;
  const _ModelDownloadDialog({required this.from, required this.to, required this.names});

  @override
  ConsumerState<_ModelDownloadDialog> createState() => _ModelDownloadDialogState();
}

class _ModelDownloadDialogState extends ConsumerState<_ModelDownloadDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _download() async {
    final l10n = AppLocalizations.of(context);
    final wifiOnly = ref.read(settingsProvider).translateWifiOnly;
    if (wifiOnly) {
      // ML Kit с условием «только Wi-Fi» без Wi-Fi не падает, а ждёт сети
      // молча — окно висело бы без конца. Проверяем сами.
      final net = await Connectivity().checkConnectivity();
      if (!net.contains(ConnectivityResult.wifi) && !net.contains(ConnectivityResult.ethernet)) {
        setState(() => _error = l10n.tr('translateNeedWifi'));
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(translatorProvider).download(widget.from, widget.to, wifiOnly: wifiOnly);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      AppLogger.warning('Перевод: скачивание языков: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          // Не «Не удалось перевести» (1.12.x): не скачались языки — нет
          // сети или ML Kit не может скачать модель на этом телефоне.
          _error = l10n.tr('translateDownloadFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mb = ref.read(translatorProvider).modelSizeMb;
    final wifiOnly = ref.watch(settingsProvider).translateWifiOnly;
    return AlertDialog(
      title: Text(l10n.tr('translateModelsTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.tr('translateModelsBody').replaceAll('{langs}', widget.names.join(', '))),
          if (mb != null) ...[
            const SizedBox(height: Space.s),
            Text(l10n.tr('translateModelSize').replaceAll('{mb}', '$mb'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.tr('translateWifiOnly')),
            value: wifiOnly,
            onChanged: _busy ? null : (v) => ref.read(settingsProvider.notifier).setTranslateWifiOnly(v),
          ),
          if (_busy) ...[
            Text(l10n.tr('translateDownloading'), style: theme.textTheme.bodySmall),
            const SizedBox(height: Space.xs),
            // ML Kit не сообщает, сколько скачано, — ход без процентов.
            const LinearProgressIndicator(),
          ],
          if (_error != null)
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.tr('cancel'))),
        FilledButton(onPressed: _busy ? null : () => unawaited(_download()), child: Text(l10n.tr('download'))),
      ],
    );
  }
}

/// «Перевести на…»: язык собеседника, недавние, остальные. null — закрыли.
/// [suggestedLabel] — подпись первого языка вместо «Язык собеседника»
/// (выбор языка письма, 1.12.x: там первым — догадка определителя).
Future<String?> pickTranslationTarget(BuildContext context, WidgetRef ref,
    {String? source, String? suggested, String? title, String? suggestedLabel}) async {
  final t = ref.read(translatorProvider);
  final l10n = AppLocalizations.of(context);
  final display = l10n.locale.languageCode;
  final available = await t.supportedLanguages();
  final names = await TranslationNames.load(t, available, display);
  if (!context.mounted) return null;
  final recent = TranslationMemory.recent(ref.read(sharedPrefsProvider));
  final order = orderTargetLanguages(
      available: available, recent: recent, suggested: suggested, source: source, names: names);
  final recentSet = recent.map(normalizeLang).toSet();
  return showChoiceSheet<String>(
    context,
    title: title ?? l10n.tr('translateTo'),
    entries: [
      for (final c in order)
        AppMenuEntry(
          value: c,
          label: capitalizeLangName(names[c] ?? c),
          icon: AppIcons.translate,
          subtitle: c == normalizeLang(suggested)
              ? suggestedLabel ?? l10n.tr('translateSuggested')
              : recentSet.contains(c)
                  ? l10n.tr('translateRecentLang')
                  : null,
        ),
    ],
  );
}

/// «Заменить текст» или «Оставить оба» (с порядком); последний выбор
/// отмечен и запоминается.
Future<ComposeTranslateMode?> pickComposeTranslateMode(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final prefs = ref.read(sharedPrefsProvider);
  final m = await showChoiceSheet<ComposeTranslateMode>(
    context,
    title: l10n.tr('translateModeTitle'),
    selected: TranslationMemory.mode(prefs),
    entries: [
      AppMenuEntry(
          value: ComposeTranslateMode.replace, icon: AppIcons.translate, label: l10n.tr('translateModeReplace')),
      AppMenuEntry(
          value: ComposeTranslateMode.originalFirst,
          icon: AppIcons.language,
          label: l10n.tr('translateModeOrigFirst')),
      AppMenuEntry(
          value: ComposeTranslateMode.translationFirst,
          icon: AppIcons.swap_vert,
          label: l10n.tr('translateModeTransFirst')),
    ],
  );
  if (m != null) await TranslationMemory.setMode(prefs, m);
  return m;
}

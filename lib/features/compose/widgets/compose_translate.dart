// lib/features/compose/widgets/compose_translate.dart
//
// Перевод своего письма на устройстве (1.9.x, просьба владельца 31.10.2026:
// «пользователь написал на русском и при нажатии кнопки перевёл на
// английский с возможностью оставить два текста»).
//
// «Перевести» в меню экрана «Написать» → язык (сначала язык собеседника —
// по цитате письма, на которое отвечают, затем недавние) → «Заменить текст»
// или «Оставить оба» (сначала оригинал или сначала перевод; выбор
// запоминается). Переводится только свой текст с приветствием: подпись и
// цитата остаются как есть. Вернуть исходный текст — кнопкой «Вернуть» в
// строке сообщения или «Отменить» редактора.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/translation/translation_languages.dart';
import '../../../services/translation/translation_prefs.dart';
import '../../../services/translation/translation_text.dart';
import '../../../services/translation/translator.dart';
import '../../../widgets/common/inline_notice.dart';
import '../../translation/translation_ui.dart';

/// Перевести своё письмо. [readBody] — текущее тело (HTML редактора или
/// текст простого поля, [html]), [apply] — записать новое тело.
Future<void> translateComposeBody(
  BuildContext context,
  WidgetRef ref, {
  required bool html,
  required Future<String> Function() readBody,
  required void Function(String body) apply,
  String? signaturePlain,
  String? quoteHtml,
}) async {
  final t = ref.read(translatorProvider);
  final l10n = AppLocalizations.of(context);
  if (!await t.isAvailable()) {
    showInlineError(l10n.tr('translateUnavailable'));
    return;
  }
  final before = await readBody();
  final split = html ? ComposeTranslation.splitOwn(before) : ComposeTranslation.splitOwnPlain(before, signaturePlain);
  final ownText = html ? visibleTextSample(split.own) : split.own.trim();
  if (!worthTranslating(ownText)) {
    showInlineError(l10n.tr('nothingToTranslate'));
    return;
  }
  final appLang = normalizeLang(l10n.locale.languageCode) ?? 'en';
  final source = await t.detectLanguage(ownText) ?? appLang;
  // Язык собеседника — по письму, на которое отвечают.
  String? quoteLang;
  final quote = quoteHtml == null ? '' : visibleTextSample(quoteHtml);
  if (quote.length >= 20) quoteLang = await t.detectLanguage(quote);
  final suggested = suggestRecipientLanguage(quoteLang: quoteLang, ownLang: source);
  if (!context.mounted) return;
  final target = await pickTranslationTarget(context, ref, source: source, suggested: suggested);
  if (target == null || !context.mounted) return;
  final mode = await pickComposeTranslateMode(context, ref);
  if (mode == null || !context.mounted) return;
  if (!await ensureTranslationModels(context, ref, from: source, to: target)) return;
  showInlineNotice(l10n.tr('translateWorking'));
  try {
    final translated = html
        ? await translateHtml(t, split.own, from: source, to: target)
        : await translatePlain(t, split.own, from: source, to: target);
    await TranslationMemory.rememberTarget(ref.read(sharedPrefsProvider), target);
    // Подпись второго блока — на его языке («English», «Русский»): её
    // читает получатель.
    final labelLang = mode == ComposeTranslateMode.translationFirst ? source : target;
    final label = capitalizeLangName(await TranslationNames.one(t, labelLang, labelLang));
    final after = html
        ? ComposeTranslation.assemble(split: split, translated: translated, mode: mode, label: label)
        : ComposeTranslation.assemblePlain(split: split, translated: translated, mode: mode, label: label);
    apply(after);
    final targetName = capitalizeLangName(await TranslationNames.one(t, target, l10n.locale.languageCode));
    showInlineNotice(
      l10n.tr('translateComposeDone').replaceAll('{lang}', targetName),
      actionLabel: l10n.tr('translateRevert'),
      onAction: () => apply(before),
    );
  } catch (e) {
    AppLogger.warning('Перевод своего письма $source → $target: $e');
    showInlineError(l10n.tr('translateFailed'));
  }
}

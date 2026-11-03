// lib/features/mail/widgets/mail_translation.dart
//
// Перевод входящего письма на устройстве (1.9.x, просьба владельца
// 31.10.2026), как в Gmail и Telegram: язык письма не язык приложения —
// плашка «Язык письма: английский · Перевести»; перевод заменяет текст
// письма, «Показать оригинал» возвращает. Пункт «Перевести» — и в меню
// письма. Переводы хранятся в памяти до конца запуска (письмо открыли
// снова — перевод сразу).
//
// HTML переводится по текстовым узлам (translation_text.dart): разметка,
// ссылки, стили остаются; разбор длинных писем — вне UI-изолята.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/quote_splitter.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/translation/translation_languages.dart';
import '../../../services/translation/translation_text.dart';
import '../../../services/translation/translator.dart';
import '../../../widgets/common/inline_notice.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/banner_button.dart';
import '../../settings/providers/settings_provider.dart';
import '../../translation/translation_ui.dart';

enum MailTranslationPhase { none, offer, working, translated }

class _Translated {
  final String? sourceHtml;
  final String? sourcePlain;
  final String? html;
  final String? plain;
  const _Translated(this.sourceHtml, this.sourcePlain, this.html, this.plain);
}

/// Состояние перевода открытого письма. Экран письма слушает его и
/// показывает [apply] вместо письма.
class MailTranslationController extends ChangeNotifier {
  MailTranslationController(this.ref);

  final WidgetRef ref;

  /// Переводы за запуск: «id письма|язык».
  static final Map<String, _Translated> _cache = {};

  String? _emailId;
  String? _detectedFor;
  MailTranslationPhase phase = MailTranslationPhase.none;

  /// Язык письма и язык перевода (коды) и их названия на языке приложения.
  String? from;
  String? to;
  String fromName = '';
  String toName = '';

  /// Показан перевод (а не оригинал).
  bool showing = false;

  /// Плашку закрыли крестиком (до следующего письма).
  bool dismissed = false;

  bool _disposed = false;

  /// Строки для сообщения об ошибке: перевод заканчивается вне build.
  AppLocalizations? _l10n;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _resetFor(String id) {
    if (_emailId == id) return;
    _emailId = id;
    _detectedFor = null;
    phase = MailTranslationPhase.none;
    from = null;
    to = null;
    showing = false;
    dismissed = false;
  }

  /// Язык приложения — читается, пока экран жив (в build и по нажатию):
  /// после await экран могли закрыть, и ref уже нельзя трогать.
  String _lang = 'en';
  String _appLang() => _lang;

  /// Определить язык письма (один раз на письмо) и решить, предлагать ли
  /// перевод. Вызывается из build — сама работа после кадра.
  void detect(EmailModel e) {
    if (!translationPlatformSupported) return;
    _lang = ref.read(settingsProvider).locale.languageCode;
    _resetFor(e.id);
    final key = '${e.id}|${(e.bodyHtml ?? e.bodyPlain ?? '').length}';
    if (_detectedFor == key) return;
    _detectedFor = key;
    unawaited(_detect(e));
  }

  Future<void> _detect(EmailModel e) async {
    final t = ref.read(translatorProvider);
    if (!await t.isAvailable()) return;
    final settings = ref.read(settingsProvider);
    final sample = await _sample(e);
    if (sample.length < 20 || _emailId != e.id) return;
    final lang = await _detectLang(t, e);
    if (_emailId != e.id || lang == null) return;
    from = lang;
    to = normalizeLang(_appLang());
    final available = await t.supportedLanguages();
    if (_emailId != e.id) return;
    await _loadNames(t);
    final offer = shouldOfferTranslation(
        detected: lang,
        appLang: _appLang(),
        enabled: settings.translateOffer,
        never: settings.translateNever,
        available: available);
    if (phase == MailTranslationPhase.none && offer) phase = MailTranslationPhase.offer;
    _notify();
  }

  Future<void> _loadNames(Translator t) async {
    final f = from, tt = to;
    if (f == null || tt == null) return;
    final names = await TranslationNames.load(t, [f, tt], _appLang());
    fromName = names[f] ?? f;
    toName = names[tt] ?? tt;
  }

  /// Образец текста для определения языка — свежий текст письма, без
  /// цитаты (1.10.1): у ответа с цитатой на другом языке определитель ML
  /// Kit не был уверен («und»), и перевод падал с «Не удалось перевести».
  static Future<String> _sample(EmailModel e) async {
    final plain = languageSample(replyPartOfPlain(e.bodyPlain ?? ''));
    if (plain.length >= 40) return plain.length > 1500 ? plain.substring(0, 1500) : plain;
    final html = e.bodyHtml ?? '';
    if (html.isEmpty) return plain;
    final reply = languageSample(await MailBodyHeavy.replySample(html));
    return reply.length >= 20 ? reply : languageSample(await MailBodyHeavy.sample(html));
  }

  /// Текст для определителя языка (1.10.5): без ссылок, адресов почты и
  /// угловых скобок — они не язык, а в коротком ответе их доля большая
  /// (журнал владельца 03.11.2026: язык ответа со ссылками не определялся).
  @visibleForTesting
  static String languageSample(String s) => s
      .replaceAll(RegExp(r'(?:https?://|www\.)\S+', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\S+@\S+\.\S+'), ' ')
      .replaceAll(RegExp(r'[<>\[\]]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @visibleForTesting
  static Future<String> debugSample(EmailModel e) => _sample(e);

  /// Язык письма: по свежему тексту, а не вышло — по первым строкам (там
  /// реже смешаны языки).
  static Future<String?> _detectLang(Translator t, EmailModel e) async {
    final sample = await _sample(e);
    final lang = await t.detectLanguage(sample);
    if (lang != null || sample.length <= 300) return lang;
    final head = sample.substring(0, 300);
    final again = await t.detectLanguage(head);
    if (again == null) _logUndetected(sample);
    return again;
  }

  /// Доля латинских букв среди букв текста (0…1).
  @visibleForTesting
  static double latinShare(String s) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(s).length;
    if (letters == 0) return 0;
    return RegExp('[A-Za-z]').allMatches(s).length / letters;
  }

  /// Почему язык не определён — в журнал без текста письма: длина и доля
  /// латиницы и кириллицы (раньше — только в подробном журнале, и причину
  /// «Не удалось перевести» было не видно).
  static void _logUndetected(String sample) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(sample).length;
    int share(RegExp re) => letters == 0 ? 0 : (re.allMatches(sample).length * 100 / letters).round();
    AppLogger.warning('Перевод: язык письма не определён — образец ${sample.length} знаков, '
        'латиница ${share(RegExp('[A-Za-z]'))} %, кириллица ${share(RegExp('[А-Яа-яЁё]'))} %');
  }

  /// Письмо, как его показать: с переводом или как есть.
  EmailModel apply(EmailModel e) {
    if (!showing || e.id != _emailId || to == null) return e;
    final c = _cache['${e.id}|$to'];
    if (c == null) return e;
    final htmlSame = e.bodyHtml == null || identical(c.sourceHtml, e.bodyHtml) || c.sourceHtml == e.bodyHtml;
    if (!htmlSame) {
      // Тело письма сменилось (разрешили картинки, догрузилось) — перевод
      // устарел: переводим новое, пока — оригинал.
      _cache.remove('${e.id}|$to');
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run(e)));
      return e;
    }
    return e.copyWith(bodyHtml: c.html ?? e.bodyHtml, bodyPlain: c.plain ?? e.bodyPlain);
  }

  /// «Перевести» (плашка или меню письма).
  Future<void> translate(BuildContext context, EmailModel e) async {
    final t = ref.read(translatorProvider);
    final l10n = _l10n = AppLocalizations.of(context);
    _lang = ref.read(settingsProvider).locale.languageCode;
    if (!await t.isAvailable()) {
      showInlineError(l10n.tr('translateUnavailable'));
      return;
    }
    _resetFor(e.id);
    if (from == null) {
      var lang = await _detectLang(t, e);
      // Язык не определился — спросить, с какого переводить (1.10.5), а не
      // «Не удалось перевести».
      if (lang == null && context.mounted) {
        // Текст латиницей — первым предложить английский: письма латиницей,
        // которые определитель не узнал, чаще всего английские.
        final sample = await _sample(e);
        if (!context.mounted) return;
        lang = await pickTranslationTarget(context, ref,
            title: l10n.tr('translateFrom'),
            source: normalizeLang(_appLang()),
            suggested: latinShare(sample) >= 0.8 ? 'en' : null);
      }
      if (lang == null) return;
      from = lang;
      to = normalizeLang(_appLang());
      await _loadNames(t);
    }
    if (from == to) {
      showInlineError(l10n.tr('nothingToTranslate'));
      return;
    }
    if (_cache.containsKey('${e.id}|$to')) {
      showing = true;
      phase = MailTranslationPhase.translated;
      _notify();
      return;
    }
    if (!context.mounted) return;
    if (!await ensureTranslationModels(context, ref, from: from!, to: to!)) return;
    await _run(e);
  }

  Future<void> _run(EmailModel e) async {
    final f = from, tt = to;
    if (f == null || tt == null || _disposed) return;
    final t = ref.read(translatorProvider);
    phase = MailTranslationPhase.working;
    _notify();
    try {
      final html = e.bodyHtml;
      final plain = e.bodyPlain;
      String? trHtml;
      String? trPlain;
      if (html != null && html.isNotEmpty) {
        final texts = await MailBodyHeavy.segments(html);
        final done = await translateSegments(t, texts, from: f, to: tt);
        trHtml = await MailBodyHeavy.rebuild(html, done);
      }
      if (plain != null && plain.isNotEmpty && (html == null || html.isEmpty)) {
        trPlain = await translatePlain(t, plain, from: f, to: tt);
      }
      _cache['${e.id}|$tt'] = _Translated(html, plain, trHtml, trPlain);
      if (_emailId != e.id) return;
      showing = true;
      phase = MailTranslationPhase.translated;
    } catch (err) {
      AppLogger.warning('Перевод письма $f → $tt: $err');
      final l10n = _l10n;
      if (l10n != null) showInlineError(l10n.tr('translateFailed'));
      phase = showing ? MailTranslationPhase.translated : MailTranslationPhase.offer;
    }
    _notify();
  }

  void showOriginal() {
    showing = false;
    _notify();
  }

  void showTranslation() {
    showing = true;
    _notify();
  }

  void dismiss() {
    dismissed = true;
    _notify();
  }

  /// «Не переводить с этого языка» — в настройки, плашка закрывается.
  Future<void> never() async {
    final f = from;
    if (f == null) return;
    final n = ref.read(settingsProvider.notifier);
    final list = ref.read(settingsProvider).translateNever;
    await n.setTranslateNever([...list.where((x) => x != f), f]);
    dismiss();
  }
}

/// Разбор письма вне UI-изолята (длинные рассылки — сотни узлов).
class MailBodyHeavy {
  static const _threshold = 20000;

  static List<String> _segments(String html) => HtmlTextSegments.parse(html).texts;
  static String _rebuild((String, List<String>) a) => HtmlTextSegments.parse(a.$1).rebuild(a.$2);
  static String _sample(String html) => visibleTextSample(html);
  static String _replySample(String html) => visibleTextSample(splitQuotedHtml(html).reply);

  static Future<List<String>> segments(String html) =>
      html.length < _threshold ? SynchronousFuture(_segments(html)) : compute(_segments, html);

  static Future<String> rebuild(String html, List<String> translated) => html.length < _threshold
      ? SynchronousFuture(_rebuild((html, translated)))
      : compute(_rebuild, (html, translated));

  static Future<String> sample(String html) =>
      html.length < _threshold ? SynchronousFuture(_sample(html)) : compute(_sample, html);

  /// Образец свежего текста — без свёрнутой цитаты (как на экране письма).
  static Future<String> replySample(String html) =>
      html.length < _threshold ? SynchronousFuture(_replySample(html)) : compute(_replySample, html);
}

/// Плашка перевода над текстом письма.
class MailTranslateStrip extends StatelessWidget {
  final MailTranslationController controller;
  final EmailModel email;
  const MailTranslateStrip({super.key, required this.controller, required this.email});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.dismissed || c.phase == MailTranslationPhase.none) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final t = c.ref.read(translatorProvider);
    final String text;
    final Widget action;
    switch (c.phase) {
      case MailTranslationPhase.working:
        text = l10n.tr('translateWorking');
        action = const Padding(
          padding: EdgeInsets.all(Space.s),
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case MailTranslationPhase.translated:
        text = c.showing
            ? l10n.tr('translateDone').replaceAll('{from}', c.fromName).replaceAll('{to}', c.toName)
            : l10n.tr('translateMsgLang').replaceAll('{lang}', c.fromName);
        action = BannerButton(
          label: l10n.tr(c.showing ? 'translateShowOriginal' : 'translateShowTranslation'),
          onPressed: c.showing ? c.showOriginal : c.showTranslation,
        );
      default:
        text = l10n.tr('translateMsgLang').replaceAll('{lang}', c.fromName);
        action = BannerButton(
          label: l10n.tr('translate'),
          onPressed: () => unawaited(c.translate(context, email)),
        );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      padding: bannerPadding,
      constraints: const BoxConstraints(minHeight: bannerMinHeight),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: Radii.chipAll),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(AppIcons.translate, size: Sizes.iconInline, color: color),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: theme.textTheme.labelLarge?.copyWith(color: color)),
              // Условия ML Kit: у перевода Google — подпись Google.
              if (c.showing && t.googleAttribution)
                Text(l10n.tr('translateByGoogle'),
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
        action,
        if (c.phase == MailTranslationPhase.offer)
          IconButton(
            tooltip: l10n.tr('more'),
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.more_vert, size: 20, color: theme.colorScheme.onSurfaceVariant),
            onPressed: () => unawaited(_more(context, l10n)),
          ),
      ]),
    );
  }

  Future<void> _more(BuildContext context, AppLocalizations l10n) async {
    final v = await showActionSheet<String>(context, items: [
      ActionSheetItem(
          icon: AppIcons.block,
          label: l10n.tr('translateNeverLang').replaceAll('{lang}', controller.fromName),
          value: 'never'),
      ActionSheetItem(icon: AppIcons.close, label: l10n.tr('close'), value: 'close'),
    ]);
    if (v == 'never') await controller.never();
    if (v == 'close') controller.dismiss();
  }
}

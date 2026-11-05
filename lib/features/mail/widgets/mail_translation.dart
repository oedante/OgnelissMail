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
//
// 1.10.5 (просьба владельца 03.11.2026): тема переводится тоже (без
// «RE:/FW:»); «Настройки → Перевод → Показ перевода письма» — заменить
// текст или оставить оба (сначала оригинал или сначала перевод): тема —
// вторая строкой под первой, текст — второй под линией с подписью языка.
//
// 1.12.x (просьба владельца 04.11.2026: плашка «сбоит и предлагает другие
// языки»): перевод предлагается только с языка, в котором определитель
// уверен (догадка — лишь для «Перевести», нажатого самим человеком); языки
// телефона — как язык приложения; «Всегда переводить с …» — перевод сразу
// при открытии письма. Решение — decideTranslationOffer
// (translation_languages.dart).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/quote_splitter.dart';
import '../../../core/theme/app_icons.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/translation/translation_languages.dart';
import '../../../services/translation/translation_prefs.dart';
import '../../../services/translation/translation_text.dart';
import '../../../services/translation/translator.dart';
import '../../../widgets/common/inline_notice.dart';
import '../../../widgets/common/peek_card.dart' show AppMenuEntry;
import '../../settings/providers/settings_provider.dart';
import '../../translation/translation_ui.dart';
import 'mail_notice_bar.dart';

enum MailTranslationPhase { none, offer, working, translated }

class _Translated {
  final String? sourceHtml;
  final String? sourcePlain;
  final String? html;
  final String? plain;

  /// Тема в переводе (с прежними «RE:/FW:»); null — не переводилась.
  final String? subject;

  /// Оба текста (1.10.5): по режиму — готовый HTML или текст.
  final Map<ComposeTranslateMode, ({String? html, String? plain})> both = {};

  _Translated(this.sourceHtml, this.sourcePlain, this.html, this.plain, this.subject);
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

  /// Язык письма не определился, но письмо явно не на языке приложения
  /// (1.10.5): плашка «Письмо на другом языке», по нажатию — выбор языка.
  bool unknownLang = false;
  String toName = '';

  /// Показан перевод (а не оригинал).
  bool showing = false;

  /// Плашку закрыли крестиком (до следующего письма).
  bool dismissed = false;

  /// Перевод сделан сам, без нажатия: язык письма — в «Всегда переводить
  /// с …» (1.12.x).
  bool autoTranslated = false;

  /// Движок перевода работает на устройстве: null — ещё не спрашивали,
  /// false — нет (iOS до 18, Mac до 15, Android, где не запустился ML Kit):
  /// пункт «Перевести» в меню письма можно скрыть (1.12.x).
  bool? engineAvailable;

  /// Язык письма по определителю — и уверенный, и догадка (1.12.x):
  /// [from] — только уверенный, догадкой пользуется лишь «Перевести».
  LangDetection? _guess;

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
    unknownLang = false;
    showing = false;
    dismissed = false;
    autoTranslated = false;
    _guess = null;
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
    // Настройки и языки телефона — до await: потом экран могли закрыть.
    final settings = ref.read(settingsProvider);
    final known = settings.translatePhoneLangs ? deviceLanguages() : const <String>[];
    final ok = await t.isAvailable();
    engineAvailable = ok;
    if (!ok) {
      // Меню письма может скрыть «Перевести» (1.12.x).
      _notify();
      return;
    }
    if (_stale(e)) return;
    final sample = await _sample(e);
    if (sample.length < 20 || _stale(e)) return;
    final guess = _guess = await _detectLang(t, sample);
    if (_stale(e)) return;
    final available = await t.supportedLanguages();
    if (_stale(e)) return;
    final app = normalizeLang(_appLang()) ?? 'en';
    final decision = decideTranslationOffer(
      detected: guess?.lang,
      confident: guess?.confident ?? false,
      appLang: _appLang(),
      enabled: settings.translateOffer,
      never: settings.translateNever,
      always: settings.translateAlways,
      known: known,
      available: available,
      // Язык не определился уверенно (письмо XERJ, 03.11.2026: не было даже
      // кнопки «Перевести»), но письмо другим алфавитом, чем язык
      // приложения, — плашку всё равно показать; язык спросим по нажатию.
      otherScript: otherScript(sample, app),
    );
    if (guess != null && guess.confident) {
      // Уверенный язык — и для «Перевести» из меню, когда плашки нет.
      from = guess.lang;
      to = app;
      await _loadNames(t);
      if (_stale(e)) return;
    }
    if (phase == MailTranslationPhase.none) {
      switch (decision) {
        case TranslationOffer.none:
          break;
        case TranslationOffer.otherLanguage:
          unknownLang = true;
          to = app;
          phase = MailTranslationPhase.offer;
        case TranslationOffer.offer:
          phase = MailTranslationPhase.offer;
        case TranslationOffer.auto:
          await _autoTranslate(t, e);
          if (_stale(e)) return;
      }
    }
    _notify();
  }

  /// Письмо сменилось или экран закрыт — результат уже не нужен.
  bool _stale(EmailModel e) => _disposed || _emailId != e.id;

  /// «Всегда переводить с …» (1.12.x): перевод сразу, без плашки — если
  /// языки уже на устройстве. Нет — обычная плашка «Перевести»: окно
  /// скачивания (до 30 МБ на язык) при открытии письма было бы навязчивым.
  Future<void> _autoTranslate(Translator t, EmailModel e) async {
    final f = from, tt = to;
    if (f == null || tt == null || f == tt) return;
    final cached = _cache['${e.id}|$tt'];
    if (cached != null) {
      await _buildBoth(cached, mode);
      showing = true;
      autoTranslated = true;
      phase = MailTranslationPhase.translated;
      return;
    }
    var missing = const <String>[];
    try {
      missing = await t.missingModels(f, tt);
    } catch (err) {
      AppLogger.warning('Перевод: языки $f → $tt: $err');
      missing = [f];
    }
    if (_stale(e)) return;
    if (missing.isNotEmpty) {
      phase = MailTranslationPhase.offer;
      return;
    }
    // Строки (подпись «оставить оба») — без экрана: перевод начат не им.
    final l10n = _l10n;
    if (l10n == null || l10n.locale.languageCode != _appLang()) _l10n = await AppLocalizations.load(_appLang());
    if (_stale(e)) return;
    autoTranslated = true;
    await _run(e, quiet: true);
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

  /// Язык письма: по свежему тексту ([sample] — из [_sample]), а не вышло
  /// уверенно — по первым строкам (там реже смешаны языки). Уверенный ответ
  /// лучше догадки (1.12.x).
  static Future<LangDetection?> _detectLang(Translator t, String sample) async {
    final s = mainScriptSample(sample);
    final first = await t.identifyLanguage(s);
    var r = first;
    if (first?.confident != true && s.length > 300) {
      final again = await t.identifyLanguage(s.substring(0, 300));
      r = again?.confident == true ? again : first ?? again;
    }
    if (r?.confident != true) _logUndetected(s, r?.lang);
    return r;
  }

  /// Образец одним алфавитом (1.11.x, журнал владельца 04.11.2026: «язык
  /// письма не определён», «Не удалось перевести», русское письмо —
  /// «украинский»). В рабочей почте подпись часто на двух языках («С
  /// уважением…» | «Best regards…»), письмо с переводом — тоже на двух, и на
  /// смеси русского и английского ML Kit не уверен или называет третий
  /// язык. Если в тексте заметно (от 15 % букв) и кириллицы, и латиницы,
  /// язык определяется по словам того алфавита, которого больше.
  @visibleForTesting
  static String mainScriptSample(String s) {
    final cyr = _cyr.allMatches(s).length;
    final lat = _lat.allMatches(s).length;
    final total = cyr + lat;
    if (total < 40 || cyr * 100 < total * 15 || lat * 100 < total * 15) return s;
    final cyrMain = cyr >= lat;
    return s.split(RegExp(r'\s+')).where((w) {
      final c = _cyr.allMatches(w).length;
      final l = _lat.allMatches(w).length;
      return cyrMain ? c > 0 && c >= l : l > 0 && l > c;
    }).join(' ');
  }

  static final _cyr = RegExp('[\u0400-\u04ff]');
  static final _lat = RegExp('[A-Za-z]');

  /// Языки приложения не латиницей: письмо латиницей для них — точно на
  /// другом языке (и наоборот).
  static const _nonLatinApp = {
    'ru', 'uk', 'be', 'bg', 'sr', 'mk', 'kk', 'el', 'zh', 'ja', 'ko', 'ar', 'he', 'fa', 'hi', 'th', 'hy', 'ka',
  };

  /// Письмо другим алфавитом, чем язык приложения [appLang].
  @visibleForTesting
  static bool otherScript(String sample, String appLang) {
    if (RegExp(r'\p{L}', unicode: true).allMatches(sample).length < 20) return false;
    final latin = latinShare(sample);
    return _nonLatinApp.contains(appLang) ? latin >= 0.8 : latin <= 0.2;
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
  /// «Не удалось перевести» было не видно). Догадка [guess] (1.12.x) — тоже:
  /// по ней перевод не предлагается.
  static void _logUndetected(String sample, [String? guess]) {
    final letters = RegExp(r'\p{L}', unicode: true).allMatches(sample).length;
    int share(RegExp re) => letters == 0 ? 0 : (re.allMatches(sample).length * 100 / letters).round();
    final what = guess == null ? 'не определён' : 'не уверен (догадка $guess)';
    // Догадка — обычное дело (короткий ответ, подпись): не предупреждение.
    final log = guess == null ? AppLogger.warning : AppLogger.info;
    log('Перевод: язык письма $what — образец ${sample.length} знаков, '
        'латиница ${share(RegExp('[A-Za-z]'))} %, кириллица ${share(RegExp('[А-Яа-яЁё]'))} %');
  }

  /// Показ перевода — из настроек (читается при каждом показе: поменяли в
  /// настройках — следующее открытие письма уже по-новому).
  ComposeTranslateMode get mode => TranslationMemory.readMode(ref.read(sharedPrefsProvider));

  /// Тема для шапки письма: с переводом — по режиму (вторая — мелко под
  /// первой), без — как есть.
  ({String main, String? second}) subjectFor(EmailModel e) {
    final c = (!showing || e.id != _emailId || to == null) ? null : _cache['${e.id}|$to'];
    return MailBilingual.subject(original: e.subject, translated: c?.subject, mode: mode);
  }

  /// Подпись второго текста в «оставить оба»: «Переведено: английский →
  /// русский» под переводом, «Язык письма: английский» под оригиналом.
  String _secondLabel(ComposeTranslateMode m) {
    final l10n = _l10n;
    if (m == ComposeTranslateMode.originalFirst) {
      return l10n == null
          ? '$fromName → $toName'
          : l10n.tr('translateDone').replaceAll('{from}', fromName).replaceAll('{to}', toName);
    }
    return l10n == null ? fromName : l10n.tr('translateMsgLang').replaceAll('{lang}', fromName);
  }

  final Set<ComposeTranslateMode> _bothPending = {};

  /// Собрать «оба текста» для режима [m] (вне UI-изолята для длинных писем).
  Future<void> _buildBoth(_Translated c, ComposeTranslateMode m) async {
    if (m == ComposeTranslateMode.replace || c.both.containsKey(m)) return;
    final label = _secondLabel(m);
    final origFirst = m == ComposeTranslateMode.originalFirst;
    String? html;
    String? plain;
    final src = c.sourceHtml, tr = c.html;
    if (src != null && src.isNotEmpty && tr != null) {
      html = await MailBodyHeavy.bilingual(origFirst ? src : tr, origFirst ? tr : src, label);
    }
    final srcP = c.sourcePlain, trP = c.plain;
    if (srcP != null && srcP.isNotEmpty && trP != null) {
      plain = MailBilingual.plain(origFirst ? srcP : trP, origFirst ? trP : srcP, label);
    }
    c.both[m] = (html: html, plain: plain);
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
    final m = mode;
    if (m != ComposeTranslateMode.replace) {
      final both = c.both[m];
      if (both != null) {
        return e.copyWith(bodyHtml: both.html ?? c.html ?? e.bodyHtml, bodyPlain: both.plain ?? c.plain ?? e.bodyPlain);
      }
      // Режим поменяли после перевода — собрать оба текста; пока — перевод.
      if (_bothPending.add(m)) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await _buildBoth(c, m);
          } catch (err) {
            AppLogger.warning('Перевод: оба текста — $err');
          } finally {
            _bothPending.remove(m);
          }
          _notify();
        });
      }
    }
    return e.copyWith(bodyHtml: c.html ?? e.bodyHtml, bodyPlain: c.plain ?? e.bodyPlain);
  }

  /// «Перевести» (плашка или меню письма).
  Future<void> translate(BuildContext context, EmailModel e) async {
    final t = ref.read(translatorProvider);
    final l10n = _l10n = AppLocalizations.of(context);
    _lang = ref.read(settingsProvider).locale.languageCode;
    if (!await t.isAvailable()) {
      engineAvailable = false;
      showInlineError(l10n.tr(translateUnavailableKey()));
      return;
    }
    engineAvailable = true;
    _resetFor(e.id);
    if (from == null) {
      // Перевести нажал сам человек — годится и догадка определителя
      // (1.12.x): плашки по ней нет, но перевод письма с цитатой и ссылками
      // на другом языке так работал с 1.10.5.
      final sample = await _sample(e);
      var lang = (_guess ?? await _detectLang(t, sample))?.lang;
      // Язык не определился — спросить, с какого переводить (1.10.5), а не
      // «Не удалось перевести».
      if (lang == null && context.mounted) {
        // Текст латиницей — первым предложить английский: письма латиницей,
        // которые определитель не узнал, чаще всего английские.
        lang = await pickTranslationTarget(context, ref,
            title: l10n.tr('translateFrom'),
            source: normalizeLang(_appLang()),
            suggested: latinShare(sample) >= 0.8 ? 'en' : null,
            suggestedLabel: l10n.tr('translateLikelyLang'));
      }
      if (lang == null) return;
      from = lang;
      unknownLang = false;
      to = normalizeLang(_appLang());
      await _loadNames(t);
    }
    if (from == to) {
      showInlineError(l10n.tr('nothingToTranslate'));
      return;
    }
    final cached = _cache['${e.id}|$to'];
    if (cached != null) {
      // Переводили раньше (за этот запуск): оба текста — для нынешнего
      // режима показа (его могли сменить в настройках).
      await _buildBoth(cached, mode);
      showing = true;
      phase = MailTranslationPhase.translated;
      _notify();
      return;
    }
    if (!context.mounted) return;
    if (!await ensureTranslationModels(context, ref, from: from!, to: to!)) return;
    await _run(e);
  }

  /// «Указать язык письма» (меню плашки перевода, 1.12.x): определитель
  /// ошибся или не уверен — язык выбирает человек, письмо переводится с него
  /// заново (прежний перевод с другого языка забывается).
  Future<void> translateFromPicked(BuildContext context, EmailModel e) async {
    final t = ref.read(translatorProvider);
    final l10n = _l10n = AppLocalizations.of(context);
    _lang = ref.read(settingsProvider).locale.languageCode;
    if (!await t.isAvailable()) {
      engineAvailable = false;
      showInlineError(l10n.tr(translateUnavailableKey()));
      return;
    }
    _resetFor(e.id);
    final sample = await _sample(e);
    if (!context.mounted) return;
    final app = normalizeLang(_appLang());
    final lang = await pickTranslationTarget(context, ref,
        title: l10n.tr('translateFrom'),
        source: app,
        suggested: from ?? _guess?.lang ?? (latinShare(sample) >= 0.8 ? 'en' : null),
        suggestedLabel: l10n.tr('translateLikelyLang'));
    if (lang == null || !context.mounted || _disposed) return;
    // Кэш — по языку перевода: перевод с прежнего языка не годится.
    if (lang != from) _cache.remove('${e.id}|$app');
    from = lang;
    unknownLang = false;
    to = app;
    await _loadNames(t);
    if (!context.mounted) return;
    await translate(context, e);
  }

  /// [quiet] — перевод начат не человеком («Всегда переводить с …»):
  /// ошибка — без сообщения, просто плашка «Перевести».
  Future<void> _run(EmailModel e, {bool quiet = false}) async {
    final f = from, tt = to;
    if (f == null || tt == null || _disposed) return;
    final t = ref.read(translatorProvider);
    // Режим показа — до await: после него экран могли закрыть (ref нельзя).
    final m = mode;
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
      // Тема — без «RE:/FW:» (1.10.5). Не перевелась — письмо всё равно
      // переведено, тема как есть.
      String? trSubject;
      final (prefix, rest) = MailBilingual.splitSubject(e.subject);
      if (rest.isNotEmpty) {
        try {
          trSubject = '$prefix${(await translatePlain(t, rest, from: f, to: tt)).trim()}';
        } catch (err) {
          AppLogger.warning('Перевод темы $f → $tt: $err');
        }
      }
      final done = _Translated(html, plain, trHtml, trPlain, trSubject);
      await _buildBoth(done, m);
      _cache['${e.id}|$tt'] = done;
      if (_emailId != e.id) return;
      showing = true;
      phase = MailTranslationPhase.translated;
    } catch (err) {
      AppLogger.warning('Перевод письма $f → $tt: $err');
      if (_disposed) return;
      final l10n = _l10n;
      if (l10n != null && !quiet) showInlineError(l10n.tr('translateFailed'));
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
    if (f != null) await neverTranslateFrom(f);
  }

  /// Язык письма — в «Всегда переводить с …»: меню плашки показывает
  /// «Не переводить автоматически» вместо «Всегда переводить» (1.12.x).
  bool get alwaysFromCurrent {
    final f = from;
    return f != null && ref.read(settingsProvider).translateAlways.map(normalizeLang).contains(f);
  }

  /// «Не переводить с языка [lang]» (меню плашки, 1.12.x): язык — в
  /// «Не переводить с языков» (и из «Всегда переводить»), плашка
  /// закрывается, на экране — оригинал.
  Future<void> neverTranslateFrom(String lang) async {
    final list = ref.read(settingsProvider).translateNever;
    await ref.read(settingsProvider.notifier).setTranslateNever(withLang(list, lang));
    showing = false;
    dismiss();
  }

  /// «Всегда переводить с языка [lang]» (меню плашки, 1.12.x): язык — в
  /// «Всегда переводить с языков» (и из «Не переводить»). Письма на нём
  /// дальше переводятся сразу при открытии; с [context] и [email]
  /// переводится и это письмо (окно скачивания языков, если их ещё нет).
  Future<void> alwaysTranslateFrom(String lang, {BuildContext? context, EmailModel? email}) async {
    final n = normalizeLang(lang);
    if (n == null) return;
    final t = ref.read(translatorProvider);
    final list = ref.read(settingsProvider).translateAlways;
    await ref.read(settingsProvider.notifier).setTranslateAlways(withLang(list, n));
    dismissed = false;
    if (context != null && email != null && context.mounted && !_disposed && email.id == _emailId && !showing) {
      if (from == null || from == n) {
        if (from == null) {
          // Язык письма не был известен — теперь это выбранный.
          from = n;
          to = normalizeLang(_appLang());
          unknownLang = false;
          await _loadNames(t);
          if (!context.mounted) return;
        }
        await translate(context, email);
        return;
      }
    }
    _notify();
  }

  /// «Не переводить автоматически» (меню плашки, 1.12.x): язык уходит из
  /// «Всегда переводить с языков»; перевод на экране остаётся.
  Future<void> stopAlwaysTranslateFrom(String lang) async {
    final list = ref.read(settingsProvider).translateAlways;
    await ref.read(settingsProvider.notifier).setTranslateAlways(withoutLang(list, lang));
    autoTranslated = false;
    _notify();
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

  static String _bilingual((String, String, String) a) => MailBilingual.html(a.$1, a.$2, a.$3);

  /// Оба текста письма (1.10.5): первый, линия с подписью, второй.
  static Future<String> bilingual(String first, String second, String label) =>
      first.length + second.length < _threshold
          ? SynchronousFuture(_bilingual((first, second, label)))
          : compute(_bilingual, (first, second, label));

  /// Образец свежего текста — без свёрнутой цитаты (как на экране письма).
  static Future<String> replySample(String html) =>
      html.length < _threshold ? SynchronousFuture(_replySample(html)) : compute(_replySample, html);
}

/// Перевод в строке сведений письма (1.12.x, просьба владельца 04.11.2026:
/// плашки «съедают место»). Вместо плашки «Язык письма: … · Перевести» —
/// чип «Перевести · английский»: нажатие переводит, и чип становится
/// «Оригинал» (нажатие возвращает оригинал, ещё раз — перевод). Остальное —
/// «▾» на чипе или долгое нажатие: «Всегда переводить с …» / «Не
/// переводить автоматически», «Не переводить с …», «Указать язык письма»,
/// «Закрыть».
abstract final class MailTranslateNotice {
  static const id = 'translate';

  /// Чип перевода; null — предлагать нечего (язык приложения, перевод
  /// выключен, нет движка перевода на устройстве, чип закрыли).
  static MailNotice? of(BuildContext context, MailTranslationController c, EmailModel email) {
    if (c.dismissed || c.phase == MailTranslationPhase.none || c.engineAvailable == false) return null;
    final l10n = AppLocalizations.of(context);
    final offer = c.unknownLang
        ? l10n.tr('translate')
        : l10n.tr('noticeTranslateLang').replaceAll('{lang}', c.fromName);
    final msgLang = c.unknownLang
        ? l10n.tr('translateMsgOther')
        : l10n.tr('translateMsgLang').replaceAll('{lang}', c.fromName);
    if (c.phase == MailTranslationPhase.working) {
      return MailNotice(
        id: id,
        icon: AppIcons.translate,
        label: l10n.tr('translateWorking'),
        tone: MailNoticeTone.info,
        busy: true,
        // Пока переводится — нажимать нечего (и не раскрывать).
        onTap: () {},
      );
    }
    final (menu, onMenu) = _options(context, c, email, l10n);
    if (c.phase == MailTranslationPhase.translated) {
      final done = l10n.tr('translateDone').replaceAll('{from}', c.fromName).replaceAll('{to}', c.toName);
      return c.showing
          ? MailNotice(
              id: id,
              icon: AppIcons.translate,
              label: l10n.tr('noticeOriginal'),
              detail: '$done. ${l10n.tr('translateShowOriginal')}',
              tone: MailNoticeTone.info,
              onTap: c.showOriginal,
              menu: menu,
              onMenu: onMenu,
            )
          : MailNotice(
              id: id,
              icon: AppIcons.translate,
              label: offer,
              detail: '$msgLang. ${l10n.tr('translateShowTranslation')}',
              tone: MailNoticeTone.info,
              onTap: c.showTranslation,
              menu: menu,
              onMenu: onMenu,
            );
    }
    return MailNotice(
      id: id,
      icon: AppIcons.translate,
      label: offer,
      detail: msgLang,
      tone: MailNoticeTone.info,
      onTap: () => unawaited(c.translate(context, email)),
      menu: menu,
      onMenu: onMenu,
    );
  }

  /// Варианты чипа («▾», долгое нажатие). Язык известен — «Всегда
  /// переводить с …» (или «Не переводить автоматически», если он уже в
  /// списке) и «Не переводить с …»; всегда — «Указать язык письма»;
  /// «Закрыть» — пока на экране оригинал (с переводом закрыть чип — значит
  /// остаться без «Оригинала»).
  static (List<AppMenuEntry<String>>, ValueChanged<String>) _options(
      BuildContext context, MailTranslationController c, EmailModel email, AppLocalizations l10n) {
    final lang = c.unknownLang ? null : c.from;
    final always = lang != null && c.alwaysFromCurrent;
    final menu = <AppMenuEntry<String>>[
      if (lang != null) ...[
        always
            ? AppMenuEntry(value: 'stopAlways', icon: AppIcons.sync_disabled, label: l10n.tr('translateStopAlways'))
            : AppMenuEntry(
                value: 'always',
                icon: AppIcons.auto_mode,
                label: l10n.tr('translateAlwaysLang').replaceAll('{lang}', c.fromName)),
        AppMenuEntry(
            value: 'never',
            icon: AppIcons.block,
            label: l10n.tr('translateNeverLang').replaceAll('{lang}', c.fromName)),
      ],
      AppMenuEntry(value: 'pick', icon: AppIcons.language, label: l10n.tr('translateChooseLang')),
      if (!c.showing) AppMenuEntry(value: 'close', icon: AppIcons.close, label: l10n.tr('close')),
    ];
    void onMenu(String v) {
      final f = c.from;
      switch (v) {
        case 'always' when f != null:
          unawaited(c.alwaysTranslateFrom(f, context: context, email: email));
        case 'stopAlways' when f != null:
          unawaited(c.stopAlwaysTranslateFrom(f));
        case 'never' when f != null:
          unawaited(c.neverTranslateFrom(f));
        case 'pick':
          unawaited(c.translateFromPicked(context, email));
        case 'close':
          c.dismiss();
      }
    }

    return (menu, onMenu);
  }

  /// Подпись под строкой сведений, пока показан перевод: условия ML Kit —
  /// подпись Google рядом с переведённым текстом.
  static String? note(BuildContext context, MailTranslationController c) {
    if (!c.showing || c.dismissed || !c.ref.read(translatorProvider).googleAttribution) return null;
    return AppLocalizations.of(context).tr('translateByGoogle');
  }
}

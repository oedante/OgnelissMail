// lib/services/translation/translator.dart
//
// Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026).
//
// Движок — у платформы, текст писем в интернет не уходит:
//  · Android — Google ML Kit (перевод и определение языка), модели языков
//    (~30 МБ каждая) скачиваются при первом переводе;
//    android/app/src/main/kotlin/com/ogneliss/mail/TranslationBridge.kt.
//    Условия ML Kit требуют подписи «Google» у перевода (attribution).
//  · iPhone и iPad — Apple Translation (iOS 18+), языки скачивает система;
//    ios/Runner/AppDelegate.swift (TranslationBridge).
//  · Mac — Apple Translation (macOS 15+), как iPhone.
//  · Windows (2.2.0) — Bergamot (Mozilla, MPL-2.0) в скрытом WebView2,
//    модели Firefox Translations с сервера Ogneliss:
//    bergamot/bergamot_translator.dart. Движка нет в сборке — перевод скрыт.
//  · Linux и веб — бесплатного движка на устройстве нет: перевод скрыт.
// Канал 'ogneliss/translate'. Тесты подменяют [Translator] своим.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import 'bergamot/bergamot_translator.dart';
import 'translation_languages.dart';
import 'translation_text.dart';

/// Движок перевода.
abstract class Translator {
  /// Перевод работает на этом устройстве.
  Future<bool> isAvailable();

  /// Язык текста (код вида «en») или null — не определён. Догадка
  /// определителя без уверенности — тоже язык (перевод своего письма).
  Future<String?> detectLanguage(String text);

  /// Язык текста и уверен ли в нём определитель (1.12.x, просьба владельца
  /// 04.11.2026). Перевод письма предлагается только при уверенном языке;
  /// догадка годится, когда человек сам нажал «Перевести».
  Future<LangDetection?> identifyLanguage(String text);

  /// Языки, с которыми работает движок.
  Future<List<String>> supportedLanguages();

  /// Названия языков [codes] на языке [displayLang].
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang);

  /// Скачанные языки (Android). null — языками управляет система (iOS).
  Future<Set<String>?> downloadedModels();

  /// Языки пары, которые надо скачать перед переводом (пусто — готово).
  Future<List<String>> missingModels(String from, String to);

  /// Скачать языки пары. [wifiOnly] — только по Wi-Fi (Android).
  Future<void> download(String from, String to, {required bool wifiOnly});

  /// Удалить скачанный язык (Android).
  Future<void> deleteModel(String lang);

  /// Перевести куски текста (порядок сохраняется).
  Future<List<String>> translate(List<String> texts, {required String from, required String to});

  /// Перевод от Google (ML Kit): по условиям Google рядом с переводом нужна
  /// подпись «Переведено Google».
  bool get googleAttribution;

  /// Примерный размер одного языка, МБ (null — неизвестен).
  int? get modelSizeMb;

  /// Языки можно удалить из приложения (у iOS — только в Настройках).
  bool get canManageModels;
}

/// Перевод возможен на платформе вообще (до вопроса к движку).
/// Android — ML Kit, iPhone и Mac (1.11.0) — Apple Translation (iOS 18+,
/// macOS 15+). Windows (2.2.0) — Bergamot, если движок есть в сборке
/// (data\bergamot рядом с exe). Linux — без перевода.
bool get translationPlatformSupported =>
    debugTranslationPlatformOverride ??
    (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || bergamotEnginePresent));

/// Тесты (1.12.x): перевод «есть на платформе» и в тестах на Linux —
/// проверить плашку и раздел настроек с подделкой движка.
@visibleForTesting
bool? debugTranslationPlatformOverride;

final translatorProvider =
    Provider<Translator>((ref) => !kIsWeb && Platform.isWindows ? BergamotTranslator() : PlatformTranslator());

/// Язык текста по определителю: [confident] — уверен (ML Kit — язык выше
/// порога 0,5; Apple — гипотеза от 0,5), иначе это лучшая догадка.
typedef LangDetection = ({String lang, bool confident});

/// Строка «перевод недоступен» для этой платформы (Mac — macOS 15+;
/// Android — не запустился ML Kit, 1.12.x: прежняя строка говорила про iOS).
String translateUnavailableKey() => kIsWeb
    ? 'translateUnavailable'
    : Platform.isMacOS
        ? 'translateUnavailableMac'
        : Platform.isAndroid
            ? 'translateUnavailableAndroid'
            : 'translateUnavailable';

/// Языки телефона (1.12.x, просьба владельца 04.11.2026) — из настроек
/// системы, в виде [normalizeLang]: с них перевод не предлагается
/// («Настройки → Перевод → Языки телефона»), как и с языка приложения.
List<String> deviceLanguages() =>
    {for (final l in ServicesBinding.instance.platformDispatcher.locales) ?normalizeLang(l.languageCode)}.toList();

/// Движок платформы через канал 'ogneliss/translate'.
class PlatformTranslator implements Translator {
  static const _ch = MethodChannel('ogneliss/translate');

  /// Вызовы — по одному: на iOS переводит одно окно SwiftUI (сессия
  /// перевода на пару языков), два запроса сразу перепутали бы пары.
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() f) {
    final c = Completer<T>();
    _tail = _tail.then((_) => f().then(c.complete, onError: c.completeError));
    return c.future;
  }

  bool? _available;
  List<String>? _languages;

  @override
  Future<bool> isAvailable() async {
    if (!translationPlatformSupported) return false;
    if (_available != null) return _available!;
    try {
      _available = await _ch.invokeMethod<bool>('available') ?? false;
    } catch (e) {
      AppLogger.debug('Перевод: движок недоступен: $e');
      _available = false;
    }
    return _available!;
  }

  @override
  Future<String?> detectLanguage(String text) async => (await identifyLanguage(text))?.lang;

  @override
  Future<LangDetection?> identifyLanguage(String text) async {
    if (text.trim().isEmpty || !await isAvailable()) return null;
    try {
      return parseDetection(await _ch.invokeMethod<Object?>('detect', {'text': text}), text);
    } catch (e) {
      AppLogger.debug('Перевод: язык не определён: $e');
      return null;
    }
  }

  /// Ответ 'detect' (1.12.x): {lang, confident}; строка — от прежней
  /// сборки платформы (Mac из tool/desktop), считается уверенной, как
  /// раньше. Русский, принятый за соседний кириллический, — русский
  /// (уверенность та же).
  @visibleForTesting
  static LangDetection? parseDetection(Object? r, String text) {
    final String? code;
    var confident = true;
    if (r is Map) {
      code = r['lang'] as String?;
      confident = r['confident'] == true;
    } else {
      code = r as String?;
    }
    final lang = refineCyrillicLang(normalizeLang(code), text);
    return lang == null ? null : (lang: lang, confident: confident);
  }

  @override
  Future<List<String>> supportedLanguages() async {
    if (_languages != null) return _languages!;
    if (!await isAvailable()) return const [];
    final r = await _ch.invokeListMethod<String>('languages') ?? const [];
    return _languages = {for (final c in r) ?normalizeLang(c)}.toList();
  }

  @override
  Future<Map<String, String>> languageNames(List<String> codes, String displayLang) async {
    try {
      final r = await _ch.invokeMapMethod<String, String>('names', {'codes': codes, 'display': displayLang});
      return r ?? const {};
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<Set<String>?> downloadedModels() async {
    final r = await _ch.invokeListMethod<String>('downloaded');
    return r == null ? null : {for (final c in r) ?normalizeLang(c)};
  }

  @override
  Future<List<String>> missingModels(String from, String to) async =>
      await _ch.invokeListMethod<String>('missing', {'from': from, 'to': to}) ?? const [];

  @override
  Future<void> download(String from, String to, {required bool wifiOnly}) =>
      _serial(() => _ch.invokeMethod<void>('download', {'from': from, 'to': to, 'wifiOnly': wifiOnly}));

  @override
  Future<void> deleteModel(String lang) => _ch.invokeMethod<void>('delete', {'lang': lang});

  @override
  Future<List<String>> translate(List<String> texts, {required String from, required String to}) => _serial(() async {
        final r = await _ch.invokeListMethod<String>('translate', {'texts': texts, 'from': from, 'to': to});
        return r ?? texts;
      });

  @override
  bool get googleAttribution => !kIsWeb && Platform.isAndroid;

  // Модель языка ML Kit — около 30 МБ (документация ML Kit).
  @override
  int? get modelSizeMb => !kIsWeb && Platform.isAndroid ? 30 : null;

  @override
  bool get canManageModels => !kIsWeb && Platform.isAndroid;
}

/// Перевести куски: одинаковые — один раз («Подробнее» в рассылке
/// повторяется десятки раз), частями — длинное письмо не держит канал.
Future<List<String>> translateSegments(Translator t, List<String> texts,
    {required String from, required String to, int chunk = 40}) async {
  final unique = <String>[];
  final index = <String, int>{};
  for (final s in texts) {
    index.putIfAbsent(s, () {
      unique.add(s);
      return unique.length - 1;
    });
  }
  final done = <String>[];
  for (var i = 0; i < unique.length; i += chunk) {
    final part = unique.sublist(i, i + chunk > unique.length ? unique.length : i + chunk);
    final r = await t.translate(part, from: from, to: to);
    done.addAll(r.length == part.length ? r : part);
  }
  return [for (final s in texts) done[index[s]!]];
}

/// HTML письма с переводом текста (разметка и ссылки — как были).
Future<String> translateHtml(Translator t, String html, {required String from, required String to}) async {
  final segs = HtmlTextSegments.parse(html);
  if (segs.texts.isEmpty) return html;
  return segs.rebuild(await translateSegments(t, segs.texts, from: from, to: to));
}

/// Простой текст с переводом (по строкам).
Future<String> translatePlain(Translator t, String text, {required String from, required String to}) async {
  final segs = PlainTextSegments.parse(text);
  if (segs.texts.isEmpty) return text;
  return segs.rebuild(await translateSegments(t, segs.texts, from: from, to: to));
}

/// Условия ML Kit — на странице «Тексты лицензий» (Android): библиотеки
/// Google подключены не из pub.dev, их LicenseRegistry сам не покажет.
void registerTranslationLicense() {
  if (!kIsWeb && Platform.isWindows && bergamotEnginePresent) {
    registerBergamotLicenses();
    return;
  }
  if (kIsWeb || !Platform.isAndroid) return;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(['Google ML Kit (Translation, Language Identification)'],
        'On-device translation and language identification in Ogneliss Mail use Google ML Kit '
        '(com.google.mlkit:translate, com.google.mlkit:language-id). ML Kit is provided by Google '
        'free of charge under the ML Kit Terms of Service (https://developers.google.com/ml-kit/terms) '
        'and the Google APIs Terms of Service (https://developers.google.com/terms). '
        'Translations are powered by Google Translate on-device models: '
        'https://cloud.google.com/translate. Text is translated on the device; ML Kit may send '
        'usage and performance metrics (not message text) to Google.');
  });
}

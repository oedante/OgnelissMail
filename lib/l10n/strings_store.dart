// lib/l10n/strings_store.dart
// Строки интерфейса из файлов assets/l10n/<код>.xml (1.7.3, решение
// владельца 25.10.2026: все переводы — в одном виде, файлами XML с одними
// и теми же ключами для всех языков).
//
// Формат — ресурсы строк Android (strings.xml): <string name>, <plurals
// name> с <item quantity>. Экранирование — как в Android (\' \" \n \t \\,
// пробелы по краям — в кавычках "…"). Править файлы — tool/l10n/l10n.py
// (tool/dev/l10n_set.py).
//
// Язык загружается при выборе (делегат локализации, запуск приложения,
// фоновые задачи — AppLocalizations.load); английский — всегда: им
// подменяется строка, которой в языке нет.

import 'package:flutter/services.dart' show rootBundle;

/// Язык интерфейса (список — languages.g.dart, создаётся по файлам XML).
class AppLanguage {
  final String code;

  /// Название на самом языке («Русский», «Deutsch», «日本語»).
  final String name;

  /// Название по-английски.
  final String english;

  /// Письмо справа налево (арабский, иврит, персидский, урду).
  final bool rtl;

  /// Перевод выполнен автоматически (не ru/en/de/fr).
  final bool machine;

  /// Формы множественного числа (категории CLDR) в файле языка.
  final List<String> plural;

  const AppLanguage(this.code, this.name, this.english,
      {this.rtl = false, this.machine = false, this.plural = const ['one', 'other']});
}

/// Строки одного языка.
class LangStrings {
  final Map<String, String> strings;
  final Map<String, Map<String, String>> plurals;
  const LangStrings(this.strings, this.plurals);
  static const empty = LangStrings({}, {});
}

abstract final class StringsStore {
  static final Map<String, LangStrings> _langs = {};
  static final Map<String, Future<void>> _loading = {};

  static bool isLoaded(String code) => _langs.containsKey(code);

  /// Загрузить язык из assets/l10n/<код>.xml (повторно — сразу).
  static Future<void> ensure(String code) {
    if (_langs.containsKey(code)) return Future.value();
    return _loading[code] ??= () async {
      try {
        // cache: false — текст файла нужен один раз, держит память разбор.
        final xml = await rootBundle.loadString('assets/l10n/$code.xml', cache: false);
        _langs[code] = parse(xml);
      } catch (_) {
        // Нет файла языка — строки возьмутся из английского.
        _langs[code] = LangStrings.empty;
      } finally {
        _loading.removeWhere((k, _) => k == code);
      }
    }();
  }

  /// Положить язык из текста XML (тесты, фоновая работа без rootBundle).
  static void put(String code, String xml) => _langs[code] = parse(xml);

  static String? get(String code, String key) => _langs[code]?.strings[key];

  static Map<String, String>? plurals(String code, String key) => _langs[code]?.plurals[key];

  // ─────────────────────────── разбор XML ───────────────────────────

  static final _comment = RegExp(r'<!--[\s\S]*?-->');
  static final _element =
      RegExp(r'<(string|plurals)\s+name="([^"]+)"[^>]*?(?:/>|>([\s\S]*?)</(?:string|plurals)>)');
  static final _item = RegExp(r'<item\s+quantity="([a-z]+)"[^>]*>([\s\S]*?)</item>');
  static final _entity = RegExp(r'&(#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos);');

  static LangStrings parse(String xml) {
    final text = xml.replaceAll(_comment, '');
    final strings = <String, String>{};
    final plurals = <String, Map<String, String>>{};
    for (final m in _element.allMatches(text)) {
      final name = m.group(2)!;
      final body = m.group(3) ?? '';
      if (m.group(1) == 'string') {
        strings[name] = value(body);
      } else {
        final forms = <String, String>{};
        for (final it in _item.allMatches(body)) {
          forms[it.group(1)!] = value(it.group(2)!);
        }
        if (forms.isNotEmpty) plurals[name] = forms;
      }
    }
    return LangStrings(strings, plurals);
  }

  /// Текст элемента → строка: сущности XML, затем экранирование Android.
  static String value(String raw) {
    var s = raw;
    if (s.contains('<![CDATA[')) {
      s = s.replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m.group(1)!);
    }
    if (s.contains('&')) {
      s = s.replaceAllMapped(_entity, (m) {
        final e = m.group(1)!;
        switch (e) {
          case 'amp':
            return '&';
          case 'lt':
            return '<';
          case 'gt':
            return '>';
          case 'quot':
            return '"';
          case 'apos':
            return "'";
        }
        final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code == null ? m.group(0)! : String.fromCharCode(code);
      });
    }
    return unescapeAndroid(s);
  }

  /// Как Android читает строку ресурса: «\» экранирует знак (\n, \t, \',
  /// \", \\, \uXXXX); "…" сохраняет пробелы; вне кавычек пробелы и
  /// переводы строк схлопываются в один пробел, края обрезаются.
  static String unescapeAndroid(String s) {
    if (!s.contains('\\') && !s.contains('"') && !s.contains('  ') && !s.contains('\n') && s.trim() == s) {
      return s;
    }
    final out = StringBuffer();
    var quoted = false;
    var lead = true;
    var lastSpace = false;
    var i = 0;
    final n = s.length;
    while (i < n) {
      final c = s[i];
      if (c == '\\' && i + 1 < n) {
        final d = s[i + 1];
        if (d == 'n') {
          out.write('\n');
        } else if (d == 't') {
          out.write('\t');
        } else if (d == 'u' && i + 5 < n) {
          final code = int.tryParse(s.substring(i + 2, i + 6), radix: 16);
          if (code != null) {
            out.writeCharCode(code);
            i += 6;
            lead = false;
            lastSpace = false;
            continue;
          }
          out.write(d);
        } else {
          out.write(d);
        }
        i += 2;
        lead = false;
        lastSpace = false;
        continue;
      }
      if (c == '"') {
        quoted = !quoted;
        i++;
        continue;
      }
      if (!quoted && (c == ' ' || c == '\t' || c == '\n' || c == '\r')) {
        if (!lead && !lastSpace) {
          out.write(' ');
          lastSpace = true;
        }
        i++;
        continue;
      }
      out.write(c);
      lead = false;
      lastSpace = false;
      i++;
    }
    var r = out.toString();
    // Пробел от схлопывания в конце (вне кавычек) — обрезать.
    if (lastSpace) r = r.substring(0, r.length - 1);
    return r;
  }

  // ─────────────────────────── множественное число ───────────────────────────

  /// Категория CLDR для целого [n] в языке [lang].
  static String pluralCategory(String lang, int count) {
    final n = count.abs();
    final n10 = n % 10;
    final n100 = n % 100;
    switch (lang) {
      case 'ru':
      case 'uk':
        if (n10 == 1 && n100 != 11) return 'one';
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'few';
        return 'many';
      case 'pl':
        if (n == 1) return 'one';
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'few';
        return 'many';
      case 'hr':
        if (n10 == 1 && n100 != 11) return 'one';
        if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return 'few';
        return 'other';
      case 'cs':
      case 'sk':
        if (n == 1) return 'one';
        if (n >= 2 && n <= 4) return 'few';
        return 'other';
      case 'lt':
        if (n10 == 1 && (n100 < 11 || n100 > 19)) return 'one';
        if (n10 >= 2 && (n100 < 11 || n100 > 19)) return 'few';
        return 'other';
      case 'lv':
        if (n10 == 0 || (n100 >= 11 && n100 <= 19)) return 'zero';
        if (n10 == 1 && n100 != 11) return 'one';
        return 'other';
      case 'ro':
        if (n == 1) return 'one';
        if (n == 0 || (n100 >= 1 && n100 <= 19)) return 'few';
        return 'other';
      case 'sl':
        if (n100 == 1) return 'one';
        if (n100 == 2) return 'two';
        if (n100 == 3 || n100 == 4) return 'few';
        return 'other';
      case 'he':
        if (n == 1) return 'one';
        if (n == 2) return 'two';
        return 'other';
      case 'ar':
        if (n == 0) return 'zero';
        if (n == 1) return 'one';
        if (n == 2) return 'two';
        if (n100 >= 3 && n100 <= 10) return 'few';
        if (n100 >= 11 && n100 <= 99) return 'many';
        return 'other';
      case 'is':
        return n10 == 1 && n100 != 11 ? 'one' : 'other';
      // «Один» — и для нуля.
      case 'fr':
      case 'pt':
      case 'hi':
      case 'bn':
      case 'gu':
      case 'kn':
      case 'fa':
      case 'zu':
      case 'pa':
        return n == 0 || n == 1 ? 'one' : 'other';
      // Без форм множественного числа.
      case 'ja':
      case 'ko':
      case 'zh':
      case 'th':
      case 'vi':
      case 'id':
        return 'other';
      default:
        return n == 1 ? 'one' : 'other';
    }
  }

  /// Форма для [n] из форм [forms] языка [lang]; нет нужной — «other».
  static String pick(String lang, Map<String, String> forms, int n) =>
      forms[pluralCategory(lang, n)] ?? forms['other'] ?? forms.values.first;
}

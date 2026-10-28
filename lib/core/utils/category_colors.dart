// lib/core/utils/category_colors.dart
// Цвет категории Outlook для календаря (замечание 10.10.2026: «цветовые
// категории сервера тоже учитывать»).
//
// Сам цвет категории хранится в «главном списке категорий» ящика, а
// ActiveSync отдаёт только название. Стандартные категории Outlook
// называются по цвету («Красная категория», «Red category», «Kategorie
// Rot»…) — цвет берём из названия. Своим категориям («Проект Н-102»)
// назначается постоянный цвет из спокойной палитры по хешу названия:
// одна категория всегда одного цвета.

import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryColors {
  CategoryColors._();

  // Спокойные оттенки (не кричащие, читаются в светлой и тёмной теме).
  static final _byWord = <(RegExp, Color)>[
    (RegExp(r'красн|\bred\b|\brot\b|\brouge\b', caseSensitive: false), const Color(0xFFC0504D)),
    (RegExp(r'оранж|\borange\b', caseSensitive: false), const Color(0xFFB8743A)),
    (RegExp(r'ж[её]лт|\byellow\b|\bgelb\b|\bjaune\b', caseSensitive: false), const Color(0xFF9E8530)),
    (RegExp(r'зел[её]н|\bgreen\b|\bgr[üu]n\b|\bvert\b', caseSensitive: false), const Color(0xFF5B8C5A)),
    (RegExp(r'син[яиеюй]|голуб|\bblue\b|\bblau\b|\bbleu\b', caseSensitive: false), const Color(0xFF4A78B0)),
    (RegExp(r'фиолет|лилов|пурпур|\bpurple\b|\bviolet\b|\blila\b', caseSensitive: false), const Color(0xFF7E5E9E)),
  ];

  static const _palette = <Color>[
    Color(0xFF4A78B0), Color(0xFF5B8C5A), Color(0xFFB0703F), Color(0xFF7E5E9E),
    Color(0xFF3F8A8C), Color(0xFFA35D6A), Color(0xFF6B7A3A), Color(0xFF5C6BA8),
  ];

  // ── Главный список категорий ящика (1.6.5) ──
  // Exchange хранит его в скрытой настройке календаря CategoryList (EWS
  // GetUserConfiguration): имя и номер цвета Outlook. Берётся при
  // синхронизации календаря ящиков с EWS — тогда цвет встречи совпадает с
  // Outlook, а в окне встречи — те же категории, что в Outlook
  // («Лиловая категория», свои — «Праздники»).

  static const _prefKey = 'cat_master_v1';
  static List<({String name, Color color})> serverList = const [];
  static Map<String, Color> _server = const {};

  /// Цвета Outlook по номеру (OlCategoryColor 0–24), чуть спокойнее оригинала.
  static const _outlook = <Color>[
    Color(0xFFD9535F), Color(0xFFE07B39), Color(0xFFC9963A), Color(0xFFD9B23A), Color(0xFF3C9A5F),
    Color(0xFF2FA5A5), Color(0xFF8A9A4E), Color(0xFF3D7CC9), Color(0xFF8467C2), Color(0xFFB85A9E),
    Color(0xFF7A8A90), Color(0xFF55626C), Color(0xFFA0A0A0), Color(0xFF6B6B6B), Color(0xFF3B3B3B),
    Color(0xFFA4262C), Color(0xFFCA5010), Color(0xFF8E562E), Color(0xFFC19C00), Color(0xFF0B6A0B),
    Color(0xFF005B70), Color(0xFF5B6B2F), Color(0xFF004E8C), Color(0xFF5C2E91), Color(0xFF881798),
  ];

  /// Цвет Outlook по номеру; вне диапазона (−1 — «без цвета») — null.
  static Color? outlookColor(int index) =>
      index >= 0 && index < _outlook.length ? _outlook[index] : null;

  static void _apply(List<({String name, Color color})> list) {
    serverList = List.unmodifiable(list);
    _server = {for (final c in list) c.name.trim().toLowerCase(): c.color};
  }

  /// Прочитать сохранённый список (при запуске, в каждом изоляте).
  static void load(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_prefKey);
      if (raw == null) return;
      final list = <({String name, Color color})>[];
      for (final m in (jsonDecode(raw) as List).whereType<Map>()) {
        final name = (m['n'] as String? ?? '').trim();
        final c = outlookColor((m['c'] as num?)?.toInt() ?? -1);
        if (name.isNotEmpty && c != null) list.add((name: name, color: c));
      }
      _apply(list);
    } catch (_) {}
  }

  /// Сохранить список с сервера: пары «имя — номер цвета Outlook».
  static Future<void> save(SharedPreferences prefs, List<({String name, int color})> raw) async {
    final kept = [for (final r in raw) if (r.name.trim().isNotEmpty && outlookColor(r.color) != null) r];
    _apply([for (final r in kept) (name: r.name.trim(), color: outlookColor(r.color)!)]);
    await prefs.setString(_prefKey, jsonEncode([for (final r in kept) {'n': r.name.trim(), 'c': r.color}]));
  }

  /// Цвет первой категории из списка; null — категорий нет.
  static Color? of(Iterable<String> categories) {
    for (final c in categories) {
      final name = c.trim();
      if (name.isEmpty) continue;
      final fromServer = _server[name.toLowerCase()];
      if (fromServer != null) return fromServer;
      for (final (re, color) in _byWord) {
        if (re.hasMatch(name)) return color;
      }
      var h = 0;
      for (final u in name.toLowerCase().codeUnits) {
        h = (h * 31 + u) & 0x7fffffff;
      }
      return _palette[h % _palette.length];
    }
    return null;
  }

  /// То же — значением ARGB для базы (CalendarEvents.colorValue).
  static int? valueOf(Iterable<String> categories) => of(categories)?.toARGB32();

  /// Стандартные цветные категории Outlook (1.6.4): цвет встречи, выбранный
  /// в приложении, уходит на сервер категорией — у Exchange нет «цвета
  /// встречи», Outlook и другие клиенты красят встречу цветом её категории.
  /// Цвета — те же, что [of] даёт этим названиям при синхронизации, поэтому
  /// выбранный кружок остаётся выбранным и после неё.
  static const presets = <({Color color, String ru, String en})>[
    (color: Color(0xFFC0504D), ru: 'Красная категория', en: 'Red category'),
    (color: Color(0xFFB8743A), ru: 'Оранжевая категория', en: 'Orange category'),
    (color: Color(0xFF9E8530), ru: 'Желтая категория', en: 'Yellow category'),
    (color: Color(0xFF5B8C5A), ru: 'Зеленая категория', en: 'Green category'),
    (color: Color(0xFF4A78B0), ru: 'Синяя категория', en: 'Blue category'),
    (color: Color(0xFF7E5E9E), ru: 'Лиловая категория', en: 'Purple category'),
  ];

  /// Название категории для цвета [argb] (точное совпадение с [presets]);
  /// null — цвет по умолчанию, без категории. [russian] — язык ящика:
  /// названия стандартных категорий в Exchange локализованы.
  static String? categoryFor(int? argb, {required bool russian}) {
    if (argb == null) return null;
    // Категории ящика — первыми: у них настоящие имена и цвета Outlook.
    for (final c in serverList) {
      if (c.color.toARGB32() == argb) return c.name;
    }
    for (final p in presets) {
      if (p.color.toARGB32() == argb) return russian ? p.ru : p.en;
    }
    return null;
  }
}

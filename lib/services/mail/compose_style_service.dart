// lib/services/mail/compose_style_service.dart
// Стиль текста писем (шрифт и размер) — у каждого аккаунта свой, без
// выбора — стиль по умолчанию. На телефоне шрифты по ходу письма почти не
// выбирают: стиль задаётся один раз в настройках аккаунта, редактор и
// отправленное письмо используют его.

import 'dart:convert';

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers/shared_prefs_provider.dart';

class ComposeStyle {
  /// Ключ шрифта из [fonts].
  final String font;

  /// Размер в пунктах (как в Outlook).
  final int sizePt;

  const ComposeStyle({this.font = 'Calibri', this.sizePt = 11});

  /// Стиль по умолчанию — как у Outlook: Calibri 11.
  static const fallback = ComposeStyle();

  /// Шрифты: ключ → CSS-семейство с запасными вариантами (у получателя
  /// может не оказаться выбранного шрифта).
  static const fonts = <String, String>{
    'Calibri': 'Calibri, Carlito, Arial, sans-serif',
    'Arial': 'Arial, Helvetica, sans-serif',
    'Segoe UI': '"Segoe UI", Roboto, Arial, sans-serif',
    'Verdana': 'Verdana, Geneva, sans-serif',
    'Tahoma': 'Tahoma, Verdana, sans-serif',
    'Times New Roman': '"Times New Roman", Times, serif',
    'Georgia': 'Georgia, serif',
  };

  static const sizes = [10, 11, 12, 14];

  String get family => fonts[font] ?? fonts['Calibri']!;

  /// CSS для тела письма.
  String get css => 'font-family:$family;font-size:${sizePt}pt';

  String get label => '$font, $sizePt';

  Map<String, Object> toJson() => {'font': font, 'size': sizePt};

  factory ComposeStyle.fromJson(Map<String, dynamic> m) => ComposeStyle(
        font: fonts.containsKey(m['font']) ? m['font'] as String : 'Calibri',
        sizePt: (m['size'] as num?)?.toInt() ?? 11,
      );

  @override
  bool operator ==(Object other) =>
      other is ComposeStyle && other.font == font && other.sizePt == sizePt;

  @override
  int get hashCode => Object.hash(font, sizePt);
}

/// Стили по аккаунтам: id аккаунта → стиль. Нет записи — [ComposeStyle.fallback].
final composeStylesProvider =
    StateNotifierProvider<ComposeStylesNotifier, Map<String, ComposeStyle>>((ref) {
  return ComposeStylesNotifier(ref.watch(sharedPrefsProvider));
});

class ComposeStylesNotifier extends StateNotifier<Map<String, ComposeStyle>> {
  final SharedPreferences _prefs;
  static const _key = 'compose_styles';

  ComposeStylesNotifier(this._prefs) : super(const {}) {
    try {
      final raw = _prefs.getString(_key);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        state = {
          for (final e in m.entries)
            e.key: ComposeStyle.fromJson(Map<String, dynamic>.from(e.value as Map)),
        };
      }
    } catch (_) {}
  }

  static ComposeStyle styleFor(Map<String, ComposeStyle> all, String? accountId) =>
      (accountId == null ? null : all[accountId]) ?? ComposeStyle.fallback;

  /// [style] null — вернуть стиль по умолчанию.
  Future<void> set(String accountId, ComposeStyle? style) async {
    final next = Map<String, ComposeStyle>.of(state);
    if (style == null || style == ComposeStyle.fallback) {
      next.remove(accountId);
    } else {
      next[accountId] = style;
    }
    state = next;
    await _prefs.setString(
        _key, jsonEncode({for (final e in next.entries) e.key: e.value.toJson()}));
  }
}

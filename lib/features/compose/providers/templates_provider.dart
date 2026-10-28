// lib/features/compose/providers/templates_provider.dart
// Подпись с динамическими полями и шаблоны ответов. Хранятся в SharedPreferences
// (без миграции БД). Подстановка полей: {имя}/{name}, {email}, {телефон}/{phone},
// {дата}/{date}, {время}/{time}, {фамилия-имя}/{fullname}.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

/// Подставить динамические поля в текст подписи/шаблона.
String applyPlaceholders(String text, {String? name, String? email, String? phone}) {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final date = '${two(now.day)}.${two(now.month)}.${now.year}';
  final time = '${two(now.hour)}:${two(now.minute)}';
  final map = <String, String>{
    'имя': name ?? '', 'name': name ?? '',
    'email': email ?? '', 'почта': email ?? '',
    'телефон': phone ?? '', 'phone': phone ?? '',
    'дата': date, 'date': date,
    'время': time, 'time': time,
    'fullname': name ?? '', 'фио': name ?? '',
  };
  var out = text;
  map.forEach((k, v) {
    out = out.replaceAll('{$k}', v);
  });
  return out;
}

// ───────────────────────── Подпись ─────────────────────────

class SignatureSettings {
  final bool enabled;
  final String template; // может содержать плейсхолдеры
  final String phone; // источник для {телефон}
  const SignatureSettings({this.enabled = true, this.template = '', this.phone = ''});

  SignatureSettings copyWith({bool? enabled, String? template, String? phone}) => SignatureSettings(
        enabled: enabled ?? this.enabled,
        template: template ?? this.template,
        phone: phone ?? this.phone,
      );
}

class SignatureNotifier extends StateNotifier<SignatureSettings> {
  final SharedPreferences _p;
  SignatureNotifier(this._p) : super(_load(_p));

  static SignatureSettings _load(SharedPreferences p) => SignatureSettings(
        enabled: p.getBool('sig_enabled') ?? true,
        template: p.getString('sig_template') ?? '',
        phone: p.getString('sig_phone') ?? '',
      );

  Future<void> setTemplate(String t) async {
    state = state.copyWith(template: t);
    await _p.setString('sig_template', t);
  }

  Future<void> setPhone(String v) async {
    state = state.copyWith(phone: v);
    await _p.setString('sig_phone', v);
  }

  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v);
    await _p.setBool('sig_enabled', v);
  }

  /// Готовый текст подписи с подставленными полями (или пусто).
  String render({String? name, String? email}) {
    if (!state.enabled || state.template.trim().isEmpty) return '';
    return applyPlaceholders(state.template, name: name, email: email, phone: state.phone);
  }
}

final signatureProvider = StateNotifierProvider<SignatureNotifier, SignatureSettings>((ref) {
  return SignatureNotifier(ref.watch(sharedPrefsProvider));
});

// ───────────────────────── Шаблоны ответов ─────────────────────────

/// Готовые шаблоны (1.8.0+118, просьба владельца 27.10.2026): тексты — в
/// `assets/l10n` (`<id>T` — название, `<id>B` — текст), на языке приложения.
/// Добавляются один раз; их можно изменить (становятся своими) и удалить.
const builtInTemplateIds = [
  'tmplFyi', 'tmplTakeOn', 'tmplMeeting', 'tmplNote', 'tmplApprove', 'tmplReview', 'tmplReceived',
];

@immutable
class ReplyTemplate {
  final String title;
  final String body;

  /// Готовый шаблон: id из [builtInTemplateIds], текст — из перевода.
  final String? builtIn;
  const ReplyTemplate({required this.title, required this.body, this.builtIn});

  /// Название и текст на языке приложения ([tr] — `l10n.tr`).
  ReplyTemplate resolve(String Function(String key) tr) =>
      builtIn == null ? this : ReplyTemplate(title: tr('${builtIn}T'), body: tr('${builtIn}B'), builtIn: builtIn);

  Map<String, dynamic> toJson() => builtIn != null ? {'builtIn': builtIn} : {'title': title, 'body': body};
  factory ReplyTemplate.fromJson(Map<String, dynamic> j) {
    final b = j['builtIn']?.toString();
    if (b != null && builtInTemplateIds.contains(b)) return ReplyTemplate(title: '', body: '', builtIn: b);
    return ReplyTemplate(title: j['title']?.toString() ?? '', body: j['body']?.toString() ?? '');
  }
}

class TemplatesNotifier extends StateNotifier<List<ReplyTemplate>> {
  final SharedPreferences _p;
  static const _key = 'reply_templates_v1';
  static const _seededKey = 'reply_templates_builtin_v1';
  TemplatesNotifier(this._p) : super(_load(_p)) {
    // Готовые шаблоны — один раз, после своих: удалённые не возвращаются.
    if (_p.getBool(_seededKey) != true) {
      final have = {for (final t in state) t.builtIn};
      state = [
        ...state,
        for (final id in builtInTemplateIds)
          if (!have.contains(id)) ReplyTemplate(title: '', body: '', builtIn: id),
      ];
      unawaited(_persist().then((_) => _p.setBool(_seededKey, true)));
    }
  }

  static List<ReplyTemplate> _load(SharedPreferences p) {
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ReplyTemplate.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist() async =>
      _p.setString(_key, jsonEncode(state.map((t) => t.toJson()).toList()));

  Future<void> add(ReplyTemplate t) async {
    state = [...state, t];
    await _persist();
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= state.length) return;
    final copy = [...state]..removeAt(i);
    state = copy;
    await _persist();
  }

  Future<void> update(int i, ReplyTemplate t) async {
    if (i < 0 || i >= state.length) return;
    final copy = [...state];
    copy[i] = t;
    state = copy;
    await _persist();
  }
}

final templatesProvider =
    StateNotifierProvider<TemplatesNotifier, List<ReplyTemplate>>((ref) {
  return TemplatesNotifier(ref.watch(sharedPrefsProvider));
});

// lib/services/mail/signature_service.dart
// Менеджер подписей. Несколько подписей с привязкой к аккаунтам,
// HTML-подписи, шаблоны (стандартная, краткая, формальная),
// автовставка по типу ответа (новое/ответ/пересылка).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'package:drift/drift.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import '../../l10n/app_language.dart';
import '../../l10n/strings_store.dart';

/// Провайдер сервиса подписей
final signatureServiceProvider = Provider<SignatureService>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return SignatureService(prefs);
});

/// Провайдер списка подписей
final signaturesProvider =
    StateNotifierProvider<SignaturesNotifier, List<SignatureModel>>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return SignaturesNotifier(ref.watch(databaseProvider), prefs);
});

/// Модель подписи
class SignatureModel {
  final String id;
  final String name;
  final String htmlContent;
  final String plainContent;
  final String? accountId; // null = для всех аккаунтов
  final bool isDefault;
  final bool useForNewEmails;
  final bool useForReplies;
  final bool useForForwards;

  const SignatureModel({
    required this.id,
    required this.name,
    required this.htmlContent,
    required this.plainContent,
    this.accountId,
    this.isDefault = false,
    this.useForNewEmails = true,
    this.useForReplies = true,
    this.useForForwards = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'htmlContent': htmlContent,
    'plainContent': plainContent,
    'accountId': accountId,
    'isDefault': isDefault,
    'useForNewEmails': useForNewEmails,
    'useForReplies': useForReplies,
    'useForForwards': useForForwards,
  };

  factory SignatureModel.fromMap(Map<String, dynamic> m) => SignatureModel(
    id: m['id'] as String,
    name: m['name'] as String,
    htmlContent: m['htmlContent'] as String,
    plainContent: m['plainContent'] as String,
    accountId: m['accountId'] as String?,
    isDefault: m['isDefault'] as bool? ?? false,
    useForNewEmails: m['useForNewEmails'] as bool? ?? true,
    useForReplies: m['useForReplies'] as bool? ?? true,
    useForForwards: m['useForForwards'] as bool? ?? false,
  );

  SignatureModel copyWith({
    String? name,
    String? htmlContent,
    String? plainContent,
    String? accountId,
    bool? isDefault,
    bool? useForNewEmails,
    bool? useForReplies,
    bool? useForForwards,
  }) => SignatureModel(
    id: id,
    name: name ?? this.name,
    htmlContent: htmlContent ?? this.htmlContent,
    plainContent: plainContent ?? this.plainContent,
    accountId: accountId ?? this.accountId,
    isDefault: isDefault ?? this.isDefault,
    useForNewEmails: useForNewEmails ?? this.useForNewEmails,
    useForReplies: useForReplies ?? this.useForReplies,
    useForForwards: useForForwards ?? this.useForForwards,
  );
}

class SignaturesNotifier extends StateNotifier<List<SignatureModel>> {
  final AppDatabase _db;
  final SharedPreferences _prefs; // нужен только для одноразового переноса
  /// Старое место хранения (SharedPreferences). Оставлен ради миграции.
  static const _legacyKey = 'signatures_list';

  SignaturesNotifier(this._db, this._prefs) : super([]) {
    _load();
  }

  Future<void> _load() async {
    await _migrateFromPrefsIfNeeded();
    final rows = await (_db.select(_db.signatures)
          ..orderBy([(s) => OrderingTerm(expression: s.sortOrder)]))
        .get();
    state = rows.map(_fromRow).toList();
    if (state.isEmpty) {
      await _createDefaults();
    }
  }

  /// Перенос подписей из SharedPreferences в БД (однократно, для существующих
  /// установок). Раньше подписи жили в prefs, хотя таблица signatures уже была —
  /// из-за этого удалённое стирание и удаление аккаунта чистили пустую таблицу,
  /// а сами подписи (ФИО, должность, телефон) оставались на устройстве.
  Future<void> _migrateFromPrefsIfNeeded() async {
    final json = _prefs.getString(_legacyKey);
    if (json == null) return;
    try {
      final list = jsonDecode(json) as List;
      final sigs = list
          .map((m) => SignatureModel.fromMap(m as Map<String, dynamic>))
          .toList();
      for (var i = 0; i < sigs.length; i++) {
        await _upsert(sigs[i], i);
      }
      AppLogger.info('Подписи перенесены в БД: ${sigs.length}');
    } catch (e) {
      AppLogger.error('Ошибка переноса подписей в БД', e);
    }
    // Убираем из prefs в любом случае: иначе персональные данные остаются
    // в незачищаемом хранилище.
    await _prefs.remove(_legacyKey);
  }

  SignatureModel _fromRow(Signature r) => SignatureModel(
        id: r.id,
        name: r.name,
        htmlContent: r.htmlContent,
        plainContent: r.plainContent,
        accountId: r.accountId,
        isDefault: r.isDefault,
        useForNewEmails: r.useForNewEmails,
        useForReplies: r.useForReplies,
        useForForwards: r.useForForwards,
      );

  Future<void> _upsert(SignatureModel s, int order) async {
    await _db.into(_db.signatures).insertOnConflictUpdate(
          SignaturesCompanion.insert(
            id: s.id,
            name: s.name,
            htmlContent: s.htmlContent,
            plainContent: s.plainContent,
            accountId: Value(s.accountId),
            isDefault: Value(s.isDefault),
            useForNewEmails: Value(s.useForNewEmails),
            useForReplies: Value(s.useForReplies),
            useForForwards: Value(s.useForForwards),
            sortOrder: Value(order),
          ),
        );
  }

  /// Подписи для первого запуска — на языке приложения (1.7.3; раньше —
  /// всегда по-русски: «С уважением», «Тел.:»). Строки — sig* в
  /// assets/l10n; язык приложения к этому моменту загружен (main.dart).
  /// Вторая подпись — английская, если приложение не на английском.
  Future<void> _createDefaults() async {
    final lang = SignatureService.appLanguage(_prefs);
    String t(String key, [String? l]) =>
        StringsStore.get(l ?? lang, key) ?? StringsStore.get('en', key) ?? '';
    String esc(String v) => const HtmlEscape(HtmlEscapeMode.element).convert(v);
    final regards = t('sigRegards'), tel = t('sigPhone'), mail = t('sigEmail');
    // «С уважением,» — имя в той же строке краткой подписи; «Mit
    // freundlichen Grüßen» (без запятой) — имя строкой ниже.
    final oneLine = regards.trimRight().endsWith(',');
    final enRegards = t('sigRegards', 'en');
    state = [
      SignatureModel(
        id: 'sig_standard',
        name: t('sigNameStandard'),
        htmlContent: '<div style="margin-top:20px;">\n'
            '<p>${esc(regards)}<br><b>{name}</b></p>\n'
            '<p>{title}<br>{company}<br>${esc(tel)} {phone}<br>${esc(mail)} {email}</p></div>',
        plainContent: '$regards\n{name}\n{title}\n{company}\n$tel {phone}\n$mail {email}',
        isDefault: true,
      ),
      SignatureModel(
        id: 'sig_short',
        name: t('sigNameShort'),
        htmlContent: '<div style="margin-top:16px;">${esc(regards)}${oneLine ? ' ' : '<br>'}{name}</div>',
        plainContent: '$regards${oneLine ? ' ' : '\n'}{name}',
      ),
      SignatureModel(
        id: 'sig_formal',
        name: t('sigNameFormal'),
        htmlContent: '<div style="margin-top:20px;border-top:1px solid #ddd;padding-top:10px;">\n'
            '<p>${esc(regards)}</p>\n'
            '<p><b>{name}</b><br>\n{title}<br>\n{department}<br>\n{company}</p>\n'
            '<p>📞 {phone}<br>\n✉️ {email}</p></div>',
        plainContent: '$regards\n{name}\n{title}\n{department}\n{company}\n$tel {phone}\n$mail {email}',
      ),
      if (lang != 'en' && enRegards.isNotEmpty)
        SignatureModel(
          id: 'sig_en',
          name: 'English',
          htmlContent: '<div style="margin-top:16px;">${esc(enRegards)}<br>{name}</div>',
          plainContent: '$enRegards\n{name}',
        ),
    ];
    await _save();
  }

  /// Сохраняем состояние в БД: upsert текущих + удаление исчезнувших.
  Future<void> _save() async {
    for (var i = 0; i < state.length; i++) {
      await _upsert(state[i], i);
    }
    final ids = state.map((s) => s.id).toList();
    await (_db.delete(_db.signatures)..where((t) => t.id.isNotIn(ids))).go();
  }

  Future<void> addSignature(SignatureModel sig) async {
    state = [...state, sig];
    await _save();
  }

  Future<void> updateSignature(SignatureModel sig) async {
    state = state.map((s) => s.id == sig.id ? sig : s).toList();
    await _save();
  }

  Future<void> deleteSignature(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _save();
  }

  Future<void> setDefault(String id) async {
    state = state.map((s) => s.copyWith(isDefault: s.id == id)).toList();
    await _save();
  }
}

/// Сервис подписей
class SignatureService {
  // ignore: unused_field
  final SharedPreferences _prefs;

  SignatureService(this._prefs);

  /// Язык приложения (настройка, иначе системный, иначе английский).
  static String appLanguage(SharedPreferences prefs) => appLanguageOf(prefs);

  /// Подпись ящика для ответа без редактора (ответ из шторки уведомления):
  /// та, что выбрана для ответов на экране «Подписи», с подставленными
  /// полями из карточки владельца. HTML; null — у ящика нет подписи.
  /// Работает и в фоновом изоляте: читает базу и настройки напрямую.
  static Future<String?> replySignatureHtml(AppDatabase db, SharedPreferences prefs, AccountModel acc) async {
    try {
      final rows = await (db.select(db.signatures)..orderBy([(s) => OrderingTerm(expression: s.sortOrder)])).get();
      final all = [
        for (final r in rows)
          SignatureModel(
            id: r.id,
            name: r.name,
            htmlContent: r.htmlContent,
            plainContent: r.plainContent,
            accountId: r.accountId,
            isDefault: r.isDefault,
            useForNewEmails: r.useForNewEmails,
            useForReplies: r.useForReplies,
            useForForwards: r.useForForwards,
          ),
      ];
      Map<String, String> choices = const {};
      try {
        final raw = prefs.getString('signature_choices');
        if (raw != null) choices = Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {}
      final sig = SignatureChoicesNotifier.resolve(all, choices, acc.id, reply: true);
      if (sig == null) return null;
      var html = sig.htmlContent.trim().isNotEmpty
          ? sig.htmlContent
          : const HtmlEscape().convert(sig.plainContent).replaceAll('\n', '<br>');
      if (html.trim().isEmpty) return null;
      Map<String, String> card = const {};
      try {
        final raw = prefs.getString('selfcard_${acc.id}');
        if (raw != null) card = Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {}
      final own = acc.displayName.trim();
      final ownIsReal = own.isNotEmpty &&
          own.toLowerCase() != acc.email.toLowerCase() &&
          own.toLowerCase() != acc.email.split('@').first.toLowerCase();
      final values = <String, String>{
        'name': ownIsReal ? own : (card['name'] ?? own),
        'title': card['title'] ?? '',
        'department': card['office'] ?? '',
        'company': card['company'] ?? '',
        'phone': card['phone'] ?? card['mobile'] ?? '',
        'email': acc.email,
      };
      values.forEach((k, v) => html = html.replaceAll('{$k}', const HtmlEscape().convert(v)));
      html = html
          .replaceAll(RegExp(r'\{[a-zA-Zа-яА-Я_]+\}'), '')
          .replaceAll(RegExp(r'color:\s*#666;?\s*font-size:\s*12px;?\s*'), '')
          .replaceAll(RegExp(r'(<br\s*/?>\s*){3,}', caseSensitive: false), '<br><br>');
      return html;
    } catch (e) {
      AppLogger.warning('Подпись для ответа из уведомления: $e');
      return null;
    }
  }

  /// Получить подходящую подпись для письма
  /// [accountId] — аккаунт отправки
  /// [isReply] — это ответ
  /// [isForward] — это пересылка
  SignatureModel? getSignatureFor({
    required String accountId,
    required List<SignatureModel> signatures,
    bool isReply = false,
    bool isForward = false,
  }) {
    // Ищем подпись привязанную к аккаунту
    final accountSigs = signatures.where((s) =>
        s.accountId == accountId ||
        s.accountId == null);

    for (final sig in accountSigs) {
      if (isForward && sig.useForForwards) return sig;
      if (isReply && sig.useForReplies) return sig;
      if (!isReply && !isForward && sig.useForNewEmails) return sig;
    }

    // Fallback: дефолтная. `.first` на ПУСТОМ списке бросил бы StateError —
    // метод возвращает nullable, поэтому корректнее отдать null.
    if (signatures.isEmpty) return null;
    return signatures.firstWhere(
      (s) => s.isDefault,
      orElse: () => signatures.first,
    );
  }

  /// Подставить переменные в подпись
  String renderSignature(
    SignatureModel signature, {
    required String name,
    String? title,
    String? department,
    String? company,
    String? phone,
    required String email,
    bool html = true,
  }) {
    var content = html ? signature.htmlContent : signature.plainContent;
    content = content
        .replaceAll('{name}', name)
        .replaceAll('{title}', title ?? '')
        .replaceAll('{department}', department ?? '')
        .replaceAll('{company}', company ?? '')
        .replaceAll('{phone}', phone ?? '')
        .replaceAll('{email}', email);
    return content;
  }
}

/// Какая подпись вставляется у аккаунта: отдельно для новых писем и для
/// ответов/пересылки (как в Outlook). Ключ — «<аккаунт>|new» / «<аккаунт>|reply»,
/// значение — id подписи или '' («без подписи»). Нет ключа — подпись по
/// умолчанию.
final signatureChoicesProvider =
    StateNotifierProvider<SignatureChoicesNotifier, Map<String, String>>((ref) {
  return SignatureChoicesNotifier(ref.watch(sharedPrefsProvider));
});

class SignatureChoicesNotifier extends StateNotifier<Map<String, String>> {
  final SharedPreferences _prefs;
  static const _key = 'signature_choices';

  SignatureChoicesNotifier(this._prefs) : super(const {}) {
    try {
      final raw = _prefs.getString(_key);
      if (raw != null) {
        state = Map<String, String>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
  }

  static String keyFor(String accountId, {required bool reply}) =>
      '$accountId|${reply ? 'reply' : 'new'}';

  /// [signatureId]: id подписи, '' — без подписи, null — по умолчанию.
  Future<void> set(String accountId, {required bool reply, String? signatureId}) async {
    final next = Map<String, String>.of(state);
    final k = keyFor(accountId, reply: reply);
    if (signatureId == null) {
      next.remove(k);
    } else {
      next[k] = signatureId;
    }
    state = next;
    await _prefs.setString(_key, jsonEncode(next));
  }

  /// Подписи, которые видны аккаунту: общие и его собственные.
  static List<SignatureModel> forAccount(List<SignatureModel> all, String accountId) =>
      [for (final s in all) if (s.accountId == null || s.accountId == accountId) s];

  /// Подпись для письма. Нет выбора — подпись по умолчанию: своя у аккаунта,
  /// затем общая (раньше в ответы и пересылку подпись не вставлялась вовсе).
  static SignatureModel? resolve(List<SignatureModel> all, Map<String, String> choices,
      String accountId, {required bool reply}) {
    final mine = forAccount(all, accountId);
    final chosen = choices[keyFor(accountId, reply: reply)];
    if (chosen != null) {
      if (chosen.isEmpty) return null;
      final s = mine.where((s) => s.id == chosen).firstOrNull;
      if (s != null) return s;
    }
    SignatureModel? pick(bool Function(SignatureModel) f) => mine.where(f).firstOrNull;
    return pick((s) => s.accountId == accountId && s.isDefault) ??
        pick((s) => s.accountId == accountId) ??
        pick((s) => s.isDefault) ??
        (mine.isEmpty ? null : mine.first);
  }
}

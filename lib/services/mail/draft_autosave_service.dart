// lib/services/mail/draft_autosave_service.dart
// Автосохранение черновиков:
// - Сохраняет каждые 30 секунд при изменении
// - При выходе из compose без отправки
// - Восстановление при повторном открытии
// - Хранение в локальной БД
//
// 1.7.0: черновик помнит, на какое письмо он отвечает (или что пересылает) —
// поле parent_id строки «r|ящик|id» / «f|ящик|id»: открытый из «Черновиков»
// ответ снова встаёт в цепочку (In-Reply-To), а исходное письмо после
// отправки получает отметку «Отвечено». [savedAt] — когда черновик последний
// раз записан (подпись «Сохранено · 06:41» в окне письма). Пустой снимок
// таймер больше не записывает (раньше стёртый до пустоты текст оставлял
// пустой черновик), а смена ящика «От» не оставляет копию под прежним ящиком.
//
// 1.7.2+111: черновик хранит и файлы письма ([DraftData.files], папка
// черновика — `DraftFiles`). Записи и удаления идут по одной: таймер и
// закрытие окна могли писать один черновик одновременно, а удаление после
// отправки — успеть раньше записи, и черновик «воскресал».

import 'package:drift/drift.dart' hide Column;
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import 'draft_files.dart';

final draftAutosaveProvider = Provider<DraftAutosaveService>((ref) {
  final db = ref.watch(databaseProvider);
  return DraftAutosaveService(db);
});

class DraftData {
  final String id;
  final String accountId;
  final List<Map<String, String>> to;
  final List<Map<String, String>> cc;
  final List<Map<String, String>> bcc;
  final String subject;
  final String body;
  final String? replyToId;
  final String? forwardFromId;
  /// Ящик исходного письма ответа или пересылки.
  final String? parentAccountId;
  /// Гриф и режимы обращения («Confidential|dsp|no-forward», MailLabel).
  final String? sensitivity;
  final DateTime savedAt;

  /// Файлы письма (1.7.2+111).
  final List<DraftFile> files;

  const DraftData({
    required this.id,
    required this.accountId,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.body = '',
    this.replyToId,
    this.forwardFromId,
    this.parentAccountId,
    this.sensitivity,
    required this.savedAt,
    this.files = const [],
  });

  /// Значение parent_id строки черновика: «r|ящик|id» — ответ, «f|ящик|id» —
  /// пересылка; null — новое письмо.
  String? get parentRef {
    final id = replyToId ?? forwardFromId;
    if (id == null || id.isEmpty) return null;
    return '${replyToId != null ? 'r' : 'f'}|${parentAccountId ?? accountId}|$id';
  }

  /// Разобрать parent_id строки черновика.
  static ({String accountId, String emailId, bool forward})? parseParentRef(String? ref) {
    if (ref == null) return null;
    final m = RegExp(r'^([rf])\|([^|]*)\|(.+)$').firstMatch(ref);
    if (m == null || m.group(2)!.isEmpty) return null;
    return (accountId: m.group(2)!, emailId: m.group(3)!, forward: m.group(1) == 'f');
  }

  Map<String, dynamic> toMap() => {
    'id': id, 'accountId': accountId,
    'to': to, 'cc': cc, 'bcc': bcc,
    'subject': subject, 'body': body,
    'replyToId': replyToId, 'forwardFromId': forwardFromId,
    'parentAccountId': parentAccountId,
    'sensitivity': sensitivity,
    'savedAt': savedAt.toIso8601String(),
  };

  factory DraftData.fromMap(Map<String, dynamic> m) => DraftData(
    id: m['id'] as String,
    accountId: m['accountId'] as String,
    to: (m['to'] as List?)?.map((e) => Map<String, String>.from(e as Map)).toList() ?? [],
    cc: (m['cc'] as List?)?.map((e) => Map<String, String>.from(e as Map)).toList() ?? [],
    bcc: (m['bcc'] as List?)?.map((e) => Map<String, String>.from(e as Map)).toList() ?? [],
    subject: m['subject'] as String? ?? '',
    body: m['body'] as String? ?? '',
    replyToId: m['replyToId'] as String?,
    forwardFromId: m['forwardFromId'] as String?,
    parentAccountId: m['parentAccountId'] as String?,
    sensitivity: m['sensitivity'] as String?,
    savedAt: DateTime.parse(m['savedAt'] as String),
  );

  bool get isEmpty => to.isEmpty && subject.isEmpty && body.isEmpty && files.isEmpty;
}

class DraftAutosaveService {
  final AppDatabase _db;
  Timer? _autosaveTimer;
  DraftData? _currentDraft;
  bool _hasChanges = false;

  static const _autosaveInterval = Duration(seconds: 30);

  /// Когда черновик открытого письма последний раз записан. null — ещё не
  /// записывался (или черновика нет).
  final ValueNotifier<DateTime?> savedAt = ValueNotifier(null);

  DraftAutosaveService(this._db);

  /// Есть изменения, ещё не записанные в базу.
  bool get hasUnsavedChanges => _hasChanges && !(_currentDraft?.isEmpty ?? true);

  /// Начать автосохранение для нового черновика
  void startAutosave(DraftData draft) {
    _currentDraft = draft;
    _hasChanges = false;
    savedAt.value = null;

    _autosaveTimer?.cancel();
    _autosaveTimer = Timer.periodic(_autosaveInterval, (_) {
      final d = _currentDraft;
      if (_hasChanges && d != null && !d.isEmpty) {
        unawaited(_saveDraft(d));
        _hasChanges = false;
      }
    });
  }

  /// Обновить данные черновика (вызывается при каждом изменении)
  void updateDraft(DraftData draft) {
    _currentDraft = draft;
    _hasChanges = true;
  }

  /// Принудительное сохранение (кнопка «Сохранить», выход). true — записан.
  /// Снимок берётся синхронно, до первого await.
  Future<bool> forceSave() async {
    final d = _currentDraft;
    if (d == null || d.isEmpty) return false;
    _hasChanges = false;
    return _saveDraft(d);
  }

  /// Записи и удаления черновиков — по одной.
  Future<void> _chain = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _chain.then((_) => action());
    _chain = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Записать черновик, не открытый в редакторе: неотправленное письмо из
  /// очереди → «Черновики» (1.7.2+114). true — записан.
  Future<bool> saveStandalone(DraftData draft) => _saveDraft(draft);

  /// Сохранить черновик в БД
  Future<bool> _saveDraft(DraftData draft) => _serial(() => _saveDraftNow(draft));

  Future<bool> _saveDraftNow(DraftData draft) async {
    try {
      // Файлы — в папку черновика. Не записались (нет места) — текст всё
      // равно сохраняется, список файлов остаётся прежним.
      String? filesJson;
      try {
        filesJson = await DraftFiles.store(draft.id, draft.files);
      } catch (e) {
        AppLogger.warning('Черновик: файлы не сохранены — $e');
      }
      // Сменили ящик «От» — копия под прежним ящиком больше не нужна (ключ
      // строки — id и ящик: иначе черновиков стало бы два).
      await (_db.delete(_db.emails)
            ..where((e) =>
                e.id.equals(draft.id) & e.folderId.equals('drafts') & e.accountId.equals(draft.accountId).not()))
          .go();
      await _db.into(_db.emails).insertOnConflictUpdate(
        EmailsCompanion.insert(
          id: draft.id,
          accountId: draft.accountId,
          folderId: 'drafts',
          folderName: const Value('Drafts'),
          fromEmail: '', // Будет заполнено при отправке
          toRecipients: jsonEncode(draft.to),
          ccJson: Value(draft.cc.isNotEmpty ? jsonEncode(draft.cc) : null),
          bccJson: Value(draft.bcc.isNotEmpty ? jsonEncode(draft.bcc) : null),
          subject: draft.subject,
          bodyPlain: Value(draft.body),
          bodyHtml: Value('<html><body>${draft.body.replaceAll('\n', '<br>')}</body></html>'),
          bodyPreview: Value(_preview(draft.body)),
          parentId: Value(draft.parentRef),
          receivedAt: draft.savedAt,
          sensitivity: Value(draft.sensitivity),
          attachmentsJson: filesJson == null ? const Value.absent() : Value(filesJson),
          hasAttachments: filesJson == null ? const Value.absent() : Value(draft.files.isNotEmpty),
          isDraft: const Value(true),
          status: const Value(0), // Draft status
          cachedAt: Value(DateTime.now()),
        ),
      );
      AppLogger.debug('Draft autosaved: ${draft.id}');
      // Отметка — только для письма, открытого сейчас (сохранение закрытого
      // окна могло закончиться уже после открытия следующего).
      if (_currentDraft?.id == draft.id) savedAt.value = DateTime.now();
      return true;
    } catch (e) {
      AppLogger.error('Draft autosave error', e);
      return false;
    }
  }

  /// Начало текста для строки «Черновики» (раньше превью у своего черновика
  /// было пустым).
  static String _preview(String body) {
    final t = body
        .replaceAll(RegExp(r'<(br|/p|/div)[^>]*>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length > 200 ? t.substring(0, 200) : t;
  }

  /// Получить все черновики
  Future<List<DraftData>> getDrafts(String accountId) async {
    final rows = await (_db.select(_db.emails)
          ..where((e) => e.accountId.equals(accountId))
          ..where((e) => e.isDraft.equals(true))
          ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)]))
        .get();

    return rows.map((r) {
      List<Map<String, String>> parseRecipients(String? json) {
        if (json == null) return [];
        try { return (jsonDecode(json) as List).map((e) => Map<String, String>.from(e as Map)).toList(); }
        catch (_) { return []; }
      }

      return DraftData(
        id: r.id,
        accountId: r.accountId,
        to: parseRecipients(r.toRecipients),
        cc: parseRecipients(r.ccJson),
        bcc: parseRecipients(r.bccJson),
        subject: r.subject,
        body: r.bodyPlain ?? '',
        savedAt: r.receivedAt,
      );
    }).toList();
  }

  /// Удалить черновик (после отправки или по «Удалить»). Свой черновик —
  /// под любым ящиком: «От» могли сменить после сохранения.
  Future<void> deleteDraft(String draftId, String accountId) {
    if (_currentDraft?.id == draftId) _hasChanges = false;
    return _serial(() async {
      await (_db.delete(_db.emails)
            ..where((e) => e.id.equals(draftId))
            ..where((e) => e.accountId.equals(accountId) | e.folderId.equals('drafts')))
          .go();
      await DraftFiles.remove(draftId);
    });
  }

  /// Остановить автосохранение
  void stopAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    _currentDraft = null;
    _hasChanges = false;
    savedAt.value = null;
  }

  void dispose() {
    _autosaveTimer?.cancel();
  }
}

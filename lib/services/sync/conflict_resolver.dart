// lib/services/sync/conflict_resolver.dart
// Разрешение конфликтов при офлайн-синхронизации:
// - Обнаружение конфликтов (одно письмо изменено и локально, и на сервере)
// - Стратегии: ServerWins, ClientWins, Merge, AskUser
// - Очередь конфликтов для пользователя
// - Автоматическое разрешение для простых случаев

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/email_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';

final conflictResolverProvider = Provider<ConflictResolver>((ref) {
  final db = ref.watch(databaseProvider);
  final prefs = ref.watch(sharedPrefsProvider);
  return ConflictResolver(db, prefs);
});

enum ConflictStrategy { serverWins, clientWins, merge, askUser }

class SyncConflict {
  final String emailId;
  final String accountId;
  final String field; // 'isRead', 'isFlagged', 'folderId', 'tags'
  final dynamic localValue;
  final dynamic serverValue;
  final DateTime detectedAt;
  final bool resolved;

  const SyncConflict({
    required this.emailId,
    required this.accountId,
    required this.field,
    required this.localValue,
    required this.serverValue,
    required this.detectedAt,
    this.resolved = false,
  });

  Map<String, dynamic> toMap() => {
    'emailId': emailId, 'accountId': accountId, 'field': field,
    'localValue': localValue?.toString(), 'serverValue': serverValue?.toString(),
    'detectedAt': detectedAt.toIso8601String(), 'resolved': resolved,
  };

  factory SyncConflict.fromMap(Map<String, dynamic> m) => SyncConflict(
    emailId: m['emailId'] ?? '', accountId: m['accountId'] ?? '', field: m['field'] ?? '',
    localValue: m['localValue'], serverValue: m['serverValue'],
    detectedAt: DateTime.tryParse(m['detectedAt'] ?? '') ?? DateTime.now(),
    resolved: m['resolved'] ?? false,
  );
}

class ConflictResolver {
  // ignore: unused_field
  final AppDatabase _db;
  final SharedPreferences _prefs;

  static const _strategyKey = 'conflict_strategy';
  static const _conflictsKey = 'sync_conflicts';

  ConflictResolver(this._db, this._prefs);

  /// Текущая стратегия. По умолчанию — merge: для почты это наименее
  /// неожиданное поведение (прочитано где-либо → прочитано, флаг где-либо →
  /// флаг, локальное перемещение приоритетно, теги объединяются). serverWins
  /// молча терял бы офлайн-правку пользователя при настоящем конфликте.
  ConflictStrategy get strategy {
    final idx = _prefs.getInt(_strategyKey) ?? ConflictStrategy.merge.index;
    return ConflictStrategy.values[idx.clamp(0, ConflictStrategy.values.length - 1)];
  }

  Future<void> setStrategy(ConflictStrategy s) async {
    await _prefs.setInt(_strategyKey, s.index);
  }

  /// Обнаружить конфликт между локальным и серверным письмом
  List<SyncConflict> detectConflicts(EmailModel local, EmailModel server) {
    final conflicts = <SyncConflict>[];

    if (!local.isLocallyModified) return conflicts; // Нет локальных изменений

    // isRead
    if (local.isRead != server.isRead) {
      conflicts.add(SyncConflict(
        emailId: local.id, accountId: local.accountId, field: 'isRead',
        localValue: local.isRead, serverValue: server.isRead, detectedAt: DateTime.now(),
      ));
    }

    // isFlagged
    if (local.isFlagged != server.isFlagged) {
      conflicts.add(SyncConflict(
        emailId: local.id, accountId: local.accountId, field: 'isFlagged',
        localValue: local.isFlagged, serverValue: server.isFlagged, detectedAt: DateTime.now(),
      ));
    }

    // folderId
    if (local.folderId != server.folderId) {
      conflicts.add(SyncConflict(
        emailId: local.id, accountId: local.accountId, field: 'folderId',
        localValue: local.folderId, serverValue: server.folderId, detectedAt: DateTime.now(),
      ));
    }

    // tags
    final localTags = local.tags.toSet();
    final serverTags = server.tags.toSet();
    if (!localTags.containsAll(serverTags) || !serverTags.containsAll(localTags)) {
      conflicts.add(SyncConflict(
        emailId: local.id, accountId: local.accountId, field: 'tags',
        localValue: local.tags.join(';'), serverValue: server.tags.join(';'), detectedAt: DateTime.now(),
      ));
    }

    return conflicts;
  }

  /// Разрешить конфликт автоматически
  EmailModel resolveConflict(SyncConflict conflict, EmailModel local, EmailModel server) {
    switch (strategy) {
      case ConflictStrategy.serverWins:
        AppLogger.info('Conflict resolved (server wins): ${conflict.field}');
        return server;

      case ConflictStrategy.clientWins:
        AppLogger.info('Conflict resolved (client wins): ${conflict.field}');
        return local;

      case ConflictStrategy.merge:
        return _mergeConflict(conflict, local, server);

      case ConflictStrategy.askUser:
        // Сохраняем конфликт для показа пользователю
        _saveConflict(conflict);
        // Пока возвращаем серверную версию
        return server;
    }
  }

  /// Merge — объединяем изменения
  EmailModel _mergeConflict(SyncConflict conflict, EmailModel local, EmailModel server) {
    switch (conflict.field) {
      case 'isRead':
        // Если хоть где-то прочитано — считаем прочитанным
        return server.copyWith(isRead: local.isRead || server.isRead);

      case 'isFlagged':
        // Если хоть где-то флаг — оставляем флаг
        return server.copyWith(isFlagged: local.isFlagged || server.isFlagged);

      case 'folderId':
        // Клиент переместил — его версия приоритетнее (пользователь осознанно переместил)
        return local;

      case 'tags':
        // Объединяем теги
        final mergedTags = {...local.tags, ...server.tags}.toList();
        return server.copyWith(tags: mergedTags);

      default:
        return server;
    }
  }

  /// Batch-разрешение конфликтов
  Future<List<EmailModel>> resolveAll(
    List<EmailModel> localEmails,
    List<EmailModel> serverEmails,
  ) async {
    final localMap = {for (final e in localEmails) e.id: e};
    final result = <EmailModel>[];

    for (final server in serverEmails) {
      final local = localMap[server.id];

      if (local == null || !local.isLocallyModified) {
        result.add(server);
        continue;
      }

      final conflicts = detectConflicts(local, server);
      if (conflicts.isEmpty) {
        result.add(server);
        continue;
      }

      var resolved = server;
      for (final conflict in conflicts) {
        resolved = resolveConflict(conflict, local, resolved);
      }

      // Снимаем флаг локальных изменений
      result.add(resolved.copyWith(isLocallyModified: false));
    }

    return result;
  }

  // ════════════════════════ PERSISTENCE ════════════════════════

  void _saveConflict(SyncConflict conflict) {
    final conflicts = getUnresolvedConflicts();
    conflicts.add(conflict);
    _prefs.setString(_conflictsKey, jsonEncode(conflicts.map((c) => c.toMap()).toList()));
  }

  List<SyncConflict> getUnresolvedConflicts() {
    final json = _prefs.getString(_conflictsKey);
    if (json == null) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((m) => SyncConflict.fromMap(m as Map<String, dynamic>)).where((c) => !c.resolved).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markResolved(String emailId, String field) async {
    final conflicts = getUnresolvedConflicts();
    final updated = conflicts.map((c) {
      if (c.emailId == emailId && c.field == field) {
        return SyncConflict(
          emailId: c.emailId, accountId: c.accountId, field: c.field,
          localValue: c.localValue, serverValue: c.serverValue,
          detectedAt: c.detectedAt, resolved: true,
        );
      }
      return c;
    }).toList();
    await _prefs.setString(_conflictsKey, jsonEncode(updated.map((c) => c.toMap()).toList()));
  }

  Future<void> clearAllConflicts() async {
    await _prefs.remove(_conflictsKey);
  }
}

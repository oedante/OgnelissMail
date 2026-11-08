// lib/services/widget_mail_actions.dart
// Действия с письмом прямо в виджете «Почта» (план 08.11.2026, п. 8.2,
// решение владельца: «Виджеты — согласен»): «Прочитано» и «В архив» у строки
// письма, без входа в приложение.
//
// Как устроено (тот же путь, что у окна «Создать» виджета календаря,
// quick_create_service.dart):
//  · виджет (Android — MailWidget.onReceive, iPhone — AppIntent расширения)
//    сразу убирает строку у себя и кладёт действие в очередь
//    (SharedPreferences / общая группа, ключ widget_mail_queue);
//  · Dart разбирает очередь: движок работает — сразу (вызов «mailAction»
//    канала ogneliss/widget), иначе — при запуске приложения и в фоновой
//    проверке почты. Действие выполняется тем же путём, что в приложении
//    (EmailActionsService): локально сразу, на сервере — с повтором из
//    очереди синхронизации, если нет сети.
// Ошибки — только в журнал (правило владельца 08.11.2026): письмо, которого
// уже нет, просто пропускается.

import 'dart:convert';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import '../data/database/app_database.dart';
import '../data/providers/database_provider.dart';
import '../features/mail/providers/mail_providers.dart' show accountsProvider;
import 'home_widget_service.dart';
import 'mail/email_actions_service.dart';
import 'mail/special_folders.dart';

final widgetMailActionsProvider = Provider<WidgetMailActions>((ref) => WidgetMailActions(ref));

class WidgetMailActions {
  final Ref _ref;
  WidgetMailActions(this._ref);

  static const queueKey = 'widget_mail_queue';
  static bool _busy = false;

  /// Разобрать очередь; вернуть, сколько действий выполнено.
  Future<int> drain() async {
    if (_busy) return 0;
    _busy = true;
    var done = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Очередь пишет код виджета в обход кэша плагина — перечитать.
      await prefs.reload();
      // iPhone: нажатия лежат в общей группе расширения — забрать к себе.
      final ios = parseQueue(await HomeWidgetService.takeIosMailQueue());
      final items = [...parseQueue(prefs.getString(queueKey)), ...ios];
      if (items.isEmpty) return 0;
      await prefs.remove(queueKey);
      final retry = <Map<String, Object?>>[];
      for (final m in items) {
        try {
          if (await _run(m, prefs)) done++;
        } catch (e) {
          AppLogger.warning('Действие из виджета ${m['op']}: $e');
          final tries = ((m['tries'] as num?)?.toInt() ?? 0) + 1;
          if (tries < 10) retry.add({...m, 'tries': tries});
        }
      }
      if (retry.isNotEmpty) {
        await prefs.reload();
        final fresh = parseQueue(prefs.getString(queueKey));
        await prefs.setString(queueKey, jsonEncode([...retry, ...fresh]));
      }
      if (done > 0) {
        AppLogger.info('Действий из виджета: $done');
        await HomeWidgetService.updateFrom(_ref, force: true);
      }
    } catch (e) {
      AppLogger.warning('Очередь действий виджета: $e');
    } finally {
      _busy = false;
    }
    return done;
  }

  /// Очередь из строки JSON: только записи с op, id и acc.
  static List<Map<String, Object?>> parseQueue(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final it in list)
          if (it is Map && it['op'] is String && it['id'] is String && it['acc'] is String)
            Map<String, Object?>.from(it),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// true — выполнено (или выполнять уже нечего: письма нет, оно прочитано
  /// или уже в архиве); исключение — повторить позже.
  Future<bool> _run(Map<String, Object?> m, SharedPreferences prefs) async {
    final op = m['op'] as String;
    final id = m['id'] as String;
    final accId = m['acc'] as String;
    final account = _ref.read(accountsProvider).where((a) => a.id == accId).firstOrNull;
    if (account == null) return false;
    final db = _ref.read(databaseProvider);
    final Email? row = await (db.select(db.emails)
          ..where((e) => e.id.equals(id) & e.accountId.equals(accId))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return false; // письмо уже удалено или перенесено
    final actions = _ref.read(emailActionsProvider);
    switch (op) {
      case 'read':
        if (row.isRead) return true;
        await actions.setRead(account, id, row.folderId, true);
        return true;
      case 'archive':
        final to = await SpecialFolders.resolve(db, prefs, accId, SpecialKind.archive);
        if (to == null) {
          // Папки «Архив» нет — пропускаем молча (её выбирают в приложении).
          AppLogger.info('Виджет «В архив»: у ящика нет папки «Архив» — пропущено');
          return false;
        }
        if (to == row.folderId) return true;
        await actions.moveTo(account, id, row.folderId, to);
        return true;
      default:
        return false;
    }
  }
}

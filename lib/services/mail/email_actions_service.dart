// lib/services/mail/email_actions_service.dart
// Единый слой действий над письмами поверх MailTransport-абстракции.
// Маршрутизация инкапсулирована в фабрике — здесь только действие + обновление БД.

import 'dart:convert';
import 'attachment_cache_service.dart';
import '../../data/models/folder_model.dart';
import 'dart:async';
import '../notifications/notification_service.dart';
import 'engine/mail_engine_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import 'later_service.dart';
import 'transport/mail_transport.dart';
import 'transport_capabilities.dart';
import '../sync/sync_service.dart';

final emailActionsProvider = Provider<EmailActionsService>((ref) {
  return EmailActionsService(ref);
});

class EmailActionsService {
  final Ref _ref;
  EmailActionsService(this._ref);

  AppDatabase get _db => _ref.read(databaseProvider);

  /// Строка письма ИМЕННО этого аккаунта. id письма уникален только в паре с
  /// аккаунтом: у IMAP это «INBOX:12», у ActiveSync — «5:12», и в двух ящиках
  /// такие id совпадают. Раньше действия искали письмо только по id —
  /// удаление в одном ящике стирало письмо с тем же id в другом.
  Expression<bool> _mine($EmailsTable e, String? accountId, String emailId) =>
      accountId == null ? e.id.equals(emailId) : (e.id.equals(emailId) & e.accountId.equals(accountId));
  MailTransport _transport(AccountModel a) => _ref.read(mailTransportFactoryProvider).forAccount(a);

  /// Письмо есть только на телефоне: черновик приложения («draft-…») или
  /// временная строка быстрого ответа («qr_…», 1.7.1, до прихода серверной
  /// копии). Действия над ним на сервер не отправляются.
  static bool _deviceOnly(String emailId) => emailId.startsWith('draft-') || emailId.startsWith('qr_');

  void _dismissNotification(String accountId, String emailId) {
    try {
      _ref.read(notificationServiceProvider).cancelEmail(accountId, emailId).catchError((_) {});
    } catch (_) {}
  }

  Future<void> setRead(AccountModel account, String emailId, String folderId, bool isRead) async {
    // Оптимистично: сначала БД (мгновенный отклик UI), затем сервер.
    // isLocallyModified=true — сигнал для conflict_resolver: при синке правку
    // нельзя молча затирать серверной версией. Флаг снимется на успешном синке.
    await (_db.update(_db.emails)..where((e) => _mine(e, account.id, emailId)))
        .write(EmailsCompanion(isRead: Value(isRead), isLocallyModified: const Value(true)));
    // Прочитано в приложении — уведомление о письме в шторке больше не нужно.
    if (isRead) _dismissNotification(account.id, emailId);
    // Результат серверного поиска ActiveSync (псевдопапка «search»): у
    // письма LongId, а не ServerId — меняем его копию в папке или находим
    // ServerId командой Find (см. _applyToSearchHit).
    if (folderId == 'search' && account.usesEas) {
      await _applyToSearchHit(account, emailId, read: isRead);
      return;
    }
    if (_deviceOnly(emailId)) return;
    try {
      await _transport(account).setRead(account, emailId: emailId, folderId: folderId, isRead: isRead);
      await _clearLocalMark(account, emailId);
    } catch (e) {
      // Сервер недоступен — правку сохраняем локально И ставим в очередь, чтобы
      // выгрузить её при следующем синке (иначе она никогда не дойдёт до сервера).
      AppLogger.warning('setRead remote failed (локально применено, в очередь): $e');
      await _enqueueOffline(account, 'mark_read', emailId, {'isRead': isRead, 'folderId': folderId});
    }
  }

  Future<void> setFlag(AccountModel account, String emailId, String folderId, bool isFlagged) async {
    await (_db.update(_db.emails)..where((e) => _mine(e, account.id, emailId)))
        .write(EmailsCompanion(isFlagged: Value(isFlagged), isLocallyModified: const Value(true)));
    if (folderId == 'search' && account.usesEas) {
      await _applyToSearchHit(account, emailId, flagged: isFlagged);
      return;
    }
    if (_deviceOnly(emailId)) return;
    try {
      await _transport(account).setFlag(account, emailId: emailId, folderId: folderId, isFlagged: isFlagged);
      await _clearLocalMark(account, emailId);
    } catch (e) {
      AppLogger.warning('setFlag remote failed (локально применено, в очередь): $e');
      await _enqueueOffline(account, 'flag', emailId, {'isFlagged': isFlagged, 'folderId': folderId});
    }
  }

  /// Прочитано/флаг для письма из серверного поиска ActiveSync.
  ///  1. Есть копия письма в синхронизируемой папке (та же тема, отправитель,
  ///     время) — меняем её обычным путём: сервер, при сбое — очередь.
  ///  2. Нет (письмо старше окна синхронизации) — ищем его ServerId командой
  ///     Find в папке письма и меняем на сервере.
  /// Раньше такие отметки оставались только на телефоне.
  Future<void> _applyToSearchHit(AccountModel account, String emailId, {bool? read, bool? flagged}) async {
    try {
      final hit = await (_db.select(_db.emails)..where((e) => _mine(e, account.id, emailId))).getSingleOrNull();
      if (hit == null) return;
      await _clearLocalMark(account, emailId);
      final twin = await findLocalTwin(_db, account.id,
          subject: hit.subject, fromEmail: hit.fromEmail, receivedAt: hit.receivedAt);
      if (twin != null) {
        if (read != null) await setRead(account, twin.id, twin.folderId, read);
        if (flagged != null) await setFlag(account, twin.id, twin.folderId, flagged);
        return;
      }
      final ok = await _ref.read(mailEngineServiceProvider).applyFlagsToSearchHit(
            account,
            emailId: emailId,
            subject: hit.subject,
            fromEmail: hit.fromEmail,
            receivedAt: hit.receivedAt,
            read: read,
            flagged: flagged,
          );
      if (!ok) AppLogger.info('Письмо из поиска: изменение сохранено только на телефоне');
    } catch (e) {
      AppLogger.warning('Письмо из поиска: $e');
    }
  }

  /// Сервер принял правку — снимаем пометку «изменено локально». Иначе
  /// синхронизация считала бы строку несогласованной и не применяла к ней
  /// изменения с сервера (прочитано/удалено на другом устройстве).
  Future<void> _clearLocalMark(AccountModel account, String emailId) async {
    try {
      await (_db.update(_db.emails)
            ..where((e) => _mine(e, account.id, emailId)))
          .write(const EmailsCompanion(isLocallyModified: Value(false)));
    } catch (_) {}
  }

  /// Поставить офлайн-операцию в очередь синхронизации (дренаж — в
  /// SyncService._processQueue перед выборкой с сервера). Раньше очередь
  /// принимала только EWS-аккаунты: у ActiveSync и IMAP офлайн-правки
  /// (прочитано, флаг, перемещение, удаление) до сервера не доходили никогда.
  Future<void> _enqueueOffline(
    AccountModel account, String type, String emailId, Map<String, dynamic> payload,
  ) async {
    try {
      await _ref.read(syncServiceProvider).enqueueOperation(
            accountId: account.id, operationType: type, targetId: emailId, payload: payload,
          );
    } catch (e) {
      AppLogger.warning('enqueue $type failed: $e');
    }
  }

  /// Прежнее «Напомнить» — теперь «Посмотреть позже» с датой.
  Future<void> setReminder(String emailId, DateTime? remindAt, {String? accountId}) async {
    final acc = accountId ?? (await _db.getEmailById(emailId))?.accountId;
    if (acc == null) return;
    await setLater(emailId, acc, on: remindAt != null, at: remindAt);
  }

  static int laterNotificationId(String accountId, String emailId) =>
      NotificationService.stableId('later|$accountId|$emailId');

  /// «Посмотреть позже»: отложить ([on], срок [at] или без даты) или снять.
  /// Уведомление о возврате планируется в ОС заранее — придёт и при
  /// выгруженном приложении.
  Future<void> setLater(String emailId, String accountId, {required bool on, DateTime? at}) async {
    await _db.setLaterState(emailId, accountId, on ? LaterState.waiting : LaterState.none, remindAt: on ? at : null);
    final notif = _ref.read(notificationServiceProvider);
    final notifId = laterNotificationId(accountId, emailId);
    await notif.cancelScheduled(notifId);
    // Уведомления прежних версий (id по hashCode строки).
    await notif.cancelScheduled(emailId.hashCode);
    if (!on || at == null || !at.isAfter(DateTime.now())) return;
    final row = await _db.getEmailById(emailId, accountId: accountId);
    if (row == null) return;
    final l10n = AppLocalizations(_ref.read(settingsProvider).locale);
    final payload = jsonEncode({
      'type': 'email',
      'accountId': row.accountId,
      'emailId': emailId,
      'folderId': row.folderId,
      'fromEmail': row.fromEmail,
      'subject': row.subject,
    });
    final from = row.fromName?.isNotEmpty == true ? row.fromName! : row.fromEmail;
    await notif.scheduleEmailReminder(
      id: notifId,
      title: l10n.tr('laterNotifTitle').replaceAll('{from}', from),
      body: row.subject.isEmpty ? l10n.tr('noSubject') : row.subject,
      when: at,
      payload: payload,
    );
  }

  /// Письмо открыто — отметка «Вернулось» больше не нужна.
  Future<void> clearReturned(String emailId, String accountId) =>
      _db.setLaterState(emailId, accountId, LaterState.none);

  /// Срок отложенных писем наступил: «Вернулось», снова непрочитанное — в
  /// приложении и на сервере. Уведомление уже показала ОС. Возвращает число
  /// вернувшихся писем.
  Future<int> returnDueLater() async {
    var n = 0;
    try {
      final due = await _db.dueLaterEmails(DateTime.now());
      if (due.isEmpty) return 0;
      final accounts = {for (final a in _ref.read(accountsProvider)) a.id: a};
      for (final row in due) {
        await _db.setLaterState(row.id, row.accountId, LaterState.returned);
        final a = accounts[row.accountId];
        if (a != null && row.isRead) {
          try {
            await setRead(a, row.id, row.folderId, false);
          } catch (e) {
            AppLogger.warning('Позже — непрочитанное: $e');
          }
        }
        n++;
      }
      AppLogger.info('Позже: вернулось писем $n');
    } catch (e) {
      AppLogger.warning('Позже — проверка срока: $e');
    }
    return n;
  }

  /// Серверные категории Outlook: сохраняем локально И пишем на сервер (EWS
  /// UpdateItem) — категории появятся и в Outlook. Возвращает успех серверной части.
  Future<bool> setCategories(AccountModel account, String emailId, List<String> categories) async {
    final clean = categories.map((c) => c.trim()).where((c) => c.isNotEmpty).toSet().toList();
    // Пометка «изменено локально» — только пока сервер не подтвердил: с ней
    // синхронизация не применяет к письму серверные удаления. Прежде она
    // оставалась навсегда.
    await (_db.update(_db.emails)..where((e) => _mine(e, account.id, emailId)))
        .write(EmailsCompanion(
          categoriesStr: Value(clean.isEmpty ? null : clean.join(';')),
          isLocallyModified: const Value(true),
        ));
    try {
      // Для ActiveSync нужна папка письма (команда Sync идёт по папке).
      final row = await (_db.select(_db.emails)..where((e) => _mine(e, account.id, emailId)))
          .getSingleOrNull();
      final ok = await _ref
          .read(mailEngineServiceProvider)
          .setCategories(account, itemId: emailId, categories: clean, folderId: row?.folderId);
      if (ok) await _clearLocalMarkIfNoPending(account.id, emailId);
      return ok;
    } catch (e) {
      AppLogger.warning('setCategories server failed (локально применено): $e');
      return false;
    }
  }

  /// Задать теги письма (локально). Разделитель — «;». Пустой список очищает теги.
  Future<void> setTags(String emailId, List<String> tags, {String? accountId}) async {
    final clean = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList();
    // Теги — только локальные: сервер их не знает, а синхронизация сохраняет
    // их объединением. Пометка «изменено локально» им не нужна — прежде из-за
    // неё к письму навсегда переставали применяться серверные удаления.
    await (_db.update(_db.emails)..where((e) => _mine(e, accountId, emailId)))
        .write(EmailsCompanion(
          tagsStr: Value(clean.isEmpty ? null : clean.join(';')),
        ));
  }

  /// Снять пометку «изменено локально», если других правок письма в очереди нет.
  Future<void> _clearLocalMarkIfNoPending(String accountId, String emailId) async {
    final pending = await (_db.select(_db.syncQueue)
          ..where((q) => q.accountId.equals(accountId) & q.targetId.equals(emailId))
          ..limit(1))
        .get();
    if (pending.isNotEmpty) return;
    await (_db.update(_db.emails)..where((e) => _mine(e, accountId, emailId)))
        .write(const EmailsCompanion(isLocallyModified: Value(false)));
  }

  Future<String> _folderName(String accountId, String folderId) async {
    final f = await (_db.select(_db.folders)
          ..where((x) => x.id.equals(folderId) & x.accountId.equals(accountId))
          ..limit(1))
        .get();
    return f.isEmpty ? folderId : f.first.displayName;
  }

  Future<void> moveTo(AccountModel account, String emailId, String fromFolderId, String targetFolderId) async {
    await (_db.update(_db.emails)..where((e) => _mine(e, account.id, emailId)))
        .write(EmailsCompanion(
          folderId: Value(targetFolderId),
          // Имя папки из списка папок аккаунта (раньше писался её id — и
          // письмо, перенесённое в «Нежелательные», оставалось в сводной ленте).
          folderName: Value(await _folderName(account.id, targetFolderId)),
          isLocallyModified: const Value(true),
        ));
    // В «Корзину» или «Спам» — файлы и картинки письма из кэша телефона.
    unawaited(_dropCacheIfBin(account.id, emailId, targetFolderId));
    if (_deviceOnly(emailId)) return;
    // Этап 7П: серверное перемещение только если транспорт это умеет.
    if (!TransportCapabilities.forAccount(account).serverMove) {
      AppLogger.info('moveTo: транспорт без серверного перемещения — применено локально');
      return;
    }
    try {
      final newId = await _transport(account)
          .move(account, emailId: emailId, fromFolderId: fromFolderId, toFolderId: targetFolderId);
      await _clearLocalMark(account, emailId);
      if (newId != null && newId != emailId) {
        await _ref.read(syncServiceProvider).renameEmailId(_db, account.id, emailId, newId);
      }
    } catch (e) {
      AppLogger.warning('moveTo remote failed (локально применено, в очередь): $e');
      await _enqueueOffline(account, 'move', emailId,
          {'targetFolderId': targetFolderId, 'fromFolderId': fromFolderId});
    }
  }

  /// Письмо ушло в «Корзину» или «Спам»: его файлы и картинки на телефоне
  /// больше не нужны (вернётся — загрузятся при открытии).
  Future<void> _dropCacheIfBin(String accountId, String emailId, String folderId) async {
    try {
      final f = await (_db.select(_db.folders)
            ..where((x) => x.accountId.equals(accountId) & x.id.equals(folderId)))
          .getSingleOrNull();
      final t = f?.type;
      if (t == FolderType.trash.index || t == FolderType.junk.index) {
        await _ref.read(attachmentCacheProvider).removeForEmail(accountId, emailId);
      }
    } catch (_) {}
  }

  Future<void> delete(AccountModel account, String emailId, String folderId, {bool hard = false}) async {
    await (_db.delete(_db.emails)..where((e) => _mine(e, account.id, emailId))).go();
    // Удалённое письмо не оставляет на телефоне файлов и картинок.
    unawaited(_ref.read(attachmentCacheProvider).removeForEmail(account.id, emailId).catchError((Object _) => 0));
    _dismissNotification(account.id, emailId);
    await _db.removeEmailFts(emailId, accountId: account.id); // не оставляем сироту в поисковом индексе
    // Черновик приложения есть только на устройстве — на сервер не ходим
    // (иначе неудачное удаление вставало в очередь и повторялось).
    if (_deviceOnly(emailId)) return;
    try {
      await _transport(account).delete(account, emailId: emailId, folderId: folderId, hard: hard);
    } catch (e) {
      AppLogger.warning('delete remote failed (локально применено, в очередь): $e');
      await _enqueueOffline(account, 'delete', emailId, {'folderId': folderId, 'hard': hard});
    }
  }

  Future<void> batchSetRead(AccountModel account, List<String> ids, String folderId, bool isRead) async {
    for (final id in ids) { await setRead(account, id, folderId, isRead); }
  }
  Future<void> batchSetFlag(AccountModel account, List<String> ids, String folderId, bool isFlagged) async {
    for (final id in ids) { await setFlag(account, id, folderId, isFlagged); }
  }
  Future<void> batchDelete(AccountModel account, List<String> ids, String folderId) async {
    for (final id in ids) { await delete(account, id, folderId); }
  }

  /// Удалить письма-кандидаты очистки (каждое со своей папкой). По умолчанию —
  /// в Корзину (hard=false), можно безвозвратно. Возвращает число удалённых.
  Future<int> cleanupDelete(AccountModel account, List<({String id, String folderId})> items, {bool hard = false}) async {
    var done = 0;
    for (final it in items) {
      try {
        await delete(account, it.id, it.folderId, hard: hard);
        done++;
      } catch (_) {}
    }
    return done;
  }
  Future<void> batchMove(AccountModel account, List<String> ids, String fromFolderId, String targetFolderId) async {
    for (final id in ids) { await moveTo(account, id, fromFolderId, targetFolderId); }
  }
}

/// Возможности транспорта активного аккаунта (для UI: скрывать недоступное).
final transportCapabilitiesProvider = Provider<TransportCapabilities?>((ref) {
  final account = ref.watch(activeAccountProvider);
  return account == null ? null : TransportCapabilities.forAccount(account);
});

/// Копия письма из серверного поиска в синхронизируемой папке: тот же
/// аккаунт, тема и отправитель, время получения — в пределах 2 минут.
Future<Email?> findLocalTwin(AppDatabase db, String accountId,
    {required String subject, required String fromEmail, required DateTime receivedAt}) async {
  final rows = await (db.select(db.emails)
        ..where((e) =>
            e.accountId.equals(accountId) &
            e.folderId.equals('search').not() &
            e.subject.equals(subject) &
            e.receivedAt.isBetweenValues(
                receivedAt.subtract(const Duration(minutes: 2)), receivedAt.add(const Duration(minutes: 2))))
        ..limit(5))
      .get();
  final from = fromEmail.toLowerCase();
  for (final r in rows) {
    if (from.isEmpty || r.fromEmail.toLowerCase() == from) return r;
  }
  return null;
}

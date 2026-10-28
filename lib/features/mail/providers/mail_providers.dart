// lib/features/mail/providers/mail_providers.dart
// Провайдеры почтового модуля с ПАГИНАЦИЕЙ и группировкой в беседы.
// Письма загружаются из SQLite порциями по 30 штук.
// При скролле подгружаются следующие порции (infinite scroll).
// Группировка по conversationId.
// Контроль RAM: не держим в памяти больше 200 писем.

import '../../../core/constants/exchange_feature.dart';
import '../../../services/notifications/account_notify_mode.dart' show FolderNotify;
import '../../../services/mail/special_folders.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/device/phone_mirror_service.dart' show phoneMirrorProvider;
import '../../../core/utils/text_safe.dart';
import '../../../core/utils/symbol_fonts.dart';
import '../../../services/sync/imap_push_service.dart';
import '../../../services/security/device_security_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/email_actions_service.dart' show findLocalTwin;
import '../../../services/mail/dav/dav_pim_service.dart' show DavPimService;
import '../../../services/mail/oauth/oauth_revocation.dart';
import '../../../services/mail/transport_capabilities.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../core/errors/app_exceptions.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/contact_model.dart' show ContactSource;
import '../../../data/models/folder_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/security/security_utils.dart' show SecurityUtils;
import '../../../features/settings/providers/settings_provider.dart';
import '../../settings/providers/account_groups_provider.dart';
import '../../../services/mail/attachment_cache_service.dart' show attachmentCacheProvider;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/text_entities.dart';
import '../../../services/mail/conversation_counter.dart';
import '../../../services/mail/focus_mode_service.dart' show focusModeProvider;

// ════════════════════════ АККАУНТЫ ════════════════════════

/// Провайдер списка аккаунтов
/// Запрос «открыть поиск по почте» (горячая клавиша на десктопе): список
/// писем слушает изменения счётчика.
final mailSearchRequestProvider = StateProvider<int>((ref) => 0);

/// Запрос «открыть папки» — повторное нажатие «Почта» в нижней панели
/// (панель по образцу Ogneliss Dialer: «Почта» — она же «Папки»).
final mailDrawerRequestProvider = StateProvider<int>((ref) => 0);

/// Открыть меню папок, когда экран почты появится (переход из другого
/// раздела по нажатию на аватар ящика в нижней панели).
final mailDrawerPendingProvider = StateProvider<bool>((ref) => false);

/// Меняется при постановке/снятии «На контроле» — «Мой день» перечитывает.
final controlRevisionProvider = StateProvider<int>((ref) => 0);

/// Меняется, когда письмо отложено («Посмотреть позже») или снято.
final laterRevisionProvider = StateProvider<int>((ref) => 0);

/// Сколько ящиков Exchange скрыто в сборке без Exchange (1.8.5).
int hiddenExchangeAccounts = 0;

final accountsProvider =
    StateNotifierProvider<AccountsNotifier, List<AccountModel>>((ref) {
  final db = ref.watch(databaseProvider);
  final secureStorage = ref.watch(secureStorageProvider);
  return AccountsNotifier(db, secureStorage, ref);
});

/// Текущий активный аккаунт
/// Аккаунт по id, иначе — активный. Экраны настроек аккаунта (автоответ,
/// синхронизация папок, подписи, правила) открываются из экрана аккаунта с
/// его id и должны работать с ним, а не с тем, что выбран в списке писем.
/// Время последней успешной синхронизации аккаунта — прямо из БД. Через
/// список аккаунтов его не проводим: каждое обновление списка пересоздаёт
/// провайдер писем, и список дёргался бы после каждой синхронизации.
final lastSyncAtProvider = StreamProvider.family<DateTime?, String>((ref, accountId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.accounts)..where((a) => a.id.equals(accountId)))
      .watchSingleOrNull()
      .map((r) => r?.lastSyncAt);
});

final accountOrActiveProvider = Provider.family<AccountModel?, String?>((ref, id) {
  if (id != null) {
    final found = ref.watch(accountsProvider).where((a) => a.id == id).firstOrNull;
    if (found != null) return found;
  }
  return ref.watch(activeAccountProvider);
});

final activeAccountProvider = Provider<AccountModel?>((ref) {
  final accounts = ref.watch(accountsProvider);
  final settings = ref.watch(settingsProvider);
  if (accounts.isEmpty) return null;

  if (settings.activeAccountId != null) {
    final found = accounts.where((a) => a.id == settings.activeAccountId).firstOrNull;
    if (found != null) return found;
  }

  return accounts.firstWhere((a) => a.isPrimary, orElse: () => accounts.first);
});

/// Непрочитанные «Всей почты» по набору аккаунтов (ключ — id через запятую,
/// пустая строка — ни одного). Живой поток из базы: прочитали письмо —
/// число уменьшилось сразу, а не после следующей синхронизации.
final unifiedUnreadByKeyProvider = StreamProvider.family<int, String>((ref, key) {
  final db = ref.watch(databaseProvider);
  final ids = key.isEmpty ? const <String>[] : key.split(',');
  return db.watchUnifiedUnreadCount(ids);
});

/// Значок на вкладке «Почта»: непрочитанные «Всей почты» всех включённых
/// ящиков — то же число, что у строки «Все аккаунты» в меню папок.
///
/// Раньше — сумма `accounts.unread_count`: поле обновлялось только в конце
/// синхронизации, включало архив и виртуальные папки Gmail (одно письмо
/// считалось несколько раз) и не совпадало ни с одним числом на экране.
final totalUnreadCountProvider = Provider<int>((ref) {
  final key = ref.watch(accountsProvider.select(
      (list) => [for (final a in list) if (a.isActive) a.id].join(',')));
  return ref.watch(unifiedUnreadByKeyProvider(key)).value ?? 0;
});

class AccountsNotifier extends StateNotifier<List<AccountModel>> {
  final AppDatabase _db;
  final SecureStorageService _secureStorage;
  final Ref? _ref;

  AccountsNotifier(this._db, this._secureStorage, [this._ref]) : super([]) {
    _loadAccounts();
  }

  /// Публичная загрузка аккаунтов из БД (await). Нужна фоновому изоляту
  /// (WorkManager): там контейнер создаётся заново и конструкторная загрузка
  /// (`_loadAccounts`) ещё не завершена к моменту синка.
  Future<void> reload() => _loadAccounts();

  /// Снять отметку «вход не удался» (после повторного входа) — синхронизация
  /// и push снова включатся для аккаунта.
  Future<void> clearAuthFailure(String accountId) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(const AccountsCompanion(authFailedAt: Value(null)));
    try {
      _ref?.read(mailEngineServiceProvider).disconnect(accountId);
    } catch (_) {}
    await _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      final rows = await (_db.select(_db.accounts)
            // Порядок из настроек; при равном (старые ящики — все 0) —
            // по дате добавления, чтобы порядок не прыгал.
            ..orderBy([
              (a) => OrderingTerm(expression: a.sortOrder, mode: OrderingMode.asc),
              (a) => OrderingTerm(expression: a.createdAt, mode: OrderingMode.asc),
            ]))
          .get();
      // Сборка без Exchange (1.8.5): ящики Exchange скрыты, данные остаются.
      final hidden = rows.where((r) => exchangeHidden(AccountType.values[r.type])).length;
      hiddenExchangeAccounts = hidden;

      state = rows.where((r) => !exchangeHidden(AccountType.values[r.type])).map((row) => AccountModel(
            id: row.id,
            type: AccountType.values[row.type],
            email: row.email,
            displayName: row.displayName,
            username: row.username,
            domain: row.domain,
            exchangeServer: row.exchangeServer,
            exchangeAuthMethod: row.exchangeAuthMethod != null
                ? ExchangeAuthMethod.values[row.exchangeAuthMethod!]
                : null,
            ewsUrl: row.ewsUrl,
            imapServer: row.imapServer,
            imapPort: row.imapPort,
            imapEncryption: row.imapEncryption != null
                ? EncryptionType.values[row.imapEncryption!]
                : null,
            smtpServer: row.smtpServer,
            smtpPort: row.smtpPort,
            smtpEncryption: row.smtpEncryption != null
                ? EncryptionType.values[row.smtpEncryption!]
                : null,
            syncInterval: SyncInterval.values[row.syncInterval],
            syncOnlyWifi: row.syncOnlyWifi,
            syncDays: row.syncDays,
            isActive: row.isActive,
            authFailedAt: row.authFailedAt,
            sharedMailboxEmail: row.sharedMailboxEmail,
            parentAccountId: row.parentAccountId,
            accountKind: row.accountKind,
            isPrimary: row.isPrimary,
            // Цвета прежней яркой палитры (и старый жёлтый по умолчанию) —
            // приглушённые; свои цвета вне палитры не трогаем.
            colorValue: _mutedColors[row.colorValue] ?? row.colorValue,
            avatarUrl: row.avatarUrl,
            signatureId: row.signatureId,
            certificatePath: row.certificatePath,
            createdAt: row.createdAt,
            lastSyncAt: row.lastSyncAt,
            unreadCount: row.unreadCount,
          )).toList();

      // Приглушённые цвета — в базу (один раз).
      for (final r in rows) {
        final m = _mutedColors[r.colorValue];
        if (m != null) {
          await (_db.update(_db.accounts)..where((x) => x.id.equals(r.id)))
              .write(AccountsCompanion(colorValue: Value(m)));
        }
      }
      await _assignDistinctColors();
      AppLogger.info('Загружено ${state.length} аккаунтов');
    } catch (e, stack) {
      AppLogger.error('Ошибка загрузки аккаунтов', e, stack);
    }
  }

  /// Цвета аккаунтов: различимые, белый текст читается на каждом.
  /// Первые восемь — прежние (порядок не менять: по нему раздаются цвета
  /// новым ящикам). Белый или чёрный текст поверх подбирается по яркости
  /// (onAccountColor), поэтому в палитре есть и светлые цвета.
  static const accountPalette = <int>[
    0xFF2F5C93, // синий (фирменный, приглушённый)
    0xFFB9773F, // охра
    0xFF4B7D58, // зелёный
    0xFF7A5C92, // фиолетовый
    0xFFA4554F, // красный
    0xFF3E7F86, // бирюзовый
    0xFF77604F, // коричневый
    0xFF51609C, // индиго
    0xFF9E5A76, // малиновый
    0xFFB89A4C, // горчичный
    0xFF7D9658, // салатовый
    0xFF4D88B4, // голубой
    0xFF675B98, // тёмно-фиолетовый
    0xFF3F6B64, // тёмно-бирюзовый
    0xFFAD6A4F, // кирпичный
    0xFF5E717B, // серо-синий
    0xFF7B7747, // оливковый
    0xFF8E5068, // вишнёвый
    0xFF34507A, // тёмно-синий
    0xFF3B4347, // графит
    // 1.6.2: ещё 12 спокойных цветов (замечание 13.10.2026: «можно
    // добавить больше цветов»).
    0xFF6A8CAF, // стальной голубой
    0xFF2E6E8E, // морской
    0xFF5C9A8C, // мятный
    0xFF4F6B3A, // хвойный
    0xFF8A9A5B, // шалфей
    0xFFC08A5A, // карамельный
    0xFF9C8A6E, // бежевый
    0xFFB3676E, // пыльная роза
    0xFF8B3F3F, // бордовый
    0xFF8C7AA8, // лавандовый
    0xFF6E4F7A, // сливовый
    0xFF757575, // серый
  ];

  /// Прежняя яркая палитра → приглушённая (замечание 09.10.2026: цвета
  /// ящиков слишком яркие и отвлекают от остального интерфейса).
  static const _mutedColors = <int, int>{
    0xFF1D4F91: 0xFF2F5C93, 0xFFE07A1F: 0xFFB9773F, 0xFF2E7D32: 0xFF4B7D58,
    0xFF8E24AA: 0xFF7A5C92, 0xFFC62828: 0xFFA4554F, 0xFF00838F: 0xFF3E7F86,
    0xFF6D4C41: 0xFF77604F, 0xFF3949AB: 0xFF51609C, 0xFFD81B60: 0xFF9E5A76,
    0xFFF9A825: 0xFFB89A4C, 0xFF7CB342: 0xFF7D9658, 0xFF039BE5: 0xFF4D88B4,
    0xFF5E35B1: 0xFF675B98, 0xFF00695C: 0xFF3F6B64, 0xFFF4511E: 0xFFAD6A4F,
    0xFF546E7A: 0xFF5E717B, 0xFF827717: 0xFF7B7747, 0xFFAD1457: 0xFF8E5068,
    0xFF0D47A1: 0xFF34507A, 0xFF263238: 0xFF3B4347, 0xFFFFC928: 0xFF2F5C93,
  };

  /// У всех аккаунтов был один цвет по умолчанию — отличить ящики было
  /// нельзя. Аккаунтам с одинаковым цветом раздаём разные из палитры
  /// (первый сохраняет свой). Выбранные пользователем цвета не повторяются.
  Future<void> _assignDistinctColors() async {
    final used = <int>{};
    final next = <AccountModel>[];
    var changed = false;
    for (final a in state) {
      var c = a.colorValue;
      if (used.contains(c)) {
        c = accountPalette.firstWhere((p) => !used.contains(p),
            orElse: () => accountPalette[used.length % accountPalette.length]);
        await (_db.update(_db.accounts)..where((x) => x.id.equals(a.id)))
            .write(AccountsCompanion(colorValue: Value(c)));
        changed = true;
      }
      used.add(c);
      next.add(c == a.colorValue ? a : a.copyWith(colorValue: c));
    }
    if (changed) state = next;
  }

  /// Цвет аккаунта (экран аккаунта).
  Future<void> setAccountColor(String accountId, int color) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(colorValue: Value(color)));
    state = [for (final a in state) a.id == accountId ? a.copyWith(colorValue: color) : a];
  }

  /// Фото аккаунта (из адресной книги организации или профиля Google).
  Future<void> setAccountPhoto(String accountId, String? photo) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(avatarUrl: Value(photo)));
    state = [for (final a in state) a.id == accountId ? a.copyWith(avatarUrl: photo) : a];
  }

  /// Добавить аккаунт (пароль сохраняется в secure storage)
  Future<void> addAccount(AccountModel account, {String? password}) async {
    // Защита от дублей: один и тот же email повторно не добавляем. Архив
    // Exchange (1.6.49) — с адресом основного ящика: для него — по id.
    final dup = account.isOnlineArchive
        ? state.any((a) => a.id == account.id)
        : state.any(
            (a) => !a.isOnlineArchive && a.email.trim().toLowerCase() == account.email.trim().toLowerCase(),
          );
    if (dup) {
      throw AccountAlreadyExistsException(email: account.email);
    }
    try {
      if (password != null) {
        await _secureStorage.saveAccountPassword(account.id, password);
      }
      // Новому ящику — свободный цвет палитры.
      final usedColors = state.map((a) => a.colorValue).toSet();
      if (usedColors.contains(account.colorValue)) {
        account = account.copyWith(
            colorValue: accountPalette.firstWhere((c) => !usedColors.contains(c),
                orElse: () => accountPalette[state.length % accountPalette.length]));
      }

      // Новый ящик — в конец списка (порядок задаётся в настройках).
      final maxOrder = await _db
          .customSelect('SELECT COALESCE(MAX(sort_order), -1) AS m FROM accounts')
          .map((r) => r.read<int>('m'))
          .getSingle();
      await _db.into(_db.accounts).insert(AccountsCompanion.insert(
            id: account.id,
            sortOrder: Value(maxOrder + 1),
            type: account.type.index,
            email: account.email,
            displayName: account.displayName,
            username: account.username,
            domain: Value(account.domain),
            exchangeServer: Value(account.exchangeServer),
            exchangeAuthMethod: Value(account.exchangeAuthMethod?.index),
            ewsUrl: Value(account.ewsUrl),
            imapServer: Value(account.imapServer),
            imapPort: Value(account.imapPort),
            imapEncryption: Value(account.imapEncryption?.index),
            smtpServer: Value(account.smtpServer),
            smtpPort: Value(account.smtpPort),
            smtpEncryption: Value(account.smtpEncryption?.index),
            syncInterval: Value(account.syncInterval.index),
            syncOnlyWifi: Value(account.syncOnlyWifi),
            syncDays: Value(account.syncDays),
            isActive: Value(account.isActive),
            isPrimary: Value(account.isPrimary),
            colorValue: Value(account.colorValue),
            // Общий ящик: без этих полей после перезапуска он становился
            // обычным аккаунтом без пароля и не синхронизировался.
            sharedMailboxEmail: Value(account.sharedMailboxEmail),
            parentAccountId: Value(account.parentAccountId),
            createdAt: account.createdAt,
          ));

      state = [...state, account];
      AppLogger.info('Аккаунт добавлен: ${account.email}');
    } catch (e, stack) {
      AppLogger.error('Ошибка добавления аккаунта', e, stack);
      rethrow;
    }
  }

  /// Удалить аккаунт и все связанные данные.
  ///
  /// Всё в одной транзакции: раньше удаление шло по шагам, и ошибка внешнего
  /// ключа (у аккаунта были поручения) оставляла его наполовину удалённым —
  /// без писем и паролей, но в списке. Контакты, заметки, поручения,
  /// поисковый индекс, состояние синхронизации и кэш вложений тоже удаляются:
  /// данные ящика не должны оставаться на устройстве после его удаления.
  Future<void> removeAccount(String accountId) async {
    // Общие ящики, открытые через этот аккаунт, без его пароля не работают —
    // удаляются вместе с ним.
    for (final child in state.where((a) => a.parentAccountId == accountId).toList()) {
      await removeAccount(child.id);
    }
    // Ящик исчезает из приложения сразу (замечание 09.10.2026: удаление
    // «срабатывало со второго нажатия» — первое долго ждало сети и базы,
    // а на экране ничего не менялось). Синхронизация удалённого ящика больше
    // не запускается; данные стираются следом.
    final removed = state.where((a) => a.id == accountId).firstOrNull;
    state = state.where((a) => a.id != accountId).toList();
    try {
      // Push (IMAP IDLE, EAS Ping, EWS) держит свои соединения: без остановки
      // он продолжал входить на сервер уже удалённого ящика.
      try {
        await _ref?.read(imapPushServiceProvider).stopForAccount(accountId).timeout(const Duration(seconds: 5));
      } catch (_) {}
      try {
        _ref?.read(mailEngineServiceProvider).disconnect(accountId);
      } catch (_) {}
      // Контакты и календарь ящика в телефоне — удалить вместе с ящиком.
      try {
        if (removed != null) await _ref?.read(phoneMirrorProvider).forget(removed).timeout(const Duration(seconds: 20));
      } catch (_) {}
      // Идущая синхронизация могла держать базу — несколько попыток.
      for (var attempt = 1;; attempt++) {
        try {
          await _deleteAccountRows(accountId);
          break;
        } catch (e) {
          if (attempt >= 3) rethrow;
          AppLogger.warning('Удаление ящика: попытка $attempt не удалась ($e) — повтор');
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
      if (removed != null) {
        try {
          await OAuthRevocation.revoke(removed, _secureStorage).timeout(const Duration(seconds: 10));
        } catch (_) {}
      }
      await _secureStorage.deleteAccountTokens(accountId);
      await _secureStorage.deleteAccountPassword(accountId);
      await clearSyncState(accountId);
      await DavPimService.forgetAccount(accountId);
      await OwnAddresses.forget(accountId);
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove('eas_policy_$accountId');
        // Уведомления по папкам этого ящика (1.7.2).
        await FolderNotify.forgetAccount(p, accountId);
        // Выбранные вручную папки «Архив» и «Спам» (1.7.2+106).
        await SpecialFolders.forgetAccount(p, accountId);
      } catch (_) {}
      try {
        await _ref?.read(attachmentCacheProvider).removeForAccount(accountId);
      } catch (_) {}

      state = state.where((a) => a.id != accountId).toList();
      AppLogger.info('Аккаунт и все данные удалены: $accountId');
      // Последний ящик удалён — администратор устройства (тайм-аут экрана по
      // политике) больше не нужен и мешал бы удалить приложение.
      if (state.isEmpty) {
        try {
          await _ref?.read(deviceSecurityServiceProvider).removeAdmin();
        } catch (_) {}
      }
    } catch (e, stack) {
      AppLogger.error('Ошибка удаления аккаунта', e, stack);
      // Данные не стёрлись — ящик возвращается в список, а не «воскресает»
      // молча после перезапуска.
      if (removed != null && !state.any((a) => a.id == accountId)) state = [...state, removed];
    }
  }

  Future<void> _deleteAccountRows(String accountId) async {
      await _db.transaction(() async {
        await _db.customStatement('DELETE FROM emails_fts WHERE account_id = ?', [accountId]);
        await (_db.delete(_db.emails)..where((e) => e.accountId.equals(accountId))).go();
        await (_db.delete(_db.folders)..where((f) => f.accountId.equals(accountId))).go();
        await (_db.delete(_db.calendarEvents)..where((c) => c.accountId.equals(accountId))).go();
        await (_db.delete(_db.tasks)..where((t) => t.accountId.equals(accountId))).go();
        await (_db.delete(_db.contacts)..where((c) => c.accountId.equals(accountId))).go();
        await (_db.delete(_db.notes)..where((n) => n.accountId.equals(accountId))).go();
        await (_db.delete(_db.signatures)..where((s) => s.accountId.equals(accountId))).go();
        await (_db.delete(_db.syncQueue)..where((q) => q.accountId.equals(accountId))).go();
        // Поручения и их подчинённые таблицы (внешние ключи — сначала дети).
        const sub = 'SELECT id FROM assignments WHERE account_id = ?';
        await _db.customStatement(
            'DELETE FROM assignment_votes WHERE proposal_id IN '
            '(SELECT id FROM assignment_proposals WHERE assignment_id IN ($sub))',
            [accountId]);
        for (final t in const [
          'assignment_proposals', 'assignment_participants', 'assignment_events',
          'assignment_meetings', 'assignment_reports',
        ]) {
          await _db.customStatement('DELETE FROM $t WHERE assignment_id IN ($sub)', [accountId]);
        }
        await _db.customStatement('DELETE FROM assignments WHERE account_id = ?', [accountId]);
        await (_db.delete(_db.accounts)..where((a) => a.id.equals(accountId))).go();
      });
  }

  /// Забыть всё состояние синхронизации аккаунта (SyncKey ActiveSync,
  /// состояние дельты EWS, отметки перечитывания календаря) — тогда
  /// следующая синхронизация загрузит ящик с нуля. Ключи лежат в
  /// SharedPreferences: «…_<аккаунт>_<папка>».
  Future<void> clearSyncState(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().toList()) {
        final isSyncKey = k.startsWith('synctok_') || k.startsWith('ews_delta_') || k.startsWith('calfull_');
        if (isSyncKey && k.contains('_${accountId}_') ||
            k == 'calfull_req_$accountId' ||
            k == 'easfolders_$accountId') {
          await prefs.remove(k);
        }
      }
      _ref?.read(mailEngineServiceProvider).disconnect(accountId);
    } catch (e) {
      AppLogger.warning('Сброс состояния синхронизации $accountId: $e');
    }
  }

  /// Обновить аккаунт
  Future<void> updateAccount(AccountModel account) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(account.id)))
        .write(AccountsCompanion(
      displayName: Value(account.displayName),
      // Логин тоже: раньше его нельзя было поменять без удаления ящика.
      username: Value(account.username),
      domain: Value(account.domain),
      exchangeServer: Value(account.exchangeServer),
      ewsUrl: Value(account.ewsUrl),
      imapServer: Value(account.imapServer),
      imapPort: Value(account.imapPort),
      smtpServer: Value(account.smtpServer),
      smtpPort: Value(account.smtpPort),
      syncInterval: Value(account.syncInterval.index),
      syncOnlyWifi: Value(account.syncOnlyWifi),
      syncDays: Value(account.syncDays),
      isActive: Value(account.isActive),
      isPrimary: Value(account.isPrimary),
      signatureId: Value(account.signatureId),
    ));

    state = state.map((a) => a.id == account.id ? account : a).toList();
  }

  /// Рабочий / личный ('work' / 'personal'; null — автоматически по типу).
  Future<void> setAccountKind(String accountId, String? kind) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(accountKind: Value(kind)));
    state = [
      for (final a in state)
        if (a.id == accountId) a.copyWith(accountKind: kind, clearAccountKind: kind == null) else a,
    ];
  }

  /// Назначить основной аккаунт (для отправки по умолчанию)
  Future<void> setPrimary(String accountId) async {
    for (final a in state) {
      await (_db.update(_db.accounts)..where((x) => x.id.equals(a.id)))
          .write(AccountsCompanion(isPrimary: Value(a.id == accountId)));
    }
    state = state.map((a) => a.copyWith(isPrimary: a.id == accountId)).toList();
    AppLogger.info('Основной аккаунт: $accountId');
  }

  /// Полная пересинхронизация: очищает локальные письма/папки аккаунта
  /// и помечает для полной загрузки при следующей синхронизации.
  ///
  /// Календарь, контакты, задачи и заметки тоже перекачиваются (09.10.2026:
  /// раньше контакты оставались прежними — «пересинхронизация не помогает»).
  /// Только то, что хранится на сервере: у IMAP без CalDAV задачи живут лишь
  /// на устройстве, заметки без serverId — тоже; их удаление было бы потерей.
  /// Удаляются личные контакты ящика; избранные и VIP, контакты из переписки,
  /// с телефона и кэш адресной книги организации остаются.
  Future<void> fullResync(String accountId) async {
    try {
      final acc0 = state.where((a) => a.id == accountId).firstOrNull;
      final pimOnServer = acc0 != null &&
          (acc0.usesEas || acc0.usesEws || DavPimService.providerOf(acc0) != null);
      await (_db.delete(_db.emails)..where((e) => e.accountId.equals(accountId))).go();
      await (_db.delete(_db.folders)..where((f) => f.accountId.equals(accountId))).go();
      await (_db.delete(_db.calendarEvents)..where((c) => c.accountId.equals(accountId))).go();
      if (pimOnServer) {
        await (_db.delete(_db.tasks)..where((t) => t.accountId.equals(accountId))).go();
        await (_db.delete(_db.contacts)
              ..where((c) =>
                  c.accountId.equals(accountId) &
                  c.isFavorite.equals(false) &
                  c.isVip.equals(false) &
                  c.source.equals(ContactSource.personal.index)))
            .go();
      }
      await (_db.delete(_db.notes)..where((n) => n.accountId.equals(accountId) & n.serverId.isNotNull())).go();
      await DavPimService.forgetAccount(accountId);
      await _db.customStatement('DELETE FROM emails_fts WHERE account_id = ?', [accountId]);
      // Изменения писем и задач в очереди относятся к только что удалённым
      // строкам — после пересинхронизации они бессмысленны и «висели» в
      // очереди навсегда. Письма к отправке не трогаем.
      await (_db.delete(_db.syncQueue)
            ..where((q) =>
                q.accountId.equals(accountId) &
                q.operationType.isNotIn(const ['send_email', 'send_pending', 'send_inflight', 'send_failed'])))
          .go();
      // Токены синхронизации лежат НЕ в папках, а в SharedPreferences (и в
      // памяти движка) — раньше они оставались, и «полная» пересинхронизация
      // запрашивала у сервера только изменения: ящик оставался пустым.
      await clearSyncState(accountId);
      // Контакты и календарь — тоже целиком (1.8.0, владелец 26.10.2026:
      // «полная пересинхронизация на контакты и календарь вообще не
      // действует»). Сервер присылает всё заново: изменённые контакты
      // обновятся, удалённые уйдут, встречи развернутся на год вперёд.
      final r0 = _ref;
      if (acc0 != null && r0 != null) {
        final engine = r0.read(mailEngineServiceProvider);
        await engine.requestFullContactsResync(acc0);
        await engine.requestFullCalendarResync(acc0);
      }
      AppLogger.info('Полная пересинхронизация запущена: $accountId');
      // Раньше на этом всё и заканчивалось: данные удалены, а загрузка ждала
      // планового синка (до часа) — кнопка «ничего не делала», ящик был пуст.
      final acc = state.where((a) => a.id == accountId).firstOrNull;
      final r = _ref;
      if (acc != null && r != null) unawaited(r.read(syncServiceProvider).syncAccount(acc));
    } catch (e, stack) {
      AppLogger.error('Ошибка пересинхронизации', e, stack);
    }
  }

  /// Обновить количество непрочитанных
  Future<void> updateUnreadCount(String accountId, int count) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(accountId)))
        .write(AccountsCompanion(unreadCount: Value(count)));

    state = state.map((a) {
      if (a.id == accountId) return a.copyWith(unreadCount: count);
      return a;
    }).toList();
  }

  /// Изменить порядок аккаунтов
  /// Порядок — везде, где ящики идут списком: меню почты (аватарки), общая
  /// лента, выбор отправителя, переключатель ящиков, настройки.
  Future<void> reorderAccounts(List<String> accountIds) async {
    // Сразу в состоянии — без мигания списка, пока пишется база.
    final byId = {for (final a in state) a.id: a};
    state = [
      for (final id in accountIds)
        if (byId[id] != null) byId[id]!,
      ...state.where((a) => !accountIds.contains(a.id)),
    ];
    await _db.transaction(() async {
      for (int i = 0; i < accountIds.length; i++) {
        await (_db.update(_db.accounts)..where((a) => a.id.equals(accountIds[i])))
            .write(AccountsCompanion(sortOrder: Value(i)));
      }
    });
    AppLogger.info('Порядок аккаунтов изменён');
  }
}

// ════════════════════════ ПАПКИ ════════════════════════

/// Текущая выбранная папка
final selectedFolderIdProvider = StateProvider<String?>((ref) => null);


/// Список писем в режиме выбора. Оболочка прячет кнопку «Написать»: она
/// плавала поверх нижней панели действий выбора и закрывала её кнопки.
final mailSelectionActiveProvider = StateProvider<bool>((ref) => false);

/// Лента писем хочет обработать «Назад» сама (выбор, поиск, папка, фильтр,
/// прокрутка) — оболочка не закрывает приложение, а передаёт нажатие ленте
/// через [mailBackRequestProvider].
final mailBackHandlerProvider = StateProvider<bool>((ref) => false);
final mailBackRequestProvider = StateProvider<int>((ref) => 0);

/// Режим Unified Inbox (один аккаунт)
final unifiedModeProvider = StateProvider<bool>((ref) => true);

/// Режим All Accounts (все аккаунты в одной ленте)
final allAccountsModeProvider = StateProvider<bool>((ref) => false);

/// Строка БД → модель папки (одно место вместо копий по провайдерам).
FolderModel folderFromRow(Folder row) => FolderModel(
      id: row.id,
      accountId: row.accountId,
      parentId: row.parentId,
      displayName: row.displayName,
      type: FolderType.values[row.type],
      serverPath: row.serverPath,
      unreadCount: row.unreadCount,
      totalCount: row.totalCount,
      showInUnified: row.showInUnified,
      isFavorite: row.isFavorite,
      sortOrder: row.sortOrder,
      isSynced: row.isSynced,
      iconName: row.iconName,
    );

/// Папки конкретного аккаунта — живой поток из базы. Экраны, открытые для
/// определённого ящика (настройки синхронизации папок), берут папки отсюда,
/// а не из [foldersProvider]: тот всегда про активный ящик, и экран
/// «Синхронизация папок» любого аккаунта показывал папки Exchange.
final accountFoldersProvider =
    StreamProvider.family<List<FolderModel>, String>((ref, accountId) {
  return _watchFolders(ref.watch(databaseProvider), accountId);
});

Stream<List<FolderModel>> _watchFolders(AppDatabase db, String accountId) {
  return (db.select(db.folders)
        ..where((f) => f.accountId.equals(accountId))
        ..orderBy([(f) => OrderingTerm(expression: f.sortOrder, mode: OrderingMode.asc)]))
      .watch()
      .map((rows) => rows.map(folderFromRow).toList());
}

/// Папки активного аккаунта. Поток, а не разовый запрос: избранное,
/// переименование и новые папки появляются в меню без ручного обновления.
final foldersProvider = StreamProvider<List<FolderModel>>((ref) {
  final accountId = ref.watch(activeAccountProvider.select((a) => a?.id));
  if (accountId == null) return Stream.value(const <FolderModel>[]);
  return _watchFolders(ref.watch(databaseProvider), accountId);
});

/// Непрочитанные по папкам аккаунта (folder_id → число) — из базы, живые.
final folderUnreadProvider =
    StreamProvider.family<Map<String, int>, String>((ref, accountId) {
  return ref.watch(databaseProvider).watchFolderUnread(accountId);
});

// ════════════════════════ ПИСЬМА (ПАГИНАЦИЯ) ════════════════════════

/// Состояние пагинации писем
class EmailListState {
  final List<EmailModel> emails;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int currentPage;
  final String? error;

  const EmailListState({
    this.emails = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
  });

  EmailListState copyWith({
    List<EmailModel>? emails,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? currentPage,
    String? error,
  }) {
    return EmailListState(
      emails: emails ?? this.emails,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error,
    );
  }
}

/// Размер страницы
const int _pageSize = 30;

/// Максимум писем в памяти (контроль RAM)
const int _maxInMemory = 2000;

/// Спец-фильтр списка писем (избранные категории из drawer).
/// Фильтры списка писем.
///
/// `toMe` отвечает на частый вопрос при разборе: «что адресовано лично мне, а
/// что прислали для сведения». Письма, где пользователь только в копии, обычно
/// достаточно просмотреть — а личные требуют ответа.
enum MailFilter { none, unread, flagged, vip, attachments, toMe, today, control, later }
final mailFilterProvider = StateProvider<MailFilter>((ref) => MailFilter.none);
/// Фильтр по тегу (null = нет). Ортогонален mailFilterProvider.
final tagFilterProvider = StateProvider<String?>((ref) => null);
/// Сортировка списка писем.
final mailSortProvider = StateProvider<MailSort>((ref) => MailSort.dateNewest);

/// Провайдер списка писем с пагинацией
final emailsProvider = StateNotifierProvider<EmailsNotifier, EmailListState>((ref) {
  final db = ref.watch(databaseProvider);
  // Подписка только на то, что меняет СОСТАВ списка. Раньше провайдер следил
  // за всем списком аккаунтов и всеми настройками: каждая синхронизация
  // (меняет счётчик непрочитанных) и любая смена настройки пересоздавали
  // список — он мигал скелетоном, сбрасывался на первые 30 писем, и
  // прокрутка терялась.
  ref.watch(activeAccountProvider.select((a) => a?.id));
  ref.watch(accountsProvider.select((list) => [
        for (final a in list) '${a.id}:${a.isActive}:${a.sharedMailboxEmail ?? ''}',
      ].join('|')));
  final groupByConversation = ref.watch(settingsProvider.select((s) => s.groupByConversation));
  final account = ref.read(activeAccountProvider);
  final accounts = ref.read(accountsProvider);
  final folderId = ref.watch(selectedFolderIdProvider);
  final isUnified = ref.watch(unifiedModeProvider);
  final allAccounts = ref.watch(allAccountsModeProvider);
  final filter = ref.watch(mailFilterProvider);
  final tagFilter = ref.watch(tagFilterProvider);
  final sort = ref.watch(mailSortProvider);

  return EmailsNotifier(
    ref: ref,
    db: db,
    account: account,
    accounts: accounts,
    folderId: folderId,
    isUnified: isUnified,
    allAccountsMode: allAccounts,
    groupAccountIds: ref.watch(activeGroupAccountIdsProvider),
    groupByConversation: groupByConversation,
    filter: filter,
    tagFilter: tagFilter,
    sortBy: sort,
  );
});

class EmailsNotifier extends StateNotifier<EmailListState> {
  final Ref ref;
  final AppDatabase db;
  final AccountModel? account;
  final List<AccountModel> accounts;
  final String? folderId;
  final bool isUnified;
  final bool allAccountsMode;

  /// Аккаунты активной группы. Пустой список — группировка не используется.
  /// Когда группа выбрана, она имеет приоритет над «все аккаунты»: человек
  /// осознанно ограничил область, и показывать сверх неё нельзя.
  final List<String> groupAccountIds;
  final bool groupByConversation;
  final MailFilter filter;
  final String? tagFilter;
  final MailSort sortBy;

  EmailsNotifier({
    required this.ref,
    required this.db,
    this.account,
    required this.accounts,
    this.folderId,
    required this.isUnified,
    required this.allAccountsMode,
    this.groupAccountIds = const [],
    required this.groupByConversation,
    this.filter = MailFilter.none,
    this.tagFilter,
    this.sortBy = MailSort.dateNewest,
  }) : super(const EmailListState()) {
    _subscribe();
  }

  /// Подписка на БД. Окно растёт при пагинации; поток переизлучает данные при
  /// ЛЮБОМ изменении таблицы писем — фоновая синхронизация, локальные действия
  /// (прочитано/флаг/удаление), разбор офлайн-очереди. Интерфейс не ждёт сеть.
  StreamSubscription<List<Email>>? _sub;
  int _window = _pageSize;
  Timer? _emitTimer;
  List<Email>? _pendingRows;
  bool _firstEmit = true;

  /// Папки вне сводной ленты по ТИПУ (корзина, спам, черновики, исходящие),
  /// с учётом аккаунта. Раньше исключение шло только по именам папок
  /// («Корзина», «Deleted Items»…) — папки с другим именем и письма,
  /// перенесённые в спам, оставались в ленте.
  Map<String, List<String>> _excluded = const {};

  Future<void> _loadExcludedFolders() async {
    try {
      const types = [FolderType.trash, FolderType.junk, FolderType.drafts, FolderType.outbox];
      final rows = await (db.select(db.folders)
            ..where((f) => f.type.isIn([for (final t in types) t.index])))
          .get();
      final map = <String, List<String>>{};
      for (final r in rows) {
        (map[r.accountId] ??= []).add(r.id);
      }
      _excluded = map;
    } catch (_) {}
  }

  EmailListFilter _sqlFilter() {
    final now = DateTime.now();
    final unifiedView = groupAccountIds.isNotEmpty || allAccountsMode || isUnified || folderId == null;
    return EmailListFilter(
      unread: filter == MailFilter.unread,
      flagged: filter == MailFilter.flagged,
      control: filter == MailFilter.control,
      later: filter == MailFilter.later,
      attachments: filter == MailFilter.attachments,
      vip: filter == MailFilter.vip,
      vipEmails: filter == MailFilter.vip
          ? [for (final v in ref.read(focusModeProvider).vipEmails) v.trim().toLowerCase()]
          : const [],
      vipKeywords: filter == MailFilter.vip
          ? [for (final v in ref.read(focusModeProvider).vipKeywords) v.trim().toLowerCase()]
          : const [],
      since: filter == MailFilter.today ? DateTime(now.year, now.month, now.day) : null,
      // «Мне» — точная проверка в памяти по всем адресам ящика письма
      // (адрес входа, основной с сервера, алиасы); SQL по одному адресу
      // отсекал письма на основной адрес и письма других ящиков.
      toMe: null,
      tag: tagFilter,
      excludedFolders: unifiedView ? _excluded : const {},
    );
  }

  void _subscribe() {
    _sub?.cancel();
    _emitTimer?.cancel();
    () async {
      if (_firstEmit) await _loadExcludedFolders();
      if (!mounted) return;
      final stream = _watchWindow(_window);
      if (stream == null) {
        state = const EmailListState(isLoading: false, emails: []);
        return;
      }
      _sub = stream.listen(
        (rows) {
          if (!mounted) return;
          // Во время синхронизации таблица писем меняется десятки раз в
          // секунду, и поток переизлучает всё окно на каждое изменение.
          // Первую порцию показываем сразу, последующие — не чаще раза в
          // 250 мс (последняя побеждает): без этого список дёргался.
          if (_firstEmit) {
            _firstEmit = false;
            _emit(rows);
            return;
          }
          _pendingRows = rows;
          _emitTimer ??= Timer(const Duration(milliseconds: 250), () {
            _emitTimer = null;
            final r = _pendingRows;
            _pendingRows = null;
            if (r != null && mounted) _emit(r);
          });
        },
        onError: (Object e, StackTrace st) {
          AppLogger.error('Emails: ошибка потока писем', e, st);
          if (mounted) state = EmailListState(isLoading: false, error: e.toString());
        },
      );
    }();
  }

  /// Письма, скрытые из списка до выполнения отложенного действия (удаление
  /// или архивирование с «Отменить»). Ключ — «аккаунт|id».
  final Set<String> _hidden = {};
  List<Email> _lastRows = const [];

  void hideLocally(EmailModel e) {
    _hidden.add('${e.accountId}|${e.id}');
    if (mounted) {
      state = state.copyWith(
          emails: state.emails.where((x) => !(x.id == e.id && x.accountId == e.accountId)).toList());
    }
  }

  void unhideLocally(EmailModel e) {
    // В режиме поиска (_sub == null) список строится не из потока — только
    // снимаем отметку.
    if (_hidden.remove('${e.accountId}|${e.id}') && mounted && _sub != null) _emit(_lastRows);
  }

  bool _groupLogged = false;

  void _emit(List<Email> rows) {
    _lastRows = rows;
    // Группа ящиков: в журнал — сколько писем каждого ящика попало в ленту
    // (1.6.27, замечание «письма только с одного ящика»).
    if (groupAccountIds.isNotEmpty && !_groupLogged) {
      _groupLogged = true;
      final per = <String, int>{for (final id in groupAccountIds) id: 0};
      for (final r in rows) {
        per[r.accountId] = (per[r.accountId] ?? 0) + 1;
      }
      final names = {for (final a in accounts) a.id: a.email};
      AppLogger.info('Группа ящиков: ${per.entries.map((e) => '${SecurityUtils.maskEmail(names[e.key] ?? e.key)} ${e.value}').join(', ')}'
          '${per.keys.any((id) => !names.containsKey(id)) ? ' (в группе есть удалённый ящик)' : ''}'
          '${accounts.any((a) => per.containsKey(a.id) && !a.isActive) ? ' (есть выключенный ящик)' : ''}');
    }
    var filtered = _dedupByMessageId(_applyFilters(rows)
        .where((e) => _hidden.isEmpty || !_hidden.contains('${e.accountId}|${e.id}')))
        .toList();
    if (groupByConversation) filtered = _collapseConversations(filtered);
    state = EmailListState(
      emails: _modelsFor(filtered),
      isLoading: false,
      isLoadingMore: false,
      // Окно заполнено — вероятно, в БД есть ещё.
      hasMore: rows.length >= _window && _window < _maxInMemory,
      currentPage: (_window ~/ _pageSize) - 1,
    );
  }

  /// Одно письмо — одна строка: у Gmail письмо с ярлыком лежит и во
  /// «Входящих», и в папке ярлыка, а в общих списках («Все ящики», группа,
  /// поиск) оно показывалось дважды. Ключ — аккаунт и Message-ID; письма
  /// без Message-ID не склеиваются.
  /// Из копий оставляется та, что не в служебной папке Gmail («Вся почта»,
  /// «Важные»): иначе во «Входящих» строка была с меткой «Вся почта».
  static Iterable<Email> _dedupByMessageId(Iterable<Email> rows) => AppDatabase.dedupCopies(rows.toList());

  /// Беседы свёрнуты: из каждой беседы в списке остаётся одна строка —
  /// первая в порядке сортировки (при сортировке по дате — самое новое
  /// письмо). Нажатие на неё открывает экран беседы.
  List<Email> _collapseConversations(List<Email> rows) {
    final seen = <String>{};
    final out = <Email>[];
    for (final e in rows) {
      final conv = e.conversationId;
      if (conv == null || conv.isEmpty) {
        out.add(e);
        continue;
      }
      if (seen.add(conversationKey(e.accountId, conv))) out.add(e);
    }
    // Подпись учитывает прочитанность и «На контроле»: изменились — сводка
    // бесед (непрочитанные внутри, отметка) пересчитывается.
    _loadConversationSizes(
        out, Object.hashAll(rows.map((e) => Object.hash(e.id, e.isRead, e.controlState, e.controlReplied))));
    return out;
  }

  int? _sizedSignature;

  /// Размеры видимых бесед — одним запросом, только когда набор писем
  /// изменился (переизлучение потока из-за флажка запрос не повторяет).
  void _loadConversationSizes(List<Email> visible, int signature) {
    final ids = <String>{
      for (final e in visible)
        if (e.conversationId != null && e.conversationId!.isNotEmpty) e.conversationId!,
    };
    final keys = <String>{
      for (final e in visible)
        if (e.conversationId != null && e.conversationId!.isNotEmpty)
          conversationKey(e.accountId, e.conversationId!),
    };
    if (ids.isEmpty || signature == _sizedSignature) return;
    _sizedSignature = signature;
    unawaited(() async {
      try {
        final stats = await db.conversationStats(ids);
        if (!mounted) return;
        ref.read(conversationCountProvider.notifier).merge({for (final e in stats.entries) e.key: e.value.count}, keys);
        ref.read(conversationStatsProvider.notifier).merge(stats, keys);
      } catch (e) {
        AppLogger.debug('Conversation sizes failed: $e');
      }
    }());
  }

  /// Число писем в беседах могло измениться (новое письмо, удаление):
  /// следующий вывод списка пересчитает размеры.
  void invalidateConversationSizes() => _sizedSignature = null;

  /// Поток для текущего режима списка. null — показывать нечего.
  Stream<List<Email>>? _watchWindow(int limit) {
    // Группа задаёт область явно: если она выбрана, работаем по её аккаунтам
    // независимо от режима «все/один» — иначе выбор группы ничего не значил бы.
    if (groupAccountIds.isNotEmpty) {
      final ids = accounts
          .where((a) => a.isActive && groupAccountIds.contains(a.id))
          .map((a) => a.id)
          .toList();
      if (ids.isEmpty) return null;
      return db.watchAllAccountsUnifiedPage(
          accountIds: ids, limit: limit, offset: 0, sortBy: sortBy, filter: _sqlFilter());
    }
    if (allAccountsMode) {
      final ids = accounts.where((a) => a.isActive).map((a) => a.id).toList();
      if (ids.isEmpty) return null;
      return db.watchAllAccountsUnifiedPage(
          accountIds: ids, limit: limit, offset: 0, sortBy: sortBy, filter: _sqlFilter());
    }
    final acc = account;
    if (acc == null) return null;
    if (isUnified || folderId == null) {
      return db.watchUnifiedInboxPage(
          accountId: acc.id, limit: limit, offset: 0, sortBy: sortBy, filter: _sqlFilter());
    }
    return db.watchEmailsPage(
        accountId: acc.id, folderId: folderId!, limit: limit, offset: 0, sortBy: sortBy, filter: _sqlFilter());
  }

  /// Фильтры уже выполнены в SQL (_sqlFilter); здесь — только точные
  /// проверки, которые LIKE выразить не может (тег целиком, адрес в «Кому»).
  Iterable<Email> _applyFilters(List<Email> raw) {
    Iterable<Email> result = raw;
    if (filter != MailFilter.none) {
      result = result.where((e) {
        switch (filter) {
          case MailFilter.unread: return !e.isRead;
          case MailFilter.flagged: return e.isFlagged;
          case MailFilter.control: return e.controlState > 0;
          case MailFilter.later: return e.laterState > 0;
          case MailFilter.attachments: return e.hasAttachments;
          case MailFilter.vip:
            return true; // отбор — в SQL (_sqlFilter: список VIP)
          case MailFilter.toMe:
            // Адресовано лично: пользователь в «Кому», а не только в копии.
            final acc = accounts.where((a) => a.id == e.accountId).firstOrNull ?? account;
            if (acc == null) return true;
            return emailModelFromRow(e).to.any((a) => OwnAddresses.isMine(acc, a.email));
          case MailFilter.today:
            final now = DateTime.now();
            final d = e.receivedAt.toLocal();
            return d.year == now.year && d.month == now.month && d.day == now.day;
          case MailFilter.none: return true;
        }
      });
    }
    if (tagFilter != null && tagFilter!.isNotEmpty) {
      result = result.where((e) =>
          (e.tagsStr ?? '').split(';').where((t) => t.isNotEmpty).contains(tagFilter));
    }
    return result;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _emitTimer?.cancel();
    super.dispose();
  }

  /// Полнотекстовый поиск (FTS5) с откатом на LIKE. Пустой запрос — обычная загрузка.
  /// Серверный поиск через EWS (AQS QueryString) по всему ящику.
  /// Для EWS/Exchange-аккаунтов; ошибки отдельного аккаунта не прерывают поиск.
  Future<List<EmailModel>> _serverSearchEws(String q) async {
    final targets = allAccountsMode
        ? accounts
        : (account != null ? [account!] : const <AccountModel>[]);
    // Серверный поиск: EWS (FindItem), EAS (Search cp15), IMAP (UID SEARCH).
    // Ящики — параллельно: медленный сервер одного не задерживает остальные.
    final serverTargets = targets.where((a) => TransportCapabilities.forAccount(a).serverSearch).toList();
    if (serverTargets.isEmpty) return const [];
    final svc = ref.read(mailEngineServiceProvider);
    final parts = await Future.wait([
      for (final a in serverTargets)
        svc.serverSearch(a, q, maxResults: 50).timeout(const Duration(seconds: 30)).catchError((Object e) {
          AppLogger.error('Серверный поиск (${a.email}): $e');
          return const <EmailModel>[];
        }),
    ]);
    return [for (final p in parts) ...p];
  }

  /// Найденные на сервере письма — в базу, чтобы их можно было открыть
  /// (экран письма читает его из базы). Письма ActiveSync — в псевдопапку
  /// «search» (её нет в списке папок); прежние результаты убираются.
  Future<void> _storeServerHits(List<EmailModel> hits) async {
    try {
      final accIds = {for (final h in hits) h.accountId};
      for (final a in accIds) {
        await (db.delete(db.emails)
              ..where((e) => e.accountId.equals(a) & e.folderId.equals('search')))
            .go();
      }
      for (final h in hits) {
        await db.into(db.emails).insert(
              EmailsCompanion.insert(
                id: h.id,
                accountId: h.accountId,
                folderId: h.folderId,
                fromEmail: h.from.email,
                fromName: Value(h.from.displayName),
                toRecipients: jsonEncode([for (final a in h.to) a.toMap()]),
                subject: h.subject,
                bodyPreview: Value(h.bodyPreview),
                bodyHtml: Value(h.bodyHtml),
                bodyPlain: Value(h.bodyPlain),
                receivedAt: h.receivedAt,
                // IMAP-письмо лежит в своей папке — с настоящими флагами.
                isRead: Value(h.folderId == 'search' ? true : h.isRead),
                isFlagged: Value(h.isFlagged),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    } catch (e) {
      AppLogger.debug('Результаты поиска не сохранены: $e');
    }
  }

  /// Номер последнего поиска: ответ более раннего запроса (пользователь
  /// продолжал печатать) не должен затирать результаты более позднего.
  int _searchSeq = 0;

  Future<void> search(String query) async {
    final seq = ++_searchSeq;
    final q = query.trim();
    if (q.isEmpty) {
      await loadFirstPage();
      return;
    }
    if (account == null && !allAccountsMode) return;
    // Во время поиска отписываемся от потока списка: иначе любое изменение в БД
    // (фоновая синхронизация) переизлучит письма папки и затрёт результаты
    // поиска. Подписка вернётся при сбросе поиска — search('') → loadFirstPage().
    await _sub?.cancel();
    _sub = null;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final List<dynamic> rows;
      if (allAccountsMode) {
        final all = <dynamic>[];
        for (final a in accounts) {
          all.addAll(await db.searchEmailsFts(accountId: a.id, query: q, limit: 50));
        }
        rows = all;
      } else {
        rows = await db.searchEmailsFts(accountId: account!.id, query: q, limit: 100);
      }
      if (seq != _searchSeq || !mounted) return;
      final emails = _dedupByMessageId(rows.cast<Email>()).map((r) => _rowToListModel(r)).toList();
      // Найденное на телефоне — сразу; серверный поиск — когда пользователь
      // перестал печатать (ещё 0,7 с): иначе каждая пауза в наборе уходила
      // запросом на сервер и занимала соединение ящика (у IMAP — единственное).
      state = EmailListState(emails: List.of(emails), isLoading: false, hasMore: false, currentPage: 0);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (seq != _searchSeq || !mounted) return;
      // Серверный поиск — находит письма вне локального кэша (вся почта).
      try {
        final server = await _serverSearchEws(q);
        if (server.isNotEmpty) {
          final ids = emails.map((e) => e.id).toSet();
          // Письмо ActiveSync из серверного поиска приходит с LongId, а не с
          // id папки: локальная копия того же письма показывалась вторым
          // экземпляром, и действия над «поисковым» не доходили до сервера.
          // Есть копия в папке — показываем её (все действия работают как
          // обычно); нет — найденное на сервере.
          bool same(EmailModel a, EmailModel b) =>
              a.accountId == b.accountId &&
              a.subject == b.subject &&
              a.from.email.toLowerCase() == b.from.email.toLowerCase() &&
              a.receivedAt.difference(b.receivedAt).abs() <= const Duration(minutes: 2);
          final fresh = <EmailModel>[];
          for (final h in server) {
            if (ids.contains(h.id) || emails.any((e) => same(e, h))) continue;
            if (h.folderId == 'search') {
              final twin = await findLocalTwin(db, h.accountId,
                  subject: h.subject, fromEmail: h.from.email, receivedAt: h.receivedAt);
              if (twin != null) {
                if (ids.add(twin.id)) emails.add(_rowToListModel(twin));
                continue;
              }
            }
            fresh.add(h);
          }
          emails.addAll(fresh);
          await _storeServerHits(fresh);
        }
      } catch (e) {
        AppLogger.error('Emails: серверный поиск не удался', e);
      }
      if (seq != _searchSeq || !mounted) return;
      state = EmailListState(emails: emails, isLoading: false, hasMore: false, currentPage: 0);
    } catch (e, stack) {
      if (seq != _searchSeq) return;
      AppLogger.error('Emails: ошибка поиска', e, stack);
      state = EmailListState(isLoading: false, error: e.toString());
    }
  }

  /// Сбросить список к первой странице. Данные придут из потока — ждать нечего.
  Future<void> loadFirstPage() async {
    if (!mounted) return;
    _window = _pageSize;
    _firstEmit = true;
    _subscribe();
  }

  /// Подгрузить ещё (infinite scroll): расширяем окно потока, а не докачиваем
  /// страницу вручную. Поток сам переизлучит расширенный список.
  Future<void> loadNextPage() async {
    if (!mounted || !state.hasMore || state.isLoadingMore) return;
    if (_window >= _maxInMemory) return; // предел RAM
    state = state.copyWith(isLoadingMore: true);
    // Шаг растёт с глубиной прокрутки: 30, 60, 120 … — к 2000-му письму
    // это десяток запросов, а не 66.
    _window += _window < 120 ? _pageSize : _window;
    if (_window > _maxInMemory) _window = _maxInMemory;
    _firstEmit = true;
    _subscribe();
  }


  // reloadFromDb() удалён: список подписан на поток из БД (.watch()) и сам
  // обновляется на любое изменение — включая локальные действия (прочитано,
  // флаг, удаление) и разбор офлайн-очереди. Ручное перечитывание не нужно.

  /// Мгновенно отразить изменение isRead/isFlagged в текущем списке (оптимистично),
  /// чтобы UI реагировал без ожидания БД/сервера.
  void applyLocalFlags(String emailId,
      {bool? isRead, bool? isFlagged, int? controlState, int? laterState, DateTime? remindAt, bool clearRemind = false}) {
    if (!mounted) return;
    final updated = state.emails.map((e) {
      if (e.id != emailId) return e;
      return e.copyWith(
        isRead: isRead ?? e.isRead,
        isFlagged: isFlagged ?? e.isFlagged,
        controlState: controlState ?? e.controlState,
        laterState: laterState ?? e.laterState,
        remindAt: remindAt,
        clearReminder: clearRemind,
      );
    }).toList();
    state = state.copyWith(emails: updated);
  }

  /// Обновить (pull-to-refresh)
  Future<void> refresh() async {
    if (!mounted) return;
    // Синхронизация с сервером. Скелетон — только если показывать нечего:
    // раньше «потянуть вниз» на полном списке заменяло его заглушкой и
    // сбрасывало прокрутку.
    if (state.emails.isEmpty) state = state.copyWith(isLoading: true);
    invalidateConversationSizes();
    try {
      final sync = ref.read(syncServiceProvider);

      // Пользователь открыл КОНКРЕТНУЮ папку и потянул вниз (или нажал
      // «обновить») — это явный запрос синхронизировать ИМЕННО ЕЁ. Делаем
      // разово, даже если папка отключена в настройках синхронизации:
      // техническую папку можно не тянуть автоматически, но посмотреть по
      // требованию — можно. syncSingleFolder по isSynced не фильтрует.
      final oneFolder = !allAccountsMode && !isUnified && account != null && folderId != null;
      if (oneFolder) {
        final folder = await _currentFolder();
        if (folder != null) {
          await sync.syncSingleFolder(account!, folder);
        } else {
          // Папка не найдена в БД (редко) — не молчим, обновим аккаунт целиком.
          await sync.syncAccount(account!);
        }
      } else if (allAccountsMode) {
        // «Вся почта» / все аккаунты — как и раньше, с учётом настроек папок.
        await sync.syncAll();
      } else if (account != null) {
        await sync.syncAccount(account!);
      }
    } catch (e, stack) {
      AppLogger.error('Emails: ошибка синхронизации', e, stack);
    }
    if (!mounted) return;
    // Перечитывать вручную не нужно: поток из БД уже отдал новые письма по ходу
    // синхронизации. И не сбрасываем окно — иначе после свайпа у пользователя,
    // пролиставшего список, осталась бы только первая страница.
    state = state.copyWith(isLoading: false);
  }

  /// Текущая папка списка (для разовой синхронизации по требованию).
  Future<FolderModel?> _currentFolder() async {
    final acc = account;
    final fid = folderId;
    if (acc == null || fid == null) return null;
    final row = await (db.select(db.folders)
          ..where((f) => f.id.equals(fid) & f.accountId.equals(acc.id)))
        .getSingleOrNull();
    if (row == null) return null;
    return folderFromRow(row);
  }

  /// Запрос к БД с пагинацией + применение спец-фильтра (flagged/vip/unread/attachments).
  /// Конвертация строки БД в модель
  EmailModel rowToModel(Email row) => _rowToModel(row);
  EmailModel _rowToModel(Email row) => emailModelFromRow(row);

  // Для СПИСКА: без полных тел (только превью+метаданные) — накопленный при скролле
  // список не раздувает память. Тред-вид и карточка используют _rowToModel с телом.
  EmailModel _rowToListModel(Email row) => emailModelFromRow(row).copyWith(clearBody: true);

  /// Готовые модели строк ленты: ключ — аккаунт, письмо и папка, проверка —
  /// хеш строки. Лента переизлучается при каждом изменении таблицы писем
  /// (во время синхронизации — несколько раз в секунду), и раньше каждый
  /// раз все строки окна (до 2000) заново разбирались: адреса и вложения из
  /// JSON, тема, превью (сущности HTML, стрелки Outlook) — в главном потоке.
  /// Теперь заново — только изменившиеся строки (аудит 11.10.2026).
  final Map<String, ({int hash, EmailModel model})> _models = {};

  List<EmailModel> _modelsFor(List<Email> rows) {
    final next = <String, ({int hash, EmailModel model})>{};
    final out = <EmailModel>[];
    for (final r in rows) {
      final k = '${r.accountId}|${r.id}|${r.folderId}';
      final h = r.hashCode;
      final hit = _models[k];
      final m = (hit != null && hit.hash == h) ? hit.model : _rowToListModel(r);
      next[k] = (hash: h, model: m);
      out.add(m);
    }
    _models
      ..clear()
      ..addAll(next);
    return out;
  }
}

/// Публичная конвертация строки БД в модель письма (переиспользуется в экранах).
EmailModel emailModelFromRow(Email row) {
  List<EmailAddress> parseAddresses(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((m) => EmailAddress(
            email: m['email'] ?? '',
            displayName: m['displayName'],
          )).toList();
    } catch (_) {
      return [];
    }
  }

  List<EmailAttachment> parseAttachments(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list.map((m) => EmailAttachment.fromMap(m as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  return EmailModel(
    id: row.id,
    accountId: row.accountId,
    folderId: row.folderId,
    folderName: row.folderName,
    conversationId: row.conversationId,
    parentId: row.parentId,
    internetMessageId: row.internetMessageId,
    references: row.referencesStr?.split(' ').where((s) => s.isNotEmpty).toList(),
    from: EmailAddress(email: row.fromEmail, displayName: row.fromName == null ? null : fixUtf16(row.fromName!)),
    to: parseAddresses(row.toRecipients),
    cc: parseAddresses(row.ccJson),
    bcc: parseAddresses(row.bccJson),
    // Половинки эмодзи без пары (обрезанные сервером или старой версией)
    // роняли отрисовку строки — заменяются на «�».
    subject: fixUtf16(row.subject),
    bodyPlain: decodeTextEntities(row.bodyPlain),
    bodyHtml: row.bodyHtml,
    // Стрелки Wingdings из Outlook («11:40 à 10:30») — настоящими стрелками.
    bodyPreview: row.bodyPreview == null
        ? null
        : SymbolFonts.fixPlain(fixUtf16(decodeTextEntities(row.bodyPreview)!)),
    authResults: row.authResults,
    listUnsubscribe: row.listUnsubscribe,
    meetingJson: row.meetingJson,
    controlState: row.controlState,
    laterState: row.laterState,
    controlReplied: row.controlReplied,
    followUpAt: row.followUpAt,
    attachments: parseAttachments(row.attachmentsJson),
    receivedAt: row.receivedAt,
    sentAt: row.sentAt,
    isRead: row.isRead,
    isFlagged: row.isFlagged,
    isDraft: row.isDraft,
    isReplied: row.isReplied,
    isForwarded: row.isForwarded,
    hasAttachments: row.hasAttachments,
    priority: EmailPriority.values[row.priority],
    status: EmailStatus.values[row.status],
    tags: row.tagsStr?.split(';').where((s) => s.isNotEmpty).toList() ?? [],
    categories: row.categoriesStr?.split(';').where((s) => s.isNotEmpty).toList() ?? [],
    classification: row.classification,
    sensitivity: row.sensitivity,
    sentimentScore: row.sentimentScore,
    aiCategory: row.aiCategory,
    aiRecommendation: row.aiRecommendation,
    extractedDeadline: row.extractedDeadline,
    size: row.size,
    readReceiptRequested: row.readReceiptRequested,
    isLocallyModified: row.isLocallyModified,
    cachedAt: row.cachedAt,
    remindAt: row.remindAt,
  );
}

/// Провайдер беседы (conversation thread) — в аккаунте САМОГО ПИСЬМА.
/// Раньше брался активный аккаунт: в сводной ленте беседа письма из другого
/// ящика оказывалась пустой (или чужой — при совпадении идентификаторов).
final conversationProvider = FutureProvider.family<List<EmailModel>,
    ({String conversationId, String accountId})>((ref, key) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.getConversation(
    conversationId: key.conversationId,
    accountId: key.accountId,
  );

  final notifier = ref.read(emailsProvider.notifier);
  return rows.map((r) => notifier._rowToModel(r)).toList();
});

/// Провайдер количества писем в папке
final folderEmailCountProvider = FutureProvider.family<int, String>((ref, folderId) async {
  final account = ref.watch(activeAccountProvider);
  if (account == null) return 0;

  final db = ref.watch(databaseProvider);
  return db.countEmailsInFolder(account.id, folderId);
});

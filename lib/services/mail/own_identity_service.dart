// lib/services/mail/own_identity_service.dart
// Узнать настоящие адреса и имя владельца ящика (см. own_addresses.dart):
// раз в сутки после синхронизации — у ActiveSync спросить сервер
// (UserInformation), у всех — посмотреть «Отправленные». Имя ящика,
// которое осталось логином («i.petrov»), заменяется настоящим
// («Ермишин Олег Андреевич»).

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/mail_domains.dart' show isPublicMailDomain, mailDomainOf;
import '../../data/models/account_model.dart';
import '../../data/models/folder_model.dart' show FolderType;
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import 'engine/mail_engine_service.dart';
import 'own_addresses.dart';

final ownIdentityServiceProvider = Provider<OwnIdentityService>((ref) => OwnIdentityService(ref));

/// Меняется, когда узнали новые свои адреса: фото и «свои письма» пересчитываются.
final ownAddressesRevisionProvider = StateProvider<int>((_) => 0);

class OwnIdentityService {
  final Ref _ref;
  OwnIdentityService(this._ref);

  /// Имя ящика «пустое» — логин, адрес или его начало: его можно заменить.
  static bool isPlaceholderName(AccountModel a) {
    final n = a.displayName.trim().toLowerCase();
    if (n.isEmpty) return true;
    final email = a.email.toLowerCase();
    final local = email.split('@').first;
    final user = a.username.toLowerCase();
    return n == email || n == local || n == user || n == user.split('\\').last || n.contains('@');
  }

  Future<void> learn(AccountModel account, {bool force = false}) async {
    final prefs = _ref.read(sharedPrefsProvider);
    final key = 'own_learned_at_${account.id}';
    final last = prefs.getInt(key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - last < const Duration(hours: 24).inMilliseconds) return;
    await prefs.setInt(key, now);

    String? name;
    var changed = false;
    var serverOk = false;
    // 1. ActiveSync: сервер знает все адреса ящика и имя.
    if (account.usesEas) {
      try {
        final info = await _ref.read(mailEngineServiceProvider).easUserInfo(account);
        if (info != null) {
          // Сервер знает адреса точно — его список заменяет узнанное раньше
          // (в т. ч. ошибочно узнанное по «Отправленным»).
          final server = {
            for (final a in [if (info.primary != null) info.primary!, ...info.addresses])
              if (a.contains('@')) a.trim().toLowerCase(),
          };
          final before = OwnAddresses.learned(account.id).toSet();
          if (server.isNotEmpty && (server.length != before.length || !server.containsAll(before))) {
            await OwnAddresses.forget(account.id);
            await OwnAddresses.remember(account.id, server);
            changed = true;
          }
          name = info.displayName;
          serverOk = true;
        }
      } catch (e) {
        AppLogger.debug('UserInformation: $e');
      }
    }
    // 2. «Отправленные»: адрес и имя отправителя своих писем.
    try {
      final db = _ref.read(databaseProvider);
      final sentIds = await (db.selectOnly(db.folders)
            ..addColumns([db.folders.id])
            ..where(db.folders.accountId.equals(account.id) & db.folders.type.equals(FolderType.sent.index)))
          .map((r) => r.read(db.folders.id)!)
          .get();
      if (sentIds.isNotEmpty) {
        final rows = await (db.select(db.emails)
              ..where((e) => e.accountId.equals(account.id) & e.folderId.isIn(sentIds))
              ..orderBy([(e) => OrderingTerm(expression: e.receivedAt, mode: OrderingMode.desc)])
              ..limit(200))
            .get();
        final byAddr = <String, int>{};
        final byName = <String, int>{};
        for (final r in rows) {
          final a = r.fromEmail.trim().toLowerCase();
          if (!a.contains('@')) continue;
          byAddr[a] = (byAddr[a] ?? 0) + 1;
          final n = (r.fromName ?? '').trim();
          if (n.isNotEmpty && !n.contains('@')) byName[n] = (byName[n] ?? 0) + 1;
        }
        // Адрес, с которого ушло хотя бы три письма, — свой, но только с тем
        // же именем до «@», что и логин (опечатка в домене при входе). Иначе
        // заместитель, отправляющий от имени руководителя или общего ящика,
        // «присвоил» бы чужой адрес: письма от него перестали бы уведомлять.
        // Адреса с сервера (ActiveSync) точнее — тогда «Отправленные» дают
        // только имя. Личный ящик общедоступной почты (iCloud, Gmail,
        // Яндекс, Mail.ru…, 1.8.13) от имени другого не пишет: свой — любой
        // адрес из трёх писем и больше (алиас iCloud с другим именем,
        // «Отправлять как» в Gmail). Иначе свои письма с алиаса считались
        // чужими: беседа «чата» стояла не той стороной, и беседы по теме не
        // складывались.
        final local = account.email.split('@').first.trim().toLowerCase();
        final personal = !account.usesEas && !account.usesEws && isPublicMailDomain(mailDomainOf(account.email));
        final mine = serverOk
            ? const <String>[]
            : [
                for (final e in byAddr.entries)
                  if (e.value >= 3 && (personal || e.key.split('@').first == local)) e.key,
              ];
        changed |= await OwnAddresses.remember(account.id, mine);
        if (name == null && byName.isNotEmpty) {
          final top = byName.entries.reduce((a, b) => a.value >= b.value ? a : b);
          if (top.value >= 3) name = top.key;
        }
      }
    } catch (e) {
      AppLogger.debug('Свои адреса по «Отправленным»: $e');
    }
    if (changed) {
      AppLogger.info('Свои адреса ${AppLogger.mask(account.email)}: ${OwnAddresses.learned(account.id).length}');
      _ref.read(ownAddressesRevisionProvider.notifier).state++;
    }

    // 3. Имя ящика — настоящее, если сейчас там логин.
    final fresh = _ref.read(accountsProvider).where((a) => a.id == account.id).firstOrNull ?? account;
    final n = name?.trim() ?? '';
    final fixName = n.isNotEmpty && isPlaceholderName(fresh);
    // Адрес входа не меняем: он же логин для сервера. Если при входе была
    // опечатка, свои письма всё равно узнаются — по адресам с сервера.
    if (fixName) {
      await _ref.read(accountsProvider.notifier).updateAccount(fresh.copyWith(displayName: n));
      AppLogger.info('Имя ящика ${AppLogger.mask(account.email)} — с сервера');
    } else if (changed) {
      // Адреса поменялись — пересобрать то, что от них зависит (фото, свои письма).
      await _ref.read(accountsProvider.notifier).reload();
    }
  }
}

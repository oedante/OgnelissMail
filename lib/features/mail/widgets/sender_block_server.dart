// lib/features/mail/widgets/sender_block_server.dart
//
// Блокировка отправителя ещё и правилом на сервере (1.10.x): письма уходят
// в «Спам» сразу на сервере — и на других устройствах, и пока телефон
// выключен. Где сервер это умеет:
//  · IMAP с ManageSieve — правило в скрипте Sieve (как «Фильтры на сервере»);
//  · Exchange — правило Exchange через Graph (Microsoft 365) или EWS.
// Gmail, Яндекс, Mail.ru и другие службы без Sieve — только на устройстве
// (ServerFilters.kindOf → webOnly, переключатель в шторке не показывается).

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/mail/server_filters.dart';
import '../../../services/mail/sieve/sieve_rules.dart';
import '../../../services/mail/sieve/sieve_service.dart';
import '../../../services/mail/special_folders.dart';
import '../../settings/screens/exchange_tools_screen.dart' show serverToolsFor;

/// Слова, по которым узнаётся «Спам» в списке папок правил Exchange.
const _junkNames = {
  'junk', 'junk email', 'junk e-mail', 'spam', 'нежелательная почта', 'спам', 'bulk mail',
};

/// Создать на сервере правило «письма от [pattern] — в Спам». null —
/// создано; иначе короткая причина (для журнала).
Future<String?> blockOnServer(WidgetRef ref, AccountModel account, String pattern) async {
  final p = pattern.trim().toLowerCase();
  final label = p.contains('@') ? p : '@$p';
  final db = ref.read(databaseProvider);
  final junkId = await SpecialFolders.resolve(db, ref.read(sharedPrefsProvider), account.id, SpecialKind.junk);
  try {
    switch (ServerFilters.kindOf(account)) {
      case ServerFilterKind.webOnly:
        return 'webOnly';
      case ServerFilterKind.sieve:
        if (junkId == null) return 'noJunk';
        final row = await (db.select(db.folders)
              ..where((f) => f.accountId.equals(account.id) & f.id.equals(junkId)))
            .getSingleOrNull();
        final path = decodeImapUtf7(row?.serverPath ?? junkId);
        final svc = ref.read(sieveServiceProvider);
        final st = await svc.load(account);
        final rule = SieveRule(
          name: 'Ogneliss: $label',
          field: SieveField.from,
          op: SieveOp.contains,
          value: p,
          action: SieveAction.move,
          arg: path,
          stop: true,
        );
        // Уже есть такое же — не дублировать.
        if (st.rules.any((r) => r.field == SieveField.from && r.value == p && r.action == SieveAction.move)) {
          return null;
        }
        await svc.saveRules(account, st, [...st.rules, rule]);
        AppLogger.info('Блокировка на сервере (Sieve): ${AppLogger.mask(p)}');
        return null;
      case ServerFilterKind.exchange:
        final t = await serverToolsFor(ref, account);
        if (t == null) return 'noTools';
        final folders = await t.tools.ruleFolders(t.account);
        String? junkLabel;
        if (junkId != null) {
          final row = await (db.select(db.folders)
                ..where((f) => f.accountId.equals(account.id) & f.id.equals(junkId)))
              .getSingleOrNull();
          junkLabel = row?.displayName.toLowerCase().trim();
        }
        final target = folders.where((f) => f.label.toLowerCase().trim() == junkLabel).firstOrNull ??
            folders.where((f) => _junkNames.contains(f.label.toLowerCase().trim())).firstOrNull;
        if (target == null) return 'noJunk';
        final err = await t.tools.createRule(
          t.account,
          SieveRule(
            name: 'Ogneliss: $label',
            field: SieveField.from,
            op: SieveOp.contains,
            value: p,
            action: SieveAction.move,
            arg: target.id,
            stop: true,
          ),
          priority: 1,
        );
        if (err == null) AppLogger.info('Блокировка на сервере (Exchange): ${AppLogger.mask(p)}');
        return err;
    }
  } catch (e) {
    AppLogger.warning('Блокировка на сервере не создана: $e');
    return 'error';
  }
}

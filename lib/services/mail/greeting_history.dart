// lib/services/mail/greeting_history.dart
// Писали ли вы уже в этой переписке — для короткого приветствия в ответе
// («Максим Геннадьевич,» вместо «Добрый день, Максим Геннадьевич,»).
//
// Просьба владельца 25.10.2026: «даже если пользователь отвечает во второй
// или третий раз — всё равно полное приветствие». Своё письмо в переписке
// ищется в базе телефона: то же conversationId (Exchange, Gmail, беседы
// IMAP) или Message-ID из цепочки References отвечаемого письма — от
// любого своего адреса ящика (адрес входа, основной с сервера, алиасы).

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/account_model.dart';
import 'own_addresses.dart';

abstract final class GreetingHistory {
  /// Message-ID из строки References / In-Reply-To: «<a@b> <c@d>» → с
  /// угловыми скобками и без (в базе бывает и так и так).
  static Set<String> messageIds(String? refs) {
    final out = <String>{};
    for (final m in RegExp(r'<?([^<>\s]+@[^<>\s]+)>?').allMatches(refs ?? '')) {
      final id = m.group(1)!;
      out
        ..add(id)
        ..add('<$id>');
    }
    return out;
  }

  /// Вы уже писали в переписке письма [parent] (отвечаемого): оно само ваше,
  /// или в базе есть ваше письмо той же беседы, или ваше письмо в его
  /// цепочке References. Ошибка базы — false (полное приветствие).
  static Future<bool> wroteBefore(AppDatabase db, AccountModel account, Email parent) async {
    if (OwnAddresses.isMine(account, parent.fromEmail)) return true;
    final mine = OwnAddresses.of(account).toList();
    if (mine.isEmpty) return false;
    try {
      final e = db.emails;
      Future<bool> any(Expression<bool> where) async {
        final q = db.selectOnly(e)
          ..addColumns([e.id])
          ..where(e.accountId.equals(account.id) & e.isDraft.equals(false) & e.fromEmail.lower().isIn(mine) & where)
          ..limit(1);
        return (await q.getSingleOrNull()) != null;
      }

      final conv = parent.conversationId?.trim() ?? '';
      if (conv.isNotEmpty && await any(e.conversationId.equals(conv))) return true;
      final ids = messageIds(parent.referencesStr);
      if (ids.isNotEmpty && await any(e.internetMessageId.isIn(ids))) return true;
    } catch (err) {
      AppLogger.debug('Приветствие: свои письма в переписке не найдены: $err');
    }
    return false;
  }
}

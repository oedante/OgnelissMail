// lib/services/mail/mention_scanner.dart
// Проверка @-упоминаний (2.2.0, план 08.11.2026 «из мессенджеров»: значок
// «@» в ленте и фильтр «Упоминания»).
//
// Не в синхронизации: текст письма приходит разными путями (синхронизация
// Exchange, загрузка IMAP заранее, открытие письма). Сканер слушает таблицу
// писем и через несколько секунд затишья проверяет письма ящика, текст
// которых уже на устройстве, а отметки ещё нет (mentions_me IS NULL).
// Проверка — Mentions.mentionsMe в отдельном изоляте, пачками; свои письма
// (отправитель — свой адрес) не упоминают сами себя. Письмо без текста
// остаётся непроверенным, пока текст не придёт.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/mentions.dart';
import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import 'own_addresses.dart';

/// Письмо для проверки и адреса и имена владельца ящика.
typedef MentionJob = ({
  List<({String id, String? html, String? plain})> mails,
  List<String> emails,
  List<String> names,
});

/// Проверить пачку (в отдельном изоляте): id письма → упомянут ли.
Map<String, bool> scanMentions(MentionJob job) => {
      for (final m in job.mails)
        m.id: Mentions.mentionsMe(html: m.html, text: m.plain, emails: job.emails, names: job.names),
    };

class MentionScanner {
  MentionScanner(this._ref);
  final Ref _ref;

  /// Писем за раз и за сколько дней.
  static const batch = 60;
  static const lookBack = Duration(days: 60);

  StreamSubscription<Set<TableUpdate>>? _sub;
  Timer? _quiet;
  bool _running = false;
  bool _again = false;

  /// Слушать таблицу писем (main.dart, при запуске приложения).
  void start() {
    if (kIsWeb || _sub != null) return;
    final db = _ref.read(databaseProvider);
    _sub = db.tableUpdates(TableUpdateQuery.onTable(db.emails)).listen((_) => _schedule());
    _schedule();
  }

  void _schedule() {
    _quiet?.cancel();
    _quiet = Timer(const Duration(seconds: 4), () => unawaited(run()));
  }

  /// Проверить непроверенные письма всех ящиков (пачками, пока есть).
  @visibleForTesting
  Future<void> run() async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      final db = _ref.read(databaseProvider);
      for (final account in _ref.read(accountsProvider)) {
        final own = OwnAddresses.of(account).map((e) => e.toLowerCase()).toList();
        final names = [if (account.displayName.trim().isNotEmpty) account.displayName.trim()];
        for (var round = 0; round < 20; round++) {
          final rows = await (db.select(db.emails)
                ..where((e) =>
                    e.accountId.equals(account.id) &
                    e.mentionsMe.isNull() &
                    (e.bodyHtml.isNotNull() | e.bodyPlain.isNotNull()) &
                    e.receivedAt.isBiggerThanValue(DateTime.now().subtract(lookBack)))
                ..limit(batch))
              .get();
          if (rows.isEmpty) break;
          final result = await compute(scanMentions, (
            mails: [
              for (final r in rows)
                // Своё письмо себя не упоминает.
                (id: r.id, html: own.contains(r.fromEmail.toLowerCase()) ? null : r.bodyHtml,
                    plain: own.contains(r.fromEmail.toLowerCase()) ? null : r.bodyPlain),
            ],
            emails: own,
            names: names,
          ));
          await db.batch((b) {
            for (final e in result.entries) {
              b.update(db.emails, EmailsCompanion(mentionsMe: Value(e.value)),
                  where: ($EmailsTable t) => t.id.equals(e.key) & t.accountId.equals(account.id));
            }
          });
          final found = result.values.where((v) => v).length;
          if (found > 0) AppLogger.info('Упоминания: ${account.email} — $found из ${rows.length}');
          if (rows.length < batch) break;
        }
      }
    } catch (e) {
      AppLogger.debug('Упоминания: $e');
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        _schedule();
      }
    }
  }

  void dispose() {
    _quiet?.cancel();
    unawaited(_sub?.cancel());
  }
}

final mentionScannerProvider = Provider<MentionScanner>((ref) {
  final s = MentionScanner(ref);
  ref.onDispose(s.dispose);
  return s;
});

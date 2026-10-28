// lib/widgets/common/queue_sheet.dart
//
// Что стоит в очереди и что с этим сделать. Раньше по нажатию на значок
// очереди было только «В очереди: N» — ни что это, ни как от него
// избавиться. Письма, помеченные «не отправлено», висели там вечно (даже
// после полной пересинхронизации), и счётчик не пропадал.
//
// Здесь: письма к отправке (с темой, временем и ошибкой) — «Отправить
// сейчас», «Удалить»; не отправленные — «Отправить снова», «В черновики»
// (1.7.2+114: поправить письмо, например уменьшить фото, которое не
// пропустил шлюз), «Удалить»; изменения писем и задач — «Повторить» или
// «Отменить».

import 'dart:convert';
import '../../core/theme/app_icons.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'app_sheet.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../data/providers/database_provider.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../services/mail/offline_send_service.dart';
import '../../services/sync/sync_service.dart';

const _sendTypes = {'send_email', 'send_pending', 'send_inflight', 'send_failed'};

Future<void> showQueueSheet(BuildContext context) async {
  // Записи удалённых аккаунтов никому не нужны и только держат счётчик.
  try {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(databaseProvider).customStatement(
        'DELETE FROM sync_queue WHERE account_id NOT IN (SELECT id FROM accounts)');
  } catch (_) {}
  if (!context.mounted) return;
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerStatefulWidget {
  const _QueueSheet();

  @override
  ConsumerState<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends ConsumerState<_QueueSheet> {
  late Future<List<SyncQueueData>> _ops = _load();
  bool _busy = false;

  /// Строка под заголовком: чем кончилось «В черновики».
  String? _note;

  Future<List<SyncQueueData>> _load() {
    final db = ref.read(databaseProvider);
    return (db.select(db.syncQueue)
          ..orderBy([(q) => OrderingTerm(expression: q.createdAt)])
          ..limit(200))
        .get();
  }

  void _reload() => setState(() {
        _ops = _load();
      });

  Map<String, dynamic> _payload(SyncQueueData op) {
    try {
      return Map<String, dynamic>.of(jsonDecode(op.payloadJson) as Map<String, dynamic>);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
    } finally {
      if (mounted) {
        _busy = false;
        _reload();
      }
    }
  }

  Future<void> _delete(SyncQueueData op) => _run(() async {
        final db = ref.read(databaseProvider);
        await (db.delete(db.syncQueue)..where((q) => q.id.equals(op.id))).go();
        // Письмо из «Исходящих» (отложенная отправка) — тоже убрать.
        await (db.delete(db.emails)..where((e) => e.id.equals(op.targetId))).go();
      });

  Future<void> _sendNow(SyncQueueData op) => _run(() async {
        final db = ref.read(databaseProvider);
        final p = _payload(op)..remove('scheduledAt');
        await (db.update(db.syncQueue)..where((q) => q.id.equals(op.id))).write(SyncQueueCompanion(
          operationType: const Value('send_email'),
          retryCount: const Value(0),
          lastAttemptAt: const Value(null),
          errorMessage: const Value(null),
          payloadJson: Value(jsonEncode(p)),
        ));
        await ref.read(offlineSendProvider).processQueue(op.accountId);
      });

  Future<void> _toDrafts(SyncQueueData op) {
    final l10n = AppLocalizations.of(context);
    return _run(() async {
      final id = await ref.read(offlineSendProvider).failedToDraft(op);
      if (mounted) setState(() => _note = l10n.tr(id == null ? 'queueToDraftsFailed' : 'queueToDraftsDone'));
    });
  }

  Future<void> _retryChanges(String accountId) => _run(() async {
        final acc = ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
        if (acc != null) await ref.read(syncServiceProvider).syncAccount(acc);
      });

  Future<void> _dropChanges(List<SyncQueueData> ops) => _run(() async {
        final db = ref.read(databaseProvider);
        final ids = ops.map((o) => o.id).toList();
        await (db.delete(db.syncQueue)..where((q) => q.id.isIn(ids))).go();
        // Локальные пометки «изменено» больше не ждут сервера: следующая
        // синхронизация вернёт письмам состояние с сервера.
        final targets = ops.map((o) => o.targetId).toSet().toList();
        await (db.update(db.emails)..where((e) => e.id.isIn(targets)))
            .write(const EmailsCompanion(isLocallyModified: Value(false)));
      });

  String _opName(AppLocalizations l10n, String type) => switch (type) {
        'mark_read' => l10n.tr('opMarkRead'),
        'flag' => l10n.tr('opFlag'),
        'move' => l10n.tr('opMove'),
        'delete' => l10n.tr('opDelete'),
        'upsert_task' => l10n.tr('opTaskChange'),
        'upsert_contact' => l10n.tr('opContactChange'),
        'delete_task' => l10n.tr('opTaskDelete'),
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = {for (final a in ref.watch(accountsProvider)) a.id: a.email};
    final fmt = DateFormat('d MMM, HH:mm', l10n.localeCode);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (ctx, scroll) => FutureBuilder<List<SyncQueueData>>(
        future: _ops,
        builder: (ctx, snap) {
          final ops = snap.data ?? const <SyncQueueData>[];
          final sends = ops.where((o) => _sendTypes.contains(o.operationType)).toList();
          final changes = ops.where((o) => !_sendTypes.contains(o.operationType)).toList();
          final byAccount = <String, List<SyncQueueData>>{};
          for (final o in changes) {
            (byAccount[o.accountId] ??= []).add(o);
          }
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: Space.xl),
            children: [
              ListTile(
                title: Text(l10n.tr('pendingInQueue'), style: theme.textTheme.titleLarge),
                subtitle: Text(l10n.tr('queueExplain')),
                trailing: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
              ),
              if (_note != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: Text(_note!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                ),
              if (snap.connectionState != ConnectionState.done && ops.isEmpty)
                const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator())),
              if (snap.connectionState == ConnectionState.done && ops.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Center(child: Text(l10n.tr('queueEmpty'))),
                ),
              for (final op in sends) _sendTile(l10n, theme, fmt, accounts, op),
              for (final e in byAccount.entries)
                Card(
                  margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(accounts[e.key] ?? e.key, style: theme.textTheme.titleSmall),
                        const SizedBox(height: Space.xs),
                        Text(
                          {
                            for (final t in e.value.map((o) => o.operationType).toSet())
                              '${_opName(l10n, t)} ×${e.value.where((o) => o.operationType == t).length}'
                          }.join(', '),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (e.value.any((o) => (o.errorMessage ?? '').isNotEmpty))
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              e.value.lastWhere((o) => (o.errorMessage ?? '').isNotEmpty).errorMessage!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                            ),
                          ),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _busy ? null : () => _dropChanges(e.value),
                              child: Text(l10n.tr('queueDiscardChanges')),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy ? null : () => _retryChanges(e.key),
                              child: Text(l10n.tr('retry')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _sendTile(AppLocalizations l10n, ThemeData theme, DateFormat fmt,
      Map<String, String> accounts, SyncQueueData op) {
    final p = _payload(op);
    final subject = (p['subject'] as String?)?.trim() ?? '';
    final scheduled = DateTime.tryParse(p['scheduledAt'] as String? ?? '');
    final failed = op.operationType == 'send_failed';
    final sending = op.operationType == 'send_inflight';
    final status = failed
        ? l10n.tr('queueNotSent')
        : sending
            ? l10n.tr('queueSending')
            : scheduled != null && scheduled.isAfter(DateTime.now())
                ? l10n.tr('queueScheduledAt').replaceAll('{time}', fmt.format(scheduled.toLocal()))
                : op.retryCount > 0
                    ? l10n.tr('queueRetryN').replaceAll('{n}', '${op.retryCount}')
                    : l10n.tr('queueWaiting');
    return Card(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(failed ? AppIcons.error : AppIcons.outbox,
                  size: 18, color: failed ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(subject.isEmpty ? l10n.tr('noSubject') : subject,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
              ),
            ]),
            const SizedBox(height: Space.xs),
            Text('${accounts[op.accountId] ?? ''} · ${fmt.format(op.createdAt.toLocal())} · $status',
                style: theme.textTheme.bodySmall),
            if ((op.errorMessage ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(op.errorMessage!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy || sending ? null : () => _delete(op),
                  child: Text(l10n.tr('delete')),
                ),
                if (failed)
                  TextButton(
                    onPressed: _busy ? null : () => _toDrafts(op),
                    child: Text(l10n.tr('queueToDrafts')),
                  ),
                FilledButton.tonal(
                  onPressed: _busy || sending ? null : () => _sendNow(op),
                  child: Text(failed ? l10n.tr('queueSendAgain') : l10n.tr('queueSendNow')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

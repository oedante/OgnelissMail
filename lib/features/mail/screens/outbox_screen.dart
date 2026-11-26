// lib/features/mail/screens/outbox_screen.dart
//
// «Исходящие», как в Outlook (просьба владельца 21.11.2026):
// - письмо попадает сюда сразу после «Отправить» — и во время отсчёта
//   перед отправкой («Отправка через 5 с»), и отложенное на время;
// - «Отменить» кнопкой на письме и одним свайпом: письмо не уходит и
//   возвращается в «Черновики»;
// - отправленное пропадает отсюда сразу (список — живой, из очереди
//   отправки);
// - не отправленное остаётся с причиной: «Отправить снова», «Изменить»,
//   «Отменить».
//
// Источник — очередь отправки (sync_queue): поток следит за лёгкими
// столбцами, а содержимое письма (в нём и вложения base64) читается один
// раз на изменение строки, как у отложенных писем (scheduled_sends.dart).
// Письма, которые отправляются прямо сейчас без очереди (отсчёт
// выключен), — из OfflineSendService.sendingNow.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable, Value, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/offline_send_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../data/models/folder_model.dart';
import '../providers/mail_providers.dart'
    show accountsProvider, emailsProvider, foldersProvider, selectedFolderIdProvider;

/// Виды строк очереди, которые — письма к отправке.
const outboxSendTypes = {'send_email', 'send_pending', 'send_inflight', 'send_failed'};

/// Письмо в «Исходящих».
class OutboxItem {
  final int queueId;
  final String accountId;
  final String targetId;
  final String type;
  final String subject;
  final String to;
  final String preview;
  final DateTime createdAt;

  /// Отсчёт перед отправкой или отложенная отправка.
  final DateTime? scheduledAt;
  final int retryCount;
  final String? error;

  const OutboxItem({
    required this.queueId,
    required this.accountId,
    required this.targetId,
    required this.type,
    required this.subject,
    required this.to,
    required this.preview,
    required this.createdAt,
    this.scheduledAt,
    this.retryCount = 0,
    this.error,
  });

  bool get failed => type == 'send_failed';
  bool get sending => type == 'send_inflight';

  /// Отменить можно всё, что ещё не отправляется.
  bool get cancellable => !sending;

  bool waiting(DateTime now) => scheduledAt != null && scheduledAt!.isAfter(now);

  @override
  bool operator ==(Object other) =>
      other is OutboxItem &&
      other.queueId == queueId &&
      other.type == type &&
      other.scheduledAt == scheduledAt &&
      other.retryCount == retryCount &&
      other.error == error &&
      other.subject == subject;

  @override
  int get hashCode => Object.hash(queueId, type, scheduledAt, retryCount, error, subject);

  /// Тема, кому и начало текста — из содержимого строки очереди.
  static ({String subject, String to, String preview, DateTime? at}) parsePayload(String json) {
    try {
      final p = jsonDecode(json) as Map<String, dynamic>;
      final to = [
        for (final r in (p['to'] as List?) ?? const [])
          if (r is Map)
            ((r['displayName'] as String?)?.trim().isNotEmpty ?? false)
                ? (r['displayName'] as String).trim()
                : (r['email'] as String? ?? ''),
      ].where((s) => s.isNotEmpty).join(', ');
      final body = (p['bodyHtml'] as String?) ?? (p['bodyPlain'] as String?) ?? '';
      final head = body.length > 6000 ? body.substring(0, 6000) : body;
      final preview = head
          .replaceAll(RegExp(r'<(style|script|head)[\s\S]*?</\1>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return (
        subject: (p['subject'] as String? ?? '').trim(),
        to: to,
        preview: preview.length > 200 ? preview.substring(0, 200) : preview,
        at: DateTime.tryParse(p['scheduledAt'] as String? ?? '')?.toLocal(),
      );
    } catch (_) {
      return (subject: '', to: '', preview: '', at: null);
    }
  }
}

/// Письма в «Исходящих» всех ящиков, старые первыми.
final outboxItemsProvider = StreamProvider<List<OutboxItem>>((ref) {
  final db = ref.watch(databaseProvider);
  final cache = <int, (int, ({String subject, String to, String preview, DateTime? at}))>{};
  final types = outboxSendTypes.map((t) => "'$t'").join(', ');
  return db
      .customSelect(
        'SELECT id, account_id, operation_type, target_id, retry_count, error_message, created_at, '
        'LENGTH(payload_json) AS len FROM sync_queue WHERE operation_type IN ($types) ORDER BY created_at',
        readsFrom: {db.syncQueue},
      )
      .watch()
      .asyncMap((rows) async {
        final out = <OutboxItem>[];
        final seen = <int>{};
        for (final r in rows) {
          final id = r.read<int>('id');
          final len = r.read<int>('len');
          seen.add(id);
          final hit = cache[id];
          if (hit == null || hit.$1 != len) {
            final p = await db
                .customSelect('SELECT payload_json FROM sync_queue WHERE id = ?', variables: [Variable.withInt(id)])
                .getSingleOrNull();
            if (p == null) continue;
            cache[id] = (len, OutboxItem.parsePayload(p.read<String>('payload_json')));
          }
          final c = cache[id]!.$2;
          out.add(OutboxItem(
            queueId: id,
            accountId: r.read<String>('account_id'),
            targetId: r.read<String>('target_id'),
            type: r.read<String>('operation_type'),
            subject: c.subject,
            to: c.to,
            preview: c.preview,
            createdAt: r.read<DateTime>('created_at'),
            scheduledAt: c.at,
            retryCount: r.read<int>('retry_count'),
            error: r.readNullable<String>('error_message'),
          ));
        }
        cache.removeWhere((k, _) => !seen.contains(k));
        return out;
      });
});

/// Писем в «Исходящих» — счётчик у папки в меню.
final outboxCountProvider = Provider<int>((ref) => ref.watch(outboxItemsProvider).value?.length ?? 0);

/// Папка «Исходящие» в списке писем (21.11.2026, просьба владельца:
/// «не отдельным экраном, а папкой, как Входящие, Черновики») — id
/// выбранной папки ленты; письма в ней — из очереди отправки всех ящиков.
const kOutboxFolderId = '__outbox__';

/// «Исходящие» отдельной страницей — из уведомления «Не отправлено».
class OutboxScreen extends StatelessWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: TextScaleCapBar(child: AppBar(title: Text(AppLocalizations.of(context).tr('outbox')))),
        body: const OutboxList(),
      );
}

/// Список «Исходящих» — в ленте писем вместо писем папки и на странице
/// [OutboxScreen].
class OutboxList extends ConsumerStatefulWidget {
  const OutboxList({super.key});

  @override
  ConsumerState<OutboxList> createState() => _OutboxListState();
}

class _OutboxListState extends ConsumerState<OutboxList> {
  Timer? _tick;

  /// Отменённые свайпом — убраны сразу, до обновления списка из базы.
  final Set<int> _hidden = {};

  /// Письма, с которыми сейчас что-то делают (кнопки неактивны).
  final Set<int> _busy = {};

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Секундный счётчик — пока есть письма с отсчётом.
  void _ensureTicker(bool needed) {
    if (needed && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needed && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  Future<SyncQueueData?> _row(OutboxItem item) {
    final db = ref.read(databaseProvider);
    return (db.select(db.syncQueue)..where((q) => q.id.equals(item.queueId))).getSingleOrNull();
  }

  Future<T?> _guard<T>(OutboxItem item, Future<T?> Function() action) async {
    setState(() => _busy.add(item.queueId));
    try {
      return await action();
    } catch (e) {
      AppLogger.warning('Исходящие: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy.remove(item.queueId));
    }
  }

  /// «Отменить»: письмо не уходит, возвращается в «Черновики».
  Future<bool> _cancel(OutboxItem item) async {
    final l10n = AppLocalizations.of(context);
    final id = await _guard(item, () async {
      final op = await _row(item);
      if (op == null) return null;
      return ref.read(offlineSendProvider).cancelToDraft(op);
    });
    if (id == null) {
      AppLogger.info('Исходящие: «Отменить» — ${l10n.tr('alreadySent')}');
      return false;
    }
    AppLogger.info('Исходящие: ${l10n.tr('cancelledToDrafts')} ($id)');
    unawaited(ref.read(emailsProvider.notifier).refresh());
    return true;
  }

  /// «Изменить»: отменить и открыть письмо в редакторе.
  Future<void> _edit(OutboxItem item) async {
    final router = GoRouter.of(context);
    final id = await _guard(item, () async {
      final op = await _row(item);
      if (op == null) return null;
      return ref.read(offlineSendProvider).cancelToDraft(op);
    });
    if (id == null || !mounted) return;
    unawaited(ref.read(emailsProvider.notifier).refresh());
    unawaited(router.push(Uri(path: '/compose', queryParameters: {
      'draftId': id,
      'accountId': item.accountId,
    }).toString()));
  }

  /// «Отправить сейчас» / «Отправить снова».
  Future<void> _sendNow(OutboxItem item) => _guard<bool>(item, () async {
        final op = await _row(item);
        if (op == null) return null;
        final db = ref.read(databaseProvider);
        Map<String, dynamic> p;
        try {
          p = Map<String, dynamic>.of(jsonDecode(op.payloadJson) as Map<String, dynamic>);
        } catch (_) {
          p = <String, dynamic>{};
        }
        p.remove('scheduledAt');
        // Повторы при плохой связи — снова сутки, с этого нажатия.
        p['retryFrom'] = DateTime.now().toIso8601String();
        final n = await (db.update(db.syncQueue)
              ..where((q) => q.id.equals(op.id) & q.operationType.isIn(const ['send_email', 'send_pending', 'send_failed'])))
            .write(SyncQueueCompanion(
          operationType: const Value('send_email'),
          retryCount: const Value(0),
          lastAttemptAt: const Value(null),
          errorMessage: const Value(null),
          payloadJson: Value(jsonEncode(p)),
        ));
        if (n == 0) return null;
        final service = ref.read(offlineSendProvider)..releaseGatewayHold(op.id);
        await service.processQueue(op.accountId);
        return true;
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = [for (final i in ref.watch(outboxItemsProvider).value ?? const <OutboxItem>[]) if (!_hidden.contains(i.queueId)) i];
    final service = ref.watch(offlineSendProvider);
    final now = DateTime.now();
    _ensureTicker(items.any((i) => i.waiting(now)));
    // Своя папка «Исходящие» на сервере ящика (Exchange и часть IMAP,
    // 22.11.2026): в меню она и есть эти «Исходящие»; письма, которые лежат
    // в ней на сервере (их положила другая программа), — по строке внизу.
    final server = (ref.watch(foldersProvider).value ?? const <FolderModel>[])
        .where((f) => f.type == FolderType.outbox && f.totalCount > 0)
        .firstOrNull;
    return ValueListenableBuilder<List<OutboxSending>>(
      valueListenable: service.sendingNow,
      builder: (context, direct, _) {
        if (items.isEmpty && direct.isEmpty && server == null) {
          return EmptyState(icon: AppIcons.outbox, title: l10n.tr('outboxEmpty'));
        }
        return SlidableAutoCloseBehavior(
          child: ListView(
            padding: const EdgeInsets.only(top: Space.xs, bottom: Space.xl),
            children: [
              for (final d in direct) _directTile(l10n, d),
              for (final i in items) _tile(l10n, i, now),
              if (server != null) _serverTile(l10n, server),
            ],
          ),
        );
      },
    );
  }

  /// Письма в папке «Исходящие» на сервере — открыть её как обычную папку.
  Widget _serverTile(AppLocalizations l10n, FolderModel f) => Padding(
        padding: const EdgeInsets.only(top: Space.s),
        child: ListTile(
          key: const ValueKey('outbox_server_folder'),
          leading: Icon(AppIcons.folder, color: AppColors.mutedText(context)),
          title: Text(l10n.tr('outboxOnServer').replaceAll('{n}', '${f.totalCount}')),
          trailing: const Icon(AppIcons.chevron_right),
          onTap: () => ref.read(selectedFolderIdProvider.notifier).state = f.id,
        ),
      );

  Widget _directTile(AppLocalizations l10n, OutboxSending d) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const SizedBox(width: 24, height: 24, child: Padding(
        padding: EdgeInsets.all(3),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      title: Text(d.subject.isEmpty ? l10n.tr('noSubject') : d.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text([if (d.to.isNotEmpty) d.to, l10n.tr('sendingNow')].join(' · '),
          maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
    );
  }

  Widget _tile(AppLocalizations l10n, OutboxItem item, DateTime now) {
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final accounts = {for (final a in ref.watch(accountsProvider)) a.id: a.email};
    final fmt = DateFormat('d MMM, HH:mm', l10n.localeCode);
    final busy = _busy.contains(item.queueId);
    final left = item.scheduledAt?.difference(now).inSeconds ?? 0;
    final String status;
    if (item.failed) {
      status = l10n.tr('queueNotSent');
    } else if (item.sending) {
      status = l10n.tr('sendingNow');
    } else if (item.waiting(now)) {
      // Отсчёт (до часа) — секундами, отложенное — временем.
      status = left <= 3600
          ? l10n.tr('sendingIn').replaceAll('{secs}', '$left')
          : l10n.tr('queueScheduledAt').replaceAll('{time}', fmt.format(item.scheduledAt!));
    } else if (item.retryCount > 0) {
      status = l10n.tr('queueRetryN').replaceAll('{n}', '${item.retryCount}');
    } else {
      status = l10n.tr('queueWaiting');
    }
    final statusColor = item.failed ? theme.colorScheme.error : theme.colorScheme.primary;
    final multiAccount = accounts.length > 1;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (item.sending)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(item.failed ? AppIcons.error : (item.waiting(now) ? AppIcons.schedule_send : AppIcons.outbox),
                size: 18, color: statusColor),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(item.subject.isEmpty ? l10n.tr('noSubject') : item.subject,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
          ),
        ]),
        if (item.to.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text('${l10n.tr('to')}: ${item.to}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          ),
        if (item.preview.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text(item.preview,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        const SizedBox(height: Space.xs),
        Text(
          [status, if (multiAccount) accounts[item.accountId] ?? ''].where((s) => s.isNotEmpty).join(' · '),
          style: theme.textTheme.labelMedium?.copyWith(color: statusColor),
        ),
        if ((item.error ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xxs),
            child: Text(item.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        // Кнопки — справа; не помещаются — переносится последняя, а не все
        // три столбиком, как у OverflowBar (лента на компьютере ~400 точек,
        // снимок v268_outbox_desktop).
        if (item.cancellable)
          SizedBox(
            width: double.infinity,
            child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, children: [
            TextButton(
              key: ValueKey('outbox_cancel_${item.queueId}'),
              onPressed: busy ? null : () => _cancel(item),
              child: Text(l10n.tr('undo')),
            ),
            TextButton(
              onPressed: busy ? null : () => _edit(item),
              child: Text(l10n.tr('edit')),
            ),
            FilledButton.tonal(
              onPressed: busy ? null : () => _sendNow(item),
              child: Text(l10n.tr(item.failed ? 'queueSendAgain' : 'queueSendNow')),
            ),
          ]),
          ),
      ]),
    );

    final card = Card(margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0), child: body);
    if (!item.cancellable) return card;
    // Один свайп влево — «Отменить» (полный свайп сразу отменяет).
    final tone = SwipeTone.of(context, AppColors.errorRed);
    return Slidable(
      key: ValueKey('outbox_${item.queueId}'),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.35,
        dismissible: DismissiblePane(
          confirmDismiss: () => _cancel(item),
          onDismissed: () => setState(() => _hidden.add(item.queueId)),
        ),
        children: [
          SlidableAction(
            onPressed: (_) => _cancel(item),
            backgroundColor: tone.$1,
            foregroundColor: tone.$2,
            icon: AppIcons.undo,
            label: l10n.tr('undo'),
          ),
        ],
      ),
      child: card,
    );
  }
}

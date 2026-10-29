// lib/features/settings/screens/folder_sync_settings_screen.dart
// Выбор папок для синхронизации. По умолчанию включены все обнаруженные папки;
// технические (архивы автоматики, служебные выгрузки) можно отключить — они
// перестанут тянуть трафик и занимать место.
//
// Хранится в колонке folders.isSynced (была в схеме, миграция не нужна).
// Синхронизация уже фильтрует папки по этому флагу; отдельно исправлено, что
// выбор не затирается при обновлении списка папок с сервера.
//
// 1.7.2 (просьба пользователя через владельца 21.10.2026): у каждой папки —
// ещё колокольчик «уведомления». Папку можно синхронизировать, но не
// получать о ней уведомлений (FolderNotify, SharedPreferences). Отправленные,
// черновики, исходящие, корзина и спам не уведомляют никогда — колокольчика
// у них нет.

import 'dart:async';

import 'package:drift/drift.dart' show Value, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/help_hint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart' show FoldersCompanion;
import '../../../core/utils/folder_icons.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/notifications/account_notify_mode.dart' show FolderNotify;
import '../../../l10n/app_localizations.dart';
import '../../mail/providers/mail_providers.dart';
import '../../mail/folder_order.dart' show hideUnsyncedFoldersProvider;
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../widgets/ui/app_menu_button.dart';

/// Выключенные уведомления папок («ящик|папка»).
final folderNotifyOffProvider = NotifierProvider<FolderNotifyOffNotifier, Set<String>>(FolderNotifyOffNotifier.new);

class FolderNotifyOffNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => FolderNotify.off(ref.read(sharedPrefsProvider));

  Future<void> set(String accountId, Iterable<String> folderIds, bool notify) async {
    state = await FolderNotify.set(ref.read(sharedPrefsProvider), accountId, folderIds, notify);
  }
}

class FolderSyncSettingsScreen extends ConsumerWidget {
  const FolderSyncSettingsScreen({super.key, this.accountId});

  /// Аккаунт, для которого открыт экран (из экрана аккаунта); null — активный.
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    // Папки ИМЕННО этого ящика. Раньше брался foldersProvider (всегда
    // активный ящик) — у любого аккаунта показывались папки Exchange.
    final account = ref.watch(accountOrActiveProvider(accountId));
    if (account == null) {
      return Scaffold(appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('folderSync')))));
    }
    final foldersAsync = ref.watch(accountFoldersProvider(account.id));

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.tr('folderSync')),
            Text(account.email, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          HelpButton(text: l10n.tr('folderSyncDisabledInfo'), title: l10n.tr('folderSync')),
          AppMenuButton<String>(
            onSelected: (v) => switch (v) {
              'notifyAll' || 'notifyNone' => _bulkNotify(ref, account, notify: v == 'notifyAll'),
              _ => _bulk(context, ref, enable: v == 'all'),
            },
            itemBuilder: (_) => [
              AppMenuEntry(value: 'all', icon: AppIcons.sync, label: l10n.tr('enableAll')),
              AppMenuEntry(value: 'none', icon: AppIcons.sync_disabled, label: l10n.tr('disableAll')),
              const AppMenuEntry.divider(),
              AppMenuEntry(value: 'notifyAll', icon: AppIcons.notifications_active, label: l10n.tr('folderNotifyAll')),
              AppMenuEntry(value: 'notifyNone', icon: AppIcons.notifications_off, label: l10n.tr('folderNotifyNone')),
            ],
          ),
        ],
      )),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (folders) {
          if (folders.isEmpty) {
            return Center(
              child: Text(l10n.tr('noFoldersYet')),
            );
          }
          // Корень — папка без родителя или с родителем вне списка (служебный
          // корень ящика, «0» у ActiveSync до обновления списка папок).
          final ids = {for (final f in folders) f.id};
          final roots = folders
              .where((f) => f.parentId == null || !ids.contains(f.parentId))
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
          final offCount = folders.where((f) => !f.isSynced).length;

          final hidden = ref.watch(hideUnsyncedFoldersProvider).contains(account.id);
          return ListView(
            children: [
              // 1.6.10: убрать из меню почты папки, которые не синхронизируются.
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                secondary: const Icon(AppIcons.visibility_off),
                title: Text(l10n.tr('hideUnsyncedFolders')),
                subtitle: Text(l10n.tr('hideUnsyncedFoldersHint')),
                value: hidden,
                onChanged: (v) => ref.read(hideUnsyncedFoldersProvider.notifier).set(account.id, v),
              ),
              const Divider(height: 1),
              const SizedBox(height: Space.s),
              if (offCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                  child: Text(
                    l10n.tr('disabledFoldersN').replaceAll('{n}', '$offCount'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              // Очистка писем выключенных папок (1.5.10) — кнопка или ход
              // очистки, если она уже идёт (в том числе после выключения
              // одной папки).
              ValueListenableBuilder<({int done, int total})?>(
                valueListenable: FolderCleanup.of(account.id),
                builder: (context, job, _) {
                  if (job != null) return _cleanupProgress(context, job);
                  if (offCount == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _cleanupDisabled(context, ref, account, folders),
                        icon: const Icon(AppIcons.delete_sweep, size: 18),
                        label: Text(l10n.tr('folderCleanup')),
                      ),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              // Что значат колокольчик и переключатель справа.
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
                child: Text(l10n.tr('folderNotifyHint'), style: Theme.of(context).textTheme.bodySmall),
              ),
              ...roots.expand((f) => _tiles(context, ref, folders, f, 0, ru, ref.watch(folderNotifyOffProvider))),
            ],
          );
        },
      ),
    );
  }

  /// Папка и её подпапки — рекурсивно, с отступом по уровню вложенности.
  Iterable<Widget> _tiles(BuildContext context, WidgetRef ref,
      List<FolderModel> all, FolderModel f, int depth, bool ru, Set<String> notifyOff) sync* {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final children = all.where((c) => c.parentId == f.id).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    // Колокольчик — только у папок, о которых уведомления бывают (не свои
    // письма, не корзина и спам, не виртуальные папки Gmail).
    final canNotify = !FolderNotify.neverTypes.contains(f.type) && f.showInUnified;
    final notifyOn = canNotify && f.isSynced && !notifyOff.contains(FolderNotify.key(f.accountId, f.id));

    yield ListTile(
      contentPadding: EdgeInsets.only(left: Space.l + depth * 20, right: Space.s),
      leading: Icon(folderIconOf(f)),
      title: Text(f.displayName),
      subtitle: children.isEmpty
          ? (f.totalCount > 0
              ? Text(l10n.tr('nMessages').replaceAll('{n}', '${f.totalCount}'))
              : null)
          : Text(l10n.tr('nSubfolders').replaceAll('{n}', '${children.length}')),
      onTap: () => _set(context, ref, f, !f.isSynced, all),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canNotify)
          IconButton(
            tooltip: l10n.tr(notifyOn ? 'folderNotifyOn' : 'folderNotifyOff'),
            icon: Icon(notifyOn ? AppIcons.notifications_active : AppIcons.notifications_off,
                color: notifyOn ? scheme.primary : scheme.onSurfaceVariant),
            // Папка не синхронизируется — уведомлять не о чем.
            onPressed: f.isSynced
                ? () => ref
                    .read(folderNotifyOffProvider.notifier)
                    .set(f.accountId, [f.id, ..._descendants(all, f.id)], !notifyOn)
                : null,
          )
        else
          const SizedBox(width: 48),
        Switch(value: f.isSynced, onChanged: (v) => _set(context, ref, f, v, all)),
      ]),
    );

    for (final c in children) {
      yield* _tiles(context, ref, all, c, depth + 1, ru, notifyOff);
    }
  }

  /// «Уведомления: все папки / ни одной» — для папок этого ящика, о которых
  /// уведомления бывают.
  Future<void> _bulkNotify(WidgetRef ref, AccountModel account, {required bool notify}) async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.folders)..where((t) => t.accountId.equals(account.id))).get();
    await ref.read(folderNotifyOffProvider.notifier).set(account.id, [for (final r in rows) r.id], notify);
  }

  /// Переключение папки. Подпапки следуют за родителем — иначе отключение
  /// технической ветки пришлось бы делать по одной.
  Future<void> _set(BuildContext context, WidgetRef ref, FolderModel f,
      bool value, List<FolderModel> all) async {
    final l10n = AppLocalizations.of(context);
    final ids = <String>[f.id, ..._descendants(all, f.id)];
    final db = ref.read(databaseProvider);
    // Только папки этого ящика: id вида «INBOX» одинаковы у всех IMAP-ящиков,
    // и переключатель одного менял папки во всех.
    await (db.update(db.folders)
          ..where((t) => t.id.isIn(ids) & t.accountId.equals(f.accountId)))
        .write(FoldersCompanion(isSynced: Value(value)));
    // Включённую папку загружаем сразу, не дожидаясь планового синка.
    final account = ref.read(accountOrActiveProvider(accountId));
    if (value) {
      if (account != null) unawaited(ref.read(syncServiceProvider).syncAccount(account));
    } else if (account != null && context.mounted) {
      // Выключили — спросить, убрать ли её письма с телефона (1.5.9).
      await _askDrop(context, ref, account, ids, f.displayName);
    }

    if (context.mounted && ids.length > 1) {
      showInlineNotice(l10n.tr('toggledWithSubfolders')
          .replaceAll('{state}', value ? l10n.tr('enabledState') : l10n.tr('disabledState'))
          .replaceAll('{n}', '${ids.length}'));
    }
  }

  List<String> _descendants(List<FolderModel> all, String parentId) {
    final direct = all.where((c) => c.parentId == parentId).map((c) => c.id);
    return [
      for (final id in direct) ...[id, ..._descendants(all, id)],
    ];
  }

  Future<void> _bulk(BuildContext context, WidgetRef ref,
      {required bool enable}) async {
    final account = ref.read(accountOrActiveProvider(accountId));
    if (account == null) return;
    final db = ref.read(databaseProvider);
    // Только папки текущего аккаунта (раньше — всех аккаунтов сразу).
    final ids = enable
        ? const <String>[]
        : [
            for (final r in await (db.select(db.folders)..where((t) => t.accountId.equals(account.id))).get())
              r.id,
          ];
    await (db.update(db.folders)..where((t) => t.accountId.equals(account.id)))
        .write(FoldersCompanion(isSynced: Value(enable)));
    if (!enable && context.mounted) await _askDrop(context, ref, account, ids, null);
  }

  /// Папки выключены: убрать ли их письма с телефона (1.5.9). На сервере
  /// всё остаётся, поиск на сервере их находит; во «Всей почте» письма
  /// выключенных папок не показываются в любом случае. Писем на телефоне
  /// нет — не спрашиваем. Удаление — в фоне (1.5.10), ход — вверху экрана.
  Future<void> _askDrop(BuildContext context, WidgetRef ref, AccountModel account, List<String> ids,
      String? folderName) async {
    final l10n = AppLocalizations.of(context);
    final n = await ref.read(databaseProvider).countLocalFolderEmails(account.id, ids);
    if (n == 0 || !context.mounted) return;
    final drop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('folderDropTitle')),
        content: Text((folderName == null ? l10n.tr('folderDropBodyAll') : l10n.tr('folderDropBody'))
            .replaceAll('{name}', folderName ?? '')
            .replaceAll('{n}', '$n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('folderDropKeep'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('folderDropDelete'))),
        ],
      ),
    );
    if (drop != true || !context.mounted) return;
    _startCleanup(context, ref, account, ids, n);
  }

  /// «Очистить от несинхронизируемых писем» (1.5.10): письма всех
  /// выключенных папок ящика — только с телефона, после подтверждения.
  Future<void> _cleanupDisabled(
      BuildContext context, WidgetRef ref, AccountModel account, List<FolderModel> folders) async {
    final l10n = AppLocalizations.of(context);
    if (FolderCleanup.busy(account.id)) return;
    final off = [for (final f in folders) if (!f.isSynced) f.id];
    if (off.isEmpty) return;
    final n = await ref.read(databaseProvider).countLocalFolderEmails(account.id, off);
    if (!context.mounted) return;
    if (n == 0) {
      showInlineNotice(l10n.tr('folderCleanupNothing'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('folderCleanupTitle')),
        content: Text(l10n
            .tr('folderCleanupBody')
            .replaceAll('{folders}', '${off.length}')
            .replaceAll('{n}', '$n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('folderCleanupGo'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    _startCleanup(context, ref, account, off, n);
  }

  /// Удаление в фоне: экран можно закрыть, итог — строкой вверху экрана.
  void _startCleanup(BuildContext context, WidgetRef ref, AccountModel account, List<String> ids, int total) {
    final l10n = AppLocalizations.of(context);
    final sync = ref.read(syncServiceProvider);
    unawaited(FolderCleanup.run(sync, account, ids, total).then((removed) {
      showInlineNotice(l10n.tr('folderDropDone').replaceAll('{n}', '$removed'));
    }, onError: (Object e) {
      showInlineError('${l10n.tr('folderCleanupFailed')}: $e');
    }));
  }

  Widget _cleanupProgress(BuildContext context, ({int done, int total}) job) {
    final l10n = AppLocalizations.of(context);
    final v = job.total <= 0 ? null : (job.done / job.total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('folderCleanupProgress').replaceAll('{done}', '${job.done}').replaceAll('{total}', '${job.total}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xs),
          LinearProgressIndicator(value: v),
        ],
      ),
    );
  }
}

/// Удаление писем выключенных папок с телефона (1.5.10) — идёт в фоне и
/// переживает закрытие экрана. Задания одного ящика — по очереди (кнопка
/// очистки и выключение папки во время очистки); [of] — ход текущего:
/// удалено и сколько всего, null — ничего не идёт.
class FolderCleanup {
  FolderCleanup._();

  static final Map<String, ValueNotifier<({int done, int total})?>> _jobs = {};
  static final Map<String, Future<void>> _queue = {};

  static ValueNotifier<({int done, int total})?> of(String accountId) =>
      _jobs.putIfAbsent(accountId, () => ValueNotifier(null));

  static bool busy(String accountId) => of(accountId).value != null || _queue.containsKey(accountId);

  static Future<int> run(SyncService sync, AccountModel account, List<String> ids, int total) {
    final v = of(account.id);
    final prev = _queue[account.id] ?? Future<void>.value();
    final job = prev.then((_) async {
      v.value = (done: 0, total: total);
      try {
        return await sync.dropLocalFolderMail(account, ids,
            onProgress: (d) => v.value = (done: d, total: total > d ? total : d));
      } finally {
        v.value = null;
      }
    });
    final tail = job.then((_) {}, onError: (Object _) {});
    _queue[account.id] = tail;
    unawaited(tail.whenComplete(() {
      if (identical(_queue[account.id], tail)) _queue.remove(account.id);
    }));
    return job;
  }
}

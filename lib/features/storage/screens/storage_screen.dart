// lib/features/storage/screens/storage_screen.dart
// Хранилище/квота: размер локального кэша ящика + очистка по возрасту и по размеру.
// Размер ящика на телефоне — фактический объём текстов писем (с 1.5.6; раньше
// — колонка emails.size, которую ActiveSync не заполняет: было «0 Б»).
// «Тяжёлые письма» — по размеру с сервера, а без него — по тексту и списку
// вложений письма.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../mail/providers/mail_providers.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/models/mail_quota.dart';
import '../../../services/mail/imap/imap_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/maintenance/maintenance_service.dart';
import '../../../services/mail/attachment_cache_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle;
import '../../../core/utils/format_bytes.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});
  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  ({int count, int bytes, int withText})? _stats;
  bool _loading = true;
  bool _busy = false;
  MailQuota? _quota;          // квота на сервере (IMAP QUOTA); null — недоступна
  bool _quotaLoading = true;
  int _cacheBytes = 0;        // сколько занимают скачанные вложения
  int _cacheFiles = 0;
  int _cacheMax = AttachmentCacheService.defaultMaxBytes;

  /// Размер с единицами на языке интерфейса.
  String _fb(int bytes) => formatBytes(bytes, AppLocalizations.of(context));

  AppDatabase get _db => ref.read(databaseProvider);
  AccountModel? get _account => ref.read(activeAccountProvider);

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadQuota();
    unawaited(_loadCache());
  }

  Future<void> _loadCache() async {
    final cache = ref.read(attachmentCacheProvider);
    // Сначала сверить индекс с диском (1.7.2): после очистки кэша системой
    // экран показывал размер и число файлов, которых уже нет.
    try {
      await cache.reconcile();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cacheBytes = cache.currentBytes;
      _cacheFiles = cache.fileCount;
      _cacheMax = cache.maxBytes;
    });
  }

  /// Очистка кэша вложений. Предупреждаем честно: данные не теряются —
  /// файлы лежат на сервере и скачаются снова при открытии.
  Future<void> _clearCache() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('clearCacheQ')),
        content: Text(
          l10n.tr('clearCacheDesc').replaceAll('{size}', _fb(_cacheBytes)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('clear')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(attachmentCacheProvider).clear();
    if (!mounted) return;
    await _loadCache();
    if (!mounted) return;
    AppLogger.info(l10n.tr('cacheCleared'));
  }

  /// Сжатие базы (VACUUM) — освобождает место на диске после удалений. Операция
  /// перезаписывает файл БД целиком, поэтому с индикатором занятости.
  Future<void> _optimizeDb() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(maintenanceServiceProvider).runNow();
    } catch (e) {
      AppLogger.warning('VACUUM failed: $e');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _loadStats();
    AppLogger.info(l10n.tr('storageOptimized'));
  }

  /// Квота на сервере — сеть, поэтому грузим отдельно и молча (не мешаем экрану).
  Future<void> _loadQuota() async {
    final acc = _account;
    // QUOTA — только для IMAP-аккаунтов (как в sync: не EAS и не EWS/Exchange).
    if (acc == null || acc.usesEas || acc.usesEws || acc.isExchange) {
      if (mounted) setState(() => _quotaLoading = false);
      return;
    }
    final q = await ref.read(imapServiceProvider).getServerQuota(acc);
    if (mounted) setState(() { _quota = q; _quotaLoading = false; });
  }

  Future<void> _loadStats() async {
    final acc = _account;
    if (acc == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final s = await _db.mailboxStats(acc.id);
    if (mounted) setState(() { _stats = s; _loading = false; });
  }

  int _epochSecDaysAgo(int days) =>
      DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

  /// Показать предпросмотр и, при подтверждении, выполнить очистку.
  Future<void> _cleanup(AppLocalizations l10n, {int? olderThanDays, int? largerThanBytes, required String title}) async {
    final acc = _account;
    if (acc == null) return;
    final olderSec = olderThanDays != null ? _epochSecDaysAgo(olderThanDays) : null;

    setState(() => _busy = true);
    final st = await _db.cleanupStats(acc.id, olderThanEpochSec: olderSec, largerThanBytes: largerThanBytes);
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    if (st.count == 0) {
      showInlineNotice(l10n.tr('noMatchingMail'));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(l10n.tr('moveToTrashConfirm').replaceAll('{count}', '${st.count}').replaceAll('{size}', _fb(st.bytes))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('cleanUp'))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final items = await _db.cleanupCandidates(acc.id, olderThanEpochSec: olderSec, largerThanBytes: largerThanBytes);
    final done = await ref.read(emailActionsProvider).cleanupDelete(acc, items);
    await ref.read(emailsProvider.notifier).refresh();
    await _loadStats();
    if (!mounted) return;
    setState(() => _busy = false);
    showInlineNotice(l10n.tr('movedToTrashN').replaceAll('{done}', '$done'));
  }

  Future<void> _customDays(AppLocalizations l10n) async {
    final ctrl = TextEditingController(text: '90');
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('olderThanDaysField')),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
            decoration: InputDecoration(labelText: l10n.tr('daysField'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: Text(l10n.tr('next'))),
        ],
      ),
    );
    if (days != null && days > 0) {
      await _cleanup(l10n, olderThanDays: days, title: l10n.tr('olderThanNDays').replaceAll('{n}', '$days'));
    }
  }

  Future<void> _customSize(AppLocalizations l10n) async {
    final ctrl = TextEditingController(text: '1');
    final mb = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('largerThanMbField')),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
            decoration: InputDecoration(labelText: l10n.tr('mbUnit'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))), child: Text(l10n.tr('next'))),
        ],
      ),
    );
    if (mb != null && mb > 0) {
      await _cleanup(l10n, largerThanBytes: (mb * 1024 * 1024).round(), title: l10n.tr('largerThanNMb').replaceAll('{n}', mb.toStringAsFixed(0)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('storage')))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(Space.l),
              children: [
                // Разделы — серыми полосами, содержимое — на подложке группы
                // настроек (как остальные экраны настроек, 11.10.2026).
                SettingsSectionTitle(l10n.tr('attachmentCache')),
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fb(_cacheBytes)} / ${_fb(_cacheMax)}',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          l10n.tr('cacheFilesDesc').replaceAll('{n}', '$_cacheFiles'),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: Space.s),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _cacheMax > 0
                                ? (_cacheBytes / _cacheMax).clamp(0.0, 1.0)
                                : 0,
                            minHeight: 6,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: Space.l),

                        // Порог автоочистки
                        Text(l10n.tr('autoCleanupThreshold'),
                            style: theme.textTheme.bodyMedium),
                        Text(
                          l10n.tr('cacheOverflowHint'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.mutedText(context)),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _cacheMax.toDouble(),
                                min: AttachmentCacheService.minBytes.toDouble(),
                                max: AttachmentCacheService.maxAllowedBytes.toDouble(),
                                divisions: (AttachmentCacheService.maxAllowedBytes -
                                        AttachmentCacheService.minBytes) ~/
                                    AttachmentCacheService.stepBytes,
                                label: _fb(_cacheMax),
                                onChanged: (v) =>
                                    setState(() => _cacheMax = v.round()),
                                onChangeEnd: (v) async {
                                  final cache = ref.read(attachmentCacheProvider);
                                  await cache.setMaxBytes(v.round());
                                  await _loadCache();
                                },
                              ),
                            ),
                            SizedBox(
                              width: 74,
                              child: Text(_fb(_cacheMax),
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodyMedium),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.xs),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(AppIcons.delete_sweep, size: 18),
                            label: Text(l10n.tr('clearCache')),
                            onPressed: _cacheBytes == 0 ? null : _clearCache,
                          ),
                        ),
                        const SizedBox(height: Space.s),
                        // Сжатие БД (VACUUM): после удаления писем/очистки Корзины
                        // файл SQLite не уменьшается сам — место освобождается
                        // только VACUUM. Раньше метод db.vacuum() не вызывался
                        // нигде, и БД росла на диске без сжатия.
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(AppIcons.compress, size: 18),
                            label: Text(l10n.tr('optimizeStorage')),
                            onPressed: _busy ? null : _optimizeDb,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Квота на сервере (IMAP QUOTA)
                if (_quotaLoading || _quota != null) SettingsSectionTitle(l10n.tr('serverQuota')),
                if (_quotaLoading || _quota != null)
                  _Panel(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_quotaLoading)
                            const LinearProgressIndicator(minHeight: 2)
                          else if (_quota != null) ...[
                            Text(
                              _quota!.limitBytes != null
                                  ? '${_fb(_quota!.usedBytes)} / ${_fb(_quota!.limitBytes!)}'
                                  : _fb(_quota!.usedBytes),
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            if (_quota!.usedFraction != null) ...[
                              const SizedBox(height: Space.s),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _quota!.usedFraction,
                                  minHeight: 8,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  color: _quota!.isNearLimit
                                      ? AppColors.errorRed
                                      : theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.tr('quotaUsedFree').replaceAll('{pct}', (_quota!.usedFraction! * 100).toStringAsFixed(1)).replaceAll('{free}', _fb(_quota!.freeBytes ?? 0)),
                                style: theme.textTheme.bodySmall,
                              ),
                              if (_quota!.isNearLimit) ...[
                                const SizedBox(height: Space.s),
                                Row(
                                  children: [
                                    const Icon(AppIcons.warning,
                                        size: 16, color: AppColors.errorRed),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        l10n.tr('mailboxAlmostFull'),
                                        style: Theme.of(context).textTheme.bodySmall
                                            ?.copyWith(color: AppColors.errorText(context)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ] else
                              Text(l10n.tr('noLimitSet'),
                                  style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ),

                // Размер ящика (локальный кэш)
                SettingsSectionTitle(l10n.tr('mailboxSizeLocal')),
                _Panel(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_stats != null ? _fb(_stats!.bytes) : '—',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                            l10n
                                .tr('mailboxTextStored')
                                .replaceAll('{n}', '${_stats?.count ?? 0}')
                                .replaceAll('{m}', '${_stats?.withText ?? 0}'),
                            style: TextStyle(color: AppColors.mutedText(context))),
                        const SizedBox(height: Space.xs),
                        Text(
                          l10n.tr('mailboxSizeNote'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
                        ),
                      ],
                    ),
                  ),
                ),

                // Очистка по возрасту
                SettingsSectionTitle(l10n.tr('deleteOldMail')),
                Text(l10n.tr('deleteOldMailDesc'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in [30, 90, 180, 365])
                      ActionChip(
                        label: Text(l10n.tr('olderThanNDaysShort').replaceAll('{n}', '$d')),
                        onPressed: _busy ? null : () => _cleanup(l10n, olderThanDays: d, title: l10n.tr('olderThanNDays').replaceAll('{n}', '$d')),
                      ),
                    ActionChip(
                      avatar: const Icon(AppIcons.tune, size: 16),
                      label: Text(l10n.tr('customValue')),
                      onPressed: _busy ? null : () => _customDays(l10n),
                    ),
                  ],
                ),

                // Очистка по размеру
                SettingsSectionTitle(l10n.tr('deleteLargeMail')),
                Text(l10n.tr('deleteLargeMailDesc'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                const SizedBox(height: Space.s),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mb in [1, 5, 10, 25])
                      ActionChip(
                        label: Text(l10n.tr('largerThanNMbShort').replaceAll('{n}', '$mb')),
                        onPressed: _busy ? null : () => _cleanup(l10n, largerThanBytes: mb * 1024 * 1024, title: l10n.tr('largerThanNMb').replaceAll('{n}', '$mb')),
                      ),
                    ActionChip(
                      avatar: const Icon(AppIcons.tune, size: 16),
                      label: Text(l10n.tr('customValue')),
                      onPressed: _busy ? null : () => _customSize(l10n),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: Space.xl),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
    );
  }
}

/// Подложка раздела — как у групп настроек (SettingsGroup): цвет карточки,
/// тонкая граница, скругление 16.
class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.cardFill(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: child,
      );
}

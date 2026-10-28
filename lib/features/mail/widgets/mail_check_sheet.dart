// lib/features/mail/widgets/mail_check_sheet.dart
// «Проверка почты» (1.6.45): когда приложение в последний раз проверяло
// почту — по каждому ящику и в фоне, работает ли мгновенная доставка,
// включены ли уведомления; пробное уведомление и «Проверить сейчас».
//
// Зачем: жалоба тестировщиков «приложение засыпает» (19.10.2026) — снаружи
// не было видно, проверяет ли оно почту. Время последней проверки было лишь
// в настройках ящика, а нажатие на красную точку ошибки у названия папки не
// показывало ничего: текст уходил в скрытую плашку.
//
// Открывается нажатием на название папки в шапке ленты, на красную точку
// ошибки и пунктом «Проверка почты» в меню «⋮».

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../core/permissions/app_permissions.dart';
import '../../../core/platform/platform_diagnostics.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/background_journal.dart';
import '../../../services/notifications/notification_service.dart';
import '../../../services/sync/push_health.dart';
import '../../../services/sync/sync_schedule.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/sync_progress_indicator.dart';
import '../../../widgets/ui/settings_group.dart';
import '../providers/mail_providers.dart';

Future<void> showMailCheckSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (_) => const _MailCheckSheet(),
    );

class _MailCheckSheet extends ConsumerStatefulWidget {
  const _MailCheckSheet();

  @override
  ConsumerState<_MailCheckSheet> createState() => _MailCheckSheetState();
}

class _MailCheckSheetState extends ConsumerState<_MailCheckSheet> {
  ({DateTime at, String kind})? _bg;
  bool _bgLoaded = false;

  /// null — уведомления в порядке (или узнать нельзя); иначе что выключено.
  BgIssue? _notifOff;
  bool _checking = false;
  bool _testSent = false;

  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bg = await BackgroundJournal.lastBackgroundCheck();
    BgIssue? off;
    if (_mobile) {
      final issues = PlatformDiagnostics.issues(await PlatformDiagnostics.collect(light: true));
      if (issues.contains(BgIssue.notificationsOff)) {
        off = BgIssue.notificationsOff;
      } else if (issues.contains(BgIssue.mailChannelOff)) {
        off = BgIssue.mailChannelOff;
      }
    }
    if (!mounted) return;
    setState(() {
      _bg = bg;
      _bgLoaded = true;
      _notifOff = off;
    });
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final sync = ref.read(syncServiceProvider);
    try {
      // Явная просьба — свой проход, даже если идёт плановый.
      await sync.syncAll(fresh: true);
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _sendTest() async {
    final ok = await ref.read(notificationServiceProvider).showTestNotification();
    if (mounted) setState(() => _testSent = ok);
  }

  Future<void> _fixNotifications() async {
    if (_notifOff == BgIssue.mailChannelOff) {
      if (!await PlatformDiagnostics.openNotificationSettings()) await openAppSettings();
      return;
    }
    if (!mounted) return;
    await AppPermissions.ensure(context, AppPermission.notifications);
    await _load();
  }

  /// Меньше часа назад — «5 мин назад», сегодня — время, иначе день и время.
  static String _stamp(BuildContext c, DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (!diff.isNegative && diff < const Duration(hours: 1)) return AppDateFormat.relative(c, local);
    final today = local.year == now.year && local.month == now.month && local.day == now.day;
    return today ? AppDateFormat.time(c, local) : AppDateFormat.dayMonthTime(c, local);
  }

  static String _modeText(AppLocalizations l10n, AccountModel a) {
    if (SyncSchedule.pushNow(a)) {
      final alive = pushLastAlive(a.id);
      final ok = alive != null && DateTime.now().difference(alive) < const Duration(minutes: 25);
      return l10n.tr(ok ? 'mailCheckPushOn' : 'mailCheckPushOff');
    }
    return switch (a.syncInterval) {
      SyncInterval.push => l10n.tr('checkInstant'),
      SyncInterval.minutes5 => l10n.tr('checkEvery').replaceAll('{n}', '5'),
      SyncInterval.minutes15 => l10n.tr('checkEvery').replaceAll('{n}', '15'),
      SyncInterval.minutes30 => l10n.tr('checkEvery').replaceAll('{n}', '30'),
      SyncInterval.hour1 => l10n.tr('checkHourly'),
      SyncInterval.manual => l10n.tr('checkManual'),
      SyncInterval.scheduled => l10n.tr('checkScheduled'),
    };
  }

  static String _kindLabel(AppLocalizations l10n, String kind) => switch (kind) {
        'пульс' => l10n.tr('mailCheckKindPulse'),
        'WorkManager' => l10n.tr('mailCheckKindWork'),
        'сигнал iOS' => l10n.tr('mailCheckKindSignal'),
        _ => l10n.tr('mailCheckKindIos'),
      };

  Widget _accountRow(BuildContext context, AppLocalizations l10n, AccountModel a) {
    final last = ref.watch(lastSyncAtProvider(a.id)).value;
    final err = ref.read(syncServiceProvider).accountError(a.id);
    final line = [
      last == null
          ? '${l10n.tr('lastSynced')}: ${l10n.tr('lastSyncNever')}'
          : l10n.tr('mailCheckLast').replaceAll('{time}', _stamp(context, last)),
      _modeText(l10n, a),
    ].join(' · ');
    final problem = a.authFailedAt != null ? l10n.tr('mailCheckAuth') : (err == null ? null : '⚠ $err');
    return SettingsItem(
      leading: Icon(AppIcons.mail, color: Color(a.colorValue)),
      title: a.email,
      subtitle: problem == null ? line : '$line\n$problem',
      onTap: () {
        final router = GoRouter.of(context);
        Navigator.of(context).pop();
        unawaited(router.push('/settings/account/${Uri.encodeComponent(a.id)}'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
    // Ошибки ящиков и время — заново после каждой синхронизации.
    ref.watch(syncStatusProvider);
    final bg = _bg;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: Space.m, right: Space.m, bottom: Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.s),
            child: Text(l10n.tr('mailCheckTitle'), style: theme.textTheme.titleMedium),
          ),
          if (accounts.isNotEmpty) ...[
            SettingsSectionTitle(l10n.tr('mailCheckMailboxes')),
            SettingsGroup(children: [for (final a in accounts) _accountRow(context, l10n, a)]),
          ],
          if (_mobile) ...[
            SettingsSectionTitle(l10n.tr('mailCheckBackground'), help: l10n.tr('mailCheckBackgroundHelp')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.history,
                title: !_bgLoaded
                    ? '…'
                    : bg == null
                        ? l10n.tr('mailCheckBgNever')
                        : l10n.tr('mailCheckBgLast').replaceAll('{time}', _stamp(context, bg.at)),
                subtitle: bg == null ? null : _kindLabel(l10n, bg.kind),
                onTap: null,
              ),
            ]),
          ],
          SettingsSectionTitle(l10n.tr('notifications')),
          SettingsGroup(children: [
            if (_notifOff != null)
              SettingsItem(
                icon: AppIcons.notifications_off,
                title: l10n.tr(_notifOff == BgIssue.mailChannelOff ? 'mailChannelOffTitle' : 'notifOffStrip'),
                color: AppColors.errorText(context),
                onTap: _fixNotifications,
              ),
            SettingsItem(
              icon: AppIcons.notifications_active,
              title: l10n.tr('ntfTestAction'),
              subtitle: l10n.tr(_testSent ? 'ntfTestSent' : 'ntfTestHint'),
              onTap: _sendTest,
            ),
          ]),
          const SizedBox(height: Space.l),
          FilledButton.icon(
            onPressed: _checking ? null : _checkNow,
            icon: _checking
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(AppIcons.sync),
            label: Text(l10n.tr(_checking ? 'mailCheckRunning' : 'mailCheckNow')),
          ),
        ],
      ),
    );
  }
}

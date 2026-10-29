// lib/features/archive/screens/archive_screen.dart
// Настройки → «Архив Ogneliss» (1.7.3): создать или подключить архив,
// архивировать сейчас и по расписанию, что архивировать, копия архива
// (.ogna — на диск, в «Файлы», на Google Диск, iCloud Drive, Яндекс Диск),
// пароль и код восстановления, закрыть и удалить.
//
// Итог архивации и ошибки — строками на экране, без всплывающих окон.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../widgets/ui/action_sheet.dart';
import '../../../core/platform/file_pick.dart' show FilePick;
import '../../../core/security/secure_storage_service.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/archive/archive_app_settings.dart';
import '../../../services/archive/archive_db.dart' show ArchiveAccountInfo, ArchiveFolder, ArchiveSettingsSnapshot;
import '../../../services/backup/backup_service.dart' show BackupException;
import '../../../services/sync/sync_service.dart' show syncServiceProvider;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/archive/archive_runner.dart';
import '../../../services/archive/archive_settings.dart';
import '../../../services/archive/archive_vault.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../help/faq_screen.dart' show FaqButton;
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../archive_providers.dart';
import '../archive_sheets.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  bool _copyBusy = false;
  String? _copyNote;
  bool _copyError = false;

  bool _appBusy = false;
  String? _appNote;
  bool _appError = false;

  static bool get _desktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> _saveCopy(AppLocalizations l10n) async {
    setState(() {
      _copyBusy = true;
      _copyNote = null;
      _copyError = false;
    });
    final vault = ref.read(archiveVaultProvider.notifier);
    File? f;
    try {
      f = await vault.buildCopy();
      final name = p.basename(f.path);
      if (_desktop) {
        final saved = await FilePick.save(fileName: name, bytes: await f.readAsBytes(), dialogTitle: name);
        if (saved != null) {
          await vault.markCopied();
          _copyNote = l10n.tr('archiveCopySaved').replaceAll('{where}', saved.shown);
        }
      } else {
        // «Поделиться»: Google Диск, «Файлы» (iCloud Drive), Яндекс Диск,
        // папка на телефоне, флешка — куда выберет человек.
        final r = await SharePlus.instance.share(ShareParams(
          files: [XFile(f.path, name: name, mimeType: 'application/octet-stream')],
          subject: name,
        ));
        if (r.status != ShareResultStatus.dismissed) {
          await vault.markCopied();
          _copyNote = l10n.tr('archiveCopyShared').replaceAll('{name}', name);
        }
      }
    } catch (e) {
      _copyError = true;
      _copyNote = archiveErrorText(l10n, e);
    } finally {
      // Сборка копии во временной папке — не позже чем через 10 минут
      // удаляется (приложение-получатель успевает её забрать).
      final tmp = f;
      if (tmp != null) {
        unawaited(Future<void>.delayed(_desktop ? Duration.zero : const Duration(minutes: 10), () async {
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }));
      }
      if (mounted) setState(() => _copyBusy = false);
    }
  }

  Future<void> _saveAppSettings(AppLocalizations l10n) async {
    setState(() {
      _appBusy = true;
      _appNote = null;
      _appError = false;
    });
    final ok = await ref.read(archiveRunnerProvider.notifier).saveAppSettings();
    if (!mounted) return;
    setState(() {
      _appBusy = false;
      _appError = !ok;
      _appNote = ok ? null : l10n.tr('archiveAppSaveFailed');
    });
  }

  Future<void> _restoreAppSettings(AppLocalizations l10n, ArchiveSettingsSnapshot snap) async {
    final ok = await confirmDestructive(
      context,
      title: l10n.tr('archiveAppRestoreAsk'),
      message: l10n.tr('archiveAppRestoreAskBody'),
      action: l10n.tr('archiveAppRestore'),
    );
    if (!ok || !mounted) return;
    final adb = ref.read(archiveDbProvider);
    if (adb == null) return;
    setState(() {
      _appBusy = true;
      _appNote = null;
      _appError = false;
    });
    try {
      final report = await ArchiveAppSettings.restore(
        archive: adb,
        id: snap.id,
        db: ref.read(databaseProvider),
        prefs: ref.read(sharedPrefsProvider),
        secure: ref.read(secureStorageProvider),
      );
      await ref.read(accountsProvider.notifier).reload();
      // Новые ящики — сразу загрузить почту, календарь и контакты.
      if (report.accountsAdded > 0) unawaited(ref.read(syncServiceProvider).syncAll());
      if (!mounted) return;
      var text = l10n
          .tr('backupRestored')
          .replaceAll('{added}', '${report.accountsAdded}')
          .replaceAll('{skipped}', '${report.accountsSkipped}')
          .replaceAll('{settings}', '${report.settings}')
          .replaceAll('{sigs}', '${report.signatures}')
          .replaceAll('{notes}', '${report.notes}');
      if (!report.withSecrets && report.accountsAdded > 0) text += '\n${l10n.tr('backupRestoredNoSecrets')}';
      setState(() => _appNote = text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _appError = true;
          _appNote = e is BackupException ? l10n.tr(e.key) : '${l10n.tr('errorLbl')}: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _appBusy = false);
    }
  }

  List<Widget> _appSettingsSection(AppLocalizations l10n, ArchiveSettings settings, bool running) {
    final theme = Theme.of(context);
    final snaps = ref.watch(archiveSettingsSnapshotsProvider).value ?? const <ArchiveSettingsSnapshot>[];
    final last = snaps.firstOrNull;
    return [
      SettingsSectionTitle(l10n.tr('archiveAppSection'), help: l10n.tr('archiveAppHelp')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.settings_backup_restore,
          title: l10n.tr('archiveAppAuto'),
          subtitle: l10n.tr('archiveAppAutoDesc'),
          value: settings.appSettings,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setAppSettings(v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.key,
          title: l10n.tr('archiveAppSecrets'),
          subtitle: l10n.tr('archiveAppSecretsDesc'),
          value: settings.appSettingsSecrets,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setAppSettingsSecrets(v),
        ),
        SettingsItem(
          icon: AppIcons.save,
          title: l10n.tr('archiveAppSaveNow'),
          subtitle: last == null
              ? l10n.tr('archiveAppNone')
              : l10n
                  .tr('archiveAppLast')
                  .replaceAll('{date}', AppDateFormat.dateTime(context, last.created))
                  .replaceAll('{n}', '${last.accounts}'),
          trailing: _appBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: _appBusy || running ? null : () => _saveAppSettings(l10n),
        ),
        if (last != null)
          SettingsItem(
            icon: AppIcons.restore,
            title: l10n.tr('archiveAppRestore'),
            subtitle: l10n.tr('archiveAppRestoreSub'),
            onTap: _appBusy || running ? null : () => _restoreAppSettings(l10n, last),
          ),
        if (_appNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_appError ? AppIcons.error : AppIcons.check_circle,
                  size: 18, color: _appError ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(_appNote!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: _appError ? theme.colorScheme.error : theme.colorScheme.primary)),
              ),
            ]),
          ),
      ]),
    ];
  }

  Future<void> _delete(AppLocalizations l10n) async {
    final ok = await confirmDestructive(
      context,
      title: l10n.tr('archiveDeleteAsk'),
      message: l10n.tr('archiveDeleteAskBody'),
    );
    if (!ok || !mounted) return;
    await ref.read(archiveVaultProvider.notifier).deleteArchive();
  }

  Future<void> _pickInt({
    required String title,
    required List<int> options,
    required int value,
    required String Function(int) label,
    required Future<void> Function(int) onPick,
  }) async {
    // Карточкой (1.8.8), как меню «⋮»; текущее — с галочкой.
    final picked = await showChoiceSheet<int>(
      context,
      title: title,
      selected: value,
      entries: [for (final o in options) AppMenuEntry(value: o, label: label(o))],
    );
    if (picked != null) await onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vault = ref.watch(archiveVaultProvider);
    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(title: Text(l10n.tr('ognaArchive')), actions: const [FaqButton(section: 'archive')]),
      ),
      body: vault.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(archiveErrorText(l10n, e))),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: switch (s.status) {
            ArchiveStatus.none => _none(l10n),
            ArchiveStatus.locked => _locked(l10n),
            ArchiveStatus.open => _open(l10n, s),
          },
        ),
      ),
    );
  }

  List<Widget> _none(AppLocalizations l10n) => [
        SettingsIntro(l10n.tr('archiveIntro'), more: l10n.tr('archiveIntroMore'), moreTitle: l10n.tr('ognaArchive')),
        const SizedBox(height: Space.s),
        SettingsGroup(children: [
          SettingsItem(
            icon: AppIcons.inventory_2,
            title: l10n.tr('archiveCreate'),
            subtitle: l10n.tr('archiveCreateSub'),
            onTap: () => showArchiveCreateSheet(context),
          ),
          SettingsItem(
            icon: AppIcons.folder_open,
            title: l10n.tr('archiveConnectTitle'),
            subtitle: l10n.tr('archiveConnectSub'),
            onTap: () => showArchiveConnectSheet(context),
          ),
        ]),
        // Как пользоваться одним архивом на нескольких устройствах
        // (замечание 28.10.2026: «не понятно, как использовать один архив»).
        SettingsSectionTitle(l10n.tr('archiveDevicesSection')),
        SettingsGroup(children: [_TextBlock(l10n.tr('archiveDevicesHowNone'))]),
      ];

  List<Widget> _locked(AppLocalizations l10n) => [
        SettingsIntro(l10n.tr('archiveLockedIntro')),
        const SizedBox(height: Space.s),
        SettingsGroup(children: [
          SettingsItem(
            icon: AppIcons.lock_open,
            title: l10n.tr('archiveOpen'),
            subtitle: l10n.tr('archivePwOrCode'),
            onTap: () => showArchiveUnlockSheet(context),
          ),
          SettingsItem(
            icon: AppIcons.delete_forever,
            title: l10n.tr('archiveDelete'),
            color: Theme.of(context).colorScheme.error,
            onTap: () => _delete(l10n),
          ),
        ]),
      ];

  List<Widget> _open(AppLocalizations l10n, ArchiveVaultState s) {
    final theme = Theme.of(context);
    final settings = ref.watch(archiveSettingsProvider);
    final run = ref.watch(archiveRunnerProvider);
    final stats = ref.watch(archiveStatsProvider).value;
    final accounts = [for (final a in ref.watch(accountsProvider)) if (a.isActive && !a.isOnlineArchive) a];
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String months(int m) => l10n.plural('archiveOlderThanN', m);
    String days(int d) => l10n.plural('archiveEveryNDays', d);

    final lines = <String>[
      if (stats != null) ...[
        l10n
            .tr('archiveStatMail')
            .replaceAll('{n}', AppDateFormat.number(context, stats.messages))
            .replaceAll('{files}', AppDateFormat.number(context, stats.attachments))
            .replaceAll('{size}', AppDateFormat.bytes(context, stats.attachmentBytes)),
        if (stats.events + stats.tasks + stats.contacts > 0)
          l10n
              .tr('archiveStatOther')
              .replaceAll('{events}', '${stats.events}')
              .replaceAll('{tasks}', '${stats.tasks}')
              .replaceAll('{contacts}', '${stats.contacts}'),
        if (stats.oldest != null && stats.newest != null)
          l10n
              .tr('archiveStatPeriod')
              .replaceAll('{from}', AppDateFormat.date(context, stats.oldest!))
              .replaceAll('{to}', AppDateFormat.date(context, stats.newest!)),
      ],
    ];

    return [
      // ── Состояние ──
      SettingsSectionTitle(s.header?.name.isNotEmpty == true ? s.header!.name : l10n.tr('ognaArchive'),
          help: l10n.tr('archiveIntroMore')),
      SettingsGroup(children: [
        // Во всю ширину карточки: столбец группы выравнивает по центру —
        // цифры и кнопки стояли посередине, а не от края.
        SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Space.xs), child: Text(l)),
              if (lines.isEmpty) Text(l10n.tr('archiveEmpty')),
              Text(l10n.tr('archiveCreatedOn').replaceAll('{date}', AppDateFormat.date(context, s.header!.created)),
                  style: muted),
              if (!run.running) ...[
                // Главные действия — кнопками на виду (замечание 28.10.2026:
                // «нет кнопок»); итог прошлой архивации — строкой над ними.
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(_lastText(l10n, run.last), style: muted),
                ),
                const SizedBox(height: Space.m),
                Wrap(spacing: Space.s, runSpacing: Space.s, children: [
                  FilledButton.tonalIcon(
                    onPressed: () => showArchiveRunSheet(context),
                    icon: const Icon(AppIcons.play_arrow),
                    label: Text(l10n.tr('archiveRunNow')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/archive/search'),
                    icon: const Icon(AppIcons.search),
                    label: Text(l10n.tr('archiveSearchTitle')),
                  ),
                ]),
              ],
            ]),
          ),
        ),
        if (run.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LinearProgressIndicator(value: run.progress),
              const SizedBox(height: Space.s),
              Row(children: [
                Expanded(
                  child: Text(
                    run.stage == 'mail'
                        ? l10n.tr('archiveRunning').replaceAll('{done}', '${run.done}').replaceAll('{total}', '${run.total}')
                        : l10n.tr('archiveRunningOther'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: run.cancelling ? null : () => ref.read(archiveRunnerProvider.notifier).cancel(),
                  icon: const Icon(AppIcons.stop_circle, size: 18),
                  label: Text(l10n.tr('archiveStop')),
                ),
              ]),
            ]),
          ),
      ]),

      // ── Что в архиве: ящики ──
      ..._contents(l10n, accounts),

      // ── По расписанию ──
      SettingsSectionTitle(l10n.tr('archiveScheduleSection'), help: l10n.tr('archiveScheduleHelp')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.schedule,
          title: l10n.tr('archiveAuto'),
          subtitle: settings.auto
              ? '${days(settings.everyDays)} · ${months(settings.months)}'
              : l10n.tr('archiveAutoOff'),
          value: settings.auto,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setAuto(v),
        ),
        SettingsItem(
          icon: AppIcons.history,
          title: l10n.tr('archiveAge'),
          subtitle: months(settings.months),
          onTap: () => _pickInt(
            title: l10n.tr('archiveAge'),
            options: ArchiveSettings.monthOptions,
            value: settings.months,
            label: months,
            onPick: (v) => ref.read(archiveSettingsProvider.notifier).setMonths(v),
          ),
        ),
        SettingsItem(
          icon: AppIcons.autorenew,
          title: l10n.tr('archiveEvery'),
          subtitle: days(settings.everyDays),
          onTap: () => _pickInt(
            title: l10n.tr('archiveEvery'),
            options: ArchiveSettings.dayOptions,
            value: settings.everyDays,
            label: days,
            onPick: (v) => ref.read(archiveSettingsProvider.notifier).setEveryDays(v),
          ),
        ),
        SettingsSwitchItem(
          icon: AppIcons.wifi,
          title: l10n.tr('wifiOnlyAcc'),
          subtitle: l10n.tr('archiveWifiDesc'),
          value: settings.wifiOnly,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setWifiOnly(v),
        ),
      ]),

      // ── Что архивировать ──
      SettingsSectionTitle(l10n.tr('archiveWhatSection')),
      SettingsGroup(children: [
        SettingsSwitchItem(
          icon: AppIcons.mail,
          title: l10n.tr('archiveKindMail'),
          subtitle: l10n.tr('archiveKindMailDesc'),
          hint: l10n.tr('archivePeriodHint'),
          value: settings.mail,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setKind('mail', v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.flag,
          title: l10n.tr('archiveIncludeFlagged'),
          subtitle: l10n.tr('archiveIncludeFlaggedDesc'),
          value: settings.includeFlagged,
          onChanged: settings.mail ? (v) => ref.read(archiveSettingsProvider.notifier).setIncludeFlagged(v) : null,
        ),
        SettingsSwitchItem(
          icon: AppIcons.delete_sweep,
          title: l10n.tr('archiveDeleteFromServer'),
          subtitle: l10n.tr(settings.deleteFromServer ? 'archiveDeleteFromServerOn' : 'archiveDeleteFromServerOff'),
          value: settings.deleteFromServer,
          onChanged: settings.mail ? (v) => ref.read(archiveSettingsProvider.notifier).setDeleteFromServer(v) : null,
        ),
        SettingsSwitchItem(
          icon: AppIcons.event,
          title: l10n.tr('archiveKindEvents'),
          subtitle: l10n.tr('archiveKindEventsDesc'),
          value: settings.events,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setKind('events', v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.check_box,
          title: l10n.tr('archiveKindTasks'),
          subtitle: l10n.tr('archiveKindTasksDesc'),
          value: settings.tasks,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setKind('tasks', v),
        ),
        SettingsSwitchItem(
          icon: AppIcons.contacts,
          title: l10n.tr('archiveKindContacts'),
          subtitle: l10n.tr('archiveKindContactsDesc'),
          value: settings.contacts,
          onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setKind('contacts', v),
        ),
      ]),
      if (accounts.isNotEmpty) ...[
        SettingsSectionTitle(l10n.tr('archiveAccountsSection'), help: l10n.tr('archiveAccountsHelp')),
        SettingsGroup(children: [
          for (final a in accounts)
            SettingsSwitchItem(
              icon: AppIcons.alternate_email,
              title: a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email,
              subtitle: a.email,
              value: !settings.skipAccounts.contains(a.id),
              onChanged: (v) => ref.read(archiveSettingsProvider.notifier).setAccount(a.id, v),
            ),
        ]),
      ],

      // ── Настройки приложения в архиве (25.10.2026) ──
      ..._appSettingsSection(l10n, settings, run.running),

      // ── Другие устройства и облако (28.10.2026) ──
      SettingsSectionTitle(l10n.tr('archiveDevicesSection'), help: l10n.tr('archiveCopyHelp')),
      SettingsGroup(children: [
        _TextBlock(l10n.tr('archiveDevicesHow')),
        SettingsItem(
          icon: AppIcons.cloud_upload,
          title: l10n.tr('archiveCopySave'),
          subtitle: s.lastCopy == null
              ? l10n.tr('archiveCopyNever')
              : l10n.tr('archiveCopyLast').replaceAll('{date}', AppDateFormat.date(context, s.lastCopy!)),
          trailing: _copyBusy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
          onTap: _copyBusy || run.running ? null : () => _saveCopy(l10n),
        ),
        if (_copyNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(_copyError ? AppIcons.error : AppIcons.check_circle,
                  size: 18, color: _copyError ? theme.colorScheme.error : theme.colorScheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(_copyNote!,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: _copyError ? theme.colorScheme.error : theme.colorScheme.primary)),
              ),
            ]),
          ),
        SettingsItem(
          icon: AppIcons.merge,
          title: l10n.tr('archiveMergeTitle'),
          subtitle: l10n.tr('archiveMergeSub'),
          onTap: _copyBusy || run.running ? null : () => showArchiveConnectSheet(context, merge: true),
        ),
      ]),

      // ── Защита ──
      SettingsSectionTitle(l10n.tr('archiveSecuritySection')),
      SettingsGroup(children: [
        SettingsItem(
          icon: AppIcons.key,
          title: l10n.tr('archivePwChange'),
          onTap: () => showArchivePasswordSheet(context),
        ),
        SettingsItem(
          icon: AppIcons.lock_reset,
          title: l10n.tr('archiveNewCode'),
          subtitle: l10n.tr('archiveNewCodeSub'),
          onTap: () => showArchiveNewCodeSheet(context),
        ),
        SettingsItem(
          icon: AppIcons.lock,
          title: l10n.tr('archiveLock'),
          subtitle: l10n.tr('archiveLockSub'),
          onTap: run.running ? null : () => ref.read(archiveVaultProvider.notifier).lock(),
        ),
        SettingsItem(
          icon: AppIcons.delete_forever,
          title: l10n.tr('archiveDelete'),
          color: theme.colorScheme.error,
          onTap: run.running ? null : () => _delete(l10n),
        ),
      ]),
    ];
  }

  /// Ящики в архиве: у каждого своя ветка папок; нажатие открывает его
  /// «Входящие» в архиве. Ящик, которого на устройстве нет (архив с другого
  /// устройства), — с пометкой.
  List<Widget> _contents(AppLocalizations l10n, List<AccountModel> onDevice) {
    final inArchive = ref.watch(archiveAccountsProvider).value ?? const <ArchiveAccountInfo>[];
    if (inArchive.isEmpty) return const [];
    final folders = ref.watch(archiveFoldersProvider).value ?? const <ArchiveFolder>[];
    final here = {for (final a in onDevice) a.email.trim().toLowerCase()};
    int? start(String accountId) {
      final roots = [for (final f in folders) if (f.accountId == accountId && f.parentId == null) f];
      return (roots.where((f) => f.type == 'inbox').firstOrNull ?? roots.firstOrNull)?.id;
    }

    return [
      SettingsSectionTitle(l10n.tr('archiveContentsSection'), help: l10n.tr('archiveContentsHelp')),
      SettingsGroup(children: [
        for (final a in inArchive)
          SettingsItem(
            icon: AppIcons.alternate_email,
            title: a.label,
            subtitle: [
              if (a.label != a.email) a.email,
              l10n.tr('archiveAccountMails').replaceAll('{n}', AppDateFormat.number(context, a.messages)),
              if (!here.contains(a.email.trim().toLowerCase())) l10n.tr('archiveAccountOtherDevice'),
            ].join(' · '),
            onTap: switch (start(a.id)) {
              final int id => () => context.push('/archive/folder/$id'),
              null => null,
            },
          ),
      ]),
    ];
  }

  String _lastText(AppLocalizations l10n, ArchiveRunResult? r) {
    if (r == null) return l10n.tr('archiveRunNever');
    final when = AppDateFormat.dateTime(context, r.at);
    if (r.errorKey != null && r.nothing) return '$when · ${l10n.tr(r.errorKey!)}';
    final parts = <String>[
      l10n.plural('archiveNMails', r.mails),
      if (r.events > 0) l10n.plural('archiveNEvents', r.events),
      if (r.tasks > 0) l10n.plural('archiveNTasks', r.tasks),
      if (r.contacts > 0) l10n.plural('archiveNContacts', r.contacts),
    ];
    var text = '$when · ${parts.join(', ')}';
    // Писем не нашлось — сказать почему, а не просто «0 писем».
    if (r.mails == 0 && r.failed == 0 && !r.cancelled && r.errorKey == null) {
      text += '\n${l10n.tr('archiveNothingOld')}';
    }
    if (r.failed > 0) text += '\n${l10n.tr('archiveFailedN').replaceAll('{n}', '${r.failed}')}';
    if (r.cancelled) text += '\n${l10n.tr('archiveStopped')}';
    if (r.errorKey != null) text += '\n${l10n.tr(r.errorKey!)}';
    return text;
  }
}

/// Абзац пояснения внутри группы (как строка группы, без нажатия).
class _TextBlock extends StatelessWidget {
  final String text;
  const _TextBlock(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
      child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

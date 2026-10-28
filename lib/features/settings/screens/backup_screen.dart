// lib/features/settings/screens/backup_screen.dart
// Настройки → «Резервная копия и перенос»: сохранить ящики и настройки в
// зашифрованный файл и восстановить их на новом телефоне. Ошибки и итог —
// строками на экране, без всплывающих окон.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../core/platform/file_pick.dart' show FilePick;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/backup/backup_service.dart';
import '../../../services/sync/sync_service.dart' show syncServiceProvider;
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  // Создание
  bool _withSecrets = true;
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busyCreate = false;
  String? _createError;
  String? _createDone;

  // Восстановление
  Uint8List? _file;
  String? _fileName;
  final _pwRestore = TextEditingController();
  bool _busyRestore = false;
  String? _restoreError;
  String? _restoreDone;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    _pwRestore.dispose();
    super.dispose();
  }

  Future<void> _create(AppLocalizations l10n) async {
    setState(() {
      _createError = null;
      _createDone = null;
    });
    if (_pw1.text.length < 8) {
      setState(() => _createError = l10n.tr('backupPwShort'));
      return;
    }
    if (_pw1.text != _pw2.text) {
      setState(() => _createError = l10n.tr('backupPwMismatch'));
      return;
    }
    setState(() => _busyCreate = true);
    try {
      final bytes = await BackupService.create(
        db: ref.read(databaseProvider),
        prefs: ref.read(sharedPrefsProvider),
        secure: ref.read(secureStorageProvider),
        passphrase: _pw1.text,
        includeSecrets: _withSecrets,
        appVersion: AppConstants.appVersion,
      );
      final d = DateTime.now();
      final name = 'ogneliss-mail-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.ognbak';
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      // «Поделиться»: сохранить в «Файлы», на Диск, отправить себе.
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, name: name)], subject: name));
      if (!mounted) return;
      setState(() => _createDone = l10n.tr('backupCreated').replaceAll('{name}', name));
    } catch (e) {
      if (mounted) setState(() => _createError = '${l10n.tr('errorLbl')}: $e');
    } finally {
      if (mounted) setState(() => _busyCreate = false);
    }
  }

  Future<void> _pick(AppLocalizations l10n) async {
    setState(() {
      _restoreError = null;
      _restoreDone = null;
    });
    final f = await FilePick.file();
    if (f == null) return;
    final bytes = await f.readBytes();
    if (!mounted) return;
    setState(() {
      _file = bytes;
      _fileName = f.name;
    });
  }

  Future<void> _restore(AppLocalizations l10n) async {
    final bytes = _file;
    if (bytes == null) return;
    setState(() {
      _restoreError = null;
      _restoreDone = null;
    });
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('backupRestoreQ')),
        content: Text(l10n.tr('backupRestoreQBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('backupRestore'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyRestore = true);
    try {
      final payload = await BackupService.open(bytes, _pwRestore.text);
      final report = await BackupService.restore(
        payload: payload,
        db: ref.read(databaseProvider),
        prefs: ref.read(sharedPrefsProvider),
        secure: ref.read(secureStorageProvider),
      );
      await ref.read(accountsProvider.notifier).reload();
      // Новые ящики — сразу загрузить почту, календарь, контакты.
      if (report.accountsAdded > 0) unawaited(ref.read(syncServiceProvider).syncAll());
      if (!mounted) return;
      setState(() {
        _restoreDone = l10n
            .tr('backupRestored')
            .replaceAll('{added}', '${report.accountsAdded}')
            .replaceAll('{skipped}', '${report.accountsSkipped}')
            .replaceAll('{settings}', '${report.settings}')
            .replaceAll('{sigs}', '${report.signatures}')
            .replaceAll('{notes}', '${report.notes}');
        if (!report.withSecrets && report.accountsAdded > 0) {
          _restoreDone = '${_restoreDone!}\n${l10n.tr('backupRestoredNoSecrets')}';
        }
      });
    } on BackupException catch (e) {
      if (mounted) setState(() => _restoreError = l10n.tr(e.key));
    } catch (e) {
      if (mounted) setState(() => _restoreError = '${l10n.tr('errorLbl')}: $e');
    } finally {
      if (mounted) setState(() => _busyRestore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget note(String? text, {required bool error}) {
      if (text == null) return const SizedBox.shrink();
      final c = error ? theme.colorScheme.error : theme.colorScheme.primary;
      return Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(error ? AppIcons.error : AppIcons.check_circle, size: 18, color: c),
            const SizedBox(width: Space.s),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: c))),
          ],
        ),
      );
    }

    InputDecoration pw(String label) => InputDecoration(labelText: label, prefixIcon: const Icon(AppIcons.key));

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('backupTitle')), actions: [
        HelpButton(text: l10n.tr('backupIntro'), title: l10n.tr('backupTitle')),
      ])),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [

          // ── Создать ──
          SettingsSectionTitle(l10n.tr('backupCreateTitle')),
          SettingsGroup(children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              secondary: Icon(AppIcons.key, color: theme.colorScheme.primary),
              title: Text(l10n.tr('backupWithSecrets')),
              subtitle: Text(l10n.tr('backupWithSecretsDesc')),
              value: _withSecrets,
              onChanged: (v) => setState(() => _withSecrets = v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: TextField(controller: _pw1, obscureText: true, autocorrect: false, enableSuggestions: false,
                  decoration: pw(l10n.tr('backupPw'))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: TextField(controller: _pw2, obscureText: true, autocorrect: false, enableSuggestions: false,
                  decoration: pw(l10n.tr('backupPwRepeat'))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: Text(l10n.tr('backupPwHint'), style: theme.textTheme.bodySmall),
            ),
            note(_createError, error: true),
            note(_createDone, error: false),
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: FilledButton.icon(
                onPressed: _busyCreate ? null : () => _create(l10n),
                icon: _busyCreate
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(AppIcons.share),
                label: Text(l10n.tr('backupCreate')),
              ),
            ),
          ]),

          // ── Восстановить ──
          SettingsSectionTitle(l10n.tr('backupRestoreTitle')),
          SettingsGroup(children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
              leading: Icon(AppIcons.folder_open, color: theme.colorScheme.primary),
              title: Text(_fileName ?? l10n.tr('backupPick')),
              subtitle: _fileName == null ? Text(l10n.tr('backupPickDesc')) : null,
              onTap: _busyRestore ? null : () => _pick(l10n),
            ),
            if (_file != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 0),
                child: TextField(controller: _pwRestore, obscureText: true, autocorrect: false,
                    enableSuggestions: false, decoration: pw(l10n.tr('backupPw'))),
              ),
            note(_restoreError, error: true),
            note(_restoreDone, error: false),
            if (_file != null)
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: FilledButton.icon(
                  onPressed: _busyRestore ? null : () => _restore(l10n),
                  icon: _busyRestore
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.restore),
                  label: Text(l10n.tr('backupRestore')),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

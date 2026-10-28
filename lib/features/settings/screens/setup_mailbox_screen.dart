// lib/features/settings/screens/setup_mailbox_screen.dart
// Первая настройка, шаг 2 (1.6.12, замечание владельца 17.10.2026: «человек
// должен получать работающее приложение сразу, а не разбираться в
// настройках, почему у него отображается не вся почта или события не
// отображаются в календаре»). После разрешений (шаг 1 — «Разрешения» в
// режиме настройки):
//  · контакты и встречи ящика — в «Контакты» и «Календарь» телефона;
//  · какие папки синхронизировать — сейчас или позже.
// Показывается один раз после входа в первый ящик (AppPermissions.maybeShowSetup).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/folder_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/device/phone_mirror_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart';

class SetupMailboxScreen extends ConsumerStatefulWidget {
  const SetupMailboxScreen({super.key});

  @override
  ConsumerState<SetupMailboxScreen> createState() => _SetupMailboxScreenState();
}

class _SetupMailboxScreenState extends ConsumerState<SetupMailboxScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool contacts, bool on) async {
    final account = ref.read(activeAccountProvider);
    if (account == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(phoneMirrorProvider);
    final ok = contacts ? await svc.setContacts(account, on) : await svc.setCalendar(account, on);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = l10n.tr('phoneMirrorFailed');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final account = ref.watch(activeAccountProvider);
    final mirror = ref.read(phoneMirrorProvider);
    final folders = account == null
        ? const <FolderModel>[]
        : ref.watch(accountFoldersProvider(account.id)).value ?? const <FolderModel>[];
    final synced = [for (final f in folders) if (f.isSynced) f];
    final names = synced.take(6).map((f) => f.displayName).join(', ');
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('setupMailboxTitle')),
        automaticallyImplyLeading: false,
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, Space.s),
            child: Text(l10n.tr('setupMailboxIntro'),
                style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
          ),
          if (account != null && mirror.isAvailable) ...[
            SettingsSectionTitle(l10n.tr('phoneMirror')),
            SettingsGroup(children: [
              SettingsSwitchItem(
                icon: AppIcons.contacts,
                title: l10n.tr('phoneMirrorContacts'),
                hint: l10n.tr('phoneMirrorContactsDesc'),
                value: mirror.contactsOn(account.id),
                onChanged: _busy ? null : (v) => _toggle(true, v),
              ),
              SettingsSwitchItem(
                icon: AppIcons.event,
                title: l10n.tr('phoneMirrorCalendar'),
                hint: l10n.tr('phoneMirrorCalendarDesc'),
                value: mirror.calendarOn(account.id),
                onChanged: _busy ? null : (v) => _toggle(false, v),
              ),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.xs, Space.xs, 0),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ],
          if (account != null) ...[
            SettingsSectionTitle(l10n.tr('folderSync')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.folder,
                title: l10n.tr('setupFoldersTitle').replaceAll('{n}', '${synced.length}'),
                subtitle: names.isEmpty ? null : (synced.length > 6 ? '$names…' : names),
                hint: l10n.tr('setupFoldersHint'),
                trailing: const Icon(AppIcons.chevron_right),
                onTap: () => context.push('/settings/folder-sync?accountId=${Uri.encodeQueryComponent(account.id)}'),
              ),
            ]),
          ],
          const SizedBox(height: Space.l),
          FilledButton(
            onPressed: () => context.go('/mail'),
            child: Text(l10n.tr('setupDone')),
          ),
          const SizedBox(height: Space.xs),
          TextButton(
            onPressed: () => context.go('/mail'),
            child: Text(l10n.tr('setupLater')),
          ),
        ],
      ),
    );
  }
}

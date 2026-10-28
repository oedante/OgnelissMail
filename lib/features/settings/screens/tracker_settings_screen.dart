// lib/features/settings/screens/tracker_settings_screen.dart
// Блокировка трекеров целиком: включение, что именно заблокировано (сервисы
// отслеживания и письма, в которых скрыты картинки), разблокировка сервиса,
// доверие отправителю, удаление записей. Раньше в шторке было только
// «Заблокировано: N» — ни что это, ни как разблокировать.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/tracker_blocker.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../../widgets/ui/confirm_dialog.dart';

class TrackerSettingsScreen extends ConsumerWidget {
  const TrackerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = ref.watch(trackerBlockerProvider);
    final n = ref.read(trackerBlockerProvider.notifier);
    final hosts = t.byHost.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    Widget section(String text) => SettingsSectionTitle(text);
    Widget hint(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        );

    return Scaffold(
      appBar: TextScaleCapBar(
        child: AppBar(
          title: Text(l10n.tr('trackerBlocker')),
          actions: [
            if (t.byHost.isNotEmpty || t.recent.isNotEmpty || t.totalBlocked > 0)
              IconButton(
                tooltip: l10n.tr('trackerClearLog'),
                icon: const Icon(AppIcons.delete_sweep),
                onPressed: () async {
                  final ok = await confirmDestructive(context,
                      title: l10n.tr('trackerClearLog'),
                      message: l10n.tr('trackerClearLogDesc'),
                      action: l10n.tr('reset'));
                  if (ok) n.clearStats();
                },
              ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
        children: [
          hint(l10n.tr('trackerBlockerDesc')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.visibility_off,
              title: l10n.tr('trackerBlocker'),
              value: t.isEnabled,
              onChanged: n.setEnabled,
            ),
            SettingsSwitchItem(
              icon: AppIcons.image_not_supported,
              title: l10n.tr('blockExternalImages'),
              subtitle: l10n.tr('trackerExternalDesc'),
              value: t.blockExternalImages,
              onChanged: t.isEnabled ? n.setBlockExternalImages : null,
            ),
            SettingsItem(
              icon: AppIcons.analytics,
              title: '${l10n.tr('trackersBlocked')}: ${t.totalBlocked}',
              onTap: null,
            ),
          ]),

          // ── Сервисы отслеживания ──
          section(l10n.tr('trackerTopHosts')),
          if (hosts.isEmpty) hint(l10n.tr('trackerNoneYet')),
          if (hosts.isNotEmpty) SettingsGroup(children: [
          for (final e in hosts)
            ListTile(
              leading: const Icon(AppIcons.visibility_off),
              title: Text(e.key),
              subtitle: Text(l10n.tr('trackerTimesN').replaceAll('{n}', '${e.value}')),
              trailing: PopupMenuButton<String>(
                tooltip: l10n.tr('more'),
                onSelected: (v) => v == 'allow' ? n.allowHost(e.key) : n.forgetHost(e.key),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'allow', child: Text(l10n.tr('trackerAllowHost'))),
                  PopupMenuItem(value: 'forget', child: Text(l10n.tr('trackerForget'))),
                ],
              ),
            ),
          ]),

          // ── Разблокированные ──
          if (t.allowedHosts.isNotEmpty) ...[
            section(l10n.tr('trackerAllowedHosts')),
            hint(l10n.tr('trackerAllowedHostsDesc')),
            SettingsGroup(children: [
            for (final h in t.allowedHosts)
              ListTile(
                leading: const Icon(AppIcons.lock_open),
                title: Text(h),
                trailing: TextButton(
                  onPressed: () => n.disallowHost(h),
                  child: Text(l10n.tr('trackerBlockAgain')),
                ),
              ),
            ]),
          ],

          // ── Письма ──
          section(l10n.tr('trackerRecentMail')),
          if (t.recent.isEmpty) hint(l10n.tr('trackerNoneYet')),
          if (t.recent.isNotEmpty) SettingsGroup(children: [
          for (final e in t.recent)
            ListTile(
              leading: Icon(e.hosts.isNotEmpty ? AppIcons.visibility_off : AppIcons.image_not_supported),
              title: Text(e.subject.isEmpty ? e.sender : '${e.sender} · ${e.subject}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  AppDateFormat.relative(context, e.at),
                  if (e.hosts.isNotEmpty) e.hosts.join(', '),
                  if (e.images > 0) l10n.tr('trackerImagesHiddenN').replaceAll('{n}', '${e.images}'),
                ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: PopupMenuButton<String>(
                tooltip: l10n.tr('more'),
                onSelected: (v) {
                  if (v == 'trust' && e.senderDomain.isNotEmpty) n.addWhitelist(e.senderDomain);
                  if (v == 'forget') n.forgetEntry(e.key);
                  if (v.startsWith('allow:')) n.allowHost(v.substring(6));
                },
                itemBuilder: (_) => [
                  if (e.senderDomain.isNotEmpty && !t.whitelistedDomains.contains(e.senderDomain))
                    PopupMenuItem(
                      value: 'trust',
                      child: Text(l10n.tr('trackerTrustSender').replaceAll('{domain}', e.senderDomain)),
                    ),
                  for (final h in e.hosts.where((h) => !t.allowedHosts.contains(h)))
                    PopupMenuItem(
                      value: 'allow:$h',
                      child: Text('${l10n.tr('trackerAllowHost')}: $h'),
                    ),
                  PopupMenuItem(value: 'forget', child: Text(l10n.tr('trackerForget'))),
                ],
              ),
            ),
          ]),

          // ── Доверенные отправители ──
          section(l10n.tr('whitelistedDomains')),
          hint(l10n.tr('imageAllowlistDesc')),
          SettingsGroup(children: [
          for (final d in t.whitelistedDomains)
            ListTile(
              leading: const Icon(AppIcons.public),
              title: Text(d),
              trailing: IconButton(
                tooltip: l10n.tr('delete'),
                icon: const Icon(AppIcons.close),
                onPressed: () => n.removeWhitelist(d),
              ),
            ),
          SettingsItem(
            icon: AppIcons.add,
            title: l10n.tr('trustedDomain'),
            onTap: () => _addDomain(context, n, l10n),
          ),
          ]),
        ],
      ),
    );
  }

  Future<void> _addDomain(BuildContext context, TrackerBlockerNotifier n, AppLocalizations l10n) async {
    final ctrl = TextEditingController();
    final domain = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('trustedDomain')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'example.com'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(l10n.tr('add'))),
        ],
      ),
    );
    ctrl.dispose();
    final d = (domain ?? '').trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (d.isNotEmpty && d.contains('.')) n.addWhitelist(d);
  }
}

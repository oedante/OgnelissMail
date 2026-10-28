// lib/features/settings/screens/security_settings_screen.dart
// Настройки безопасности соединения: режим certificate pinning,
// доверенные домены (приём корп. CA) и правила пиннинга (домен → SHA-256).

import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/certificate_pinning_service.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/ca_certificates_section.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../../widgets/ui/confirm_dialog.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  late CertificatePinningService _svc;

  @override
  void initState() {
    super.initState();
    _svc = ref.read(certPinningProvider);
  }

  String _modeLabel(PinningMode m, AppLocalizations l10n) {
    switch (m) {
      case PinningMode.off: return l10n.tr('pinOffLabel');
      case PinningMode.trustStore: return l10n.tr('pinTrustStoreLabel');
      case PinningMode.pinned: return l10n.tr('pinPinnedLabel');
    }
  }

  String _modeDesc(PinningMode m, AppLocalizations l10n) {
    switch (m) {
      case PinningMode.off: return l10n.tr('pinOffDesc');
      case PinningMode.trustStore: return l10n.tr('pinTrustStoreDesc');
      case PinningMode.pinned: return l10n.tr('pinPinnedDesc');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('connectionSecurity')))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
        children: [
          // ── Центры сертификации: Минцифры, с устройства, импортированные ──
          const CaCertificatesSection(),

          // ── Доверенные хосты и домены (самоподписанный сертификат или
          // корпоративный центр сертификации). Раньше один и тот же список
          // показывался на экране дважды — в двух разделах с разными
          // названиями и разными кнопками «Добавить».
          SettingsSectionTitle(l10n.tr('trustedSelfSignedHosts')),
          _hint(context, l10n.tr('trustedHostsDesc')),
          SettingsGroup(children: [
            if (_svc.trustedCaDomains.isEmpty)
              SettingsItem(icon: AppIcons.verified_user, title: l10n.tr('listEmpty'), onTap: null),
            for (final d in _svc.trustedCaDomains)
              SettingsItem(
                icon: AppIcons.verified_user,
                title: d,
                trailing: IconButton(
                  tooltip: l10n.tr('delete'),
                  icon: const Icon(AppIcons.close, size: Sizes.iconRow),
                  onPressed: () async {
                    await _svc.removeTrustedCaDomain(d);
                    if (mounted) setState(() {});
                  },
                ),
                onTap: null,
              ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('addHost'),
              trailing: const SizedBox.shrink(),
              onTap: _addTrustedHost,
            ),
          ]),

          // ── Режим проверки сертификатов — только в отладочной сборке ──
          // В выпускаемой «принимать все» не действует, а «строгий пиннинг»
          // работал так же, как стандартная проверка: правила сверяются,
          // только когда система сертификату не доверяет (1.6.2). Выбор,
          // который ничего не меняет, убран; правила ниже работают всегда.
          if (!kReleaseMode) ...[
          SettingsSectionTitle(l10n.tr('certCheckMode')),
          SettingsGroup(children: [
            for (final m in PinningMode.values)
              AppRadioTile<PinningMode>(
                title: Text(_modeLabel(m, l10n)),
                subtitle: Text(_modeDesc(m, l10n)),
                value: m,
                groupValue: _svc.mode,
                onChanged: (v) async {
                  await _svc.setMode(v!);
                  setState(() {});
                },
              ),
          ]),
          ],

          // ── Правила пиннинга ──
          SettingsSectionTitle(l10n.tr('pinningRules')),
          _hint(context, l10n.tr('pinningRulesDesc')),
          SettingsGroup(children: [
            if (_svc.rules.isEmpty)
              SettingsItem(icon: AppIcons.rule, title: l10n.tr('pinNoRules'), onTap: null),
            for (final r in _svc.rules)
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(AppIcons.verified_user, color: theme.colorScheme.primary),
                // «=host» — сертификат, принятый при входе, только для этого хоста.
                title: Text(r.domain.startsWith('=') ? r.domain.substring(1) : r.domain),
                subtitle: Text('${r.sha256Fingerprints.length} ${l10n.tr('fingerprintsCount')}'),
                children: [
                  for (final fp in r.sha256Fingerprints)
                    ListTile(
                      dense: true,
                      title: Text(fp, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: l10n.tr('copy'),
                        icon: const Icon(AppIcons.content_copy, size: Sizes.iconInline),
                        onPressed: () => Clipboard.setData(ClipboardData(text: fp)),
                      ),
                    ),
                  TextButton.icon(
                    icon: Icon(AppIcons.delete, color: theme.colorScheme.error),
                    label: Text(l10n.tr('deleteRule'), style: TextStyle(color: theme.colorScheme.error)),
                    onPressed: () async {
                      final ok = await confirmDestructive(context, title: l10n.tr('deleteRule'), message: r.domain);
                      if (!ok) return;
                      await _svc.removeRule(r.domain);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            SettingsItem(
              icon: AppIcons.add,
              title: l10n.tr('addPinRule'),
              trailing: const SizedBox.shrink(),
              onTap: _addPinRule,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
        child: Text(text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
      );

  Future<void> _addTrustedHost() async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('trustedHost')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'mail.example.com / 217.114.43.126'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('add'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await _svc.ensureTrustedCaDomain(ctrl.text.trim());
      if (mounted) setState(() {});
    }
    ctrl.dispose();
  }

  Future<void> _addPinRule() async {
    final l10n = AppLocalizations.of(context);
    final domainCtrl = TextEditingController();
    final fpCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('addPinRule')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: domainCtrl, decoration: InputDecoration(labelText: l10n.tr('domain'))),
            const SizedBox(height: Space.s),
            TextField(
              controller: fpCtrl,
              decoration: InputDecoration(labelText: l10n.tr('sha256FieldLabel')),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('add'))),
        ],
      ),
    );
    if (result == true && domainCtrl.text.trim().isNotEmpty) {
      final fps = fpCtrl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await _svc.addRule(PinRule(domain: domainCtrl.text.trim(), sha256Fingerprints: fps));
      setState(() {});
    }
  }
}

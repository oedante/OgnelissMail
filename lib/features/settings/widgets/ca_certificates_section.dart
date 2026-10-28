// lib/features/settings/widgets/ca_certificates_section.dart
// «Безопасность соединения → Центры сертификации»: встроенные сертификаты
// Минцифры, сертификаты ЦС с устройства, импорт своих и сохранение файла для
// установки на устройство (требование ИБ — ЦС ставится в систему).

import 'dart:io' show Platform;
import '../../../core/theme/app_icons.dart';

import '../../../core/platform/file_pick.dart' show FilePick;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/security/trusted_ca_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/settings_group.dart';

class CaCertificatesSection extends StatefulWidget {
  const CaCertificatesSection({super.key});

  @override
  State<CaCertificatesSection> createState() => _CaCertificatesSectionState();
}

class _CaCertificatesSectionState extends State<CaCertificatesSection>
    with WidgetsBindingObserver {
  static const _security = MethodChannel('ogneliss/device_security');
  TrustedCaStore? get _store => TrustedCaStore.instance;
  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Вернулись из системных настроек — сертификат могли установить.
  @override
  // Переопределение void-метода WidgetsBindingObserver.
  // ignore: avoid_void_async
  void didChangeAppLifecycleState(AppLifecycleState s) async {
    if (s == AppLifecycleState.resumed && _android) {
      await _store?.reloadDevice();
      if (mounted) setState(() {});
    }
  }

  // Всплывающие уведомления в приложении отключены, поэтому результат
  // действий показывается строкой прямо в разделе.
  bool _needRestart = false;
  String? _status;

  void _restartNote() => _needRestart = true;

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final file = await FilePick.file();
    if (file == null || _store == null) return;
    final bytes = await file.readBytes();
    final added = await _store!.importBytes(bytes);
    if (!mounted) return;
    setState(() => _status = added.isEmpty
        ? l10n.tr('caImportNone')
        : l10n.tr('caImported').replaceAll('{n}', '${added.length}'));
  }

  /// Сохранить файл сертификата и открыть настройки безопасности Android:
  /// с Android 11 приложение не может само поставить ЦС в систему, это
  /// делает пользователь (или MDM).
  Future<void> _installOnDevice(CaCertInfo c) async {
    final l10n = AppLocalizations.of(context);
    final name = '${c.commonName.replaceAll(RegExp(r'[^A-Za-z0-9А-Яа-я_-]+'), '_')}.crt';
    final saved = await FilePick.save(
      dialogTitle: l10n.tr('caSaveForDevice'),
      fileName: name,
      bytes: Uint8List.fromList(c.der),
    );
    if (saved == null || !mounted) return;
    if (!_android) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(AppIcons.verified_user),
        title: Text(l10n.tr('caInstallTitle')),
        content: Text(l10n.tr('caInstallSteps').replaceAll('{file}', name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('permOpenSettings'))),
        ],
      ),
    );
    if (go == true) {
      try {
        await _security.invokeMethod('openSecuritySettings');
      } catch (_) {}
    }
  }

  Widget _cert(CaCertInfo c, {VoidCallback? onDelete, bool install = true}) {
    final l10n = AppLocalizations.of(context);
    final until = c.validTo == null ? '—' : DateFormat('dd.MM.yyyy').format(c.validTo!.toLocal());
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: Space.l, right: Space.s),
      leading: Icon(c.expired ? AppIcons.gpp_bad : AppIcons.verified,
          size: Sizes.iconRow,
          color: c.expired ? AppColors.errorText(context) : AppColors.successText(context)),
      title: Text(c.commonName),
      subtitle: Text(
        '${c.expired ? l10n.tr('caExpired') : l10n.tr('caValidUntil')} $until\n'
        'SHA-256 ${c.fingerprint.substring(0, 23)}…',
        style: TextStyle(color: AppColors.mutedText(context)),
      ),
      isThreeLine: true,
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: c.fingerprint));
        setState(() => _status = l10n.tr('caFingerprintCopied'));
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (install)
            IconButton(
              tooltip: l10n.tr('caSaveForDevice'),
              icon: const Icon(AppIcons.install_mobile),
              onPressed: () => _installOnDevice(c),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: l10n.tr('delete'),
              icon: const Icon(AppIcons.delete),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = _store;
    if (store == null) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.tr('caTitle')),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Text(l10n.tr('caDesc'), style: muted),
        ),
        if (_needRestart || _status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Row(children: [
              Icon(AppIcons.info, size: Sizes.iconInline, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  [if (_status != null) _status!, if (_needRestart) l10n.tr('caRestartNote')].join('\n'),
                  style: muted,
                ),
              ),
            ]),
          ),

        // Встроенные: Минцифры. На других языках интерфейса — только если
        // включено (выключить), 1.7.3: пункт о российских сертификатах пугал
        // пользователей из других стран.
        if (l10n.isRussian || store.bundledEnabled)
        SettingsGroup(children: [
          SwitchListTile(
            secondary: const Icon(AppIcons.account_balance),
            title: Text(l10n.tr('caMincifryAll')),
            subtitle: Text(l10n.tr('caMincifryAllDesc')),
            value: store.bundledEnabled,
            onChanged: (v) async {
              await store.setBundledEnabled(v);
              if (!v) _restartNote();
              if (mounted) setState(() {});
            },
          ),
          ...store.bundled.map((c) => _cert(c)),
        ]),

        // Установленные на устройство (на Android их могут быть сотни —
        // список свёрнут, раскрывается по нажатию).
        if (_android)
          SettingsGroup(children: [
            SwitchListTile(
              secondary: const Icon(AppIcons.phone_android),
              title: Text(l10n.tr('caDevice')),
              subtitle: Text(store.deviceEnabled
                  ? l10n.tr('caDeviceCount').replaceAll('{n}', '${store.device.length}')
                  : l10n.tr('caDeviceDesc')),
              value: store.deviceEnabled,
              onChanged: (v) async {
                await store.setDeviceEnabled(v);
                if (!v) _restartNote();
                if (mounted) setState(() {});
              },
            ),
            if (store.deviceEnabled && store.device.isNotEmpty)
              ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const Icon(AppIcons.list_alt),
                title: Text(l10n.tr('caDeviceCount').replaceAll('{n}', '${store.device.length}')),
                children: [for (final c in store.device) _cert(c, install: false)],
              ),
          ]),

        // Импортированные в приложение
        SettingsGroup(children: [
          ListTile(
            leading: const Icon(AppIcons.file_present),
            title: Text(l10n.tr('caImportedTitle')),
            subtitle: Text(store.imported.isEmpty ? l10n.tr('caImportedEmpty') : l10n.tr('caImportedDesc')),
          ),
          ...store.imported.map((c) => _cert(c, onDelete: () async {
                await store.removeImported(c.fingerprint);
                _restartNote();
                if (mounted) setState(() {});
              })),
          SettingsItem(
            icon: AppIcons.add,
            title: l10n.tr('caImport'),
            trailing: const SizedBox.shrink(),
            onTap: _import,
          ),
        ]),
      ],
    );
  }
}

// lib/features/settings/screens/about_screen.dart
// «О приложении»: название, версия (из package_info), правообладатель и ссылки
// на документы сайта ogneliss.ru/mail: условия, политика, лицензионное
// соглашение, открытые компоненты.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/app_logo.dart';
import '../../../widgets/common/text_scale_cap.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<String> _version() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return p.version.isNotEmpty
          ? 'v${p.version}${p.buildNumber.isNotEmpty ? '+${p.buildNumber}' : ''}'
          : 'v${AppConstants.appVersion}';
    } catch (_) {
      return 'v${AppConstants.appVersion}';
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('about')))),
      body: ListView(
        children: [
          const SizedBox(height: Space.xl),
          const Center(
            child: AppLogo(size: 72),
          ),
          const SizedBox(height: Space.m),
          Center(
            child: Text(AppConstants.appName,
                style: theme.textTheme.headlineSmall),
          ),
          Center(
            child: FutureBuilder<String>(
              future: _version(),
              builder: (_, snap) => Text(
                snap.data ?? 'v${AppConstants.appVersion}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Center(
            child: Text(
              '© 2026 ${AppConstants.copyrightHolder}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Space.xl),
          const Divider(),
          ListTile(
            leading: const Icon(AppIcons.description),
            title: Text(l10n.tr('termsOfUse')),
            trailing: const Icon(AppIcons.open_in_new, size: 18),
            onTap: () => _open(AppConstants.termsUrl),
          ),
          ListTile(
            leading: const Icon(AppIcons.privacy_tip),
            title: Text(l10n.tr('privacyPolicy')),
            trailing: const Icon(AppIcons.open_in_new, size: 18),
            onTap: () => _open(AppConstants.privacyUrl),
          ),
          const Divider(),
          // Все документы — на сайте (ogneliss.ru/mail): одна редакция для
          // приложения, Google Play и сайта, правка без выпуска новой версии.
          ListTile(
            leading: const Icon(AppIcons.workspace_premium),
            title: Text(l10n.tr('appLicense')),
            subtitle: Text(
              l10n.tr('appLicenseDesc').replaceAll('{company}', AppConstants.copyrightHolder),
            ),
            trailing: const Icon(AppIcons.open_in_new, size: 18),
            onTap: () => _open(AppConstants.eulaUrl),
          ),
          ListTile(
            leading: const Icon(AppIcons.article),
            title: Text(l10n.tr('thirdPartyLicenses')),
            subtitle: Text(l10n.tr('thirdPartyLicensesDesc')),
            trailing: const Icon(AppIcons.open_in_new, size: 18),
            onTap: () => _open(AppConstants.licensesUrl),
          ),
          // Тексты лицензий (MIT, Apache, BSD требуют их воспроизводить) —
          // собираются из самих пакетов и открываются без сети.
          ListTile(
            leading: const Icon(AppIcons.gavel),
            title: Text(l10n.tr('licenseTexts')),
            subtitle: Text(l10n.tr('licenseTextsDesc')),
            trailing: const Icon(AppIcons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: 'v${AppConstants.appVersion}',
              applicationLegalese: '© 2026 ${AppConstants.copyrightHolder}',
            ),
          ),
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }
}

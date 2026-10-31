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
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

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

    // Как остальные экраны настроек (1.8.12, замечание 31.10.2026: «экран
    // „О приложении“ отличается от остального UI»): строки — карточками
    // SettingsGroup на фоне экрана, шапка с логотипом — тоже карточкой.
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    const external = Icon(AppIcons.open_in_new, size: 18);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('about')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            SettingsGroup(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xl, horizontal: Space.l),
                child: Column(children: [
                  const AppLogo(size: 72),
                  const SizedBox(height: Space.m),
                  Text(AppConstants.appName, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: Space.xxs),
                  FutureBuilder<String>(
                    future: _version(),
                    builder: (_, snap) => Text(snap.data ?? 'v${AppConstants.appVersion}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: Space.xs),
                  Text('© 2026 ${AppConstants.copyrightHolder}', style: muted),
                ]),
              ),
            ]),
            const SizedBox(height: Space.l),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.description,
                title: l10n.tr('termsOfUse'),
                trailing: external,
                onTap: () => _open(AppConstants.termsUrl),
              ),
              SettingsItem(
                icon: AppIcons.privacy_tip,
                title: l10n.tr('privacyPolicy'),
                trailing: external,
                onTap: () => _open(AppConstants.privacyUrl),
              ),
            ]),
            const SizedBox(height: Space.l),
            // Все документы — на сайте (ogneliss.ru/mail): одна редакция для
            // приложения, Google Play и сайта, правка без выпуска новой версии.
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.workspace_premium,
                title: l10n.tr('appLicense'),
                subtitle: l10n.tr('appLicenseDesc').replaceAll('{company}', AppConstants.copyrightHolder),
                trailing: external,
                onTap: () => _open(AppConstants.licenseUrl),
              ),
              // Открытый код (1.8.6): репозиторий на GitHub.
              SettingsItem(
                icon: AppIcons.code,
                title: l10n.tr('sourceCode'),
                subtitle: l10n.tr('sourceCodeDesc'),
                trailing: external,
                onTap: () => _open(AppConstants.sourceUrl),
              ),
              SettingsItem(
                icon: AppIcons.article,
                title: l10n.tr('thirdPartyLicenses'),
                subtitle: l10n.tr('thirdPartyLicensesDesc'),
                trailing: external,
                onTap: () => _open(AppConstants.licensesUrl),
              ),
              // Тексты лицензий (MIT, Apache, BSD требуют их воспроизводить) —
              // собираются из самих пакетов и открываются без сети.
              SettingsItem(
                icon: AppIcons.gavel,
                title: l10n.tr('licenseTexts'),
                subtitle: l10n.tr('licenseTextsDesc'),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: 'v${AppConstants.appVersion}',
                  applicationLegalese: '© 2026 ${AppConstants.copyrightHolder}',
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// lib/features/auth/screens/license_agreement_screen.dart
// Ознакомление с лицензионным соглашением при первой авторизации. Показывается
// до добавления первого аккаунта (гейт в splash). Требует явного согласия
// (чекбокс + кнопка). Согласие сохраняется в настройках (licenseAccepted).

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/providers/settings_provider.dart';
import '../../../widgets/common/app_logo.dart';

class LicenseAgreementScreen extends ConsumerStatefulWidget {
  const LicenseAgreementScreen({super.key});

  @override
  ConsumerState<LicenseAgreementScreen> createState() => _LicenseAgreementScreenState();
}

class _LicenseAgreementScreenState extends ConsumerState<LicenseAgreementScreen> {
  bool _agreed = false;

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _accept() async {
    await ref.read(settingsProvider.notifier).acceptLicense();
    if (!mounted) return;
    // Дальше — обычный путь первого запуска: онбординг/логин.
    final settings = ref.read(settingsProvider);
    context.go(settings.isFirstLaunch ? '/onboarding' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        // Окно компьютера и планшет: колонка по центру, а не во всю ширину
        // (на 1280 px кнопка и флажок расходились по краям окна).
        child: ReadableWidth(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Space.m),
                const AppLogo(size: 64),
                const SizedBox(height: Space.l),
                Text(
                  l10n.tr('welcomeTo').replaceAll('{app}', AppConstants.appName),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: Space.s),
                Text(
                  l10n.tr('licenseIntro'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Space.l),
                Expanded(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(Space.l),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.tr('inBrief'),
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: Space.s),
                          Text(
                            l10n.tr('licenseBrief'),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: Space.m),
                          Wrap(
                            spacing: 12,
                            children: [
                              TextButton.icon(
                                icon: const Icon(AppIcons.description, size: 18),
                                label: Text(l10n.tr('termsOfUse')),
                                onPressed: () => _open(AppConstants.termsUrl),
                              ),
                              TextButton.icon(
                                icon: const Icon(AppIcons.privacy_tip, size: 18),
                                label: Text(l10n.tr('privacyPolicy')),
                                onPressed: () => _open(AppConstants.privacyUrl),
                              ),
                              TextButton.icon(
                                icon: const Icon(AppIcons.workspace_premium, size: 18),
                                label: Text(l10n.tr('appLicense')),
                                onPressed: () => _open(AppConstants.eulaUrl),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.s),
                CheckboxListTile(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.tr('licenseAcceptCheckbox'),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: Space.s),
                FilledButton(
                  onPressed: _agreed ? _accept : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.m),
                    child: Text(l10n.tr('acceptAndContinue')),
                  ),
                ),
                const SizedBox(height: Space.s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

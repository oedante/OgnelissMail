// lib/features/auth/screens/onboarding_screen.dart
// Onboarding — 3 страницы с полной локализацией:
// 1. О приложении
// 2. Умные функции
// 3. Безопасность

import '../../../core/constants/exchange_feature.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/readable_width.dart';
import '../../settings/providers/settings_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isLast = _currentPage == 2;

    final pages = [
      _OnboardingPage(
        icon: AppIcons.mail,
        iconColor: AppColors.accent(context),
        title: l10n.tr('onboardingTitle1'),
        description: l10n.tr(kExchangeEnabled ? 'onboardingDesc1' : 'onboardingDesc1NoEx'),
      ),
      _OnboardingPage(
        icon: AppIcons.task_alt,
        iconColor: AppColors.accent(context),
        title: l10n.tr('onboardingTitle2'),
        description: l10n.tr('onboardingDesc2'),
      ),
      _OnboardingPage(
        icon: AppIcons.security,
        iconColor: AppColors.successGreen,
        title: l10n.tr('onboardingTitle3'),
        description: l10n.tr(kExchangeEnabled ? 'onboardingDesc3' : 'onboardingDesc3NoEx'),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        // Окно компьютера и планшет: колонка по центру, а не во всю ширину.
        child: ReadableWidth(
          maxWidth: 640,
          child: Column(
            children: [
              // Skip
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text(l10n.tr('skip')),
                ),
              ),

              // Pages
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) => pages[i],
                ),
              ),

              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pages.length, (i) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: Space.xs),
                    width: _currentPage == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i ? theme.colorScheme.primary : theme.colorScheme.outline.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),

              const SizedBox(height: Space.xxl),

              // Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: isLast
                        ? _finish
                        : () {
                            HapticFeedback.selectionClick();
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          },
                    child: Text(isLast ? l10n.tr('getStarted') : l10n.tr('next')),
                  ),
                ),
              ),

              const SizedBox(height: Space.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    ref.read(settingsProvider.notifier).markFirstLaunchDone();
    context.go('/login');
  }
}

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 56, color: iconColor),
          ),
          const SizedBox(height: 40),
          Text(title, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: Space.l),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7), height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// lib/splash_screen.dart
// Финальный splash — с проверкой PIN-блокировки

import 'core/constants/exchange_feature.dart';
import 'data/models/account_model.dart' show AccountType;
import 'package:flutter/material.dart';
import 'core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/logging/app_logger.dart';
import 'services/background/background_service.dart';
import 'services/security/pin_lock_service.dart';
import 'features/settings/providers/settings_provider.dart';
import 'l10n/app_localizations.dart';
import 'data/providers/database_provider.dart';
import 'widgets/common/app_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  /// Ключ строки состояния (переводится в build: в initState контекст
  /// локализации ещё недоступен).
  String _statusKey = '';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    _initAndNavigate();
  }

  Future<void> _initAndNavigate() async {
    try {
      final minDelay = Future.delayed(const Duration(milliseconds: 1800));

      if (mounted) setState(() => _statusKey = 'splashInitializing');

      try {
        final bgService = ref.read(backgroundServiceProvider);
        await bgService.initialize();
      } catch (e) {
        AppLogger.warning('Splash bg init: $e');
      }

      await minDelay;
      if (!mounted) return;

      final settings = ref.read(settingsProvider);
      // Аккаунты грузятся асинхронно — читаем напрямую из БД, чтобы не уйти
      // на /login преждевременно (пока провайдер ещё пуст).
      final db = ref.read(databaseProvider);
      final accountRows = await db.select(db.accounts).get();
      final hasAccounts = accountRows.any((r) => !exchangeHidden(AccountType.values[r.type]));
      if (!mounted) return;

      // Если есть подключённые аккаунты — сразу на почту (онбординг/логин
      // не показываем, даже если флаг isFirstLaunch ещё не успел прогрузиться).
      if (hasAccounts) {
        final pinState = ref.read(pinLockProvider);
        if (pinState.isPinSet) {
          ref.read(pinLockProvider.notifier).lock();
        }
        context.go('/mail');
      } else if (!settings.licenseAccepted) {
        // Перед первой авторизацией — ознакомление с лицензионным соглашением.
        context.go('/license');
      } else if (settings.isFirstLaunch) {
        context.go('/onboarding');
      } else {
        context.go('/login');
      }
    } catch (e) {
      AppLogger.error('Splash error', e);
      if (mounted) {
        setState(() => _statusKey = 'error');
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/login');
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandDark,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 100),
                const SizedBox(height: Space.xl),
                const Text(AppConstants.appName, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 48),
                SizedBox(width: Space.xl, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(height: Space.l),
                Text(_statusKey.isEmpty ? '' : AppLocalizations.of(context).tr(_statusKey), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

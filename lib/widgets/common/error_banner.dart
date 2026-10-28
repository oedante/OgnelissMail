// lib/widgets/common/error_banner.dart
// Banner для отображения сетевых ошибок в UI.
// Показывается вверху экрана с типом ошибки и кнопкой Retry.
// Автоматически исчезает при восстановлении связи.

import 'dart:async';
import '../../core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// Провайдер текущей ошибки
final errorBannerProvider = StateProvider<ErrorBannerData?>((ref) => null);

class ErrorBannerData {
  final String message;
  final ErrorBannerType type;
  final VoidCallback? onRetry;
  final DateTime timestamp;

  ErrorBannerData({
    required this.message,
    this.type = ErrorBannerType.network,
    this.onRetry,
  }) : timestamp = DateTime.now();
}

enum ErrorBannerType { network, auth, server, sync, general }

class ErrorBanner extends ConsumerWidget {
  const ErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(errorBannerProvider);
    final l10n = AppLocalizations.of(context);

    // Офлайн НЕ показываем баннером: работа без сети штатная (очередь отправки),
    // и постоянная полоса во всю ширину только мешала бы. Вместо неё —
    // компактная пиктограмма OfflineIndicator в шапке.

    // Показываем ошибку если есть
    if (error != null) {
      // Автоскрытие через 10 сек
      Future.delayed(const Duration(seconds: 10), () {
        if (ref.read(errorBannerProvider)?.timestamp == error.timestamp) {
          ref.read(errorBannerProvider.notifier).state = null;
        }
      });

      return _buildBanner(
        context,
        icon: _iconForType(error.type),
        message: error.message,
        color: _colorForType(error.type),
        textColor: Colors.white,
        action: error.onRetry != null
            ? TextButton(
                onPressed: () {
                  error.onRetry!();
                  ref.read(errorBannerProvider.notifier).state = null;
                },
                child: Text(l10n.tr('retry'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            : IconButton(
                tooltip: l10n.tr('dismiss'),
                icon: const Icon(AppIcons.close, color: Colors.white, size: 18),
                onPressed: () => ref.read(errorBannerProvider.notifier).state = null,
              ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBanner(
    BuildContext context, {
    required IconData icon,
    required String message,
    required Color color,
    required Color textColor,
    Widget? action,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
      color: color,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 18),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (action != null) action,
          ],
        ),
      ),
    );
  }

  IconData _iconForType(ErrorBannerType type) {
    switch (type) {
      case ErrorBannerType.network: return AppIcons.wifi_off;
      case ErrorBannerType.auth: return AppIcons.lock;
      case ErrorBannerType.server: return AppIcons.dns;
      case ErrorBannerType.sync: return AppIcons.sync_problem;
      case ErrorBannerType.general: return AppIcons.error;
    }
  }

  Color _colorForType(ErrorBannerType type) {
    switch (type) {
      case ErrorBannerType.network: return AppColors.warningYellow;
      case ErrorBannerType.auth: return AppColors.errorRed;
      case ErrorBannerType.server: return AppColors.accentOrange;
      case ErrorBannerType.sync: return AppColors.infoBlue;
      case ErrorBannerType.general: return const Color(0xFF616161);
    }
  }
}

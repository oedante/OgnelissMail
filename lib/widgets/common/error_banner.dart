// lib/widgets/common/error_banner.dart
// Плашка ошибок синхронизации: поверх экрана сверху (с 1.10.2 — не полосой
// в разметке, которая сдвигала содержимое), с типом ошибки и кнопкой
// «Повторить». Уходит сама через 10 с или по крестику.

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

    Widget content = const SizedBox.shrink(key: ValueKey('none'));
    if (error != null) {
      // Автоскрытие через 10 сек
      Future.delayed(const Duration(seconds: 10), () {
        if (ref.read(errorBannerProvider)?.timestamp == error.timestamp) {
          ref.read(errorBannerProvider.notifier).state = null;
        }
      });

      content = _buildBanner(
        context,
        key: ValueKey(error.timestamp),
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

    // Выезжает сверху и уходит так же, ничего не сдвигая.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (w, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero).animate(a),
          child: w,
        ),
      ),
      child: content,
    );
  }

  Widget _buildBanner(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String message,
    required Color color,
    required Color textColor,
    Widget? action,
  }) {
    return SafeArea(
      key: key,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.s, Space.xs, Space.s, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Material(
              color: color,
              elevation: 3,
              shadowColor: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
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
            ),
          ),
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

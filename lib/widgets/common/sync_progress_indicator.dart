// lib/widgets/common/sync_progress_indicator.dart
// Индикатор синхронизации — тонкая полоска сверху.
// Показывает: прогресс, статус, сообщение, ошибки.

import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/theme/app_theme.dart';
import 'inline_notice.dart' show showInlineError;

enum SyncStatus { idle, syncing, success, error }

final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.idle);
final syncProgressProvider = StateProvider<double>((ref) => 0.0);
final syncMessageProvider = StateProvider<String?>((ref) => null);

class SyncProgressIndicator extends ConsumerWidget {
  const SyncProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final progress = ref.watch(syncProgressProvider);
    final message = ref.watch(syncMessageProvider);

    if (status == SyncStatus.idle) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Прогресс-бар
        if (status == SyncStatus.syncing)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 300),
            builder: (_, value, __) => LinearProgressIndicator(
              value: value > 0 ? value : null,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(
                status == SyncStatus.error ? AppColors.errorRed : AppColors.primaryBlue,
              ),
            ),
          ),

        // Текст «Синхронизация: …» больше не выводится строкой — полоска
        // лежит поверх заголовка экрана; сообщение доступно экранному диктору.
        if (message != null && status == SyncStatus.syncing)
          Semantics(liveRegion: true, label: message, child: const SizedBox.shrink()),

        // Успех (исчезает через 2 сек)
        if (status == SyncStatus.success)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: 0.0),
            duration: const Duration(seconds: 2),
            onEnd: () => ref.read(syncStatusProvider.notifier).state = SyncStatus.idle,
            builder: (_, opacity, __) => Opacity(
              opacity: opacity,
              child: Container(
                height: 2,
                color: AppColors.successGreen,
              ),
            ),
          ),

        // Ошибка
        if (status == SyncStatus.error)
          Container(
            height: 2,
            color: AppColors.errorRed,
          ),
      ],
    );
  }
}


/// Незаметный индикатор синхронизации — рядом с названием папки: маленькое
/// вращающееся кольцо, пока идёт синхронизация, и красная точка при ошибке
/// (нажатие показывает текст). Заменил полосу под строкой состояния: она
/// постоянно мелькала над экраном.
class SyncStatusDot extends ConsumerWidget {
  const SyncStatusDot({super.key, this.onTap});

  /// Нажатие на точку ошибки (1.6.45: лента открывает «Проверку почты»).
  /// Без него — текст ошибки строкой вверху экрана. Раньше текст уходил в
  /// плашку внизу, а плашки в приложении скрыты: нажатие не давало ничего.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final message = ref.watch(syncMessageProvider);
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      // Ход синхронизации не показываем: догрузка истории и проверки шли
      // почти постоянно, и значок крутился без остановки (замечание 05.10).
      // Время последней синхронизации — на экране аккаунта. Остаётся только
      // точка ошибки.
      case SyncStatus.syncing:
        return const SizedBox.shrink();
      case SyncStatus.error:
        return InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap ?? (message == null ? null : () => showInlineError(message)),
          child: Padding(
            padding: const EdgeInsets.all(Space.xs),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
            ),
          ),
        );
      case SyncStatus.idle:
      case SyncStatus.success:
        return const SizedBox.shrink();
    }
  }
}

// lib/widgets/common/offline_indicator.dart
//
// Компактная пиктограмма «нет сети» со всплывающим пояснением.
//
// Офлайн-работа в приложении штатная: письма, правки задач и контактов
// складываются в очередь и уходят при восстановлении связи. Поэтому постоянный
// баннер во всю ширину только мешал бы — вместо него маленькая иконка, а
// подробности показываются по нажатию.
//
// Иконка также показывает, сколько операций ждёт отправки: это важнее самого
// факта отсутствия сети — пользователь видит, что его действия не потеряны.
//
// 1.7.2 (замечание 21.10.2026: «на верхней панели дублируется состояние сети
// и отправки»): «Нет сети · почта на 07:59» уже пишет строка под названием
// папки (MailFreshnessLine), поэтому значок облака здесь больше не
// показывается. Остался только значок очереди с числом — когда действия ждут
// отправки (жёлтый без сети); нажатие — список «Ожидают отправки».

import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_service.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../data/providers/database_provider.dart';
import 'queue_sheet.dart';

/// Число операций, ожидающих отправки. Обновляется реактивно.
final pendingQueueCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchQueueCount();
});

class OfflineIndicator extends ConsumerStatefulWidget {
  const OfflineIndicator({super.key});

  @override
  ConsumerState<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends ConsumerState<OfflineIndicator> {
  // Значок появляется не сразу. Каждое действие (прочитано, флажок,
  // удаление) на секунду кладёт операцию в очередь: значок мелькал в
  // заголовке и сдвигал кнопки — экран «дёргался». Теперь — только если
  // очередь не разошлась за несколько секунд.
  static const _queueDelay = Duration(seconds: 4);
  Timer? _timer;
  bool _shown = false;
  bool _wanted = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _want(bool want, Duration delay) {
    if (want == _wanted) return;
    _wanted = want;
    _timer?.cancel();
    if (!want) {
      if (_shown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_wanted) setState(() => _shown = false);
        });
      }
      return;
    }
    _timer = Timer(delay, () {
      if (mounted && _wanted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(connectivityServiceProvider);
    final pending = ref.watch(pendingQueueCountProvider).value ?? 0;
    final l10n = AppLocalizations.of(context);
    final offline = !connectivity.isConnected;

    _want(pending > 0, _queueDelay);
    // Очередь пуста — значка нет (сеть показывает строка под названием папки).
    if (!_shown || pending == 0) return const SizedBox.shrink();

    final color = offline ? AppColors.warningYellow : AppColors.primaryBlue;

    return Tooltip(
      message: l10n.tr('pendingInQueue'),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        // Список с действиями: отправить, удалить, отменить изменения.
        onTap: () => showQueueSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.schedule_send, size: 18, color: color),
              const SizedBox(width: Space.xs),
              Text('$pending', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

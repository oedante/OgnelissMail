// lib/features/mail/widgets/first_load_strip.dart
// Строка вверху ленты, пока идёт первая загрузка писем на телефон (после
// установки, добавления ящика или увеличения периода синхронизации):
// «Загружаю письма на телефон: осталось N. Пока идёт первая загрузка, расход
// трафика и заряда выше обычного». Аудит 11.10.2026: человек должен знать,
// почему телефон в первые часы греется и тратит трафик, и что это пройдёт.
//
// Показывается, когда текстов ждут больше 200 писем; скрывается сама, когда
// осталось меньше 50, или по «✕» (до следующей большой загрузки). Счётчик —
// тот же, что в «Настройки → Почта → На телефоне»; пересчёт — раз в 3 минуты,
// только пока строка видна.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/offline_store_service.dart';
import '../providers/mail_providers.dart';

class FirstLoadStrip extends ConsumerStatefulWidget {
  const FirstLoadStrip({super.key});

  static const _dismissedKey = 'first_load_dismissed';
  static const _showFrom = 200;
  static const _hideBelow = 50;

  @override
  ConsumerState<FirstLoadStrip> createState() => _FirstLoadStripState();
}

class _FirstLoadStripState extends ConsumerState<FirstLoadStrip> {
  int? _waiting;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Не в первый кадр: подсчёт — запрос к базе, лента важнее.
    _timer = Timer(const Duration(seconds: 3), _count);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _count() async {
    try {
      final s = await ref.read(offlineStoreProvider).stats(ref.read(accountsProvider));
      if (!mounted) return;
      final prefs = ref.read(sharedPrefsProvider);
      // Загрузка закончилась — следующая большая (новый ящик) снова покажет строку.
      if (s.waiting < FirstLoadStrip._hideBelow && (prefs.getBool(FirstLoadStrip._dismissedKey) ?? false)) {
        await prefs.setBool(FirstLoadStrip._dismissedKey, false);
      }
      setState(() => _waiting = s.waiting);
      if (_visible) _timer = Timer(const Duration(minutes: 3), _count);
    } catch (_) {}
  }

  bool get _visible {
    final w = _waiting;
    if (w == null || w < FirstLoadStrip._hideBelow) return false;
    if (ref.read(sharedPrefsProvider).getBool(FirstLoadStrip._dismissedKey) ?? false) return false;
    return w >= FirstLoadStrip._showFrom || _shownOnce;
  }

  /// Уже показанная строка остаётся до «меньше 50», а не прячется на 199.
  bool _shownOnce = false;

  Future<void> _dismiss() async {
    await ref.read(sharedPrefsProvider).setBool(FirstLoadStrip._dismissedKey, true);
    _timer?.cancel();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    _shownOnce = true;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.chipAll,
      ),
      child: InkWell(
        borderRadius: Radii.chipAll,
        onTap: () => context.push('/settings/mail'),
        child: Padding(
          padding: const EdgeInsets.only(left: Space.m),
          child: Row(children: [
            Icon(AppIcons.cloud_download, size: Sizes.iconInline, color: theme.colorScheme.primary),
            const SizedBox(width: Space.s),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s),
                child: Text(
                  l10n.tr('firstLoadStrip').replaceAll('{n}', '$_waiting'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: AppColors.mutedText(context)),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.tr('close'),
              icon: const Icon(AppIcons.close, size: Sizes.iconInline),
              onPressed: _dismiss,
            ),
          ]),
        ),
      ),
    );
  }
}

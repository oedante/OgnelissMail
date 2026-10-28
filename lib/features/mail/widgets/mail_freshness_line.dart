// lib/features/mail/widgets/mail_freshness_line.dart
// Строка под названием папки (1.6.47): «Обновлено сейчас», «Обновлено в
// 15:40»; давно не обновлялось — «Не обновлялось с 15:40» заметным цветом;
// нет сети — «Нет сети · почта на 15:40». После неё — адрес ящика (или
// легенда ящиков в Хабе), как раньше. Расчёт — MailFreshness.
//
// Пока идёт проверка, а почта давняя, — «Обновление…»: после возврата в
// приложение строка не пугает «не обновлялось», пока проверка ещё идёт.
// Свежая почта во время проверки — без изменений (строка не мигает на
// каждом плановом тике).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/mail_freshness.dart';
import '../../../services/sync/push_health.dart';
import '../../../widgets/common/sync_progress_indicator.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/mail_providers.dart' show lastSyncAtProvider;

class MailFreshnessLine extends ConsumerStatefulWidget {
  /// Ящики на экране.
  final List<AccountModel> accounts;

  /// Что идёт после « · » (адрес ящика, легенда ящиков).
  final List<InlineSpan> tail;

  /// Обычный (приглушённый) стиль строки.
  final TextStyle? style;

  /// Цвет «давно не обновлялось» и «нет сети».
  final Color warnColor;

  const MailFreshnessLine({
    super.key,
    required this.accounts,
    required this.warnColor,
    this.tail = const [],
    this.style,
  });

  @override
  ConsumerState<MailFreshnessLine> createState() => _MailFreshnessLineState();
}

class _MailFreshnessLineState extends ConsumerState<MailFreshnessLine> with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTick();
  }

  /// «Сейчас» → «в 15:40», «давно», пульс push — без событий, по часам.
  /// Только пока приложение на экране (1.6.48): в фоне таймер будил бы
  /// процесс каждые 30 секунд ради строки, которую никто не видит.
  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTick();
      if (mounted) setState(() {});
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  String _stamp(DateTime t, DateTime now) {
    final local = t.toLocal();
    final today = local.year == now.year && local.month == now.month && local.day == now.day;
    return today ? AppDateFormat.time(context, local) : AppDateFormat.dayMonthTime(context, local);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final boxes = [
      for (final a in widget.accounts) (account: a, last: ref.watch(lastSyncAtProvider(a.id)).value),
    ];
    final online = ref.watch(connectivityServiceProvider).isConnected;
    final syncing = ref.watch(syncStatusProvider) == SyncStatus.syncing;
    final autoSync = ref.watch(settingsProvider.select((s) => s.syncIntervalMinutes >= 0));
    final f = MailFreshness.of(boxes, now: now, pushAlive: pushLastAlive, autoSync: autoSync);
    final at = f.at;

    final String text;
    IconData? icon;
    if (!online) {
      text = at == null ? l10n.tr('offline') : l10n.tr('mailOfflineAsOf').replaceAll('{time}', _stamp(at, now));
      icon = AppIcons.cloud_off;
    } else if ((f.stale || at == null) && syncing) {
      text = l10n.tr('mailUpdating');
    } else if (at == null) {
      text = l10n.tr('mailNeverUpdated');
    } else if (f.stale) {
      text = l10n.tr('mailNotUpdatedSince').replaceAll('{time}', _stamp(at, now));
      icon = AppIcons.sync_problem;
    } else if (now.difference(at) < const Duration(minutes: 2)) {
      text = l10n.tr('mailUpdatedNow');
    } else {
      final local = at.toLocal();
      final today = local.year == now.year && local.month == now.month && local.day == now.day;
      text = today
          ? l10n.tr('mailUpdatedAt').replaceAll('{time}', AppDateFormat.time(context, local))
          : l10n.tr('mailUpdatedOn').replaceAll('{date}', AppDateFormat.dayMonthTime(context, local));
    }

    final base = widget.style ?? Theme.of(context).textTheme.bodySmall;
    final warn = icon != null;
    final statusStyle = warn ? base?.copyWith(color: widget.warnColor, fontWeight: FontWeight.w600) : base;
    return Text.rich(
      TextSpan(style: base, children: [
        if (icon != null)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: Space.xs),
              child: Icon(icon, size: (base?.fontSize ?? 11) + 2, color: widget.warnColor),
            ),
          ),
        TextSpan(text: text, style: statusStyle),
        if (widget.tail.isNotEmpty) ...[
          const TextSpan(text: '  ·  '),
          ...widget.tail,
        ],
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

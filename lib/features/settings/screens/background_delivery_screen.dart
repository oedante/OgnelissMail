// lib/features/settings/screens/background_delivery_screen.dart
// «Расширенные настройки → Проверка почты в фоне» (2.7.0, замечание
// владельца 22.11.2026: «как и что будет будить приложение, пользователю не
// интересно» и уточнение «не убирать без потери функций, а автоматизировать
// выбор того, в чём пользователь не разберётся»). Всё здесь выбирается само:
//  · сигналы сервера (свёрнутое приложение просыпается проверить почту)
//    включены; способ — Google, если есть сервисы Google Play, иначе
//    приложение UnifiedPush (несколько — первое по названию), иначе — по
//    расписанию;
//  · «Работать в фоне» (Android) — служба поднимается сама, когда у ящика
//    «Мгновенно» или «По расписанию».
// Вручную — только если уведомления опаздывают. Раньше это было в
// «Уведомлениях» и «Разрешениях».

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../services/push/push_wake_service.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../providers/settings_provider.dart';

/// Есть что показать на этом устройстве (Android, iPhone).
bool get backgroundDeliveryAvailable =>
    !kIsWeb && (Platform.isAndroid || (Platform.isIOS && PushWakeService.supported));

class BackgroundDeliveryScreen extends ConsumerWidget {
  const BackgroundDeliveryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final android = !kIsWeb && Platform.isAndroid;
    final pushOn = ref.watch(pushWakePrefsProvider).enabled;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('pushWakeTitleAndroid')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            // Что выбирается само — названия переключателей и режимов
            // подставляются из строк приложения (на всех языках одинаково).
            if (android)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xs, Space.s, Space.xs, Space.s),
                child: Text(
                    l10n
                        .tr('bgDeliveryAuto')
                        .replaceAll('{bg}', l10n.tr('runInBackground'))
                        .replaceAll('{instant}', l10n.tr('checkInstant'))
                        .replaceAll('{scheduled}', l10n.tr('checkScheduled')),
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
              ),
            // «Работать в фоне» (Android): служба мгновенной доставки, пока
            // приложение свёрнуто, — только ящикам «Мгновенно» и «По
            // расписанию».
            if (android) ...[
              SettingsSectionTitle(l10n.tr('runInBackground')),
              SettingsGroup(children: [
                SettingsSwitchItem(
                  key: const ValueKey('bg_keep_alive'),
                  icon: AppIcons.cloud_sync,
                  title: l10n.tr('runInBackground'),
                  hint: '${l10n.tr('runInBackgroundShort')}.\n\n${l10n.tr('runInBackgroundDesc')}',
                  value: settings.backgroundKeepAlive,
                  onChanged: (v) async {
                    await ref.read(settingsProvider.notifier).setBackgroundKeepAlive(v);
                    final ctl = ref.read(foregroundSyncControllerProvider);
                    if (keepAliveNeeded(
                        keepAliveSetting: v,
                        globalInterval: ref.read(settingsProvider).syncIntervalMinutes,
                        accounts: ref.read(accountsProvider))) {
                      await ctl.start();
                    } else {
                      await ctl.stop();
                    }
                  },
                ),
              ]),
            ],
            if (PushWakeService.supported) ...[
              if (PushWakeService.platformOs == PushWakeOs.android)
                SettingsSectionTitle(l10n.tr('pushWakeSwitch'), help: l10n.tr('pushWakeHelpAndroid'))
              else
                SettingsSectionTitle(l10n.tr('pushWakeSwitch'), help: l10n.tr('pushWakeHelp')),
              SettingsGroup(children: [
                SettingsSwitchItem(
                  key: const ValueKey('push_wake_switch'),
                  icon: AppIcons.cloud_sync,
                  title: l10n.tr('pushWakeSwitch'),
                  subtitle: pushWakeStatusText(context, ref, l10n),
                  value: pushOn,
                  onChanged: (v) => ref.read(pushWakePrefsProvider.notifier).setEnabled(v),
                ),
                if (pushOn)
                  for (final m in PushWakePrefsNotifier.intervals)
                    AppRadioTile<int>(
                      title: Text(l10n.tr('pushWakeEvery').replaceAll('{n}', '$m')),
                      value: m,
                      groupValue: ref.watch(pushWakePrefsProvider).interval,
                      onChanged: (v) => ref.read(pushWakePrefsProvider.notifier).setInterval(v ?? 15),
                    ),
              ]),
              // Android: через Google или UnifiedPush — «Автоматически» по умолчанию.
              if (PushWakeService.platformOs == PushWakeOs.android && pushOn) ...[
                SettingsSectionTitle(l10n.tr('pushWakeVia'), help: l10n.tr('pushWakeViaHelp')),
                const SettingsGroup(children: [_PushTransportPicker()]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Строка под переключателем сигналов: пояснение и состояние регистрации.
String pushWakeStatusText(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
  final svc = ref.read(pushWakeServiceProvider);
  final st = svc.state();
  final parts = <String>[l10n.tr('pushWakeDesc')];
  if (!ref.read(pushWakePrefsProvider).enabled) return parts.first;
  // Android без сервисов Google и без распространителя (1.12.x): не ошибка
  // и не «ещё не зарегистрировано», а как есть — почта проверяется по
  // расписанию; что поставить для сигналов — в «Как приходят сигналы».
  if (svc.os == PushWakeOs.android &&
      svc.transport == PushWakeTransport.unifiedpush &&
      svc.upDistributor == null &&
      !st.registered) {
    parts.add(l10n.tr('pushWakeStatusPeriodic'));
    return parts.join('\n');
  }
  if (st.lastError != null && !st.registered) {
    parts.add(l10n.tr('pushWakeStatusError').replaceAll('{e}', st.lastError!));
  } else if (st.registered && st.registeredAt != null) {
    parts.add(l10n.tr('pushWakeStatusOk').replaceAll('{when}', AppDateFormat.dayMonthTime(context, st.registeredAt!)));
    if (st.lastWake != null) {
      parts.add(l10n.tr('pushWakeStatusLast').replaceAll('{when}', AppDateFormat.dayMonthTime(context, st.lastWake!)));
    }
  } else {
    parts.add(l10n.tr('pushWakeStatusNone'));
  }
  return parts.join('\n');
}

/// Способ доставки сигналов на Android: Google (FCM) или распространитель
/// UnifiedPush (1.10.x, просьба владельца 01.11.2026).
class _PushTransportPicker extends ConsumerStatefulWidget {
  const _PushTransportPicker();

  @override
  ConsumerState<_PushTransportPicker> createState() => _PushTransportPickerState();
}

class _PushTransportPickerState extends ConsumerState<_PushTransportPicker> {
  late Future<List<UpDistributor>> _list = ref.read(pushWakeServiceProvider).upDistributors();
  bool _busy = false;

  Future<void> _use(PushWakeTransport t, {String? distributor}) async {
    setState(() => _busy = true);
    try {
      await ref.read(pushWakeServiceProvider).useTransport(t, distributor: distributor);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.read(pushWakeServiceProvider);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    return FutureBuilder<List<UpDistributor>>(
      future: _list,
      builder: (context, snap) {
        final list = snap.data ?? const <UpDistributor>[];
        // Выбор приложения (2.7.0) — «Автоматически», пока человек не выбрал сам.
        final current = !s.explicitChoice
            ? 'auto'
            : s.transport == PushWakeTransport.unifiedpush
                ? 'up:${s.upDistributor ?? ''}'
                : 'fcm';
        void pick(String? v) {
          if (v == null || _busy || v == current) return;
          if (v == 'auto') {
            setState(() => _busy = true);
            unawaited(s.useAuto().whenComplete(() {
              if (mounted) setState(() => _busy = false);
            }));
          } else if (v == 'fcm') {
            unawaited(_use(PushWakeTransport.fcm));
          } else {
            unawaited(_use(PushWakeTransport.unifiedpush, distributor: v.substring(3)));
          }
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          AppRadioTile<String>(
            key: const ValueKey('push_via_auto'),
            title: Text(l10n.tr('accountKindAuto')),
            subtitle: Text(l10n.tr('bgDeliveryAutoShort'), style: muted),
            value: 'auto',
            groupValue: current,
            onChanged: pick,
          ),
          // Нет сервисов Google Play на телефоне (1.12.x) — и пункта нет:
          // через Google сигналы не придут.
          if (s.fcmUsable)
            AppRadioTile<String>(
              title: Text(l10n.tr('pushWakeViaGoogle')),
              subtitle: Text(l10n.tr('pushWakeViaGoogleDesc'), style: muted),
              value: 'fcm',
              groupValue: current,
              onChanged: pick,
            ),
          for (final d in list)
            AppRadioTile<String>(
              title: Text(l10n.tr('pushWakeViaUp').replaceAll('{app}', d.name)),
              subtitle: Text(l10n.tr('pushWakeViaUpDesc'), style: muted),
              value: 'up:${d.id}',
              groupValue: current,
              onChanged: pick,
            ),
          if (snap.connectionState == ConnectionState.done && list.isEmpty)
            ListTile(
              leading: const Icon(AppIcons.info),
              title: Text(l10n.tr('pushWakeNoDistributor')),
              subtitle: Text(l10n.tr('pushWakeNoDistributorDesc'), style: muted),
              trailing: IconButton(
                tooltip: l10n.tr('refresh'),
                icon: const Icon(AppIcons.refresh),
                onPressed: () => setState(() => _list = s.upDistributors()),
              ),
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
        ]);
      },
    );
  }
}

// lib/features/mail/widgets/background_hint_strip.dart
// Строка вверху ленты на телефонах, где оболочка производителя останавливает
// свёрнутые приложения (Honor/Huawei, Xiaomi, OPPO/OnePlus/realme, vivo…):
// «Уведомления могут опаздывать · Настроить». По журналам 10.10.2026 на
// Honor приложение «замораживалось» на 10–30 минут даже со службой —
// пользователь не знал, что нужно разрешение в настройках телефона.
//
// Показывается один раз, пока не нажато «Настроить» или «✕»; снова — если
// приложение заметило заморозку (ForegroundSyncController.frozenRecently).
// Состояние телефона читается после первого кадра, а решение «показывать»
// запоминается: на следующих запусках строка есть сразу, без появления
// «из ниоткуда».
//
// iPhone (1.6.40, жалобы тестировщиков 19.10.2026 «уведомления приходят с
// задержкой»): при выключенном «Обновлении контента» iOS не будит приложение
// в фоне вовсе — о письмах оно узнаёт только при открытии. Строка с тем же
// видом: «Уведомления — только при открытии · Включить».

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:permission_handler/permission_handler.dart' show openAppSettings;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/permissions/app_permissions.dart';
import '../../../core/platform/platform_diagnostics.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/background/foreground_sync_controller.dart';

class BackgroundHintStrip extends ConsumerStatefulWidget {
  const BackgroundHintStrip({super.key});

  static const _dismissedKey = 'bg_hint_dismissed';
  static const _wantedKey = 'bg_hint_wanted';

  /// 1.6.44: уведомления выключены (разрешение или категория «Почта»).
  /// Закрытая строка возвращается через 3 дня, пока уведомления выключены:
  /// это главная причина «приложение перестало сообщать о почте».
  static const _notifOffKey = 'notif_hint_off';
  static const _notifDismissedAtKey = 'notif_hint_dismissed_at';

  @override
  ConsumerState<BackgroundHintStrip> createState() => _BackgroundHintStripState();
}

class _BackgroundHintStripState extends ConsumerState<BackgroundHintStrip> with WidgetsBindingObserver {
  late bool _show;

  /// Что именно выключено: null — уведомления в порядке; иначе
  /// notificationsOff или mailChannelOff.
  BgIssue? _notif;

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _ios => !kIsWeb && Platform.isIOS;

  bool _notifDismissedRecently(SharedPreferences p) {
    final at = p.getInt(BackgroundHintStrip._notifDismissedAtKey);
    if (at == null) return false;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < const Duration(days: 3);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final p = ref.read(sharedPrefsProvider);
    // Уведомления выключены — строка сразу (по прошлой проверке), уточняется
    // после первого кадра и при каждом возврате в приложение.
    final off = p.getString(BackgroundHintStrip._notifOffKey);
    if ((_android || _ios) && off != null && !_notifDismissedRecently(p)) {
      _notif = BgIssue.values.where((i) => i.name == off).firstOrNull;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkNotifications());
    final dismissed = p.getBool(BackgroundHintStrip._dismissedKey) ?? false;
    if (_ios) {
      // iPhone: пока «Обновление контента» выключено — строка, пока её не
      // закрыли; проверяется при каждом запуске (включили — исчезает).
      _show = !dismissed && (p.getBool(BackgroundHintStrip._wantedKey) ?? false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
      return;
    }
    final frozen = ForegroundSyncController.frozenRecently(p);
    _show = _android && (frozen || (!dismissed && (p.getBool(BackgroundHintStrip._wantedKey) ?? false)));
    if (_android && !dismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Вернулись из настроек телефона — уведомления могли включить.
    if (state == AppLifecycleState.resumed) unawaited(_checkNotifications());
  }

  /// Разрешены ли уведомления и включена ли категория «Почта».
  Future<void> _checkNotifications() async {
    if (!(_android || _ios)) return;
    final d = await PlatformDiagnostics.collect(light: true);
    if (d.isEmpty || !mounted) return;
    final issues = PlatformDiagnostics.issues(d);
    final off = issues.contains(BgIssue.notificationsOff)
        ? BgIssue.notificationsOff
        : issues.contains(BgIssue.mailChannelOff)
            ? BgIssue.mailChannelOff
            : null;
    final p = ref.read(sharedPrefsProvider);
    if (off == null) {
      await p.remove(BackgroundHintStrip._notifOffKey);
      await p.remove(BackgroundHintStrip._notifDismissedAtKey);
    } else {
      await p.setString(BackgroundHintStrip._notifOffKey, off.name);
    }
    if (!mounted) return;
    final shown = off != null && !_notifDismissedRecently(p) ? off : null;
    if (shown != _notif) setState(() => _notif = shown);
  }

  /// «Включить»: системный запрос (если ещё можно) или настройки телефона.
  Future<void> _fixNotifications() async {
    if (_notif == BgIssue.mailChannelOff) {
      if (!await PlatformDiagnostics.openNotificationSettings()) await openAppSettings();
      return;
    }
    if (!mounted) return;
    final ok = await AppPermissions.ensure(context, AppPermission.notifications);
    if (ok) await _checkNotifications();
  }

  Future<void> _dismissNotifications() async {
    final p = ref.read(sharedPrefsProvider);
    await p.setInt(BackgroundHintStrip._notifDismissedAtKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() => _notif = null);
  }

  /// Есть ли у телефона «оптимизатор» производителя или запрет фона.
  Future<void> _check() async {
    final d = await PlatformDiagnostics.collect(light: true);
    if (!mounted) return;
    final issues = PlatformDiagnostics.issues(d);
    // Оптимизатор производителя и приложение не исключено из экономии
    // батареи — или фоновая работа запрещена совсем.
    final wanted = _ios
        ? issues.contains(BgIssue.iosRefreshOff)
        : issues.contains(BgIssue.backgroundRestricted) ||
            (issues.contains(BgIssue.oemManager) && issues.contains(BgIssue.batteryOptimized));
    final p = ref.read(sharedPrefsProvider);
    await p.setBool(BackgroundHintStrip._wantedKey, wanted);
    final dismissed = p.getBool(BackgroundHintStrip._dismissedKey) ?? false;
    if (!mounted) return;
    // iPhone: «Обновление контента» включили — строка уходит сама.
    if (_ios && !wanted && _show) setState(() => _show = false);
    // Первый запуск: показываем сразу, как узнали; дальше — с первого кадра.
    if (wanted && !_show && !dismissed) setState(() => _show = true);
  }

  Future<void> _dismiss({bool open = false}) async {
    final p = ref.read(sharedPrefsProvider);
    await p.setBool(BackgroundHintStrip._dismissedKey, true);
    // Заморозку тоже считаем увиденной — строка вернётся при новой.
    await ForegroundSyncController.clearFrozen(p);
    if (!mounted) return;
    setState(() => _show = false);
    if (open) unawaited(context.push('/settings/permissions'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notif = _notif;
    // Уведомления выключены — важнее всего: без них о письмах не узнать
    // вовсе, как бы ни работала фоновая проверка.
    if (notif != null) {
      return _strip(
        context,
        text: l10n.tr(notif == BgIssue.mailChannelOff ? 'mailChannelOffStrip' : 'notifOffStrip'),
        action: l10n.tr('bgHintEnable'),
        onAction: _fixNotifications,
        onClose: _dismissNotifications,
      );
    }
    if (!_show) return const SizedBox.shrink();
    return _strip(
      context,
      text: l10n.tr(_ios ? 'bgHintStripIos' : 'bgHintStrip'),
      action: l10n.tr('bgHintSetup'),
      onAction: () => _dismiss(open: true),
      onClose: () => _dismiss(),
    );
  }

  Widget _strip(BuildContext context,
      {required String text,
      required String action,
      required VoidCallback onAction,
      required VoidCallback onClose}) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onAction,
        child: Padding(
          padding: const EdgeInsets.only(left: Space.m),
          child: Row(children: [
            Icon(AppIcons.notifications_off, size: 18, color: AppColors.warningText(context)),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: AppColors.mutedText(context)),
              ),
            ),
            TextButton(onPressed: onAction, child: Text(action)),
            IconButton(
              tooltip: l10n.tr('close'),
              icon: const Icon(AppIcons.close, size: 18),
              onPressed: onClose,
            ),
          ]),
        ),
      ),
    );
  }
}

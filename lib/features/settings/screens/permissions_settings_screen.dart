// lib/features/settings/screens/permissions_settings_screen.dart
// «Настройки → Разрешения»: что приложение может просить у системы, зачем,
// текущее состояние и кнопка «Разрешить» / «Открыть настройки».
// Состояние перечитывается при возврате из системных настроек.
//
// Режим [setup] — один раз после входа в первый ящик: тот же список с
// пояснениями, кнопка «Разрешить всё» и «Продолжить». Администратор
// устройства показывается, только если его требует политика ящика Exchange
// (тайм-аут блокировки экрана).

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../core/permissions/app_permissions.dart';
import '../../../core/platform/platform_diagnostics.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/background/foreground_sync_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/device_security_service.dart';
import '../../../services/security/eas_policy_store.dart';
import '../../../services/security/policy_compliance.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;
import '../providers/settings_provider.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class PermissionsSettingsScreen extends ConsumerStatefulWidget {
  final bool setup;
  const PermissionsSettingsScreen({super.key, this.setup = false});

  @override
  ConsumerState<PermissionsSettingsScreen> createState() => _PermissionsSettingsScreenState();
}

class _PermissionsSettingsScreenState extends ConsumerState<PermissionsSettingsScreen>
    with WidgetsBindingObserver {
  // 1.6.9 (замечание 14.10.2026: экран притормаживал при открытии):
  // прошлое состояние запоминается на время работы приложения — повторное
  // открытие показывает список сразу и уточняет его; разрешения читаются
  // параллельно, сведения о прошивке — отдельно, список их не ждёт.
  static Map<AppPermission, AppPermissionState>? _lastStates;
  static DeviceSecurityStatus? _lastDevice;
  static Map<String, dynamic> _lastDiag = const {};

  Map<AppPermission, AppPermissionState> _states = _lastStates ?? {};
  DeviceSecurityStatus? _device = _lastDevice;
  Map<String, dynamic> _diag = _lastDiag;
  bool _busy = false;
  // Пока состояние не прочитано, список не строится: иначе на миг
  // появлялись кнопка «Разрешить всё» и неприменимые разрешения, а затем
  // пропадали — экран дёргался.
  bool _loaded = _lastStates != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// «Разрешить всё» дошло до особого доступа (точные будильники, работа без
  /// ограничений): он открывает системные экраны по одному — после возврата
  /// открываем следующий (1.6.12; раньше открывался только первый).
  bool _chainSpecial = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) return;
    _reload().then((_) => _nextSpecial());
  }

  Future<void> _nextSpecial() async {
    if (!_chainSpecial || !mounted) return;
    final next = AppPermissions.all
        .where((i) => i.special && _states[i.id] == AppPermissionState.denied)
        .firstOrNull;
    if (next == null) {
      _chainSpecial = false;
      return;
    }
    // Тот же экран повторно не открываем, если человек вернулся, не разрешив.
    if (_specialAsked.contains(next.id)) {
      final rest = AppPermissions.all
          .where((i) => i.special && _states[i.id] == AppPermissionState.denied && !_specialAsked.contains(i.id))
          .firstOrNull;
      if (rest == null) {
        _chainSpecial = false;
        return;
      }
      _specialAsked.add(rest.id);
      await AppPermissions.ensure(context, rest.id, explain: false);
      return;
    }
    _specialAsked.add(next.id);
    await AppPermissions.ensure(context, next.id, explain: false);
  }

  final Set<AppPermission> _specialAsked = {};

  Future<void> _reload() async {
    if (!mounted) return;
    // Сведения о прошивке и ограничениях фона — без ожидания: им нужен
    // разбор системных свойств, а список разрешений готов раньше.
    unawaited(PlatformDiagnostics.collect(light: true).then((diag) {
      _lastDiag = diag;
      if (mounted) setState(() => _diag = diag);
    }));
    final ids = [for (final i in AppPermissions.all) i.id];
    final results = await Future.wait([for (final id in ids) AppPermissions.state(id)]);
    final m = <AppPermission, AppPermissionState>{
      for (var k = 0; k < ids.length; k++) ids[k]: results[k],
    };
    DeviceSecurityStatus? d;
    try {
      d = await ref.read(deviceSecurityServiceProvider).status();
    } catch (_) {}
    _lastStates = m;
    _lastDevice = d;
    if (mounted) {
      setState(() {
        _states = m;
        _device = d;
        _loaded = true;
      });
    }
  }

  Future<void> _act(AppPermissionInfo i) async {
    final st = _states[i.id];
    if (st == AppPermissionState.granted) {
      // Отозвать разрешение приложение не может — только в настройках ОС.
      await openAppSettings();
    } else {
      // Пояснение уже на карточке — сразу системный диалог.
      await AppPermissions.ensure(context, i.id, explain: false);
    }
    await _reload();
  }

  Future<void> _allowAll() async {
    setState(() => _busy = true);
    try {
      await AppPermissions.requestAllDialogs(context);
      await _reload();
      // Особый доступ — системный экран; после возврата список обновится.
      if (!mounted) return;
      _chainSpecial = true;
      _specialAsked.clear();
      await _nextSpecial();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Политика ящика Exchange требует тайм-аут блокировки, а администратор
  /// устройства не включён.
  int? _adminIdleSeconds() {
    final d = _device;
    if (d == null) return null;
    final p = ref.watch(easPolicyProvider);
    final c = evaluatePolicy(p, d);
    return c.adminWanted ? p.maxInactivitySeconds : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final visible = AppPermissions.all
        .where((i) => _states[i.id] != AppPermissionState.notApplicable)
        .toList();
    final adminIdle = _adminIdleSeconds();
    final anyMissing = visible.any((i) => _states[i.id] != AppPermissionState.granted);
    return PopScope(
      canPop: true,
      child: Scaffold(
        // Как работают разрешения — за «?» в шапке (было абзацем над списком).
        appBar: TextScaleCapBar(child: AppBar(
          title: Text(l10n.tr(widget.setup ? 'permSetupTitle' : 'permissions')),
          automaticallyImplyLeading: !widget.setup,
          actions: [
            HelpButton(
                text: l10n.tr(widget.setup ? 'permSetupIntro' : 'permIntro'),
                title: l10n.tr(widget.setup ? 'permSetupTitle' : 'permissions')),
          ],
        )),
        body: !AppPermissions.supported
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(l10n.tr('permNotNeededHere'),
                      textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
                ),
              )
            : !_loaded
                // Пока состояние не прочитано, список не строится (экран не дёргается).
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xxl),
                    children: [
                      // ── Работа в фоне (перенесено с главного экрана настроек) ──
                      // 1.6.12: и при первой настройке — приложение должно
                      // работать сразу, а не после поиска по настройкам.
                      ..._backgroundGroup(context, l10n),

                      // ── Разрешения: переключатель = выдано ли ──
                      SettingsSectionTitle(l10n.tr('permissions')),
                      SettingsGroup(children: [
                        for (final i in visible) _tile(context, l10n, i),
                        if (adminIdle != null) _adminTile(context, l10n, adminIdle),
                        SettingsItem(
                          icon: AppIcons.open_in_new,
                          title: l10n.tr('permOpenSettings'),
                          onTap: () => openAppSettings(),
                        ),
                      ]),
                      if (anyMissing) ...[
                        const SizedBox(height: Space.m),
                        FilledButton.icon(
                          onPressed: _busy ? null : _allowAll,
                          icon: const Icon(AppIcons.done_all),
                          label: Text(l10n.tr('permAllowAll')),
                        ),
                      ],

                      // ── Что мешает работе в фоне (если найдено) ──
                      ..._backgroundTiles(context, l10n),

                      if (widget.setup) ...[
                        const SizedBox(height: Space.s),
                        // Дальше — календарь, контакты и папки ящика (1.6.12).
                        TextButton(
                          onPressed: () => context.pushReplacement('/setup/mailbox'),
                          child: Text(l10n.tr(anyMissing ? 'permLater' : 'permContinue')),
                        ),
                      ],
                    ],
                  ),
      ),
    );
  }

  /// «Работать в фоне» и «Скрыть уведомление о работе в фоне» (Android),
  /// «Обновление в фоне» (iOS) — раньше были на главном экране настроек.
  List<Widget> _backgroundGroup(BuildContext context, AppLocalizations l10n) {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return const [];
    final settings = ref.watch(settingsProvider);
    return [
      SettingsSectionTitle(l10n.tr('runInBackground')),
      SettingsGroup(children: [
        if (Platform.isAndroid)
          SettingsSwitchItem(
            icon: AppIcons.cloud_sync,
            title: l10n.tr('runInBackground'),
            hint: '${l10n.tr('runInBackgroundShort')}.\n\n${l10n.tr('runInBackgroundDesc')}',
            value: settings.backgroundKeepAlive,
            onChanged: (v) async {
              await ref.read(settingsProvider.notifier).setBackgroundKeepAlive(v);
              final ctl = ref.read(foregroundSyncControllerProvider);
              // Включили — сразу, а не при следующем сворачивании.
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
        // Строка в шторке: без сервиса push в свёрнутом приложении не
        // работает, но само уведомление можно выключить в настройках канала.
        if (Platform.isAndroid && settings.backgroundKeepAlive)
          SettingsItem(
            icon: AppIcons.notifications_off,
            title: l10n.tr('bgNotifHide'),
            hint: '${l10n.tr('bgNotifHideShort')}.\n\n${l10n.tr('bgNotifHideDesc')}',
            trailing: const Icon(AppIcons.open_in_new, size: Sizes.iconInline),
            onTap: () => ref.read(foregroundSyncControllerProvider).openNotificationSettings(),
          ),
        // iOS: почту в фоне проверяет BGTaskScheduler, когда сочтёт нужным.
        if (Platform.isIOS)
          SettingsItem(
            icon: AppIcons.cloud_sync,
            title: l10n.tr('iosBackgroundTitle'),
            hint: '${l10n.tr('iosBackgroundShort')}.\n\n${l10n.tr('iosBackgroundDesc')}',
            trailing: const Icon(AppIcons.open_in_new, size: Sizes.iconInline),
            onTap: () => openAppSettings(),
          ),
      ]),
    ];
  }

  /// Ограничения фоновой работы, которых нет среди разрешений выше:
  /// «Батарея → Ограничено», редкая корзина ожидания, экономия трафика и
  /// энергии, оптимизатор производителя (MIUI, EMUI, ColorOS, One UI…),
  /// «Обновление контента» и энергосбережение iOS. Строки с «?» —
  /// пояснение и что сделать; нажатие открывает нужные настройки.
  List<Widget> _backgroundTiles(BuildContext context, AppLocalizations l10n) {
    final issues = PlatformDiagnostics.issues(_diag).where((i) => const {
          BgIssue.mailChannelOff,
          BgIssue.backgroundRestricted, BgIssue.standbyRare, BgIssue.dataSaver,
          BgIssue.powerSave, BgIssue.oemManager, BgIssue.iosRefreshOff, BgIssue.iosLowPower,
        }.contains(i)).toList();
    // Замечено по журналу пульса: процесс стоял минутами (см.
    // ForegroundSyncController._checkFrozen).
    final prefs = ref.read(sharedPrefsProvider);
    final frozen = ForegroundSyncController.frozenRecently(prefs);
    if (issues.isEmpty && !frozen) return const [];
    final family = PlatformDiagnostics.family(_diag);
    final oemKey = switch (family) {
      'xiaomi' => 'bgOemXiaomi',
      'huawei' || 'honor' => 'bgOemHuawei',
      'oppo' || 'oneplus' || 'realme' => 'bgOemOppo',
      'vivo' => 'bgOemVivo',
      'samsung' => 'bgOemSamsung',
      'zte' || 'nubia' => 'bgOemZte',
      _ => 'bgOemOther',
    };
    Future<void> details() async {
      await PlatformDiagnostics.openAppDetails();
    }

    Future<void> oem() async {
      final opened = await PlatformDiagnostics.openOemSettings();
      if (opened.isEmpty) await openAppSettings();
    }

    Widget row(IconData icon, String title, String body, {VoidCallback? onTap, bool warn = false}) => SettingsItem(
          icon: icon,
          title: title,
          hint: body,
          color: warn ? AppColors.errorText(context) : null,
          trailing: onTap == null ? null : const Icon(AppIcons.open_in_new, size: Sizes.iconInline),
          onTap: onTap,
        );

    return [
      SettingsSectionTitle(l10n.tr('bgSectionTitle')),
      SettingsGroup(children: [
        if (frozen)
          row(
            AppIcons.sync_disabled,
            l10n.tr('bgFrozenTitle'),
            '${l10n.tr('bgFrozenBody').replaceAll('{min}', '${prefs.getInt(ForegroundSyncController.frozenMinutesKey) ?? 10}')}\n\n${l10n.tr(oemKey)}',
            warn: true,
            onTap: oem,
          ),
        for (final i in issues)
          (switch (i) {
            BgIssue.mailChannelOff => row(AppIcons.notifications_off, l10n.tr('mailChannelOffTitle'),
                l10n.tr('mailChannelOffBody'), onTap: () async {
              if (!await PlatformDiagnostics.openNotificationSettings()) await details();
            }, warn: true),
            BgIssue.backgroundRestricted =>
              row(AppIcons.block, l10n.tr('bgRestrictedTitle'), l10n.tr('bgRestrictedBody'), onTap: details, warn: true),
            BgIssue.standbyRare => row(AppIcons.bedtime, l10n.tr('bgRareTitle'), l10n.tr('bgRareBody'), onTap: details),
            BgIssue.dataSaver =>
              row(AppIcons.data_saver_on, l10n.tr('bgDataSaverTitle'), l10n.tr('bgDataSaverBody'), onTap: details, warn: true),
            BgIssue.powerSave => row(AppIcons.battery_saver, l10n.tr('bgPowerSaveTitle'), l10n.tr('bgPowerSaveBody')),
            BgIssue.oemManager => row(AppIcons.phonelink_setup,
                l10n.tr('bgOemTitle').replaceAll('{maker}', '${_diag['manufacturer'] ?? ''}'), l10n.tr(oemKey),
                onTap: oem),
            BgIssue.iosRefreshOff => row(AppIcons.sync_disabled, l10n.tr('bgIosRefreshTitle'), l10n.tr('bgIosRefreshBody'),
                onTap: () => openAppSettings(), warn: true),
            BgIssue.iosLowPower => row(AppIcons.battery_saver, l10n.tr('bgPowerSaveTitle'), l10n.tr('bgIosLowPowerBody')),
            _ => const SizedBox.shrink(),
          }),
      ]),
    ];
  }

  /// Администратор устройства — нужен политике ящика Exchange (тайм-аут
  /// блокировки экрана). Переключатель выключен, включение — системный запрос.
  Widget _adminTile(BuildContext context, AppLocalizations l10n, int idleSeconds) {
    final min = '${(idleSeconds / 60).ceil()}';
    return SettingsSwitchItem(
      icon: AppIcons.admin_panel_settings,
      title: l10n.tr('permDeviceAdmin'),
      hint: l10n.tr('deviceAdminBody').replaceAll('{min}', min),
      value: false,
      onChanged: (_) async {
        await ref
            .read(deviceSecurityServiceProvider)
            .requestAdmin(l10n.tr('deviceAdminExplanation').replaceAll('{min}', min));
        await _reload();
      },
    );
  }

  /// Разрешение — переключатель: включён = выдано. Включить — системный
  /// запрос (или настройки телефона, если запрос запрещён); выключить
  /// приложение не может само — открываются настройки телефона. Зачем
  /// разрешение — за «?»; под названием — только «Запрещено в настройках».
  Widget _tile(BuildContext context, AppLocalizations l10n, AppPermissionInfo i) {
    final st = _states[i.id];
    return SettingsSwitchItem(
      icon: i.icon,
      title: l10n.tr(i.titleKey),
      subtitle: st == AppPermissionState.blocked ? l10n.tr('permBlockedShort') : null,
      hint: l10n.tr(i.purposeKey),
      value: st == AppPermissionState.granted,
      onChanged: (_) => _act(i),
    );
  }
}

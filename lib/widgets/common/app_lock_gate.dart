// lib/widgets/common/app_lock_gate.dart
// Экран PIN поверх всего приложения.
//
// Раньше блокировка рисовалась внутри MainShell, и всё, что открыто поверх
// оболочки (письмо на весь экран, окно ответа, вложение, настройки), оставалось
// видно и доступно при заблокированном приложении. Теперь ворота стоят в
// MaterialApp.builder — над навигатором. Содержимое под ними не удаляется
// (состояние экранов и черновик сохраняются), но не рисуется, не получает
// фокус и не читается экранным диктором.
//
// Здесь же исполняется политика Exchange:
// - Android: требование пароля выполняет блокировка экрана телефона нужной
//   сложности (policy_compliance.dart); пока её нет, почта не открывается.
//   Тайм-аут бездействия — через администратора устройства (только
//   force-lock), если пользователь его включил; если отказался — через
//   обязательный PIN приложения и его блокировку по бездействию.
// - Windows и другие платформы: обязательный PIN приложения, как раньше.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../services/security/device_security_service.dart';
import '../../services/security/eas_policy_store.dart';
import '../../services/security/pin_lock_service.dart';
import '../../services/security/policy_compliance.dart';
import 'pin_lock_screen.dart';

/// Ключ: пользователь отказался от администратора устройства для тайм-аута
/// с этим значением (секунды). Политика изменилась — спросим снова.
const _kAdminDeclinedIdle = 'device_admin_declined_idle';

class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  DeviceSecurityStatus? _device;
  bool _checking = false;
  bool _again = false; // запрос проверки пришёл, пока шла предыдущая

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<StoredEasPolicy>(easPolicyProvider, (_, p) {
      ref.read(pinLockProvider.notifier).setIdleTimeout(
          p.maxInactivitySeconds > 0 ? Duration(seconds: p.maxInactivitySeconds) : null);
      _refreshDevice();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Возврат из системных настроек блокировки или экрана администратора.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshDevice();
  }

  Future<void> _refreshDevice() async {
    if (_checking) {
      _again = true;
      return;
    }
    _checking = true;
    try {
      do {
        _again = false;
        final svc = ref.read(deviceSecurityServiceProvider);
        final s = await svc.status();
        if (!mounted) return;
        setState(() => _device = s);
        // Тайм-аут экрана из политики — если администратор устройства включён;
        // политика без тайм-аута — снимаем ограничение.
        final idle = ref.read(easPolicyProvider).maxInactivitySeconds;
        if (s.adminActive && s.maxTimeToLockMs != idle * 1000) {
          await svc.setMaxTimeToLock(Duration(seconds: idle));
        }
      } while (_again && mounted);
    } finally {
      _checking = false;
    }
  }

  bool _adminDeclined(StoredEasPolicy p) =>
      ref.read(sharedPrefsProvider).getInt(_kAdminDeclinedIdle) == p.maxInactivitySeconds;

  Future<void> _declineAdmin(StoredEasPolicy p) async {
    await ref.read(sharedPrefsProvider).setInt(_kAdminDeclinedIdle, p.maxInactivitySeconds);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pin = ref.watch(pinLockProvider);
    final policy = ref.watch(easPolicyProvider);
    final device = _device;
    // Пока не известно состояние устройства, политику не оцениваем, но и
    // почту не показываем, если политика что-то требует.
    final deviceUnknown = device == null && policy.hasDeviceRequirements;
    final compliance = device == null ? null : evaluatePolicy(policy, device);
    // Переменная-флаг не продвигает тип в Dart, поэтому ниже `compliance!`
    // стоит только там, где deviceMode уже гарантирует не-null.
    final deviceMode = compliance?.applies ?? false;

    final needDevice = deviceMode && compliance!.blocking;
    final askAdmin =
        deviceMode && !needDevice && compliance!.adminWanted && !_adminDeclined(policy);
    // PIN приложения обязателен: вне Android — по требованию пароля; на
    // Android — если отказались от администратора, а тайм-аут задан.
    final needSetup = pin.loaded &&
        !pin.isPinSet &&
        (deviceMode
            ? compliance!.adminWanted && _adminDeclined(policy)
            : (device != null && policy.pinRequired));
    final pinLocked = pin.isPinSet && pin.isLocked;
    final hide = !pin.loaded || deviceUnknown || pinLocked || needSetup || needDevice || askAdmin;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(pinLockProvider.notifier).recordActivity(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: hide,
            child: ExcludeFocus(
              excluding: hide,
              child: TickerMode(enabled: !hide, child: widget.child),
            ),
          ),
          if (!pin.loaded || deviceUnknown)
            const ColoredBox(color: AppColors.brandDark)
          else if (pinLocked)
            const PinLockScreen()
          else if (needDevice)
            _DeviceLockRequired(
              policy: policy,
              compliance: compliance,
              onRecheck: _refreshDevice,
            )
          else if (askAdmin)
            _DeviceAdminPrompt(
              idleSeconds: policy.maxInactivitySeconds,
              onDecline: () => _declineAdmin(policy),
            )
          else if (needSetup)
            _PolicyPinSetup(minLength: policy.minPinLength),
        ],
      ),
    );
  }
}

/// Общий каркас полноэкранных экранов политики.
class _PolicyScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  const _PolicyScaffold({required this.icon, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.brandDark,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(icon, color: Colors.white, size: 48),
                    const SizedBox(height: Space.l),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: Space.m),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Политика требует блокировку экрана (и/или шифрование), а её нет.
/// Экран стоит над навигатором, поэтому подтверждение удаления — прямо на нём,
/// а не диалогом (showDialog здесь не найдёт Navigator).
class _DeviceLockRequired extends ConsumerStatefulWidget {
  final StoredEasPolicy policy;
  final PolicyCompliance compliance;
  final Future<void> Function() onRecheck;
  const _DeviceLockRequired({
    required this.policy,
    required this.compliance,
    required this.onRecheck,
  });

  @override
  ConsumerState<_DeviceLockRequired> createState() => _DeviceLockRequiredState();
}

class _DeviceLockRequiredState extends ConsumerState<_DeviceLockRequired> {
  List<String>? _toRemove; // не null — показано подтверждение удаления

  void _askRemove() {
    final ids = ref.read(accountsProvider).map((a) => a.id);
    final affected = EasPolicyStore(ref.read(sharedPrefsProvider)).accountsWithRequirements(ids);
    if (affected.isNotEmpty) setState(() => _toRemove = affected);
  }

  Future<void> _remove(List<String> ids) async {
    final notifier = ref.read(accountsProvider.notifier);
    for (final id in ids) {
      await notifier.removeAccount(id);
    }
    if (mounted) setState(() => _toRemove = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compliance = widget.compliance;
    final level = l10n.tr(switch (compliance.required) {
      LockComplexity.high => 'deviceLockLevelHigh',
      LockComplexity.medium => 'deviceLockLevelMedium',
      _ => 'deviceLockLevelLow',
    });
    const body = TextStyle(color: Colors.white70);
    final toRemove = _toRemove;
    if (toRemove != null) {
      return _PolicyScaffold(
        icon: AppIcons.delete,
        title: l10n.tr('deviceRemoveAccounts'),
        children: [
          Text(l10n.tr('deviceRemoveConfirm').replaceAll('{n}', '${toRemove.length}'),
              textAlign: TextAlign.center, style: body),
          const SizedBox(height: Space.xl),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => _remove(toRemove),
            child: Text(l10n.tr('delete')),
          ),
          const SizedBox(height: Space.s),
          TextButton(
            onPressed: () => setState(() => _toRemove = null),
            child: Text(l10n.tr('cancel'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      );
    }
    return _PolicyScaffold(
      icon: AppIcons.screen_lock_portrait,
      title: l10n.tr('deviceLockTitle'),
      children: [
        if (!compliance.screenLockOk) ...[
          Text(l10n.tr('deviceLockBody').replaceAll('{level}', level),
              textAlign: TextAlign.center, style: body),
          if (PolicyCompliance.lengthRoundedUp(widget.policy)) ...[
            const SizedBox(height: Space.s),
            Text(l10n.tr('deviceLockRounded').replaceAll('{n}', '${widget.policy.minPasswordLength}'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          ],
        ],
        if (!compliance.encryptionOk) ...[
          const SizedBox(height: Space.s),
          Text(l10n.tr('deviceEncryptionBody'), textAlign: TextAlign.center, style: body),
        ],
        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: () {
            final svc = ref.read(deviceSecurityServiceProvider);
            // Блокировка в порядке, не хватает шифрования — в настройки безопасности.
            compliance.screenLockOk
                ? svc.openSecuritySettings()
                : svc.requestScreenLock(compliance.required);
          },
          child: Text(l10n.tr(compliance.screenLockOk ? 'deviceSecuritySettings' : 'deviceLockOpen')),
        ),
        const SizedBox(height: Space.s),
        TextButton(
          onPressed: widget.onRecheck,
          child: Text(l10n.tr('deviceLockRecheck'), style: const TextStyle(color: Colors.white)),
        ),
        // Выход для того, кто не может или не хочет менять телефон: удалить
        // ящики, чья политика этого требует (остальная почта останется).
        TextButton(
          onPressed: _askRemove,
          child: Text(l10n.tr('deviceRemoveAccounts'), style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}

/// Предложение включить администратора устройства ради тайм-аута экрана.
class _DeviceAdminPrompt extends ConsumerWidget {
  final int idleSeconds;
  final VoidCallback onDecline;
  const _DeviceAdminPrompt({required this.idleSeconds, required this.onDecline});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final min = '${(idleSeconds / 60).ceil()}';
    return _PolicyScaffold(
      icon: AppIcons.admin_panel_settings,
      title: l10n.tr('deviceAdminTitle'),
      children: [
        Text(l10n.tr('deviceAdminBody').replaceAll('{min}', min),
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: Space.xl),
        FilledButton(
          onPressed: () => ref
              .read(deviceSecurityServiceProvider)
              .requestAdmin(l10n.tr('deviceAdminExplanation').replaceAll('{min}', min)),
          child: Text(l10n.tr('deviceAdminEnable')),
        ),
        const SizedBox(height: Space.s),
        TextButton(
          onPressed: onDecline,
          child: Text(l10n.tr('deviceAdminUsePin'), style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Обязательная установка PIN по требованию политики Exchange.
/// Стоит над навигатором, поэтому несёт собственный Overlay (он нужен полю
/// ввода для курсора и меню выделения).
class _PolicyPinSetup extends ConsumerStatefulWidget {
  final int minLength;
  const _PolicyPinSetup({required this.minLength});

  @override
  ConsumerState<_PolicyPinSetup> createState() => _PolicyPinSetupState();
}

class _PolicyPinSetupState extends ConsumerState<_PolicyPinSetup> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  // Overlay читает initialEntries один раз: запись создаётся однажды и
  // перерисовывается через markNeedsBuild — иначе текст ошибки не появлялся.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildContent);

  void _setError(String? e) {
    setState(() => _error = e);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save(AppLocalizations l10n) async {
    final a = _pin.text, b = _confirm.text;
    if (a.length < widget.minLength) {
      _setError(l10n.tr('pinTooShort').replaceAll('{n}', '${widget.minLength}'));
      return;
    }
    if (a != b) {
      _setError(l10n.tr('pinMismatch'));
      return;
    }
    final ok = await ref.read(pinLockProvider.notifier).setPin(a);
    if (!ok && mounted) _setError(l10n.tr('pinHint'));
  }

  Widget _field(TextEditingController c, String label) => TextField(
        controller: c,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 6,
        style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 8),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          counterStyle: const TextStyle(color: Colors.white54),
        ),
      );

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
          backgroundColor: AppColors.brandDark,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(AppIcons.admin_panel_settings, color: Colors.white, size: 48),
                      const SizedBox(height: Space.l),
                      Text(l10n.tr('policyPinTitle'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: Space.s),
                      Text(
                        l10n.tr('policyPinBody').replaceAll('{n}', '${widget.minLength}'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: Space.xl),
                      _field(_pin, l10n.tr('setPin')),
                      _field(_confirm, l10n.tr('pinConfirm')),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.s),
                          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      const SizedBox(height: Space.l),
                      FilledButton(onPressed: () => _save(l10n), child: Text(l10n.save)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
  }
}

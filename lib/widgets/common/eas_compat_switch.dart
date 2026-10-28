// lib/widgets/common/eas_compat_switch.dart
// Переключатель «Совместимость со шлюзом (Android-клиент)» для Exchange.
// Используется на экране входа (дополнительно) и в настройках аккаунтов.

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';

import '../../core/device/device_user_agent.dart';
import '../../l10n/app_localizations.dart';
import '../ui/help_hint.dart' show TitleWithHelp;

class EasCompatSwitch extends StatefulWidget {
  /// Вызывается после смены режима (например, переподключить ящики).
  final VoidCallback? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  /// Ящик, для которого переключатель (экран аккаунта, повторный вход).
  /// null — значение по умолчанию для новых ящиков (экран входа).
  final String? accountId;

  const EasCompatSwitch({super.key, this.onChanged, this.contentPadding, this.accountId});

  @override
  State<EasCompatSwitch> createState() => _EasCompatSwitchState();
}

class _EasCompatSwitchState extends State<EasCompatSwitch> {
  static bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  late bool _on = widget.accountId == null
      ? DeviceUserAgent.compatMode
      : DeviceUserAgent.compatFor(widget.accountId!);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SwitchListTile(
      contentPadding: widget.contentPadding,
      secondary: const Icon(AppIcons.shield),
      // Пояснение — под «?» (10.10.2026): длинный абзац под переключателем
      // на экране входа отодвигал поля вниз.
      // На iPhone — «как Почта iPhone» (1.6.12), на Android — как прежде.
      title: TitleWithHelp(l10n.tr(_ios ? 'easCompatUaIos' : 'easCompatUa'),
          hint: l10n.tr(_ios ? 'easCompatUaIosHint' : 'easCompatUaHint')),
      value: _on,
      onChanged: (v) async {
        setState(() => _on = v);
        final id = widget.accountId;
        if (id == null) {
          await DeviceUserAgent.setCompatMode(v);
        } else {
          await DeviceUserAgent.setCompatFor(id, v);
        }
        widget.onChanged?.call();
      },
    );
  }
}

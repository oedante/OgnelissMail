// lib/features/settings/widgets/graphics_item.dart
// «Настройки → Расширенные → Графика» (Android, 08.11.2026): движок
// рисования — «Автоматически» (Impeller, после его сбоя — Skia),
// «Совместимость (Skia)» или «Новый движок (Impeller)». Причина — чёрный
// экран на HUAWEI DEL-LX9 (диагностика владельца 08.11.2026), подробности —
// android/…/GraphicsMode.kt и docs/guides/GRAPHICS.md.
//
// Выбор применяется только с новым процессом: кнопка «Перезапустить»
// (обычное «закрыть и открыть» процесс не завершает — его держит служба
// почты).
//
// Mac (14.11.2026): тот же выбор, свои пояснения — «Автоматически» значит
// Skia на Mac с Intel (там Impeller рассыпал буквы в шум) и Impeller на
// Apple Silicon.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/platform/graphics_mode.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/app_date_format.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import '../../../widgets/ui/settings_group.dart';

class GraphicsItem extends StatefulWidget {
  /// Для тестов — вместо канала платформы.
  final Future<GraphicsState?> Function()? load;
  const GraphicsItem({super.key, this.load});

  @override
  State<GraphicsItem> createState() => _GraphicsItemState();
}

class _GraphicsItemState extends State<GraphicsItem> {
  GraphicsState? _s;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final s = await (widget.load ?? GraphicsMode.state)();
    if (mounted) setState(() => _s = s);
  }

  static String modeName(AppLocalizations l10n, String mode) => switch (mode) {
        'skia' => l10n.tr('graphicsSkia'),
        'impeller' => l10n.tr('graphicsImpeller'),
        _ => l10n.tr('graphicsAuto'),
      };

  /// «Автоматически · Сейчас: Skia (после сбоя 08.11.2026)».
  static String subtitle(BuildContext context, GraphicsState s) {
    final l10n = AppLocalizations.of(context);
    final name = s.active == 'skia' ? 'Skia' : 'Impeller';
    final crash = s.active == 'skia' && s.mode == 'auto' && s.autoAt != null
        ? ' (${l10n.tr('graphicsAfterCrash').replaceAll('{date}', AppDateFormat.date(context, s.autoAt!))})'
        : '';
    final b = StringBuffer('${modeName(l10n, s.mode)} · ${l10n.tr('graphicsNow').replaceAll('{name}', name)}$crash');
    if (s.restartNeeded) b.write('\n${l10n.tr('graphicsRestartNeeded')}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return SettingsItem(
      icon: AppIcons.display_settings,
      title: l10n.tr('graphicsTitle'),
      subtitle: subtitle(context, s),
      onTap: () async {
        await showDialog<void>(context: context, builder: (_) => GraphicsDialog(initial: s));
        await _reload();
      },
    );
  }
}

class GraphicsDialog extends StatefulWidget {
  final GraphicsState initial;

  /// Для тестов — вместо канала платформы.
  final Future<GraphicsState?> Function(String mode)? setMode;
  final Future<void> Function()? restart;
  final Future<GraphicsState?> Function(bool on)? setHcpp;

  /// Пояснения для Mac; null — по платформе (для тестов — задать).
  final bool? mac;
  const GraphicsDialog({super.key, required this.initial, this.setMode, this.restart, this.setHcpp, this.mac});

  @override
  State<GraphicsDialog> createState() => _GraphicsDialogState();
}

class _GraphicsDialogState extends State<GraphicsDialog> {
  late GraphicsState _s = widget.initial;

  Future<void> _pick(String? mode) async {
    if (mode == null || mode == _s.mode) return;
    final s = await (widget.setMode ?? GraphicsMode.setMode)(mode);
    if (s != null && mounted) setState(() => _s = s);
  }

  Future<void> _hcpp(bool on) async {
    final s = await (widget.setHcpp ?? GraphicsMode.setHcpp)(on);
    if (s != null && mounted) setState(() => _s = s);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mac = widget.mac ?? (!kIsWeb && Platform.isMacOS);
    Widget option(String mode, String desc) => AppRadioTile<String>(
          value: mode,
          groupValue: _s.mode,
          onChanged: _pick,
          title: Text(_GraphicsItemState.modeName(l10n, mode)),
          subtitle: Text(l10n.tr(desc)),
        );
    return AlertDialog(
      title: Text(l10n.tr('graphicsTitle')),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(l10n.tr(mac ? 'graphicsHelpMac' : 'graphicsHelp'), style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 8),
            option('auto', mac ? 'graphicsAutoDescMac' : 'graphicsAutoDesc'),
            option('skia', mac ? 'graphicsSkiaDescMac' : 'graphicsSkiaDesc'),
            option('impeller', mac ? 'graphicsImpellerDescMac' : 'graphicsImpellerDesc'),
            // HCPP — только там, где он может работать (Android 14+, Vulkan).
            if (_s.hcppSupported || _s.hcpp)
              SwitchListTile(
                key: const ValueKey('graphics_hcpp'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                value: _s.hcpp,
                onChanged: _hcpp,
                title: Text(l10n.tr('graphicsHcppTitle')),
                subtitle: Text(l10n.tr('graphicsHcppDesc')),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(_GraphicsItemState.subtitle(context, _s), style: theme.textTheme.bodySmall),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        if (_s.restartNeeded)
          FilledButton(
            onPressed: () => (widget.restart ?? GraphicsMode.restart)(),
            child: Text(l10n.tr('graphicsRestart')),
          ),
      ],
    );
  }
}

// lib/features/settings/screens/experimental_settings_screen.dart
//
// «Экспериментальный функционал» (1.10.3, решение владельца 02.11.2026:
// «вернуть раздел и пока точно не решим, отображать подобные вещи там
// по-умолчанию выключенными»). Функции на пробе: по умолчанию выключены,
// могут измениться или уйти в основные настройки. Прежний раздел
// «Возможности» (до 1.6.1) стал основными настройками — здесь только новое.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../widgets/feature_settings_sections.dart' show ExperimentalKeys;

class ExperimentalSettingsScreen extends ConsumerStatefulWidget {
  const ExperimentalSettingsScreen({super.key});

  @override
  ConsumerState<ExperimentalSettingsScreen> createState() => _ExperimentalSettingsScreenState();
}

class _ExperimentalSettingsScreenState extends ConsumerState<ExperimentalSettingsScreen> {
  bool _on(String key) => ref.read(sharedPrefsProvider).getBool(key) ?? false;

  Future<void> _set(String key, bool v) async {
    await ref.read(sharedPrefsProvider).setBool(key, v);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('experimentalTitle')))),
      body: ReadableWidth(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.s, Space.m),
              child: Text(l10n.tr('experimentalIntro'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            SettingsGroup(children: [
              // Люди в шапках цитат (просьба владельца 02.11.2026).
              SettingsSwitchItem(
                key: const ValueKey('exp_quotePeople'),
                icon: AppIcons.groups,
                title: l10n.tr('quotePeopleTitle'),
                subtitle: l10n.tr('quotePeopleDesc'),
                value: _on(ExperimentalKeys.quotePeople),
                onChanged: (v) => _set(ExperimentalKeys.quotePeople, v),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

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
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/readable_width.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

class ExperimentalSettingsScreen extends ConsumerStatefulWidget {
  const ExperimentalSettingsScreen({super.key});

  @override
  ConsumerState<ExperimentalSettingsScreen> createState() => _ExperimentalSettingsScreenState();
}

class _ExperimentalSettingsScreenState extends ConsumerState<ExperimentalSettingsScreen> {
  // Выключатель функции на пробе: ref.read(sharedPrefsProvider).getBool(key)
  // ?? false и SettingsSwitchItem (как у «Людей в цитатах» в 1.10.3).

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
            // «Люди в цитатах» (1.10.3) с 1.10.5 включены по умолчанию и
            // перешли в «Почта → Работа с письмами» (решение владельца
            // 03.11.2026). Новые функции на пробе — здесь, выключателями.
            SettingsGroup(children: [
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Row(children: [
                  Icon(AppIcons.science, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Space.m),
                  Expanded(child: Text(l10n.tr('experimentalEmpty'), style: theme.textTheme.bodyMedium)),
                ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// lib/features/settings/screens/notes_settings_screen.dart
// Настройки модуля Заметки: превью в списке, порядок сортировки.

import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../providers/module_settings_provider.dart';
import '../../../widgets/common/text_scale_cap.dart';

class NotesSettingsScreen extends ConsumerWidget {
  const NotesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(moduleSettingsProvider);
    final n = ref.read(moduleSettingsProvider.notifier);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('notes')),
        actions: const [FaqButton(section: 'tasks')],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('display')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.notes,
              title: l10n.tr('textPreview'),
              subtitle: l10n.tr('showNotePreview'),
              value: s.notesPreviewLines,
              onChanged: n.setNotesPreviewLines,
            ),
          ]),
          SettingsSectionTitle(l10n.tr('sortOrder')),
          SettingsGroup(children: [
            AppRadioTile<bool>(
              title: Text(l10n.tr('sortByModified')),
              value: true,
              groupValue: s.notesSortByModified,
              onChanged: (v) => n.setNotesSortByModified(v!),
            ),
            AppRadioTile<bool>(
              title: Text(l10n.tr('sortByCreatedDate')),
              value: false,
              groupValue: s.notesSortByModified,
              onChanged: (v) => n.setNotesSortByModified(v!),
            ),
          ]),
        ],
      ),
    );
  }
}

// lib/features/settings/widgets/doc_preview_settings_section.dart
// Настройки → Почта → «Просмотр документов» (1.11.x, просьба владельца
// 04.11.2026): общий выключатель и виды документов — текстовые, таблицы,
// CSV таблицей, презентации (DocPreviewSettings). На iPhone и iPad Office,
// RTF и CSV показывает «Просмотр» iOS — там виды касаются только
// OpenDocument, а CSV-переключателя нет.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/documents/doc_preview_settings.dart';
import '../../../widgets/ui/settings_group.dart';

class DocPreviewSettingsSection extends ConsumerStatefulWidget {
  const DocPreviewSettingsSection({super.key});

  @override
  ConsumerState<DocPreviewSettingsSection> createState() => _DocPreviewSettingsSectionState();
}

class _DocPreviewSettingsSectionState extends ConsumerState<DocPreviewSettingsSection> {
  static bool get _ios => !kIsWeb && Platform.isIOS;

  /// Форматы вида — под названием переключателя (названия форматов не
  /// переводятся).
  static String _formats(DocPreviewType t) => switch (t) {
        // Старые DOC, XLS, PPT (1.14.0) — в своих видах; на iPhone и iPad
        // их, как и новые форматы Office, показывает «Просмотр» iOS.
        DocPreviewType.text => _ios ? 'ODT, TXT, Markdown' : 'DOCX, DOC, ODT, RTF, TXT, Markdown',
        DocPreviewType.sheets => _ios ? 'ODS' : 'XLSX, XLS, ODS',
        DocPreviewType.csv => 'CSV, TSV',
        DocPreviewType.slides => _ios ? 'ODP' : 'PPTX, PPT, ODP',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(sharedPrefsProvider);
    final enabled = DocPreviewSettings.enabled;
    Widget type(DocPreviewType t, IconData icon, String title, {String? note}) => SettingsSwitchItem(
          icon: icon,
          title: title,
          subtitle: note == null ? _formats(t) : '${_formats(t)}. $note',
          value: DocPreviewSettings.typeOn(t),
          onChanged: (v) {
            unawaited(DocPreviewSettings.setType(prefs, t, v));
            setState(() {});
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSectionTitle(l10n.tr('docPreviewSection')),
        if (_ios) SettingsIntro(l10n.tr('docPreviewIosNote')),
        SettingsGroup(children: [
          SettingsSwitchItem(
            icon: AppIcons.visibility,
            title: l10n.tr('docPreview'),
            subtitle: l10n.tr('docPreviewDesc'),
            value: enabled,
            onChanged: (v) {
              unawaited(DocPreviewSettings.setEnabled(prefs, v));
              setState(() {});
            },
          ),
          if (enabled) ...[
            type(DocPreviewType.text, AppIcons.description, l10n.tr('docTypeText')),
            type(DocPreviewType.sheets, AppIcons.table_chart, l10n.tr('docTypeSheets')),
            if (!_ios) type(DocPreviewType.csv, AppIcons.text_snippet, l10n.tr('docTypeCsv'), note: l10n.tr('docTypeCsvDesc')),
            type(DocPreviewType.slides, AppIcons.slideshow, l10n.tr('docTypeSlides')),
          ],
        ]),
      ],
    );
  }
}

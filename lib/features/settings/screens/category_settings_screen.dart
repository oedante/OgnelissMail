// lib/features/settings/screens/category_settings_screen.dart
// Управление пользовательскими категориями: список, добавление, удаление,
// цвет (2.7.5), сброс к стандартным, экспорт/импорт настроек (через буфер
// обмена, JSON). Ниже — категории Outlook ящиков Exchange с их цветами.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/category_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../mail/widgets/categories_sheet.dart' show pickCategoryColor, refreshOutlookCategories;
import '../providers/categories_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../widgets/ui/app_menu_button.dart';

class CategorySettingsScreen extends ConsumerStatefulWidget {
  const CategorySettingsScreen({super.key});

  @override
  ConsumerState<CategorySettingsScreen> createState() => _CategorySettingsScreenState();
}

class _CategorySettingsScreenState extends ConsumerState<CategorySettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Категории и цвета Outlook — свежие (2.7.5: раньше раз в сутки).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(refreshOutlookCategories(ref, maxAge: const Duration(minutes: 1)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final categories = ref.watch(categoriesProvider);
    final colors = ref.watch(categoryColorsProvider);
    final notifier = ref.read(categoriesProvider.notifier);
    final server = [
      for (final c in CategoryColors.serverList)
        if (!categories.contains(c.name)) c.name,
    ];

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('categories')),
        actions: [
          AppMenuButton<String>(
            onSelected: (v) async {
              if (v == 'export') {
                await Clipboard.setData(ClipboardData(text: notifier.exportJson()));
                showInlineNotice(l10n.tr('categorySettingsCopied'));
              } else if (v == 'import') {
                await _importDialog(context, ref, ru);
              } else if (v == 'reset') {
                await notifier.resetToDefault();
                showInlineNotice(l10n.tr('defaultCategoriesRestored'));
              }
            },
            itemBuilder: (ctx) => [
              AppMenuEntry(value: 'export', icon: AppIcons.content_copy, label: l10n.tr('exportToClipboardParen')),
              AppMenuEntry(value: 'import', icon: AppIcons.download, label: l10n.tr('importFromClipboardParen')),
              const AppMenuEntry.divider(),
              AppMenuEntry(value: 'reset', icon: AppIcons.restart_alt, label: l10n.tr('resetToDefault'), destructive: true),
            ],
          ),
        ],
      )),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Text(
              l10n.tr('categoriesDescLong'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context)),
            ),
          ),
          Expanded(
            child: categories.isEmpty && server.isEmpty
                ? Center(child: Text(l10n.tr('noCategories')))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 88),
                    children: [
                      for (final c in categories)
                        ListTile(
                          key: ValueKey('category_row_$c'),
                          leading: _ColorButton(name: c, color: categoryColor(c, colors)),
                          title: Text(c),
                          trailing: IconButton(
                            icon: const Icon(AppIcons.close, size: 20),
                            tooltip: l10n.tr('delete'),
                            onPressed: () => notifier.remove(c),
                          ),
                        ),
                      // Категории Outlook ящика Exchange (главный список, с
                      // цветами Outlook) — те, которых нет среди своих.
                      if (server.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xs),
                          child: Text(l10n.tr('outlookCategories'), style: Theme.of(context).textTheme.titleSmall),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                          child: Text(l10n.tr('outlookCategoriesHint'),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                        ),
                        for (final c in server)
                          ListTile(
                            key: ValueKey('category_row_$c'),
                            leading: _ColorButton(name: c, color: categoryColor(c, colors)),
                            title: Text(c),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addDialog(context, ref, ru),
        icon: const Icon(AppIcons.add),
        label: Text(l10n.tr('add')),
      ),
    );
  }

  Future<void> _addDialog(BuildContext context, WidgetRef ref, bool ru) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('newCategory')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.tr('name')),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: Text(l10n.tr('add'))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(categoriesProvider.notifier).add(name);
    }
  }

  Future<void> _importDialog(BuildContext context, WidgetRef ref, bool ru) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    // Предзаполняем из буфера обмена, если там есть текст.
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (clip?.text != null) controller.text = clip!.text!;
    if (!context.mounted) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('importCategories')),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: l10n.tr('pasteCategoriesJson'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: Text(l10n.tr('import'))),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    if (!context.mounted) return;
    final parsed = CategoriesNotifier.parseImport(raw);
    if (parsed == null || parsed.isEmpty) {
      showInlineError(l10n.tr('couldNotParseSettings'));
      return;
    }
    await ref.read(categoriesProvider.notifier).setAll(parsed);
    showInlineNotice(l10n.tr('importedCategoriesN').replaceAll('{n}', '${parsed.length}'));
  }
}

/// Кружок цвета категории: касание — выбрать цвет.
class _ColorButton extends ConsumerWidget {
  final String name;
  final Color color;
  const _ColorButton({required this.name, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        key: ValueKey('category_color_$name'),
        tooltip: AppLocalizations.of(context).tr('categoryColor'),
        icon: Icon(AppIcons.label, fill: 1, color: color),
        onPressed: () => pickCategoryColor(context, ref, name),
      );
}

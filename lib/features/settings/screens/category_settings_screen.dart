// lib/features/settings/screens/category_settings_screen.dart
// Управление пользовательскими категориями: список, добавление, удаление,
// сброс к стандартным, экспорт/импорт настроек (через буфер обмена, JSON).

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/categories_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;

class CategorySettingsScreen extends ConsumerWidget {
  const CategorySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final categories = ref.watch(categoriesProvider);
    final notifier = ref.read(categoriesProvider.notifier);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('categories')),
        actions: [
          PopupMenuButton<String>(
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
              PopupMenuItem(value: 'export', child: Text(l10n.tr('exportToClipboardParen'))),
              PopupMenuItem(value: 'import', child: Text(l10n.tr('importFromClipboardParen'))),
              PopupMenuItem(value: 'reset', child: Text(l10n.tr('resetToDefault'))),
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
            child: categories.isEmpty
                ? Center(child: Text(l10n.tr('noCategories')))
                : ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (ctx, i) {
                      final c = categories[i];
                      return ListTile(
                        leading: const Icon(AppIcons.label),
                        title: Text(c),
                        trailing: IconButton(
                          icon: const Icon(AppIcons.close, size: 20),
                          tooltip: l10n.tr('delete'),
                          onPressed: () => notifier.remove(c),
                        ),
                      );
                    },
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

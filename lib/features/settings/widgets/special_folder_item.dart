// lib/features/settings/widgets/special_folder_item.dart
// «Папка для архива» и «Папка для спама» в настройках ящика (1.7.2+106,
// просьба владельца 24.10.2026, как в Nine и OfficeMail).
//
// Под названием — какая папка сейчас: «Архив · найдена сама», «Старое ·
// выбрана вами», «Не найдена — выберите папку». Нажатие — список:
// «Автоматически» (по названию на любом языке, см. SpecialFolders) и папки
// ящика. Выбор применяется к базе сразу: кнопки «В архив» и «В спам»
// работают, не дожидаясь обновления списка папок с сервера.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/utils/folder_icons.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/folder_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/special_folders.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountFoldersProvider;

class SpecialFolderItem extends ConsumerStatefulWidget {
  final AccountModel account;
  final SpecialKind kind;
  const SpecialFolderItem({super.key, required this.account, required this.kind});

  @override
  ConsumerState<SpecialFolderItem> createState() => _SpecialFolderItemState();
}

class _SpecialFolderItemState extends ConsumerState<SpecialFolderItem> {
  bool get _archive => widget.kind == SpecialKind.archive;

  String get _titleKey => _archive ? 'specialArchiveFolder' : 'specialJunkFolder';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folders = ref.watch(accountFoldersProvider(widget.account.id)).value ?? const <FolderModel>[];
    final chosenId = SpecialFolders.chosen(ref.read(sharedPrefsProvider), widget.account.id, widget.kind);
    final current = folders.where((f) => f.type == widget.kind.type).firstOrNull;
    final subtitle = current == null
        ? l10n.tr('specialFolderNone')
        : l10n
            .tr(current.id == chosenId ? 'specialFolderManual' : 'specialFolderAuto')
            .replaceAll('{name}', current.displayName);
    return SettingsItem(
      icon: _archive ? AppIcons.archive : AppIcons.report,
      title: l10n.tr(_titleKey),
      subtitle: subtitle,
      hint: l10n.tr('specialFoldersHint'),
      onTap: folders.isEmpty ? null : () => unawaited(_pick(context, folders, chosenId, current)),
    );
  }

  Future<void> _pick(BuildContext context, List<FolderModel> folders, String? chosenId, FolderModel? current) async {
    final l10n = AppLocalizations.of(context);
    final byId = {for (final f in folders) f.id: f};
    // Подойдёт обычная папка или нынешняя этого вида; системные («Входящие»,
    // «Удалённые»…) и папка другого вида — нет.
    final options = [
      for (final f in folders)
        if (f.type == FolderType.custom || f.type == widget.kind.type) f,
    ]..sort((a, b) {
        final da = _depth(a, byId), db = _depth(b, byId);
        if (da != db) return da.compareTo(db);
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
    // Отдельное значение для «Автоматически»: null — «передумал».
    const auto = '\u0000auto';
    final picked = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final check = Icon(AppIcons.check, color: theme.colorScheme.primary);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text(l10n.tr(_titleKey), style: theme.textTheme.titleMedium),
                  trailing: HelpButton(text: l10n.tr('specialFoldersHint'), title: l10n.tr(_titleKey)),
                ),
                ListTile(
                  leading: const Icon(AppIcons.auto_awesome),
                  title: Text(l10n.tr('specialFolderAutoOption')),
                  subtitle: Text(l10n.tr(_archive ? 'specialArchiveAutoDesc' : 'specialJunkAutoDesc')),
                  trailing: chosenId == null ? check : null,
                  onTap: () => Navigator.pop(ctx, auto),
                ),
                for (final f in options)
                  ListTile(
                    leading: Icon(folderIconOf(f)),
                    title: Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: switch (_parentPath(f, byId)) {
                      final p? => Text(p,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.mutedText(ctx))),
                      null => null,
                    },
                    trailing: chosenId == f.id ? check : null,
                    onTap: () => Navigator.pop(ctx, f.id),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final id = picked == auto ? null : picked;
    if (id == chosenId) return;
    await SpecialFolders.choose(
        ref.read(databaseProvider), ref.read(sharedPrefsProvider), widget.account.id, widget.kind, id);
    if (mounted) setState(() {});
  }

  static int _depth(FolderModel f, Map<String, FolderModel> byId) {
    var d = 0;
    var p = f.parentId;
    final seen = <String>{};
    while (p != null && byId.containsKey(p) && seen.add(p)) {
      d++;
      p = byId[p]!.parentId;
    }
    return d;
  }

  /// «Входящие / Проекты» — где лежит вложенная папка.
  static String? _parentPath(FolderModel f, Map<String, FolderModel> byId) {
    final parts = <String>[];
    var p = f.parentId;
    final seen = <String>{};
    while (p != null && byId.containsKey(p) && seen.add(p)) {
      parts.insert(0, byId[p]!.displayName);
      p = byId[p]!.parentId;
    }
    return parts.isEmpty ? null : parts.join(' / ');
  }
}

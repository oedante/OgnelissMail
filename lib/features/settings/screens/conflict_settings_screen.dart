import 'package:flutter/material.dart';
import '../../../widgets/ui/app_radio_tile.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/sync/conflict_resolver.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsSectionTitle, SettingsIntro;
import '../../mail/providers/mail_providers.dart' show accountFoldersProvider;

/// Настройка разрешения конфликтов синхронизации (правка одного письма на
/// телефоне и на сервере). Как устроено на деле (1.6.2, описания приведены
/// в соответствие с кодом sync_service._batchSaveEmails):
/// • действие на телефоне, ещё не отправленное на сервер, сохраняется всегда;
/// • «прочитано» и флажок иначе берутся с сервера, теги объединяются;
/// • стратегия решает только папку: телефон (merge) или сервер;
///   askUser — как на сервере и запись расхождения в список.
/// clientWins для папки совпадает с merge — в списке не показывается.
class ConflictSettingsScreen extends ConsumerStatefulWidget {
  const ConflictSettingsScreen({super.key});

  @override
  ConsumerState<ConflictSettingsScreen> createState() => _ConflictSettingsScreenState();
}

class _ConflictSettingsScreenState extends ConsumerState<ConflictSettingsScreen> {
  ConflictResolver get _resolver => ref.read(conflictResolverProvider);

  String _strategyTitle(ConflictStrategy s, bool ru) {
    final l10n = AppLocalizations.of(context);
    switch (s) {
      case ConflictStrategy.merge:
        return l10n.tr('conflictMerge');
      case ConflictStrategy.serverWins:
        return l10n.tr('conflictServerWins');
      case ConflictStrategy.clientWins:
        return l10n.tr('conflictDeviceWins');
      case ConflictStrategy.askUser:
        return l10n.tr('conflictAsk');
    }
  }

  String _strategyDesc(ConflictStrategy s, bool ru) {
    final l10n = AppLocalizations.of(context);
    switch (s) {
      case ConflictStrategy.merge:
        return l10n.tr('conflictMergeDesc');
      case ConflictStrategy.serverWins:
        return l10n.tr('conflictServerWinsDesc');
      case ConflictStrategy.clientWins:
        return l10n.tr('conflictDeviceWinsDesc');
      case ConflictStrategy.askUser:
        return l10n.tr('conflictAskDesc');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ru = l10n.isRussian;
    final stored = _resolver.strategy;
    final current = stored == ConflictStrategy.clientWins ? ConflictStrategy.merge : stored;
    final unresolved = _resolver.getUnresolvedConflicts();

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('syncConflicts')))),
      body: ListView(
        children: [
          SettingsIntro(l10n.tr('conflictIntro')),
          SettingsSectionTitle(l10n.tr('resolutionStrategy')),
          ...ConflictStrategy.values
              .where((s) => s != ConflictStrategy.clientWins)
              .map((s) => AppRadioTile<ConflictStrategy>(
                value: s,
                groupValue: current,
                title: Text(_strategyTitle(s, ru)),
                subtitle: Text(_strategyDesc(s, ru), style: Theme.of(context).textTheme.bodySmall),
                onChanged: (v) async {
                  if (v == null) return;
                  await _resolver.setStrategy(v);
                  if (mounted) setState(() {});
                },
              )),
          if (current == ConflictStrategy.askUser) ...[
            SettingsSectionTitle(l10n.tr('unresolvedConflictsN').replaceAll('{n}', '${unresolved.length}')),
            if (unresolved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                child: Text(l10n.tr('noConflicts'),
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else ...[
              ...unresolved.take(50).map((c) => ListTile(
                    dense: true,
                    leading: Icon(_fieldIcon(c.field), size: 20, color: AppColors.accent(context)),
                    title: Text(_fieldLabel(c.field, ru)),
                    subtitle: Text(
                      '${l10n.tr('deviceWord')}: ${_value(c, c.localValue, l10n)}  •  '
                      '${l10n.tr('serverWord')}: ${_value(c, c.serverValue, l10n)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: IconButton(
                      icon: const Icon(AppIcons.check, size: 20),
                      tooltip: l10n.tr('trackerForget'),
                      onPressed: () async {
                        await _resolver.markResolved(c.emailId, c.field);
                        if (mounted) setState(() {});
                      },
                    ),
                  )),
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: OutlinedButton.icon(
                  icon: const Icon(AppIcons.clear_all),
                  label: Text(l10n.tr('clearConflictList')),
                  onPressed: () async {
                    await _resolver.clearAllConflicts();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Значение по-человечески: папка — названием, отметки — «Да/Нет»
  /// (раньше показывались внутренние id папок и true/false).
  String _value(SyncConflict c, Object? v, AppLocalizations l10n) {
    if (v == null || (v is String && v.isEmpty)) return '—';
    if (v is bool) return l10n.tr(v ? 'yes' : 'no');
    if (c.field == 'folderId') {
      final folders = ref.watch(accountFoldersProvider(c.accountId)).value ?? const [];
      return folders.where((f) => f.id == '$v').firstOrNull?.displayName ?? '$v';
    }
    return '$v';
  }

  IconData _fieldIcon(String field) {
    switch (field) {
      case 'isRead':
        return AppIcons.mark_email_read;
      case 'isFlagged':
        return AppIcons.flag;
      case 'folderId':
        return AppIcons.drive_file_move;
      case 'tags':
        return AppIcons.label;
      default:
        return AppIcons.sync_problem;
    }
  }

  String _fieldLabel(String field, bool ru) {
    final l10n = AppLocalizations.of(context);
    switch (field) {
      case 'isRead':
        return l10n.tr('readFlag');
      case 'isFlagged':
        return l10n.tr('flag');
      case 'folderId':
        return l10n.tr('folderWord');
      case 'tags':
        return l10n.tr('tagsWord');
      default:
        return field;
    }
  }
}

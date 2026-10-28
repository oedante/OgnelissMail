// lib/features/settings/screens/account_groups_screen.dart
//
// Управление группами аккаунтов.
//
// Создать группу, выбрать в неё ящики, переименовать, удалить. 1.6.27
// (замечание владельца «окно создания не проработано»): вместо маленького
// диалога — отдельный экран: название с готовыми вариантами, ящики с фото,
// именем и адресом, кнопка «Сохранить» откликается сразу на ввод названия
// (раньше — только после отметки ящика), удаление — с подтверждением.
// В списке групп — ящики цветными метками, касание открывает группу на
// правку, «Показать в почте» — включает её в ленте.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/text_safe.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/person_photo.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../widgets/ui/help_hint.dart';
import '../../../widgets/ui/app_menu_button.dart';
import '../../mail/providers/account_look.dart' show onAccountColor;
import '../../mail/providers/mail_providers.dart';
import '../providers/account_groups_provider.dart';

/// Имя ящика для списков: имя владельца, если оно есть, иначе адрес.
String _accountName(AccountModel a) {
  final n = a.displayName.trim();
  final login = a.email.split('@').first.toLowerCase();
  return (n.isEmpty || n.toLowerCase() == login || n.toLowerCase() == a.email.toLowerCase()) ? a.email : n;
}

Widget _accountAvatar(AccountModel a, {double radius = 18}) {
  final color = Color(a.colorValue);
  return PhotoRing(
    child: CircleAvatar(
      radius: radius,
      backgroundColor: color,
      foregroundImage: photoImage(a.avatarUrl),
      child: Text(initialOf(_accountName(a)),
          style: TextStyle(fontSize: radius * 0.8, color: onAccountColor(color))),
    ),
  );
}

class AccountGroupsScreen extends ConsumerWidget {
  const AccountGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final groups = ref.watch(accountGroupsProvider);
    final accounts = ref.watch(accountsProvider);
    final activeId = ref.watch(activeGroupIdProvider);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('accountGroups')), actions: [
        HelpButton(text: l10n.tr('accountGroupsHint'), title: l10n.tr('accountGroups')),
      ])),
      floatingActionButton: accounts.length < 2
          ? null // группировать нечего
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(context, null),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.tr('createGroup')),
            ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (accounts.length < 2)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.tr('groupsNeedTwoAccounts'), style: theme.textTheme.bodyMedium),
            )
          else if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.tr('accountGroupsHint'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          for (final g in groups)
            ListTile(
              leading: Icon(AppIcons.folder_shared,
                  color: activeId == g.id ? theme.colorScheme.primary : null),
              title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(children: [
                    for (final (i, a) in accounts.where((a) => g.accountIds.contains(a.id)).indexed) ...[
                      if (i > 0) const TextSpan(text: '   '),
                      TextSpan(text: '● ', style: TextStyle(color: Color(a.colorValue))),
                      TextSpan(text: a.email),
                    ],
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onTap: () => _openEditor(context, g),
              trailing: AppMenuButton<String>(
                itemBuilder: (_) => [
                  AppMenuEntry(value: 'show', icon: AppIcons.inbox, label: l10n.tr('groupShowInMail')),
                  AppMenuEntry(value: 'edit', icon: AppIcons.edit, label: l10n.tr('edit')),
                  AppMenuEntry(value: 'delete', icon: AppIcons.delete, label: l10n.delete, destructive: true),
                ],
                onSelected: (v) async {
                  switch (v) {
                    case 'show':
                      showGroupInMail(ref, g.id);
                      if (context.mounted) context.go('/mail');
                    case 'edit':
                      _openEditor(context, g);
                    case 'delete':
                      await deleteGroupConfirmed(context, ref, g);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, AccountGroup? g) {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AccountGroupEditor(existing: g),
    )));
  }
}

/// Включить группу в ленте почты (как выбор группы в боковом меню).
void showGroupInMail(WidgetRef ref, String groupId) {
  ref.read(activeGroupIdProvider.notifier).state = groupId;
  ref.read(allAccountsModeProvider.notifier).state = false;
  ref.read(unifiedModeProvider.notifier).state = true;
  ref.read(selectedFolderIdProvider.notifier).state = null;
  ref.read(mailFilterProvider.notifier).state = MailFilter.none;
}

/// Удалить группу после подтверждения. true — удалена.
Future<bool> deleteGroupConfirmed(BuildContext context, WidgetRef ref, AccountGroup g) async {
  final l10n = AppLocalizations.of(context);
  final ok = await confirmDestructive(context,
      title: l10n.tr('groupDeleteTitle').replaceAll('{name}', g.name),
      message: l10n.tr('groupDeleteBody'),
      action: l10n.delete);
  if (!ok) return false;
  await ref.read(accountGroupsProvider.notifier).remove(g.id);
  // Удалили активную группу — обычный режим, иначе лента фильтровалась бы
  // по несуществующей.
  if (ref.read(activeGroupIdProvider) == g.id) {
    ref.read(activeGroupIdProvider.notifier).state = null;
  }
  return true;
}

/// Экран создания и правки группы.
class AccountGroupEditor extends ConsumerStatefulWidget {
  final AccountGroup? existing;
  const AccountGroupEditor({super.key, this.existing});

  @override
  ConsumerState<AccountGroupEditor> createState() => _AccountGroupEditorState();
}

class _AccountGroupEditorState extends ConsumerState<AccountGroupEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final Set<String> _selected = {...?widget.existing?.accountIds};
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _selected.isNotEmpty;

  Future<void> _save() async {
    if (!_valid) {
      setState(() => _tried = true);
      return;
    }
    final notifier = ref.read(accountGroupsProvider.notifier);
    final ex = widget.existing;
    // Порядок ящиков — как в списке аккаунтов, а не как отмечали.
    final ids = [
      for (final a in ref.read(accountsProvider))
        if (_selected.contains(a.id)) a.id,
    ];
    if (ex == null) {
      await notifier.add(_name.text.trim(), ids);
    } else {
      await notifier.update(ex.copyWith(name: _name.text.trim(), accountIds: ids));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider);
    final ex = widget.existing;
    final presets = [l10n.tr('groupPresetWork'), l10n.tr('groupPresetPersonal')];
    final nameError = _tried && _name.text.trim().isEmpty ? l10n.tr('groupNeedName') : null;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(ex == null ? l10n.tr('createGroup') : l10n.tr('groupEditTitle')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: FilledButton(onPressed: _valid ? _save : null, child: Text(l10n.save)),
          ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xxl),
        children: [
          TextField(
            controller: _name,
            autofocus: ex == null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: l10n.tr('groupName'),
              prefixIcon: const Icon(AppIcons.folder_shared),
              errorText: nameError,
            ),
          ),
          const SizedBox(height: Space.s),
          Wrap(
            spacing: Space.s,
            children: [
              for (final p in presets)
                ActionChip(
                  label: Text(p),
                  onPressed: () => setState(() {
                    _name.text = p;
                    _name.selection = TextSelection.collapsed(offset: p.length);
                  }),
                ),
            ],
          ),
          const SizedBox(height: Space.l),
          Text(l10n.tr('selectAccounts'), style: theme.textTheme.titleSmall),
          const SizedBox(height: Space.xs),
          Text(
            _tried && _selected.isEmpty ? l10n.tr('groupNeedAccounts') : l10n.tr('groupAccountsHint'),
            style: theme.textTheme.bodySmall?.copyWith(
                color: _tried && _selected.isEmpty ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: Space.s),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, a) in accounts.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  CheckboxListTile(
                    value: _selected.contains(a.id),
                    onChanged: (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id)),
                    secondary: _accountAvatar(a),
                    title: Row(children: [
                      if (a.isSharedMailbox) ...[
                        const Icon(AppIcons.supervisor_account, size: 16, color: kSharedMailboxColor),
                        const SizedBox(width: Space.xs),
                      ],
                      Expanded(child: Text(_accountName(a), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    subtitle: _accountName(a) == a.email
                        ? null
                        : Text(a.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
          if (ex != null) ...[
            const SizedBox(height: Space.xl),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                icon: const Icon(AppIcons.delete),
                label: Text(l10n.tr('groupDelete')),
                onPressed: () async {
                  final nav = Navigator.of(context);
                  if (await deleteGroupConfirmed(context, ref, ex)) nav.pop();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

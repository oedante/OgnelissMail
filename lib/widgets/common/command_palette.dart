// lib/widgets/common/command_palette.dart
// Командная палитра (Ctrl+K) для desktop: быстрый доступ ко всем действиям
// и навигации с клавиатуры. Нечёткий поиск по названию команды.

import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart' show kRulesAndCategoriesEnabled;
import '../../l10n/app_localizations.dart';

class PaletteCommand {
  final String title;
  final IconData icon;
  final String? hint;
  final VoidCallback action;
  const PaletteCommand({required this.title, required this.icon, this.hint, required this.action});
}

class CommandPalette {
  /// Открыть палитру команд.
  static Future<void> show(BuildContext context) async {
    final commands = _defaultCommands(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _CommandPaletteDialog(commands: commands),
    );
  }

  static List<PaletteCommand> _defaultCommands(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      PaletteCommand(title: l10n.tr('paletteNewEmail'), icon: AppIcons.edit, hint: 'Ctrl+N', action: () => context.push('/compose')),
      PaletteCommand(title: l10n.tr('inbox'), icon: AppIcons.inbox, action: () => context.go('/mail')),
      PaletteCommand(title: l10n.tr('calendarLabel'), icon: AppIcons.calendar_month, action: () => context.go('/calendar')),
      PaletteCommand(title: l10n.tr('contactsLabel'), icon: AppIcons.contacts, action: () => context.go('/contacts')),
      PaletteCommand(title: l10n.tr('tasksLabel'), icon: AppIcons.task_alt, action: () => context.go('/tasks')),
      PaletteCommand(title: l10n.tr('settingsLabel'), icon: AppIcons.settings, action: () => context.push('/settings')),
      PaletteCommand(title: l10n.tr('paletteManageAccounts'), icon: AppIcons.manage_accounts, action: () => context.push('/settings/accounts')),
      PaletteCommand(title: l10n.tr('addAccountLbl'), icon: AppIcons.person_add, action: () => context.push('/login?mode=add')),
      PaletteCommand(title: l10n.tr('emailSettings'), icon: AppIcons.mail, action: () => context.push('/settings/mail')),
      PaletteCommand(title: l10n.tr('signatures'), icon: AppIcons.draw, action: () => context.push('/settings/signatures')),
      PaletteCommand(title: l10n.tr('paletteSecurityPinning'), icon: AppIcons.shield, action: () => context.push('/settings/security')),
      // Общие «Правила обработки» скрыты (kRulesAndCategoriesEnabled) —
      // правила на телефоне живут в «VIP и правила».
      if (kRulesAndCategoriesEnabled)
        PaletteCommand(title: l10n.tr('rules'), icon: AppIcons.rule, action: () => context.push('/settings/rules'))
      else
        PaletteCommand(title: l10n.tr('vipRulesTitle'), icon: AppIcons.rule, action: () => context.push('/vip-settings')),
    ];
  }
}

class _CommandPaletteDialog extends StatefulWidget {
  final List<PaletteCommand> commands;
  const _CommandPaletteDialog({required this.commands});

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  int _selected = 0;
  late List<PaletteCommand> _filtered = widget.commands;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.toLowerCase();
    setState(() {
      _filtered = widget.commands
          .where((c) => c.title.toLowerCase().contains(q))
          .toList();
      _selected = 0;
    });
  }

  void _run(PaletteCommand cmd) {
    Navigator.of(context).pop();
    cmd.action();
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1).clamp(0, _filtered.length - 1));
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (_selected - 1).clamp(0, _filtered.length - 1));
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_filtered.isNotEmpty) _run(_filtered[_selected]);
    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: Space.xl, right: Space.xl),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 440),
        child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(AppIcons.search),
                    hintText: l10n.tr('paletteSearchHint'),
                    border: InputBorder.none,
                  ),
                  onChanged: _filter,
                  onSubmitted: (_) {
                    if (_filtered.isNotEmpty) _run(_filtered[_selected]);
                  },
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final cmd = _filtered[i];
                    return Material(
                      color: i == _selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                      child: ListTile(
                        leading: Icon(cmd.icon),
                        title: Text(cmd.title),
                        trailing: cmd.hint != null
                            ? Text(cmd.hint!, style: theme.textTheme.bodySmall)
                            : null,
                        onTap: () => _run(cmd),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

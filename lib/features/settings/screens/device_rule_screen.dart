// lib/features/settings/screens/device_rule_screen.dart
// Правило на устройстве: «ЕСЛИ письмо такое → СДЕЛАТЬ так». Открывается из
// «VIP и правила» и из письма («Правило для отправителя…»). Ошибки — строкой
// над кнопкой «Сохранить», без всплывающих окон.

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/folder_model.dart' show FolderType;
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/rules/device_rules_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider;

/// Открыть редактор правила. [initial] — правка; без него — новое правило
/// (можно подставить отправителя и ящик из письма).
Future<void> openDeviceRule(BuildContext context, {DeviceRule? initial, String? sender, String? accountId}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => DeviceRuleScreen(
      initial: initial ??
          DeviceRule(
            id: const Uuid().v4(),
            accountId: accountId,
            senders: [if (sender != null && sender.trim().isNotEmpty) sender.trim().toLowerCase()],
          ),
      isNew: initial == null,
    ),
  ));
}

/// Папки ящика, куда правило может переложить письмо.
final _ruleFoldersProvider = FutureProvider.autoDispose.family<List<Folder>, String>((ref, accountId) async {
  final db = ref.watch(databaseProvider);
  final rows = await (db.select(db.folders)
        ..where((f) => f.accountId.equals(accountId))
        ..orderBy([(f) => OrderingTerm(expression: f.displayName)]))
      .get();
  const skip = {FolderType.inbox, FolderType.drafts, FolderType.outbox, FolderType.sent};
  return [
    for (final f in rows)
      if (!skip.contains(FolderType.values.elementAtOrNull(f.type))) f,
  ];
});

class DeviceRuleScreen extends ConsumerStatefulWidget {
  final DeviceRule initial;
  final bool isNew;
  const DeviceRuleScreen({super.key, required this.initial, this.isNew = false});

  @override
  ConsumerState<DeviceRuleScreen> createState() => _DeviceRuleScreenState();
}

class _DeviceRuleScreenState extends ConsumerState<DeviceRuleScreen> {
  late DeviceRule _r = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);
  late final _subject = TextEditingController(text: widget.initial.subject);
  late final _tag = TextEditingController(text: widget.initial.tag);
  final _sender = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _tag.dispose();
    _sender.dispose();
    super.dispose();
  }

  void _addSender() {
    final v = _sender.text.trim().toLowerCase();
    if (v.isEmpty) return;
    setState(() {
      if (!_r.senders.contains(v)) _r = _r.copyWith(senders: [..._r.senders, v]);
      _sender.clear();
    });
  }

  void _save(AppLocalizations l10n) {
    _addSender();
    final r = _r.copyWith(name: _name.text.trim(), subject: _subject.text.trim(), tag: _tag.text.trim());
    if (!r.hasCondition) {
      setState(() => _error = l10n.tr('ruleNeedCondition'));
      return;
    }
    if (!r.hasAction) {
      setState(() => _error = l10n.tr('ruleNeedAction'));
      return;
    }
    // «Уведомлять всегда» + «В папку»: письмо не перекладывается (после
    // переноса у него новый id, и уведомление вело бы в никуда) — раньше
    // правило молча не выполняло перенос.
    if (r.notify == RuleNotify.always && r.moveFolderId != null) {
      setState(() => _error = l10n.tr('ruleAlwaysNoMove'));
      return;
    }
    ref.read(deviceRulesProvider.notifier).upsert(r);
    Navigator.of(context).pop();
  }

  String _notifyLabel(RuleNotify n, AppLocalizations l10n) => l10n.tr(switch (n) {
        RuleNotify.keep => 'ruleNotifyKeep',
        RuleNotify.silent => 'ruleNotifySilent',
        RuleNotify.none => 'ruleNotifyNone',
        RuleNotify.always => 'ruleNotifyAlways',
      });

  String _laterLabel(RuleLater l, AppLocalizations l10n) => l10n.tr(switch (l) {
        RuleLater.none => 'ruleLaterNone',
        RuleLater.evening => 'ruleLaterEvening',
        RuleLater.tomorrow => 'ruleLaterTomorrow',
        RuleLater.nextWeek => 'ruleLaterNextWeek',
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).where((a) => a.isActive).toList();
    final acc = accounts.where((a) => a.id == _r.accountId).firstOrNull;
    final muted = AppColors.mutedText(context);

    Widget field(TextEditingController c, String label, {IconData? icon, ValueChanged<String>? onSubmit}) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
          child: TextField(
            controller: c,
            onSubmitted: onSubmit,
            textInputAction: onSubmit == null ? TextInputAction.next : TextInputAction.done,
            decoration: InputDecoration(labelText: label, prefixIcon: icon == null ? null : Icon(icon)),
          ),
        );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr(widget.isNew ? 'ruleNew' : 'ruleEdit')),
        actions: [
          HelpButton(text: l10n.tr('ruleHowItWorks'), title: l10n.tr('rulesSection')),
          if (!widget.isNew)
            IconButton(
              tooltip: l10n.tr('delete'),
              icon: const Icon(AppIcons.delete),
              onPressed: () {
                ref.read(deviceRulesProvider.notifier).remove(_r.id);
                Navigator.of(context).pop();
              },
            ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xxl),
        children: [
          SettingsGroup(children: [
            field(_name, l10n.tr('ruleNameOpt'), icon: AppIcons.label),
            ListTile(
              leading: const Icon(AppIcons.alternate_email),
              title: Text(l10n.tr('ruleAccount')),
              subtitle: Text(acc?.email ?? l10n.tr('ruleAllAccounts')),
              trailing: PopupMenuButton<String>(
                icon: const Icon(AppIcons.arrow_drop_down),
                onSelected: (v) => setState(() {
                  // Папки у каждого ящика свои — при смене ящика папка сбрасывается.
                  _r = v.isEmpty
                      ? _r.copyWith(clearAccount: true, clearMove: true)
                      : _r.copyWith(accountId: v, clearMove: v != _r.accountId);
                }),
                itemBuilder: (_) => [
                  PopupMenuItem(value: '', child: Text(l10n.tr('ruleAllAccounts'))),
                  for (final a in accounts) PopupMenuItem(value: a.id, child: Text(a.email)),
                ],
              ),
            ),
          ]),

          // ── ЕСЛИ ──
          SettingsSectionTitle(l10n.tr('ruleIf')),
          SettingsGroup(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Text(l10n.tr('ruleSenders'), style: theme.textTheme.labelLarge),
            ),
            if (_r.senders.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
                  for (final s in _r.senders)
                    InputChip(
                      label: Text(s),
                      onDeleted: () => setState(() => _r = _r.copyWith(senders: [..._r.senders]..remove(s))),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _sender,
                    keyboardType: TextInputType.emailAddress,
                    enableSuggestions: false,
                    autocorrect: false,
                    onSubmitted: (_) => _addSender(),
                    decoration: InputDecoration(hintText: l10n.tr('ruleSenderHint'), prefixIcon: const Icon(AppIcons.person)),
                  ),
                ),
                IconButton(tooltip: l10n.tr('add'), icon: const Icon(AppIcons.add), onPressed: _addSender),
              ]),
            ),
            field(_subject, l10n.tr('ruleSubject'), icon: AppIcons.title),
            SettingsSwitchItem(
              icon: AppIcons.group,
              title: l10n.tr('ruleCcOnly'),
              value: _r.ccOnly,
              onChanged: (v) => setState(() => _r = _r.copyWith(ccOnly: v)),
            ),
            SettingsSwitchItem(
              icon: AppIcons.attach_file,
              title: l10n.tr('ruleHasAttachment'),
              value: _r.hasAttachment,
              onChanged: (v) => setState(() => _r = _r.copyWith(hasAttachment: v)),
            ),
            SettingsSwitchItem(
              icon: AppIcons.campaign,
              title: l10n.tr('ruleMailingList'),
              value: _r.mailingList,
              onChanged: (v) => setState(() => _r = _r.copyWith(mailingList: v)),
            ),
          ]),

          // ── ТО ──
          SettingsSectionTitle(l10n.tr('ruleThen')),
          SettingsGroup(children: [
            ListTile(
              leading: const Icon(AppIcons.notifications),
              title: Text(l10n.tr('ruleNotify')),
              subtitle: Text(_notifyLabel(_r.notify, l10n)),
              trailing: PopupMenuButton<RuleNotify>(
                icon: const Icon(AppIcons.arrow_drop_down),
                initialValue: _r.notify,
                onSelected: (v) => setState(() => _r = _r.copyWith(notify: v)),
                itemBuilder: (_) => [
                  for (final n in RuleNotify.values) PopupMenuItem(value: n, child: Text(_notifyLabel(n, l10n))),
                ],
              ),
            ),
            _folderTile(context, l10n, muted),
            SettingsSwitchItem(
              icon: AppIcons.drafts,
              title: l10n.tr('ruleMarkRead'),
              value: _r.markRead,
              onChanged: (v) => setState(() => _r = _r.copyWith(markRead: v)),
            ),
            SettingsSwitchItem(
              icon: AppIcons.flag,
              title: l10n.tr('ruleFlag'),
              value: _r.flag,
              onChanged: (v) => setState(() => _r = _r.copyWith(flag: v)),
            ),
            SettingsSwitchItem(
              icon: AppIcons.bookmark,
              title: l10n.tr('ruleControl'),
              subtitle: l10n.tr('ruleControlDesc'),
              value: _r.control,
              onChanged: (v) => setState(() => _r = _r.copyWith(control: v)),
            ),
            ListTile(
              leading: const Icon(AppIcons.watch_later),
              title: Text(l10n.tr('ruleLater')),
              subtitle: Text(_laterLabel(_r.later, l10n)),
              trailing: PopupMenuButton<RuleLater>(
                icon: const Icon(AppIcons.arrow_drop_down),
                initialValue: _r.later,
                onSelected: (v) => setState(() => _r = _r.copyWith(later: v)),
                itemBuilder: (_) => [
                  for (final l in RuleLater.values) PopupMenuItem(value: l, child: Text(_laterLabel(l, l10n))),
                ],
              ),
            ),
            field(_tag, l10n.tr('ruleTag'), icon: AppIcons.label_important),
            SettingsSwitchItem(
              icon: AppIcons.palette,
              title: l10n.tr('ruleHighlight'),
              subtitle: l10n.tr('ruleHighlightDesc'),
              value: _r.highlight,
              onChanged: (v) => setState(() => _r = _r.copyWith(highlight: v)),
            ),
          ]),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 0),
              child: Row(children: [
                Icon(AppIcons.error, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: Space.s),
                Expanded(child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: FilledButton.icon(
              onPressed: () => _save(l10n),
              icon: const Icon(AppIcons.check),
              label: Text(l10n.tr('save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderTile(BuildContext context, AppLocalizations l10n, Color muted) {
    final accId = _r.accountId;
    if (accId == null) {
      return ListTile(
        leading: Icon(AppIcons.drive_file_move, color: muted),
        title: Text(l10n.tr('ruleMove'), style: TextStyle(color: muted)),
        subtitle: Text(l10n.tr('ruleMoveNeedAccount')),
      );
    }
    final folders = ref.watch(_ruleFoldersProvider(accId)).value ?? const <Folder>[];
    return ListTile(
      leading: const Icon(AppIcons.drive_file_move),
      title: Text(l10n.tr('ruleMove')),
      subtitle: Text(_r.moveFolderName ?? l10n.tr('ruleMoveNone')),
      trailing: PopupMenuButton<String>(
        icon: const Icon(AppIcons.arrow_drop_down),
        onSelected: (v) => setState(() {
          final f = folders.where((x) => x.id == v).firstOrNull;
          _r = f == null ? _r.copyWith(clearMove: true) : _r.copyWith(moveFolderId: f.id, moveFolderName: f.displayName);
        }),
        itemBuilder: (_) => [
          PopupMenuItem(value: '', child: Text(l10n.tr('ruleMoveNone'))),
          for (final f in folders) PopupMenuItem(value: f.id, child: Text(f.displayName)),
        ],
      ),
    );
  }
}

/// Краткое описание правила для списка: «от firm.ru · без звука, в папку …».
String deviceRuleSummary(DeviceRule r, AppLocalizations l10n) {
  final cond = [
    if (r.senders.isNotEmpty) r.senders.take(2).join(', ') + (r.senders.length > 2 ? '…' : ''),
    if (r.subject.trim().isNotEmpty) '«${r.subject.trim()}»',
    if (r.ccOnly) l10n.tr('ruleCcOnlyShort'),
    if (r.hasAttachment) l10n.tr('ruleHasAttachmentShort'),
    if (r.mailingList) l10n.tr('ruleMailingListShort'),
  ];
  final act = [
    if (r.notify != RuleNotify.keep)
      l10n.tr(switch (r.notify) {
        RuleNotify.silent => 'ruleNotifySilent',
        RuleNotify.none => 'ruleNotifyNone',
        _ => 'ruleNotifyAlways',
      }),
    if (r.moveFolderName != null) '→ ${r.moveFolderName}',
    if (r.markRead) l10n.tr('ruleMarkReadShort'),
    if (r.flag) l10n.tr('ruleFlagShort'),
    if (r.control) l10n.tr('ruleControlShort'),
    if (r.later != RuleLater.none) l10n.tr('ruleLaterShort'),
    if (r.tag.trim().isNotEmpty) '#${r.tag.trim()}',
  ];
  return '${cond.join(' · ')} → ${act.join(', ')}';
}

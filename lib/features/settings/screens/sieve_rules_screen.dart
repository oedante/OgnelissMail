// lib/features/settings/screens/sieve_rules_screen.dart
// Фильтры на сервере IMAP (Sieve): список правил Ogneliss, включить и
// выключить, добавить, изменить, удалить; скрипт целиком — для знающих.
// Сервис — sieve_service.dart; протокол — managesieve_client.dart.
//
// 1.7.3: открывается из настроек ящика (свой ящик, без переключателя);
// сервер, который не отвечает (у служб без ManageSieve), — понятной строкой
// через 10 с, с кнопками «Повторить», «Сервер фильтров» и «Правила на
// телефоне», а не крутилкой; редактор правила — общий с правилами Exchange
// (filter_rule_editor.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../data/database/app_database.dart' show AppDatabase;
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/sieve/managesieve_client.dart' show SieveException;
import '../../../services/mail/sieve/sieve_rules.dart';
import '../../../services/mail/sieve/sieve_service.dart';
import '../../../services/mail/server_filters.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../widgets/ui/settings_group.dart';
import '../widgets/filter_rule_editor.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider;

/// Папки ящика для «Переложить в папку»: (путь для Sieve, подпись).
Future<List<FilterFolder>> _sieveFolders(AppDatabase db, String accountId) async {
  final rows = await (db.select(db.folders)..where((f) => f.accountId.equals(accountId))).get();
  final out = <FilterFolder>[
    for (final f in rows)
      (id: decodeImapUtf7(f.serverPath ?? f.id), label: decodeImapUtf7(f.serverPath ?? f.id)),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  return out;
}

class SieveRulesScreen extends ConsumerStatefulWidget {
  final String? accountId;
  const SieveRulesScreen({super.key, this.accountId});

  @override
  ConsumerState<SieveRulesScreen> createState() => _SieveRulesScreenState();
}

class _SieveRulesScreenState extends ConsumerState<SieveRulesScreen> {
  AccountModel? _account;
  SieveState? _state;
  List<SieveRule> _rules = const [];
  bool _loading = false;
  bool _saving = false;
  String? _error;

  /// Ящики с ManageSieve: IMAP с паролем, не у служб без фильтров по
  /// протоколу (iCloud, Gmail…; 1.7.3 — у них порт 4190 молчал).
  List<AccountModel> get _accounts =>
      [for (final a in ref.read(accountsProvider)) if (SieveService.supports(a) && ServerFilters.kindOf(a) == ServerFilterKind.sieve) a];

  @override
  void initState() {
    super.initState();
    final list = _accounts;
    _account = list.where((a) => a.id == widget.accountId).firstOrNull ??
        list.where((a) => a.id == ref.read(activeAccountProvider)?.id).firstOrNull ??
        list.firstOrNull;
    unawaited(_load());
  }

  String _describe(Object e, AppLocalizations l10n) {
    final acc = _account;
    final server = acc == null ? '' : '${ref.read(sieveServiceProvider).hostOf(acc)}:${ref.read(sieveServiceProvider).portOf(acc)}';
    if (e is SieveException) {
      switch (e.code) {
        case 'NO-TLS':
          return l10n.tr('sieveNoTls');
        case 'NO-ANSWER':
          return l10n.tr('sieveNoAnswer').replaceAll('{server}', server);
        case 'NO-PLAIN':
          return l10n.tr('sieveNoPlain');
        case 'AUTH':
          return l10n.tr('sieveAuthFailed');
        case 'NO-PASSWORD':
          return l10n.tr('sieveNoPassword');
      }
      if (e.message == 'connection closed') return l10n.tr('sieveNoAnswer').replaceAll('{server}', server);
    }
    if (e is TimeoutException) return l10n.tr('sieveNoAnswer').replaceAll('{server}', server);
    return '$e';
  }

  Future<void> _load() async {
    final acc = _account;
    if (acc == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await ref.read(sieveServiceProvider).load(acc);
      if (!mounted) return;
      setState(() {
        _state = st;
        _rules = List.of(st.rules);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = null;
        _loading = false;
        _error = '${l10n.tr('sieveLoadFailed')}: ${_describe(e, l10n)}';
      });
    }
  }

  /// Записать список правил на сервер; при ошибке — вернуть прежний.
  Future<void> _save(List<SieveRule> rules) async {
    final acc = _account;
    final st = _state;
    if (acc == null || st == null) return;
    final l10n = AppLocalizations.of(context);
    final before = _rules;
    setState(() {
      _rules = rules;
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sieveServiceProvider).saveRules(acc, st, rules);
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rules = before;
        _saving = false;
        _error = '${l10n.tr('sieveSaveFailed')}: ${_describe(e, l10n)}';
      });
    }
  }

  Future<void> _edit({int? index}) async {
    final acc = _account;
    if (acc == null) return;
    final ext = _state?.extensions ?? const <String>{};
    bool has(String x) => ext.isEmpty || ext.contains(x);
    final folders = await _sieveFolders(ref.read(databaseProvider), acc.id);
    if (!mounted) return;
    final result = await showFilterRuleEditor(
      context,
      initial: index == null ? null : _rules[index],
      folders: folders,
      actions: {
        if (has('fileinto')) SieveAction.move,
        if (has('imap4flags')) ...{SieveAction.markRead, SieveAction.flag},
        SieveAction.delete,
        SieveAction.forward,
      },
    );
    if (result == null) return;
    final list = List.of(_rules);
    if (result.delete) {
      if (index != null) list.removeAt(index);
    } else if (index == null) {
      list.add(result.rule!);
    } else {
      list[index] = result.rule!;
    }
    await _save(list);
  }

  Future<void> _serverDialog() async {
    final acc = _account;
    if (acc == null) return;
    final svc = ref.read(sieveServiceProvider);
    final l10n = AppLocalizations.of(context);
    final host = TextEditingController(text: svc.hostOf(acc));
    final port = TextEditingController(text: '${svc.portOf(acc)}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('sieveServer')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: host, decoration: InputDecoration(labelText: l10n.tr('server'))),
          const SizedBox(height: Space.s),
          TextField(
            controller: port,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.tr('sievePort')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    final h = host.text.trim();
    final p = int.tryParse(port.text.trim()) ?? 4190;
    host.dispose();
    port.dispose();
    if (ok != true || h.isEmpty) return;
    await svc.setServer(acc, h, p);
    await _load();
  }

  Future<void> _openScript() async {
    final acc = _account;
    final st = _state;
    if (acc == null || st == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _ScriptEditor(account: acc, name: st.scriptName, text: st.script, activate: !st.hasActive),
    ));
    if (saved == true) await _load();
  }

  String _ruleSummary(SieveRule r, AppLocalizations l10n) {
    final field = filterFieldLabel(r.field, l10n);
    final op = r.op == SieveOp.isExactly ? l10n.tr('sieveOpIs') : l10n.tr('sieveOpContains');
    return '$field $op «${r.value}» → ${filterActionLabel(r.action, l10n)}${r.arg.isEmpty ? '' : ' ${r.arg}'}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final acc = _account;
    final st = _state;
    final accounts = _accounts;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('sieveTitle')),
        actions: [
          if (acc != null)
            IconButton(tooltip: l10n.tr('sieveServer'), icon: const Icon(AppIcons.dns), onPressed: _serverDialog),
          IconButton(tooltip: l10n.tr('sync'), icon: const Icon(AppIcons.refresh), onPressed: _loading ? null : _load),
        ],
      )),
      floatingActionButton: st == null || _saving
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.tr('sieveRuleNew')),
            ),
      body: acc == null
          ? EmptyState(
              icon: AppIcons.filter_list,
              title: l10n.tr('sieveNoAccounts'),
              message: l10n.tr('sieveNoAccountsHint'),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 96),
                children: [
                  // Открыт из настроек ящика — только этот ящик.
                  if (widget.accountId == null && accounts.length > 1)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(top: Space.s),
                      child: Row(children: [
                        for (final a in accounts)
                          Padding(
                            padding: const EdgeInsets.only(right: Space.s),
                            child: ChoiceChip(
                              label: Text(a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email),
                              selected: a.id == acc.id,
                              onSelected: (_) {
                                setState(() {
                                  _account = a;
                                  _state = null;
                                  _rules = const [];
                                });
                                unawaited(_load());
                              },
                            ),
                          ),
                      ]),
                    ),
                  SettingsIntro(l10n.tr('sieveIntro'), more: l10n.tr('sieveMore'), moreTitle: l10n.tr('sieveTitle')),
                  if (_error != null) _notice(context, _error!),
                  // Не подключились — что можно сделать.
                  if (_error != null && st == null && !_loading)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.m),
                      child: Wrap(spacing: Space.s, runSpacing: Space.s, alignment: WrapAlignment.center, children: [
                        FilledButton.tonalIcon(
                          onPressed: _load,
                          icon: const Icon(AppIcons.refresh, size: 18),
                          label: Text(l10n.tr('retry')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _serverDialog,
                          icon: const Icon(AppIcons.dns, size: 18),
                          label: Text(l10n.tr('sieveServer')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/vip-settings'),
                          icon: const Icon(AppIcons.rule, size: 18),
                          label: Text(l10n.tr('srvFiltersPhoneRules')),
                        ),
                      ]),
                    ),
                  if (_loading && st == null)
                    const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
                  else if (st != null) ...[
                    SettingsSectionTitle(
                      l10n.tr('sieveRulesSection'),
                      trailing: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : null,
                    ),
                    if (_rules.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Text(l10n.tr('sieveEmpty'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
                      )
                    else
                      SettingsGroup(children: [
                        for (var i = 0; i < _rules.length; i++)
                          SettingsItem(
                            icon: filterActionIcon(_rules[i].action),
                            color: _rules[i].enabled ? null : theme.disabledColor,
                            title: _rules[i].name.trim().isNotEmpty ? _rules[i].name.trim() : _rules[i].value,
                            subtitle: _ruleSummary(_rules[i], l10n),
                            trailing: Switch(
                              value: _rules[i].enabled,
                              onChanged: _saving
                                  ? null
                                  : (v) {
                                      final list = List.of(_rules);
                                      list[i] = list[i].copyWith(enabled: v);
                                      unawaited(_save(list));
                                    },
                            ),
                            onTap: _saving ? null : () => _edit(index: i),
                          ),
                      ]),
                    if (st.parts.hasForeignRules)
                      _notice(context, l10n.tr('sieveForeign').replaceAll('{name}', st.scriptName), warn: false),
                    SettingsSectionTitle(l10n.tr('sieveScript'), help: l10n.tr('sieveScriptHint')),
                    SettingsGroup(children: [
                      SettingsItem(
                        icon: AppIcons.code,
                        title: st.scriptName,
                        subtitle: '${st.host}:${st.port}',
                        onTap: _openScript,
                      ),
                    ]),
                  ],
                ],
              ),
            ),
    );
  }
}

Widget _notice(BuildContext context, String text, {bool warn = true}) {
  final theme = Theme.of(context);
  final c = warn ? theme.colorScheme.error : theme.colorScheme.primary;
  return Container(
    margin: const EdgeInsets.only(top: Space.s),
    padding: const EdgeInsets.all(Space.m),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.08),
      borderRadius: Radii.cardAll,
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(warn ? AppIcons.error : AppIcons.info, size: Sizes.iconRow, color: c),
      const SizedBox(width: Space.s),
      Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
    ]),
  );
}

// ════════════════════════ Скрипт целиком ════════════════════════

class _ScriptEditor extends ConsumerStatefulWidget {
  final AccountModel account;
  final String name;
  final String text;
  final bool activate;
  const _ScriptEditor({required this.account, required this.name, required this.text, required this.activate});

  @override
  ConsumerState<_ScriptEditor> createState() => _ScriptEditorState();
}

class _ScriptEditorState extends ConsumerState<_ScriptEditor> {
  late final _c = TextEditingController(text: widget.text);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sieveServiceProvider).saveRaw(widget.account, widget.name, _c.text, activate: widget.activate);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${l10n.tr('sieveSaveFailed')}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(widget.name),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(Space.l),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(tooltip: l10n.tr('save'), icon: const Icon(AppIcons.check), onPressed: _save),
        ],
      )),
      body: Column(children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 0),
            child: _notice(context, _error!),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(Space.m),
            child: TextField(
              controller: _c,
              maxLines: null,
              expands: true,
              keyboardType: TextInputType.multiline,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: l10n.tr('sieveScriptHint'),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

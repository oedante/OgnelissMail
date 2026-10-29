// lib/features/settings/screens/exchange_tools_screen.dart
// Exchange на сервере: правила (включить/выключить) и «Восстановить
// удалённые» (план П3, пункты 12–13; сервис — ews_server_tools.dart).
// Оба экрана — для ящиков с доступом к EWS (AccountModel.hasEwsExtras);
// несколько таких ящиков — переключатель сверху.
//
// 1.7.3 (замечание владельца 25.10.2026: «EWS/EAS вообще нет»): открываются
// из настроек ящика — своим ящиком, без переключателя; у ящика ActiveSync —
// через EWS того же сервера, если он открыт ([ewsAccountFor]), иначе экран
// объясняет, почему правила сервера недоступны, и ведёт к правилам на
// телефоне. Правила можно создавать (редактор — общий с фильтрами Sieve) и
// удалять.
//
// 1.8.10: у ящика Exchange Online — через Microsoft Graph ([serverToolsFor]),
// EWS там Microsoft отключает; без согласия на Graph — по EWS, как раньше.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/ews/ews_server_tools.dart';
import '../../../services/mail/engine/graph_server_tools.dart' show graphServerToolsProvider;
import '../../../services/mail/engine/mail_engine_service.dart' show mailEngineServiceProvider;
import '../../../services/mail/oauth/graph_tokens.dart' show graphTokensProvider;
import '../../../services/mail/sieve/sieve_rules.dart' show SieveAction;
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../widgets/filter_rule_editor.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart' show accountsProvider, activeAccountProvider, emailsProvider;

/// Ящики, где есть EWS (основной транспорт или «спутник» ActiveSync).
List<AccountModel> ewsAccounts(WidgetRef ref) =>
    [for (final a in ref.read(accountsProvider)) if (a.isActive && a.hasEwsExtras) a];

/// Переключатель ящика (если EWS-ящиков несколько).
class _AccountChips extends StatelessWidget {
  final List<AccountModel> accounts;
  final AccountModel selected;
  final ValueChanged<AccountModel> onSelect;
  const _AccountChips({required this.accounts, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    if (accounts.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Row(children: [
        for (final a in accounts)
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: ChoiceChip(
              label: Text(a.displayName.trim().isNotEmpty ? a.displayName.trim() : a.email),
              selected: a.id == selected.id,
              onSelected: (_) => onSelect(a),
            ),
          ),
      ]),
    );
  }
}

/// Ящик для запросов EWS (1.7.3): сам ящик, если EWS у него есть; ящик
/// ActiveSync — с адресом EWS того же сервера, если сервер его открывает;
/// null — EWS нет (шлюз закрывает EWS — правила сервера по ActiveSync
/// недоступны).
Future<AccountModel?> ewsAccountFor(WidgetRef ref, AccountModel a) async {
  if (a.hasEwsExtras) return a;
  if (!a.usesEas) return null;
  final url = await ref.read(mailEngineServiceProvider).directoryEwsUrl(a);
  return url == null ? null : a.copyWith(ewsUrl: url);
}

/// Через что работают правила и «Восстановить удалённые» (1.8.10): у
/// Exchange Online — Microsoft Graph, если есть согласие на него; иначе EWS
/// (свой или того же сервера у ActiveSync). null — ни того, ни другого.
/// [graph] — через Graph.
Future<({AccountModel account, ServerTools tools, bool graph})?> serverToolsFor(WidgetRef ref, AccountModel a) async {
  final graph = ref.read(graphTokensProvider);
  if (graph.supports(a) && await graph.token(a) != null) {
    return (account: a, tools: ref.read(graphServerToolsProvider), graph: true);
  }
  final ews = await ewsAccountFor(ref, a);
  return ews == null ? null : (account: ews, tools: ref.read(ewsServerToolsProvider), graph: false);
}

AccountModel? _initial(WidgetRef ref, String? accountId) {
  // Из настроек ящика — этот ящик Exchange, даже без своего EWS (1.7.3).
  if (accountId != null) {
    final own = ref.read(accountsProvider).where((a) => a.id == accountId && a.isMsExchange).firstOrNull;
    if (own != null) return own;
  }
  final list = ewsAccounts(ref);
  if (list.isEmpty) return null;
  return list.where((a) => a.id == accountId).firstOrNull ??
      list.where((a) => a.id == ref.read(activeAccountProvider)?.id).firstOrNull ??
      list.first;
}

// ════════════════════════ Серверные правила ════════════════════════

class ServerRulesScreen extends ConsumerStatefulWidget {
  final String? accountId;
  const ServerRulesScreen({super.key, this.accountId});

  @override
  ConsumerState<ServerRulesScreen> createState() => _ServerRulesScreenState();
}

class _ServerRulesScreenState extends ConsumerState<ServerRulesScreen> {
  late AccountModel? _account = _initial(ref, widget.accountId);

  /// Ящик для запросов EWS (у ActiveSync — с адресом EWS того же сервера)
  /// или ящик Exchange Online для запросов Graph.
  AccountModel? _ews;

  /// Через что: EWS или Microsoft Graph (1.8.10).
  ServerTools? _tools;
  bool _viaGraph = false;

  /// У ящика ActiveSync EWS нет — правила сервера недоступны.
  bool _noEws = false;

  ServerRulesResult? _result;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final acc = _account;
    if (acc == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _noEws = false;
    });
    final via = await serverToolsFor(ref, acc);
    if (!mounted) return;
    if (via == null) {
      setState(() {
        _ews = null;
        _tools = null;
        _result = null;
        _noEws = true;
        _loading = false;
      });
      return;
    }
    final ews = _ews = via.account;
    _tools = via.tools;
    _viaGraph = via.graph;
    final r = await via.tools.getRules(ews);
    if (!mounted) return;
    setState(() {
      _result = r;
      _loading = false;
    });
  }

  /// EWS того же сервера не ответил — проверить заново (отказ помнится
  /// неделю).
  Future<void> _retryEws() async {
    final acc = _account;
    if (acc == null) return;
    await ref.read(mailEngineServiceProvider).forgetDirectoryEws(acc.id);
    await _load();
  }

  String _errorText(String err, AppLocalizations l10n) => switch (err) {
        'outlookBlob' => l10n.tr('srvRulesOutlookBlob'),
        'readOnly' => l10n.tr('srvRulesReadOnly'),
        _ => '${l10n.tr('error')}: $err',
      };

  /// Новое правило (1.7.3): одно условие, одно действие — тот же редактор,
  /// что у фильтров Sieve; «Отметить флажком» в правилах EWS нет, тема
  /// проверяется только на «содержит».
  Future<void> _create() async {
    final ews = _ews;
    final tools = _tools;
    if (ews == null || tools == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    var folders = const <FilterFolder>[];
    try {
      folders = await tools.ruleFolders(ews);
    } catch (_) {
      // Без списка папок — правило без «Переложить в папку».
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final res = await showFilterRuleEditor(
      context,
      folders: folders,
      actions: {
        if (folders.isNotEmpty) SieveAction.move,
        SieveAction.markRead,
        SieveAction.delete,
        SieveAction.forward,
      },
      subjectExact: false,
    );
    final rule = res?.rule;
    if (rule == null || !mounted) return;
    setState(() => _busy = true);
    final err = await tools.createRule(ews, rule, priority: (_result?.rules.length ?? 0) + 1);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) _error = _errorText(err, l10n);
    });
    if (err == null) await _load();
  }

  /// Карточка правила: что делает, удалить.
  Future<void> _ruleSheet(ServerRule rule) async {
    final ews = _ews;
    if (ews == null) return;
    final l10n = AppLocalizations.of(context);
    final remove = await showAppSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(rule.name.trim().isEmpty ? l10n.tr('srvRuleNoName') : rule.name.trim(),
                style: Theme.of(ctx).textTheme.titleMedium),
            if (_actions(rule, l10n).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(_actions(rule, l10n),
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(ctx))),
              ),
            if (rule.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Text(l10n.tr('srvRuleOutlookOnly'), style: Theme.of(ctx).textTheme.bodySmall),
              ),
            const SizedBox(height: Space.l),
            Row(children: [
              if (!rule.readOnly)
                TextButton.icon(
                  icon: const Icon(AppIcons.delete),
                  label: Text(l10n.tr('sieveRuleDelete')),
                  style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.tr('close'))),
            ]),
          ]),
        ),
      ),
    );
    if (remove != true || !mounted) return;
    final ok = await confirmDestructive(
      context,
      title: l10n.tr('srvRuleDeleteAsk'),
      message: rule.name.trim().isEmpty ? null : rule.name.trim(),
    );
    if (!ok || !mounted) return;
    setState(() {
      _saving.add(rule.id);
      _error = null;
    });
    final tools = _tools;
    if (tools == null) return;
    final err = await tools.deleteRule(ews, rule);
    if (!mounted) return;
    setState(() {
      _saving.remove(rule.id);
      if (err != null) _error = _errorText(err, l10n);
    });
    if (err == null) await _load();
  }

  Future<void> _toggle(ServerRule rule, bool on) async {
    final acc = _ews;
    final tools = _tools;
    if (acc == null || tools == null) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _saving.add(rule.id);
      _error = null;
    });
    final err = await tools.setEnabled(acc, rule, on);
    if (!mounted) return;
    setState(() {
      _saving.remove(rule.id);
      if (err != null) _error = _errorText(err, l10n);
    });
    if (err == null) await _load();
  }

  String _actions(ServerRule r, AppLocalizations l10n) {
    if (r.actions.isEmpty) return '';
    return r.actions.map((a) => l10n.tr('srvRuleAct_$a')).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final acc = _account;
    final rules = _result?.rules ?? const <ServerRule>[];
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('srvRulesTitle')),
        actions: [
          IconButton(tooltip: l10n.tr('sync'), icon: const Icon(AppIcons.refresh), onPressed: _loading ? null : _load),
        ],
      )),
      floatingActionButton: _ews == null || _result == null || _result!.error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(AppIcons.add),
              label: Text(l10n.tr('sieveRuleNew')),
            ),
      body: acc == null
          ? EmptyState(icon: AppIcons.rule, title: l10n.tr('srvNoEws'), message: l10n.tr('srvNoEwsHint'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, 96),
                children: [
                  if (widget.accountId == null)
                  _AccountChips(
                    accounts: ewsAccounts(ref),
                    selected: acc,
                    onSelect: (a) {
                      setState(() {
                        _account = a;
                        _result = null;
                      });
                      unawaited(_load());
                    },
                  ),
                  SettingsIntro(l10n.tr('srvRulesIntro'), more: l10n.tr('srvRulesMore'), moreTitle: l10n.tr('srvRulesTitle')),
                  if (_viaGraph) _notice(context, l10n.tr('srvViaGraph'), warn: false),
                  // Ящик ActiveSync, а EWS сервер не открывает (1.7.3).
                  if (_noEws) ...[
                    _notice(context, l10n.tr('srvRulesNoEwsEas'), warn: false),
                    Padding(
                      padding: const EdgeInsets.only(top: Space.m),
                      child: Wrap(spacing: Space.s, runSpacing: Space.s, alignment: WrapAlignment.center, children: [
                        FilledButton.tonalIcon(
                          onPressed: _loading ? null : _retryEws,
                          icon: const Icon(AppIcons.refresh, size: 18),
                          label: Text(l10n.tr('retry')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/vip-settings'),
                          icon: const Icon(AppIcons.rule, size: 18),
                          label: Text(l10n.tr('srvFiltersPhoneRules')),
                        ),
                      ]),
                    ),
                  ],
                  if (_error != null) _notice(context, _error!),
                  if (_result?.error != null) _notice(context, '${l10n.tr('srvLoadFailed')}: ${_result!.error}'),
                  if (_result?.outlookBlob == true) _notice(context, l10n.tr('srvRulesBlobHint'), warn: false),
                  if (_loading && _result == null)
                    const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
                  else if (_noEws)
                    const SizedBox.shrink()
                  else if (rules.isEmpty && _result?.error == null)
                    Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text(l10n.tr('srvRulesEmpty'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
                    )
                  else ...[
                    SettingsSectionTitle(l10n.tr('srvRulesSection')),
                    SettingsGroup(children: [
                      for (final r in rules)
                        SettingsItem(
                          icon: r.inError ? AppIcons.error : AppIcons.rule,
                          color: r.enabled ? null : theme.disabledColor,
                          title: r.name.trim().isEmpty ? l10n.tr('srvRuleNoName') : r.name.trim(),
                          subtitle: [
                            _actions(r, l10n),
                            if (r.readOnly) l10n.tr('srvRuleOutlookOnly'),
                            if (r.inError) l10n.tr('srvRuleInError'),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          trailing: _saving.contains(r.id)
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : Switch(
                                  value: r.enabled,
                                  onChanged: r.readOnly ? null : (v) => _toggle(r, v),
                                ),
                          // Что делает правило, удалить (1.7.3).
                          onTap: () => unawaited(_ruleSheet(r)),
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

// ════════════════════════ Восстановить удалённые ════════════════════════

class RecoverDeletedScreen extends ConsumerStatefulWidget {
  final String? accountId;
  const RecoverDeletedScreen({super.key, this.accountId});

  @override
  ConsumerState<RecoverDeletedScreen> createState() => _RecoverDeletedScreenState();
}

class _RecoverDeletedScreenState extends ConsumerState<RecoverDeletedScreen> {
  late AccountModel? _account = _initial(ref, widget.accountId);

  /// Ящик для запросов EWS (у ActiveSync — EWS того же сервера), 1.7.3,
  /// или ящик Exchange Online для запросов Graph (1.8.10).
  AccountModel? _ews;
  ServerTools? _tools;
  bool _viaGraph = false;
  bool _noEws = false;
  List<RecoverableItem>? _items;
  final Set<String> _picked = {};
  bool _loading = false;
  bool _restoring = false;
  String? _error;
  String? _done;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final acc = _account;
    if (acc == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _noEws = false;
    });
    try {
      final via = _ews != null && _tools != null
          ? (account: _ews!, tools: _tools!, graph: _viaGraph)
          : await serverToolsFor(ref, acc);
      if (!mounted) return;
      if (via == null) {
        setState(() => _noEws = true);
        return;
      }
      final ews = _ews = via.account;
      _tools = via.tools;
      _viaGraph = via.graph;
      final items = await via.tools.getRecoverable(ews);
      if (!mounted) return;
      setState(() {
        _items = items;
        _picked.removeWhere((id) => !items.any((i) => i.id == id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore() async {
    final acc = _ews;
    final tools = _tools;
    final items = _items;
    if (acc == null || tools == null || items == null || _picked.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _restoring = true;
      _error = null;
      _done = null;
    });
    try {
      final chosen = items.where((i) => _picked.contains(i.id)).toList();
      final n = await tools.restore(acc, chosen);
      if (!mounted) return;
      setState(() {
        _done = l10n.tr('srvRestored').replaceAll('{n}', '$n');
        _picked.clear();
      });
      // Письма вернутся во «Входящие» ближайшей синхронизацией.
      unawaited(ref.read(emailsProvider.notifier).refresh());
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '${l10n.tr('error')}: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final acc = _account;
    final items = _items ?? const <RecoverableItem>[];
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('srvRecoverTitle')),
        actions: [
          IconButton(tooltip: l10n.tr('sync'), icon: const Icon(AppIcons.refresh), onPressed: _loading ? null : _load),
        ],
      )),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: FilledButton.icon(
                  icon: _restoring
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(AppIcons.restore),
                  label: Text(l10n.tr('srvRestoreN').replaceAll('{n}', '${_picked.length}')),
                  onPressed: _restoring ? null : _restore,
                ),
              ),
            ),
      body: acc == null
          ? EmptyState(icon: AppIcons.restore, title: l10n.tr('srvNoEws'), message: l10n.tr('srvNoEwsHint'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xl),
                children: [
                  if (widget.accountId == null)
                  _AccountChips(
                    accounts: ewsAccounts(ref),
                    selected: acc,
                    onSelect: (a) {
                      setState(() {
                        _account = a;
                        _ews = null;
                        _tools = null;
                        _items = null;
                        _picked.clear();
                      });
                      unawaited(_load());
                    },
                  ),
                  SettingsIntro(l10n.tr('srvRecoverIntro'), more: l10n.tr('srvRecoverMore'), moreTitle: l10n.tr('srvRecoverTitle')),
                  if (_viaGraph) _notice(context, l10n.tr('srvViaGraph'), warn: false),
                  if (_noEws) _notice(context, l10n.tr('srvRecoverNoEwsEas'), warn: false),
                  if (_error != null) _notice(context, _error!),
                  if (_done != null) _notice(context, _done!, warn: false),
                  if (_loading && _items == null)
                    const Padding(padding: EdgeInsets.all(Space.xl), child: Center(child: CircularProgressIndicator()))
                  else if (_noEws)
                    const SizedBox.shrink()
                  else if (items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Text(l10n.tr('srvRecoverEmpty'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context))),
                    )
                  else ...[
                    SettingsSectionTitle('${l10n.tr('srvRecoverSection')} · ${items.length}'),
                    SettingsGroup(children: [
                      for (final i in items)
                        CheckboxListTile(
                          value: _picked.contains(i.id),
                          onChanged: (v) => setState(() => v == true ? _picked.add(i.id) : _picked.remove(i.id)),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(i.subject.isEmpty ? l10n.tr('noSubject') : i.subject,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            [
                              if (i.from.isNotEmpty) i.from,
                              if (i.received != null) DateFormat('d MMM yyyy, HH:mm', l10n.localeCode).format(i.received!),
                              if (!i.isMail) l10n.tr('srvNotMail'),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
    );
  }
}

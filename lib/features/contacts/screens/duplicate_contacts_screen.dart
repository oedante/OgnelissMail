// lib/features/contacts/screens/duplicate_contacts_screen.dart
// Поиск и объединение дублей контактов (по нормализованному email). Слияние заполняет
// пустые поля основного контакта из дублей и удаляет остальные (локально + на сервере).

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../mail/providers/mail_providers.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class DuplicateContactsScreen extends ConsumerStatefulWidget {
  const DuplicateContactsScreen({super.key});
  @override
  ConsumerState<DuplicateContactsScreen> createState() => _DuplicateContactsScreenState();
}

class _DuplicateContactsScreenState extends ConsumerState<DuplicateContactsScreen> {
  List<List<Contact>> _groups = [];
  bool _loading = true;
  bool _busy = false;

  AppDatabase get _db => ref.read(databaseProvider);

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    setState(() => _loading = true);
    final all = await _db.select(_db.contacts).get();
    final map = <String, List<Contact>>{};
    for (final c in all) {
      final key = c.email.trim().toLowerCase();
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => []).add(c);
    }
    final groups = map.values.where((g) => g.length > 1).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (mounted) setState(() { _groups = groups; _loading = false; });
  }

  /// Выбрать основной (по числу взаимодействий, затем по заполненности).
  Contact _primaryOf(List<Contact> g) {
    int filled(Contact c) => [
          c.firstName, c.lastName, c.middleName, c.jobTitle, c.department, c.company,
          c.phoneWork, c.phoneMobile, c.office, c.city, c.notes, c.avatarUrl,
        ].where((v) => v != null && v.toString().trim().isNotEmpty).length;
    final sorted = [...g]..sort((a, b) {
        final byInter = b.interactionCount.compareTo(a.interactionCount);
        if (byInter != 0) return byInter;
        return filled(b).compareTo(filled(a));
      });
    return sorted.first;
  }

  Future<void> _mergeGroup(List<Contact> g) async {
    final primary = _primaryOf(g);
    final others = g.where((c) => c.id != primary.id).toList();

    // Заполнить пустые поля основного из дублей.
    String? pick(String? Function(Contact) f) {
      final cur = f(primary);
      if (cur != null && cur.trim().isNotEmpty) return cur;
      for (final o in others) {
        final v = f(o);
        if (v != null && v.trim().isNotEmpty) return v;
      }
      return cur;
    }

    final companion = ContactsCompanion(
      firstName: Value(pick((c) => c.firstName)),
      middleName: Value(pick((c) => c.middleName)),
      lastName: Value(pick((c) => c.lastName)),
      jobTitle: Value(pick((c) => c.jobTitle)),
      department: Value(pick((c) => c.department)),
      company: Value(pick((c) => c.company)),
      phoneWork: Value(pick((c) => c.phoneWork)),
      phoneMobile: Value(pick((c) => c.phoneMobile)),
      phoneExtension: Value(pick((c) => c.phoneExtension)),
      office: Value(pick((c) => c.office)),
      city: Value(pick((c) => c.city)),
      avatarUrl: Value(pick((c) => c.avatarUrl)),
      avatarPath: Value(pick((c) => c.avatarPath)),
      notes: Value(pick((c) => c.notes)),
      additionalEmails: Value(pick((c) => c.additionalEmails)),
      isFavorite: Value(g.any((c) => c.isFavorite)),
      isVip: Value(g.any((c) => c.isVip)),
      interactionCount: Value(g.fold<int>(0, (s, c) => s + c.interactionCount)),
    );

    // Строка — по паре (id, аккаунт): id у разных ящиков может совпадать.
    Expression<bool> same($ContactsTable c, Contact x) => x.accountId == null
        ? c.id.equals(x.id) & c.accountId.isNull()
        : c.id.equals(x.id) & c.accountId.equals(x.accountId!);
    await (_db.update(_db.contacts)..where((c) => same(c, primary))).write(companion);

    // Удалить дубли (локально + на сервере их собственного аккаунта; раньше
    // удаление уходило в активный аккаунт, даже если дубль был из другого).
    final accounts = ref.read(accountsProvider);
    for (final o in others) {
      await (_db.delete(_db.contacts)..where((c) => same(c, o))).go();
      final account = accounts.where((a) => a.id == o.accountId).firstOrNull;
      if (account != null && !o.id.startsWith('local_')) {
        try { await ref.read(mailEngineServiceProvider).deleteContactEntry(account, o.id); } catch (_) {}
      }
    }
  }

  Future<void> _mergeOne(List<Contact> g) async {
    setState(() => _busy = true);
    await _mergeGroup(g);
    await _find();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _mergeAll(AppLocalizations l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('mergeAll')),
        content: Text(l10n.tr('mergeAllConfirm').replaceAll('{n}', '${_groups.length}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('merge'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    for (final g in [..._groups]) {
      await _mergeGroup(g);
    }
    await _find();
    if (mounted) {
      setState(() => _busy = false);
      showInlineNotice(l10n.tr('duplicatesMerged'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('duplicateContacts')),
        actions: [
          if (_groups.isNotEmpty && !_busy)
            TextButton(
              onPressed: () => _mergeAll(l10n),
              child: Text(l10n.tr('mergeAll')),
            ),
        ],
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.done_all, size: 48, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: Space.m),
                      Text(l10n.tr('noDuplicatesFound'),
                          style: TextStyle(color: AppColors.mutedText(context))),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    ListView.builder(
                      itemCount: _groups.length,
                      itemBuilder: (ctx, i) {
                        final g = _groups[i];
                        final primary = _primaryOf(g);
                        return Card(
                          margin: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, 0),
                          child: Padding(
                            padding: const EdgeInsets.all(Space.m),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(primary.email,
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                    ),
                                    Text('${g.length}×', style: TextStyle(color: theme.colorScheme.primary)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ...g.map((c) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Icon(c.id == primary.id ? AppIcons.star : AppIcons.person,
                                              size: 16,
                                              color: c.id == primary.id ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                                          const SizedBox(width: 6),
                                          Expanded(child: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                          if ((c.phoneMobile ?? c.phoneWork ?? '').isNotEmpty)
                                            Text(c.phoneMobile ?? c.phoneWork ?? '',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                                        ],
                                      ),
                                    )),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _busy ? null : () => _mergeOne(g),
                                    icon: const Icon(AppIcons.merge, size: 18),
                                    label: Text(l10n.tr('merge')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: Space.xs, child: _busy ? const LinearProgressIndicator() : null),
                  ],
                ),
    );
  }
}

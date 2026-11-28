// lib/features/mail/widgets/categories_sheet.dart
// «Категории» письма (2.7.5, замечание владельца 27.11.2026: «тэги и
// категории — одно и то же, и не реализованы категории по цветам»).
//
// Одна кнопка вместо «Добавить тег» и «Категории Outlook». У ящиков Exchange
// категории уходят на сервер (видны в Outlook и веб-почте), у остальных —
// хранятся на телефоне. У каждой категории — цвет: стандартные категории
// Outlook («Красная категория»…) — своим цветом, остальные — постоянным
// цветом палитры; цвет можно выбрать (кружок слева).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/email_actions_service.dart' show emailActionsProvider;
import '../../../widgets/common/app_sheet.dart';
import '../../settings/providers/categories_provider.dart';
import '../providers/mail_providers.dart' show accountsProvider;

/// Категории письма: категории Exchange и прежние теги (без повторов).
List<String> mailCategoriesOf(EmailModel e) => [
      ...e.categories,
      for (final t in e.tags)
        if (!e.categories.contains(t)) t,
    ];

/// Записать категории письма: у Exchange — на сервер (прежние теги
/// переходят в категории), у остальных — теги на телефоне. Возвращает
/// записанный список.
Future<void> saveMailCategories(WidgetRef ref, EmailModel email, List<String> names) async {
  final actions = ref.read(emailActionsProvider);
  final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
  if (acc != null && acc.isMsExchange) {
    await actions.setCategories(acc, email.id, names);
    if (email.tags.isNotEmpty) await actions.setTags(email.id, const [], accountId: email.accountId);
  } else {
    await actions.setTags(email.id, names, accountId: email.accountId);
  }
}

/// Окно «Категории»: отметить категории письма, добавить новую, выбрать
/// цвет. null — закрыли без изменений; иначе — новый список.
Future<List<String>?> showCategoriesSheet(BuildContext context, WidgetRef ref, EmailModel email) async {
  final l10n = AppLocalizations.of(context);
  final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
  final exchange = acc?.isMsExchange ?? false;
  final current = mailCategoriesOf(email);
  final selected = {...current};
  final names = <String>[
    ...ref.read(categoriesProvider),
    for (final c in current)
      if (!ref.read(categoriesProvider).contains(c)) c,
  ];
  final input = TextEditingController();
  final result = await showAppSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final colors = ref.watch(categoryColorsProvider);
      return StatefulBuilder(builder: (ctx, setSheet) {
        void add() {
          final t = input.text.trim();
          if (t.isEmpty) return;
          unawaited(ref.read(categoriesProvider.notifier).add(t));
          setSheet(() {
            if (!names.contains(t)) names.add(t);
            selected.add(t);
            input.clear();
          });
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                title: Text(l10n.tr('categoriesTitle'), style: Theme.of(ctx).textTheme.titleMedium),
                subtitle: Text(l10n.tr(exchange ? 'outlookCategoriesSynced' : 'categoriesLocalHint')),
                trailing: FilledButton(
                  key: const ValueKey('categories_done'),
                  onPressed: () => Navigator.pop(ctx, [for (final n in names) if (selected.contains(n)) n]),
                  child: Text(l10n.tr('done')),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final n in names)
                    CheckboxListTile(
                      key: ValueKey('category_$n'),
                      value: selected.contains(n),
                      onChanged: (v) => setSheet(() => v == true ? selected.add(n) : selected.remove(n)),
                      title: Text(n),
                      secondary: IconButton(
                        key: ValueKey('category_color_$n'),
                        tooltip: l10n.tr('categoryColor'),
                        icon: Icon(AppIcons.label, fill: 1, color: categoryColor(n, colors)),
                        onPressed: () => unawaited(_pickColor(ctx, ref, n, l10n)),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.m),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('category_new'),
                      controller: input,
                      decoration: InputDecoration(isDense: true, hintText: l10n.tr('customCategory')),
                      onSubmitted: (_) => add(),
                    ),
                  ),
                  IconButton(tooltip: l10n.tr('add'), icon: const Icon(AppIcons.add), onPressed: add),
                ]),
              ),
            ]),
          ),
        );
      });
    }),
  );
  input.dispose();
  if (result == null) return null;
  if (result.length == current.length && result.every(current.contains)) return null;
  unawaited(HapticFeedback.selectionClick());
  await saveMailCategories(ref, email, result);
  return result;
}

/// Цвет категории — кружки палитры.
Future<void> _pickColor(BuildContext context, WidgetRef ref, String name, AppLocalizations l10n) async {
  final picked = await showAppSheet<Color>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${l10n.tr('categoryColor')} · $name', style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.m, runSpacing: Space.m, children: [
            for (final c in categoryPalette)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(ctx, c),
                child: CircleAvatar(radius: 20, backgroundColor: c),
              ),
          ]),
        ]),
      ),
    ),
  );
  if (picked != null) await ref.read(categoryColorsProvider.notifier).set(name, picked);
}

/// Метка категории: название её цветом на светлой подложке.
class CategoryChip extends ConsumerWidget {
  final String name;
  const CategoryChip(this.name, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = categoryColor(name, ref.watch(categoryColorsProvider));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Text(name,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: color)),
    );
  }
}

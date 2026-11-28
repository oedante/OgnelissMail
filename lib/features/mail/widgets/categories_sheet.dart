// lib/features/mail/widgets/categories_sheet.dart
// «Категории» письма (2.7.5, замечание владельца 27.11.2026: «тэги и
// категории — одно и то же, и не реализованы категории по цветам»).
//
// Одна кнопка вместо «Добавить тег» и «Категории Outlook». У ящиков Exchange
// категории уходят на сервер (видны в Outlook и веб-почте), у остальных —
// хранятся на телефоне. У каждой категории — цвет: стандартные категории
// Outlook («Красная категория»…) — своим цветом, категории из Outlook — его
// цветом, остальные — постоянным цветом палитры; цвет можно выбрать
// (кружок слева). Окно умеет и несколько писем сразу (выделение в ленте).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/category_colors.dart';
import '../../../data/models/email_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/models/account_model.dart';
import '../../../services/mail/email_actions_service.dart' show EmailActionsService, emailActionsProvider;
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
/// переходят в категории), у остальных — теги на телефоне.
Future<void> saveMailCategories(WidgetRef ref, EmailModel email, List<String> names) =>
    saveMailCategoriesWith(ref.read(emailActionsProvider),
        ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull, email, names);

/// То же без ref — для массовой записи в фоне (экран мог уже закрыться).
Future<void> saveMailCategoriesWith(
    EmailActionsService actions, AccountModel? acc, EmailModel email, List<String> names) async {
  if (acc != null && acc.isMsExchange) {
    await actions.setCategories(acc, email.id, names);
    if (email.tags.isNotEmpty) await actions.setTags(email.id, const [], accountId: email.accountId);
  } else {
    await actions.setTags(email.id, names, accountId: email.accountId);
  }
}

/// Изменения категорий: true — поставить, false — снять; категорий, которых
/// нет в карте, изменение не касается.
typedef CategoryChanges = Map<String, bool>;

/// Применить изменения к категориям одного письма (порядок прежних
/// сохраняется, новые — в конец).
List<String> applyCategoryChanges(List<String> current, CategoryChanges changes) {
  final out = [for (final c in current) if (changes[c] != false) c];
  for (final e in changes.entries) {
    if (e.value && !out.contains(e.key)) out.add(e.key);
  }
  return out;
}

/// Окно «Категории»: отметить категории письма, добавить новую, выбрать
/// цвет. null — закрыли без изменений; иначе — новый список.
Future<List<String>?> showCategoriesSheet(BuildContext context, WidgetRef ref, EmailModel email) async {
  final changes = await pickCategoryChanges(context, ref, [email]);
  if (changes == null) return null;
  final current = mailCategoriesOf(email);
  final result = applyCategoryChanges(current, changes);
  if (result.length == current.length && result.every(current.contains)) return null;
  unawaited(HapticFeedback.selectionClick());
  await saveMailCategories(ref, email, result);
  return result;
}

/// Окно «Категории» для одного или нескольких писем (2.7.5, выделение в
/// ленте). Категория, которая есть у части писем, отмечена чертой: её можно
/// поставить всем, снять у всех или оставить как есть. Возвращает изменения
/// (пусто — ничего не меняли); null — окно закрыли.
Future<CategoryChanges?> pickCategoryChanges(BuildContext context, WidgetRef ref, List<EmailModel> emails) async {
  if (emails.isEmpty) return null;
  final l10n = AppLocalizations.of(context);
  final accounts = {for (final a in ref.read(accountsProvider)) a.id: a};
  final exchange = [for (final e in emails) accounts[e.accountId]?.isMsExchange ?? false];
  final anyExchange = exchange.contains(true);
  final hint = !anyExchange
      ? 'categoriesLocalHint'
      : exchange.contains(false)
          ? 'categoriesMixedHint'
          : 'outlookCategoriesSynced';
  final own = mailCategoriesOrder(emails);
  final userList = ref.read(categoriesProvider);
  final names = <String>[
    ...userList,
    // Категории Outlook ящика — у писем Exchange.
    if (anyExchange)
      for (final c in CategoryColors.serverList)
        if (!userList.contains(c.name)) c.name,
  ];
  for (final c in own) {
    if (!names.contains(c)) names.add(c);
  }
  // Сколько писем с категорией: у всех — true, ни у одного — false, у части — null.
  final initial = <String, bool?>{
    for (final n in names)
      n: switch (emails.where((e) => mailCategoriesOf(e).contains(n)).length) {
        0 => false,
        final k when k == emails.length => true,
        _ => null,
      },
  };
  final state = {...initial};
  final input = TextEditingController();
  final result = await showAppSheet<CategoryChanges>(
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
            initial.putIfAbsent(t, () => false);
            state[t] = true;
            input.clear();
          });
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                title: Text(
                    emails.length == 1
                        ? l10n.tr('categoriesTitle')
                        : '${l10n.tr('categoriesTitle')} · ${l10n.tr('selectedMailsN').replaceAll('{n}', '${emails.length}')}',
                    style: Theme.of(ctx).textTheme.titleMedium),
                subtitle: Text(l10n.tr(hint)),
                trailing: FilledButton(
                  key: const ValueKey('categories_done'),
                  onPressed: () => Navigator.pop(ctx, {
                    for (final n in names)
                      if (state[n] != null && state[n] != initial[n]) n: state[n]!,
                  }),
                  child: Text(l10n.tr('done')),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final n in names)
                    CheckboxListTile(
                      key: ValueKey('category_$n'),
                      // Черта — у части писем; касание: всем → ни у кого → как было.
                      tristate: initial[n] == null,
                      value: state[n],
                      onChanged: (_) => setSheet(() => state[n] = switch (state[n]) {
                            null => true,
                            true => false,
                            false => initial[n] == null ? null : true,
                          }),
                      title: Text(n),
                      secondary: IconButton(
                        key: ValueKey('category_color_$n'),
                        tooltip: l10n.tr('categoryColor'),
                        icon: Icon(AppIcons.label, fill: 1, color: categoryColor(n, colors)),
                        onPressed: () => unawaited(pickCategoryColor(ctx, ref, n)),
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
  return result;
}

/// Категории писем по порядку первого появления (без повторов).
List<String> mailCategoriesOrder(Iterable<EmailModel> emails) {
  final out = <String>[];
  for (final e in emails) {
    for (final c in mailCategoriesOf(e)) {
      if (!out.contains(c)) out.add(c);
    }
  }
  return out;
}

/// Цвет категории — кружки палитры и «как в Outlook» (свой цвет снять).
Future<void> pickCategoryColor(BuildContext context, WidgetRef ref, String name) async {
  final l10n = AppLocalizations.of(context);
  final chosen = ref.read(categoryColorsProvider);
  final own = chosen[name];
  final byDefault = categoryColor(name, const {});
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
                key: ValueKey('category_palette_${c.toARGB32()}'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(ctx, c),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: c,
                  child: own == c.toARGB32() ? const Icon(AppIcons.check, color: Colors.white, size: 20) : null,
                ),
              ),
          ]),
          if (own != null) ...[
            const SizedBox(height: Space.m),
            TextButton.icon(
              key: const ValueKey('category_color_default'),
              onPressed: () => Navigator.pop(ctx, Colors.transparent),
              icon: Icon(AppIcons.label, fill: 1, color: byDefault),
              label: Text(l10n.tr('categoryColorDefault')),
            ),
          ],
        ]),
      ),
    ),
  );
  if (picked == null) return;
  final notifier = ref.read(categoryColorsProvider.notifier);
  if (picked == Colors.transparent) {
    await notifier.clear(name);
  } else {
    await notifier.set(name, picked);
  }
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

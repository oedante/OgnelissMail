// lib/features/compose/widgets/people_picker_sheet.dart
// Выбор людей: поиск по своим контактам и адресной книге организации
// (Exchange), ввод адреса вручную, «Моё подразделение». Используется при
// добавлении участников встречи — раньше там было голое поле «e-mail»
// без поиска, и коллегу приходилось помнить по адресу.

import '../../../core/utils/text_safe.dart';
import 'dart:async';
import '../../../core/theme/app_icons.dart';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import '../../../widgets/common/app_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/person_names.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/contacts/person_name_directory.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../widgets/common/person_photo.dart';
import '../providers/distribution_groups_provider.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;
import '../../contacts/person_names.dart' show normalizePersonName;

/// Открыть выбор людей. Возвращает выбранных (может быть пусто).
Future<List<ContactModel>> showPeoplePicker(
  BuildContext context, {
  required AccountModel? account,
  Set<String> exclude = const {},
}) async {
  final res = await showAppSheet<List<ContactModel>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PeoplePicker(account: account, exclude: exclude),
  );
  return res ?? const [];
}

/// Подбор адресатов строки «Кому/Копия/Скрытая» (по нажатию на её значок):
/// уже добавленные — сверху, их можно убрать; поиск по контактам и адресной
/// книге организации, сохранённые группы, «Моё подразделение». Возвращает
/// новый список адресатов строки; null — окно закрыли без изменений.
Future<List<ContactModel>?> editRecipientsSheet(
  BuildContext context, {
  required AccountModel? account,
  required String title,
  required List<ContactModel> current,
}) {
  return showAppSheet<List<ContactModel>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PeoplePicker(account: account, exclude: const {}, initial: current, title: title),
  );
}

class _PeoplePicker extends ConsumerStatefulWidget {
  final AccountModel? account;
  final Set<String> exclude;
  /// Режим правки строки адресатов: уже выбранные и заголовок окна.
  final List<ContactModel>? initial;
  final String? title;
  const _PeoplePicker({required this.account, required this.exclude, this.initial, this.title});

  @override
  ConsumerState<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends ConsumerState<_PeoplePicker> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  /// Клавиатура — после того, как шторка выехала (1.6.19). С autofocus она
  /// открывалась одновременно со шторкой: каждый кадр менялась высота окна,
  /// перестраивались шторка и экран письма под ней (вместе с редактором в
  /// WebView), и шторка выезжала рывками.
  Animation<double>? _routeAnim;
  bool _focusAsked = false;

  void _focusWhenShown(AnimationStatus st) {
    if (st != AnimationStatus.completed) return;
    _routeAnim?.removeStatusListener(_focusWhenShown);
    _routeAnim = null;
    if (mounted && !_focus.hasFocus) _focus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusAsked) return;
    _focusAsked = true;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } else {
      _routeAnim = anim..addStatusListener(_focusWhenShown);
    }
  }
  Timer? _debounce;
  int _seq = 0;
  bool _searching = false;
  List<ContactModel> _results = const [];
  final Map<String, ContactModel> _picked = {};

  /// Полные ФИО по адресу (1.6.4): адресная книга Exchange отдаёт
  /// «Смирнов, Андрей», а в письмах и контактах тот же человек записан
  /// полностью. Найденное показывается в списке и уходит в выбранных.
  final Map<String, String> _fullNames = {};
  final Set<String> _nameAsked = {};

  bool get _editMode => widget.initial != null;

  String _nameOf(ContactModel c) {
    final full = _fullNames[c.email.trim().toLowerCase()];
    if (full != null) return full;
    // «Смирнов, Андрей» → «Смирнов Андрей», пока полное ФИО не найдено.
    return c.displayName.isNotEmpty ? normalizePersonName(c.displayName) : c.email;
  }

  /// Тот же человек с найденным ФИО.
  ContactModel _withFullName(ContactModel c) {
    final found = _fullNames[c.email.trim().toLowerCase()];
    // Без найденного ФИО — имя без запятой («Смирнов, Андрей» → «Смирнов Андрей»).
    final full = found ?? (c.displayName.contains(',') ? normalizePersonName(c.displayName) : null);
    if (full == null || c.isGroup) return c;
    return ContactModel(
      id: c.id, accountId: c.accountId, email: c.email, additionalEmails: c.additionalEmails,
      displayName: full, firstName: c.firstName, lastName: c.lastName, middleName: c.middleName,
      jobTitle: c.jobTitle, department: c.department, company: c.company,
      phoneWork: c.phoneWork, phoneMobile: c.phoneMobile, phoneExtension: c.phoneExtension,
      office: c.office, manager: c.manager, city: c.city, avatarPath: c.avatarPath, avatarUrl: c.avatarUrl,
      source: c.source, isFavorite: c.isFavorite, isVip: c.isVip,
      interactionCount: c.interactionCount, lastInteraction: c.lastInteraction,
      notes: c.notes, birthday: c.birthday, isGroup: c.isGroup,
    );
  }

  /// Дозапросить полные ФИО для первых строк списка (контакты, письма,
  /// адресная книга — [PersonNameDirectory], результат кэшируется).
  void _resolveNames(Iterable<ContactModel> list) {
    var n = 0;
    for (final c in list) {
      if (n >= 12) break;
      if (c.isGroup) continue;
      final key = c.email.trim().toLowerCase();
      if (key.isEmpty || _nameAsked.contains(key)) continue;
      final dn = c.displayName;
      if (PersonNames.words(dn) >= 3 && !dn.contains(',')) continue;
      _nameAsked.add(key);
      n++;
      unawaited(ref.read(personNameDirectoryProvider).fullName(c.email, account: widget.account).then((full) {
        if (!mounted || full == null || !PersonNames.better(dn, full)) return;
        setState(() => _fullNames[key] = full);
      }, onError: (Object _) {}));
    }
  }

  @override
  void initState() {
    super.initState();
    for (final c in widget.initial ?? const <ContactModel>[]) {
      _picked[c.email.toLowerCase()] = c;
    }
    _resolveNames(_picked.values);
  }

  @override
  void dispose() {
    _routeAnim?.removeStatusListener(_focusWhenShown);
    _debounce?.cancel();
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    _deptMode = false;
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    final out = <ContactModel>[];
    final seen = <String>{...widget.exclude};
    void add(Iterable<ContactModel> list) {
      for (final c in list) {
        final k = c.email.trim().toLowerCase();
        if (k.isEmpty || !seen.add(k)) continue;
        out.add(c);
      }
    }

    // Свои контакты: несколько написаний (SQLite не сравнивает кириллицу
    // без учёта регистра).
    try {
      final db = ref.read(databaseProvider);
      final lower = q.toLowerCase();
      final cap = lower[0].toUpperCase() + lower.substring(1);
      final variants = {q, lower, cap, q.toUpperCase()}.toList();
      final cond = List.filled(variants.length, 'display_name LIKE ?').join(' OR ');
      final rows = await db.customSelect(
        'SELECT id, email, display_name, job_title, company, avatar_url FROM contacts '
        'WHERE lower(email) LIKE ? OR $cond '
        'ORDER BY interaction_count DESC, display_name LIMIT 15',
        variables: [
          Variable.withString('%$lower%'),
          for (final v in variants) Variable.withString('%$v%'),
        ],
      ).get();
      add(rows.map((r) => ContactModel(
            id: r.read<String>('id'),
            email: r.read<String>('email'),
            displayName: r.read<String>('display_name'),
            jobTitle: r.readNullable<String>('job_title'),
            company: r.readNullable<String>('company'),
            avatarUrl: r.readNullable<String>('avatar_url'),
          )));
    } catch (_) {}
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = List.of(out);
      _searching = widget.account?.isMsExchange ?? false;
    });
    _resolveNames(out);

    // Адресная книга организации — не дольше 15 с.
    final acc = widget.account;
    if (acc == null || !acc.isMsExchange) return;
    try {
      final gal = await ref
          .read(mailEngineServiceProvider)
          .resolveNames(acc, q)
          .timeout(const Duration(seconds: 15));
      if (!mounted || seq != _seq) return;
      add(gal);
      setState(() => _results = List.of(out));
      _resolveNames(out);
    } catch (_) {
    } finally {
      if (mounted && seq == _seq) setState(() => _searching = false);
    }
  }

  void _toggle(ContactModel c) {
    final k = c.email.toLowerCase();
    setState(() {
      if (_picked.remove(k) == null) _picked[k] = c;
    });
  }

  /// В списке — результат «Моё подразделение»: показываем и кабинет.
  bool _deptMode = false;

  Future<void> _department() async {
    final acc = widget.account;
    if (acc == null) return;
    setState(() => _searching = true);
    try {
      final r = await ref.read(mailEngineServiceProvider).departmentColleagues(acc);
      if (!mounted) return;
      if (r.people.isEmpty) {
        showInlineNotice(AppLocalizations.of(context).tr('myDepartmentNone'));
        return;
      }
      // Отмечены сразу — коллеги с тем же полем «Офис», что у вас; остальные
      // из того же здания/подразделения («РММ…») — в списке без отметки
      // (1.6.26: адресная книга ActiveSync не знает поля «Отдел»).
      setState(() {
        _deptMode = true;
        _results = r.people.where((p) => !widget.exclude.contains(p.email.toLowerCase())).toList();
        for (final p in _results) {
          if (r.near.contains(p.email.toLowerCase())) _picked[p.email.toLowerCase()] = p;
        }
      });
      _resolveNames(_results);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typed = _ctrl.text.trim();
    final typedIsEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(typed);
    final photos = ref.watch(personPhotosProvider).value ?? const <String, String>{};

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (ctx, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(AppIcons.search),
                hintText: l10n.tr('attendeeEmailHint'),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(Space.m),
                        child: SizedBox(width: Space.l, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                _onChanged(v);
              },
            ),
          ),
          Row(
            children: [
              if (widget.account?.isMsExchange ?? false)
                TextButton.icon(
                  onPressed: _department,
                  icon: const Icon(AppIcons.apartment, size: 18),
                  label: Text(l10n.tr('myDepartment')),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: Space.l),
                child: FilledButton(
                  onPressed: (_picked.isEmpty && !_editMode)
                      ? null
                      : () => Navigator.pop(context, _picked.values.map(_withFullName).toList()),
                  child: Text((_editMode ? l10n.tr('doneN') : l10n.tr('addSelectedN'))
                      .replaceAll('{n}', '${_picked.length}')),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                if (widget.title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                    child: Text(widget.title!, style: theme.textTheme.titleMedium),
                  ),
                // Уже выбранные — плашками с крестиком (убрать из строки).
                if (_picked.isNotEmpty && typed.length < 2)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                    child: Wrap(
                      spacing: Space.xs,
                      runSpacing: Space.xs,
                      children: [
                        for (final c in _picked.values)
                          InputChip(
                            avatar: PhotoRing(
                              width: 1,
                              child: CircleAvatar(
                                foregroundImage: photoImage(c.avatarUrl ?? photos[c.email.toLowerCase()]),
                                child: c.isGroup
                                    ? const Icon(AppIcons.groups, size: 14)
                                    : Text(initialOf(_nameOf(c)), style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                            label: Text(_nameOf(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                            tooltip: c.email,
                            onDeleted: () => setState(() => _picked.remove(c.email.toLowerCase())),
                          ),
                      ],
                    ),
                  ),
                // Сохранённые группы получателей: все при пустом поиске,
                // подходящие по имени — при наборе. Нажатие добавляет участников.
                for (final g in ref.watch(distributionGroupsProvider))
                  if (typed.length < 2 || g.name.toLowerCase().contains(typed.toLowerCase()))
                    ListTile(
                      leading: const CircleAvatar(child: Icon(AppIcons.groups, size: 18)),
                      title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(l10n.tr('groupMembersN').replaceAll('{n}', '${g.members.length}'),
                          style: theme.textTheme.bodySmall),
                      trailing: const Icon(AppIcons.add_circle),
                      onTap: () => setState(() {
                        for (final m in g.members) {
                          _picked[m.email.toLowerCase()] = ContactModel(
                              id: 'grp:${m.email}', email: m.email, displayName: m.name ?? m.email);
                        }
                      }),
                    ),
                // Адрес набран целиком и не найден — добавить как есть.
                if (typedIsEmail && !_results.any((c) => c.email.toLowerCase() == typed.toLowerCase()))
                  ListTile(
                    leading: const CircleAvatar(child: Icon(AppIcons.alternate_email, size: 18)),
                    title: Text(typed),
                    trailing: Icon(_picked.containsKey(typed.toLowerCase())
                        ? AppIcons.check_circle
                        : AppIcons.add_circle),
                    onTap: () => _toggle(ContactModel(id: 'typed', email: typed, displayName: typed)),
                  ),
                for (final c in _results)
                  CheckboxListTile(
                    value: _picked.containsKey(c.email.toLowerCase()),
                    onChanged: (_) => _toggle(c),
                    secondary: PhotoRing(child: CircleAvatar(
                      foregroundImage: photoImage(c.avatarUrl ?? photos[c.email.toLowerCase()]),
                      child: c.isGroup
                          ? const Icon(AppIcons.groups, size: 18)
                          : Text(initialOf(_nameOf(c))),
                    )),
                    title: Text(_nameOf(c), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      c.isGroup
                          ? '${l10n.tr('groupMailingList')} · ${c.email}'
                          : [c.email, c.jobTitle, if (_deptMode) c.office]
                              .where((x) => x != null && x.isNotEmpty)
                              .join(' · '),
                      maxLines: _deptMode ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (_results.isEmpty && !_searching && typed.length >= 2 && !typedIsEmail)
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Text(l10n.tr('recipientSearchNone'), style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

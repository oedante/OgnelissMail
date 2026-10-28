// lib/features/contacts/widgets/contact_editor.dart
// Создание и правка контакта — полноэкранная форма вместо диалога из четырёх
// полей. Видно, КУДА сохраняется контакт: в адресную книгу ящика на сервере
// (Exchange, Google, Яндекс, Yahoo — появится на других устройствах) или
// только на этом телефоне. Раньше это было непонятно (замечание 08.10.2026).
//
// 1.6.49 (замечание 19.10.2026: «в контактах нет многих данных — отдел,
// отчество, руководитель»): поля «Руководитель» и «Кабинет»; если в адресной
// книге организации (или в имени из писем) есть то, чего нет в контакте, —
// строка «В адресной книге организации есть: …» и кнопка «Заполнить».
// Заполненное сохраняется в контакт и уходит на сервер вместе с правкой.
//
// 1.7.2+106 (замечание 24.10.2026: «очень серые, поля сливаются с фоном, нет
// группировки»): поля — строками в белых карточках по группам («Где
// хранится», «ФИО», «Связь», «Работа», «Заметка») с серыми полосами
// разделов, как в настройках; у ФИО значков нет — все три поля с одной линии.

import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart';
import '../person_names.dart' show personNamesProvider;

/// Открыть форму. [existing] — правка, иначе — новый контакт ([email] и
/// [name] — подстановка, например из карточки человека).
Future<bool?> showContactEditor(BuildContext context,
    {Contact? existing, String? email, String? name}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ContactEditorScreen(existing: existing, email: email, name: name),
  ));
}

class ContactEditorScreen extends ConsumerStatefulWidget {
  final Contact? existing;
  final String? email;
  final String? name;
  const ContactEditorScreen({super.key, this.existing, this.email, this.name});

  @override
  ConsumerState<ContactEditorScreen> createState() => _ContactEditorScreenState();
}

/// «Только на этом телефоне» в списке мест хранения.
const _localTarget = '__local__';

class _ContactEditorScreenState extends ConsumerState<ContactEditorScreen> {
  late final _last = TextEditingController(text: widget.existing?.lastName ?? '');
  late final _first = TextEditingController(text: widget.existing?.firstName ?? '');
  late final _middle = TextEditingController(text: widget.existing?.middleName ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? widget.email ?? '');
  late final _mobile = TextEditingController(text: widget.existing?.phoneMobile ?? '');
  late final _work = TextEditingController(text: widget.existing?.phoneWork ?? '');
  late final _company = TextEditingController(text: widget.existing?.company ?? '');
  late final _department = TextEditingController(text: widget.existing?.department ?? '');
  late final _title = TextEditingController(text: widget.existing?.jobTitle ?? '');
  late final _manager = TextEditingController(text: widget.existing?.manager ?? '');
  late final _office = TextEditingController(text: widget.existing?.office ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');

  /// Данные из адресной книги организации (null — нет или ещё не пришли).
  ContactModel? _dir;

  String _target = _localTarget;
  bool _saving = false;
  String? _error;
  String? _nameError;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    // Правка контакта без раздельных полей ФИО — раскладываем отображаемое
    // имя: «Фамилия Имя Отчество».
    if (e != null && (e.firstName ?? '').isEmpty && (e.lastName ?? '').isEmpty) {
      _splitInto(e.displayName);
    }
    if (_isNew && (widget.name ?? '').trim().isNotEmpty) _splitInto(widget.name!);
    if (_isNew) {
      // По умолчанию — адресная книга активного ящика, если она доступна.
      final active = ref.read(activeAccountProvider);
      if (active != null && _writable(active)) _target = active.id;
    }
    unawaited(_loadDirectory());
  }

  /// Карточка человека из адресной книги организации (ActiveSync и EWS) —
  /// чтобы предложить недостающие поля.
  Future<void> _loadDirectory() async {
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@')) return;
    final accounts = ref
        .read(accountsProvider)
        .where((a) => a.isActive && a.authFailedAt == null && (a.usesEas || a.hasEwsExtras || a.isExchange))
        .toList();
    if (accounts.isEmpty) return;
    final domain = email.split('@').last;
    final acc = accounts.where((a) => a.id == widget.existing?.accountId).firstOrNull ??
        accounts.where((a) => a.email.toLowerCase().endsWith('@$domain')).firstOrNull ??
        accounts.first;
    ContactModel? p;
    try {
      p = await ref.read(mailEngineServiceProvider).lookupPerson(acc, email);
    } catch (_) {}
    if (!mounted || p == null) return;
    setState(() => _dir = p);
  }

  /// Что можно дополнить: поле формы, значение, подпись. Отчество — и из
  /// полного имени человека в письмах («Фамилия Имя Отчество»).
  List<(TextEditingController, String, String)> _fillable(AppLocalizations l10n) {
    final p = _dir;
    final out = <(TextEditingController, String, String)>[];
    void add(TextEditingController c, String? v, String label) {
      final t = (v ?? '').trim();
      if (t.isNotEmpty && c.text.trim().isEmpty && !out.any((x) => identical(x.$1, c))) out.add((c, t, label));
    }

    if (p != null) {
      add(_last, p.lastName, l10n.tr('lastName'));
      add(_first, p.firstName, l10n.tr('firstName'));
      add(_middle, p.middleName, l10n.tr('middleName'));
    }
    final known = ref.watch(personNamesProvider).value?[_email.text.trim().toLowerCase()];
    add(_middle, MailEngineService.middleFromDisplay(known, _v(_first), _v(_last)), l10n.tr('middleName'));
    if (p != null) {
      add(_mobile, p.phoneMobile, l10n.tr('phoneMobile'));
      add(_work, p.phoneWork, l10n.tr('phoneWork'));
      add(_company, p.company, l10n.tr('company'));
      add(_department, p.department, l10n.tr('department'));
      add(_title, p.jobTitle, l10n.tr('jobTitle'));
      add(_manager, p.manager, l10n.tr('manager'));
      add(_office, p.office, l10n.tr('officeLocation'));
    }
    return out;
  }

  void _splitInto(String display) {
    final parts = display.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.first.contains('@')) return;
    if (parts.length == 1) {
      _first.text = parts[0];
    } else {
      _last.text = parts[0];
      _first.text = parts[1];
      if (parts.length > 2) _middle.text = parts.sublist(2).join(' ');
    }
  }

  bool _writable(AccountModel a) => ref.read(mailEngineServiceProvider).canWriteContacts(a);

  @override
  void dispose() {
    for (final c in [_last, _first, _middle, _email, _mobile, _work, _company, _department, _title, _manager, _office, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  ContactModel _model(String id, String? accountId) {
    final display = [_v(_last), _v(_first), _v(_middle)].whereType<String>().join(' ');
    return ContactModel(
      id: id,
      accountId: accountId,
      email: _email.text.trim(),
      displayName: display.isNotEmpty ? display : _email.text.trim(),
      firstName: _v(_first),
      lastName: _v(_last),
      middleName: _v(_middle),
      company: _v(_company),
      department: _v(_department),
      jobTitle: _v(_title),
      manager: _v(_manager),
      office: _v(_office),
      phoneWork: _v(_work),
      phoneMobile: _v(_mobile),
      notes: _v(_notes),
      source: ContactSource.personal,
    );
  }

  ContactsCompanion _row(ContactModel c) => ContactsCompanion(
        id: Value(c.id),
        accountId: Value(c.accountId),
        email: Value(c.email),
        displayName: Value(c.displayName),
        firstName: Value(c.firstName),
        lastName: Value(c.lastName),
        middleName: Value(c.middleName),
        company: Value(c.company),
        department: Value(c.department),
        jobTitle: Value(c.jobTitle),
        manager: Value(c.manager),
        office: Value(c.office),
        phoneWork: Value(c.phoneWork),
        phoneMobile: Value(c.phoneMobile),
        notes: Value(c.notes),
        source: Value(c.source.index),
      );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final hasName = [_last, _first, _middle].any((c) => c.text.trim().isNotEmpty);
    if (!hasName && _email.text.trim().isEmpty) {
      setState(() => _nameError = l10n.tr('contactNameOrEmail'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final db = ref.read(databaseProvider);
    final engine = ref.read(mailEngineServiceProvider);
    try {
      if (_isNew) {
        final account = _target == _localTarget
            ? null
            : ref.read(accountsProvider).where((a) => a.id == _target).firstOrNull;
        var model = _model('local_${DateTime.now().millisecondsSinceEpoch}', account?.id);
        if (account != null) {
          // Id, выданный сервером, становится локальным: иначе синхронизация
          // принесла бы тот же контакт второй раз.
          String? serverId;
          try {
            if (account.usesEas) {
              final sid = await engine.createOrUpdateContact(account, model);
              if (sid != null && sid.isNotEmpty) serverId = 'eas_$sid';
            } else {
              serverId = await engine.createContactEntry(account, model);
            }
          } catch (e) {
            AppLogger.warning('Контакт на сервер: $e');
          }
          if (serverId == null || serverId.isEmpty) {
            // Сервер не принял — не молчим: предлагаем сохранить на телефоне.
            if (!mounted) return;
            setState(() {
              _saving = false;
              _error = l10n.tr('contactServerFailed');
            });
            return;
          }
          model = _model(serverId, account.id);
        }
        await db.into(db.contacts).insert(_row(model), mode: InsertMode.insertOrReplace);
      } else {
        final old = widget.existing!;
        final model = _model(old.id, old.accountId);
        await (db.update(db.contacts)
              ..where((c) => c.id.equals(old.id) &
                  (old.accountId == null ? c.accountId.isNull() : c.accountId.equals(old.accountId!))))
            .write(_row(model).copyWith(id: const Value.absent(), accountId: const Value.absent()));
        final account = ref.read(accountsProvider).where((a) => a.id == old.accountId).firstOrNull;
        if (account != null && _writable(account)) {
          try {
            // Выгружается вся строка — поля, которых нет в форме, сохраняются.
            await engine.pushContact(account, old.id);
          } catch (e) {
            // Офлайн — в очередь: иначе синхронизация вернула бы старую версию.
            AppLogger.warning('Правка контакта — в очередь: $e');
            await ref.read(syncServiceProvider).enqueueOperation(
                  accountId: account.id,
                  operationType: 'upsert_contact',
                  targetId: old.id,
                  payload: const {},
                );
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      AppLogger.error('Сохранение контакта', e);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${l10n.tr('error')}: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).where(_writable).toList();
    final fill = _fillable(l10n);
    final existingAccount = widget.existing?.accountId == null
        ? null
        : ref.watch(accountsProvider).where((a) => a.id == widget.existing!.accountId).firstOrNull;

    final muted = AppColors.mutedText(context);

    // Поле — строкой в белой карточке группы (1.7.2+106, замечание
    // владельца 24.10.2026: серые поля на сером фоне сливались, группы полей
    // не было видно). Значки — у всех полей группы или ни у одного: у
    // «Фамилии» значок был один на три поля ФИО и сдвигал строку.
    Widget field(TextEditingController c, String label, IconData? icon,
            {TextInputType? type, String? error, TextCapitalization cap = TextCapitalization.words, bool multiline = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (icon != null) ...[
              Icon(icon, color: muted),
              const SizedBox(width: Space.l),
            ],
            Expanded(
              child: TextField(
                controller: c,
                keyboardType: multiline ? TextInputType.multiline : type,
                textCapitalization: cap,
                minLines: 1,
                maxLines: multiline ? 6 : 1,
                onChanged: error == null ? null : (_) => setState(() => _nameError = null),
                decoration: InputDecoration(
                  labelText: label,
                  errorText: error,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  // Фокус — тонкой линией акцента под полем.
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
                  focusedErrorBorder: UnderlineInputBorder(borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(vertical: Space.s),
                ),
              ),
            ),
          ]),
        );

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr(_isNew ? 'newContact' : 'editContact')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.s),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: Sizes.iconRow, height: Sizes.iconRow, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l10n.save),
            ),
          ),
        ],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.xxl),
        children: [
          // ── Где хранится ──
          SettingsSectionTitle(l10n.tr(_isNew ? 'contactSaveTo' : 'contactStoredIn')),
          SettingsGroup(children: [
            if (_isNew)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
                child: Row(children: [
                  Icon(AppIcons.cloud_sync, color: muted),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _target,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: Space.s),
                      ),
                      items: [
                        for (final a in accounts)
                          DropdownMenuItem(value: a.id, child: Text(a.email, overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: _localTarget, child: Text(l10n.tr('contactLocalOnly'))),
                      ],
                      onChanged: (v) => setState(() {
                        _target = v ?? _localTarget;
                        _error = null;
                      }),
                    ),
                  ),
                ]),
              )
            else
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                leading: Icon(AppIcons.cloud_sync, color: muted),
                title: Text(existingAccount?.email ?? l10n.tr('contactLocalOnly')),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
            child: Text(
              l10n.tr((_isNew ? _target == _localTarget : existingAccount == null)
                  ? 'contactLocalHint'
                  : 'contactServerHint'),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, 0),
              child: Row(children: [
                Icon(AppIcons.error, color: theme.colorScheme.error, size: Sizes.iconRow),
                const SizedBox(width: Space.s),
                Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                if (_isNew && _target != _localTarget)
                  TextButton(
                    onPressed: () => setState(() {
                      _target = _localTarget;
                      _error = null;
                    }),
                    child: Text(l10n.tr('contactSaveLocally')),
                  ),
              ]),
            ),

          // ── Из адресной книги организации (1.6.49) ──
          if (fill.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: Space.l),
              padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.s),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: Radii.chipAll,
              ),
              child: Row(children: [
                Icon(AppIcons.account_tree, size: Sizes.iconRow, color: theme.colorScheme.onSecondaryContainer),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Text(
                    l10n.tr('contactDirHas').replaceAll('{fields}', fill.map((f) => f.$3).join(', ')),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: Space.s),
                FilledButton.tonal(
                  onPressed: () => setState(() {
                    for (final f in fill) {
                      f.$1.text = f.$2;
                    }
                  }),
                  child: Text(l10n.tr('contactDirFill')),
                ),
              ]),
            ),

          // ── ФИО: без значков, все три поля с одной линии ──
          SettingsSectionTitle(l10n.tr('contactGroupName')),
          SettingsGroup(dividerIndent: Space.l, children: [
            field(_last, l10n.tr('lastName'), null, error: _nameError),
            field(_first, l10n.tr('firstName'), null),
            field(_middle, l10n.tr('middleName'), null),
          ]),

          // ── Связь ──
          SettingsSectionTitle(l10n.tr('contactGroupReach')),
          SettingsGroup(children: [
            field(_email, 'E-mail', AppIcons.mail, type: TextInputType.emailAddress, cap: TextCapitalization.none),
            field(_mobile, l10n.tr('phoneMobile'), AppIcons.smartphone, type: TextInputType.phone),
            field(_work, l10n.tr('phoneWork'), AppIcons.phone, type: TextInputType.phone),
          ]),

          // ── Работа ──
          SettingsSectionTitle(l10n.tr('contactGroupWork')),
          SettingsGroup(children: [
            field(_company, l10n.tr('company'), AppIcons.business, cap: TextCapitalization.sentences),
            field(_department, l10n.tr('department'), AppIcons.account_tree, cap: TextCapitalization.sentences),
            field(_title, l10n.tr('jobTitle'), AppIcons.badge, cap: TextCapitalization.sentences),
            field(_manager, l10n.tr('manager'), AppIcons.supervisor_account),
            field(_office, l10n.tr('officeLocation'), AppIcons.place, cap: TextCapitalization.sentences),
          ]),

          // ── Заметка (только на телефоне) ──
          SettingsSectionTitle(l10n.tr('contactGroupNote')),
          SettingsGroup(dividerIndent: Space.l, children: [
            field(_notes, l10n.tr('contactNotePhoneOnly'), null, cap: TextCapitalization.sentences, multiline: true),
          ]),
        ],
      ),
    );
  }
}

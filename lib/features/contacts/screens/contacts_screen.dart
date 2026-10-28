// lib/features/contacts/screens/contacts_screen.dart
import '../my_contact.dart' show showContactQr;
import '../../../core/utils/text_safe.dart';
import '../../settings/providers/module_settings_provider.dart';
import '../../../services/contacts/mail_contacts_service.dart' show mailContactsServiceProvider;
import '../../../core/theme/app_icons.dart';
import '../../../core/logging/app_logger.dart';
import 'package:drift/drift.dart' hide Column;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/person_card.dart';
import '../widgets/contact_editor.dart';
import 'contact_groups_screen.dart';
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/ui/section_band.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsGroup, SettingsSectionTitle;
import '../../../widgets/navigation/panel_requests.dart';
import '../../../widgets/navigation/app_bottom_bar.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/empty_state.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/common/person_photo.dart';
import '../../../widgets/common/photo_viewer.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/peek_card.dart';
import '../../../widgets/common/quick_long_press.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/models/account_model.dart';
import '../../../services/contacts/contact_export_service.dart';
import 'package:share_plus/share_plus.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../mail/providers/mail_providers.dart';
import '../../../services/sync/sync_service.dart' show syncServiceProvider;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/animated_appearance.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../widgets/common/adaptive_layout.dart';
import '../../../widgets/common/shared_mailbox_badge.dart';
import '../../settings/providers/account_groups_provider.dart';
import '../../../data/models/calendar_event_model.dart';
import '../../calendar/screens/calendar_screen.dart' show calendarEventsProvider;
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../person_names.dart';
import '../contact_prefs.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../../services/mail/focus_mode_service.dart' show focusModeProvider;
import '../../../core/utils/person_names.dart' show PersonNames;
import '../../../core/theme/ogneliss_look.dart';
import '../../../core/utils/mail_domains.dart' show sameOrgDomain, mailDomainOf, isPublicMailDomain;

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});
  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // all, frequent, company
  final _listController = ScrollController();

  /// Выбранный контакт для правой панели (только планшет/десктоп).
  Contact? _selectedContact;

  /// Поиск в адресной книге организации (1.7.2, замечание 20.10.2026: «в
  /// контактах не ищет все контакты, через отправителя находит»). Поле
  /// «Кому» искало в контактах всех ящиков, в собранных из переписки и в
  /// адресной книге Exchange, а экран «Контакты» — только в контактах
  /// открытого ящика. Теперь при поиске — то же, что в «Кому».
  List<ContactModel> _gal = const [];
  /// Запрос, для которого получен [_gal].
  String _galFor = '';
  bool _galBusy = false;
  Timer? _galTimer;
  int _galSeq = 0;

  /// Поток списка не пересоздаётся на каждую букву поиска: раньше каждый
  /// символ заново подписывался на базу и на миг показывал индикатор.
  Stream<List<Contact>>? _stream;
  String? _streamKey;

  @override
  void dispose() {
    _galTimer?.cancel();
    _searchCtrl.dispose();
    _listController.dispose();
    super.dispose();
  }

  /// Область списка: группа ящиков, если выбрана, иначе открытый ящик.
  List<String> _scopeIds() {
    final g = ref.read(activeGroupAccountIdsProvider);
    if (g.isNotEmpty) return g;
    final acc = ref.read(activeAccountProvider);
    return acc == null ? <String>[] : [acc.id];
  }

  /// Ящики, у которых есть адресная книга организации (Exchange), в области
  /// списка. Общий ящик — книга основного ящика того же домена.
  List<AccountModel> _directoryAccounts() {
    bool dir(AccountModel a) => !a.isSharedMailbox && (a.usesEas || a.usesEws);
    final all = ref.read(accountsProvider);
    final scope = _scopeIds();
    final inScope = all.where((a) => scope.isEmpty || scope.contains(a.id)).toList();
    final out = inScope.where(dir).toList();
    if (out.isEmpty) {
      final domains = {for (final a in inScope) a.email.split('@').last.toLowerCase()};
      out.addAll(all.where((a) => dir(a) && domains.contains(a.email.split('@').last.toLowerCase())));
    }
    return out;
  }

  void _onSearch(String v) {
    setState(() => _search = v.toLowerCase());
    _galTimer?.cancel();
    final q = v.trim().toLowerCase();
    final seq = ++_galSeq;
    if (q.length < 2) {
      if (_gal.isNotEmpty || _galBusy) {
        setState(() {
          _gal = const [];
          _galFor = '';
          _galBusy = false;
        });
      }
      return;
    }
    _galTimer = Timer(const Duration(milliseconds: 450), () => unawaited(_searchGal(q, seq)));
  }

  Future<void> _searchGal(String q, int seq) async {
    final accounts = _directoryAccounts();
    if (accounts.isEmpty || !mounted) return;
    setState(() => _galBusy = true);
    final out = <ContactModel>[];
    final seen = <String>{};
    for (final acc in accounts) {
      try {
        // Потолок 15 с, как в «Кому»: при плохой связи поиск не висит.
        final list = await ref
            .read(mailEngineServiceProvider)
            .resolveNames(acc, q, maxResults: 25)
            .timeout(const Duration(seconds: 15));
        for (final c in list) {
          final k = c.email.trim().toLowerCase();
          if (k.isEmpty || !seen.add(k)) continue;
          out.add(c);
        }
      } catch (e) {
        AppLogger.debug('Контакты: поиск в адресной книге ${acc.email}: $e');
      }
      if (!mounted || seq != _galSeq) return;
    }
    if (!mounted || seq != _galSeq) return;
    setState(() {
      _gal = out;
      _galFor = q;
      _galBusy = false;
    });
  }

  static String _norm(String? s) => (s ?? '').toLowerCase().replaceAll('ё', 'е');

  /// Совпадение строки поиска: каждое слово — в имени, фамилии, отчестве,
  /// адресе, должности, отделе или компании («артем мис» находит «Мисюра
  /// Артем»); цифры (от трёх) — в телефонах без пробелов и дефисов.
  static bool _matches(Contact c, List<String> words, String digits) {
    final hay = _norm([
      c.displayName, c.email, c.firstName, c.lastName, c.middleName,
      c.jobTitle, c.department, c.company,
    ].whereType<String>().join(' '));
    if (words.isNotEmpty && words.every(hay.contains)) return true;
    if (digits.length >= 3) {
      for (final p in [c.phoneWork, c.phoneMobile]) {
        if ((p ?? '').replaceAll(RegExp(r'\D'), '').contains(digits)) return true;
      }
    }
    return false;
  }

  Stream<List<Contact>> _streamFor(AppDatabase db, List<String> scopeIds) {
    final key = [
      _search.isNotEmpty,
      _filter,
      scopeIds.join(','),
      ref.read(moduleSettingsProvider).contactSort.name,
      identityHashCode(db),
    ].join('|');
    if (_stream == null || key != _streamKey) {
      _streamKey = key;
      _stream = _buildQuery(db, scopeIds);
    }
    return _stream!;
  }

  /// Прокрутка к группе буквы из алфавитного указателя.
  /// Высоты оцениваются (заголовок + плитки контактов): ListView.builder с
  /// переменной высотой не даёт точного offset, но оценка попадает в нужную
  /// область, а дальше пользователь видит заголовок буквы.
  void _jumpToLetter(List<String> keys, Map<String, List<dynamic>> grouped, String letter, {int pinned = 0}) {
    // Плашка буквы (SectionBand.light: 28 + отступы 12 и 4) и строка
    // контакта (портрет 44 + отступы 8 + линия 1), 1.6.40.
    const headerHeight = 44.0;
    const tileHeight = 61.0;
    // Закреплённые (1.6.49+95) — над буквами.
    var offset = pinned == 0 ? 0.0 : headerHeight + tileHeight * pinned;
    for (final k in keys) {
      if (k == letter) break;
      offset += headerHeight + tileHeight * (grouped[k]?.length ?? 0);
    }
    if (!_listController.hasClients) return;
    final max = _listController.position.maxScrollExtent;
    _listController.animateTo(
      offset.clamp(0.0, max),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(databaseProvider);
    // Подписка на настройки модуля: при смене сортировки список перестроится.
    ref.watch(moduleSettingsProvider);
    // «Новый контакт» из центра нижней панели.
    ref.listen<int>(contactsAddRequestProvider, (_, __) => _addContact(db));
    // Закреплённые контакты (1.6.49+95) — вверху списка, без поиска.
    final pinKeys = ref.watch(pinnedContactsProvider);
    // Есть ли в области ящик Exchange — тогда поиск идёт и по адресной
    // книге организации.
    ref.watch(accountsProvider);
    final hasDirectory = _directoryAccounts().isNotEmpty;

    return Scaffold(
      // Список — на белом, как лента писем (1.6.40, замечание 19.10.2026:
      // «контакты и поле поиска не соответствуют остальному интерфейсу»).
      backgroundColor: AppColors.listFill(context),
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.contactsLabel),
        actions: [
          // «Мой контакт» — QR своей карточки, как в Ogneliss Dialer.
          IconButton(
            icon: const Icon(AppIcons.qr_code_2),
            tooltip: l10n.tr('myContact'),
            onPressed: () => context.push('/contacts/me'),
          ),
          IconButton(
            icon: const Icon(AppIcons.merge_type),
            tooltip: l10n.tr('findDuplicates'),
            onPressed: () => context.push('/contacts/duplicates'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'export_vcf' || v == 'export_csv') {
                _exportContacts(db, v == 'export_vcf' ? 'vcf' : 'csv');
              } else if (v == 'groups') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ContactGroupsScreen()));
              } else if (v == 'resync') {
                unawaited(_resyncContacts());
              } else {
                setState(() => _filter = v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'all', child: Text(l10n.tr('all'))),
              PopupMenuItem(value: 'frequent', child: Text(l10n.tr('frequent'))),
              PopupMenuItem(value: 'company', child: Text(l10n.tr('byCompany'))),
              PopupMenuItem(value: 'fromMail', child: Text(l10n.tr('contactsFromMail'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'groups', child: Text(l10n.tr('contactGroups'))),
              // Полное обновление (1.8.0): контакты всех ящиков заново с
              // сервера — изменения, сделанные в Outlook или на сайте почты.
              PopupMenuItem(value: 'resync', child: Text(l10n.tr('contactsResync'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'export_vcf', child: Text(l10n.tr('exportVcf'))),
              PopupMenuItem(value: 'export_csv', child: Text(l10n.tr('exportCsv'))),
            ],
          ),
        ],
      )),
      // На планшете/десктопе — список слева, карточка контакта справа.
      // На телефоне AdaptiveLayout показывает только список (как раньше).
      body: AdaptiveLayout(
        widthKey: 'contacts',
        showDetail: _selectedContact != null,
        detailBody: _selectedContact != null
            ? _ContactDetailsPane(contact: _selectedContact!, l10n: l10n)
            : null,
        placeholder: Center(child: Text(l10n.tr('contactSelectPrompt'))),
        body: Column(
        children: [
          // Поиск — в стиле полей приложения: заливка, скругление, без рамки
          // (тема); крестик очищает.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xs),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.search,
                prefixIcon: const Icon(AppIcons.search),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.tr('clear'),
                        icon: const Icon(AppIcons.close, size: 20),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      ),
              ),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Contact>>(
              stream: _streamFor(db, () {
      // Область: группа, если выбрана; иначе текущий аккаунт. Совпадает с
      // почтой и календарём — адресная книга должна соответствовать ящику.
      final g = ref.watch(activeGroupAccountIdsProvider);
      if (g.isNotEmpty) return g;
      final acc = ref.watch(activeAccountProvider);
      return acc == null ? <String>[] : [acc.id];
    }()),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final contacts = snap.data ?? [];
                final q = _norm(_search.trim());
                final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
                final digits = q.replaceAll(RegExp(r'\D'), '');
                final filtered = q.isEmpty
                    ? contacts
                    : contacts.where((c) => _matches(c, words, digits)).toList();

                // Адресная книга организации — разделом под найденными на
                // телефоне, без тех, кто уже в списке.
                final shown = {for (final c in filtered) c.email.trim().toLowerCase()};
                final galQuery = _search.trim();
                final galOn = galQuery.length >= 2 && hasDirectory;
                final galRows = galOn && _galFor == galQuery
                    ? [for (final g in _gal) if (!shown.contains(g.email.trim().toLowerCase())) g]
                    : const <ContactModel>[];
                final galPending = galOn && (_galBusy || _galFor != galQuery);
                final galSection = galRows.isNotEmpty || galPending;

                if (filtered.isEmpty && !galSection) {
                  return EmptyState(
                    icon: _search.isEmpty ? AppIcons.contacts : AppIcons.search_off,
                    title: l10n.noContacts,
                  );
                }

                // Закреплённые — отдельным разделом сверху, в буквах их нет;
                // по алфавиту, как остальной список (1.7.1: раньше — в порядке
                // закрепления).
                final pinKeySet = pinKeys.toSet();
                final seen = <String>{};
                final pinned = _search.isEmpty && pinKeys.isNotEmpty
                    ? [
                        for (final c in filtered)
                          if (pinKeySet.contains(contactPinKey(c)) && seen.add(contactPinKey(c))) c,
                      ]
                    : <Contact>[];
                pinned.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
                final pinnedSet = {for (final c in pinned) contactPinKey(c)};
                // Group by first letter
                final grouped = <String, List<Contact>>{};
                for (final c in filtered) {
                  if (pinnedSet.contains(contactPinKey(c))) continue;
                  final key = c.displayName.isNotEmpty
                      ? initialOf(c.displayName)
                      : '#';
                  grouped.putIfAbsent(key, () => []).add(c);
                }
                final keys = grouped.keys.toList()..sort();

                return Row(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _listController,
                        itemCount: keys.length + (pinned.isEmpty ? 0 : 1) + (galSection ? 1 : 0),
                        itemBuilder: (ctx, index) {
                          if (galSection && index == keys.length + (pinned.isEmpty ? 0 : 1)) {
                            return _GalSection(rows: galRows, searching: galPending, l10n: l10n);
                          }
                          final top = pinned.isNotEmpty && index == 0;
                          final letter = top ? '' : keys[index - (pinned.isEmpty ? 0 : 1)];
                          final group = top ? pinned : grouped[letter]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Буква — лёгкой плашкой, как даты в ленте писем.
                              SectionBand.light(
                                  title: top ? l10n.tr('pinnedBand') : letter,
                                  count: group.length > 1 ? group.length : null),
                              for (final (j, c) in group.indexed) ...[
                                _ContactTile(
                                  contact: c,
                                  l10n: l10n,
                                  // На планшете тап выбирает контакт для
                                  // правой панели, на телефоне — открывает
                                  // bottom sheet (onSelect = null).
                                  onSelect: AdaptiveLayout.splitOf(context)
                                      ? (picked) => setState(() => _selectedContact = picked)
                                      : null,
                                  selected: _selectedContact?.id == c.id,
                                ),
                                // Линия между строками от начала текста, как в
                                // ленте писем и настройках.
                                if (j < group.length - 1)
                                  const RowDivider(indent: Space.l + 44 + Space.m),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    // Алфавитный указатель. Ширина 28 + вертикальные отступы:
                    // компромисс между площадью касания и местом для списка.
                    SizedBox(
                      width: 28,
                      child: ListView(
                        children: keys
                            .map((k) => GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _jumpToLetter(keys, grouped, k, pinned: pinned.length),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    child: Text(k,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context).colorScheme.primary)),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      ),
      // На телефоне «Новый контакт» — в центре нижней панели.
      floatingActionButton: AppBottomBar.inUse(context) ? null : FloatingActionButton(
        tooltip: AppLocalizations.of(context).tr('create'),
        onPressed: () => _addContact(db),
        child: const Icon(AppIcons.add),
      ),
    );
  }

  /// Диалог создания нового контакта. Сохраняет локально и на сервере (EWS).
  /// Новый контакт — полноэкранная форма с выбором, где хранить
  /// (адресная книга ящика на сервере или только этот телефон).
  /// «Создать» (10.10.2026): контакт или группа для рассылки — группу
  /// раньше можно было завести только через «⋮ → Группы контактов».
  Future<void> _addContact(AppDatabase db) async {
    final l10n = AppLocalizations.of(context);
    final kind = await showActionSheet<String>(context, title: l10n.tr('create'), items: [
      ActionSheetItem(icon: AppIcons.person_add, label: l10n.tr('newContact'), value: 'contact'),
      ActionSheetItem(
          icon: AppIcons.groups,
          label: l10n.tr('groupNew'),
          subtitle: l10n.tr('groupNewHint'),
          value: 'group'),
    ]);
    if (!mounted) return;
    if (kind == 'contact') {
      await showContactEditor(context);
    } else if (kind == 'group') {
      openGroupEditor(context);
    }
  }

  /// Экспорт всех контактов в VCF/CSV и системный «Поделиться». Берём весь
  /// список (без учёта фильтра/поиска — экспорт полный), маппим строки БД в
  /// модель, отдаём файл через share_plus.
  /// «Обновить с сервера» (1.8.0, просьба владельца 26.10.2026: «у
  /// контактов на сервере изменилась компания, но у себя я этих изменений не
  /// вижу»). Контакты каждого ящика с адресной книгой на сервере (Exchange,
  /// CardDAV) перечитываются целиком: изменённые обновятся, удалённые уйдут.
  /// Карточки коллег, кроме того, берут должность, отдел и компанию из
  /// адресной книги организации при каждом открытии.
  Future<void> _resyncContacts() async {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.read(accountsProvider).where((a) => a.isActive && a.authFailedAt == null).toList();
    if (accounts.isEmpty) return;
    final sync = ref.read(syncServiceProvider);
    try {
      for (final a in accounts) {
        await sync.resyncContacts(a);
      }
    } catch (e) {
      AppLogger.warning('Обновление контактов: $e');
      showInlineError(l10n.tr('contactsResyncFailed'));
    }
  }

  Future<void> _exportContacts(AppDatabase db, String fmt) async {
    final l10n = AppLocalizations.of(context);
    try {
      final rows = await db.select(db.contacts).get();
      if (rows.isEmpty) {
        showInlineNotice(l10n.tr('noContactsToExport'));
        return;
      }
      final models = rows
          .map((c) => ContactModel(
                id: c.id,
                accountId: c.accountId,
                email: c.email,
                displayName: c.displayName,
                firstName: c.firstName,
                lastName: c.lastName,
                middleName: c.middleName,
                jobTitle: c.jobTitle,
                department: c.department,
                company: c.company,
                phoneWork: c.phoneWork,
                phoneMobile: c.phoneMobile,
                city: c.city,
                notes: c.notes,
              ))
          .toList();
      final svc = ref.read(contactExportProvider);
      final path = fmt == 'vcf' ? await svc.exportToVcf(models) : await svc.exportToCsv(models);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(path)],
        subject: l10n.tr('contactsN').replaceAll('{n}', '${models.length}'),
      ));
    } catch (e) {
      showInlineError(l10n.tr('exportFailed').replaceAll('{e}', '$e'));
    }
  }

  /// Контакты в области видимости.
  ///
  /// Раньше показывались контакты ВСЕХ аккаунтов сразу, независимо от того,
  /// какой ящик открыт: при нескольких учётных записях адресные книги
  /// смешивались, и рабочий контакт было не отличить от личного.
  /// Теперь область та же, что в почте: группа, либо текущий аккаунт.
  Stream<List<Contact>> _buildQuery(AppDatabase db, List<String> scopeIds) =>
      _buildQueryRaw(db, scopeIds).map(_dedupeByEmail);

  /// Один человек — одна строка. Один и тот же адрес приходит из нескольких
  /// источников: карточка Exchange, адресная книга организации, CardDAV,
  /// собранные из переписки — и в списке было «Никитин, Юрий» дважды.
  /// Оставляем самую полную запись (своя адресная книга, затем организация),
  /// недостающие телефон, должность и фото берём из остальных.
  static List<Contact> _dedupeByEmail(List<Contact> list) {
    int rank(Contact c) => switch (c.source) {
          1 => 3, // personal
          0 => 2, // exchangeGal
          2 => 1, // device
          _ => 0, // fromMail
        };
    int filled(Contact c) => [c.jobTitle, c.company, c.department, c.phoneWork, c.phoneMobile, c.avatarUrl]
        .where((v) => v != null && v.isNotEmpty)
        .length;
    final byKey = <String, int>{};
    final out = <Contact>[];
    for (final c in list) {
      final key = c.email.trim().toLowerCase();
      if (key.isEmpty) {
        out.add(c);
        continue;
      }
      final i = byKey[key];
      if (i == null) {
        byKey[key] = out.length;
        out.add(c);
        continue;
      }
      final old = out[i];
      final better = rank(c) > rank(old) || (rank(c) == rank(old) && filled(c) > filled(old));
      final keep = better ? c : old;
      final other = better ? old : c;
      String? pick(String? a, String? b) => (a != null && a.isNotEmpty) ? a : b;
      out[i] = keep.copyWith(
        jobTitle: Value(pick(keep.jobTitle, other.jobTitle)),
        company: Value(pick(keep.company, other.company)),
        department: Value(pick(keep.department, other.department)),
        phoneWork: Value(pick(keep.phoneWork, other.phoneWork)),
        phoneMobile: Value(pick(keep.phoneMobile, other.phoneMobile)),
        avatarUrl: Value(pick(keep.avatarUrl, other.avatarUrl)),
        middleName: Value(pick(keep.middleName, other.middleName)),
        interactionCount: keep.interactionCount > other.interactionCount
            ? keep.interactionCount
            : other.interactionCount,
      );
    }
    return out;
  }

  Stream<List<Contact>> _buildQueryRaw(AppDatabase db, List<String> scopeIds) {
    // Пустая область (нет аккаунтов) — показываем всё, чтобы экран не выглядел
    // сломанным при первом запуске.
    // Тип запроса указан явно: с dynamic замыкание where получало тип
    // (dynamic) => dynamic, и drift падал при открытии экрана («is not a
    // subtype of ($ContactsTable) => Expression<bool>»).
    void applyScope(SimpleSelectStatement<$ContactsTable, Contact> q) {
      if (scopeIds.isNotEmpty) {
        q.where((c) => c.accountId.isIn(scopeIds));
      }
    }
    if (_search.isNotEmpty) {
      // Поиск (1.7.2) — по всем, как в «Кому»: контакты области и собранные
      // из переписки (у них нет ящика). Фильтр «Частые» (50 первых) поиск
      // не сужает.
      final q = db.select(db.contacts)
        ..orderBy([(c) => OrderingTerm(expression: c.displayName, mode: OrderingMode.asc)]);
      if (scopeIds.isNotEmpty) {
        q.where((c) => c.accountId.isIn(scopeIds) | c.accountId.isNull());
      }
      return q.watch();
    }
    switch (_filter) {
      case 'fromMail':
        // Собранные из переписки (MailContactsService): без ящика, по
        // частоте и свежести переписки.
        return (db.select(db.contacts)
              ..where((c) => c.source.equals(ContactSource.fromMail.index))
              ..orderBy([
                (c) => OrderingTerm(expression: c.interactionCount, mode: OrderingMode.desc),
                (c) => OrderingTerm(expression: c.lastInteraction, mode: OrderingMode.desc),
              ])
              ..limit(500))
            .watch();
      case 'frequent':
        final q = db.select(db.contacts)
          ..orderBy([(c) => OrderingTerm(expression: c.interactionCount, mode: OrderingMode.desc)])
          ..limit(50);
        applyScope(q);
        return q.watch();
      case 'company':
        final q = db.select(db.contacts)
          ..orderBy([(c) => OrderingTerm(expression: c.company, mode: OrderingMode.asc)])
          ..orderBy([(c) => OrderingTerm(expression: c.displayName, mode: OrderingMode.asc)]);
        applyScope(q);
        return q.watch();
      default:
        // Применяем выбранную пользователем сортировку (настройки модуля).
        final sort = ref.read(moduleSettingsProvider).contactSort;
        switch (sort) {
          case ContactSort.recent:
            final q = db.select(db.contacts)
                  ..orderBy([(c) => OrderingTerm(expression: c.lastInteraction, mode: OrderingMode.desc)]);
                applyScope(q);
                return q.watch();
          case ContactSort.firstName:
            final q = db.select(db.contacts)
                  ..orderBy([(c) => OrderingTerm(expression: c.firstName, mode: OrderingMode.asc)]);
                applyScope(q);
                return q.watch();
          case ContactSort.lastName:
            final q = db.select(db.contacts)
                  ..orderBy([(c) => OrderingTerm(expression: c.lastName, mode: OrderingMode.asc)]);
                applyScope(q);
                return q.watch();
        }
    }
  }
}

/// Раздел «Адресная книга организации» в результатах поиска (1.7.2):
/// люди из Exchange, которых нет в контактах на телефоне. Нажатие — карточка
/// человека (как у отправителя письма: должность, отдел, телефоны, «Добавить
/// в контакты»).
class _GalSection extends StatelessWidget {
  final List<ContactModel> rows;
  final bool searching;
  final AppLocalizations l10n;
  const _GalSection({required this.rows, required this.searching, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionBand.light(
          title: l10n.tr('contactsDirectoryBand'),
          count: rows.length > 1 ? rows.length : null),
      for (final (j, p) in rows.indexed) ...[
        _GalTile(person: p, l10n: l10n),
        if (j < rows.length - 1) const RowDivider(indent: Space.l + 44 + Space.m),
      ],
      if (searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: Space.m),
            Expanded(
              child: Text(l10n.tr('recipientSearchGal'),
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ),
          ]),
        ),
    ]);
  }
}

class _GalTile extends ConsumerWidget {
  final ContactModel person;
  final AppLocalizations l10n;
  const _GalTile({required this.person, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = person.displayName.trim().isNotEmpty ? person.displayName.trim() : person.email;
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
    final photosOn = ref.watch(moduleSettingsProvider).showContactPhotos;
    final own = person.avatarUrl;
    final photo = !photosOn
        ? null
        : (own != null && own.isNotEmpty ? own : ref.watch(personPhotosProvider).value?[person.email.toLowerCase()]);
    if (photo == null && photosOn && person.email.contains('@')) {
      ref.read(mailContactsServiceProvider).requestPhoto(person.email, accountId: person.accountId);
    }
    final sub = [person.jobTitle, person.department, person.company, person.email]
        .map((v) => v?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final phone = (person.phoneWork?.isNotEmpty == true) ? person.phoneWork : person.phoneMobile;
    Widget btn(IconData icon, String tip, VoidCallback onTap) => SizedBox(
          width: 40,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(icon, size: 20),
            color: theme.colorScheme.onSurfaceVariant,
            tooltip: tip,
            onPressed: onTap,
          ),
        );
    return InkWell(
      onTap: () => showPersonCard(context, email: person.email, name: name, accountId: person.accountId),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
        child: Row(children: [
          HeroEmailAvatar(
            emailId: 'gal_${person.email.toLowerCase()}',
            hero: false,
            radius: 22,
            initial: initials.isNotEmpty ? initials : '?',
            color: HeroEmailAvatar.colorForEmail(person.email.isNotEmpty ? person.email : name),
            photo: photo,
            email: photosOn ? person.email : null,
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
            ]),
          ),
          if (phone?.isNotEmpty == true)
            btn(AppIcons.phone, l10n.tr('call'), () async {
              final cleaned = phone!.replaceAll(RegExp(r'[^\d+]'), '');
              if (cleaned.isEmpty) return;
              try {
                final ok = await launchUrl(Uri.parse('tel:$cleaned'), mode: LaunchMode.externalApplication);
                if (!ok) showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
              } catch (_) {
                showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
              }
            })
          else
            const SizedBox(width: 40),
          btn(AppIcons.mail, l10n.tr('writeEmail'),
              () => context.push('/compose?to=${Uri.encodeComponent(person.email)}')),
        ]),
      ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  final Contact contact;
  final AppLocalizations l10n;

  /// В режиме split-view (планшет/десктоп) тап не открывает bottom sheet,
  /// а выбирает контакт для правой панели.
  final ValueChanged<Contact>? onSelect;

  /// Подсветка выбранной строки в split-view.
  final bool selected;

  const _ContactTile({
    required this.contact,
    required this.l10n,
    this.onSelect,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Контакт из общего ящика выделяем полосой: правка или удаление чужого
    // контакта затронет всех, кто пользуется этим ящиком.
    final isShared = ref
        .read(accountsProvider)
        .where((a) => a.id == contact.accountId)
        .firstOrNull
        ?.isSharedMailbox ??
        false;
    // Строки контактов не «проявляются» при прокрутке — только сразу.
    return AnimatedAppearance(
      play: false,
      child: SharedMailboxStripe(isShared: isShared, child: _buildTile(context, ref)),
    );
  }

  /// Фото контакта; если у этой записи его нет — фото того же адреса из
  /// других источников (адресная книга организации, CardDAV, аккаунт).
  /// Контакт из переписки и карточка Exchange — разные записи, и у первой
  /// фото не бывало никогда: «фото контактов не загружаются».
  String? _photoOf(WidgetRef ref) {
    // Настройка «Показывать фото» (раньше ни на что не влияла).
    if (!ref.watch(moduleSettingsProvider).showContactPhotos) return null;
    final own = contact.avatarUrl;
    if (own != null && own.isNotEmpty) return own;
    return ref.watch(personPhotosProvider).value?[contact.email.toLowerCase()];
  }

  Widget _buildTile(BuildContext context, WidgetRef ref) {
    final name = contactFullName(contact, ref.watch(personNamesProvider).value);
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
    final photo = _photoOf(ref);
    // Фото нет — спросить в адресной книге организации (по одному запросу
    // за раз, повтор — не чаще раза в неделю). Придёт — строка обновится.
    if (photo == null && ref.read(moduleSettingsProvider).showContactPhotos && contact.email.contains('@')) {
      ref.read(mailContactsServiceProvider).requestPhoto(contact.email, accountId: contact.accountId);
    }
    // Строка контакта (1.5.11, замечание 12.10.2026: «элементы разрознены,
    // пропали аватары»): компактно, как строка ленты писем — портрет той же
    // цветной монограммой или фото, что у писем этого человека; имя одной
    // строкой; под ним одна строка — должность (или отдел, компания,
    // адрес). Компания у сотрудников своей организации одна и та же и
    // повторялась в каждой строке — теперь видна в карточке контакта.
    // Кнопки — меньше и на постоянных местах.
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = [contact.jobTitle, contact.department, contact.company, contact.email]
        .map((v) => v?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    final photosOn = ref.watch(moduleSettingsProvider).showContactPhotos;
    final phone = (contact.phoneWork?.isNotEmpty == true) ? contact.phoneWork : contact.phoneMobile;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      // Удержание — карточка контакта «как в Telegram» (1.6.47): позвонить,
      // написать, скопировать, изменить; палец можно довести до кнопки.
      child: QuickLongPress(
        onLongPress: () => _peek(context, ref, name, photo, phone),
        tracker: HoldPointer.instance,
        pressEffect: true,
        child: InkWell(
        onTap: () => onSelect != null ? onSelect!(contact) : _showContact(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.xs, Space.s),
          child: Row(children: [
            HeroEmailAvatar(
              emailId: 'contact_${contact.id}',
              hero: false,
              radius: 22,
              initial: initials.isNotEmpty ? initials : '?',
              color: HeroEmailAvatar.colorForEmail(contact.email.isNotEmpty ? contact.email : name),
              photo: photo,
              // Фото выключены в настройках — только монограмма.
              email: photosOn ? contact.email : null,
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
                ],
              ),
            ),
            // Звёздочка — VIP одним нажатием (1.6.49+95).
            if (contact.email.contains('@')) _VipStar(email: contact.email, l10n: l10n),
            if (phone?.isNotEmpty == true)
              _actionBtn(context, AppIcons.phone, l10n.tr('call'), () => _callPhone(context, phone!))
            else
              const SizedBox(width: 40),
            if (contact.email.isNotEmpty)
              _actionBtn(context, AppIcons.mail, l10n.tr('writeEmail'),
                  () => context.push('/compose?to=${Uri.encodeComponent(contact.email)}'))
            else
              const SizedBox(width: 40),
          ]),
        ),
      ),
      ),
    );
  }

  /// Карточка контакта по удержанию (1.6.47). Касание карточки — полная
  /// карточка (шторка), как касание строки. 1.6.49+95: вместо «Изменить» —
  /// «Все письма» (поиск в ленте по адресу); «Ещё» — все действия по группам
  /// здесь же: связь, контакт (VIP, закрепить, все письма, изменить,
  /// поделиться), удалить.
  void _peek(BuildContext context, WidgetRef ref, String name, String? photo, String? phone) {
    unawaited(HapticFeedback.mediumImpact());
    final email = contact.email.trim();
    final copy = email.isNotEmpty ? email : (phone ?? '').trim();
    void full() => onSelect != null ? onSelect!(contact) : _showContact(context, ref);
    final vip = email.contains('@') && isVipEmail(ref.read(focusModeProvider), email);
    final pinned = ref.read(pinnedContactsProvider.notifier).isPinned(contact);
    final work = (contact.phoneWork ?? '').trim();
    final mobile = (contact.phoneMobile ?? '').trim();
    unawaited(showPeekCard(
      context,
      anchor: peekAnchorOf(context),
      onOpen: full,
      card: _ContactPeekCard(contact: contact, name: name, photo: photo),
      moreLabel: l10n.tr('peekMore'),
      more: [
        PeekGroup(title: l10n.tr('peekGroupContact'), items: [
          // Подписи короткие (1.7.0: «Ещё» — кнопками в ряд, номер целиком
          // в подпись под кнопкой не помещался).
          if (work.isNotEmpty)
            PeekAction(icon: AppIcons.phone, label: l10n.tr('phoneWork'), onTap: () => unawaited(_callPhone(context, work))),
          if (mobile.isNotEmpty)
            PeekAction(
                icon: AppIcons.smartphone, label: l10n.tr('phoneMobile'), onTap: () => unawaited(_callPhone(context, mobile))),
          if (email.isNotEmpty)
            PeekAction(
              icon: AppIcons.mail,
              label: l10n.tr('writeEmail'),
              onTap: () => context.push('/compose?to=${Uri.encodeComponent(email)}'),
            ),
          if (email.isNotEmpty)
            PeekAction(
              icon: AppIcons.content_copy,
              label: l10n.tr('copyEmail'),
              onTap: () => unawaited(Clipboard.setData(ClipboardData(text: email))),
            ),
          if ((phone ?? '').trim().isNotEmpty)
            PeekAction(
              icon: AppIcons.content_copy,
              label: l10n.tr('copyPhone'),
              onTap: () => unawaited(Clipboard.setData(ClipboardData(text: phone!.trim()))),
            ),
        ]),
        PeekGroup(title: l10n.tr('peekGroupPerson'), items: [
          if (email.contains('@'))
            PeekAction(
              icon: AppIcons.star,
              filled: vip,
              color: vip ? AppColors.brandAmber : null,
              label: l10n.tr(vip ? 'vipRemove' : 'vipAdd'),
              onTap: () => toggleVipEmail(ref, email),
            ),
          PeekAction(
            icon: AppIcons.push_pin,
            filled: pinned,
            label: l10n.tr(pinned ? 'unpinMail' : 'pinMail'),
            onTap: () => unawaited(ref.read(pinnedContactsProvider.notifier).toggle(contact)),
          ),
          if (email.isNotEmpty)
            PeekAction(icon: AppIcons.manage_search, label: l10n.tr('contactAllMails'), onTap: () => _allMails(context, ProviderScope.containerOf(context, listen: false))),
          PeekAction(icon: AppIcons.edit, label: l10n.tr('edit'), onTap: () => _editContact(context, ref)),
          PeekAction(
              icon: AppIcons.qr_code_2,
              label: l10n.tr('shareContactQr'),
              onTap: () => showContactQr(context, contactFromRow(contact))),
        ]),
        PeekGroup(items: [
          PeekAction(
            icon: AppIcons.delete,
            label: l10n.delete,
            color: AppColors.errorText(context),
            onTap: () => _deleteContact(context, ProviderScope.containerOf(context, listen: false)),
          ),
        ]),
      ],
      actions: [
        if (phone?.isNotEmpty == true)
          PeekAction(icon: AppIcons.phone, label: l10n.tr('call'), onTap: () => unawaited(_callPhone(context, phone!))),
        if (email.isNotEmpty)
          PeekAction(
            icon: AppIcons.mail,
            label: l10n.tr('writeEmail'),
            onTap: () => context.push('/compose?to=${Uri.encodeComponent(email)}'),
          ),
        if (copy.isNotEmpty)
          PeekAction(
            icon: AppIcons.content_copy,
            label: l10n.tr('copy'),
            onTap: () {
              unawaited(Clipboard.setData(ClipboardData(text: copy)));
              unawaited(HapticFeedback.selectionClick());
            },
          ),
        // «Все письма от» — вместо «Изменить» (1.6.49+95); без адреса —
        // по-прежнему «Изменить».
        if (email.isNotEmpty)
          PeekAction(icon: AppIcons.manage_search, label: l10n.tr('contactAllMails'), onTap: () => _allMails(context, ProviderScope.containerOf(context, listen: false)))
        else
          PeekAction(icon: AppIcons.edit, label: l10n.tr('peekEdit'), onTap: () => _editContact(context, ref)),
      ],
    ));
  }

  /// Все письма от контакта: поиск в ленте по адресу (1.6.49+95).
  void _allMails(BuildContext context, ProviderContainer c) {
    final email = contact.email.trim();
    if (email.isEmpty) return;
    c.read(mailSearchQueryProvider.notifier).state = email;
    context.go('/mail');
  }

  /// Позвонить по номеру (системное приложение телефона).
  /// Номер очищаем от пробелов/скобок — tel: их не принимает.
  Future<void> _callPhone(BuildContext context, String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    final uri = Uri.parse('tel:$cleaned');
    // Плашки скрыты (19.10) — ошибка строкой на экране.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
    } catch (_) {
      showInlineError(l10n.tr('cannotOpenFile').replaceAll('{e}', phone));
    }
  }

  Widget _actionBtn(BuildContext context, IconData icon, String tooltip, VoidCallback onTap) {
    return SizedBox(
      width: 40,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 20),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  void _showContact(BuildContext context, WidgetRef ref) {
    showAppSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
        // Недостающее (отдел, руководитель, отчество) — из адресной книги
        // организации, при показе (1.6.49). Прокрутку и закреплённые внизу
        // действия ведёт сама карточка (1.7.2+110).
        child: _ContactSheet(tile: this, close: () => Navigator.pop(ctx)),
      ),
    );
  }

  /// Содержимое карточки контакта. Используется в двух местах: в bottom sheet
  /// (телефон) и в правой панели split-view (планшет/десктоп). В панели нечего
  /// закрывать, поэтому [closeSheet] там не передаётся.
  Widget detailsContent(BuildContext context, WidgetRef ref, {VoidCallback? closeSheet}) =>
      _ContactCard(tile: this, closeSheet: closeSheet);

  /// Добавить день рождения контакта в календарь (ежегодное событие на весь день).
  Future<void> _addBirthdayToCalendar(BuildContext context, ProviderContainer ref) async {
    final bday = contact.birthday;
    if (bday == null) return;
    // Контакт может быть общим (без ящика) — событие кладём в активный ящик.
    final accountId = contact.accountId ?? ref.read(activeAccountProvider)?.id;
    if (accountId == null) return;
    final db = ref.read(databaseProvider);
    final now = DateTime.now();
    var next = DateTime(now.year, bday.month, bday.day);
    if (next.isBefore(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year + 1, bday.month, bday.day);
    }
    final name = contact.displayName.isNotEmpty ? contact.displayName : contact.email;
    try {
      await db.into(db.calendarEvents).insert(
            CalendarEventsCompanion.insert(
              id: 'bday_${contact.id}',
              accountId: accountId,
              title: l10n.tr('birthdayOf').replaceAll('{name}', name),
              startTime: next,
              endTime: next.add(const Duration(days: 1)),
              isAllDay: const Value(true),
              recurrence: Value(RecurrenceType.yearly.index),
              createdAt: DateTime.now(),
            ),
            mode: InsertMode.insertOrReplace,
          );
      ref.invalidate(calendarEventsProvider);
      AppLogger.info('День рождения ${contact.email} — в календаре');
    } catch (e) {
      showInlineError('$e');
    }
  }

  void _deleteContact(BuildContext context, ProviderContainer ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('deleteContactQ')),
        content: Text((contact.displayName.isNotEmpty ? contact.displayName : contact.email)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseProvider);
              // Локально (отобразится сразу через watch)
              await (db.delete(db.contacts)
                    ..where((c) => c.id.equals(contact.id) &
                        (contact.accountId == null
                            ? c.accountId.isNull()
                            : c.accountId.equals(contact.accountId!))))
                  .go();
              // На сервере — в аккаунте самого контакта (раньше удаление
              // уходило в активный аккаунт, даже если контакт из другого).
              final account = ref.read(accountsProvider)
                  .where((a) => a.id == contact.accountId).firstOrNull;
              if (account != null && !contact.id.startsWith('local_')) {
                try {
                  // EAS — Sync Delete, EWS — DeleteItem, прочие — no-op.
                  await ref.read(mailEngineServiceProvider).deleteContactEntry(account, contact.id);
                } catch (_) {/* локально уже удалено */}
              }
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _editContact(BuildContext context, WidgetRef ref) {
    showContactEditor(context, existing: contact);
  }
}

/// Правая панель split-view (планшет/десктоп): карточка выбранного контакта.
/// Переиспользует ту же вёрстку и действия, что и bottom sheet на телефоне —
/// содержимое отдаёт `_ContactTile.detailsContent`, поэтому логика в одном месте.
class _ContactDetailsPane extends ConsumerWidget {
  final Contact contact;
  final AppLocalizations l10n;
  const _ContactDetailsPane({required this.contact, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.l),
      // closeSheet не передаём: закрывать нечего, панель постоянная.
      child: _ContactTile(contact: contact, l10n: l10n).detailsContent(context, ref),
    );
  }
}

/// Полное имя контакта: «Фамилия Имя Отчество». Карточки Exchange часто
/// хранят «Фамилия, Имя» — без отчества; если в другой записи (адресная книга
/// организации) имя полнее, берётся оно.
String contactFullName(Contact c, [Map<String, String>? known]) {
  final base = _contactOwnName(c);
  // Имя того же адреса из писем или другой записи — если оно полнее
  // («Смирнов Андрей» → «Смирнов Андрей Викторович»).
  final other = known?[c.email.trim().toLowerCase()];
  if (other != null && isFullerName(other, base)) return PersonNames.russianOrder(other);
  return base;
}

String _contactOwnName(Contact c) {
  final first = c.firstName?.trim() ?? '';
  final last = c.lastName?.trim() ?? '';
  final middle = c.middleName?.trim() ?? '';
  final composed = [last, first, middle].where((p) => p.isNotEmpty).join(' ');
  var dn = c.displayName.trim();
  final comma = dn.indexOf(',');
  if (comma > 0) dn = '${dn.substring(0, comma).trim()} ${dn.substring(comma + 1).trim()}'.trim();
  int words(String v) => v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (composed.isNotEmpty && words(composed) >= words(dn)) return PersonNames.russianOrder(composed);
  if (dn.isNotEmpty) return PersonNames.russianOrder(dn);
  return composed.isNotEmpty ? composed : c.email;
}

/// Содержимое карточки контакта по удержанию: фото, имя, должность и отдел,
/// компания, адрес и телефоны.
class _ContactPeekCard extends StatelessWidget {
  final Contact contact;
  final String name;
  final String? photo;
  const _ContactPeekCard({required this.contact, required this.name, this.photo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final c = contact;
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();
    final role = [c.jobTitle, c.department].map((v) => v?.trim() ?? '').where((v) => v.isNotEmpty).join(' · ');
    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: Space.xs),
          child: Row(children: [
            Icon(icon, size: 16, color: muted),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          HeroEmailAvatar(
            emailId: 'contact_peek_${c.id}',
            hero: false,
            radius: 26,
            initial: initials.isNotEmpty ? initials : '?',
            color: HeroEmailAvatar.colorForEmail(c.email.isNotEmpty ? c.email : name),
            photo: photo,
            email: photo == null ? null : c.email,
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
              if (role.isNotEmpty)
                Text(role, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              if ((c.company ?? '').trim().isNotEmpty)
                Text(c.company!.trim(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ]),
          ),
        ]),
        const SizedBox(height: Space.xs),
        if (c.email.trim().isNotEmpty) line(AppIcons.mail, c.email.trim()),
        if ((c.phoneWork ?? '').trim().isNotEmpty) line(AppIcons.phone, c.phoneWork!.trim()),
        if ((c.phoneMobile ?? '').trim().isNotEmpty) line(AppIcons.smartphone, c.phoneMobile!.trim()),
      ]),
    );
  }
}

/// Полная карточка контакта (1.6.49): то, чего нет в самом контакте (отдел,
/// руководитель, кабинет, телефоны, отчество), — из адресной книги
/// организации (ActiveSync и, если сервер отвечает, EWS) и из полного имени
/// человека в письмах. Только для показа; сохранить в контакт — «Изменить»
/// (в форме — кнопка «Заполнить»).
class _ContactSheet extends ConsumerStatefulWidget {
  final _ContactTile tile;

  final VoidCallback close;
  const _ContactSheet({required this.tile, required this.close});

  @override
  ConsumerState<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends ConsumerState<_ContactSheet> {
  Contact? _merged;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = widget.tile.contact;
    final email = c.email.trim().toLowerCase();
    if (!email.contains('@')) return;
    final accounts = ref
        .read(accountsProvider)
        .where((a) => a.isActive && a.authFailedAt == null && (a.usesEas || a.hasEwsExtras || a.isExchange))
        .toList();
    if (accounts.isEmpty) return;
    final domain = email.split('@').last;
    final acc = accounts.where((a) => a.id == c.accountId).firstOrNull ??
        accounts.where((a) => a.email.toLowerCase().endsWith('@$domain')).firstOrNull ??
        accounts.first;
    ContactModel? found;
    try {
      found = await ref.read(mailEngineServiceProvider).lookupPerson(acc, email);
    } catch (_) {}
    if (!mounted || found == null) return;
    final p = found;
    // Коллега (тот же домен, что у ящика) — должность, отдел, компания,
    // кабинет, руководитель и рабочий телефон берутся из адресной книги
    // организации: она главнее копии в личных контактах, которая сама не
    // обновляется (1.8.0). У остальных — только пустые поля.
    final colleague = !isPublicMailDomain(domain) && sameOrgDomain(domain, mailDomainOf(acc.email));
    Value<String?> pick(String? mine, String? dir) {
      final d = (dir ?? '').trim();
      return Value((mine ?? '').trim().isNotEmpty || d.isEmpty ? mine : d);
    }

    Value<String?> org(String? mine, String? dir) =>
        colleague && (dir ?? '').trim().isNotEmpty ? Value(dir!.trim()) : pick(mine, dir);

    setState(() => _merged = c.copyWith(
          firstName: pick(c.firstName, p.firstName),
          lastName: pick(c.lastName, p.lastName),
          middleName: pick(c.middleName, p.middleName),
          jobTitle: org(c.jobTitle, p.jobTitle),
          department: org(c.department, p.department),
          company: org(c.company, p.company),
          phoneWork: org(c.phoneWork, p.phoneWork),
          phoneMobile: pick(c.phoneMobile, p.phoneMobile),
          office: org(c.office, p.office),
          manager: org(c.manager, p.manager),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final m = _merged;
    final tile = m == null
        ? widget.tile
        : _ContactTile(contact: m, l10n: widget.tile.l10n, onSelect: widget.tile.onSelect);
    // Своим ref и context (1.7.1): ref строки списка к этому времени мог
    // быть уже недействителен — журнал 20.10.2026, «Using ref when a widget
    // is about to or has been unmounted».
    return _ContactCard(tile: tile, closeSheet: widget.close);
  }
}

/// Звёздочка VIP (1.6.49+95): нажатие — адрес в VIP или из VIP.
class _VipStar extends ConsumerWidget {
  final String email;
  final AppLocalizations l10n;
  const _VipStar({required this.email, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vip = ref.watch(focusModeProvider.select((s) => isVipEmail(s, email)));
    return SizedBox(
      width: 40,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        isSelected: vip,
        tooltip: l10n.tr(vip ? 'vipRemove' : 'vipAdd'),
        icon: Icon(AppIcons.star, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        selectedIcon: const Icon(AppIcons.star, size: 20, fill: 1, color: AppColors.brandAmber),
        onPressed: () => toggleVipEmail(ref, email),
      ),
    );
  }
}

/// Полная карточка контакта (1.7.1, замечание владельца 20.10.2026: «не
/// соответствует общему стилю, элементы можно перераспределить; нажатием на
/// почту и телефон ничего не сделать»):
///   · сверху — фото (нажатие — на весь экран), имя, должность и отдел,
///     компания;
///   · ряд круглых кнопок, как у карточек по удержанию: написать, позвонить,
///     все письма, VIP, закрепить;
///   · «СВЯЗЬ» полосой: адрес — нажатие пишет письмо, телефон — звонит,
///     кабинет и руководитель; у каждой строки — «копировать» (и удержание
///     строки копирует);
///   · письма от контакта;
///   · внизу — ряд «Изменить», «QR-код», «Удалить».
class _ContactCard extends ConsumerWidget {
  final _ContactTile tile;
  final VoidCallback? closeSheet;
  const _ContactCard({required this.tile, this.closeSheet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = tile.contact;
    final l10n = tile.l10n;
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final photosOn = ref.watch(moduleSettingsProvider).showContactPhotos;
    final own = c.avatarUrl;
    final photo = !photosOn
        ? null
        : ((own != null && own.isNotEmpty) ? own : ref.watch(personPhotosProvider).value?[c.email.toLowerCase()]);
    final name = contactFullName(c, ref.watch(personNamesProvider).value);
    final role = [c.jobTitle, c.department].map((v) => v?.trim() ?? '').where((v) => v.isNotEmpty).join(' · ');
    final email = c.email.trim();
    final work = (c.phoneWork ?? '').trim();
    final mobile = (c.phoneMobile ?? '').trim();
    final phone = work.isNotEmpty ? work : mobile;
    final vip = email.contains('@') && ref.watch(focusModeProvider.select((s) => isVipEmail(s, email)));
    final pinned = ref.watch(pinnedContactsProvider).contains(contactPinKey(c));
    final container = ProviderScope.containerOf(context, listen: false);
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase();

    // Действие после закрытия шторки — в контексте навигатора приложения:
    // контекст самой шторки к тому времени уже недействителен.
    void afterClose(void Function(BuildContext ctx) action) {
      final nav = Navigator.of(context, rootNavigator: true).context;
      closeSheet?.call();
      action(nav);
    }

    void write() => afterClose((ctx) => GoRouter.of(ctx).push('/compose?to=${Uri.encodeComponent(email)}'));
    void copy(String text) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      unawaited(HapticFeedback.selectionClick());
    }

    final quick = <PeekAction>[
      if (email.isNotEmpty) PeekAction(icon: AppIcons.mail, label: l10n.tr('writeEmail'), keepOpen: true, onTap: write),
      if (phone.isNotEmpty)
        PeekAction(
            icon: AppIcons.phone,
            label: l10n.tr('call'),
            keepOpen: true,
            onTap: () => unawaited(tile._callPhone(context, phone))),
      if (email.isNotEmpty)
        PeekAction(
          icon: AppIcons.manage_search,
          label: l10n.tr('contactAllMails'),
          keepOpen: true,
          onTap: () => afterClose((ctx) => tile._allMails(ctx, container)),
        ),
      if (email.contains('@'))
        PeekAction(
          icon: AppIcons.star,
          filled: vip,
          color: vip ? AppColors.brandAmber : null,
          label: l10n.tr(vip ? 'vipRemove' : 'vipAdd'),
          keepOpen: true,
          onTap: () => toggleVipEmail(ref, email),
        ),
      PeekAction(
        icon: AppIcons.push_pin,
        filled: pinned,
        label: l10n.tr(pinned ? 'unpinMail' : 'pinMail'),
        keepOpen: true,
        onTap: () => unawaited(ref.read(pinnedContactsProvider.notifier).toggle(c)),
      ),
    ];

    Widget row(IconData icon, String value, String label, {VoidCallback? onTap, Widget? trailing}) => InkWell(
          onTap: onTap ?? () => copy(value),
          onLongPress: () => copy(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.tapTarget + Space.s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.xs, Space.xs),
              child: Row(children: [
                Icon(icon, size: Sizes.iconRow, color: onTap == null ? muted : theme.colorScheme.primary),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(value, style: theme.textTheme.bodyLarge),
                    Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ]),
                ),
                trailing ??
                    IconButton(
                      tooltip: l10n.tr('copy'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(AppIcons.content_copy, size: 20, color: muted),
                      onPressed: () => copy(value),
                    ),
              ]),
            ),
          ),
        );

    final bday = c.birthday;
    final info = <Widget>[
      if (email.isNotEmpty) row(AppIcons.mail, email, l10n.tr('email'), onTap: write),
      if (work.isNotEmpty)
        row(AppIcons.phone, work, l10n.tr('phoneWork'), onTap: () => unawaited(tile._callPhone(context, work))),
      if (mobile.isNotEmpty)
        row(AppIcons.smartphone, mobile, l10n.tr('phoneMobile'), onTap: () => unawaited(tile._callPhone(context, mobile))),
      if ((c.office ?? '').trim().isNotEmpty) row(AppIcons.place, c.office!.trim(), l10n.tr('officeLocation')),
      if ((c.manager ?? '').trim().isNotEmpty)
        row(AppIcons.supervisor_account, c.manager!.trim(), l10n.tr('manager')),
      if (bday != null)
        row(
          AppIcons.cake,
          '${bday.day.toString().padLeft(2, '0')}.${bday.month.toString().padLeft(2, '0')}',
          l10n.tr('birthday'),
          trailing: IconButton(
            tooltip: l10n.tr('toCalendar'),
            visualDensity: VisualDensity.compact,
            icon: Icon(AppIcons.event_available, size: 20, color: theme.colorScheme.primary),
            onPressed: () => afterClose((ctx) => unawaited(tile._addBirthdayToCalendar(ctx, container))),
          ),
        ),
    ];

    // ── Контакт: изменить, QR-код, удалить ──
    final actions = PeekActionsRow(actions: [
      PeekAction(
        icon: AppIcons.edit,
        label: l10n.tr('edit'),
        keepOpen: true,
        onTap: () => afterClose((ctx) => tile._editContact(ctx, ref)),
      ),
      PeekAction(
        icon: AppIcons.qr_code_2,
        label: l10n.tr('shareContactQr'),
        keepOpen: true,
        onTap: () => showContactQr(context, contactFromRow(c)),
      ),
      PeekAction(
        icon: AppIcons.delete,
        label: l10n.delete,
        color: AppColors.errorText(context),
        keepOpen: true,
        onTap: () => afterClose((ctx) => tile._deleteContact(ctx, container)),
      ),
    ]);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Кто ──
        Center(
          child: GestureDetector(
            onTap: photoImage(photo) == null
                ? null
                : () => unawaited(showPhotoViewer(context, photo: photo!, title: name)),
            child: photoImage(photo) != null
                ? PhotoRing(
                    child: CircleAvatar(
                    radius: 44,
                    backgroundImage: photoImage(photo),
                    onBackgroundImageError: (_, __) {},
                  ))
                : HeroEmailAvatar(
                    emailId: 'contact_card_${c.id}',
                    hero: false,
                    radius: 44,
                    initial: initials.isNotEmpty ? initials : '?',
                    color: HeroEmailAvatar.colorForEmail(email.isNotEmpty ? email : name),
                  ),
          ),
        ),
        const SizedBox(height: Space.m),
        Text(name, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        if (role.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(role, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          ),
        if ((c.company ?? '').trim().isNotEmpty)
          Text(c.company!.trim(), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: Space.l),
        // ── Быстрые действия — как ряд под карточкой по удержанию ──
        if (quick.isNotEmpty) PeekActionsRow(actions: quick),
        // ── Связь — белой карточкой под полосой раздела, как настройки
        // (1.7.2+110, замечание владельца 24.10.2026: «карточка контакта не
        // похожа на остальные — сплошное серое пространство») ──
        if (info.isNotEmpty) ...[
          SettingsSectionTitle(l10n.tr('peekGroupContact')),
          SettingsGroup(children: info),
        ],
        // ── Письма от контакта: последние 5, остальные — по «Ещё» ──
        if (email.isNotEmpty) PersonMails(email: email, onOpen: closeSheet, cards: true),
      ],
    );

    // В шторке действия закреплены внизу, над системной панелью телефона
    // (1.7.2+110: «нижняя панель контактов уезжает вниз» — ряд был в конце
    // прокрутки, и у длинной карточки его закрывала панель навигации).
    if (closeSheet != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.l, Space.m, Space.m),
              child: content,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.m, Space.s),
              child: actions,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [content, const SizedBox(height: Space.l), actions],
    );
  }
}

// lib/features/contacts/widgets/person_card.dart
// Карточка человека по адресу: нажатие на отправителя или адресата в письме.
// Сразу показывает то, что есть в контактах на телефоне, затем дополняет из
// адресной книги организации (Exchange): должность, отдел, телефоны,
// кабинет, руководитель, фото. Нужна, чтобы понять, кто написал, не уходя
// из письма.

import '../../../widgets/ui/section_band.dart';
import '../../../widgets/ui/settings_group.dart' show SettingsGroup, SettingsSectionTitle;
import 'dart:async';
import '../../../core/utils/text_safe.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/navigation/app_router.dart' show mailOpenPath;
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/contact_model.dart';
import '../../../data/providers/database_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/person_photo.dart' show personPhotosProvider;
import '../../../widgets/common/photo_viewer.dart';
import '../../mail/providers/mail_providers.dart';
import '../../settings/providers/feature_flags_provider.dart';
import 'contact_editor.dart';
import '../contact_prefs.dart' show isVipEmail, toggleVipEmail;
import '../../../services/mail/focus_mode_service.dart' show focusModeProvider;

/// Открыть карточку человека. [accountId] — ящик письма: через него
/// запрашивается адресная книга организации.
Future<void> showPersonCard(
  BuildContext context, {
  required String email,
  String? name,
  String? accountId,
}) {
  HapticFeedback.selectionClick();
  return showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PersonCard(email: email.trim(), name: name, accountId: accountId),
  );
}

class _PersonCard extends ConsumerStatefulWidget {
  final String email;
  final String? name;
  final String? accountId;
  const _PersonCard({required this.email, this.name, this.accountId});

  @override
  ConsumerState<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends ConsumerState<_PersonCard> {
  ContactModel? _person;
  bool _loadingRemote = false;
  /// Человек уже есть в контактах телефона.
  bool _hasLocal = false;

  Future<void> _load() async {
    final e = widget.email.toLowerCase();
    // 1. Контакты на телефоне (все ящики): сначала этого ящика, затем самая
    //    полная карточка.
    try {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(db.contacts)
            ..where((c) => c.email.lower().equals(e)))
          .get();
      if (rows.isNotEmpty) {
        int score(Contact r) =>
            (r.accountId == widget.accountId ? 100 : 0) +
            [r.jobTitle, r.department, r.company, r.phoneWork, r.phoneMobile, r.middleName, r.manager]
                .where((v) => (v ?? '').trim().isNotEmpty)
                .length;
        rows.sort((a, b) => score(b).compareTo(score(a)));
        if (mounted) {
          setState(() {
            _person = contactFromRow(rows.first);
            _hasLocal = true;
          });
        }
      }
    } catch (_) {}

    // 2. Адресная книга организации.
    final account = ref.read(accountsProvider).where((a) => a.id == widget.accountId).firstOrNull;
    if (account == null || !(account.usesEas || account.hasEwsExtras || account.isExchange)) return;
    if (mounted) setState(() => _loadingRemote = true);
    final remote = await ref.read(mailEngineServiceProvider).lookupPerson(account, e);
    if (!mounted) return;
    setState(() {
      _loadingRemote = false;
      if (remote != null) _person = _merge(_person, remote);
    });
  }

  /// Данные адресной книги свежее; локальные поля (избранное, заметки)
  /// остаются, пустые поля книги не затирают заполненные локально.
  static ContactModel _merge(ContactModel? local, ContactModel gal) {
    if (local == null) return gal;
    String? pick(String? g, String? l) => (g ?? '').trim().isNotEmpty ? g : l;
    int words(String v) => v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return ContactModel(
      id: local.id,
      accountId: local.accountId,
      email: local.email,
      displayName: words(gal.displayName) >= words(local.displayName) ? gal.displayName : local.displayName,
      firstName: pick(gal.firstName, local.firstName),
      lastName: pick(gal.lastName, local.lastName),
      middleName: pick(gal.middleName, local.middleName),
      jobTitle: pick(gal.jobTitle, local.jobTitle),
      department: pick(gal.department, local.department),
      company: pick(gal.company, local.company),
      phoneWork: pick(gal.phoneWork, local.phoneWork),
      phoneMobile: pick(gal.phoneMobile, local.phoneMobile),
      office: pick(gal.office, local.office),
      manager: pick(gal.manager, local.manager),
      city: pick(gal.city, local.city),
      avatarUrl: pick(gal.avatarUrl, local.avatarUrl),
      source: local.source,
      notes: local.notes,
      birthday: local.birthday,
    );
  }

  String _fullName(ContactModel? p) {
    final fallback = (widget.name ?? '').trim().isNotEmpty ? widget.name!.trim() : widget.email;
    if (p == null) return fallback;
    final composed = p.fullName;
    int words(String v) => v.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final dn = p.displayName.trim();
    if (composed.isNotEmpty && words(composed) >= words(dn)) return composed;
    return dn.isNotEmpty ? dn : fallback;
  }

  Future<void> _call(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return;
    await launchUrl(Uri.parse('tel:$cleaned'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = _person;
    final name = _fullName(p);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.mutedText(context));
    final subtitle = [p?.jobTitle, p?.department, p?.company]
        .where((v) => (v ?? '').trim().isNotEmpty)
        .map((v) => v!.trim())
        .toList();

    Widget row(IconData icon, String value, String label, {VoidCallback? onTap, Widget? trailing}) => ListTile(
          leading: Icon(icon),
          title: Text(value),
          subtitle: Text(label),
          onTap: onTap,
          trailing: trailing,
          minTileHeight: Sizes.tapTarget,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
        );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Шапка: фото, ФИО, должность ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Нажатие на фото — на весь экран (1.6.49, как в Telegram).
                  GestureDetector(
                    onTap: () {
                      final photo = p?.avatarUrl ?? ref.read(personPhotosProvider).value?[widget.email.toLowerCase()];
                      if ((photo ?? '').isNotEmpty) unawaited(showPhotoViewer(context, photo: photo!, title: name));
                    },
                    child: HeroEmailAvatar(
                      emailId: 'person_${widget.email}',
                      hero: false,
                      initial: name.isNotEmpty ? initialOf(name) : '?',
                      color: HeroEmailAvatar.colorForEmail(widget.email),
                      email: widget.email,
                      photo: p?.avatarUrl,
                      radius: 32,
                    ),
                  ),
                  const SizedBox(width: Space.l),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(name, style: theme.textTheme.titleLarge),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(subtitle.join(' · '), style: muted),
                          ),
                      ],
                    ),
                  ),
                  // Звёздочка VIP одним нажатием (1.6.49+95).
                  if (widget.email.contains('@'))
                    Builder(builder: (context) {
                      final vip = ref.watch(focusModeProvider.select((s) => isVipEmail(s, widget.email)));
                      return IconButton(
                        isSelected: vip,
                        tooltip: l10n.tr(vip ? 'vipRemove' : 'vipAdd'),
                        icon: const Icon(AppIcons.star),
                        selectedIcon: const Icon(AppIcons.star, fill: 1, color: AppColors.brandAmber),
                        onPressed: () => toggleVipEmail(ref, widget.email),
                      );
                    }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.m, Space.xl, 0),
              child: SizedBox(height: 2, child: _loadingRemote ? const LinearProgressIndicator(minHeight: 2) : null),
            ),
            const SizedBox(height: Space.s),

            // ── Быстрые действия ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
              child: Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(AppIcons.edit),
                    label: Text(l10n.tr('compose')),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push(Uri(path: '/compose', queryParameters: {
                        'to': widget.email,
                        if (widget.accountId != null) 'accountId': widget.accountId!,
                      }).toString());
                    },
                  ),
                  if (!_hasLocal)
                    OutlinedButton.icon(
                      icon: const Icon(AppIcons.person_add),
                      label: Text(l10n.tr('addContact')),
                      // Форма поверх карточки; после сохранения карточка
                      // перечитывает контакт.
                      onPressed: () async {
                        final saved = await showContactEditor(context,
                            email: widget.email, name: _fullName(_person));
                        if (saved == true && mounted) unawaited(_load());
                      },
                    ),
                  // Все файлы из писем этого человека («найти документ»).
                  if (ref.watch(featureFlagsProvider).showFileHub)
                    OutlinedButton.icon(
                      icon: const Icon(AppIcons.attach_file),
                      label: Text(l10n.tr('personFiles')),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push('/attachment-hub?from=${Uri.encodeQueryComponent(widget.email)}');
                      },
                    ),
                  if ((p?.phoneMobile ?? p?.phoneWork ?? '').trim().isNotEmpty)
                    FilledButton.tonalIcon(
                      icon: const Icon(AppIcons.phone),
                      label: Text(l10n.tr('call')),
                      onPressed: () => _call((p!.phoneMobile ?? '').trim().isNotEmpty ? p.phoneMobile! : p.phoneWork!),
                    ),
                ],
              ),
            ),
            // ── Сведения и письма — белыми карточками под полосами разделов,
            // как карточка контакта и настройки (1.7.2+110) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsSectionTitle(l10n.tr('peekGroupContact')),
                  SettingsGroup(children: [
                    row(AppIcons.mail, widget.email, 'E-mail',
                        trailing: IconButton(
                          tooltip: l10n.tr('copy'),
                          icon: const Icon(AppIcons.content_copy),
                          onPressed: () => Clipboard.setData(ClipboardData(text: widget.email)),
                        )),
                    if ((p?.phoneWork ?? '').trim().isNotEmpty)
                      row(AppIcons.phone, p!.phoneWork!, l10n.tr('phoneWork'), onTap: () => _call(p.phoneWork!)),
                    if ((p?.phoneMobile ?? '').trim().isNotEmpty)
                      row(AppIcons.smartphone, p!.phoneMobile!, l10n.tr('phoneMobile'), onTap: () => _call(p.phoneMobile!)),
                    if ((p?.department ?? '').trim().isNotEmpty)
                      row(AppIcons.account_tree, p!.department!, l10n.tr('department')),
                    if ((p?.office ?? '').trim().isNotEmpty)
                      row(AppIcons.place, p!.office!, l10n.tr('officeLocation')),
                    if ((p?.manager ?? '').trim().isNotEmpty)
                      row(AppIcons.supervisor_account, p!.manager!, l10n.tr('manager')),
                  ]),
                  // ── Письма от человека ──
                  PersonMails(email: widget.email, onOpen: () => Navigator.of(context).pop(), cards: true),
                ],
              ),
            ),
            if (p == null && !_loadingRemote)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0),
                child: Text(l10n.tr('personNotInDirectory'), style: muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Письма от человека: последние 5 (карточка открывается быстро), по «Ещё» —
/// до 50. Используется в карточке человека и в карточке контакта.
class PersonMails extends ConsumerStatefulWidget {
  final String email;
  /// Вызывается перед переходом к письму (закрыть шторку).
  final VoidCallback? onOpen;

  /// Белой карточкой под полосой раздела, как настройки (1.7.2+110,
  /// замечание владельца 24.10.2026: «карточка контакта — сплошное серое
  /// пространство»).
  final bool cards;
  const PersonMails({super.key, required this.email, this.onOpen, this.cards = false});

  @override
  ConsumerState<PersonMails> createState() => _PersonMailsState();
}

class _PersonMailsState extends ConsumerState<PersonMails> {
  List<Email> _mails = const [];
  bool _more = false;
  int _limit = 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = widget.email.trim().toLowerCase();
    if (e.isEmpty) return;
    try {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(db.emails)
            ..where((m) => m.fromEmail.lower().equals(e))
            ..orderBy([(m) => OrderingTerm(expression: m.receivedAt, mode: OrderingMode.desc)])
            ..limit(_limit + 1))
          .get();
      if (!mounted) return;
      setState(() {
        _more = rows.length > _limit;
        _mails = rows.take(_limit).toList();
      });
    } catch (_) {}
  }

  void _openMail(Email m) {
    // Адрес — до закрытия карточки: карточка лежит в навигаторе того
    // экрана, откуда её открыли (главный экран или страница поверх него).
    final router = GoRouter.of(context);
    final path = mailOpenPath(context, m.id, accountId: m.accountId);
    widget.onOpen?.call();
    router.push(path);
  }

  @override
  Widget build(BuildContext context) {
    if (_mails.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    if (widget.cards) {
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSectionTitle(l10n.tr('personMails'), count: _mails.length > 1 ? _mails.length : null),
          SettingsGroup(children: [
            for (final m in _mails)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                leading: Icon(m.isRead ? AppIcons.drafts : AppIcons.mail, color: AppColors.mutedText(context)),
                title: Text(m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: m.isRead ? null : const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('d MMM yyyy, HH:mm', l10n.localeCode).format(m.receivedAt.toLocal())),
                onTap: () => _openMail(m),
              ),
            if (_more)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                leading: Icon(AppIcons.expand_more, color: theme.colorScheme.primary),
                title: Text(l10n.tr('more'), style: TextStyle(color: theme.colorScheme.primary)),
                onTap: () {
                  _limit = 50;
                  _load();
                },
              ),
          ]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Раздел — полосой, как в боковом меню (10.10.2026).
        const SizedBox(height: Space.s),
        SectionBand(title: l10n.tr('personMails'), count: _mails.length > 1 ? _mails.length : null),
        for (final m in _mails)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: Icon(m.isRead ? AppIcons.drafts : AppIcons.mail, size: Sizes.iconRow),
            title: Text(m.subject.trim().isEmpty ? l10n.tr('noSubject') : m.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: m.isRead ? null : const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(DateFormat('d MMM yyyy, HH:mm', l10n.localeCode).format(m.receivedAt.toLocal())),
            onTap: () => _openMail(m),
          ),
        if (_more)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: Space.m),
              child: TextButton(
                onPressed: () {
                  _limit = 50;
                  _load();
                },
                child: Text(l10n.tr('more')),
              ),
            ),
          ),
      ],
    );
  }
}

// lib/features/contacts/my_contact.dart
// «Мой контакт» и обмен контактом через QR-код (как в Ogneliss Dialer).
//
// QR содержит обычную карточку vCard 3.0: её распознаёт камера любого
// телефона (Android, iPhone) и предлагает сохранить контакт — второму
// человеку не нужно наше приложение. Кнопка «Поделиться» отправляет ту же
// карточку файлом .vcf (мессенджер, почта).
//
// Свой контакт определяется сам: адрес ящика → контакт с этим адресом в
// базе → адресная книга организации (Exchange: должность, отдел, телефоны) →
// имя ящика. Пользователь может поправить поля; правка хранится в телефоне.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/contact_model.dart';
import '../../data/providers/database_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/mail/engine/mail_engine_service.dart';
import '../../widgets/common/app_sheet.dart';
import '../../widgets/common/text_scale_cap.dart';
import '../mail/providers/mail_providers.dart';

/// Карточка vCard 3.0 для QR и файла: только то, что нужно для звонка и
/// письма, — короткая карточка даёт крупные, легко читаемые точки QR.
String vcardOf(ContactModel c) {
  String esc(String? v) => (v ?? '')
      .trim()
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');
  bool has(String? v) => (v ?? '').trim().isNotEmpty;
  final fn = has(c.fullName) ? c.fullName : c.displayName;
  final lines = <String>[
    'BEGIN:VCARD',
    'VERSION:3.0',
    'N:${esc(c.lastName)};${esc(c.firstName)};${esc(c.middleName)};;',
    'FN:${esc(fn)}',
    if (has(c.company) || has(c.department))
      'ORG:${esc(c.company)}${has(c.department) ? ';${esc(c.department)}' : ''}',
    if (has(c.jobTitle)) 'TITLE:${esc(c.jobTitle)}',
    if (has(c.phoneMobile)) 'TEL;TYPE=CELL:${esc(c.phoneMobile)}',
    if (has(c.phoneWork))
      'TEL;TYPE=WORK:${esc(c.phoneWork)}${has(c.phoneExtension) ? ';ext=${esc(c.phoneExtension)}' : ''}',
    if (has(c.email)) 'EMAIL;TYPE=INTERNET:${esc(c.email)}',
    'END:VCARD',
  ];
  return '${lines.join('\r\n')}\r\n';
}

const _kMyContact = 'my_contact_v1';

Map<String, String?> _toMap(ContactModel c) => {
      'email': c.email,
      'displayName': c.displayName,
      'firstName': c.firstName,
      'lastName': c.lastName,
      'middleName': c.middleName,
      'jobTitle': c.jobTitle,
      'department': c.department,
      'company': c.company,
      'phoneMobile': c.phoneMobile,
      'phoneWork': c.phoneWork,
      'phoneExtension': c.phoneExtension,
    };

ContactModel _fromMap(Map<String, dynamic> m) => ContactModel(
      id: 'me',
      email: (m['email'] as String?) ?? '',
      displayName: (m['displayName'] as String?) ?? '',
      firstName: m['firstName'] as String?,
      lastName: m['lastName'] as String?,
      middleName: m['middleName'] as String?,
      jobTitle: m['jobTitle'] as String?,
      department: m['department'] as String?,
      company: m['company'] as String?,
      phoneMobile: m['phoneMobile'] as String?,
      phoneWork: m['phoneWork'] as String?,
      phoneExtension: m['phoneExtension'] as String?,
    );

/// Сохранённый «мой контакт» (null — ещё не определён).
ContactModel? savedMyContact(WidgetRef ref) {
  final raw = ref.read(sharedPrefsProvider).getString(_kMyContact);
  if (raw == null) return null;
  try {
    return _fromMap(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> saveMyContact(WidgetRef ref, ContactModel c) =>
    ref.read(sharedPrefsProvider).setString(_kMyContact, jsonEncode(_toMap(c)));

/// Определить свой контакт по активному ящику: контакт в базе с этим адресом,
/// затем адресная книга организации, затем имя ящика.
Future<ContactModel?> detectMyContact(WidgetRef ref) async {
  final account = ref.read(activeAccountProvider) ?? ref.read(accountsProvider).firstOrNull;
  if (account == null) return null;
  final email = account.email.trim();
  ContactModel? best;
  try {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.contacts)..where((c) => c.email.lower().equals(email.toLowerCase()))).get();
    if (rows.isNotEmpty) best = contactFromRow(rows.first);
  } catch (_) {}
  try {
    final gal = await ref.read(mailEngineServiceProvider).lookupPerson(account, email);
    if (gal != null) best = _merge(best, gal);
  } catch (_) {}
  final name = account.displayName.trim();
  final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  best ??= ContactModel(
    id: 'me',
    email: email,
    displayName: name.isEmpty ? email : name,
    // «Фамилия Имя Отчество» — порядок, принятый в корпоративной почте.
    lastName: parts.length >= 2 ? parts[0] : null,
    firstName: parts.length >= 2 ? parts[1] : (parts.isEmpty ? null : parts[0]),
    middleName: parts.length >= 3 ? parts[2] : null,
  );
  return _merge(best, null);
}

ContactModel _merge(ContactModel? a, ContactModel? b) {
  String? pick(String? x, String? y) => (x ?? '').trim().isNotEmpty ? x : y;
  final base = a ?? b!;
  final other = a == null ? null : b;
  return ContactModel(
    id: 'me',
    email: base.email,
    displayName: pick(base.displayName, other?.displayName) ?? base.email,
    firstName: pick(base.firstName, other?.firstName),
    lastName: pick(base.lastName, other?.lastName),
    middleName: pick(base.middleName, other?.middleName),
    jobTitle: pick(base.jobTitle, other?.jobTitle),
    department: pick(base.department, other?.department),
    company: pick(base.company, other?.company),
    phoneMobile: pick(base.phoneMobile, other?.phoneMobile),
    phoneWork: pick(base.phoneWork, other?.phoneWork),
    phoneExtension: pick(base.phoneExtension, other?.phoneExtension),
  );
}

/// Отправить карточку файлом .vcf (мессенджер, почта, Bluetooth).
Future<void> shareContactVcf(ContactModel c) async {
  final dir = await getTemporaryDirectory();
  final base = (c.fullName.isNotEmpty ? c.fullName : c.displayName).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  final file = File('${dir.path}/${base.isEmpty ? 'contact' : base}.vcf');
  await file.writeAsString(vcardOf(c));
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/vcard')]));
}

/// QR-код карточки любого контакта (шторка).
Future<void> showContactQr(BuildContext context, ContactModel c) => showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
          child: _QrCard(contact: c),
        ),
      ),
    );

/// QR, имя, должность и кнопка «Поделиться».
class _QrCard extends StatelessWidget {
  final ContactModel contact;
  final List<Widget> extraActions;
  const _QrCard({required this.contact, this.extraActions = const []});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = contact;
    final name = c.fullName.isNotEmpty ? c.fullName : c.displayName;
    final width = MediaQuery.sizeOf(context).width;
    final size = (width - 2 * Space.xl).clamp(160.0, 300.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // QR — всегда тёмный на белом: так его читает любая камера, и в
        // тёмной теме тоже.
        Container(
          padding: const EdgeInsets.all(Space.m),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: Radii.chipAll),
          child: QrImageView(
            data: vcardOf(c),
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0F2742)),
            dataModuleStyle:
                const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0F2742)),
          ),
        ),
        const SizedBox(height: Space.m),
        Text(name, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        if (c.subtitle.isNotEmpty)
          Text(c.subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
        const SizedBox(height: Space.xs),
        Text(l10n.tr('qrHint'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context))),
        const SizedBox(height: Space.m),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            FilledButton.icon(
              icon: const Icon(AppIcons.share),
              label: Text(l10n.tr('share')),
              onPressed: () => shareContactVcf(c),
            ),
            ...extraActions,
          ],
        ),
      ],
    );
  }
}

/// Экран «Мой контакт»: QR своей карточки, «Поделиться», «Изменить»,
/// «Определить заново».
class MyContactScreen extends ConsumerStatefulWidget {
  const MyContactScreen({super.key});

  @override
  ConsumerState<MyContactScreen> createState() => _MyContactScreenState();
}

class _MyContactScreenState extends ConsumerState<MyContactScreen> {
  ContactModel? _me;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _me = savedMyContact(ref);
    if (_me == null) {
      _detect();
    } else {
      _loading = false;
    }
  }

  Future<void> _detect() async {
    setState(() => _loading = true);
    final me = await detectMyContact(ref);
    if (!mounted) return;
    if (me != null) await saveMyContact(ref, me);
    if (!mounted) return;
    setState(() {
      _me = me;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final me = _me;
    if (me == null) return;
    final edited = await showAppSheet<ContactModel>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _MyContactForm(contact: me),
    );
    if (edited == null || !mounted) return;
    await saveMyContact(ref, edited);
    if (mounted) setState(() => _me = edited);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = _me;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('myContact')), actions: [
        IconButton(
          tooltip: l10n.tr('myContactDetect'),
          icon: const Icon(AppIcons.sync),
          onPressed: _loading ? null : _detect,
        ),
      ])),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : me == null
              ? Center(child: Text(l10n.tr('noAccountsAdded')))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.xl),
                  child: _QrCard(contact: me, extraActions: [
                    OutlinedButton.icon(
                      icon: const Icon(AppIcons.edit),
                      label: Text(l10n.tr('edit')),
                      onPressed: _edit,
                    ),
                  ]),
                ),
    );
  }
}

/// Правка своего контакта (только в телефоне, на сервер не отправляется).
class _MyContactForm extends StatefulWidget {
  final ContactModel contact;
  const _MyContactForm({required this.contact});

  @override
  State<_MyContactForm> createState() => _MyContactFormState();
}

class _MyContactFormState extends State<_MyContactForm> {
  late final Map<String, TextEditingController> _c;

  @override
  void initState() {
    super.initState();
    final m = _toMap(widget.contact);
    _c = {for (final k in m.keys) k: TextEditingController(text: m[k] ?? '')};
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget field(String key, String label, {TextInputType? type}) => Padding(
          padding: const EdgeInsets.only(bottom: Space.s),
          child: TextField(
            controller: _c[key],
            keyboardType: type,
            decoration: InputDecoration(labelText: label),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.l),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l10n.tr('myContact'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Space.m),
            field('lastName', l10n.tr('lastName')),
            field('firstName', l10n.tr('firstName')),
            field('middleName', l10n.tr('middleName')),
            field('phoneMobile', l10n.tr('phoneMobile'), type: TextInputType.phone),
            field('phoneWork', l10n.tr('phoneWork'), type: TextInputType.phone),
            field('email', 'Email', type: TextInputType.emailAddress),
            field('company', l10n.tr('company')),
            field('department', l10n.tr('department')),
            field('jobTitle', l10n.tr('jobTitle')),
            const SizedBox(height: Space.s),
            FilledButton(
              onPressed: () {
                String? v(String k) => _c[k]!.text.trim().isEmpty ? null : _c[k]!.text.trim();
                final full = [v('lastName'), v('firstName'), v('middleName')].whereType<String>().join(' ');
                Navigator.of(context).pop(ContactModel(
                  id: 'me',
                  email: v('email') ?? '',
                  displayName: full.isEmpty ? (v('email') ?? '') : full,
                  lastName: v('lastName'),
                  firstName: v('firstName'),
                  middleName: v('middleName'),
                  phoneMobile: v('phoneMobile'),
                  phoneWork: v('phoneWork'),
                  phoneExtension: widget.contact.phoneExtension,
                  company: v('company'),
                  department: v('department'),
                  jobTitle: v('jobTitle'),
                ));
              },
              child: Text(l10n.save),
            ),
          ]),
        ),
      ),
    );
  }
}

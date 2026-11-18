// lib/features/settings/widgets/client_certificates_section.dart
// «Безопасность соединения → Сертификаты клиента» (2.6.5): сервер почты
// организации требует сертификат устройства (mTLS). Файл .p12/.pfx с
// паролем и домены серверов, которым его предъявлять; сертификат,
// заданный организацией (MDM), — только для просмотра.

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/platform/file_pick.dart' show FilePick;
import '../../../core/security/client_cert_store.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../features/mail/providers/mail_providers.dart' show accountsProvider;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/inline_notice.dart' show quietError;
import '../../../widgets/ui/settings_group.dart';

class ClientCertificatesSection extends ConsumerStatefulWidget {
  const ClientCertificatesSection({super.key});

  @override
  ConsumerState<ClientCertificatesSection> createState() => _ClientCertificatesSectionState();
}

class _ClientCertificatesSectionState extends ConsumerState<ClientCertificatesSection> {
  ClientCertStore? get _store => ClientCertStore.instance;

  /// Домены по умолчанию: серверы и домены ящиков организаций (Exchange,
  /// свой IMAP) — не общедоступных служб со входом Google, Microsoft и т. п.
  List<String> _suggested() {
    final List<AccountModel> accounts = ref.read(accountsProvider);
    return ClientCertStore.normalizeDomains([
      for (final a in accounts)
        if (!a.isOAuth) ...[
          ?ClientCertStore.domainOfEmail(a.email),
          ?a.exchangeServer,
          ?a.imapServer,
          ?a.smtpServer,
        ],
    ]);
  }

  Future<void> _add() async {
    final file = await FilePick.file();
    if (file == null || _store == null || !mounted) return;
    final bytes = await file.readBytes();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ImportDialog(
        fileName: file.name,
        domains: _suggested().join(', '),
        onImport: (password, domains) => _store!.importBytes(bytes, password, domains),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _editDomains(ClientCertInfo c) async {
    final domains = await _askDomains(AppLocalizations.of(context).tr('clientCertEditDomains'), c.domains.join(', '));
    if (domains == null) return;
    await _store?.setDomains(c.id, domains);
    if (mounted) setState(() {});
  }

  // ── Сертификат устройства (Android KeyChain) ──

  static const _ch = MethodChannel('ogneliss/native_http');

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Системное окно выбора сертификата (установленные на телефон и
  /// выданные организацией), затем домены серверов.
  Future<void> _addDevice() async {
    final l10n = AppLocalizations.of(context);
    final suggested = _suggested();
    String? alias;
    try {
      alias = await _ch.invokeMethod<String>('chooseClientAlias', {
        'host': suggested.isEmpty ? null : suggested.first,
        'port': 443,
      });
    } catch (e) {
      quietError('Сертификат устройства: окно выбора не открылось (${e.runtimeType})');
    }
    if (alias == null || !mounted) return;
    Map<String, dynamic>? info;
    try {
      info = await _ch.invokeMapMethod<String, dynamic>('clientAliasInfo', {'alias': alias});
    } catch (_) {}
    if (!mounted) return;
    final domains = await _askDomains(l10n.tr('clientCertDevice'), suggested.join(', '));
    if (domains == null) return;
    final notAfter = info?['notAfter'];
    await _store?.importDevice(
      alias,
      name: cnOf('${info?['subject'] ?? ''}') ?? alias,
      issuer: cnOf('${info?['issuer'] ?? ''}') ?? '',
      validTo: notAfter is int ? DateTime.fromMillisecondsSinceEpoch(notAfter) : null,
      domains: domains,
    );
    if (mounted) setState(() {});
  }

  /// Имя (CN) из X.500: «CN=Иванов Иван,O=Ромашка» → «Иванов Иван».
  static String? cnOf(String x500) => RegExp(r'(?:^|,)\s*CN=([^,]+)').firstMatch(x500)?.group(1)?.trim();

  /// Домены серверов; null — отмена или пусто.
  Future<List<String>?> _askDomains(String title, String initial) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.tr('clientCertDomains'),
            hintText: l10n.tr('clientCertDomainsHint'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    final domains = ClientCertStore.parseDomains(ctrl.text);
    ctrl.dispose();
    return ok == true && domains.isNotEmpty ? domains : null;
  }

  Widget _cert(ClientCertInfo c) {
    final l10n = AppLocalizations.of(context);
    final until = c.validTo == null ? '—' : DateFormat('dd.MM.yyyy').format(c.validTo!.toLocal());
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: Space.l, right: Space.s),
      leading: Icon(c.expired ? AppIcons.gpp_bad : AppIcons.badge,
          size: Sizes.iconRow,
          color: c.expired ? AppColors.errorText(context) : AppColors.successText(context)),
      title: Text(c.name),
      subtitle: Text(
        [
          '${c.expired ? l10n.tr('caExpired') : l10n.tr('caValidUntil')} $until',
          l10n.tr('clientCertFor').replaceAll('{domains}', c.domains.join(', ')),
          if (c.isDevice) l10n.tr('clientCertDeviceTag'),
          if (c.managed) l10n.tr('clientCertManaged'),
        ].join('\n'),
        style: TextStyle(color: AppColors.mutedText(context)),
      ),
      isThreeLine: true,
      trailing: c.managed
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: l10n.tr('clientCertEditDomains'),
                icon: const Icon(AppIcons.edit),
                onPressed: () => _editDomains(c),
              ),
              IconButton(
                tooltip: l10n.tr('delete'),
                icon: const Icon(AppIcons.delete),
                onPressed: () async {
                  await _store?.remove(c.id);
                  if (mounted) setState(() {});
                },
              ),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = _store;
    if (store == null) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedText(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.tr('clientCertTitle')),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
          child: Text(l10n.tr('clientCertDesc'), style: muted),
        ),
        SettingsGroup(children: [
          ...store.items.map(_cert),
          SettingsItem(
            icon: AppIcons.add,
            title: l10n.tr('clientCertAdd'),
            trailing: const SizedBox.shrink(),
            onTap: _add,
          ),
          // Android: сертификат из системного хранилища (KeyChain).
          if (_android)
            SettingsItem(
              icon: AppIcons.phone_android,
              title: l10n.tr('clientCertDevice'),
              subtitle: l10n.tr('clientCertDeviceDesc'),
              trailing: const SizedBox.shrink(),
              onTap: _addDevice,
            ),
        ]),
      ],
    );
  }
}

/// Пароль файла и домены серверов; ошибка — строкой в окне.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.fileName, required this.domains, required this.onImport});

  final String fileName;
  final String domains;
  final Future<ClientCertInfo> Function(String password, List<String> domains) onImport;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _password = TextEditingController();
  late final _domains = TextEditingController(text: widget.domains);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _domains.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    final l10n = AppLocalizations.of(context);
    final domains = ClientCertStore.parseDomains(_domains.text);
    if (domains.isEmpty) {
      setState(() => _error = l10n.tr('clientCertNoDomains'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onImport(_password.text, domains);
      if (mounted) Navigator.pop(context);
    } on ClientCertException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.tr(e.code == 'password' ? 'clientCertWrongPassword' : 'clientCertBadFile');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      icon: const Icon(AppIcons.badge),
      title: Text(widget.fileName, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(labelText: l10n.tr('clientCertPassword')),
            onSubmitted: (_) => _ok(),
          ),
          const SizedBox(height: Space.m),
          TextField(
            controller: _domains,
            decoration: InputDecoration(
              labelText: l10n.tr('clientCertDomains'),
              hintText: l10n.tr('clientCertDomainsHint'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.m),
            Text(_error!, style: TextStyle(color: AppColors.errorText(context))),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(l10n.tr('cancel'))),
        FilledButton(onPressed: _busy ? null : _ok, child: Text(l10n.tr('clientCertAdd'))),
      ],
    );
  }
}

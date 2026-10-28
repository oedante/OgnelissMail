// lib/features/settings/widgets/smime_section.dart
// Раздел ящика «Подпись и шифрование (S/MIME)»: загрузить сертификат
// (.p12/.pfx с паролем), посмотреть срок и издателя, подписывать и
// шифровать по умолчанию, удалить сертификат с телефона.

import 'dart:async';
import 'dart:typed_data';

import '../../../core/platform/file_pick.dart' show FilePick, FileType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/security/smime_service.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError;
import '../../../widgets/ui/settings_group.dart';

class SmimeSection extends ConsumerStatefulWidget {
  final AccountModel account;
  const SmimeSection({super.key, required this.account});

  @override
  ConsumerState<SmimeSection> createState() => _SmimeSectionState();
}

class _SmimeSectionState extends ConsumerState<SmimeSection> {
  SmimeCert? _cert;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final c = await ref.read(smimeServiceProvider).certificate(widget.account.id);
    if (!mounted) return;
    setState(() {
      _cert = c;
      _loading = false;
    });
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final file = await FilePick.file(type: FileType.custom, allowedExtensions: const ['p12', 'pfx']);
    if (file == null || !mounted) return;
    final Uint8List bytes = await file.readBytes();
    if (!mounted) return;
    final password = await _askPassword(l10n);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final cert = await ref.read(smimeServiceProvider).importPkcs12(widget.account.id, bytes, password);
      if (!mounted) return;
      setState(() {
        _cert = cert;
        _busy = false;
      });
    } on Pkcs12Exception catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showInlineError(l10n.tr(switch (e.code) {
        'password' => 'smimeWrongPassword',
        'nokey' => 'smimeNoKey',
        'unsupported' => 'smimeUnsupported',
        _ => 'smimeBadFile',
      }));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showInlineError('${l10n.tr('smimeBadFile')}: $e');
    }
  }

  Future<String?> _askPassword(AppLocalizations l10n) async {
    final c = TextEditingController();
    var hidden = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(l10n.tr('smimePassword')),
          content: TextField(
            controller: c,
            autofocus: true,
            obscureText: hidden,
            onSubmitted: (_) => Navigator.pop(ctx, true),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                tooltip: l10n.tr(hidden ? 'showPassword' : 'hidePassword'),
                icon: Icon(hidden ? AppIcons.visibility : AppIcons.visibility_off),
                onPressed: () => set(() => hidden = !hidden),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('ok'))),
          ],
        ),
      ),
    );
    final v = c.text;
    c.dispose();
    return ok == true ? v : null;
  }

  Future<void> _remove() async {
    await ref.read(smimeServiceProvider).removeIdentity(widget.account.id);
    if (mounted) setState(() => _cert = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _cert;
    final fmt = DateFormat('d MMM yyyy', l10n.localeCode);
    final expired = c?.notAfter != null && c!.notAfter!.isBefore(DateTime.now());
    final otherEmail = c != null && c.emails.isNotEmpty && !c.hasEmail(widget.account.email);
    final svc = ref.read(smimeServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('smimeSection'), help: l10n.tr('smimeHelp')),
        SettingsGroup(children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(Space.l),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (c == null)
            SettingsItem(
              icon: AppIcons.workspace_premium,
              title: l10n.tr('smimeImport'),
              subtitle: l10n.tr('smimeNoCert'),
              trailing: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _busy ? null : _import,
            )
          else ...[
            SettingsItem(
              icon: AppIcons.workspace_premium,
              color: expired ? Theme.of(context).colorScheme.error : null,
              title: c.commonName,
              subtitle: [
                if (c.notAfter != null)
                  expired
                      ? l10n.tr('smimeCertExpired').replaceAll('{date}', fmt.format(c.notAfter!.toLocal()))
                      : l10n
                          .tr('smimeCertValid')
                          .replaceAll('{date}', fmt.format(c.notAfter!.toLocal()))
                          .replaceAll('{issuer}', c.issuerName),
                if (otherEmail) l10n.tr('smimeCertOtherEmail').replaceAll('{email}', c.emails.join(', ')),
              ].join('\n'),
              trailing: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _busy ? null : _import,
            ),
            // По умолчанию для новых писем ящика; в письме меняется в шторке
            // грифа (значок замка в редакторе).
            SettingsSwitchItem(
              icon: AppIcons.verified_user,
              title: l10n.tr('smimeSignDefault'),
              subtitle: l10n.tr('smimeSignDefaultHint'),
              value: svc.signByDefault(widget.account.id),
              onChanged: expired
                  ? null
                  : (v) async {
                      await svc.setSignByDefault(widget.account.id, v);
                      if (mounted) setState(() {});
                    },
            ),
            SettingsSwitchItem(
              icon: AppIcons.shield,
              title: l10n.tr('smimeEncryptDefault'),
              subtitle: l10n.tr('smimeEncryptDefaultHint'),
              value: svc.encryptByDefault(widget.account.id),
              onChanged: expired
                  ? null
                  : (v) async {
                      await svc.setEncryptByDefault(widget.account.id, v);
                      if (mounted) setState(() {});
                    },
            ),
            SettingsItem(
              icon: AppIcons.delete,
              title: l10n.tr('smimeRemove'),
              color: AppColors.mutedText(context),
              onTap: _remove,
            ),
          ],
        ]),
      ],
    );
  }
}

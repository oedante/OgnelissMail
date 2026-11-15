// lib/features/compose/widgets/recipients_check.dart
// «Проверьте получателей» — внешние адресаты рабочего ящика. Одна проверка
// для редактора письма и для поручений (15.11.2026: поручение с рабочей
// почты ушло на yandex.ru без предупреждения, хотя оно включено, — Exchange
// Online отклонил письмо правилом организации).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mail_domains.dart' show mailDomainOf, sameOrgDomain;
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/own_addresses.dart';
import '../../settings/providers/feature_flags_provider.dart';

/// Домены адресатов вне организации ящика [account].
///
/// Только для рабочего ящика (Exchange): с личной почты (Gmail, Яндекс) все
/// получатели «внешние», и предупреждение было бы на каждом письме. Домены
/// организации — по всем адресам ящика (адрес входа, основной с сервера,
/// алиасы) и с поддоменами («msk.corp.ru» — свой для «corp.ru»).
Set<String> externalDomainsOf(AccountModel? account, Iterable<String> emails) {
  if (account == null || !account.isMsExchange) return const {};
  final org = OwnAddresses.domains(account);
  if (org.isEmpty) return const {};
  final out = <String>{};
  for (final e in emails) {
    final d = mailDomainOf(e);
    if (d.isNotEmpty && !org.any((o) => sameOrgDomain(d, o))) out.add(d);
  }
  return out;
}

/// Строка предупреждения о внешних доменах.
String externalRecipientsLine(Set<String> domains, AppLocalizations l10n) => l10n
    .tr('externalRecipientsWarn')
    .replaceAll('{domains}', domains.take(5).join(', '))
    .replaceAll('{ellipsis}', domains.length > 5 ? '…' : '');

/// Окно «Проверьте получателей» со строками [lines]. true — отправлять.
Future<bool> showRecipientsWarning(BuildContext context, List<String> lines, {String? sendLabel}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(AppIcons.warning, color: AppColors.accentOrangeText(ctx)),
      title: Text(l10n.tr('checkRecipients')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(sendLabel ?? l10n.tr('send'))),
      ],
    ),
  );
  return ok == true;
}

/// Письмо уйдёт внешним адресатам — спросить (если предупреждение включено
/// в настройках). true — отправлять.
Future<bool> confirmExternalRecipients(
  BuildContext context,
  AccountModel? account,
  Iterable<String> emails, {
  String? sendLabel,
}) async {
  if (!ProviderScope.containerOf(context, listen: false).read(featureFlagsProvider).confirmRecipients) return true;
  final ext = externalDomainsOf(account, emails);
  if (ext.isEmpty) return true;
  return showRecipientsWarning(context, [externalRecipientsLine(ext, AppLocalizations.of(context))],
      sendLabel: sendLabel);
}

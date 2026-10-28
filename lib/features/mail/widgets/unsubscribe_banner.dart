// lib/features/mail/widgets/unsubscribe_banner.dart
// Плашка «Рассылка · Отписаться» в письме с заголовком List-Unsubscribe.
// Отписка — только по нажатию; варианты — по тому, что дала рассылка:
// «в одно нажатие» (при пройденной проверке отправителя), страница отписки,
// письмо для отписки. При подозрении на подделку отправителя плашки нет.

import '../../../widgets/ui/banner_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/email_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/unsubscribe_service.dart';
import '../../../services/security/sender_safety_service.dart';
import '../../../widgets/ui/action_sheet.dart';

/// Отписались ли от отправителя (список в настройках, последние 500).
const kUnsubscribedSenders = 'unsubscribed_senders_v1';

bool isUnsubscribed(WidgetRef ref, String sender) =>
    (ref.read(sharedPrefsProvider).getStringList(kUnsubscribedSenders) ?? const []).contains(sender.toLowerCase());

Future<void> markUnsubscribed(WidgetRef ref, String sender) async {
  final prefs = ref.read(sharedPrefsProvider);
  final list = {...(prefs.getStringList(kUnsubscribedSenders) ?? const <String>[]), sender.toLowerCase()}.toList();
  await prefs.setStringList(kUnsubscribedSenders, list.length > 500 ? list.sublist(list.length - 500) : list);
}

/// Отписка: меню вариантов (в одно нажатие — только при подтверждённом
/// отправителе; страница отписки; письмо для отписки) и выполнение.
/// Возвращает null — отменили; true — отписались (или открыта страница /
/// письмо); false — рассылка не приняла запрос «в одно нажатие».
Future<bool?> runUnsubscribe(
    BuildContext context, WidgetRef ref, AccountModel account, EmailModel email, ListUnsubscribe info,
    {void Function(bool busy)? onBusy}) async {
  final l10n = AppLocalizations.of(context);
  final auth = senderAuthenticated(email.authResults);
  final sender = email.from.label;
  final choice = await showActionSheet<String>(
    context,
    title: l10n.tr('unsubscribeTitle').replaceAll('{name}', info.listName ?? sender),
    subtitle: auth ? null : l10n.tr('unsubscribeNotVerified'),
    leading: const Icon(AppIcons.unsubscribe),
    items: [
      if (info.oneClick && auth)
        ActionSheetItem(
          icon: AppIcons.unsubscribe,
          label: l10n.tr('unsubscribeNow'),
          subtitle: info.web.first.host,
          value: 'one',
        ),
      if (info.web.isNotEmpty)
        ActionSheetItem(
          icon: AppIcons.open_in_new,
          label: l10n.tr('unsubscribePage'),
          subtitle: info.web.first.host,
          value: 'web',
        ),
      if (info.mail.isNotEmpty)
        ActionSheetItem(
          icon: AppIcons.mail,
          label: l10n.tr('unsubscribeByMail'),
          subtitle: info.mail.first.path,
          value: 'mail',
        ),
    ],
  );
  if (choice == null || !context.mounted) return null;
  switch (choice) {
    case 'one':
      onBusy?.call(true);
      final ok = await UnsubscribeService.oneClick(info.web.first);
      onBusy?.call(false);
      if (ok) await markUnsubscribed(ref, email.from.email);
      return ok;
    case 'web':
      await launchUrl(info.web.first, mode: LaunchMode.externalApplication);
      await markUnsubscribed(ref, email.from.email);
      return true;
    case 'mail':
      final m = info.mail.first;
      final q = <String, String>{
        'to': m.path,
        'subject': m.queryParameters['subject'] ?? 'unsubscribe',
        if (m.queryParameters['body'] != null) 'body': m.queryParameters['body']!,
        'accountId': account.id,
      };
      if (!context.mounted) return null;
      unawaited(context.push(Uri(path: '/compose', queryParameters: q).toString()));
      await markUnsubscribed(ref, email.from.email);
      return true;
  }
  return null;
}

class UnsubscribeBanner extends ConsumerStatefulWidget {
  final AccountModel account;
  final EmailModel email;
  const UnsubscribeBanner({super.key, required this.account, required this.email});

  @override
  ConsumerState<UnsubscribeBanner> createState() => _UnsubscribeBannerState();
}

class _UnsubscribeBannerState extends ConsumerState<UnsubscribeBanner> {
  bool _danger = false;
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _done = isUnsubscribed(ref, widget.email.from.email);
    _checkSafety();
  }

  Future<void> _checkSafety() async {
    try {
      final report = await ref.read(senderSafetyServiceProvider).analyze(widget.account, widget.email);
      if (mounted && report.level == SafetyLevel.danger) setState(() => _danger = true);
    } catch (_) {}
  }

  Future<void> _unsubscribe(ListUnsubscribe info) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _error = null);
    final r = await runUnsubscribe(context, ref, widget.account, widget.email, info,
        onBusy: (b) {
          if (mounted) setState(() => _busy = b);
        });
    if (!mounted || r == null) return;
    setState(() {
      if (r) {
        _done = true;
      } else {
        _error = l10n.tr('unsubscribeFailed');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = ListUnsubscribe.parse(widget.email.listUnsubscribe);
    if (info == null || _danger) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final name = info.listName ?? widget.email.from.label;
    return Container(
      // Как у всех плашек письма: отступ сверху, общий отступ после группы
      // плашек даёт экран письма (раньше снизу был свой — двойной зазор).
      margin: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      constraints: const BoxConstraints(minHeight: bannerMinHeight),
      padding: bannerPadding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: Radii.chipAll,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Icon(AppIcons.unsubscribe, size: Sizes.iconInline, color: muted),
        const SizedBox(width: Space.s),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              _done ? l10n.tr('unsubscribeDone') : l10n.tr('mailingList').replaceAll('{name}', name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: muted),
            ),
            if (_error != null)
              Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.errorText(context))),
          ]),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (!_done)
          BannerButton(onPressed: () => _unsubscribe(info), label: l10n.tr('unsubscribe')),
      ]),
    );
  }
}

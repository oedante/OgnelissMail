// lib/features/compose/widgets/mail_tips_strip.dart
// Подсказки Exchange под адресатами (1.6.49, как в Outlook): у адресата
// включён автоответ — его текст («В отпуске до 25.10…») виден до отправки;
// ящик переполнен; большая рассылка или в ней внешние получатели. Данные —
// EWS GetMailTips (MailEngineService.mailTips); нет EWS — строки нет.
// Запрос — через секунду после того, как адресаты перестали меняться.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/ews/ews_mail_tips.dart';

class MailTipsStrip extends ConsumerStatefulWidget {
  final AccountModel? account;
  final List<String> emails;
  const MailTipsStrip({super.key, required this.account, required this.emails});

  @override
  ConsumerState<MailTipsStrip> createState() => _MailTipsStripState();
}

class _MailTipsStripState extends ConsumerState<MailTipsStrip> {
  Timer? _debounce;
  String _key = '';
  List<MailTip> _tips = const [];

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(MailTipsStrip old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _keyOf() {
    final list = [for (final e in widget.emails) e.trim().toLowerCase()]..sort();
    return '${widget.account?.id}|${list.join(',')}';
  }

  void _schedule() {
    final key = _keyOf();
    if (key == _key) return;
    _key = key;
    _debounce?.cancel();
    final account = widget.account;
    if (account == null || widget.emails.isEmpty) {
      if (_tips.isNotEmpty) setState(() => _tips = const []);
      return;
    }
    _debounce = Timer(const Duration(seconds: 1), () async {
      final got = await ref.read(mailEngineServiceProvider).mailTips(account, widget.emails);
      if (!mounted || key != _key) return;
      setState(() => _tips = got);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tips.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = <(IconData, String, bool)>[];
    for (final t in _tips) {
      final who = t.name.isNotEmpty ? t.name : t.email;
      if (t.autoReply != null) {
        rows.add((AppIcons.event_busy, l10n.tr('mailTipOof').replaceAll('{name}', who).replaceAll('{text}', t.autoReply!), false));
      }
      if (t.mailboxFull) rows.add((AppIcons.error, l10n.tr('mailTipFull').replaceAll('{name}', who), true));
      if (t.isBigList) {
        rows.add((AppIcons.group, l10n.tr('mailTipBig').replaceAll('{name}', who).replaceAll('{n}', '${t.totalMembers}'), false));
      }
      if (t.hasExternal) {
        rows.add((AppIcons.public, l10n.tr('mailTipExternal').replaceAll('{name}', who).replaceAll('{n}', '${t.externalMembers}'), false));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: Space.s),
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
        decoration: BoxDecoration(
          color: AppColors.infoBlue.withValues(alpha: 0.08),
          borderRadius: Radii.chipAll,
          border: Border.all(color: AppColors.infoBlue.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final (icon, text, warn) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon,
                    size: Sizes.iconInline,
                    color: warn ? AppColors.errorText(context) : AppColors.infoText(context)),
                const SizedBox(width: Space.s),
                Expanded(
                  child: Text(text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: warn ? AppColors.errorText(context) : theme.colorScheme.onSurface,
                      )),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

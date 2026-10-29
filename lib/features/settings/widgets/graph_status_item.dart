// lib/features/settings/widgets/graph_status_item.dart
// «Microsoft Graph» в настройках ящика Exchange Online (1.8.10): дала ли
// организация согласие на Graph. Microsoft отключает EWS в Exchange Online;
// адресная книга, подсказки MailTips, правила сервера и «Восстановить
// удалённые» теперь идут через Graph (движок, me.GraphEngine; токен —
// graph_tokens.dart). Нет согласия —
// нажатие ведёт ко входу заново (согласие просится при входе); не помогло —
// разрешение должен дать администратор организации.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_icons.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/oauth/graph_tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/widgets/account_auth_banner.dart' show reauthenticateFlow;

class GraphStatusItem extends ConsumerStatefulWidget {
  final AccountModel account;
  const GraphStatusItem({super.key, required this.account});

  @override
  ConsumerState<GraphStatusItem> createState() => _GraphStatusItemState();
}

class _GraphStatusItemState extends ConsumerState<GraphStatusItem> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Состояние ещё не известно — узнать (запрос токена, без окна входа).
    if (ref.read(graphTokensProvider).access(widget.account) == GraphAccess.unknown) unawaited(_check());
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await ref.read(graphTokensProvider).token(widget.account);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.read(graphTokensProvider).access(widget.account);
    final theme = Theme.of(context);
    final (String sub, Color? color) = _checking
        ? (l10n.tr('graphChecking'), null)
        : switch (state) {
            GraphAccess.ok => (l10n.tr('graphOk'), null),
            GraphAccess.noConsent => (l10n.tr('graphNoConsent'), theme.colorScheme.error),
            GraphAccess.unknown => (l10n.tr('graphUnknown'), null),
          };
    return SettingsItem(
      icon: AppIcons.hub,
      color: color,
      title: 'Microsoft Graph',
      subtitle: sub,
      trailing: HelpButton(text: l10n.tr('graphHint'), title: 'Microsoft Graph', compact: true),
      onTap: _checking
          ? null
          : state == GraphAccess.noConsent
              ? () => reauthenticateFlow(context, ref, widget.account)
              : () => unawaited(_check()),
    );
  }
}

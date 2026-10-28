// lib/features/settings/widgets/online_archive_item.dart
// «Архив Exchange» в настройках ящика (1.6.49): архив на сервере (online
// archive — куда политика хранения уносит старую почту) подключается
// отдельным ящиком: «Архив · Имя» со своими папками, только почта. Через EWS
// (у ящика ActiveSync — EWS того же сервера), с учётными данными основного.
//
// Нажатие — проверить, есть ли архив, и подключить. Итог проверки — строкой
// под названием (всплывающих сообщений в приложении нет): «Подключён»,
// «У ящика нет архива», «Нужен EWS». Подключён — нажатие открывает
// настройки ящика-архива (там же — удалить).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/ui/settings_group.dart';
import '../../mail/providers/mail_providers.dart';

class OnlineArchiveItem extends ConsumerStatefulWidget {
  final AccountModel account;
  const OnlineArchiveItem({super.key, required this.account});

  static String archiveIdOf(AccountModel a) => 'archive_${a.id}';

  @override
  ConsumerState<OnlineArchiveItem> createState() => _OnlineArchiveItemState();
}

class _OnlineArchiveItemState extends ConsumerState<OnlineArchiveItem> {
  bool _busy = false;
  String? _error;

  String get _stateKey => 'online_archive_state_${widget.account.id}';

  Future<void> _connect() async {
    final l10n = AppLocalizations.of(context);
    final account = widget.account;
    final prefs = ref.read(sharedPrefsProvider);
    final engine = ref.read(mailEngineServiceProvider);
    final accounts = ref.read(accountsProvider.notifier);
    final sync = ref.read(syncServiceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final has = await engine.hasOnlineArchive(account);
      if (has != true) {
        await prefs.setString(_stateKey, has == null ? 'noews' : 'none');
        AppLogger.info('Архив Exchange ${AppLogger.mask(account.email)}: ${has == null ? 'нет EWS' : 'нет архива'}');
        return;
      }
      final url = await engine.directoryEwsUrl(account);
      final archive = AccountModel(
        id: OnlineArchiveItem.archiveIdOf(account),
        type: AccountType.exchange,
        email: account.email,
        displayName: '${l10n.tr('onlineArchive')} · ${account.displayName}',
        username: account.username.trim().isNotEmpty ? account.username : account.email,
        domain: account.domain,
        exchangeServer: account.exchangeServer,
        ewsUrl: (account.ewsUrl ?? '').trim().isNotEmpty ? account.ewsUrl : url,
        exchangeAuthMethod: account.exchangeAuthMethod,
        // Учётные данные — основного ящика; запросы — к его же ящику.
        sharedMailboxEmail: account.email,
        parentAccountId: account.id,
        // Архив меняется редко: раз в час, без push.
        syncInterval: SyncInterval.hour1,
        createdAt: DateTime.now(),
      );
      await accounts.addAccount(archive);
      await prefs.remove(_stateKey);
      AppLogger.info('Архив Exchange ${AppLogger.mask(account.email)}: подключён');
      unawaited(sync.syncAccount(archive).catchError((Object e) {
        AppLogger.warning('Архив Exchange: первая синхронизация — $e');
      }));
    } catch (e) {
      AppLogger.warning('Архив Exchange: $e');
      if (mounted) setState(() => _error = '${l10n.tr('error')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final id = OnlineArchiveItem.archiveIdOf(widget.account);
    final connected = ref.watch(accountsProvider).any((a) => a.id == id);
    final state = ref.read(sharedPrefsProvider).getString(_stateKey);
    final subtitle = connected
        ? l10n.tr('archiveConnected')
        : _error ??
            switch (state) {
              'none' => l10n.tr('archiveNone'),
              'noews' => l10n.tr('archiveNeedsEws'),
              _ => l10n.tr('archiveSub'),
            };
    return SettingsItem(
      icon: AppIcons.inventory_2,
      title: l10n.tr('onlineArchive'),
      subtitle: subtitle,
      hint: l10n.tr('archiveHelp'),
      trailing: _busy
          ? const SizedBox.square(dimension: Sizes.iconRow, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: _busy
          ? null
          : connected
              ? () => context.push('/settings/account/${Uri.encodeComponent(id)}')
              : () => unawaited(_connect()),
    );
  }
}

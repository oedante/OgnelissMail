// lib/features/auth/screens/shared_mailbox_screen.dart
//
// Добавление общего или делегированного почтового ящика.
//
// Такой ящик не имеет собственного пароля: доступ выдаётся администратором на
// сервере, а подключение идёт под учётными данными основного аккаунта. Поэтому
// от пользователя нужен только адрес ящика — логин и пароль не запрашиваются.
//
// Типичные случаи: общий ящик подразделения (склад@, снабжение@) и
// делегированный доступ секретаря к ящику руководителя.
//
// 1.6.49:
//   · ящик ActiveSync тоже может открыть общий ящик — через EWS того же
//     сервера (если он отвечает); раньше — только ящики с EWS;
//   · адрес — из адресной книги (кнопка у поля), не только вручную;
//   · до добавления — проверка доступа: к почте и к календарю. Нет доступа
//     ни к чему — понятная строка вместо ящика, который не откроется; доступ
//     только к календарю (частый случай у секретаря) — ящик добавляется как
//     календарь, об этом сказано здесь же.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_logger.dart';
import '../../../data/models/account_model.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/own_addresses.dart';
import '../../../services/mail/shared_access.dart';
import '../../compose/widgets/people_picker_sheet.dart';
import '../../mail/providers/mail_providers.dart';
import '../../../widgets/common/text_scale_cap.dart';

class SharedMailboxScreen extends ConsumerStatefulWidget {
  /// Основной ящик (из настроек ящика); null — активный.
  final String? parentId;
  const SharedMailboxScreen({super.key, this.parentId});

  @override
  ConsumerState<SharedMailboxScreen> createState() => _SharedMailboxScreenState();
}

class _SharedMailboxScreenState extends ConsumerState<SharedMailboxScreen> {
  final _emailController = TextEditingController();
  AccountModel? _parent;
  bool _busy = false;
  String? _error;

  /// Ящик добавлен только как календарь — строка-итог и «Готово».
  String? _calendarOnlyDone;

  @override
  void initState() {
    super.initState();
    // Основной аккаунт: тот, из настроек которого открыли экран; иначе —
    // активный (чаще всего доступ к общему ящику выдан именно ему).
    final accounts = ref.read(accountsProvider);
    _parent = accounts.where((a) => a.id == widget.parentId).firstOrNull ?? ref.read(activeAccountProvider);
    if (_parent != null && (_parent!.isSharedMailbox || _parent!.isOnlineArchive)) {
      _parent = accounts.where((a) => a.id == _parent!.parentAccountId).firstOrNull ?? _parent;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Адрес из адресной книги организации.
  Future<void> _pickFromDirectory() async {
    final picked = await showPeoplePicker(context, account: _parent);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _emailController.text = picked.first.email.trim();
      _error = null;
    });
  }

  Future<void> _add(AppLocalizations l10n) async {
    final email = _emailController.text.trim();
    final parent = _parent;
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l10n.tr('invalidEmail'));
      return;
    }
    if (parent == null) {
      setState(() => _error = l10n.tr('noActiveAccount'));
      return;
    }
    if (OwnAddresses.isMine(parent, email)) {
      setState(() => _error = l10n.tr('sharedIsOwn'));
      return;
    }

    setState(() { _busy = true; _error = null; });
    try {
      // Общий ящик работает через EWS: там есть адресация к чужому ящику.
      // У ящика ActiveSync — EWS того же сервера (1.6.49).
      final access = await ref.read(mailEngineServiceProvider).checkSharedAccess(parent, email);
      if (!mounted) return;
      if (access == null) {
        setState(() => _error = l10n.tr('sharedNeedsEws'));
        return;
      }
      if (!access.mail && !access.calendar) {
        setState(() => _error = l10n.tr('sharedNoAccess').replaceAll('{email}', email));
        return;
      }
      final id = 'shared_${DateTime.now().millisecondsSinceEpoch}';
      final ewsUrl = (parent.ewsUrl ?? '').trim().isNotEmpty ? parent.ewsUrl : access.ewsUrl;
      await ref.read(accountsProvider.notifier).addAccount(
            AccountModel(
              id: id,
              syncInterval: SyncInterval.minutes15,
              // Только EWS умеет адресоваться к чужому ящику. Если основной
              // аккаунт работает по ActiveSync (гибрид EAS + EWS), общий ящик
              // всё равно должен ходить по EWS: иначе синхронизация пошла бы
              // по EAS от имени общего адреса и не подключилась бы вовсе.
              type: parent.usesEws ? parent.type : AccountType.exchange,
              email: email,
              displayName: email.split('@').first,
              // Пустой логин означал бы вход по адресу ОБЩЕГО ящика —
              // подставляем адрес основного.
              username: parent.username.trim().isNotEmpty ? parent.username : parent.email,
              domain: parent.domain,
              exchangeServer: parent.exchangeServer,
              ewsUrl: ewsUrl,
              exchangeAuthMethod: parent.exchangeAuthMethod,
              // Пометка, из-за которой запросы адресуются другому ящику,
              // а учётные данные берутся у основного аккаунта.
              sharedMailboxEmail: email,
              parentAccountId: parent.id,
              createdAt: DateTime.now(),
            ),
          );
      if (!access.mail) {
        await SharedAccess.setCalendarOnly(ref.read(sharedPrefsProvider), id, true);
      }
      AppLogger.info('Добавлен общий ящик ${AppLogger.mask(email)} (основной: ${AppLogger.mask(parent.email)}; '
          'почта ${access.mail ? 'да' : 'нет'}, календарь ${access.calendar ? 'да' : 'нет'})');
      if (!mounted) return;
      if (access.mail) {
        context.pop();
      } else {
        setState(() => _calendarOnlyDone = l10n.tr('sharedCalendarOnly').replaceAll('{email}', email));
      }
    } catch (e) {
      AppLogger.error('Не удалось добавить общий ящик', e);
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accounts =
        ref.watch(accountsProvider).where((a) => !a.isSharedMailbox && !a.isOnlineArchive && a.isMsExchange).toList();
    final done = _calendarOnlyDone;

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('addSharedMailbox')))),
      body: ListView(
        padding: const EdgeInsets.all(Space.l),
        children: [
          Text(l10n.tr('sharedMailboxHint'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: Space.xl),

          // Основной аккаунт: под его учётными данными пойдут запросы.
          if (accounts.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: accounts.any((a) => a.id == _parent?.id) ? _parent?.id : null,
              decoration: InputDecoration(
                labelText: l10n.tr('accessVia'),
                prefixIcon: const Icon(AppIcons.person),
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.email)),
              ],
              onChanged: done != null
                  ? null
                  : (v) => setState(() => _parent = accounts.where((a) => a.id == v).firstOrNull ?? _parent),
            ),
            const SizedBox(height: Space.l),
          ],

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            enabled: done == null,
            decoration: InputDecoration(
              labelText: l10n.tr('sharedMailboxEmail'),
              hintText: 'sklad@company.ru',
              prefixIcon: const Icon(AppIcons.alternate_email),
              // Адрес — из адресной книги (1.6.49).
              suffixIcon: IconButton(
                tooltip: l10n.tr('sharedPickPerson'),
                icon: const Icon(AppIcons.contacts),
                onPressed: _busy || done != null ? null : () => unawaited(_pickFromDirectory()),
              ),
              errorText: _error,
              errorMaxLines: 4,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _busy ? null : _add(l10n),
          ),
          const SizedBox(height: Space.xl),

          if (done != null) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(AppIcons.event, color: AppColors.successText(context)),
              const SizedBox(width: Space.m),
              Expanded(child: Text(done, style: theme.textTheme.bodyMedium)),
            ]),
            const SizedBox(height: Space.l),
            FilledButton(
              onPressed: () => context.pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.m),
                child: Text(l10n.tr('done')),
              ),
            ),
          ] else
            FilledButton(
              onPressed: _busy ? null : () => _add(l10n),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.m),
                child: _busy
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.tr('sharedCheckAndAdd')),
              ),
            ),

          const SizedBox(height: Space.xl),
          Text(l10n.tr('sharedMailboxNote'), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// lib/features/settings/screens/account_screen.dart
// Экран одного аккаунта (этап 4, Ф4 UI_REDESIGN.md): все настройки ящика в
// одном месте — тип, подпись, адреса отправки, синхронизация папок, правила,
// автоответ и категории Exchange, пароль календаря, удаление. Раньше они были
// разбросаны по общему меню настроек и меню ⋮ строки аккаунта и работали с
// «активным» ящиком, а не с тем, который хотели настроить.

import '../../../services/sync/sync_schedule.dart';
import '../../../services/notifications/account_notify_mode.dart';
import 'delivery_schedule_screen.dart' show scheduleDaysLabel;
import '../../../services/device/phone_mirror_service.dart';
import '../../../core/constants/app_constants.dart' show kRulesAndCategoriesEnabled;
import '../../../core/utils/text_safe.dart';
import 'dart:async';
import '../../../core/theme/app_icons.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../../../core/logging/app_logger.dart';

import 'package:flutter/material.dart';
import '../../../core/platform/file_pick.dart' show FilePick, FileType;
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../../mail/providers/account_look.dart';
import '../../../widgets/common/person_photo.dart' show photoImage, PhotoRing;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/certificate_pinning_service.dart';
import '../../../core/security/trusted_ca_store.dart';
import '../../../services/sync/sync_service.dart';
import '../../../widgets/common/sync_progress_indicator.dart' show syncStatusProvider;
import '../../../services/background/foreground_sync_controller.dart';
import '../../../widgets/common/eas_compat_switch.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/utils/app_date_format.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../services/mail/shared_access.dart';
import '../widgets/online_archive_item.dart';
import '../widgets/special_folder_item.dart';
import '../widgets/server_filters_item.dart' show serverFilterItems;
import '../../../services/mail/special_folders.dart' show SpecialKind;
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/signature_service.dart';
import '../../../services/mail/compose_style_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../services/security/eas_policy_store.dart';
import '../../../services/sync/imap_push_service.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/dav/dav_pim_service.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../mail/providers/mail_providers.dart';
import '../../mail/widgets/account_auth_banner.dart' show reauthenticateFlow;
import '../providers/settings_provider.dart';
import 'accounts_settings_screen.dart';
import '../widgets/dav_pim_item.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/confirm_dialog.dart' show confirmDestructive;
import '../../contacts/person_names.dart' show personNamesProvider;
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import '../../../widgets/ui/settings_group.dart';
import '../widgets/smime_section.dart';

/// Пересинхронизация запущена — строка у пункта вместо всплывающего
/// уведомления (всплывающих сообщений в приложении нет).
final _resyncStartedProvider = StateProvider.family<bool, String>((ref, id) => false);

/// Режим уведомлений ящика (1.6.45) — из prefs, меняется в [_pickNotifyMode].
final _notifyModeProvider = StateProvider.family<AccountNotifyMode, String>(
    (ref, id) => AccountNotify.of(ref.read(sharedPrefsProvider), id));

class AccountScreen extends ConsumerWidget {
  final String accountId;

  /// «Расширенные настройки» ящика (1.8.0, решение владельца 26.10.2026:
  /// «часть настроек аккаунта … вынести в разделы „Расширенные
  /// настройки“»): подключение, сервер и сертификаты, папки «Архив» и
  /// «Спам», общий ящик, синхронизация с телефоном, S/MIME, полная
  /// пересинхронизация. На основном экране — почта, синхронизация и вид.
  final bool advanced;
  const AccountScreen({super.key, required this.accountId, this.advanced = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final account = ref.watch(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    if (account == null) {
      // Аккаунт удалили (в том числе с этого экрана) — показывать нечего.
      return Scaffold(appBar: TextScaleCapBar(child: AppBar()), body: Center(child: Text(l10n.tr('noAccounts'))));
    }
    final settings = ref.watch(settingsProvider);
    final isPrimary = account.isPrimary || settings.activeAccountId == account.id;
    final q = '?accountId=${Uri.encodeQueryComponent(account.id)}';
    final dav = DavPimService.providerOf(account);

    if (advanced) return _advanced(context, ref, account, l10n, theme);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(account.displayName.isNotEmpty ? account.displayName : account.email))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          _Header(account: account, typeLabel: accountTypeLabel(account.type, l10n), isPrimary: isPrimary),
          const SizedBox(height: Space.l),

          // ── Письма ──
          SettingsSectionTitle(l10n.tr('accSectionMail')),
          SettingsGroup(children: [
            // Имя отправителя: в поле «От» и в подписи ({name}). У Gmail и
            // Яндекса адресной книги организации нет — имя задаётся здесь.
            // Заданное вручную синхронизация не перезаписывает (она меняет
            // имя, только пока оно совпадает с логином).
            SettingsItem(
              icon: AppIcons.badge,
              title: l10n.tr('senderName'),
              subtitle: account.displayName.trim().isNotEmpty &&
                      account.displayName.trim().toLowerCase() != account.email.toLowerCase()
                  ? account.displayName
                  : l10n.tr('senderNameEmpty'),
              onTap: () => _editSenderName(context, ref, account),
            ),
            Builder(builder: (context) {
              // Какие подписи вставляются: для новых писем и для ответов.
              final all = ref.watch(signaturesProvider);
              final ch = ref.watch(signatureChoicesProvider);
              String name(bool reply) =>
                  SignatureChoicesNotifier.resolve(all, ch, account.id, reply: reply)?.name ??
                  l10n.tr('noSignature');
              return SettingsItem(
                icon: AppIcons.draw,
                title: l10n.tr('signatures'),
                subtitle: '${name(false)} · ${name(true)}',
                onTap: () => context.push('/settings/signatures$q'),
              );
            }),
            // Автоответ — у всех ящиков: Exchange — на сервере, остальные —
            // телефоном и ссылкой на настройки сайта.
            SettingsItem(
              icon: AppIcons.beach_access,
              title: l10n.tr('autoReply'),
              onTap: () => context.push('/settings/auto-reply$q'),
            ),
            // «Отвечать от имени» (1.6.27): адреса отправки — общий ящик
            // отдела, диспетчерская, ящик руководителя у секретаря.
            SettingsItem(
              icon: AppIcons.alternate_email,
              title: l10n.tr('aliases'),
              subtitle: l10n.tr('aliasesSub'),
              onTap: () => manageAliases(context, ref, account),
            ),
            if (kRulesAndCategoriesEnabled)
            SettingsItem(
              icon: AppIcons.rule,
              title: l10n.tr('rules'),
              onTap: () => context.push('/settings/rules$q'),
            ),
            // Фильтры на сервере — у каждого ящика свои (1.7.3): Sieve у
            // IMAP, правила Exchange через EWS, у служб без фильтров по
            // протоколу — где их настроить.
            ...serverFilterItems(context, ref, account),
          ]),

          // ── Синхронизация ──
          SettingsSectionTitle(l10n.tr('accSectionSync')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.date_range,
              title: l10n.tr('syncPeriod'),
              subtitle: _periodLabel(account.syncDays, l10n),
              onTap: () => _pickPeriod(context, ref, account),
            ),
            SettingsItem(
              icon: AppIcons.schedule,
              title: l10n.tr('checkMail'),
              subtitle: account.syncInterval == SyncInterval.scheduled
                  ? '${_intervalLabel(account.syncInterval, l10n)} · ${_scheduleSummary(l10n)}'
                  : _intervalLabel(account.syncInterval, l10n),
              onTap: () => _pickInterval(context, ref, account),
            ),
            // Уведомления этого ящика (1.6.45): все, без звука, только VIP.
            Builder(builder: (context) {
              final mode = ref.watch(_notifyModeProvider(account.id));
              return SettingsItem(
                icon: AppIcons.notifications,
                title: l10n.tr('accNotify'),
                subtitle: l10n.tr(AccountNotify.labelKey(mode)),
                onTap: () => _pickNotifyMode(context, ref, account, mode),
              );
            }),
            SettingsSwitchItem(
              icon: AppIcons.wifi,
              title: l10n.tr('wifiOnlyAcc'),
              subtitle: l10n.tr('wifiOnlyAccDesc'),
              value: account.syncOnlyWifi,
              onChanged: (v) => ref
                  .read(accountsProvider.notifier)
                  .updateAccount(account.copyWith(syncOnlyWifi: v)),
            ),
            SettingsItem(
              icon: AppIcons.folder_copy,
              title: l10n.tr('folderSync'),
              onTap: () => context.push('/settings/folder-sync$q'),
            ),
            // Пароль приложения для календаря и контактов — только у ящиков,
            // которым он нужен (1.7.2+110; раньше — у всех, с текстом про
            // Яндекс).
            if (dav != null && dav != 'google') DavPimItem(account: account),
          ]),

          // ── Вид ящика ──
          SettingsSectionTitle(l10n.tr('accSectionLook')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.palette,
              title: l10n.tr('accountColor'),
              trailing: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(color: Color(account.colorValue), shape: BoxShape.circle),
              ),
              onTap: () => _pickColor(context, ref, account),
            ),
            SettingsItem(
              icon: AppIcons.account_circle,
              title: l10n.tr('accountPhoto'),
              subtitle: l10n.tr(ref.watch(manualPhotosProvider).contains(account.id)
                  ? 'accountPhotoManual'
                  : (account.avatarUrl != null ? 'accountPhotoAuto' : 'accountPhotoNone')),
              trailing: PhotoRing(
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(account.colorValue),
                  foregroundImage: photoImage(account.avatarUrl),
                  child: Text(account.email.isEmpty ? '?' : initialOf(account.email),
                      style: TextStyle(fontSize: 12, color: onAccountColor(Color(account.colorValue)))),
                ),
              ),
              onTap: () => _pickPhoto(context, ref, account),
            ),
            Builder(builder: (context) {
              final style = ComposeStylesNotifier.styleFor(ref.watch(composeStylesProvider), account.id);
              return SettingsItem(
                icon: AppIcons.text_fields,
                title: l10n.tr('composeStyle'),
                subtitle: style.label,
                onTap: () => _pickComposeStyle(context, ref, account.id),
              );
            }),
            if (!isPrimary)
              SettingsItem(
                icon: AppIcons.star,
                title: l10n.tr('makePrimary'),
                onTap: () async {
                  await ref.read(accountsProvider.notifier).setPrimary(account.id);
                  await ref.read(settingsProvider.notifier).setActiveAccountId(account.id);
                },
              ),
          ]),

          const SizedBox(height: Space.l),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.tune,
              title: l10n.tr('advancedSettings'),
              subtitle: l10n.tr(account.isMsExchange || account.usesEas || account.usesEws
                  ? 'accAdvancedDescExchange'
                  : 'accAdvancedDesc'),
              onTap: () => context.push('/settings/account/${Uri.encodeComponent(account.id)}/advanced'),
            ),
          ]),
          const SizedBox(height: Space.l),

          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.delete,
              title: l10n.tr('deleteAccount'),
              color: theme.colorScheme.error,
              onTap: () async {
                final ok = await confirmDeleteAccount(context, account.email);
                if (ok != true || !context.mounted) return;
                // Сразу назад: ящик исчезает из списка мгновенно, данные
                // стираются следом (раньше экран ждал сети и базы, и казалось,
                // что первое нажатие не сработало).
                final notifier = ref.read(accountsProvider.notifier);
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                unawaited(notifier.removeAccount(account.id));
              },
            ),
          ]),
        ],
      ),
    );
  }

  /// «Расширенные настройки» ящика: подключение, папки, общий ящик,
  /// синхронизация с телефоном, защита и S/MIME, полная пересинхронизация.
  Widget _advanced(BuildContext context, WidgetRef ref, AccountModel account, AppLocalizations l10n, ThemeData theme) {
    final policy = account.usesEas
        ? EasPolicyStore(ref.watch(sharedPrefsProvider)).effective([account.id])
        : null;
    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(l10n.tr('advancedSettings')),
          Text(account.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          // ── Подключение ──
          SettingsSectionTitle(l10n.tr('accSectionConnection')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.dns,
              title: l10n.tr('server'),
              subtitle: _serverText(account, l10n),
              onTap: account.usesOAuthTokens ? null : () => _editServer(context, ref, account),
            ),
            SettingsItem(
              icon: AppIcons.key,
              title: l10n.tr('signInAgain'),
              subtitle: account.usesOAuthTokens ? null : l10n.tr('signInAgainDesc'),
              onTap: () => reauthenticateFlow(context, ref, account),
            ),
            // Совместимость со шлюзом — рядом с остальными данными подключения
            // (раньше только в списке ящиков и на экране входа).
            if (account.isMsExchange || account.usesEas || account.usesEws)
              EasCompatSwitch(
                accountId: account.id,
                contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                onChanged: () {
                  ref.read(mailEngineServiceProvider).disconnect(account.id);
                  showInlineError(l10n.tr('easCompatUaReconnect'));
                },
              ),
            // ЦС Минцифры — только для серверов этого ящика. На других
            // языках интерфейса — только если уже включено (чтобы можно было
            // выключить): пункт о российских сертификатах пугал пользователей
            // из других стран (1.7.3, решение владельца 25.10.2026).
            if (TrustedCaStore.instance case final store?
                when l10n.isRussian || store.bundledEnabled || store.mincifryForAccount(account.id))
              StatefulBuilder(
                builder: (ctx, setLocal) => SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                  secondary: Icon(AppIcons.verified_user, color: theme.colorScheme.primary),
                  title: Text(l10n.tr('caMincifry')),
                  subtitle: Text(store.bundledEnabled
                      ? l10n.tr('caMincifryOnForAll')
                      : l10n.tr('caMincifryAccountDesc')),
                  value: store.bundledEnabled || store.mincifryForAccount(account.id),
                  onChanged: store.bundledEnabled
                      ? null
                      : (v) async {
                          await store.setMincifryForAccount(account.id, v);
                          if (!ctx.mounted) return;
                          setLocal(() {});
                          // Подключение с новым доверием — сразу проверка почты.
                          if (v) unawaited(ref.read(syncServiceProvider).syncAccount(account));
                        },
                ),
              ),
          ]),

          // ── Ящик ──
          SettingsSectionTitle(l10n.tr('accSectionAccount')),
          SettingsGroup(children: [
            SettingsItem(
              icon: account.isWork ? AppIcons.work : AppIcons.person,
              title: l10n.tr('accountKind'),
              subtitle: l10n.tr(account.accountKind == null
                  ? 'accountKindAuto'
                  : account.isWork ? 'accountKindWork' : 'accountKindPersonal'),
              onTap: () => pickAccountKind(context, ref, account),
            ),
            // Куда «В архив» и «В спам» (1.7.2+106): Exchange не помечает эти
            // папки — узнаём по названию, можно выбрать вручную.
            if (!account.isOnlineArchive) ...[
              SpecialFolderItem(account: account, kind: SpecialKind.archive),
              SpecialFolderItem(account: account, kind: SpecialKind.junk),
            ],
            // Общий или делегированный ящик целиком (папки, письма): раньше
            // экран был, но открыть его было неоткуда.
            if (account.isMsExchange && !account.isSharedMailbox && !account.isOnlineArchive) ...[
              SettingsItem(
                icon: AppIcons.supervisor_account,
                title: l10n.tr('addSharedMailbox'),
                subtitle: l10n.tr('sharedMailboxSub'),
                onTap: () => context.push(Uri(path: '/settings/shared-mailbox', queryParameters: {'parent': account.id}).toString()),
              ),
              // Архив Exchange отдельным ящиком (1.6.49).
              OnlineArchiveItem(account: account),
            ],
            // Общий ящик без доступа к почте — только календарь (1.6.49).
            if (account.isSharedMailbox &&
                !account.isOnlineArchive &&
                SharedAccess.calendarOnly(ref.read(sharedPrefsProvider), account.id))
              SettingsItem(
                icon: AppIcons.event,
                title: l10n.tr('sharedCalendarOnlyTitle'),
                subtitle: l10n.tr('sharedCalendarOnlySub'),
                onTap: null,
              ),
            if (account.isMsExchange && kRulesAndCategoriesEnabled)
              // Список своих категорий скрыт вместе с «Категориями»
              // (kRulesAndCategoriesEnabled); категории в письме остаются.
              SettingsItem(
                icon: AppIcons.label,
                title: l10n.tr('outlookCategories'),
                onTap: () => context.push('/settings/categories'),
              ),
          ]),

          // ── В телефоне: контакты и календарь ящика ──
          _PhoneMirrorSection(account: account),

          // ── Безопасность ──
          SettingsSectionTitle(l10n.tr('accSectionSecurity')),
          SettingsGroup(children: [
            if (policy != null)
              SettingsItem(
                icon: AppIcons.policy,
                title: l10n.tr('orgPolicy'),
                subtitle: _policyText(policy, l10n),
                onTap: null,
              ),
            _ServerCertItem(account: account),
            SettingsItem(
              icon: AppIcons.verified_user,
              title: l10n.tr('connectionSecurity'),
              onTap: () => context.push('/settings/security'),
            ),
          ]),

          // ── Подпись и шифрование писем (S/MIME) ──
          SmimeSection(account: account),

          // ── Данные ──
          SettingsSectionTitle(l10n.tr('accSectionData')),
          SettingsGroup(children: [
            // Полная пересинхронизация — красная и с подтверждением: она
            // удаляет данные ящика на устройстве (09.10.2026).
            SettingsItem(
              icon: AppIcons.sync,
              color: theme.colorScheme.error,
              title: l10n.tr('fullResync'),
              // Ошибка последней синхронизации — здесь, у ящика: раньше её
              // было видно только в журнале.
              subtitle: '${ref.watch(_resyncStartedProvider(account.id)) ? '${l10n.tr('resyncStarted')}\n' : ''}'
                  '${l10n.tr('lastSynced')}: ${_lastSync(context, ref.watch(lastSyncAtProvider(account.id)).value, l10n)}'
                  '${(() {
                    ref.watch(syncStatusProvider); // обновлять после синхронизации
                    final err = ref.read(syncServiceProvider).accountError(account.id);
                    return err == null ? '' : '\n⚠ $err';
                  })()}',
              onTap: () async {
                final ok = await confirmDestructive(context,
                    title: l10n.tr('fullResyncConfirmTitle'),
                    message: l10n.tr('fullResyncConfirmBody').replaceAll('{email}', account.email),
                    action: l10n.tr('fullResyncConfirmAction'));
                if (!ok || !context.mounted) return;
                // Контейнер — до ожидания: пересинхронизация меняет список
                // ящиков, экран за это время перестраивается, и ref после
                // await бросал «Using ref when a widget is unmounted»
                // (журнал 11.10.2026, 17:17).
                final container = ProviderScope.containerOf(context, listen: false);
                await container.read(accountsProvider.notifier).fullResync(account.id);
                container.invalidate(personNamesProvider);
                container.read(_resyncStartedProvider(account.id).notifier).state = true;
              },
            ),
          ]),
        ],
      ),
    );
  }

  static String _intervalLabel(SyncInterval i, AppLocalizations l10n) => switch (i) {
        SyncInterval.push => l10n.tr('checkInstant'),
        SyncInterval.minutes5 => l10n.tr('checkEvery').replaceAll('{n}', '5'),
        SyncInterval.minutes15 => l10n.tr('checkEvery').replaceAll('{n}', '15'),
        SyncInterval.minutes30 => l10n.tr('checkEvery').replaceAll('{n}', '30'),
        SyncInterval.hour1 => l10n.tr('checkHourly'),
        SyncInterval.manual => l10n.tr('checkManual'),
        SyncInterval.scheduled => l10n.tr('checkScheduled'),
      };

  /// Пояснение к «По расписанию»: «Мгновенно 7:00–19:00 пн–пт, иначе раз в 15 мин».
  static String _scheduleSummary(AppLocalizations l10n) => l10n
      .tr('checkScheduledDesc')
      .replaceAll('{window}', SyncSchedule.windowLabel())
      .replaceAll('{days}', scheduleDaysLabel(SyncSchedule.days, l10n))
      .replaceAll('{n}', '${SyncSchedule.offMinutes}');

  Future<void> _pickNotifyMode(
      BuildContext context, WidgetRef ref, AccountModel account, AccountNotifyMode current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppSheet<AccountNotifyMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.tr('accNotify'), style: Theme.of(ctx).textTheme.titleMedium),
                trailing: HelpButton(text: l10n.tr('accNotifyHint'), title: l10n.tr('accNotify')),
              ),
              for (final m in AccountNotifyMode.values)
                ListTile(
                  title: Text(l10n.tr(AccountNotify.labelKey(m))),
                  subtitle: Text(l10n.tr('${AccountNotify.labelKey(m)}Desc')),
                  trailing: m == current
                      ? Icon(AppIcons.check, color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await AccountNotify.set(ref.read(sharedPrefsProvider), account.id, picked);
    ref.read(_notifyModeProvider(account.id).notifier).state = picked;
  }

  Future<void> _pickInterval(BuildContext context, WidgetRef ref, AccountModel account) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showAppSheet<SyncInterval>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(l10n.tr('checkMail'), style: Theme.of(ctx).textTheme.titleMedium),
                trailing: HelpButton(text: l10n.tr('checkMailHint'), title: l10n.tr('checkMail')),
              ),
              for (final i in const [
                SyncInterval.push,
                SyncInterval.scheduled,
                SyncInterval.minutes15,
                SyncInterval.minutes30,
                SyncInterval.hour1,
                SyncInterval.manual,
              ])
                ListTile(
                  title: Text(_intervalLabel(i, l10n)),
                  // «По расписанию» — с текущим окном; настройка — в своём экране.
                  subtitle: i == SyncInterval.scheduled ? Text(_scheduleSummary(l10n)) : null,
                  trailing: i == account.syncInterval
                      ? Icon(AppIcons.check, color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, i),
                ),
              ListTile(
                leading: const Icon(AppIcons.schedule),
                title: Text(l10n.tr('scheduleSetup')),
                trailing: const Icon(AppIcons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/settings/delivery-schedule');
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == account.syncInterval) return;
    final updated = account.copyWith(syncInterval: picked);
    await ref.read(accountsProvider.notifier).updateAccount(updated);
    // Push включаем и выключаем сразу, не дожидаясь перезапуска.
    final push = ref.read(imapPushServiceProvider);
    if (SyncSchedule.pushNow(updated)) {
      await push.start();
    } else {
      await push.stopForAccount(account.id);
    }
    // Фоновый сервис нужен только ящикам с мгновенной доставкой.
    final st = ref.read(settingsProvider);
    final ctl = ref.read(foregroundSyncControllerProvider);
    if (keepAliveNeeded(
        keepAliveSetting: st.backgroundKeepAlive,
        globalInterval: st.syncIntervalMinutes,
        accounts: ref.read(accountsProvider))) {
      await ctl.start();
    } else {
      await ctl.stop();
    }
  }

  static String _serverText(AccountModel a, AppLocalizations l10n) {
    if (a.isOAuth) {
      return l10n.tr('serverViaProvider').replaceAll('{name}', accountTypeLabel(a.type, l10n));
    }
    if (a.isExchangeOnlineOAuth) {
      return l10n.tr('serverViaProvider').replaceAll('{name}', 'Microsoft 365');
    }
    if (a.isMsExchange || a.usesEas || a.usesEws) {
      return a.exchangeServer ?? a.ewsUrl ?? '—';
    }
    final imap = '${a.imapServer ?? '—'}${a.imapPort != null ? ':${a.imapPort}' : ''}';
    final smtp = '${a.smtpServer ?? '—'}${a.smtpPort != null ? ':${a.smtpPort}' : ''}';
    return 'IMAP $imap · SMTP $smtp';
  }

  /// Адрес сервера Exchange или серверы и порты IMAP/SMTP. Пароль меняется
  /// пунктом «Войти снова».
  Future<void> _editServer(BuildContext context, WidgetRef ref, AccountModel a) async {
    final l10n = AppLocalizations.of(context);
    final exchange = a.isMsExchange || a.usesEas || a.usesEws;
    final host = TextEditingController(text: exchange ? (a.exchangeServer ?? '') : (a.imapServer ?? ''));
    final port = TextEditingController(text: a.imapPort?.toString() ?? '');
    final sHost = TextEditingController(text: a.smtpServer ?? '');
    final sPort = TextEditingController(text: a.smtpPort?.toString() ?? '');
    InputDecoration dec(String label) => InputDecoration(labelText: label, isDense: true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('server')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!exchange)
                Text(l10n.tr('incomingServer'), style: Theme.of(ctx).textTheme.labelLarge),
              TextField(controller: host, keyboardType: TextInputType.url, autocorrect: false,
                  decoration: dec(l10n.tr('serverHostLbl'))),
              if (!exchange) ...[
                TextField(controller: port, keyboardType: TextInputType.number,
                    decoration: dec(l10n.tr('port'))),
                const SizedBox(height: Space.l),
                Text(l10n.tr('outgoingServer'), style: Theme.of(ctx).textTheme.labelLarge),
                TextField(controller: sHost, keyboardType: TextInputType.url, autocorrect: false,
                    decoration: dec(l10n.tr('serverHostLbl'))),
                TextField(controller: sPort, keyboardType: TextInputType.number,
                    decoration: dec(l10n.tr('port'))),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    if (ok != true) return;
    final h = host.text.trim();
    if (h.isEmpty) return;
    final updated = exchange
        ? a.copyWith(exchangeServer: h)
        : a.copyWith(
            imapServer: h,
            imapPort: int.tryParse(port.text.trim()) ?? a.imapPort,
            smtpServer: sHost.text.trim().isEmpty ? a.smtpServer : sHost.text.trim(),
            smtpPort: int.tryParse(sPort.text.trim()) ?? a.smtpPort,
          );
    await ref.read(accountsProvider.notifier).updateAccount(updated);
    ref.read(mailEngineServiceProvider).disconnect(a.id);
    if (context.mounted) {
      showInlineNotice(l10n.tr('serverSettingsSaved'));
    }
  }

  /// Хосты аккаунта (Exchange или IMAP/SMTP) без схемы и порта.
  static Set<String> _hostsOf(AccountModel a) {
    String? h(String? v) {
      if (v == null || v.trim().isEmpty) return null;
      final t = v.trim();
      final u = Uri.tryParse(t.contains('://') ? t : 'https://$t');
      return u?.host.toLowerCase();
    }
    return {h(a.exchangeServer), h(a.ewsUrl), h(a.imapServer), h(a.smtpServer)}.whereType<String>().toSet();
  }

  /// Сертификаты, принятые вручную для серверов этого аккаунта.
  static List<PinRule> _pinsFor(CertificatePinningService svc, AccountModel a) {
    final hosts = _hostsOf(a);
    return svc.rules.where((r) {
      final d = r.domain.toLowerCase();
      if (d.startsWith('=')) return hosts.contains(d.substring(1));
      return hosts.any((h) => h == d || (r.includeSubdomains && h.endsWith('.$d')));
    }).toList();
  }

  static String _hex(String b64) {
    try {
      final bytes = base64.decode(b64);
      return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
    } catch (_) {
      return b64;
    }
  }

  static Future<void> _showPins(BuildContext context, WidgetRef ref, List<PinRule> pins) async {
    final l10n = AppLocalizations.of(context);
    final revoke = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('serverCert')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in pins) ...[
                Text(r.domain.replaceFirst('=', ''), style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: Space.xs),
                for (final f in r.sha256Fingerprints)
                  SelectableText('SHA-256 ${_hex(f)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: Space.m),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('serverCertRevoke'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('close'))),
        ],
      ),
    );
    if (revoke != true) return;
    final svc = ref.read(certPinningProvider);
    for (final r in pins) {
      await svc.removeRule(r.domain);
    }
    if (context.mounted) {
      showInlineNotice(l10n.tr('serverCertRevoked'));
    }
  }

  /// Цвет ящика и стиль окраски: 32 цвета и образец верхней панели почты,
  /// который сразу показывает выбор (нижняя панель — по теме, 1.6.4). Стиль — общий для всех
  /// ящиков, цвет — у каждого свой.
  Future<void> _pickColor(BuildContext context, WidgetRef ref, AccountModel account) async {
    final l10n = AppLocalizations.of(context);
    var color = account.colorValue;
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final theme = Theme.of(ctx);
        final style = ref.watch(accountHeaderStyleProvider);
        return StatefulBuilder(builder: (ctx, setLocal) {
          final c = Color(color);
          final look = headerLook(style, c, theme);
          final fg = look.foreground ?? theme.colorScheme.onSurface;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.tr('accountColor'), style: theme.textTheme.titleMedium),
                  const SizedBox(height: Space.m),
                  // Образец шапки — как она будет выглядеть в списке писем.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 56,
                      decoration: ShapeDecoration(
                        // Цвет и градиент вместе ShapeDecoration не принимает.
                        color: look.gradient == null ? (look.background ?? theme.colorScheme.surface) : null,
                        gradient: look.gradient,
                        shape: look.shape ?? const Border(),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: Space.m),
                      child: Row(children: [
                        CircleAvatar(radius: 16, backgroundColor: c,
                            child: Text(account.email.isEmpty ? '?' : initialOf(account.email),
                                style: TextStyle(color: onAccountColor(c), fontSize: 14))),
                        const SizedBox(width: Space.m),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.inbox, style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                              Text(account.email, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.7))),
                            ],
                          ),
                        ),
                        Icon(AppIcons.search, color: fg),
                        const SizedBox(width: Space.m),
                        Icon(AppIcons.more_vert, color: fg),
                      ]),
                    ),
                  ),
                  const SizedBox(height: Space.l),
                  Wrap(
                    spacing: Space.m,
                    runSpacing: Space.m,
                    children: [
                      for (final p in AccountsNotifier.accountPalette)
                        InkResponse(
                          onTap: () async {
                            setLocal(() => color = p);
                            await ref.read(accountsProvider.notifier).setAccountColor(account.id, p);
                          },
                          radius: 24,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(p),
                              shape: BoxShape.circle,
                              border: p == color
                                  ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                                  : null,
                            ),
                            child: p == color ? Icon(AppIcons.check, color: onAccountColor(Color(p))) : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.l),
                  TitleWithHelp(l10n.tr('headerStyle'),
                      hint: l10n.tr('headerStyleHint'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: Space.s),
                  Wrap(
                    spacing: Space.s,
                    runSpacing: Space.s,
                    children: [
                      for (final (st, key) in const [
                        (AccountHeaderStyle.none, 'headerStyleNone'),
                        (AccountHeaderStyle.tint, 'headerStyleTint'),
                        (AccountHeaderStyle.stripe, 'headerStyleStripe'),
                        (AccountHeaderStyle.gradient, 'headerStyleGradient'),
                        (AccountHeaderStyle.full, 'headerStyleFull'),
                      ])
                        ChoiceChip(
                          label: Text(l10n.tr(key)),
                          selected: style == st,
                          onSelected: (_) => ref.read(accountHeaderStyleProvider.notifier).set(st),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      }),
    );
  }

  /// Фото ящика: своё из галереи или файлов, либо сброс (снова фото из
  /// адресной книги организации или инициалы).
  Future<void> _pickPhoto(BuildContext context, WidgetRef ref, AccountModel account) async {
    final l10n = AppLocalizations.of(context);
    final manual = ref.read(manualPhotosProvider).contains(account.id);
    final action = await showAppSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(AppIcons.photo_library),
            title: Text(l10n.tr('accountPhotoChoose')),
            onTap: () => Navigator.pop(ctx, 'pick'),
          ),
          if (account.avatarUrl != null || manual)
            ListTile(
              leading: const Icon(AppIcons.hide_image),
              title: Text(l10n.tr('accountPhotoReset')),
              subtitle: Text(l10n.tr('accountPhotoResetDesc')),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
        ]),
      ),
    );
    if (action == null) return;
    final notifier = ref.read(accountsProvider.notifier);
    if (action == 'reset') {
      await ref.read(manualPhotosProvider.notifier).mark(account.id, false);
      await notifier.setAccountPhoto(account.id, null);
      return;
    }
    // Раньше при пустом bytes (часть галерей и «Фото» Android отдают только
    // путь) выбор молча ничего не делал. Теперь: байты или чтение по пути,
    // ошибки — в журнал и сообщением.
    Uint8List? bytes;
    try {
      final f = await FilePick.file(type: FileType.image);
      if (f == null) return; // выбор отменён
      bytes = await f.readBytes();
      AppLogger.info('Фото аккаунта: выбран файл ${f.name}, ${bytes.length} байт');
    } catch (e) {
      AppLogger.warning('Фото аккаунта: выбор не удался — $e');
    }
    if (bytes == null || bytes.isEmpty) {
      // Строкой вверху экрана: чёрные плашки в приложении выключены, и
      // сообщение о негодном файле раньше не показывалось.
      showInlineError(l10n.tr('accountPhotoBad'));
      return;
    }
    String? uri;
    try {
      uri = await photoToDataUri(bytes);
    } catch (e) {
      AppLogger.warning('Фото аккаунта: не удалось обработать — $e');
    }
    if (uri == null) {
      if (context.mounted) {
        showInlineError(l10n.tr('accountPhotoBad'));
      }
      return;
    }
    await ref.read(manualPhotosProvider.notifier).mark(account.id, true);
    await notifier.setAccountPhoto(account.id, uri);
  }


  /// Период в месяцах (1–24) из дней настройки и обратно. Год — 365 дней,
  /// два — 730, остальное — по средней длине месяца.
  static int _monthsOf(int days) => (days / 30.44).round().clamp(1, 24);
  static int _daysOf(int months) =>
      months == 12 ? 365 : months == 24 ? 730 : (months * 30.44).round();

  static String _periodLabel(int days, AppLocalizations l10n) {
    if (days <= 0) return l10n.tr('syncPeriodAll');
    final m = _monthsOf(days);
    if (m == 12) return l10n.plural('periodYearsN', 1);
    if (m == 24) return l10n.plural('periodYearsN', 2);
    if (m == 18) return l10n.tr('periodYearAndHalf');
    return l10n.plural('periodMonthsN', m);
  }

  static String _lastSync(BuildContext context, DateTime? at, AppLocalizations l10n) =>
      at == null ? l10n.tr('lastSyncNever') : AppDateFormat.dayMonthTime(context, at);

  static String _policyText(StoredEasPolicy p, AppLocalizations l10n) {
    final parts = <String>[
      if (p.pinRequired)
        l10n.tr('orgPolicyLock').replaceAll('{n}', '${p.minPasswordLength > 0 ? p.minPasswordLength : p.minPinLength}'),
      if (p.maxInactivitySeconds > 0)
        l10n.tr('orgPolicyIdle').replaceAll('{n}', '${(p.maxInactivitySeconds / 60).ceil()}'),
      if (p.requireEncryption) l10n.tr('orgPolicyEncrypt'),
    ];
    if (parts.isEmpty) return l10n.tr('orgPolicyNone');
    final t = parts.join(', ');
    return t[0].toUpperCase() + t.substring(1);
  }

  Future<void> _editSenderName(BuildContext context, WidgetRef ref, AccountModel account) async {
    final l10n = AppLocalizations.of(context);
    final ctl = TextEditingController(
        text: account.displayName.toLowerCase() == account.email.toLowerCase() ? '' : account.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('senderName')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: l10n.tr('senderNameHint'), helperText: account.email),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(l10n.tr('save'))),
        ],
      ),
    );
    ctl.dispose();
    if (name == null) return;
    final v = name.trim();
    await ref.read(accountsProvider.notifier)
        .updateAccount(account.copyWith(displayName: v.isEmpty ? account.email : v));
  }

  /// Период синхронизации: ползунок от месяца до двух лет и отдельный
  /// переключатель «Весь период», который блокирует ползунок. Раньше — четыре
  /// пункта (месяц, полгода, год, всё): двух-трёх месяцев не было, а
  /// подпись «полгода» показывалась и для трёх месяцев.
  Future<void> _pickPeriod(BuildContext context, WidgetRef ref, AccountModel account) async {
    final l10n = AppLocalizations.of(context);
    var all = account.syncDays <= 0;
    var months = all ? 12.0 : _monthsOf(account.syncDays).toDouble();
    final picked = await showAppSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final theme = Theme.of(ctx);
            final days = all ? 0 : _daysOf(months.round());
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(l10n.tr('syncPeriod'), style: theme.textTheme.titleMedium),
                  trailing: HelpButton(text: l10n.tr('syncPeriodHint'), title: l10n.tr('syncPeriod')),
                ),
                SwitchListTile(
                  title: Text(l10n.tr('syncPeriodAll')),
                  subtitle: Text(l10n.tr('syncPeriodAllDesc')),
                  value: all,
                  onChanged: (v) => setLocal(() => all = v),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                  child: Row(
                    children: [
                      Text(l10n.tr('syncPeriodWindow'), style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Text(
                        all ? '—' : _periodLabel(days, l10n),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: all ? theme.disabledColor : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Slider(
                  value: months,
                  min: 1,
                  max: 24,
                  divisions: 23,
                  label: _periodLabel(_daysOf(months.round()), l10n),
                  onChanged: all ? null : (v) => setLocal(() => months = v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Row(
                    children: [
                      Text(_periodLabel(_daysOf(1), l10n), style: theme.textTheme.bodySmall),
                      const Spacer(),
                      Text(_periodLabel(_daysOf(24), l10n), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, days),
                      child: Text(l10n.tr('save')),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (picked == null || picked == account.syncDays) return;
    await ref.read(accountsProvider.notifier).updateAccount(account.copyWith(syncDays: picked));
    // Окно ActiveSync задаётся при подключении — переподключаемся с новым.
    ref.read(mailEngineServiceProvider).disconnect(account.id);
    // Период расширили — догружаем историю сразу, а не при плановой проверке.
    if (picked <= 0 || picked > account.syncDays) {
      final fresh = ref.read(accountsProvider).where((a) => a.id == account.id).firstOrNull;
      if (fresh != null) unawaited(ref.read(syncServiceProvider).syncAccount(fresh));
    }
  }
}

/// Сертификат сервера аккаунта: принят ли вручную по отпечатку; отзыв доверия.
class _ServerCertItem extends ConsumerStatefulWidget {
  final AccountModel account;
  const _ServerCertItem({required this.account});

  @override
  ConsumerState<_ServerCertItem> createState() => _ServerCertItemState();
}

class _ServerCertItemState extends ConsumerState<_ServerCertItem> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pins = AccountScreen._pinsFor(ref.read(certPinningProvider), widget.account);
    return SettingsItem(
      icon: pins.isEmpty ? AppIcons.verified : AppIcons.push_pin,
      title: l10n.tr('serverCert'),
      subtitle: pins.isEmpty
          ? l10n.tr('serverCertSystem')
          : l10n.tr('serverCertPinned').replaceAll('{n}', pins.map((r) => r.domain.replaceFirst('=', '')).join(', ')),
      onTap: pins.isEmpty
          ? null
          : () async {
              await AccountScreen._showPins(context, ref, pins);
              if (mounted) setState(() {});
            },
    );
  }
}


class _Header extends StatelessWidget {
  final AccountModel account;
  final String typeLabel;
  final bool isPrimary;
  const _Header({required this.account, required this.typeLabel, required this.isPrimary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = account.displayName.isNotEmpty ? account.displayName : account.email;
    return Row(
      children: [
        HeroEmailAvatar(
          emailId: 'account/${account.id}',
          initial: initialOf(name),
          color: Color(account.colorValue),
          radius: Sizes.avatarLarge / 2,
          hero: false,
          email: account.email,
          photo: account.avatarUrl,
        ),
        const SizedBox(width: Space.l),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.email, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                isPrimary ? '$typeLabel · ${AppLocalizations.of(context).tr('primaryChip')}' : typeLabel,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Карточка-группа строк (принципы Dialer: группы в карточках, радиус 16).



/// Стиль текста писем аккаунта: шрифт и размер, с образцом.
void _pickComposeStyle(BuildContext context, WidgetRef ref, String accountId) {
  final l10n = AppLocalizations.of(context);
  var style = ComposeStylesNotifier.styleFor(ref.read(composeStylesProvider), accountId);
  showAppSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final theme = Theme.of(ctx);
      void pick(ComposeStyle s) {
        setLocal(() => style = s);
        ref.read(composeStylesProvider.notifier).set(accountId, s);
      }
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TitleWithHelp(l10n.tr('composeStyle'),
                  hint: l10n.tr('composeStyleHint'), style: theme.textTheme.titleMedium),
              const SizedBox(height: Space.m),
              Text(l10n.tr('font'), style: theme.textTheme.labelLarge),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.xs,
                children: [
                  for (final f in ComposeStyle.fonts.keys)
                    ChoiceChip(
                      label: Text(f),
                      selected: style.font == f,
                      onSelected: (_) => pick(ComposeStyle(font: f, sizePt: style.sizePt)),
                    ),
                ],
              ),
              const SizedBox(height: Space.m),
              Text(l10n.tr('fontSize'), style: theme.textTheme.labelLarge),
              const SizedBox(height: Space.xs),
              Wrap(
                spacing: Space.s,
                children: [
                  for (final sz in ComposeStyle.sizes)
                    ChoiceChip(
                      label: Text('$sz'),
                      selected: style.sizePt == sz,
                      onSelected: (_) => pick(ComposeStyle(font: style.font, sizePt: sz)),
                    ),
                ],
              ),
              const SizedBox(height: Space.m),
              // Образец — примерно так письмо увидит получатель.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.m),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.tr('composeStyleSample'),
                  style: TextStyle(
                    fontFamily: style.font,
                    fontFamilyFallback: const ['Carlito', 'Arial', 'Roboto'],
                    fontSize: style.sizePt * 4 / 3,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: Space.s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => pick(ComposeStyle.fallback),
                  child: Text(l10n.tr('resetToDefault')),
                ),
              ),
            ],
          ),
        ),
      );
    }),
  );
}

/// «В телефоне»: контакты и календарь ящика в «Контактах» и «Календаре»
/// телефона (определитель номера, системный календарь и его виджеты).
class _PhoneMirrorSection extends ConsumerStatefulWidget {
  final AccountModel account;
  const _PhoneMirrorSection({required this.account});

  @override
  ConsumerState<_PhoneMirrorSection> createState() => _PhoneMirrorSectionState();
}

class _PhoneMirrorSectionState extends ConsumerState<_PhoneMirrorSection> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool contacts, bool on) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(phoneMirrorProvider);
    final ok = contacts
        ? await svc.setContacts(widget.account, on)
        : await svc.setCalendar(widget.account, on);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // Без всплывающих окон: причина — под переключателями.
      if (!ok) _error = l10n.tr('phoneMirrorFailed');
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(phoneMirrorProvider);
    if (!svc.isAvailable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final a = widget.account;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('phoneMirror')),
        SettingsGroup(children: [
          SettingsSwitchItem(
            icon: AppIcons.contacts,
            title: l10n.tr('phoneMirrorContacts'),
            subtitle: l10n.tr('phoneMirrorContactsShort'),
            hint: l10n.tr('phoneMirrorContactsDesc'),
            value: svc.contactsOn(a.id),
            onChanged: _busy ? null : (v) => _toggle(true, v),
          ),
          SettingsSwitchItem(
            icon: AppIcons.calendar_today,
            title: l10n.tr('phoneMirrorCalendar'),
            subtitle: l10n.tr('phoneMirrorCalendarShort'),
            hint: l10n.tr('phoneMirrorCalendarDesc'),
            value: svc.calendarOn(a.id),
            onChanged: _busy ? null : (v) => _toggle(false, v),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
            child: Text(_error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.errorText(context))),
          ),
      ],
    );
  }
}


// lib/features/settings/screens/accounts_settings_screen.dart
// Управление аккаунтами: список (несколько одного типа), добавление,
// выбор основного (для отправки по умолчанию), удаление, полная пересинхронизация.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../mail/providers/mail_providers.dart';
import '../../../widgets/common/eas_compat_switch.dart';
import '../../../services/mail/engine/mail_engine_service.dart';
import '../../../services/mail/alias_service.dart';
import '../providers/settings_provider.dart';
import '../../../data/models/account_model.dart';
import '../../../core/theme/app_icons.dart';
import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../widgets/common/text_scale_cap.dart';

class AccountsSettingsScreen extends ConsumerWidget {
  const AccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final accounts = ref.watch(accountsProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('accounts')), actions: const [FaqButton(section: 'exchange')])),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/login?mode=add'),
        icon: const Icon(AppIcons.add),
        label: Text(l10n.tr('addAccount')),
      ),
      body: accounts.isEmpty
          ? Center(child: Text(l10n.tr('noAccounts')))
          // Порядок ящиков — перетаскиванием за ручку справа (или долгим
          // нажатием на карточку). Тот же порядок — в меню почты (аватарки
          // внизу), в выборе отправителя и в переключателе ящиков.
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96), // под кнопкой «Добавить»
              buildDefaultDragHandles: false,
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Text(
                      accounts.length > 1
                          ? '${l10n.tr('accountsHint')}\n${l10n.tr('accountsOrderHint')}'
                          : l10n.tr('accountsHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (accounts.any((a) => a.isMsExchange))
                    EasCompatSwitch(
                      onChanged: () {
                        // UA задаётся при подключении — сбрасываем открытые
                        // подключения Exchange, следующая синхронизация
                        // подключится заново.
                        final engine = ref.read(mailEngineServiceProvider);
                        for (final a in accounts.where((a) => a.isMsExchange)) {
                          engine.disconnect(a.id);
                        }
                      },
                    ),
                ],
              ),
              itemCount: accounts.length,
              // onReorderItem появился в Flutter 3.41; pubspec допускает 3.38.
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                if (newIndex == oldIndex) return;
                final ids = accounts.map((a) => a.id).toList();
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                HapticFeedback.selectionClick();
                ref.read(accountsProvider.notifier).reorderAccounts(ids);
              },
              itemBuilder: (context, i) {
                final a = accounts[i];
                final isPrimary = a.isPrimary || (settings.activeAccountId == a.id);
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('acc_${a.id}'),
                  index: i,
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
                    child: ListTile(
                      leading: Icon(AppIcons.forAccountType(a.type.name), color: Color(a.colorValue)),
                      title: Row(
                        children: [
                          Flexible(child: Text(a.email, overflow: TextOverflow.ellipsis)),
                          if (isPrimary)
                            Padding(
                              padding: const EdgeInsets.only(left: Space.s),
                              child: Chip(
                                label: Text(l10n.tr('primaryChip'), style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text('${accountTypeLabel(a.type, l10n)} · ${a.unreadCount} ${l10n.tr('unreadShort')}'),
                      // Все настройки ящика — на его экране (тип, подпись,
                      // адреса, синхронизация, календарь, автоответ, правила,
                      // удаление).
                      trailing: accounts.length < 2
                          ? const Icon(AppIcons.chevron_right)
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Кнопки «выше/ниже» — для тех, кому
                                // неудобно перетаскивать (и для TalkBack).
                                IconButton(
                                  tooltip: l10n.tr('moveUp'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(AppIcons.arrow_upward, size: 20),
                                  onPressed: i == 0
                                      ? null
                                      : () {
                                          final ids = accounts.map((x) => x.id).toList();
                                          ids.insert(i - 1, ids.removeAt(i));
                                          ref.read(accountsProvider.notifier).reorderAccounts(ids);
                                        },
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(Space.s),
                                    child: Icon(AppIcons.drag_indicator,
                                        semanticLabel: l10n.tr('reorderAccounts'),
                                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                      onTap: () => context.push('/settings/account/${Uri.encodeComponent(a.id)}'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ── Действия с аккаунтом: общие для списка и экрана аккаунта ──

String accountTypeLabel(AccountType t, AppLocalizations l10n) {
  switch (t) {
    case AccountType.corporate: return l10n.tr('brandExchange');
    case AccountType.exchange: return 'Exchange';
    case AccountType.activesync: return 'ActiveSync';
    case AccountType.google: return 'Google';
    case AccountType.yandex: return l10n.tr('brandYandex');
    case AccountType.yahoo: return 'Yahoo';
    case AccountType.mailru: return 'Mail.ru';
    case AccountType.outlook: return 'Outlook';
    case AccountType.imap: return 'IMAP/SMTP';
  }
}

/// Рабочий или личный ящик: у рабочего — предупреждения о внешних
/// отправителях и первом контакте, у личного их нет.
Future<void> pickAccountKind(BuildContext context, WidgetRef ref, AccountModel a) async {
  final l10n = AppLocalizations.of(context);
  final picked = await showAppSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(l10n.tr('accountKind'), style: Theme.of(ctx).textTheme.titleMedium),
              subtitle: Text(l10n.tr('accountKindHint'))),
          for (final k in const ['auto', 'work', 'personal'])
            ListTile(
              leading: Icon(k == 'work' ? AppIcons.work : k == 'personal' ? AppIcons.person : AppIcons.auto_mode),
              title: Text(l10n.tr(k == 'work' ? 'accountKindWork' : k == 'personal' ? 'accountKindPersonal' : 'accountKindAuto')),
              trailing: (k == 'auto' ? a.accountKind == null : a.accountKind == k)
                  ? Icon(AppIcons.check, color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, k),
            ),
        ],
      ),
    ),
  );
  if (picked == null) return;
  await ref.read(accountsProvider.notifier).setAccountKind(a.id, picked == 'auto' ? null : picked);
}

/// Управление псевдонимами (алиасами) отправки для аккаунта: список +
/// добавление/удаление. Хранение — в prefs через aliasServiceProvider.
/// Примечание: сама ОТПРАВКА от имени алиаса требует прав send-as на сервере и
/// сквозной поддержки транспортов — пока настраивается, но не используется при
/// отправке (см. ROADMAP).
Future<void> manageAliases(BuildContext context, WidgetRef ref, AccountModel a) async {
  final l10n = AppLocalizations.of(context);
  final ctrl = TextEditingController();
  // Ошибка у поля (всплывающие сообщения в приложении отключены).
  final aliasError = ValueNotifier<String?>(null);

  bool validEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  await showDialog<void>(
    context: context,
    builder: (ctx) => Consumer(
      builder: (ctx, dref, _) {
        final aliases = dref.watch(aliasServiceProvider)[a.id] ?? const <String>[];
        final notifier = dref.read(aliasServiceProvider.notifier);
        return AlertDialog(
          title: Text(l10n.tr('aliases')),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.email} ${l10n.tr('primaryParen')}',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: Space.s),
                // Как это работает (1.6.27): адрес появляется в поле «От»,
                // ответ на письмо, пришедшее на него, — сразу от него.
                Text(l10n.tr('aliasesSendAsHint'),
                    style: Theme.of(ctx).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: Space.s),
                if (aliases.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s),
                    child: Text(l10n.tr('noAliasesYet'),
                        style: Theme.of(ctx).textTheme.bodyMedium),
                  )
                else
                  ...aliases.map((e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(e, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: l10n.tr('delete'),
                          icon: const Icon(AppIcons.close, size: 18),
                          onPressed: () => notifier.removeAlias(a.id, e),
                        ),
                      )),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<String?>(
                        valueListenable: aliasError,
                        builder: (_, err, __) => TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          onChanged: (_) => aliasError.value = null,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.tr('newAliasEmail'),
                            errorText: err,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.tr('add'),
                      icon: const Icon(AppIcons.add),
                      onPressed: () async {
                        final v = ctrl.text.trim();
                        if (!validEmail(v)) {
                          aliasError.value = l10n.tr('invalidEmail');
                          return;
                        }
                        await notifier.addAlias(a.id, v);
                        ctrl.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.tr('close')),
            ),
          ],
        );
      },
    ),
  );
}

Future<bool?> confirmDeleteAccount(BuildContext context, String email) {
  final l10n = AppLocalizations.of(context);
  return confirmDestructive(context,
      title: l10n.tr('deleteAccountQ'), message: '$email\n\n${l10n.tr('deleteAccountConfirm')}');
}

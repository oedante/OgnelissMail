// lib/features/settings/widgets/dav_pim_item.dart
// «Календарь и контакты» в настройках ящика (1.7.2+110, замечание владельца
// 24.10.2026: «отличаются от остальных и во всех аккаунтах указывается
// Яндекс — пользователям непонятно, что это и зачем»).
//
// Пункт есть только у ящиков, которым нужен пароль приложения
// (`DavPimService.needsAppPassword`): Яндекс по паролю, Mail.ru и Yahoo через
// вход в аккаунт; или если пароль уже сохранён (чтобы его можно было убрать).
// Под названием — состояние: «Нужен пароль приложения — без него …» или
// «Пароль приложения сохранён»; «?» — зачем и где его взять, своими словами
// для каждой почты. Нажатие — шторка, как у остальных пунктов настроек
// (раньше — окно с текстом про Яндекс у всех ящиков). У Яндекса два поля:
// пароли приложений «Календарь» и «Контакты» у него раздельные.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/secure_storage_service.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart' show AppColors;
import '../../../core/theme/tokens.dart';
import '../../../data/models/account_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/mail/dav/dav_credentials.dart';
import '../../../services/mail/dav/dav_pim_service.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/ui/settings_group.dart';

class DavPimItem extends ConsumerStatefulWidget {
  final AccountModel account;
  const DavPimItem({super.key, required this.account});

  @override
  ConsumerState<DavPimItem> createState() => _DavPimItemState();
}

class _DavPimItemState extends ConsumerState<DavPimItem> {
  ({String? cal, String? card})? _saved;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final s = ref.read(secureStorageProvider);
    final cal = await DavCredentials.appPassword(s, widget.account.id);
    final card = await DavCredentials.contactsPassword(s, widget.account.id);
    if (mounted) setState(() => _saved = (cal: cal, card: card));
  }

  String? get _provider => DavPimService.providerOf(widget.account);

  /// Пояснение «зачем и где взять» для почты ящика.
  static String hintFor(String? provider, AppLocalizations l10n) => switch (provider) {
        'mailru' => l10n.tr('davPimHintMailru'),
        'yahoo' => l10n.tr('davPimHintYahoo'),
        _ => l10n.tr('davPimHintYandex'),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final saved = _saved;
    final has = saved != null && (saved.cal != null || saved.card != null);
    if (!DavPimService.needsAppPassword(widget.account) && !has) return const SizedBox.shrink();
    final provider = _provider;
    final contacts = provider != null && DavPimService.hasContacts(provider);
    return SettingsItem(
      icon: AppIcons.event_note,
      title: l10n.tr(contacts ? 'davPim' : 'davPimCalendarOnly'),
      subtitle: saved == null
          ? null
          : has
              ? l10n.tr('davPimSaved')
              : l10n.tr(contacts ? 'davPimNeeded' : 'davPimNeededCal'),
      hint: hintFor(provider, l10n),
      onTap: saved == null ? null : () => unawaited(_edit(context, l10n, saved)),
    );
  }

  Future<void> _edit(BuildContext context, AppLocalizations l10n, ({String? cal, String? card}) saved) async {
    final provider = _provider;
    final yandex = provider == 'yandex';
    final contacts = provider != null && DavPimService.hasContacts(provider);
    final cal = TextEditingController(text: saved.cal ?? '');
    final card = TextEditingController(text: saved.card ?? '');
    final storage = ref.read(secureStorageProvider);
    final result = await showAppSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = AppColors.mutedText(ctx);
        Widget field(TextEditingController c, String label, IconData icon) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
              child: Row(children: [
                Icon(icon, color: muted),
                const SizedBox(width: Space.l),
                Expanded(
                  child: TextField(
                    controller: c,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: label,
                      filled: false,
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(vertical: Space.s),
                    ),
                  ),
                ),
              ]),
            );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.l),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: Text(l10n.tr(contacts ? 'davPim' : 'davPimCalendarOnly'), style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: Space.xs),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: Text(widget.account.email, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  ),
                  const SizedBox(height: Space.m),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s),
                    child: Text(hintFor(provider, l10n), style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                  ),
                  const SizedBox(height: Space.m),
                  SettingsGroup(children: [
                    field(cal, l10n.tr(yandex ? 'davPwCalendar' : 'davAppPwLabel'), AppIcons.event_note),
                    if (yandex) field(card, l10n.tr('davPwContacts'), AppIcons.contacts),
                  ]),
                  const SizedBox(height: Space.m),
                  Row(children: [
                    if (saved.cal != null || saved.card != null)
                      TextButton(
                        onPressed: () {
                          cal.clear();
                          card.clear();
                          Navigator.pop(ctx, true);
                        },
                        child: Text(l10n.tr('davPwRemove'),
                            style: TextStyle(color: AppColors.errorTextOn(theme))),
                      ),
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.tr('cancel'))),
                    const SizedBox(width: Space.s),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('save'))),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
    final calPw = cal.text;
    final cardPw = card.text;
    cal.dispose();
    card.dispose();
    if (result != true) return;
    await DavCredentials.saveAppPassword(storage, widget.account.id, calPw);
    if (yandex) await DavCredentials.saveContactsPassword(storage, widget.account.id, cardPw);
    if (mounted) await _load();
  }
}

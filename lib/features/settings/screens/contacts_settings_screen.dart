// lib/features/settings/screens/contacts_settings_screen.dart
// Настройки модуля Контакты: сортировка, фото, приоритет глобального каталога.

import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../../../services/device/device_contacts_sync.dart';
import '../../mail/providers/mail_providers.dart';
import '../providers/module_settings_provider.dart';
import '../../../core/permissions/app_permissions.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineNotice;

class ContactsSettingsScreen extends ConsumerWidget {
  const ContactsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(moduleSettingsProvider);
    final n = ref.read(moduleSettingsProvider.notifier);

    String sortLabel(ContactSort v) {
      switch (v) {
        case ContactSort.firstName: return l10n.tr('sortByFirstName');
        case ContactSort.lastName: return l10n.tr('sortByLastName');
        case ContactSort.recent: return l10n.tr('sortByRecent');
      }
    }

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('contacts')),
        actions: const [FaqButton(section: 'contacts')],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('display')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.sort_by_alpha,
              title: l10n.tr('sortOrder'),
              subtitle: sortLabel(s.contactSort),
              onTap: () => showAppSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ContactSort.values.map((v) => AppRadioTile<ContactSort>(
                          title: Text(sortLabel(v)),
                          value: v,
                          groupValue: s.contactSort,
                          onChanged: (sel) {
                            n.setContactSort(sel!);
                            Navigator.pop(ctx);
                          },
                        )).toList(),
                  ),
                ),
              ),
            ),
            SettingsSwitchItem(
              icon: AppIcons.account_circle,
              title: l10n.tr('showPhotos'),
              value: s.showContactPhotos,
              onChanged: n.setShowContactPhotos,
            ),
          ]),
          // «Сначала глобальный каталог» убрано: поиск адресатов ранжирует
          // по частоте переписки, адресная книга организации дополняет его
          // автоматически; переключатель ни на что не влиял.
          const _DeviceContactsSyncSection(),
        ],
      ),
    );
  }
}

/// Импорт/экспорт контактов с адресной книгой устройства. Раздел показывается
/// ТОЛЬКО если реально подключён нативный канал (иначе действия молча вернули бы
/// 0 — фикция). Проба кэшируется на время жизни виджета.
class _DeviceContactsSyncSection extends ConsumerStatefulWidget {
  const _DeviceContactsSyncSection();

  @override
  ConsumerState<_DeviceContactsSyncSection> createState() => _DeviceContactsSyncSectionState();
}

class _DeviceContactsSyncSectionState extends ConsumerState<_DeviceContactsSyncSection> {
  late final Future<bool> _ready = ref.read(deviceContactsSyncProvider).isChannelReady();
  bool _busy = false;

  Future<void> _import() async {
    if (!await AppPermissions.ensure(context, AppPermission.contacts)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final count = await ref.read(deviceContactsSyncProvider).importFromDevice();
    if (!mounted) return;
    setState(() => _busy = false);
    showInlineNotice(l10n.tr('importedContactsN').replaceAll('{count}', '$count'));
  }

  Future<void> _export() async {
    if (!await AppPermissions.ensure(context, AppPermission.contacts)) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final account = ref.read(activeAccountProvider);
    if (account == null) return;
    setState(() => _busy = true);
    final count = await ref.read(deviceContactsSyncProvider).exportToDevice(account.id);
    if (!mounted) return;
    setState(() => _busy = false);
    showInlineNotice(l10n.tr('exportedContactsN').replaceAll('{count}', '$count'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<bool>(
      future: _ready,
      builder: (context, snap) {
        // Пока проба не завершилась или канал недоступен — раздел не показываем
        // (не вводим пользователя в заблуждение недоступной кнопкой).
        if (snap.data != true) return const SizedBox.shrink();
        final busy = _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSectionTitle(l10n.tr('deviceAddressBook')),
            SettingsGroup(children: [
              SettingsItem(
                icon: AppIcons.download,
                title: l10n.tr('importFromDevice'),
                subtitle: l10n.tr('importFromDeviceDesc'),
                trailing: busy,
                onTap: _busy ? null : _import,
              ),
              SettingsItem(
                icon: AppIcons.upload,
                title: l10n.tr('exportToDevice'),
                subtitle: l10n.tr('exportToDeviceDesc'),
                trailing: busy,
                onTap: _busy ? null : _export,
              ),
            ]),
          ],
        );
      },
    );
  }
}

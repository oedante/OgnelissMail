// lib/features/settings/widgets/phone_mirror_switch.dart
// «Контакты на устройстве» и «Календарь на устройстве» — один выключатель на
// все ящики (2.7.0, замечание владельца 22.11.2026: «контакты и календарь на
// устройстве у каждого аккаунта нужно всегда включать по умолчанию»).
// Включено по умолчанию; Google и iCloud на iPhone телефон синхронизирует
// сам — они не дублируются (PhoneMirrorService.eligible). Раньше — по
// переключателю у каждого ящика, выключено.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/app_permissions.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/device/phone_mirror_service.dart';
import '../../../widgets/ui/settings_group.dart';

class PhoneMirrorSection extends ConsumerStatefulWidget {
  /// true — контакты, false — календарь.
  final bool contacts;
  const PhoneMirrorSection({super.key, required this.contacts});

  @override
  ConsumerState<PhoneMirrorSection> createState() => _PhoneMirrorSectionState();
}

class _PhoneMirrorSectionState extends ConsumerState<PhoneMirrorSection> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle(bool on) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    final svc = ref.read(phoneMirrorProvider);
    try {
      if (on) {
        // Разрешение — через общий порядок: запрещено навсегда — настройки
        // телефона, а не молча «не получилось».
        final ok = await AppPermissions.ensure(
            context, widget.contacts ? AppPermission.contacts : AppPermission.calendar,
            explain: false);
        if (!ok) {
          if (mounted) setState(() => _error = l10n.tr('phoneMirrorFailed'));
          return;
        }
      }
      if (widget.contacts) {
        await svc.setContactsEnabled(on);
      } else {
        await svc.setCalendarEnabled(on);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(phoneMirrorProvider);
    if (!svc.isAvailable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final c = widget.contacts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.tr('phoneMirror')),
        SettingsGroup(children: [
          SettingsSwitchItem(
            key: ValueKey(c ? 'mirror_contacts_all' : 'mirror_calendar_all'),
            icon: c ? AppIcons.contacts : AppIcons.calendar_today,
            title: l10n.tr(c ? 'phoneMirrorContacts' : 'phoneMirrorCalendar'),
            subtitle: l10n.tr(c ? 'phoneMirrorContactsShort' : 'phoneMirrorCalendarShort'),
            hint: l10n.tr(c ? 'phoneMirrorContactsDesc' : 'phoneMirrorCalendarDesc'),
            value: c ? svc.contactsEnabled : svc.calendarEnabled,
            onChanged: _busy ? null : _toggle,
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

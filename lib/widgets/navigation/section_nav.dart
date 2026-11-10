// lib/widgets/navigation/section_nav.dart
// Разделы на компьютере и планшете (2.2.1, решение владельца 10.11.2026:
// «зачем в десктопной версии дубликаты кнопок? Давай от левой области
// вообще избавимся, а основные кнопки перенесём над избранным»). Узкой
// полосы разделов слева больше нет: «Написать» и «Почта · Календарь ·
// Контакты · Задачи» — шапкой боковой панели над «Избранным» (в почте — в
// панели папок, MailDrawer; в других разделах — в панели MainShell, где
// под ними «Мой день», «Поручения», «Файлы», «Настройки»). На телефоне
// не используется — там нижняя панель.

import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../features/mail/providers/mail_providers.dart' show totalUnreadCountProvider;
import '../../features/settings/providers/feature_flags_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../common/calendar_day_icon.dart';

class SectionNav extends ConsumerWidget {
  /// Под разделами — «Мой день», «Поручения», «Файлы», «Настройки» списком:
  /// там, где нет «Избранного» (календарь, контакты, задачи…). В почте они —
  /// плитками «Избранного».
  final bool extras;

  /// Перед переходом (выдвижное меню — закрыть).
  final VoidCallback? onNavigate;

  const SectionNav({super.key, this.extras = false, this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = GoRouterState.of(context).uri.path;
    final flags = ref.watch(featureFlagsProvider);
    final unread = ref.watch(totalUnreadCountProvider);

    void go(String route, {bool push = false}) {
      onNavigate?.call();
      if (push) {
        context.push(route);
      } else if (path != route) {
        context.go(route);
      }
    }

    bool at(String route) => path == route || path.startsWith('$route/');

    Widget section(String key, String route, String label, Widget Function(bool selected) icon) {
      final selected = at(route);
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('section_$key'),
            borderRadius: BorderRadius.circular(Radii.chip),
            onTap: () => go(route),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 52,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? scheme.secondaryContainer : null,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: IconTheme.merge(
                    data: IconThemeData(color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                    child: icon(selected),
                  ),
                ),
                const SizedBox(height: 2),
                // Узкая панель — подпись мельче, а не «Календа…».
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: selected ? FontWeight.w700 : null,
                        color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                      )),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    Widget mailIcon(bool selected) => badges.Badge(
          showBadge: unread > 0,
          badgeContent: Text(unread > 99 ? '99+' : '$unread',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.errorRed, padding: EdgeInsets.all(Space.xs)),
          child: Icon(AppIcons.mail, size: 22, fill: selected ? 1 : 0),
        );

    Widget extra(String key, IconData icon, String label, VoidCallback onTap, {bool selected = false}) => ListTile(
          key: ValueKey('section_$key'),
          dense: true,
          selected: selected,
          leading: Icon(icon, size: 22),
          title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
          onTap: onTap,
        );

    return Column(
      key: const ValueKey('section_nav'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s),
          child: FilledButton.icon(
            key: const ValueKey('section_compose'),
            onPressed: () => go('/compose', push: true),
            icon: const Icon(AppIcons.edit, size: 20),
            label: Text(l10n.compose, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xs),
          child: Row(children: [
            section('mail', '/mail', l10n.mail, mailIcon),
            section('calendar', '/calendar', l10n.calendarLabel, (_) => const CalendarDayIcon()),
            section('contacts', '/contacts', l10n.contactsLabel,
                (s) => Icon(AppIcons.contacts, size: 22, fill: s ? 1 : 0)),
            if (flags.showTasksTab)
              section('tasks', '/tasks', l10n.tasksLabel, (s) => Icon(AppIcons.check_box, size: 22, fill: s ? 1 : 0)),
          ]),
        ),
        if (extras) ...[
          const Divider(height: Space.l),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s),
            child: Column(children: [
              if (ref.watch(settingsProvider.select((s) => s.myDay)))
                extra('myday', AppIcons.myDay, l10n.tr('myDay'), () => go('/my-day'), selected: at('/my-day')),
              extra('assignments', AppIcons.assignment_ind, l10n.tr('assignments'), () => go('/assignments'),
                  selected: at('/assignments')),
              if (flags.showNotes)
                extra('notes', AppIcons.sticky_note_2, l10n.tr('notes'), () => go('/notes'), selected: at('/notes')),
              if (flags.showFileHub)
                extra('files', AppIcons.folder_copy, l10n.tr('fileHub'), () => go('/files'), selected: at('/files')),
              extra('settings', AppIcons.settings, l10n.tr('settings'), () => go('/settings', push: true)),
            ]),
          ),
        ],
      ],
    );
  }
}

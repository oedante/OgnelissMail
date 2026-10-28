// lib/features/settings/screens/swipe_settings_screen.dart
//
// Настройка действий по свайпу в списке писем.
//
// Устройство экрана намеренно простое. В некоторых клиентах настройка свайпов
// сделана длинным списком из полутора десятков операций с перетаскиванием —
// выглядит богато, но разбираться в нём долго, а меняют такие настройки один
// раз. Здесь четыре понятные позиции: по два действия на каждую сторону.
//
// Поведение при разном числе действий:
//  · одно действие на сторону — полный свайп выполняет его сразу;
//  · два — кнопки раскрываются и ждут выбора.
// Это подсказано прямо на экране, чтобы результат не был сюрпризом.

import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/settings_group.dart';

/// Действия свайпа, доступные в беседе.
/// Действия свайпа в «Разобрать входящие» (после действия — следующее письмо).
const triageSwipeActions = [
  SwipeAction.archive,
  SwipeAction.delete,
  SwipeAction.markRead,
  SwipeAction.snooze,
  SwipeAction.control,
  SwipeAction.flag,
  SwipeAction.reply,
  SwipeAction.none,
];

const conversationSwipeActions = [
  SwipeAction.markRead,
  SwipeAction.flag,
  SwipeAction.archive,
  SwipeAction.delete,
  SwipeAction.moveToJunk,
  SwipeAction.snooze,
  SwipeAction.control,
  SwipeAction.reply,
  SwipeAction.forward,
  SwipeAction.none,
];

class SwipeSettingsScreen extends ConsumerWidget {
  const SwipeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('swipeSettings')), actions: [
        HelpButton(text: l10n.tr('swipeSingleHint'), title: l10n.tr('swipeSettings')),
      ])),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.xs, Space.l, 0),
            child: Text(l10n.tr('swipeHint'),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          SettingsSectionTitle(l10n.tr('swipeRight')),
          SettingsGroup(children: [
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeFirstAction'),
              value: settings.swipeLeftPrimary,
              onChanged: notifier.setSwipeLeftPrimary,
            ),
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeSecondAction'),
              value: settings.swipeLeftSecondary,
              onChanged: notifier.setSwipeLeftSecondary,
            ),
          ]),
          SettingsSectionTitle(l10n.tr('swipeLeft')),
          SettingsGroup(children: [
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeFirstAction'),
              value: settings.swipeRightPrimary,
              onChanged: notifier.setSwipeRightPrimary,
            ),
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeSecondAction'),
              value: settings.swipeRightSecondary,
              onChanged: notifier.setSwipeRightSecondary,
            ),
          ]),
          // Беседа: свой набор, по одному действию на сторону (09.10.2026).
          SettingsSectionTitle(l10n.tr('swipeInConversation')),
          SettingsGroup(children: [
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeRight'),
              value: settings.swipeConvLeft,
              onChanged: notifier.setSwipeConvLeft,
              only: conversationSwipeActions,
            ),
            _actionTile(
              context, l10n,
              title: l10n.tr('swipeLeft'),
              value: settings.swipeConvRight,
              onChanged: notifier.setSwipeConvRight,
              only: conversationSwipeActions,
            ),
          ]),
          // Живой свайп (1.6.21): значок виден сразу, у порога — отклик.
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.animation,
              title: l10n.tr('swipeAnimatedTitle'),
              subtitle: l10n.tr('swipeAnimatedSub'),
              value: settings.swipeAnimated,
              onChanged: notifier.setSwipeAnimated,
            ),
          ]),
          // «Разобрать входящие»: как в ленте или свой набор (10.10.2026).
          SettingsSectionTitle(l10n.tr('swipeInTriage')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.tune,
              title: l10n.tr('swipeTriageCustom'),
              subtitle: l10n.tr(settings.swipeTriageCustom ? 'swipeTriageCustomOn' : 'swipeTriageAsList'),
              value: settings.swipeTriageCustom,
              onChanged: notifier.setSwipeTriageCustom,
            ),
            if (settings.swipeTriageCustom) ...[
              _actionTile(
                context, l10n,
                title: l10n.tr('swipeRight'),
                value: settings.swipeTriageLeft,
                onChanged: notifier.setSwipeTriageLeft,
                only: triageSwipeActions,
              ),
              _actionTile(
                context, l10n,
                title: l10n.tr('swipeLeft'),
                value: settings.swipeTriageRight,
                onChanged: notifier.setSwipeTriageRight,
                only: triageSwipeActions,
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    AppLocalizations l10n, {
    required String title,
    required SwipeAction value,
    required ValueChanged<SwipeAction> onChanged,
    List<SwipeAction>? only,
  }) {
    return SettingsItem(
      icon: _icon(value),
      title: title,
      subtitle: _label(l10n, value),
      onTap: () async {
        final picked = await showAppSheet<SwipeAction>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(Space.l),
                  child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                ),
                for (final a in only ?? SwipeAction.values)
                  // «На контроле» выключено в «Функциях» — пункта нет.
                  if (a != SwipeAction.control ||
                      ProviderScope.containerOf(ctx, listen: false).read(settingsProvider).mailControl)
                  ListTile(
                    leading: Icon(_icon(a)),
                    title: Text(_label(l10n, a)),
                    selected: a == value,
                    onTap: () => Navigator.pop(ctx, a),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }

  String _label(AppLocalizations l10n, SwipeAction a) => switch (a) {
        SwipeAction.markRead => l10n.tr('markRead'),
        SwipeAction.flag => l10n.tr('flag'),
        SwipeAction.archive => l10n.tr('archive'),
        SwipeAction.delete => l10n.delete,
        SwipeAction.moveToJunk => l10n.tr('moveToJunk'),
        SwipeAction.moveTo => l10n.tr('move'),
        SwipeAction.snooze => l10n.tr('later'),
        SwipeAction.reply => l10n.tr('reply'),
        SwipeAction.forward => l10n.tr('forward'),
        SwipeAction.createTask => l10n.tr('tasksLabel'),
        SwipeAction.findBySender => l10n.tr('from'),
        SwipeAction.none => l10n.tr('none'),
        SwipeAction.control => l10n.tr('controlSet'),
      };

  IconData _icon(SwipeAction a) => switch (a) {
        SwipeAction.markRead => AppIcons.mark_email_read,
        SwipeAction.flag => AppIcons.flag,
        SwipeAction.archive => AppIcons.archive,
        SwipeAction.delete => AppIcons.delete,
        SwipeAction.moveToJunk => AppIcons.block,
        SwipeAction.moveTo => AppIcons.drive_file_move,
        SwipeAction.snooze => AppIcons.watch_later,
        SwipeAction.reply => AppIcons.reply,
        SwipeAction.forward => AppIcons.forward,
        SwipeAction.createTask => AppIcons.add_task,
        SwipeAction.findBySender => AppIcons.person_search,
        SwipeAction.none => Icons.block_flipped,
        SwipeAction.control => AppIcons.task_alt,
      };
}

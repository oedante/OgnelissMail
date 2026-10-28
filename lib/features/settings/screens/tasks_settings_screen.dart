// lib/features/settings/screens/tasks_settings_screen.dart
// Настройки модуля To Do (Задачи): вид по умолчанию, скрытие выполненных, напоминания.

import '../../../widgets/ui/app_radio_tile.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/settings_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../help/faq_screen.dart' show FaqButton;
import '../../../l10n/app_localizations.dart';
import '../providers/module_settings_provider.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';

class TasksSettingsScreen extends ConsumerWidget {
  const TasksSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(moduleSettingsProvider);
    final n = ref.read(moduleSettingsProvider.notifier);

    String viewLabel(TaskDefaultView v) {
      switch (v) {
        case TaskDefaultView.all: return l10n.tr('all');
        case TaskDefaultView.today: return l10n.tr('today');
        case TaskDefaultView.upcoming: return l10n.tr('upcoming');
      }
    }

    return Scaffold(
      appBar: TextScaleCapBar(child: AppBar(
        title: Text(l10n.tr('toDo')),
        actions: const [FaqButton(section: 'tasks')],
      )),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.xl),
        children: [
          SettingsSectionTitle(l10n.tr('display')),
          SettingsGroup(children: [
            SettingsItem(
              icon: AppIcons.filter_list,
              title: l10n.tr('defaultView'),
              // «Сегодня» убрано — день смотрят в календаре.
              subtitle: viewLabel(s.taskView == TaskDefaultView.today ? TaskDefaultView.upcoming : s.taskView),
              onTap: () => showAppSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: TaskDefaultView.values.where((v) => v != TaskDefaultView.today).map((v) => AppRadioTile<TaskDefaultView>(
                          title: Text(viewLabel(v)),
                          value: v,
                          groupValue: s.taskView == TaskDefaultView.today ? TaskDefaultView.upcoming : s.taskView,
                          onChanged: (sel) {
                            n.setTaskView(sel!);
                            Navigator.pop(ctx);
                          },
                        )).toList(),
                  ),
                ),
              ),
            ),
          ]),
          // «Скрывать выполненные» убрано: выполненные задачи и так живут в
          // отдельном списке «Выполнено»; переключатель ни на что не влиял.
          SettingsSectionTitle(l10n.tr('reminders')),
          SettingsGroup(children: [
            SettingsSwitchItem(
              icon: AppIcons.notification_add,
              title: l10n.tr('defaultReminder'),
              subtitle: l10n.tr('addReminderOnDueTask'),
              value: s.taskReminderDefault,
              onChanged: n.setTaskReminderDefault,
            ),
          ]),
        ],
      ),
    );
  }
}

// lib/features/settings/settings_search.dart
// Поиск по настройкам (Ф4, docs/plan/UI_REDESIGN.md): по названию настройки
// и экрана на языке интерфейса. Нажатие открывает экран, где она лежит.
// Раньше «где включаются тихие часы» приходилось искать, открывая разделы
// по очереди.

import '../../core/constants/app_constants.dart' show kRulesAndCategoriesEnabled;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';

class _Entry {
  final String key;
  final String screenKey;
  final IconData icon;
  final String route;

  /// Настройка есть только на Android (1.6.49: фон виджетов).
  final bool androidOnly;

  /// Только на телефоне и планшете — Android и iPhone (1.7.0: тема виджетов).
  final bool mobileOnly;

  /// Только на iPhone и iPad (1.7.2: сигналы сервера).
  final bool iosOnly;
  const _Entry(this.key, this.screenKey, this.icon, this.route,
      {this.androidOnly = false, this.mobileOnly = false, this.iosOnly = false});
}

const _entries = <_Entry>[
  // Уведомления
  _Entry('notifyNewMail', 'notifications', AppIcons.notifications, '/settings/notifications'),
  _Entry('sound', 'notifications', AppIcons.volume_up, '/settings/notifications'),
  _Entry('vibration', 'notifications', AppIcons.vibration, '/settings/notifications'),
  _Entry('quietHours', 'notifications', AppIcons.bedtime, '/settings/notifications'),
  _Entry('focusMode', 'notifications', AppIcons.do_not_disturb_on, '/settings/notifications'),
  // 1.6.45: пробное уведомление.
  _Entry('ntfTestAction', 'notifications', AppIcons.notifications_active, '/settings/notifications'),
  _Entry('vipManage', 'notifications', AppIcons.star, '/vip-settings'),
  _Entry('rulesSection', 'notifications', AppIcons.rule, '/vip-settings'),
  // 1.7.2: сигналы сервера для проверки почты в фоне на iPhone.
  _Entry('pushWakeTitle', 'notifications', AppIcons.cloud_sync, '/settings/notifications', iosOnly: true),
  _Entry('autoReplies', 'emailSettings', AppIcons.beach_access, '/settings/auto-reply'),
  // Общие
  _Entry('theme', 'general', AppIcons.palette, '/settings/general'),
  _Entry('language', 'general', AppIcons.language, '/settings/general'),
  _Entry('fontSize', 'general', AppIcons.format_size, '/settings/general'),
  // Специальные возможности
  _Entry('highContrast', 'accessibility', AppIcons.contrast, '/settings/accessibility'),
  _Entry('colorBlind', 'accessibility', AppIcons.palette, '/settings/accessibility'),
  _Entry('dyslexiaFont', 'accessibility', AppIcons.font_download, '/settings/accessibility'),
  _Entry('reduceMotion', 'accessibility', AppIcons.animation, '/settings/accessibility'),
  // Почта
  _Entry('startupFolder', 'emailSettings', AppIcons.start, '/settings/mail'),
  _Entry('threading', 'emailSettings', AppIcons.forum, '/settings/mail'),
  _Entry('quickFilters', 'emailSettings', AppIcons.filter_list, '/settings/mail'),
  _Entry('quickReplyBar', 'emailSettings', AppIcons.quickreply, '/settings/mail'),
  _Entry('mailSwipePager', 'emailSettings', AppIcons.swipe, '/settings/mail'),
  // Кнопки под письмом и вопрос перед удалением (1.7.3).
  _Entry('mailBarOrder', 'emailSettings', AppIcons.view_week, '/settings/mail'),
  _Entry('confirmMailDelete', 'emailSettings', AppIcons.delete, '/settings/mail'),
  _Entry('widgetBgTitle', 'general', AppIcons.palette, '/settings/general', androidOnly: true),
  _Entry('widgetThemeTitle', 'general', AppIcons.palette, '/settings/general', mobileOnly: true),
  _Entry('faqTitle', 'about', AppIcons.help, '/settings/faq'),
  _Entry('fetchMode', 'emailSettings', AppIcons.download, '/settings/mail'),
  _Entry('downloadAttachmentsWifiOnly', 'emailSettings', AppIcons.wifi, '/settings/mail'),
  _Entry('swipeSettings', 'swipeSettings', AppIcons.swipe, '/settings/swipes'),
  _Entry('swipeInTriage', 'swipeSettings', AppIcons.swipe, '/settings/swipes'),
  // Фильтры на сервере — выбор ящика в «Правилах» (1.7.3), у ящика — в его настройках.
  _Entry('sieveTitle', 'vipRulesTitle', AppIcons.filter_list, '/vip-settings'),
  // Exchange на сервере (EWS, 11.10.2026)
  _Entry('srvRulesTitle', 'vipRulesTitle', AppIcons.rule, '/settings/server-rules'),
  _Entry('srvRecoverTitle', 'vipRulesTitle', AppIcons.restore, '/settings/recover-deleted'),
  // Категории и автоматизация скрыты (kRulesAndCategoriesEnabled).
  if (kRulesAndCategoriesEnabled) _Entry('categories', 'categories', AppIcons.label, '/settings/categories'),
  _Entry('templatesSignature', 'templatesSignature', AppIcons.article, '/settings/templates'),
  if (kRulesAndCategoriesEnabled) _Entry('automation', 'automation', AppIcons.rule, '/settings/automation'),
  // Функции
  _Entry('undoSendWindow', 'emailSettings', AppIcons.undo, '/settings/mail'),
  _Entry('photoSendSize', 'emailSettings', AppIcons.photo_size_select_large, '/settings/mail'),
  _Entry('confirmRecipients', 'emailSettings', AppIcons.groups, '/settings/mail'),
  _Entry('antiPhishing', 'emailSettings', AppIcons.phishing, '/settings/mail'),
  _Entry('tasksTab', 'profileFeatures', AppIcons.check_box, '/settings/profile'),
  _Entry('myDay', 'profileFeatures', AppIcons.myDay, '/settings/profile'),
  _Entry('controlFilter', 'profileFeatures', AppIcons.task_alt, '/settings/profile'),
  _Entry('digestSetting', 'profileFeatures', AppIcons.notifications_active, '/settings/profile'),
  // Разделы
  _Entry('defaultView', 'calendar', AppIcons.view_module, '/settings/calendar'),
  _Entry('weekStartsOn', 'calendar', AppIcons.today, '/settings/calendar'),
  _Entry('weekNumbers', 'calendar', AppIcons.format_list_numbered, '/settings/calendar'),
  _Entry('defaultReminder', 'calendar', AppIcons.notifications, '/settings/calendar'),
  _Entry('eventFallbackReminder', 'calendar', AppIcons.notifications_active, '/settings/calendar'),
  _Entry('dynamicColor', 'general', AppIcons.palette, '/settings/general'),
  _Entry('allowRotation', 'general', AppIcons.screen_rotation, '/settings/general'),
  _Entry('warmPage', 'general', AppIcons.wb_sunny, '/settings/general'),
  _Entry('eventAlarmClock', 'calendar', AppIcons.alarm, '/settings/calendar'),
  _Entry('deviceCalendar', 'calendar', AppIcons.upload, '/settings/calendar'),
  _Entry('sortOrder', 'contacts', AppIcons.sort_by_alpha, '/settings/contacts'),
  _Entry('showPhotos', 'contacts', AppIcons.account_circle, '/settings/contacts'),
  _Entry('deviceAddressBook', 'contacts', AppIcons.import_contacts, '/settings/contacts'),
  _Entry('defaultView', 'toDo', AppIcons.filter_list, '/settings/tasks'),
  _Entry('defaultReminder', 'toDo', AppIcons.notification_add, '/settings/tasks'),
  _Entry('textPreview', 'notes', AppIcons.notes, '/settings/notes'),
  // Аккаунты, защита, данные
  _Entry('accounts', 'accounts', AppIcons.manage_accounts, '/settings/accounts'),
  _Entry('addAccount', 'accounts', AppIcons.add, '/login?mode=add'),
  _Entry('accountGroups', 'accounts', AppIcons.folder_shared, '/settings/groups'),
  // 1.8.0: синхронизация, фон, сертификаты, защита данных, журнал, сброс —
  // в «Расширенных настройках».
  _Entry('advancedSettings', 'settings', AppIcons.tune, '/settings/advanced'),
  _Entry('permissions', 'advancedSettings', AppIcons.admin_panel_settings, '/settings/permissions'),
  _Entry('autoSyncAll', 'advancedSettings', AppIcons.sync, '/settings/advanced'),
  _Entry('scheduleTitle', 'advancedSettings', AppIcons.schedule, '/settings/delivery-schedule'),
  _Entry('checkScheduled', 'advancedSettings', AppIcons.schedule, '/settings/delivery-schedule'),
  _Entry('runInBackground', 'permissions', AppIcons.cloud_sync, '/settings/permissions'),
  _Entry('bgNotifHide', 'permissions', AppIcons.notifications_off, '/settings/permissions'),
  _Entry('pinLock', 'security', AppIcons.pin, '/settings'),
  _Entry('vipRulesTitle', 'sectionMail', AppIcons.rule, '/vip-settings'),
  _Entry('connectionSecurity', 'advancedSettings', AppIcons.verified_user, '/settings/security'),
  _Entry('dlpTitle', 'advancedSettings', AppIcons.shield, '/settings/dlp'),
  _Entry('syncConflicts', 'advancedSettings', AppIcons.sync_problem, '/settings/conflicts'),
  _Entry('resetApp', 'advancedSettings', AppIcons.delete_forever, '/settings/advanced'),
  _Entry('profileFeatures', 'advancedSettings', AppIcons.widgets, '/settings/profile'),
  _Entry('backupTitle', 'backupTitle', AppIcons.settings_backup_restore, '/settings/backup'),
  // Архив Ogneliss (1.7.3).
  _Entry('ognaArchive', 'ognaArchive', AppIcons.inventory_2, '/settings/archive'),
  _Entry('archiveAuto', 'ognaArchive', AppIcons.schedule, '/settings/archive'),
  _Entry('archiveCopySave', 'ognaArchive', AppIcons.cloud_upload, '/settings/archive'),
  _Entry('archiveAppSection', 'ognaArchive', AppIcons.settings_backup_restore, '/settings/archive'),
  _Entry('storage', 'storage', AppIcons.storage, '/settings/storage'),
  _Entry('logsTitle', 'advancedSettings', AppIcons.bug_report, '/settings/logs'),
  // Бывшие «Возможности» (1.6.1 — в «Почте» и «Календаре»).
  _Entry('expRecipTitle', 'emailSettings', AppIcons.group, '/settings/mail'),
  _Entry('expRulesTitle', 'emailSettings', AppIcons.rule, '/settings/mail'),
  _Entry('expSpareTitle', 'emailSettings', AppIcons.bolt, '/settings/mail'),
  _Entry('expNativeTitle', 'emailSettings', AppIcons.article, '/settings/mail'),
  _Entry('expBoardTitle', 'calendar', AppIcons.view_module, '/settings/calendar'),
  _Entry('meetingPrepTitle', 'calendar', AppIcons.groups, '/settings/calendar'),
  _Entry('expHubTitle', 'calendar', AppIcons.calendar_today, '/settings/calendar'),
  _Entry('about', 'about', AppIcons.info, '/settings/about'),
];

class SettingsSearchDelegate extends SearchDelegate<void> {
  final AppLocalizations l10n;
  SettingsSearchDelegate(this.l10n) : super(searchFieldLabel: l10n.tr('settingsSearchHint'));

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
            icon: const Icon(AppIcons.clear),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(AppIcons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _list(context);

  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final q = query.trim().toLowerCase();
    final router = GoRouter.of(context);
    final android = defaultTargetPlatform == TargetPlatform.android;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final mobile = android || ios;
    final hits = [
      for (final e in _entries)
        if ((android || !e.androidOnly) && (mobile || !e.mobileOnly) && (ios || !e.iosOnly) &&
            (q.isEmpty ||
                l10n.tr(e.key).toLowerCase().contains(q) ||
                l10n.tr(e.screenKey).toLowerCase().contains(q)))
          e,
    ];
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Text(l10n.tr('noResults'), style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final e = hits[i];
        final title = l10n.tr(e.key);
        final screen = l10n.tr(e.screenKey);
        return ListTile(
          leading: Icon(e.icon, color: scheme.primary),
          title: Text(title),
          subtitle: screen == title ? null : Text(screen),
          trailing: const Icon(AppIcons.chevron_right),
          onTap: () {
            close(context, null);
            // Настройка на главном экране настроек — поиск открыт с него,
            // достаточно закрыть поиск.
            if (e.route != '/settings') router.push(e.route);
          },
        );
      },
    );
  }
}

// lib/features/help/faq_content.dart
// Вопросы и ответы (1.7.1, просьба владельца 20.10.2026: «FAQ для разделов
// приложения и настроек»). Здесь — только порядок разделов и вопросов,
// значки и экраны настроек ([FaqItem.route], кнопка «Открыть»). Тексты — в
// файлах строк assets/l10n/<код>.xml (1.7.3, как все строки интерфейса):
// faq_<раздел>_title, faq_<раздел>_<n>_q и faq_<раздел>_<n>_a.
//
// Меняется поведение приложения — поправьте ответ (tool/dev/l10n_set.py).
// Новый вопрос — строки faq_<раздел>_<n>_q/_a во всех языках и строка
// FaqItem здесь.

import 'package:flutter/widgets.dart' show IconData;

import '../../core/theme/app_icons.dart';
import '../../l10n/app_localizations.dart';

class FaqItem {
  /// «<раздел>_<n>»: ключи строк faq_<key>_q и faq_<key>_a.
  final String key;
  final String? route;
  const FaqItem(this.key, {this.route});

  String q(AppLocalizations l10n) => l10n.tr('faq_${key}_q');
  String a(AppLocalizations l10n) => l10n.tr('faq_${key}_a');
}

class FaqSection {
  final String id;
  final IconData icon;
  final List<FaqItem> items;
  const FaqSection({required this.id, required this.icon, required this.items});

  String title(AppLocalizations l10n) => l10n.tr('faq_${id}_title');
}

const faqSections = <FaqSection>[
  FaqSection(id: 'mail', icon: AppIcons.mail, items: [
    FaqItem('mail_1', route: '/settings/mail'),
    FaqItem('mail_2', route: '/settings/mail'),
    FaqItem('mail_3'),
    FaqItem('mail_4', route: '/settings/accounts'),
    FaqItem('mail_5'),
    FaqItem('mail_6'),
    FaqItem('mail_7', route: '/settings/mail'),
    FaqItem('mail_8'),
    // Увеличение письма разведением пальцев (1.8.0).
    FaqItem('mail_9', route: '/settings/general'),
  ]),
  FaqSection(id: 'drafts', icon: AppIcons.drafts, items: [
    FaqItem('drafts_1'),
    FaqItem('drafts_2'),
    FaqItem('drafts_3'),
    FaqItem('drafts_4'),
    FaqItem('drafts_5', route: '/settings/mail'),
    FaqItem('drafts_6', route: '/settings/mail'),
    FaqItem('drafts_7'),
    FaqItem('drafts_8'),
    FaqItem('drafts_9', route: '/settings/signatures'),
    FaqItem('drafts_10'),
  ]),
  FaqSection(id: 'conv', icon: AppIcons.forum, items: [
    FaqItem('conv_1', route: '/settings/mail'),
    FaqItem('conv_2'),
  ]),
  FaqSection(id: 'calendar', icon: AppIcons.calendar_today, items: [
    FaqItem('calendar_1'),
    FaqItem('calendar_2'),
    FaqItem('calendar_3'),
    FaqItem('calendar_4', route: '/settings/calendar'),
    FaqItem('calendar_5'),
    FaqItem('calendar_6'),
  ]),
  FaqSection(id: 'contacts', icon: AppIcons.contacts, items: [
    FaqItem('contacts_1', route: '/vip-settings'),
    FaqItem('contacts_2'),
    FaqItem('contacts_3'),
    FaqItem('contacts_4'),
    FaqItem('contacts_5'),
  ]),
  FaqSection(id: 'tasks', icon: AppIcons.check_box, items: [
    FaqItem('tasks_1'),
    FaqItem('tasks_2'),
    FaqItem('tasks_3'),
  ]),
  FaqSection(id: 'notify', icon: AppIcons.notifications, items: [
    FaqItem('notify_1', route: '/settings/notifications'),
    FaqItem('notify_2', route: '/settings/folder-sync'),
    FaqItem('notify_3', route: '/settings/permissions'),
    FaqItem('notify_4', route: '/settings/notifications'),
    FaqItem('notify_5', route: '/settings/notifications'),
  ]),
  FaqSection(id: 'widgets', icon: AppIcons.widgets, items: [
    FaqItem('widgets_1'),
    FaqItem('widgets_2', route: '/settings/general'),
    FaqItem('widgets_3', route: '/settings/general'),
    FaqItem('widgets_4'),
    FaqItem('widgets_5'),
  ]),
  FaqSection(id: 'exchange', icon: AppIcons.business, items: [
    FaqItem('exchange_1', route: '/settings/accounts'),
    FaqItem('exchange_2', route: '/settings/accounts'),
    FaqItem('exchange_3'),
  ]),
  // Архив Ogneliss (1.7.3).
  FaqSection(id: 'archive', icon: AppIcons.inventory_2, items: [
    FaqItem('archive_1', route: '/settings/archive'),
    FaqItem('archive_2', route: '/settings/archive'),
    FaqItem('archive_3', route: '/settings/archive'),
    FaqItem('archive_4', route: '/settings/archive'),
    FaqItem('archive_5', route: '/settings/archive'),
  ]),
  FaqSection(id: 'security', icon: AppIcons.lock, items: [
    FaqItem('security_1'),
    FaqItem('security_2', route: '/settings'),
    FaqItem('security_3', route: '/settings/backup'),
  ]),
  FaqSection(id: 'settings', icon: AppIcons.settings, items: [
    FaqItem('settings_1'),
    FaqItem('settings_2', route: '/settings/logs'),
    // Вход по адресу (1.8.0).
    FaqItem('settings_3', route: '/settings/accounts'),
  ]),
];

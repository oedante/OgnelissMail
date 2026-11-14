// lib/core/navigation/app_router.dart
// Финальный роутер — ВСЕ маршруты приложения.

import '../../features/mail/screens/mail_list_pager.dart';
import '../../features/contacts/my_contact.dart' show MyContactScreen;
import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import '../theme/app_theme.dart';
import '../../data/models/email_model.dart';
import '../../data/database/app_database.dart' show CalendarEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

import '../../splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/onboarding_screen.dart';
import '../../features/auth/screens/license_agreement_screen.dart';
import '../../features/mail/screens/mail_list_screen.dart';
import '../../features/mail/screens/mail_detail_screen.dart';
import '../../features/mail/screens/triage_screen.dart';
import '../../features/mail/screens/conversation_screen.dart';
import '../../features/mail/screens/attachment_hub_screen.dart';
import '../../features/compose/screens/compose_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/calendar/screens/create_event_screen.dart';
import '../../features/calendar/screens/event_details_screen.dart';
import '../../features/contacts/screens/contacts_screen.dart';
import '../../features/tasks/screens/tasks_screen.dart';
import '../../features/notes/screens/notes_screen.dart';
import '../../features/settings/screens/backup_screen.dart';
import '../../features/archive/screens/archive_screen.dart';
import '../../features/archive/screens/archive_list_screen.dart';
import '../../features/archive/screens/archive_message_screen.dart';
import '../../features/archive/screens/archive_items_screen.dart';
import '../../features/archive/screens/archive_hub_screen.dart';
import '../../features/archive/archive_providers.dart' show archiveAccountsParam;
import '../../features/my_day/my_day_screen.dart';
import '../../features/assignments/assignments_screen.dart';
import '../../features/assignments/assignment_screen.dart';
import '../../features/mail/screens/subscriptions_screen.dart';
import '../../features/notes/screens/note_edit_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/tracker_settings_screen.dart';
import '../../features/settings/widgets/settings_split.dart';
import '../../features/settings/screens/advanced_settings_screen.dart';
import '../../features/settings/screens/rules_screen.dart';
import '../../features/settings/screens/exchange_tools_screen.dart';
import '../../features/settings/screens/sieve_rules_screen.dart';
import '../../features/settings/screens/delivery_schedule_screen.dart';
import '../../features/settings/screens/vip_settings_screen.dart';
import '../../features/settings/screens/accessibility_screen.dart';
import '../../features/settings/screens/dlp_settings_screen.dart';
import '../../features/settings/screens/automation_screen.dart';
import '../../features/settings/screens/about_screen.dart';
import '../../features/help/faq_screen.dart';
import '../../features/settings/screens/swipe_settings_screen.dart';
import '../../features/settings/screens/account_groups_screen.dart';
import '../../features/auth/screens/shared_mailbox_screen.dart';
import '../../features/settings/screens/general_settings_screen.dart';
import '../../features/settings/screens/profile_settings_screen.dart';
import '../../features/settings/screens/mail_settings_screen.dart';
import '../../features/settings/screens/calendar_settings_screen.dart';
import '../../features/settings/screens/conflict_settings_screen.dart';
import '../../features/settings/screens/contacts_settings_screen.dart';
import '../../features/settings/screens/tasks_settings_screen.dart';
import '../../features/settings/screens/notes_settings_screen.dart';
import '../../features/settings/screens/category_settings_screen.dart';
import '../../features/settings/screens/templates_settings_screen.dart';
import '../../features/storage/screens/storage_screen.dart';
import '../../features/contacts/screens/duplicate_contacts_screen.dart';
import '../../features/settings/screens/log_viewer_screen.dart';
import '../../features/settings/screens/auto_reply_screen.dart';
import '../../features/settings/screens/signatures_settings_screen.dart';
import '../../features/settings/screens/accounts_settings_screen.dart';
import '../../features/settings/screens/account_screen.dart';
import '../../features/settings/screens/security_settings_screen.dart';
import '../../features/settings/screens/permissions_settings_screen.dart';
import '../../features/settings/screens/setup_mailbox_screen.dart';
import '../../features/settings/screens/aliases_settings_screen.dart';
import '../../features/settings/screens/notifications_settings_screen.dart';
import '../../widgets/navigation/main_shell.dart';
import '../../features/settings/screens/folder_sync_settings_screen.dart';
import '../../widgets/common/text_scale_cap.dart';
import '../../widgets/common/wide_frame.dart';
import '../../widgets/common/mail_open_motion.dart' show MailOpenPage;
import '../../features/settings/screens/appearance_screen.dart';
import '../../features/settings/screens/experimental_settings_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    debugLogDiagnostics: false,
    routes: [
      GoRoute(path: '/splash', name: 'splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', name: 'onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/license', name: 'license', builder: (_, __) => const LicenseAgreementScreen()),
      GoRoute(path: '/login', name: 'login', builder: (_, state) =>
          LoginScreen(
            isAddMode: state.uri.queryParameters['mode'] == 'add',
            reauthAccountId: state.uri.queryParameters['reauth'],
          )),

      // Main Shell
      ShellRoute(
        builder: (_, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/mail',
            name: 'mail',
            builder: (_, __) => const MailListScreen(),
            routes: [
              // Письмо из ленты — страницей MailOpenPage (1.9.x): с «Анимацией
              // открытия письма» портрет и тема летят из строки, письмо
              // закрывается свайпом вниз; без неё — как MaterialPage.
              GoRoute(
                path: 'detail/:emailId',
                name: 'mail-detail',
                pageBuilder: (_, state) => _mailPage(
                  state,
                  MailDetailScreen(
                    emailId: state.pathParameters['emailId']!,
                    accountId: state.uri.queryParameters['accountId'] ?? '',
                  ),
                ),
              ),
              // Листание писем ленты свайпом (1.6.49+95). Без списка (адрес
              // открыт заново) — одно письмо.
              GoRoute(
                path: 'pager',
                name: 'mail-pager',
                pageBuilder: (_, state) {
                  final a = state.extra;
                  if (a is MailPagerArgs && a.items.isNotEmpty) return _mailPage(state, MailListPagerScreen(args: a));
                  return _mailPage(
                    state,
                    MailDetailScreen(
                      emailId: state.uri.queryParameters['emailId'] ?? '',
                      accountId: state.uri.queryParameters['accountId'] ?? '',
                    ),
                  );
                },
              ),
              GoRoute(
                path: 'conversation/:convId',
                name: 'mail-conversation',
                builder: (_, state) => ConversationScreen(
                  conversationId: state.pathParameters['convId']!,
                  accountId: state.uri.queryParameters['accountId'] ?? '',
                ),
                routes: [
                  GoRoute(
                    path: ':emailId',
                    name: 'mail-conversation-message',
                    pageBuilder: (_, state) => _mailPage(
                      state,
                      ConversationPagerScreen(
                        conversationId: state.pathParameters['convId']!,
                        emailId: state.pathParameters['emailId']!,
                        accountId: state.uri.queryParameters['accountId'] ?? '',
                        find: state.uri.queryParameters['find'],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(path: '/calendar', name: 'calendar', builder: (_, __) => const CalendarScreen()),
          GoRoute(path: '/contacts', name: 'contacts', builder: (_, __) => const ContactsScreen()),
          GoRoute(path: '/tasks', name: 'tasks', builder: (_, st) => TasksScreen(
                openTaskId: st.uri.queryParameters['task'],
                openAccountId: st.uri.queryParameters['accountId'],
                openNew: st.uri.queryParameters['new'] == '1',
                openText: st.uri.queryParameters['text'],
              )),
          GoRoute(path: '/notes', name: 'notes', builder: (_, __) => const NotesScreen()),
          GoRoute(path: '/my-day', name: 'my-day', builder: (_, __) => const MyDayScreen()),
          // «Поручения» (2.2.0, решение владельца 09.11.2026) и «Вложения» —
          // внутри главного экрана: их можно поставить на нижнюю панель
          // (2.2.0), и панель под ними остаётся. Файлы одного отправителя
          // (?from=, из письма и карточки человека) — отдельной страницей
          // /attachment-hub поверх любого экрана.
          GoRoute(
            path: '/assignments', name: 'assignments',
            builder: (_, __) => const WideFrame(child: AssignmentsScreen()),
          ),
          GoRoute(path: '/files', name: 'files', builder: (_, __) => const AttachmentHubScreen()),
        ],
      ),

      // «Разобрать входящие» — непрочитанные по одному (поверх ленты).
      GoRoute(path: '/triage', name: 'triage', builder: (_, __) => const TriageScreen()),

      // Письмо отдельной страницей поверх любого экрана (1.8.13): из
      // уведомления, ярлыка, виджета и со страниц вне главного экрана
      // (настройки, «Разобрать», «Файлы», встреча). См. [messagePath].
      GoRoute(
        path: '/message/:emailId',
        name: 'message',
        // На широком окне — колонкой по центру, как редактор и встреча.
        builder: (_, state) => WideFrame.wide(
          child: MailDetailScreen(
            emailId: state.pathParameters['emailId']!,
            accountId: state.uri.queryParameters['accountId'] ?? '',
          ),
        ),
      ),

      // Fullscreen dialogs
      GoRoute(
        path: '/compose', name: 'compose',
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: WideFrame.wide(child: ComposeScreen(
            replyToId: state.uri.queryParameters['replyToId'],
            forwardFromId: state.uri.queryParameters['forwardFromId'],
            draftId: state.uri.queryParameters['draftId'],
            accountId: state.uri.queryParameters['accountId'],
            to: state.uri.queryParameters['to'],
            cc: state.uri.queryParameters['cc'],
            bcc: state.uri.queryParameters['bcc'],
            sharedBody: state.uri.queryParameters['body'],
            sharedSubject: state.uri.queryParameters['subject'],
            sharedAttachments: (state.uri.queryParameters['attachments'] ?? '')
                .split('|').where((s) => s.isNotEmpty).toList(),
            replyAll: state.uri.queryParameters['replyAll'] == 'true',
            replyWithAttachments: state.uri.queryParameters['withAttachments'] == 'true',
            quoteFragment: state.uri.queryParameters['fragment'],
            quickText: state.uri.queryParameters['quick'],
          )),
        ),
      ),
      GoRoute(
        path: '/vip-settings', name: 'vip-settings',
        pageBuilder: (_, st) => settingsRoutePage(st, const VipSettingsScreen()),
      ),
      GoRoute(
        path: '/create-event', name: 'create-event',
        pageBuilder: (_, state) {
          final extra = state.extra;
          EmailModel? email;
          DateTime? start, end;
          String? location, title, description, linkedEmailId;
          CalendarEvent? edit, duplicate;
          var allDay = false;
          if (extra is EmailModel) {
            email = extra;
          } else if (extra is CalendarEvent) {
            edit = extra;
          } else if (extra is Map) {
            email = extra['email'] as EmailModel?;
            start = extra['start'] as DateTime?;
            end = extra['end'] as DateTime?;
            location = extra['location'] as String?;
            title = extra['title'] as String?;
            description = extra['description'] as String?;
            duplicate = extra['duplicate'] as CalendarEvent?;
            // Дата из текста письма (1.9.x): весь день, ссылка на письмо.
            allDay = extra['allDay'] == true;
            linkedEmailId = extra['linkedEmailId'] as String?;
            // Правка с новым временем — «Принять предложенное время» (1.6.7).
            edit = extra['edit'] as CalendarEvent?;
          }
          return MaterialPage(
            fullscreenDialog: true,
            child: WideFrame.wide(child: CreateEventScreen(
              editEvent: edit,
              duplicateOf: duplicate,
              sourceEmail: email,
              initialStart: start,
              initialEnd: end,
              initialLocation: location,
              initialTitle: title,
              initialDescription: description,
              initialAllDay: allDay,
              linkedEmailId: linkedEmailId,
            )),
          );
        },
      ),
      // Встреча целиком (из календаря, напоминания, уведомления).
      GoRoute(
        path: '/event/:id', name: 'event-details',
        pageBuilder: (_, state) => MaterialPage(
          child: WideFrame.wide(child: EventDetailsScreen(
            eventId: state.pathParameters['id']!,
            accountId: state.uri.queryParameters['accountId'] ?? '',
          )),
        ),
      ),
      GoRoute(
        path: '/notes/edit', name: 'note-edit',
        pageBuilder: (_, state) => MaterialPage(
          fullscreenDialog: true,
          child: WideFrame.wide(child: NoteEditScreen(noteId: state.extra as String?)),
        ),
      ),
      GoRoute(
        path: '/attachment-hub', name: 'attachment-hub',
        // ?from=адрес — только файлы этого отправителя; ?pick=1 — выбор
        // файлов для письма (14.11.2026).
        builder: (_, st) => AttachmentHubScreen(
          sender: st.uri.queryParameters['from'],
          pick: st.uri.queryParameters['pick'] == '1',
        ),
      ),
      // «Рассылки»: отправители с отпиской (боковое меню, у папок ящика;
      // ?accountId= — только этот ящик).
      GoRoute(
        path: '/subscriptions', name: 'subscriptions',
        builder: (_, st) => WideFrame(child: SubscriptionsScreen(accountId: st.uri.queryParameters['accountId'])),
      ),

      // Карточка поручения (список «Поручения» — в главном экране).
      GoRoute(
        path: '/assignments/:id', name: 'assignment',
        builder: (_, st) => WideFrame(child: AssignmentScreen(id: st.pathParameters['id']!)),
      ),

      // Settings
      GoRoute(
          path: '/settings',
          name: 'settings',
          // В две колонки справа — «Общие», а не второй список.
          pageBuilder: (_, st) => settingsRoutePage(st, const SettingsScreen(), splitChild: const GeneralSettingsScreen())),
      // «Защита от трекеров» — страницей (была окном поверх), чтобы в две
      // колонки открываться справа.
      GoRoute(path: '/settings/trackers', name: 'tracker-settings', pageBuilder: (_, st) => settingsRoutePage(st, const TrackerSettingsScreen())),
      // «Расширенные настройки» приложения (1.8.0).
      GoRoute(path: '/settings/advanced', name: 'advanced-settings', pageBuilder: (_, st) => settingsRoutePage(st, const AdvancedSettingsScreen())),
      GoRoute(path: '/settings/rules', name: 'rules', pageBuilder: (_, st) => settingsRoutePage(st, RulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/accessibility', name: 'accessibility', pageBuilder: (_, st) => settingsRoutePage(st, const AccessibilityScreen())),
      GoRoute(path: '/settings/dlp', name: 'dlp', pageBuilder: (_, st) => settingsRoutePage(st, const DlpSettingsScreen())),
      // «Экспериментальный функционал» (1.10.3): функции на пробе, по
      // умолчанию выключены. Прежние «Возможности» (до 1.6.1) — в «Почте» и
      // «Календаре».
      GoRoute(path: '/settings/experimental', name: 'experimental',
          pageBuilder: (_, st) => settingsRoutePage(st, const ExperimentalSettingsScreen())),
      // Exchange на сервере: правила и «Восстановить удалённые» (EWS).
      GoRoute(path: '/settings/server-rules', name: 'server-rules', pageBuilder: (_, st) => settingsRoutePage(st, ServerRulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/recover-deleted', name: 'recover-deleted', pageBuilder: (_, st) => settingsRoutePage(st, RecoverDeletedScreen(accountId: st.uri.queryParameters['accountId']))),
      // Фильтры на сервере IMAP (Sieve).
      GoRoute(path: '/settings/sieve', name: 'sieve', pageBuilder: (_, st) => settingsRoutePage(st, SieveRulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/delivery-schedule', name: 'delivery-schedule', pageBuilder: (_, st) => settingsRoutePage(st, const DeliveryScheduleScreen())),
      GoRoute(path: '/settings/profile', name: 'profile-settings', pageBuilder: (_, st) => settingsRoutePage(st, const ProfileSettingsScreen())),
      GoRoute(path: '/settings/general', name: 'general-settings', pageBuilder: (_, st) => settingsRoutePage(st, const GeneralSettingsScreen())),
      // «Оформление» (1.9.x): тема, цвета, скругление, плотность ленты.
      GoRoute(path: '/settings/appearance', name: 'appearance', pageBuilder: (_, st) => settingsRoutePage(st, const AppearanceScreen())),
      GoRoute(path: '/settings/mail', name: 'mail-settings', pageBuilder: (_, st) => settingsRoutePage(st, const MailSettingsScreen())),
      // Настройки почты частями (12.11.2026).
      GoRoute(path: '/settings/mail/compose', name: 'mail-settings-compose', pageBuilder: (_, st) => settingsRoutePage(st, const MailSettingsScreen(part: MailSettingsPart.compose))),
      GoRoute(path: '/settings/mail/files', name: 'mail-settings-files', pageBuilder: (_, st) => settingsRoutePage(st, const MailSettingsScreen(part: MailSettingsPart.files))),
      GoRoute(path: '/settings/mail/translate', name: 'mail-settings-translate', pageBuilder: (_, st) => settingsRoutePage(st, const MailSettingsScreen(part: MailSettingsPart.translate))),
      GoRoute(path: '/settings/mail/safety', name: 'mail-settings-safety', pageBuilder: (_, st) => settingsRoutePage(st, const MailSettingsScreen(part: MailSettingsPart.safety))),
      GoRoute(path: '/settings/calendar', name: 'calendar-settings', pageBuilder: (_, st) => settingsRoutePage(st, const CalendarSettingsScreen())),
      GoRoute(path: '/settings/contacts', name: 'contacts-settings', pageBuilder: (_, st) => settingsRoutePage(st, const ContactsSettingsScreen())),
      GoRoute(path: '/settings/tasks', name: 'tasks-settings', pageBuilder: (_, st) => settingsRoutePage(st, const TasksSettingsScreen())),
      GoRoute(path: '/settings/notes', name: 'notes-settings', pageBuilder: (_, st) => settingsRoutePage(st, const NotesSettingsScreen())),
      GoRoute(path: '/settings/categories', name: 'category-settings', pageBuilder: (_, st) => settingsRoutePage(st, const CategorySettingsScreen())),
      GoRoute(path: '/settings/templates', name: 'templates-settings', pageBuilder: (_, st) => settingsRoutePage(st, const TemplatesSettingsScreen())),
      GoRoute(path: '/settings/storage', name: 'storage', pageBuilder: (_, st) => settingsRoutePage(st, const StorageScreen())),
      GoRoute(path: '/settings/backup', name: 'backup', pageBuilder: (_, st) => settingsRoutePage(st, const BackupScreen())),
      // Архив Ogneliss (1.7.3): настройки, папки и письма архива, поиск.
      GoRoute(path: '/settings/archive', name: 'ogna-archive', pageBuilder: (_, st) => settingsRoutePage(st, const ArchiveScreen())),
      GoRoute(
          path: '/archive/folder/:id',
          name: 'ogna-folder',
          builder: (_, st) => WideFrame(child: ArchiveListScreen(folderId: int.tryParse(st.pathParameters['id'] ?? '')))),
      // Весь архив (1.8.14): все ящики, встречи, задачи и контакты — как
      // «Файлы» для вложений. В меню — только архив выбранного ящика.
      GoRoute(path: '/archive', name: 'ogna-hub', builder: (_, __) => const WideFrame(child: ArchiveHubScreen())),
      GoRoute(
          path: '/archive/search',
          name: 'ogna-search',
          builder: (_, st) => WideFrame(
              child: ArchiveListScreen(
                  query: st.uri.queryParameters['q'],
                  accounts: archiveAccountsParam(st.uri.queryParameters['accounts'])))),
      GoRoute(
          path: '/archive/message/:id',
          name: 'ogna-message',
          builder: (_, st) => WideFrame(child: ArchiveMessageScreen(id: int.tryParse(st.pathParameters['id'] ?? '') ?? 0))),
      GoRoute(
          path: '/archive/items/:kind',
          name: 'ogna-items',
          builder: (_, st) => WideFrame(
              child: ArchiveItemsScreen(
                  kind: st.pathParameters['kind'] ?? 'events',
                  accounts: archiveAccountsParam(st.uri.queryParameters['accounts'])))),
      GoRoute(path: '/settings/folder-sync', name: 'folderSync', pageBuilder: (_, st) => settingsRoutePage(st, FolderSyncSettingsScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/conflicts', name: 'conflicts', pageBuilder: (_, st) => settingsRoutePage(st, const ConflictSettingsScreen())),
      GoRoute(path: '/contacts/duplicates', name: 'contacts-duplicates', builder: (_, __) => const WideFrame(child: DuplicateContactsScreen())),
      GoRoute(path: '/contacts/me', name: 'my-contact', builder: (_, __) => const WideFrame(child: MyContactScreen())),
      GoRoute(path: '/settings/logs', name: 'log-viewer', pageBuilder: (_, st) => settingsRoutePage(st, const LogViewerScreen(), maxWidth: double.infinity)),
      GoRoute(path: '/settings/auto-reply', name: 'auto-reply', pageBuilder: (_, st) => settingsRoutePage(st, AutoReplyScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/signatures', name: 'signatures-settings', pageBuilder: (_, st) => settingsRoutePage(st, SignaturesSettingsScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/accounts', name: 'accounts-settings', pageBuilder: (_, st) => settingsRoutePage(st, const AccountsSettingsScreen())),
      GoRoute(path: '/settings/account/:id', name: 'account-settings', pageBuilder: (_, st) => settingsRoutePage(st, AccountScreen(accountId: st.pathParameters['id']!))),
      // «Расширенные настройки» ящика (1.8.0).
      GoRoute(path: '/settings/account/:id/advanced', name: 'account-advanced', pageBuilder: (_, st) => settingsRoutePage(st, AccountScreen(accountId: st.pathParameters['id']!, advanced: true))),
      GoRoute(path: '/settings/security', name: 'security-settings', pageBuilder: (_, st) => settingsRoutePage(st, const SecuritySettingsScreen())),
      GoRoute(
          path: '/settings/permissions',
          name: 'permissions-settings',
          // Первая настройка — без списка слева.
          pageBuilder: (_, s) => settingsRoutePage(s, PermissionsSettingsScreen(setup: s.uri.queryParameters['setup'] == '1'),
              split: s.uri.queryParameters['setup'] != '1')),
      // Первая настройка, шаг 2: календарь, контакты и папки ящика (1.6.12).
      GoRoute(path: '/setup/mailbox', name: 'setup-mailbox', builder: (_, __) => const WideFrame(child: SetupMailboxScreen())),
      GoRoute(path: '/settings/aliases', name: 'aliases-settings', pageBuilder: (_, st) => settingsRoutePage(st, const AliasesSettingsScreen())),
      GoRoute(path: '/settings/notifications', name: 'notifications-settings', pageBuilder: (_, st) => settingsRoutePage(st, const NotificationsSettingsScreen())),
      GoRoute(path: '/settings/automation', name: 'automation', pageBuilder: (_, st) => settingsRoutePage(st, const AutomationScreen())),
      GoRoute(path: '/settings/about', name: 'about', pageBuilder: (_, st) => settingsRoutePage(st, const AboutScreen())),
      // Вопросы и ответы (1.7.1); ?section=<id> — сразу нужный раздел.
      GoRoute(
          path: '/settings/faq',
          name: 'faq',
          pageBuilder: (_, state) => settingsRoutePage(state, FaqScreen(section: state.uri.queryParameters['section']))),
      GoRoute(path: '/settings/swipes', name: 'swipe-settings', pageBuilder: (_, st) => settingsRoutePage(st, const SwipeSettingsScreen())),
      GoRoute(path: '/settings/groups', name: 'account-groups', pageBuilder: (_, st) => settingsRoutePage(st, const AccountGroupsScreen())),
      GoRoute(path: '/settings/shared-mailbox', name: 'shared-mailbox', pageBuilder: (_, state) => settingsRoutePage(state, SharedMailboxScreen(parentId: state.uri.queryParameters['parent']))),
    ],

    errorBuilder: (context, state) {
      final l10n = AppLocalizations.of(context);
      return Scaffold(
        appBar: TextScaleCapBar(child: AppBar(title: Text(l10n.tr('errorLbl')))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(AppIcons.error, size: 48, color: AppColors.errorRed),
              const SizedBox(height: Space.l),
              Text('${state.uri}'),
              const SizedBox(height: Space.xl),
              ElevatedButton(onPressed: () => context.go('/mail'), child: Text(l10n.tr('routerGoHome'))),
            ],
          ),
        ),
      );
    },
  );
});


/// Страница письма из ленты или беседы — те же ключ, имя и аргументы, что
/// у MaterialPage, которую go_router строит для builder.
Page<void> _mailPage(GoRouterState state, Widget child) => MailOpenPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{...state.pathParameters, ...state.uri.queryParameters},
      restorationId: state.pageKey.value,
      child: child,
    );

/// Адрес экрана письма. id кодируется: у IMAP он содержит путь папки
/// («[Gmail]/Вся почта:2038»), и «/» без кодирования ломал маршрут —
/// открывался экран «Ошибка».
String mailDetailPath(String emailId, {String? accountId}) =>
    '/mail/detail/${Uri.encodeComponent(emailId)}'
    '${accountId != null ? '?accountId=${Uri.encodeQueryComponent(accountId)}' : ''}';

/// Письмо отдельной страницей поверх любого экрана (1.8.13). Страница
/// ленты ([mailDetailPath]) живёт внутри главного экрана, и открытая поверх
/// страницы вне его (настройки, «Написать», «Разобрать», «Файлы», встреча)
/// создавала второй главный экран с теми же ключами страниц: после «Назад»
/// пропадали верхняя и нижняя панели (замечание 29.10.2026).
String messagePath(String emailId, {String? accountId}) =>
    '/message/${Uri.encodeComponent(emailId)}'
    '${accountId != null && accountId.isNotEmpty ? '?accountId=${Uri.encodeQueryComponent(accountId)}' : ''}';

/// Адрес письма для перехода из [context]: со страницы главного экрана
/// (лента, календарь, «Мой день», задачи) — страница в нём, панель
/// навигации остаётся; со страницы поверх главного экрана — [messagePath].
String mailOpenPath(BuildContext context, String emailId, {String? accountId}) {
  final nav = Navigator.maybeOf(context);
  final root = Navigator.maybeOf(context, rootNavigator: true);
  final inShell = nav != null && root != null && !identical(nav, root);
  return inShell ? mailDetailPath(emailId, accountId: accountId) : messagePath(emailId, accountId: accountId);
}

/// Письмо ленты с листанием соседних писем (1.6.49+95).
String mailPagerPath(String emailId, {required String accountId}) =>
    Uri(path: '/mail/pager', queryParameters: {'emailId': emailId, 'accountId': accountId}).toString();

/// Встреча целиком. id кодируется (у EAS он вида «eas_2:15#20261007»).
String eventDetailsPath(String eventId, {required String accountId}) =>
    '/event/${Uri.encodeComponent(eventId)}'
    '${accountId.isNotEmpty ? '?accountId=${Uri.encodeQueryComponent(accountId)}' : ''}';

/// «Напоминания» (задачи) с открытой задачей.
String tasksPath({String? openTaskId, String? accountId}) {
  if (openTaskId == null) return '/tasks';
  final q = <String, String>{'task': openTaskId, if (accountId != null && accountId.isNotEmpty) 'accountId': accountId};
  return Uri(path: '/tasks', queryParameters: q).toString();
}

/// Экран беседы: письма беседы карточками.
String conversationPath(String conversationId, {required String accountId}) =>
    '/mail/conversation/${Uri.encodeComponent(conversationId)}'
    '?accountId=${Uri.encodeQueryComponent(accountId)}';

/// Письмо беседы с листанием «i / N».
String conversationMessagePath(String conversationId, String emailId,
        {required String accountId, String? find}) =>
    '/mail/conversation/${Uri.encodeComponent(conversationId)}/${Uri.encodeComponent(emailId)}'
    '?accountId=${Uri.encodeQueryComponent(accountId)}'
    // Поиск по беседе (2.2.0): письмо открывается с тем же поиском.
    '${find == null || find.trim().isEmpty ? '' : '&find=${Uri.encodeQueryComponent(find.trim())}'}';

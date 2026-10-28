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
import '../../features/my_day/my_day_screen.dart';
import '../../features/mail/screens/subscriptions_screen.dart';
import '../../features/notes/screens/note_edit_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
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
              GoRoute(
                path: 'detail/:emailId',
                name: 'mail-detail',
                builder: (_, state) => MailDetailScreen(
                  emailId: state.pathParameters['emailId']!,
                  accountId: state.uri.queryParameters['accountId'] ?? '',
                ),
              ),
              // Листание писем ленты свайпом (1.6.49+95). Без списка (адрес
              // открыт заново) — одно письмо.
              GoRoute(
                path: 'pager',
                name: 'mail-pager',
                builder: (_, state) {
                  final a = state.extra;
                  if (a is MailPagerArgs && a.items.isNotEmpty) return MailListPagerScreen(args: a);
                  return MailDetailScreen(
                    emailId: state.uri.queryParameters['emailId'] ?? '',
                    accountId: state.uri.queryParameters['accountId'] ?? '',
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
                    builder: (_, state) => ConversationPagerScreen(
                      conversationId: state.pathParameters['convId']!,
                      emailId: state.pathParameters['emailId']!,
                      accountId: state.uri.queryParameters['accountId'] ?? '',
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
              )),
          GoRoute(path: '/notes', name: 'notes', builder: (_, __) => const NotesScreen()),
          GoRoute(path: '/my-day', name: 'my-day', builder: (_, __) => const MyDayScreen()),
        ],
      ),

      // «Разобрать входящие» — непрочитанные по одному (поверх ленты).
      GoRoute(path: '/triage', name: 'triage', builder: (_, __) => const TriageScreen()),

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
            quickText: state.uri.queryParameters['quick'],
          )),
        ),
      ),
      GoRoute(
        path: '/vip-settings', name: 'vip-settings',
        pageBuilder: (_, __) => const MaterialPage(child: WideFrame(child: VipSettingsScreen())),
      ),
      GoRoute(
        path: '/create-event', name: 'create-event',
        pageBuilder: (_, state) {
          final extra = state.extra;
          EmailModel? email;
          DateTime? start, end;
          String? location, title, description;
          CalendarEvent? edit, duplicate;
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
        // ?from=адрес — только файлы этого отправителя.
        builder: (_, st) => AttachmentHubScreen(sender: st.uri.queryParameters['from']),
      ),
      // «Рассылки»: отправители с отпиской (боковое меню, у папок ящика;
      // ?accountId= — только этот ящик).
      GoRoute(
        path: '/subscriptions', name: 'subscriptions',
        builder: (_, st) => WideFrame(child: SubscriptionsScreen(accountId: st.uri.queryParameters['accountId'])),
      ),

      // Settings
      GoRoute(path: '/settings', name: 'settings', builder: (_, __) => const WideFrame(child: SettingsScreen())),
      // «Расширенные настройки» приложения (1.8.0).
      GoRoute(path: '/settings/advanced', name: 'advanced-settings', builder: (_, __) => const WideFrame(child: AdvancedSettingsScreen())),
      GoRoute(path: '/settings/rules', name: 'rules', builder: (_, st) => WideFrame(child: RulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/accessibility', name: 'accessibility', builder: (_, __) => const WideFrame(child: AccessibilityScreen())),
      GoRoute(path: '/settings/dlp', name: 'dlp', builder: (_, __) => const WideFrame(child: DlpSettingsScreen())),
      // «Возможности» (до 1.6.1) — их настройки теперь в «Почте» и
      // «Календаре»; старые ссылки ведут в «Почту».
      GoRoute(path: '/settings/experimental', name: 'experimental', redirect: (_, __) => '/settings/mail'),
      // Exchange на сервере: правила и «Восстановить удалённые» (EWS).
      GoRoute(path: '/settings/server-rules', name: 'server-rules', builder: (_, st) =>
          WideFrame(child: ServerRulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/recover-deleted', name: 'recover-deleted', builder: (_, st) =>
          WideFrame(child: RecoverDeletedScreen(accountId: st.uri.queryParameters['accountId']))),
      // Фильтры на сервере IMAP (Sieve).
      GoRoute(path: '/settings/sieve', name: 'sieve', builder: (_, st) =>
          WideFrame(child: SieveRulesScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/delivery-schedule', name: 'delivery-schedule', builder: (_, __) => const WideFrame(child: DeliveryScheduleScreen())),
      GoRoute(path: '/settings/profile', name: 'profile-settings', builder: (_, __) => const WideFrame(child: ProfileSettingsScreen())),
      GoRoute(path: '/settings/general', name: 'general-settings', builder: (_, __) => const WideFrame(child: GeneralSettingsScreen())),
      GoRoute(path: '/settings/mail', name: 'mail-settings', builder: (_, __) => const WideFrame(child: MailSettingsScreen())),
      GoRoute(path: '/settings/calendar', name: 'calendar-settings', builder: (_, __) => const WideFrame(child: CalendarSettingsScreen())),
      GoRoute(path: '/settings/contacts', name: 'contacts-settings', builder: (_, __) => const WideFrame(child: ContactsSettingsScreen())),
      GoRoute(path: '/settings/tasks', name: 'tasks-settings', builder: (_, __) => const WideFrame(child: TasksSettingsScreen())),
      GoRoute(path: '/settings/notes', name: 'notes-settings', builder: (_, __) => const WideFrame(child: NotesSettingsScreen())),
      GoRoute(path: '/settings/categories', name: 'category-settings', builder: (_, __) => const WideFrame(child: CategorySettingsScreen())),
      GoRoute(path: '/settings/templates', name: 'templates-settings', builder: (_, __) => const WideFrame(child: TemplatesSettingsScreen())),
      GoRoute(path: '/settings/storage', name: 'storage', builder: (_, __) => const WideFrame(child: StorageScreen())),
      GoRoute(path: '/settings/backup', name: 'backup', builder: (_, __) => const WideFrame(child: BackupScreen())),
      // Архив Ogneliss (1.7.3): настройки, папки и письма архива, поиск.
      GoRoute(path: '/settings/archive', name: 'ogna-archive', builder: (_, __) => const WideFrame(child: ArchiveScreen())),
      GoRoute(
          path: '/archive/folder/:id',
          name: 'ogna-folder',
          builder: (_, st) => WideFrame(child: ArchiveListScreen(folderId: int.tryParse(st.pathParameters['id'] ?? '')))),
      GoRoute(
          path: '/archive/search',
          name: 'ogna-search',
          builder: (_, st) => WideFrame(child: ArchiveListScreen(query: st.uri.queryParameters['q']))),
      GoRoute(
          path: '/archive/message/:id',
          name: 'ogna-message',
          builder: (_, st) => WideFrame(child: ArchiveMessageScreen(id: int.tryParse(st.pathParameters['id'] ?? '') ?? 0))),
      GoRoute(
          path: '/archive/items/:kind',
          name: 'ogna-items',
          builder: (_, st) => WideFrame(child: ArchiveItemsScreen(kind: st.pathParameters['kind'] ?? 'events'))),
      GoRoute(path: '/settings/folder-sync', name: 'folderSync', builder: (_, st) => WideFrame(child: FolderSyncSettingsScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/conflicts', name: 'conflicts', builder: (_, __) => const WideFrame(child: ConflictSettingsScreen())),
      GoRoute(path: '/contacts/duplicates', name: 'contacts-duplicates', builder: (_, __) => const WideFrame(child: DuplicateContactsScreen())),
      GoRoute(path: '/contacts/me', name: 'my-contact', builder: (_, __) => const WideFrame(child: MyContactScreen())),
      GoRoute(path: '/settings/logs', name: 'log-viewer', builder: (_, __) => const LogViewerScreen()),
      GoRoute(path: '/settings/auto-reply', name: 'auto-reply', builder: (_, st) => WideFrame(child: AutoReplyScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/signatures', name: 'signatures-settings', builder: (_, st) => WideFrame(child: SignaturesSettingsScreen(accountId: st.uri.queryParameters['accountId']))),
      GoRoute(path: '/settings/accounts', name: 'accounts-settings', builder: (_, __) => const WideFrame(child: AccountsSettingsScreen())),
      GoRoute(path: '/settings/account/:id', name: 'account-settings', builder: (_, st) => WideFrame(child: AccountScreen(accountId: st.pathParameters['id']!))),
      // «Расширенные настройки» ящика (1.8.0).
      GoRoute(path: '/settings/account/:id/advanced', name: 'account-advanced', builder: (_, st) => WideFrame(child: AccountScreen(accountId: st.pathParameters['id']!, advanced: true))),
      GoRoute(path: '/settings/security', name: 'security-settings', builder: (_, __) => const WideFrame(child: SecuritySettingsScreen())),
      GoRoute(
          path: '/settings/permissions',
          name: 'permissions-settings',
          builder: (_, s) => WideFrame(child: PermissionsSettingsScreen(setup: s.uri.queryParameters['setup'] == '1'))),
      // Первая настройка, шаг 2: календарь, контакты и папки ящика (1.6.12).
      GoRoute(path: '/setup/mailbox', name: 'setup-mailbox', builder: (_, __) => const WideFrame(child: SetupMailboxScreen())),
      GoRoute(path: '/settings/aliases', name: 'aliases-settings', builder: (_, __) => const WideFrame(child: AliasesSettingsScreen())),
      GoRoute(path: '/settings/notifications', name: 'notifications-settings', builder: (_, __) => const WideFrame(child: NotificationsSettingsScreen())),
      GoRoute(path: '/settings/automation', name: 'automation', builder: (_, __) => const WideFrame(child: AutomationScreen())),
      GoRoute(path: '/settings/about', name: 'about', builder: (_, __) => const WideFrame(child: AboutScreen())),
      // Вопросы и ответы (1.7.1); ?section=<id> — сразу нужный раздел.
      GoRoute(
          path: '/settings/faq',
          name: 'faq',
          builder: (_, state) => WideFrame(child: FaqScreen(section: state.uri.queryParameters['section']))),
      GoRoute(path: '/settings/swipes', name: 'swipe-settings', builder: (_, __) => const WideFrame(child: SwipeSettingsScreen())),
      GoRoute(path: '/settings/groups', name: 'account-groups', builder: (_, __) => const WideFrame(child: AccountGroupsScreen())),
      GoRoute(path: '/settings/shared-mailbox', name: 'shared-mailbox', builder: (_, state) => WideFrame(child: SharedMailboxScreen(parentId: state.uri.queryParameters['parent']))),
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


/// Адрес экрана письма. id кодируется: у IMAP он содержит путь папки
/// («[Gmail]/Вся почта:2038»), и «/» без кодирования ломал маршрут —
/// открывался экран «Ошибка».
String mailDetailPath(String emailId, {String? accountId}) =>
    '/mail/detail/${Uri.encodeComponent(emailId)}'
    '${accountId != null ? '?accountId=${Uri.encodeQueryComponent(accountId)}' : ''}';

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
        {required String accountId}) =>
    '/mail/conversation/${Uri.encodeComponent(conversationId)}/${Uri.encodeComponent(emailId)}'
    '?accountId=${Uri.encodeQueryComponent(accountId)}';

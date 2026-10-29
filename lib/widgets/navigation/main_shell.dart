// lib/widgets/navigation/main_shell.dart
// Финальный shell:
// - PIN-блокировка (overlay)
// - Keyboard shortcuts (desktop)
// - Focus mode indicator
// - Adaptive: phone=BottomNav, tablet=Rail, desktop=Rail+extended
// - Attachment hub в FAB
// - Sync progress

import '../../features/mail/providers/mail_open_cache.dart';
import '../../features/mail/widgets/mail_html_view.dart' show MailWebViewPool;
import '../../services/sync/offline_store_service.dart';
import '../../services/notifications/email_reminder_service.dart';
import '../../services/mail/auto_reply_status.dart';
import '../../features/mail/widgets/auto_reply_strip.dart' show AutoReplyBadge;
import '../../core/platform/orientation_policy.dart';
import '../../core/utils/text_safe.dart';
import '../../services/notifications/notification_service.dart' show notificationServiceProvider;
import '../../services/notifications/notification_router.dart';
import '../../services/calendar/quick_create_service.dart' show quickCreateProvider;
import '../../core/theme/app_icons.dart';
import 'app_bottom_bar.dart';
import 'panel_requests.dart';
import '../ui/action_sheet.dart';
import '../common/peek_card.dart';
import '../common/hero_email_transition.dart' show HeroEmailAvatar;
import '../../features/settings/providers/account_groups_provider.dart' show activeGroupIdProvider, accountGroupsProvider;
import '../../features/tasks/widgets/task_editor_sheet.dart' show showTaskEditor;
import '../../features/tasks/task_quick_parser.dart' show ParsedTask;
import 'dart:io';
import '../../features/settings/providers/feature_flags_provider.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:badges/badges.dart' as badges;

import '../../l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../features/mail/providers/mail_providers.dart';
import '../../features/mail/providers/drawer_prefs.dart' show menuOnRightProvider;
import '../../features/settings/providers/settings_provider.dart';
import '../../services/security/pin_lock_service.dart';
import '../../services/maintenance/maintenance_service.dart';
import '../../services/mail/focus_mode_service.dart';
import '../../services/background/background_service.dart';
import '../../services/background/foreground_sync_controller.dart';
import '../../services/notifications/notification_action_handler.dart';
import '../common/calendar_day_icon.dart';
import '../common/error_banner.dart';
import '../common/keyboard_shortcuts.dart';
import '../common/animated_appearance.dart';
import '../../services/background/background_journal.dart';
import '../../core/logging/app_logger.dart';
import '../../core/permissions/app_permissions.dart';
import '../../services/notifications/reminder_scheduler_service.dart';
import '../../services/archive/archive_runner.dart' show archiveRunnerProvider;

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  /// Активные маршруты с учётом флага видимости «Задач» (хвост, поэтому его
  /// скрытие не сдвигает индексы Mail/Calendar/Contacts).
  List<String> _activeRoutes() {
    final f = ref.read(featureFlagsProvider);
    return [
      '/mail', '/calendar', '/contacts',
      if (f.showTasksTab) '/tasks',
    ];
  }

  @override
  void initState() {
    super.initState();
    NotificationRouter.shellMounted();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recheckExactAlarms()); // исходное состояние для сравнения при возврате
    // Приложение открыли нажатием на уведомление — переход к письму, встрече
    // или задаче, когда главный экран уже на месте.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationRouterProvider).consumePending();
    });
    // Значок на рабочем столе («пришли письма») — сброшен при открытии.
    // Чуть позже: сначала приложение разберёт нажатое уведомление.
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) unawaited(ref.read(notificationServiceProvider).clearMailBadge());
    });
    // Разово после обновления: превью писем IMAP из сохранённых текстов и
    // разметка текстов в поиске — когда лента и первая синхронизация уже
    // на месте.
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (mounted) unawaited(ref.read(maintenanceServiceProvider).afterUpdateOnce());
    });
    // Архив Ogneliss по расписанию (1.7.3) — когда первая синхронизация
    // уже прошла.
    Future<void>.delayed(const Duration(minutes: 1), () {
      if (mounted) unawaited(ref.read(archiveRunnerProvider.notifier).maybeAutoRun());
    });
  }

  @override
  void dispose() {
    NotificationRouter.shellUnmounted();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Когда приложение ушло в фон — для журнала фоновой работы.
  DateTime? _pausedAt;

  /// Последнее известное состояние разрешения на точные будильники.
  AppPermissionState? _exactAlarms;

  Future<void> _recheckExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final now = await AppPermissions.state(AppPermission.exactAlarms);
    final before = _exactAlarms;
    _exactAlarms = now;
    if (before != null && before != now) {
      AppLogger.info('Точные будильники: ${now.name} — напоминания перевыставлены');
      await ref.read(reminderSchedulerProvider).rescheduleAll();
    }
  }

  /// Экран сменился (раскрыли или сложили складной телефон, другой дисплей):
  /// пересчитать, разрешён ли поворот.
  @override
  void didChangeMetrics() {
    unawaited(OrientationPolicy.apply());
  }

  /// Системе не хватает памяти: сбросить подготовленные письма и картинки
  /// (их соберёт заново открытие письма) и кэш декодированных картинок Flutter.
  @override
  void didHaveMemoryPressure() {
    ref.read(mailOpenCacheProvider).clear();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    // Android и iOS присылают этот сигнал и при каждом сворачивании — это не
    // нехватка памяти, а «приберитесь в фоне». В журнале — по-разному, чтобы
    // тестировщики не пугались «Мало памяти» после каждого выхода (1.6.32).
    final away = WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    AppLogger.info(away
        ? 'Свёрнуто: временные данные очищены (подготовленные письма и картинки)'
        : 'Системе не хватает памяти: временные данные очищены (подготовленные письма и картинки)');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pausedAt != null) {
      final away = DateTime.now().difference(_pausedAt!);
      _pausedAt = null;
      unawaited(BackgroundJournal.note('открыто',
          'в фоне ${away.inMinutes >= 1 ? '${away.inMinutes} мин' : '${away.inSeconds} с'}'));
    }
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      unawaited(BackgroundJournal.note('свёрнуто', 'приложение ушло в фон'));
      // iPhone: заявки на фоновые пробуждения — заново от сворачивания.
      ref.read(backgroundServiceProvider).onPaused();
      // Память в фоне — поменьше: подготовленные письма и картинки.
      ref.read(mailOpenCacheProvider).trim();
      // Запасное окно браузера (1.5.9) — тоже: вернувшись, лента создаст его
      // заново в простое.
      unawaited(MailWebViewPool.release());
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Строки журнала — на диск, пока процесс не заморожен.
      AppLogger.flushNow();
    }
    if (state == AppLifecycleState.resumed) {
      // Блокировка, если приложение было свёрнуто дольше короткой паузы.
      ref.read(pinLockProvider.notifier).onForeground();
      // Записать активность
      ref.read(backgroundServiceProvider).recordActivity();
      // «Посмотреть позже» с наступившим сроком — в ленту сразу.
      ref.read(emailReminderProvider).checkNow();
      // Докачка текстов, отложенная в фоне (экономия заряда), — сразу.
      ref.read(offlineStoreProvider).wake();
      // Свежая почта сразу при возврате (троттлинг внутри — не чаще раза в 2 мин).
      unawaited(ref.read(backgroundServiceProvider).syncOnResume());
      // Кнопки уведомлений, не выполненные в фоне (не было сети).
      unawaited(ref.read(notificationActionHandlerProvider).runPending());
      // Окно открыли нажатием на уведомление, пока движок жил без окна:
      // новая активность приходит без колбэка нажатия — спрашиваем сами.
      unawaited(ref.read(notificationRouterProvider).checkLaunch(ref.read(notificationServiceProvider)));
      // Встречи и задачи, созданные в виджете без входа в приложение.
      unawaited(ref.read(quickCreateProvider).drain());
      // Открыли — значок с числом новых писем сброшен (непрочитанные остаются).
      unawaited(ref.read(notificationServiceProvider).clearMailBadge());
      // Архив Ogneliss: пора ли архивировать (не чаще проверки в 15 мин).
      unawaited(ref.read(archiveRunnerProvider.notifier).maybeAutoRun());
      // Автоответ на сервере: если при запуске сервер не ответил — ещё раз.
      unawaited(ref.read(autoReplyStatusProvider.notifier).refreshOnce(ref.read(accountsProvider)));
      // Push мог умереть, пока приложение было в фоне, — проверить сразу.
      unawaited(ref.read(backgroundServiceProvider).onResume());
      // Точные будильники дали (или отозвали) в настройках, пока приложение
      // было свёрнуто, — перевыставить напоминания нужным способом.
      unawaited(_recheckExactAlarms());
      // Фоновый сервис больше НЕ останавливается при возврате (раньше —
      // стоп/старт на каждое переключение, см. журнал 06.10): каждый запуск
      // из фона Android 12+ может запретить, и тогда процесс оставался без
      // защиты — его замораживали, push умирал. Сервис живёт, пока живо
      // приложение; на переднем плане его уведомление скрыто (IMPORTANCE_MIN).
      // Повторный start() здесь поднимает сервис, если система остановила
      // его по лимиту Android 15 (лимит сбрасывается выходом на передний план).
      final st = ref.read(settingsProvider);
      if (keepAliveNeeded(
          keepAliveSetting: st.backgroundKeepAlive,
          globalInterval: st.syncIntervalMinutes,
          accounts: ref.read(accountsProvider))) {
        unawaited(ref.read(foregroundSyncControllerProvider).start());
      } else {
        // Ящиков с мгновенной доставкой нет — сервис и уведомление не нужны.
        unawaited(ref.read(foregroundSyncControllerProvider).stop());
      }
    }
    if (state == AppLifecycleState.hidden) {
      // Windows/macOS: окно свёрнуто (paused там может не прийти).
      ref.read(pinLockProvider.notifier).onBackground();
    }
    if (state == AppLifecycleState.paused) {
      // Автоблокировка PIN: засекаем уход в фон, блокируем при возврате.
      ref.read(pinLockProvider.notifier).onBackground();
      // Обслуживание БД раз в сутки (чистка индекса + VACUUM) — в фоне, когда нет
      // активного UI. Guard по времени внутри; unawaited, чтобы не задерживать
      // сворачивание.
      unawaited(ref.read(maintenanceServiceProvider).maybeRunDaily());
      // Держать процесс живым в фоне (Android), если включено и есть аккаунты —
      // тогда таймеры синка и IMAP IDLE продолжают работать свёрнутыми.
      final st = ref.read(settingsProvider);
      if (keepAliveNeeded(
          keepAliveSetting: st.backgroundKeepAlive,
          globalInterval: st.syncIntervalMinutes,
          accounts: ref.read(accountsProvider))) {
        unawaited(ref.read(foregroundSyncControllerProvider).start());
      } else {
        // Ящиков с мгновенной доставкой нет — сервис и уведомление не нужны.
        unawaited(ref.read(foregroundSyncControllerProvider).stop());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unreadCount = ref.watch(totalUnreadCountProvider);
    ref.watch(settingsProvider); // перестроение при смене настроек
    final focusState = ref.watch(focusModeProvider);
    final screenWidth = MediaQuery.of(context).size.width;

    final isTablet = screenWidth >= 600;
    final isDesktop = screenWidth >= 1200 ||
        (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux));

    // Экран PIN показывается поверх всего приложения (AppLockGate в
    // MaterialApp.builder) — включая окна, открытые поверх оболочки.

    // Записать активность при взаимодействии
    ref.read(backgroundServiceProvider).recordActivity();

    final destinations = _buildDestinations(l10n, unreadCount);
    // Если выбранная вкладка скрыта флагом — не выходим за границы.
    if (_currentIndex >= destinations.length) _currentIndex = 0;

    Widget body;

    if (isTablet || isDesktop) {
      // NavigationRail
      body = Scaffold(
        body: _withSyncOverlay(Column(
          children: [
            // Ошибки синхронизации (временные, с автоскрытием и кнопкой
            // повтора). Офлайн сюда НЕ попадает — для него компактная
            // пиктограмма в правом верхнем углу, см. OfflineIndicator.
            const ErrorBanner(),
            if (focusState.isEnabled && focusState.isCurrentlyActive)
              _buildFocusBanner(l10n, theme),
            Expanded(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: _onTabChanged,
                    // Развёрнутая панель — только когда места достаточно; на
                    // узком окне Windows она съедала треть ширины.
                    extended: screenWidth >= 1200,
                    minWidth: 56,
                    minExtendedWidth: 200,
                    // Низкое окно (телефон боком с «Поворотом экрана», узкое
                    // окно компьютера, 1.8.13): разделы прокручиваются, а
                    // «Написать» и нижние значки остаются на месте. Раньше
                    // колонка не помещалась по высоте и обрезалась.
                    scrollable: true,
                    leadingAtTop: true,
                    trailingAtBottom: true,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.s),
                      child: FloatingActionButton.small(
                        heroTag: 'fab_rail',
                        onPressed: () => context.push('/compose'),
                        child: const Icon(AppIcons.edit),
                      ),
                    ),
                    trailing: Padding(
                      padding: const EdgeInsets.only(top: Space.s),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (ref.watch(settingsProvider.select((s) => s.myDay)))
                            IconButton(
                              icon: const Icon(AppIcons.myDay),
                              tooltip: l10n.tr('myDay'),
                              onPressed: () => context.go('/my-day'),
                            ),
                          if (ref.watch(featureFlagsProvider.select((f) => f.showFileHub)))
                            IconButton(
                              icon: const Icon(AppIcons.folder_open),
                              tooltip: l10n.tr('attachmentHub'),
                              onPressed: () => context.push('/attachment-hub'),
                            ),
                          IconButton(
                            icon: const Icon(AppIcons.settings),
                            tooltip: l10n.tr('settings'),
                            onPressed: () => context.push('/settings'),
                          ),
                          const SizedBox(height: Space.l),
                        ],
                      ),
                    ),
                    destinations: destinations.map((d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    )).toList(),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: AnimatedContentSwitcher(child: KeyedSubtree(key: ValueKey(_currentIndex), child: widget.child))),
                ],
              ),
            ),
          ],
        )),
      );
    } else {
      // Phone: BottomNav
      body = Scaffold(
        body: _withSyncOverlay(Column(
          children: [
            // Ошибки синхронизации (временные, с автоскрытием и кнопкой
            // повтора). Офлайн сюда НЕ попадает — для него компактная
            // пиктограмма в правом верхнем углу, см. OfflineIndicator.
            const ErrorBanner(),
            if (focusState.isEnabled && focusState.isCurrentlyActive)
              _buildFocusBanner(l10n, theme),
            Expanded(child: AnimatedContentSwitcher(child: KeyedSubtree(key: ValueKey(_currentIndex), child: widget.child))),
          ],
        )),
        // Панель — только на корневых экранах разделов. Письмо и беседа
        // открываются внутри оболочки, и под их собственной панелью действий
        // вкладки стояли второй полосой (замечание 05.10.2026).
        // Плавающей кнопки на телефоне нет: «Создать» — в центре панели.
        bottomNavigationBar: _phoneRoots.contains(GoRouterState.of(context).uri.path)
            ? _phoneBar(context, l10n, theme, unreadCount)
            : null,
      );
    }

    // Горячие клавиши: компьютер и планшет (iPad и Android-планшет с
    // клавиатурой, 1.6.28) — на сенсорном экране без клавиатуры не мешают.
    if (isDesktop || isTablet) {
      return KeyboardShortcutsWrapper(
        onCompose: () => context.push('/compose'),
        // Раньше F5 и Ctrl+E ничего не делали (пустые обработчики).
        onRefresh: () => ref.read(emailsProvider.notifier).refresh(),
        onSearch: () {
          if (_currentIndex != 0 && _activeRoutes().isNotEmpty) {
            setState(() => _currentIndex = 0);
            context.go(_activeRoutes().first);
          }
          ref.read(mailSearchRequestProvider.notifier).state++;
        },
        onSwitchTab: (index) {
          if (index < _activeRoutes().length) {
            setState(() => _currentIndex = index);
            context.go(_activeRoutes()[index]);
          }
        },
        child: body,
      );
    }

    // «Назад» на вкладке календаря, контактов или задач возвращает в почту,
    // а не закрывает приложение. Экраны внутри почты (письмо, беседа)
    // закрываются вложенным навигатором раньше, чем срабатывает эта проверка.
    final path = GoRouterState.of(context).uri.path;
    final mailWantsBack = ref.watch(mailBackHandlerProvider);
    return PopScope(
      canPop: path == '/mail' && !mailWantsBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (path == '/mail') {
          // Лента: выход из выбора, поиска, папки или фильтра.
          ref.read(mailBackRequestProvider.notifier).state++;
          return;
        }
        if (_activeRoutes().contains(path)) {
          setState(() => _currentIndex = 0);
          context.go('/mail');
        } else if (GoRouter.of(context).canPop()) {
          GoRouter.of(context).pop();
        } else {
          context.go('/mail');
        }
      },
      child: body,
    );
  }

  Widget _buildFocusBanner(AppLocalizations l10n, ThemeData theme) {
    final fg = AppColors.accentOrangeText(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: Space.l, right: Space.xs),
      color: AppColors.accentOrange.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(AppIcons.do_not_disturb_on, size: Sizes.iconInline, color: fg),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(
              l10n.tr('focusActive'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: fg),
            ),
          ),
          // Кнопка, а не подчёркнутый текст: область нажатия была ~16 dp.
          TextButton(
            onPressed: () => ref.read(focusModeProvider.notifier).setEnabled(false),
            style: TextButton.styleFrom(foregroundColor: fg, visualDensity: VisualDensity.compact),
            child: Text(l10n.tr('turnOff')),
          ),
        ],
      ),
    );
  }

  List<NavigationDestination> _buildDestinations(AppLocalizations l10n, int unreadCount) {
    final flags = ref.read(featureFlagsProvider);
    return [
      NavigationDestination(
        icon: badges.Badge(
          showBadge: unreadCount > 0,
          badgeContent: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.errorRed, padding: EdgeInsets.all(Space.xs)),
          child: const Icon(AppIcons.mail),
        ),
        selectedIcon: badges.Badge(
          showBadge: unreadCount > 0,
          badgeContent: Text(unreadCount > 99 ? '99+' : '$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.errorRed, padding: EdgeInsets.all(Space.xs)),
          child: const Icon(AppIcons.mail, fill: 1),
        ),
        label: l10n.mail,
      ),
      // Число дня — по центру листа значка, цветом значка, само меняется в
      // полночь (1.7.2+108: раньше стояло на нижней рамке, см. CalendarDayIcon).
      NavigationDestination(
        icon: const CalendarDayIcon(),
        selectedIcon: const CalendarDayIcon(),
        label: l10n.calendarLabel,
      ),
      NavigationDestination(icon: const Icon(AppIcons.contacts), selectedIcon: const Icon(AppIcons.contacts, fill: 1), label: l10n.contactsLabel),
      // Задачи — хвост, скрываются флагом (порядок совпадает с _activeRoutes()).
      if (flags.showTasksTab)
        NavigationDestination(icon: const Icon(AppIcons.check_box), selectedIcon: const Icon(AppIcons.check_box, fill: 1), label: l10n.tasksLabel),
    ];
  }

  // ── Телефон: панель «Почта · Календарь · [Создать] · Контакты · Ещё» ──

  static const _phoneRoots = {'/mail', '/calendar', '/contacts', '/tasks', '/notes', '/my-day'};

  int _phoneIndex(String path) {
    if (path.startsWith('/calendar')) return 1;
    if (path.startsWith('/contacts')) return 2;
    if (path.startsWith('/tasks') || path.startsWith('/notes') || path.startsWith('/my-day')) return 3;
    return 0;
  }

  Widget _phoneBar(BuildContext context, AppLocalizations l10n, ThemeData theme, int unreadCount) {
    final path = GoRouterState.of(context).uri.path;
    final all = _buildDestinations(l10n, unreadCount);
    // «Почта» — с аватаром текущего ящика (или значком «Все аккаунты» /
    // группы) вместо конверта: одна кнопка и для раздела, и для ящиков. В
    // почте нажатие открывает меню ящиков и папок, из другого раздела —
    // переход в почту (09.10.2026: отдельный аватар отнимал место у вкладок).
    // 1.6.40 (решение владельца 18.10.2026): «Почта» — снова значком
    // конверта; портрет ящика — справа, на месте «Ещё»: открывает меню ящиков,
    // папок и избранного (там теперь и «Мой день», задачи, заметки,
    // настройки и тема). Меню и «Ещё» дублировали друг друга, а справа
    // внизу портрет под большим пальцем.
    final mailBadge = unreadCount;
    Widget mailIcon(bool selected) => badges.Badge(
          showBadge: mailBadge > 0,
          badgeContent: Text(mailBadge > 99 ? '99+' : '$mailBadge',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.errorRed, padding: EdgeInsets.all(Space.xs)),
          child: Icon(AppIcons.mail, fill: selected ? 1.0 : 0.0),
        );
    final logical = [
      NavigationDestination(icon: mailIcon(false), selectedIcon: mailIcon(true), label: l10n.mail),
      all[1],
      all[2],
      NavigationDestination(
        icon: _accountAvatar(theme, selected: false),
        selectedIcon: _accountAvatar(theme, selected: true),
        label: l10n.tr('barMenu'),
      ),
    ];
    // Портрет «Меню» — с той стороны, откуда выезжает меню (настройка
    // «Меню ящиков и папок»: слева по умолчанию или справа, 1.6.40).
    final order = ref.watch(menuOnRightProvider) ? const [0, 1, 2, 3] : const [3, 0, 1, 2];
    final destinations = [for (final i in order) logical[i]];
    // Нижняя панель — всегда по теме (решение владельца 13.10.2026): цвет
    // ящика окрашивает только верхнюю панель ленты. В 1.6.2 окрашивались обе.
    return AppBottomBar(
      selectedIndex: order.indexOf(_phoneIndex(path)),
      destinations: destinations,
      // В режиме выбора писем внизу — панель действий списка; центральная
      // кнопка там не нужна.
      center: path == '/mail' && ref.watch(mailSelectionActiveProvider) ? null : _centerAction(context, l10n, path),
      onSelected: (i) {
        switch (order[i]) {
          case 0:
            // Уже в ленте — к её началу (1.6.49, как повторное нажатие на
            // «Чаты» в Telegram).
            if (path == '/mail') {
              ref.read(mailScrollTopRequestProvider.notifier).state++;
              return;
            }
            _goPhone(0, '/mail');
          case 1:
            _goPhone(1, '/calendar');
          case 2:
            _goPhone(2, '/contacts');
          default:
            _openMenu();
        }
      },
      // Долгое нажатие на «Почту» или портрет — смена ящика прямо под
      // пальцем, без меню папок.
      onLongPressed: (i) {
        if (order[i] == 0 || order[i] == 3) unawaited(_pickAccount(context, l10n));
      },
    );
  }

  /// Портрет внизу: меню ящиков, папок и избранного. В почте — открыть или
  /// закрыть; из другого раздела — переход в почту и сразу меню.
  void _openMenu() {
    final path = GoRouterState.of(context).uri.path;
    if (path == '/mail') {
      ref.read(mailDrawerRequestProvider.notifier).state++;
      return;
    }
    ref.read(mailDrawerPendingProvider.notifier).state = true;
    _goPhone(0, '/mail');
    // Лента уже была построена — её initState не повторится: просим меню
    // после перехода. Новая лента заберёт запрос сама (mailDrawerPending).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(mailDrawerPendingProvider)) return;
      ref.read(mailDrawerPendingProvider.notifier).state = false;
      ref.read(mailDrawerRequestProvider.notifier).state++;
    });
  }

  /// Аватар текущего ящика для вкладки «Почта»; «Все аккаунты» и группа —
  /// значком. Размер — по высоте значка вкладки.
  Widget _accountAvatar(ThemeData theme, {required bool selected}) {
    final scheme = theme.colorScheme;
    final account = ref.watch(activeAccountProvider);
    final all = ref.watch(allAccountsModeProvider);
    final groupId = ref.watch(activeGroupIdProvider);
    final hasGroup = groupId != null && ref.watch(accountGroupsProvider).any((g) => g.id == groupId);
    // Значок со стрелками — автоответ включён (1.7.2): строку в ленте можно
    // скрыть, портрет напоминает.
    if (all || hasGroup || account == null) {
      return AutoReplyBadge(
          child: Icon(hasGroup ? AppIcons.folder_shared : AppIcons.all_inbox, fill: selected ? 1.0 : 0.0));
    }
    final name = account.displayName.trim();
    return AutoReplyBadge(accountId: account.id, child: Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? scheme.onSecondaryContainer : Colors.transparent, width: 1.5),
      ),
      child: HeroEmailAvatar(
        emailId: 'bar/${account.id}',
        radius: 12,
        color: Color(account.colorValue),
        initial: name.isNotEmpty ? initialOf(name) : '?',
        hero: false,
        email: account.email,
        photo: account.avatarUrl,
      ),
    ));
  }

  Future<void> _pickAccount(BuildContext context, AppLocalizations l10n) async {
    final accounts = ref.read(accountsProvider);
    if (accounts.length < 2) return;
    final active = ref.read(activeAccountProvider)?.id;
    final all = ref.read(allAccountsModeProvider);
    final picked = await showActionSheet<String>(context, title: l10n.tr('accounts'), items: [
      ActionSheetItem(
        icon: AppIcons.all_inbox,
        label: l10n.tr('allAccounts'),
        value: '*',
        enabled: !all,
      ),
      for (final a in accounts)
        ActionSheetItem(
          icon: a.id == active && !all ? AppIcons.check_circle : AppIcons.forAccountType(a.type.name),
          label: a.displayName.isEmpty ? a.email : a.displayName,
          subtitle: a.email,
          value: a.id,
        ),
    ]);
    if (picked == null || !mounted) return;
    ref.read(activeGroupIdProvider.notifier).state = null;
    ref.read(unifiedModeProvider.notifier).state = true;
    ref.read(selectedFolderIdProvider.notifier).state = null;
    if (picked == '*') {
      ref.read(allAccountsModeProvider.notifier).state = true;
    } else {
      ref.read(allAccountsModeProvider.notifier).state = false;
      await ref.read(settingsProvider.notifier).setActiveAccountId(picked);
    }
    if (mounted && context.mounted) _goPhone(0, '/mail');
  }

  void _goPhone(int railIndex, String route) {
    setState(() => _currentIndex = railIndex);
    context.go(route);
  }

  /// Главное действие раздела — в центре панели.
  PanelAction _centerAction(BuildContext context, AppLocalizations l10n, String path) {
    // Календарь и «Мой день» — общий план: встреча или задача (напоминание
    // себе). В «Моём дне» раньше была только задача (замечание 13.10.2026).
    if (path.startsWith('/calendar') || path.startsWith('/my-day')) {
      return PanelAction(
          icon: AppIcons.add,
          label: l10n.tr('calendarCreate'),
          onLongPress: (button) => _createMenu(context, l10n, button),
          onPressed: () async {
            final kind = await showActionSheet<String>(context, items: [
              ActionSheetItem(icon: AppIcons.event, label: l10n.tr('createMeeting'), value: 'event'),
              ActionSheetItem(
                  icon: AppIcons.add_task,
                  label: l10n.tr('newTask'),
                  subtitle: l10n.tr('newTaskHint'),
                  value: 'task'),
            ]);
            if (!mounted || !context.mounted) return;
            if (kind == 'event') unawaited(context.push('/create-event'));
            // Срок по умолчанию — сегодня: задача сразу видна в календаре.
            if (kind == 'task') {
              final now = DateTime.now();
              unawaited(showTaskEditor(context,
                  draft: ParsedTask(title: '', due: DateTime(now.year, now.month, now.day))));
            }
          });
    }
    if (path.startsWith('/contacts')) {
      return PanelAction(
          icon: AppIcons.add,
          label: l10n.tr('create'),
          onPressed: () => ref.read(contactsAddRequestProvider.notifier).state++);
    }
    if (path.startsWith('/tasks')) {
      return PanelAction(
          icon: AppIcons.add_task,
          label: l10n.tr('newTask'),
          onPressed: () => ref.read(tasksAddRequestProvider.notifier).state++);
    }
    if (path.startsWith('/notes')) {
      return PanelAction(
          icon: AppIcons.note_add,
          label: l10n.tr('newNote'),
          onPressed: () => context.push('/notes/edit'));
    }
    return PanelAction(
      icon: AppIcons.edit,
      label: l10n.compose,
      onPressed: () => context.push('/compose'),
      onLongPress: (button) => _createMenu(context, l10n, button),
    );
  }

  /// Удержание кнопки «Написать» или «+» календаря (1.6.47): письмо, встреча
  /// или задача — меню над кнопкой; палец можно довести до пункта и
  /// отпустить.
  void _createMenu(BuildContext context, AppLocalizations l10n, BuildContext button) {
    final anchor = peekAnchorOf(button);
    if (anchor == null) return;
    unawaited(showHoldMenu(context, anchor: anchor, items: [
      PeekAction(icon: AppIcons.edit, label: l10n.tr('newMessage'), onTap: () => context.push('/compose')),
      PeekAction(icon: AppIcons.event, label: l10n.tr('createMeeting'), onTap: () => context.push('/create-event')),
      PeekAction(
        icon: AppIcons.add_task,
        label: l10n.tr('newTask'),
        onTap: () {
          // Срок по умолчанию — сегодня, как у «+» в календаре.
          final now = DateTime.now();
          unawaited(showTaskEditor(context, draft: ParsedTask(title: '', due: DateTime(now.year, now.month, now.day))));
        },
      ),
    ]));
  }

  /// Полоска синхронизации — поверх содержимого, сразу под строкой
  /// состояния. Раньше она стояла в колонке над экраном и рисовалась под
  /// часами и значками (приложение занимает весь экран, edge-to-edge).
  // Полоса синхронизации сверху убрана (05.10.2026): состояние показывает
  // SyncStatusDot рядом с названием папки.
  Widget _withSyncOverlay(Widget child) => child;

  void _onTabChanged(int index) {
    if (index != _currentIndex) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
      context.go(_activeRoutes()[index]);
    }
  }
}

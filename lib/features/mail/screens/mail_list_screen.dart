// lib/features/mail/screens/mail_list_screen.dart
import '../../../widgets/ui/action_sheet.dart';
import '../../../widgets/common/gap_below.dart';
import '../widgets/mail_check_sheet.dart' show showMailCheckSheet;
import '../widgets/background_hint_strip.dart';
import '../widgets/first_load_strip.dart';
import '../../../core/utils/text_safe.dart';
import '../providers/drawer_prefs.dart' show drawerPinnedProvider, menuOnRightProvider, quickFiltersProvider, mailSwipePagerProvider;
import '../../../widgets/navigation/app_bottom_bar.dart' show AppBottomBar;
import '../providers/startup_folder.dart';
import '../../../core/theme/app_icons.dart';
import '../../../widgets/common/sync_progress_indicator.dart' show SyncStatusDot, SyncStatus, syncStatusProvider;
import '../../../core/navigation/app_router.dart' show mailDetailPath, conversationPath, mailPagerPath;
import '../../../core/logging/open_trace.dart';
import '../../../core/theme/mail_page_color.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../settings/widgets/feature_settings_sections.dart' show ExperimentalKeys;
import '../../../core/utils/work_isolate.dart';
import '../../../services/background/work_scheduler.dart';
import '../providers/mail_open_cache.dart';
import '../../archive/archive_sheets.dart' show ensureArchiveReady;
import '../../archive/widgets/archive_search_strip.dart';
import '../../../services/archive/archive_runner.dart' show archiveRunnerProvider;
import '../../../services/archive/archive_settings.dart' show archiveSettingsProvider;
import '../widgets/mail_html_view.dart' show MailHtmlView, MailWebViewPool;
import '../../../widgets/common/swipe_action_indicator.dart';
import '../../compose/widgets/mail_editor.dart' show warmUpMailEditor;
import '../../../services/mail/conversation_counter.dart';
import 'dart:async';
import '../../../services/mail/offline_send_service.dart';
// Список писем с:
// - Пагинацией (infinite scroll из SQLite по 30 штук)
// - Группировкой по дате (TODAY/YESTERDAY/дата)
// - Опциональной группировкой по conversation
// - Настраиваемыми свайпами из settings
// - Контекстным меню по долгому нажатию
// - Pull-to-refresh с haptic
// - Skeleton shimmer при загрузке
// - Адаптивный layout (tablet = 2-panel)

import 'package:flutter/gestures.dart' show kTouchSlop, HitTestResult;
import 'package:flutter/material.dart';
import '../../../services/mail/control_service.dart';
import '../../../services/mail/later_service.dart';
import '../widgets/later_sheet.dart';
import '../widgets/pending_send_strip.dart';
import '../widgets/scheduled_sends.dart' show ScheduledSendStrip;
import '../providers/pinned_mail.dart';
import '../../../widgets/common/undo_strip.dart';
import 'mail_list_pager.dart' show MailPagerArgs;
import '../../../widgets/ui/confirm_dialog.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/ui/empty_state.dart';
import 'package:flutter/rendering.dart' show RendererBinding, ScrollDirection, RenderMetaData;
import '../../../widgets/common/chrome_visibility.dart';
import 'package:flutter/services.dart' hide UndoManager;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateController;
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../settings/providers/account_groups_provider.dart' show activeGroupIdProvider, accountGroupsProvider, activeGroupAccountIdsProvider;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../data/models/email_model.dart';
import '../../../data/models/account_model.dart';
import '../../../widgets/common/adaptive_layout.dart';
import '../../../widgets/common/hero_email_transition.dart';
import '../../../widgets/common/offline_indicator.dart';
import '../../../services/mail/search_history_service.dart';
import '../../../widgets/common/undo_manager.dart';
import '../../../data/models/folder_model.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import '../../tasks/widgets/task_editor_sheet.dart' show showTaskEditorForEmail;
import '../providers/conversation_mute.dart';
import '../providers/mail_providers.dart';
import '../../../core/utils/folder_icons.dart';
import '../../../services/mail/folder_actions_service.dart';
import '../../../features/settings/providers/settings_provider.dart';
import '../../../widgets/common/inline_notice.dart' show showInlineError, showInlineNotice;
import '../widgets/account_auth_banner.dart';
import '../widgets/auto_reply_strip.dart';
import '../../../services/mail/own_addresses.dart';
import '../widgets/email_list_tile.dart';
import '../widgets/mail_peek_card.dart';
import '../widgets/peek_helpers.dart';
import '../../../widgets/common/peek_card.dart' show peekAnchorOf;
import '../../../widgets/common/quick_long_press.dart' show HoldPointer, HoldTracker;
import '../widgets/mail_freshness_line.dart';
import '../../../widgets/navigation/panel_requests.dart' show mailScrollTopRequestProvider, mailSearchQueryProvider;
import '../providers/account_look.dart';
import '../widgets/mail_drawer.dart';
import 'mail_detail_screen.dart';
import '../../../services/mail/email_actions_service.dart';
import '../../settings/providers/categories_provider.dart';
import '../../../data/database/app_database.dart';
import '../../../data/providers/database_provider.dart';
import '../../../services/mail/special_folders.dart';
import '../../../core/permissions/app_permissions.dart';
import '../../../widgets/common/app_sheet.dart';
import '../../../widgets/common/text_scale_cap.dart';
import '../../../widgets/ui/app_menu_button.dart';
import '../../../widgets/ui/section_band.dart';
import '../../../core/theme/ogneliss_look.dart';

class MailListScreen extends ConsumerStatefulWidget {
  const MailListScreen({super.key});

  @override
  ConsumerState<MailListScreen> createState() => _MailListScreenState();
}

class _MailListScreenState extends ConsumerState<MailListScreen> with WidgetsBindingObserver {
  /// С этой ширины области ленты папки стоят панелью слева (1.6.28):
  /// 272 dp папок + лента 340 + письмо 400 с запасом.
  static const _dockedFoldersMin = 1040.0;

  /// Меню выдвигается справа (телефон).
  bool _menuAtEnd = false;

  /// Открыть или закрыть меню ящиков и папок (на телефоне — справа).
  /// [open] — только открыть.
  void _toggleMenu({bool open = false}) {
    final s = _scaffoldKey.currentState;
    if (s == null) return;
    if (_menuAtEnd) {
      if (s.isEndDrawerOpen) {
        if (!open) s.closeEndDrawer();
      } else {
        s.openEndDrawer();
      }
    } else {
      if (s.isDrawerOpen) {
        if (!open) s.closeDrawer();
      } else {
        s.openDrawer();
      }
    }
  }

  /// Папки сейчас стоят панелью слева (строки можно перетаскивать на них).
  bool _foldersDocked = false;

  final _scrollController = ScrollController();

  /// Видимы ли вспомогательные панели (кнопка «Написать», нижняя навигация).
  /// Скрываются при прокрутке вниз, возвращаются при прокрутке вверх.
  bool _chromeVisible = true;
  double _lastScrollOffset = 0;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;

  // Для 2-panel layout на планшетах
  String? _selectedEmailId;
  // Кэш группировки по дате: пересчитываем только когда меняется сам список писем
  // или язык (а не на каждом ребилде — тема, режим выбора и т.п.).
  List<dynamic>? _cachedGrouped;
  List<EmailModel>? _cachedGroupedSource;
  String? _cachedGroupedRu; // код языка, для которого собраны заголовки
  // Режим множественного выбора (массовые действия).
  bool _selectionMode = false;
  MailSort? _cachedGroupedSort;
  bool _cachedGroupedLater = false;

  /// Закреплённые письма в ленте (1.6.49): подпись набора для кэша групп.
  String _cachedPinSig = '';

  // ── Плавающая дата (1.6.40, идея владельца 18.10.2026) ──
  // При прокрутке сверху ленты — плашка с датой группы, которая сейчас
  // вверху («ВЧЕРА», «16 ОКТЯБРЯ · ПЯТНИЦА»); после остановки прокрутки
  // исчезает. Дёшево: строки на экране отмечаются в [_rowMarks] (их 15–30),
  // на шаге прокрутки ищется верхняя; перестройка — только когда меняется
  // подпись или видимость.
  final Map<int, BuildContext> _rowMarks = {};
  EmailListState? _itemState;
  AppSettings? _itemSettings;
  List<String?> _groupLabelAt = const [];
  final _floatLabel = ValueNotifier<String?>(null);
  final _floatVisible = ValueNotifier<bool>(false);

  /// «↑ N новых» (1.6.48): сколько непрочитанных писем пришло выше, пока
  /// лента прокручена вниз; [_seenNewest] — самое новое письмо, которое было
  /// видно у верха ленты; [_newAboveKey] — папка, ящик, фильтр (сменились —
  /// счёт заново).
  final _newAbove = ValueNotifier<int>(0);
  DateTime? _seenNewest;
  DateTime? _currentNewest;
  String? _newAboveKey;
  final _listBoxKey = GlobalKey();

  /// Выбор писем проведением пальцем от портрета (1.6.47).
  late final _dragSelect = _DragSelect(this);
  Timer? _floatHide;
  final Set<String> _selectedIds = {};
  String? _selectedAccountId;

  /// «Назад» ленты (выбор → поиск → папка/фильтр → наверх) — его вызывает и
  /// оболочка через [mailBackRequestProvider].
  VoidCallback? _handleBack;
  DateTime? _lastBackAt;

  /// В ленте письма нескольких ящиков (Хаб аккаунтов или группа) — у
  /// каждого письма отмечается его ящик.
  bool get _multiAccountView =>
      ref.watch(accountsProvider).length > 1 &&
      (ref.watch(allAccountsModeProvider) || ref.watch(activeGroupIdProvider) != null);

  /// Сообщает оболочке о режиме выбора (см. [mailSelectionActiveProvider]).
  StateController<bool>? _selectionNotifier;

  void _publishSelection() {
    final active = _selectionMode || _selectedIds.isNotEmpty;
    final n = _selectionNotifier;
    if (n == null || n.state == active) return;
    // После кадра: менять провайдер во время build нельзя.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (n.state != active) n.state = active;
    });
  }

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _selectionNotifier = ref.read(mailSelectionActiveProvider.notifier);
    // Infinite scroll — подгрузка при приближении к концу
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    // Ctrl+E / Ctrl+Shift+F на десктопе — открыть поиск.
    ref.listenManual<int>(mailSearchRequestProvider, (_, __) {
      if (mounted && !_isSearching) setState(() => _isSearching = true);
    });
    // «Все письма от» в контактах (1.6.49+95): поиск по адресу. Запрос мог
    // прийти до появления ленты — тогда он выполняется после первого кадра.
    ref.listenManual<String?>(mailSearchQueryProvider, (_, q) {
      if (q != null) WidgetsBinding.instance.addPostFrameCallback((_) => _consumeSearchQuery());
    }, fireImmediately: true);
    // «Почта» внизу: меню ящиков и папок открыто — закрыть, закрыто —
    // открыть (1.5.10, просьба пользователей: второе нажатие закрывает).
    ref.listenManual<int>(mailDrawerRequestProvider, (_, __) {
      if (!mounted) return;
      ref.read(mailDrawerPendingProvider.notifier).state = false;
      _toggleMenu();
    });
    // Движок браузера для писем — заранее, через пару секунд после показа
    // ленты: первое письмо после запуска открывалось заметно дольше.
    // Загрузка движка занимает главный поток на доли секунды, поэтому — не
    // во время прокрутки ленты (ждём остановки, но не дольше ~10 с).
    var warmTries = 0;
    void warmUp() {
      if (!mounted) return;
      final scrolling = _scrollController.positions.any((p) => p.isScrollingNotifier.value);
      if (scrolling && ++warmTries < 8) {
        Future<void>.delayed(const Duration(seconds: 1), warmUp);
        return;
      }
      // Рабочий изолят открытия писем — тоже заранее (1.5.9).
      unawaited(WorkIsolate.interactive.warm());
      // Редактор письма (1,3 МБ скрипта и его хэш) — тоже заранее (1.6.19):
      // первое «Новое сообщение» открывалось с паузой.
      unawaited(warmUpMailEditor());
      _warmSpare();
    }
    Future<void>.delayed(const Duration(seconds: 2), warmUp);
    // Пришли из другого раздела нажатием на аватар ящика — сразу меню.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(mailDrawerPendingProvider)) return;
      ref.read(mailDrawerPendingProvider.notifier).state = false;
      _toggleMenu(open: true);
    });
    // Первая синхронизация при открытии (если есть активный аккаунт)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _applyStartupFolder();
      if (!mounted) return;
      final account = ref.read(activeAccountProvider);
      if (account != null) {
        // Один раз после входа — экран разрешений с пояснениями.
        unawaited(AppPermissions.maybeShowSetup(context));
        unawaited(ref.read(emailsProvider.notifier).refresh());
      }
    });
  }

  /// Папка при запуске (Настройки → Почта → «Открывать при запуске») —
  /// один раз за запуск приложения, не при каждом возврате на экран.
  static bool _startupApplied = false;

  Future<void> _applyStartupFolder() async {
    if (_startupApplied) return;
    _startupApplied = true;
    final mode = ref.read(startupFolderProvider);
    if (mode == StartupFolder.allMail) return; // так и открывается по умолчанию
    final db = ref.read(databaseProvider);
    String? accountId = ref.read(activeAccountProvider)?.id;
    String? folderId;
    if (mode == StartupFolder.last) {
      final last = ref.read(startupFolderProvider.notifier).lastSelection;
      if (last.accountId != null &&
          ref.read(accountsProvider).any((a) => a.id == last.accountId)) {
        if (last.accountId != accountId) {
          await ref.read(settingsProvider.notifier).setActiveAccountId(last.accountId!);
          accountId = last.accountId;
        }
        folderId = last.folderId;
      }
    } else if (accountId != null) {
      final inbox = await (db.select(db.folders)
            ..where((f) => f.accountId.equals(accountId!) & f.type.equals(FolderType.inbox.index))
            ..limit(1))
          .getSingleOrNull();
      folderId = inbox?.id;
    }
    if (!mounted || folderId == null) return;
    ref.read(allAccountsModeProvider.notifier).state = false;
    ref.read(unifiedModeProvider.notifier).state = false;
    ref.read(selectedFolderIdProvider.notifier).state = folderId;
  }

  /// Приложение сворачивали — при возврате лента начинается сверху: иначе
  /// после перерыва непонятно, где новые письма (замечание 08.10.2026).
  bool _wasBackgrounded = false;

  /// Лента прокручена от начала: «Назад» сначала возвращает её наверх и
  /// только со второго нажатия закрывает приложение.
  bool _awayFromTop = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      // Запасное окно закрывается в свёрнутом приложении — снова, в простое.
      unawaited(WorkScheduler.instance.run(WorkPriority.idle, () async {
        await Future<void>.delayed(const Duration(seconds: 2));
        _warmSpare();
      }));
      if (_scrollController.hasClients && _scrollController.offset > 0) {
        _scrollController.jumpTo(0);
      }
    }
  }

  /// «На контроле» из списка: своё письмо — жду ответа, чужое — должен ответить.
  /// Свёрнутая беседа в строке: группировка включена и у письма есть беседа.
  bool _rowIsConversation(EmailModel e) =>
      !_isSearching && ref.read(settingsProvider).groupByConversation && (e.conversationId ?? '').isNotEmpty;

  /// «На контроле» для строки (1.7.2, замечание 22.10.2026: «поставил на
  /// контроль, а кнопка всё равно доступна»). Строка свёрнутой беседы
  /// показывает отметку любого письма беседы, а карточка, свайп и меню
  /// смотрели только на верхнее письмо: строка — «на контроле», карточка —
  /// «На контроль», и нажатие ставило на контроль второе письмо беседы.
  int _rowControl(EmailModel e) {
    if (_rowIsConversation(e)) {
      final c = ref.read(conversationStatsProvider)[conversationKey(e.accountId, e.conversationId!)]?.control ?? 0;
      if (c != 0) return c;
    }
    return e.controlState;
  }

  /// Непрочитанная строка: у свёрнутой беседы — есть непрочитанные внутри
  /// (как жирный шрифт строки).
  bool _rowUnread(EmailModel e) {
    if (!e.isRead) return true;
    if (!_rowIsConversation(e)) return false;
    return (ref.read(conversationStatsProvider)[conversationKey(e.accountId, e.conversationId!)]?.unread ?? 0) > 0;
  }

  Future<void> _toggleControl(EmailModel email) async {
    final db = ref.read(databaseProvider);
    final notifier = ref.read(emailsProvider.notifier);
    if (_rowControl(email) != 0) {
      // Снять: с письма и — у свёрнутой беседы — со всех её писем на контроле.
      final ids = <String>{if (email.controlState != 0) email.id};
      if (_rowIsConversation(email)) {
        ids.addAll([for (final m in await db.conversationMembers(email.accountId, email.conversationId!, controlled: true)) m.id]);
      }
      for (final id in ids) {
        await db.setControlState(id, email.accountId, ControlState.none);
        notifier.applyLocalFlags(id, controlState: ControlState.none);
      }
    } else {
      final acc = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
      final next = ControlService.initialFor(
          fromEmail: email.from.email, myEmail: acc == null ? '' : OwnAddresses.of(acc).join(','), to: [for (final a in email.to) a.email]);
      await db.setControlState(email.id, email.accountId, next);
      notifier.applyLocalFlags(email.id, controlState: next);
    }
    // Отметка беседы в строке — пересчитать.
    notifier.invalidateConversationSizes();
    ref.read(controlRevisionProvider.notifier).state++;
  }

  /// «На контроль» выбранным письмам (уже отмеченные не меняются).
  Future<void> _bulkControl() async {
    final db = ref.read(databaseProvider);
    final notifier = ref.read(emailsProvider.notifier);
    final mine = {for (final a in ref.read(accountsProvider)) a.id: OwnAddresses.of(a).join(',')};
    for (final e in _selectedEmails()) {
      if (e.controlState != 0) continue;
      final next = ControlService.initialFor(fromEmail: e.from.email, myEmail: mine[e.accountId] ?? '', to: [for (final a in e.to) a.email]);
      await db.setControlState(e.id, e.accountId, next);
      notifier.applyLocalFlags(e.id, controlState: next);
    }
    ref.read(controlRevisionProvider.notifier).state++;
    _exitSelection();
  }

  /// Пересчитать «↑ N новых» по списку писем (после построения кадра —
  /// значение меняется не во время построения).
  void _trackNewAbove(List<EmailModel> emails, {required bool enabled}) {
    DateTime? newest;
    for (final e in emails) {
      if (newest == null || e.receivedAt.isAfter(newest)) newest = e.receivedAt;
    }
    _currentNewest = newest;
    final key = [
      ref.read(selectedFolderIdProvider),
      ref.read(activeAccountProvider)?.id,
      ref.read(unifiedModeProvider),
      ref.read(allAccountsModeProvider),
      ref.read(activeGroupIdProvider),
      ref.read(mailFilterProvider).name,
    ].join('|');
    final atTop = !_scrollController.hasClients || _scrollController.offset < 80;
    var n = 0;
    if (!enabled || key != _newAboveKey || _seenNewest == null || atTop) {
      _newAboveKey = key;
      _seenNewest = newest;
    } else {
      final seen = _seenNewest!;
      n = emails.where((e) => !e.isRead && e.receivedAt.isAfter(seen)).length;
    }
    if (n != _newAbove.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _newAbove.value = n;
      });
    }
  }

  /// Нажатие на «↑ N новых»: к началу ленты.
  void _jumpToNew() {
    unawaited(HapticFeedback.selectionClick());
    _seenNewest = _currentNewest ?? _seenNewest;
    _newAbove.value = 0;
    _scrollToTop();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    final off = _scrollController.offset;
    // Далеко внизу — сразу почти к началу, затем короткая анимация.
    if (off > 4000) _scrollController.jumpTo(600);
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _dragSelect.stop();
    WidgetsBinding.instance.removeObserver(this);
    _warmTimer?.cancel();
    _pressTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _floatHide?.cancel();
    _floatLabel.dispose();
    _floatVisible.dispose();
    _newAbove.dispose();
    _searchController.dispose();
    // Экран ушёл в режиме выбора — вернуть кнопку «Написать» оболочке.
    // Не во время демонтажа дерева: менять провайдер здесь нельзя.
    final sel = _selectionNotifier;
    if (sel != null) Future.microtask(() => sel.state = false);
    super.dispose();
  }

  /// Подгрузка следующей страницы при скролле
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(emailsProvider.notifier).loadNextPage();
    }
    _updateFloatingDate();

    // Прокрутка ВНИЗ — пользователь читает список, панели не нужны и только
    // занимают место на маленьком экране. Прокрутка ВВЕРХ — вероятно, ищет
    // действие, возвращаем. Порог 12 px гасит дрожание пальца: без него панель
    // мигала бы при малейшем движении.
    final dir = _scrollController.position.userScrollDirection;
    final offset = _scrollController.position.pixels;
    final away = offset > 300;
    if (away != _awayFromTop) setState(() => _awayFromTop = away);
    if (offset < 80) {
      // Долистали до верха — новые письма видны, плашка не нужна.
      _seenNewest = _currentNewest ?? _seenNewest;
      if (_newAbove.value != 0) _newAbove.value = 0;
      // У самого верха списка панели всегда видны.
      if (!_chromeVisible) {
        _chromeVisible = true;
        ref.read(chromeVisibleProvider.notifier).state = true;
      }
      return;
    }
    if (dir == ScrollDirection.reverse && _chromeVisible) {
      if ((offset - _lastScrollOffset).abs() > 12) {
        _lastScrollOffset = offset;
        _chromeVisible = false;
        ref.read(chromeVisibleProvider.notifier).state = false;
      }
    } else if (dir == ScrollDirection.forward && !_chromeVisible) {
      if ((_lastScrollOffset - offset).abs() > 12) {
        _lastScrollOffset = offset;
        _chromeVisible = true;
        ref.read(chromeVisibleProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(mailBackRequestProvider, (_, __) => _handleBack?.call());
    // Повторное нажатие на «Почту» внизу — к началу ленты (1.6.49).
    ref.listen<int>(mailScrollTopRequestProvider, (_, __) => _jumpToNew());
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final emailState = ref.watch(emailsProvider);
    _scheduleWarmFresh(emailState.emails);
    final isUnified = ref.watch(unifiedModeProvider);
    final allAccounts = ref.watch(allAccountsModeProvider);
    final account = ref.watch(activeAccountProvider);
    final settings = ref.watch(settingsProvider);

    // При смене папки или аккаунта сбрасываем выбранное письмо в master-detail,
    // иначе во встроенной панели остаётся письмо из прошлой папки/аккаунта.
    ref.listen(selectedFolderIdProvider, (prev, next) {
      if (prev != next && _selectedEmailId != null) {
        setState(() { _selectedEmailId = null; _selectedAccountId = null; });
      }
    });
    ref.listen(activeAccountProvider, (prev, next) {
      if (prev?.id != next?.id && _selectedEmailId != null) {
        setState(() { _selectedEmailId = null; _selectedAccountId = null; });
      }
    });

    // Заголовок. Выбрана группа ящиков — её имя (1.6.27: раньше «Вся почта»,
    // а в легенде — все ящики, хотя лента показывала только ящики группы).
    final groupId = ref.watch(activeGroupIdProvider);
    final group = groupId == null
        ? null
        : ref.watch(accountGroupsProvider).where((g) => g.id == groupId).firstOrNull;
    String title;
    if (group != null) {
      title = group.name;
    } else if (allAccounts) {
      title = l10n.tr('allAccounts');
    } else if (isUnified) {
      title = l10n.allMail;
    } else {
      // Имя папки, а не её идентификатор (у EWS это «AAMkAG…», у IMAP —
      // путь «INBOX/Проекты»).
      final fid = ref.watch(selectedFolderIdProvider);
      final folders = ref.watch(foldersProvider).value ?? const <FolderModel>[];
      title = fid == null
          ? l10n.inbox
          : (folders.where((f) => f.id == fid && (account == null || f.accountId == account.id))
                  .firstOrNull
                  ?.displayName ??
              l10n.inbox);
    }

    _publishSelection();
    final inSelection = _selectionMode || _selectedIds.isNotEmpty;
    // Шапка окрашивается по стилю для любого выбранного ящика (раньше в
    // «Вся почта» ящика часть стилей не применялась).
    final look = (account != null && !_multiAccountView)
        ? headerLook(ref.watch(accountHeaderStyleProvider), Color(account.colorValue), theme)
        : null;
    // При заливке текст и значки шапки — цвета, читаемого на цвете ящика.
    final fg = look?.foreground;
    final barTheme = fg == null
        ? theme
        : theme.copyWith(
            textTheme: theme.textTheme.apply(bodyColor: fg, displayColor: fg),
            colorScheme: theme.colorScheme.copyWith(onSurface: fg, primary: fg, onSurfaceVariant: fg),
            iconTheme: IconThemeData(color: fg),
          );
    // «Назад» по шагам: выбор → поиск → из папки или фильтра в папку по
    // умолчанию («Вся почта» ящика или общая лента) → наверх списка → выход.
    // Раньше из «Отправленных» «Назад» сразу закрывал приложение.
    // Папка по умолчанию — из «Открывать при запуске»: «Входящие» ящика или
    // «Вся почта» (и для «последней выбранной» — она меняется при каждом
    // переходе, возвращаться к ней бессмысленно).
    final homeInbox = ref.watch(startupFolderProvider) == StartupFolder.inbox;
    String? inboxId;
    if (homeInbox && account != null) {
      inboxId = (ref.watch(foldersProvider).value ?? const <FolderModel>[])
          .where((f) => f.accountId == account.id && f.type == FolderType.inbox)
          .firstOrNull
          ?.id;
    }
    final currentFolder = ref.watch(selectedFolderIdProvider);
    final atHome = (homeInbox && inboxId != null)
        ? (!isUnified && currentFolder == inboxId)
        : isUnified;
    final inFolder = !atHome && !allAccounts;
    final filtered = ref.watch(mailFilterProvider) != MailFilter.none;
    final canExit = !_awayFromTop && !inSelection && !_isSearching && !inFolder && !filtered;
    // Оболочка (нижняя панель) тоже держит «Назад»: она узнаёт, что ленте
    // есть куда возвращаться, и передаёт нажатие сюда. Без этого «Назад» в
    // папке, с фильтром или в режиме выбора закрывал приложение
    // (замечание 09.10.2026): нажатие доставалось оболочке, а не ленте.
    if (ref.read(mailBackHandlerProvider) == canExit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(mailBackHandlerProvider.notifier).state = !canExit;
      });
    }
    void handleBack() {
      final now = DateTime.now();
      if (_lastBackAt != null && now.difference(_lastBackAt!) < const Duration(milliseconds: 250)) return;
      _lastBackAt = now;
      if (inSelection) {
          _exitSelection();
        } else if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _searchDebounce?.cancel();
          });
          ref.read(emailsProvider.notifier).loadFirstPage();
        } else if (inFolder || filtered) {
          ref.read(mailFilterProvider.notifier).state = MailFilter.none;
          if (inFolder) {
            if (homeInbox && inboxId != null) {
              ref.read(unifiedModeProvider.notifier).state = false;
              ref.read(selectedFolderIdProvider.notifier).state = inboxId;
            } else {
              ref.read(unifiedModeProvider.notifier).state = true;
              ref.read(selectedFolderIdProvider.notifier).state = null;
            }
          }
          if (_awayFromTop) _scrollToTop();
        } else if (_awayFromTop) {
          _scrollToTop();
        }
    }
    _handleBack = handleBack;
    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        handleBack();
      },
      // Широкое окно (компьютер, планшет в альбомной ориентации): папки —
      // постоянной панелью слева, а не выдвижным меню (1.6.28, PLAN п. 25).
      child: LayoutBuilder(builder: (context, box) {
        // Телефон — меню выдвигается справа (портрет внизу справа, свайп от
        // правого края). Планшет и компьютер — слева; закреплено постоянной
        // панелью, если так выбрано значком в меню (или окно от 1040).
        final phone = AppBottomBar.inUse(context);
        final pinned = ref.watch(drawerPinnedProvider);
        final docked = !phone && (pinned ?? box.maxWidth >= _dockedFoldersMin);
        _foldersDocked = docked;
        // Сторона меню на телефоне — по настройке (по умолчанию слева).
        _menuAtEnd = phone && ref.watch(menuOnRightProvider);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (docked) ...[
              const SizedBox(width: 272, child: MailDrawer(docked: true)),
              VerticalDivider(width: 1, thickness: 1, color: theme.dividerColor),
            ],
            Expanded(child: Scaffold(
      key: _scaffoldKey,
      // Лента — на белом (1.6.25): серый фон под строками делал её тусклой.
      backgroundColor: AppColors.listFill(context),
      appBar: TextScaleCapBar(child: inSelection
          ? _buildSelectionAppBar(l10n, theme)
          : AppBar(
        // Шапка цвета ящика, когда открыт один ящик (в том числе его «Вся
        // почта»): рабочий и личный не перепутать. Стиль — в настройке цвета
        // ящика. В Хабе и группе — обычная.
        backgroundColor: look?.background,
        foregroundColor: look?.foreground,
        shape: look?.shape,
        flexibleSpace: look?.gradient == null
            ? null
            : DecoratedBox(decoration: BoxDecoration(gradient: look!.gradient)),
        // Телефон (1.6.40, решение владельца): портрета в шапке нет — меню
        // открывает портрет в нижней панели, под большим пальцем. Планшет и
        // компьютер (нижней панели нет) — портрет остаётся здесь.
        automaticallyImplyLeading: false,
        leading: AppBottomBar.inUse(context)
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: _buildAccountAvatar(account),
                  // Папки уже на экране — портрет ведёт к ящикам.
                  onPressed: docked ? () => context.push('/settings/accounts') : () => Scaffold.of(ctx).openDrawer(),
                  tooltip: l10n.tr('foldersAndAccounts'),
                ),
              ),
        title: _isSearching
            ? _buildSearchField(l10n)
            // Нажатие на название — «Проверка почты» (1.6.45): когда ящики
            // проверялись, в фоне и мгновенно, уведомления, «Проверить сейчас».
            : InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showMailCheckSheet(context),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(title, style: barTheme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: Space.s),
                    SyncStatusDot(onTap: () => showMailCheckSheet(context)),
                  ]),
                  // Сначала — когда почта обновлялась (1.6.47: «Обновлено
                  // сейчас», «в 15:40», давно — заметным цветом), затем адрес
                  // ящика. В Хабе — не адрес одного ящика (он вводил в
                  // заблуждение), а легенда: имена ящиков их цветами.
                  if (_multiAccountView)
                    Builder(builder: (_) {
                      final all = ref.watch(accountsProvider);
                      final shown = all.where((a) => group == null || group.accountIds.contains(a.id)).toList();
                      return MailFreshnessLine(
                        accounts: shown,
                        warnColor: fg ?? AppColors.warningText(context),
                        style: barTheme.textTheme.bodySmall?.copyWith(
                          color: barTheme.colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                        tail: [
                          for (final (i, a) in shown.indexed) ...[
                            if (i > 0) const TextSpan(text: '  '),
                            TextSpan(
                              text: '● ',
                              style: TextStyle(color: Color(a.colorValue)),
                            ),
                            TextSpan(text: EmailListTile.accountMarkOf(all, a.id)?.label ?? a.email),
                          ],
                        ],
                      );
                    })
                  else if (account != null)
                    MailFreshnessLine(
                      accounts: [account],
                      warnColor: fg ?? AppColors.warningText(context),
                      style: barTheme.textTheme.bodySmall?.copyWith(
                        color: barTheme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                      tail: [TextSpan(text: account.email)],
                    ),
                ],
              ),
              ),
        actions: [
          // Компактная пиктограмма офлайна/очереди: скрыта, когда сеть есть и
          // очередь пуста; иначе показывает иконку и число ожидающих операций.
          const OfflineIndicator(),
          IconButton(
            tooltip: _isSearching ? l10n.tr('cancel') : l10n.search,
            icon: Icon(_isSearching ? AppIcons.close : AppIcons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchDebounce?.cancel();
                  ref.read(emailsProvider.notifier).loadFirstPage();
                }
              });
            },
          ),
          IconButton(
            tooltip: l10n.tr('filter'),
            icon: const Icon(AppIcons.filter_list),
            onPressed: () => _showFilterSheet(context, l10n),
          ),
          AppMenuButton<String>(
            itemBuilder: (ctx) => [
              AppMenuEntry(value: 'sort', icon: AppIcons.sort, label: l10n.tr('sortBy')),
              AppMenuEntry(value: 'select_all', icon: AppIcons.select_all, label: l10n.tr('selectAll')),
              AppMenuEntry(value: 'mark_all_read', icon: AppIcons.done_all, label: l10n.tr('markAllRead')),
              AppMenuEntry(value: 'read_where_cc', icon: AppIcons.mark_email_read, label: l10n.tr('markReadWhereCc')),
              // «Очистить» — только в Корзине и Спаме, и именно открытую
              // папку: раньше пункт был везде и чистил только Корзину.
              if (_currentFolder()?.type case FolderType.trash || FolderType.junk)
                AppMenuEntry(
                  value: 'empty_trash',
                  icon: AppIcons.delete_sweep,
                  label: _currentFolder()?.type == FolderType.junk ? l10n.tr('clearJunk') : l10n.tr('emptyTrash'),
                  destructive: true,
                ),
              // Exchange (EWS): удалённое из «Удалённых» ещё ~14 дней на сервере.
              if (_currentFolder()?.type == FolderType.trash &&
                  (ref.read(activeAccountProvider)?.hasEwsExtras ?? false))
                AppMenuEntry(value: 'recover_deleted', icon: AppIcons.restore, label: l10n.tr('srvRecoverTitle')),
              const AppMenuEntry.divider(),
              AppMenuEntry(value: 'refresh', icon: AppIcons.sync, label: l10n.tr('sync')),
              AppMenuEntry(value: 'mail_check', icon: AppIcons.history, label: l10n.tr('mailCheckTitle')),
            ],
            onSelected: (value) => _handleMenuAction(value, l10n),
          ),
        ],
      )),

      // Телефон — справа (1.6.40, решение владельца: портрет «Меню» внизу
      // справа и свайп от правого края — под большим пальцем).
      drawer: docked || _menuAtEnd ? null : const MailDrawer(),
      endDrawer: _menuAtEnd ? const MailDrawer() : null,

      // В режиме выбора действия показываем внизу — до них можно дотянуться
      // одной рукой. В обычном режиме панели нет: место занимает список.
      bottomNavigationBar: inSelection
          ? _selectionBottomBar(l10n, theme)
          : null,

      body: AdaptiveLayout(
        widthKey: 'mail',
        showDetail: _selectedEmailId != null,
        detailBody: _selectedEmailId != null
            ? MailDetailScreen(
                key: ValueKey(_selectedEmailId),
                emailId: _selectedEmailId!,
                accountId: _selectedAccountId ?? (account?.id ?? ''),
                embedded: true,
              )
            : null,
        // Широкое окно: панель письма на месте и до выбора (1.6.28) —
        // лента не меняет ширину при первом нажатии.
        placeholder: _DetailPlaceholder(text: l10n.selectEmailPrompt),
        body: _withBottomStrips(_buildBody(emailState, theme, l10n, settings)),
      ),
    )),
          ],
        );
      }),
    );
  }

  /// Архивировать выбранные письма (папка «Архив» своего аккаунта у каждого).
  Future<void> _bulkArchive() async {
    if (_selectedIds.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final actions = ref.read(emailActionsProvider);
    var skipped = 0;
    var noFolder = false;
    _bulkInBackground(hide: true, (a, e) async {
      final archiveId = await _folderOfType(a.id, FolderType.archive);
      if (archiveId == null || archiveId == e.folderId) {
        skipped++;
        if (archiveId == null) noFolder = true;
        return;
      }
      await actions.moveTo(a, e.id, e.folderId, archiveId);
    }, done: () {
      // Нет папки — подсказка, где её выбрать; иначе — сколько пропущено.
      if (noFolder) {
        showInlineError(l10n.tr('archiveFolderNotFound'));
      } else if (skipped > 0) {
        showInlineError(l10n.tr('bulkMoveSkipped').replaceAll('{n}', '$skipped'));
      }
    });
  }

  /// Выбранные письма — в архив Ogneliss (1.7.3). Исходные — в «Удалённые»
  /// на сервере, если так настроено; не заархивированные (не скачалось
  /// вложение) остаются в ящике — строкой «Не удалось: N».
  Future<void> _bulkOgna({List<EmailModel>? emails}) async {
    if (emails == null && _selectedIds.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    if (!await ensureArchiveReady(context, ref) || !mounted) return;
    final runner = ref.read(archiveRunnerProvider.notifier);
    final db = ref.read(databaseProvider);
    final hide = ref.read(archiveSettingsProvider).deleteFromServer;
    var failed = 0;
    _bulkInBackground(hide: hide, (a, e) async {
      final row = await (db.select(db.emails)..where((x) => x.id.equals(e.id) & x.accountId.equals(a.id)))
          .getSingleOrNull();
      if (row == null) {
        failed++;
        return;
      }
      final r = await runner.archiveEmails(a, [row]);
      failed += r.failed;
    }, emails: emails, done: () {
      if (failed > 0) showInlineError(l10n.tr('archiveSomeFailed').replaceAll('{n}', '$failed'));
    });
  }

  /// Панель действий режима выбора — внизу экрана.
  ///
  /// Массовые операции делают на ходу, одной рукой: до верхней панели на
  /// шестидюймовом телефоне дотянуться нельзя без перехвата. Иконки крупные,
  /// с подписями — при выборе важно не промахнуться.
  Widget _selectionBottomBar(AppLocalizations l10n, ThemeData theme) {
    Widget action(IconData icon, String label, VoidCallback onTap,
        {Color? color}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 2),
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
    }

    // Фон панели — до края экрана (под жестовой полосой), кнопки — выше неё.
    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            action(AppIcons.mark_email_read, l10n.tr('markRead'),
                () => _bulkSetRead(true)),
            action(AppIcons.flag, l10n.tr('flag'),
                () => _bulkSetFlag(true)),
            action(AppIcons.drive_file_move, l10n.tr('move'),
                () => _bulkMove(l10n)),
            action(AppIcons.archive, l10n.tr('archive'), _bulkArchive),
            action(AppIcons.delete, l10n.delete, _bulkDelete,
                color: AppColors.errorRed),
          ],
        ),
      ),
    );
  }

  /// Адрес общего ящика для аккаунта письма, или null для собственного.
  /// Вынесено в метод: вызывается на каждую строку списка, а поиск по списку
  /// аккаунтов дешевле, чем отдельный запрос.
  String? _sharedMailboxOf(String accountId) {
    final acc = ref.read(accountsProvider).where((a) => a.id == accountId).firstOrNull;
    return acc?.isSharedMailbox == true ? acc!.sharedMailboxEmail : null;
  }

  /// Строки вверху ленты. Снизу — пустая полоса, если есть хоть одна
  /// строка (1.7.2): письма не уходят под нижний край строки вплотную.
  Widget _topStrips() => const GapBelowIfNotEmpty(
        gap: Space.s,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AccountAuthBanner(),
          // «Отправка через N с · Отменить» и «Письмо удалено · Вернуть» —
          // с 1.7.2+106 поверх ленты внизу (_withBottomStrips): здесь они
          // при появлении и исчезновении сдвигали всю ленту.
          // Отложенные письма (1.6.49): «Запланировано: N · ближайшее …».
          ScheduledSendStrip(),
          // Автоответ включён — «до 20 окт · Выключить» (вернувшись, не
          // забыть); с 1.7.2 строку можно скрыть крестиком.
          AutoReplyStrip(),
          // Honor, Xiaomi…: телефон может останавливать приложение в фоне.
          BackgroundHintStrip(),
          // Первая загрузка писем на телефон: расход выше обычного.
          FirstLoadStrip(),
        ]),
      );

  /// Строки с отсчётом и отменой — поверх ленты внизу, над нижней панелью
  /// (1.7.2+106, замечание владельца 24.10.2026: вставленные над лентой,
  /// они при появлении и исчезновении сдвигали всю ленту). Поверх любого
  /// состояния ленты: удалив последнее письмо папки, его можно вернуть и
  /// с пустого экрана. Без строк область нулевой высоты — касаниям ленты
  /// не мешает.
  Widget _withBottomStrips(Widget body) => Stack(fit: StackFit.expand, children: [
        body,
        const Positioned(
          left: 0,
          right: 0,
          bottom: Space.s,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PendingSendStrip(),
            UndoStrip(),
          ]),
        ),
      ]);

  /// Недавние поисковые запросы. Показываются, пока поле поиска пустое.
  Widget _buildSearchHistory(ThemeData theme, AppLocalizations l10n) {
    final history = ref.read(searchHistoryProvider).items;
    if (history.isEmpty) {
      return Center(
        child: Text(l10n.tr('search'), style: theme.textTheme.bodyMedium),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(l10n.tr('recentSearches'), style: theme.textTheme.titleSmall),
              ),
              TextButton(
                onPressed: () async {
                  await ref.read(searchHistoryProvider).clear();
                  if (mounted) setState(() {});
                },
                child: Text(l10n.tr('clear')),
              ),
            ],
          ),
        ),
        for (final q in history)
          ListTile(
            leading: const Icon(AppIcons.history, size: 20),
            title: Text(q),
            trailing: IconButton(
              icon: const Icon(AppIcons.close, size: 18),
              tooltip: l10n.tr('delete'),
              onPressed: () async {
                await ref.read(searchHistoryProvider).remove(q);
                if (mounted) setState(() {});
              },
            ),
            onTap: () {
              _searchController.text = q;
              ref.read(emailsProvider.notifier).search(q);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _buildBody(
    EmailListState emailState,
    ThemeData theme,
    AppLocalizations l10n,
    AppSettings settings,
  ) {
    // Поиск открыт, но запрос ещё не введён — показываем недавние запросы.
    // В рабочей переписке ищут одно и то же по многу раз (фамилия, номер
    // договора, узел), а набирать с телефона неудобно.
    if (_isSearching && _searchController.text.trim().isEmpty) {
      return _buildSearchHistory(theme, l10n);
    }

    if (emailState.isLoading) {
      return _buildSkeletonList(theme);
    }

    if (emailState.error != null) {
      return _buildErrorState(theme, l10n, emailState.error!);
    }

    // Быстрые фильтры строкой (1.6.45) — не в поиске и не при выборе писем.
    final quickFilters = ref.watch(quickFiltersProvider) && !_isSearching && !_selectionMode && _selectedIds.isEmpty;

    Future<void> onRefresh() async {
      unawaited(HapticFeedback.mediumImpact());
      await ref.read(emailsProvider.notifier).refresh();
    }

    if (emailState.emails.isEmpty) {
      // Пустая папка тоже обновляется жестом «потянуть вниз» — раньше на
      // пустом экране обновить было нечем.
      return Column(children: [
        _topStrips(),
        // Поиск — и по архиву Ogneliss (1.7.3): «В архиве Ogneliss: N».
        if (_isSearching) ArchiveSearchStrip(query: _searchController.text),
        if (quickFilters) const _QuickFilterBar(),
        _buildActiveFilterBanner(l10n, quickFilters: quickFilters),
        Expanded(
          child: _PinchFilter(
            onPinchIn: _pinchUnread,
            onPinchOut: _pinchClear,
            child: _QuickPullRefresh(
            onRefresh: onRefresh,
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(height: c.maxHeight, child: _buildEmptyState(theme, l10n)),
              ),
            ),
          ),
          ),
        ),
      ]);
    }

    return Column(
      children: [
        _topStrips(),
        if (_isSearching) ArchiveSearchStrip(query: _searchController.text),
        if (quickFilters) const _QuickFilterBar(),
        _buildActiveFilterBanner(l10n, quickFilters: quickFilters),
        Expanded(
          // Сведение двух пальцев — «Непрочитанные», разведение — сброс
          // любого фильтра.
          child: _PinchFilter(
            onPinchIn: _pinchUnread,
            onPinchOut: _pinchClear,
            child: _QuickPullRefresh(
              onRefresh: onRefresh,
              child: _buildEmailList(emailState, theme, l10n, settings),
            ),
          ),
        ),
      ],
    );
  }

  void _pinchUnread() {
    if (ref.read(mailFilterProvider) == MailFilter.unread) return;
    HapticFeedback.mediumImpact();
    ref.read(mailFilterProvider.notifier).state = MailFilter.unread;
    _pinchToast(AppLocalizations.of(context).tr('pinchUnreadOn'));
  }

  void _pinchClear() {
    final tag = ref.read(tagFilterProvider);
    if (ref.read(mailFilterProvider) == MailFilter.none && (tag == null || tag.isEmpty)) return;
    HapticFeedback.lightImpact();
    ref.read(mailFilterProvider.notifier).state = MailFilter.none;
    ref.read(tagFilterProvider.notifier).state = null;
    _pinchToast(AppLocalizations.of(context).tr('pinchFilterOff'));
  }

  /// Короткая подсказка, что жест сработал (строкой вверху, 1.8.0).
  void _pinchToast(String text) {
    showInlineNotice(text, duration: const Duration(milliseconds: 1500));
  }

  /// Подписи включённых фильтров: «Непрочитанные», «#Проект».
  static List<String> _filterParts(AppLocalizations l10n, MailFilter filter, String? tag) {
    final parts = <String>[];
    switch (filter) {
      case MailFilter.unread: parts.add(l10n.tr('unread')); break;
      case MailFilter.flagged: parts.add(l10n.tr('flagged')); break;
      case MailFilter.vip: parts.add('VIP'); break;
      case MailFilter.attachments: parts.add(l10n.tr('withAttachments')); break;
      case MailFilter.toMe: parts.add(l10n.tr('filterToMe')); break;
      case MailFilter.today: parts.add(l10n.tr('today')); break;
      case MailFilter.control: parts.add(l10n.tr('controlFilter')); break;
      case MailFilter.later: parts.add(l10n.tr('laterFilter')); break;
      case MailFilter.none: break;
    }
    if (tag != null && tag.isNotEmpty) parts.add('#$tag');
    return parts;
  }

  /// Плашка активного фильтра со сбросом (иначе скрытые письма сбивают с толку).
  Widget _buildActiveFilterBanner(AppLocalizations l10n, {bool quickFilters = false}) {
    final filter = ref.watch(mailFilterProvider);
    final tag = ref.watch(tagFilterProvider);
    if (filter == MailFilter.none && (tag == null || tag.isEmpty)) return const SizedBox.shrink();
    // Фильтр уже виден выбранным чипом — плашка нужна только для тега.
    if (quickFilters && (tag == null || tag.isEmpty)) return const SizedBox.shrink();
    final parts = _filterParts(l10n, filter, tag);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      padding: const EdgeInsets.only(left: Space.l, right: Space.s, top: Space.xs, bottom: Space.xs),
      child: Row(
        children: [
          Icon(AppIcons.filter_list, size: 16, color: scheme.primary),
          const SizedBox(width: Space.s),
          Expanded(child: Text(l10n.tr('filterPrefix').replaceAll('{parts}', parts.join(', ')), style: Theme.of(context).textTheme.bodyMedium)),
          TextButton(
            onPressed: () {
              ref.read(mailFilterProvider.notifier).state = MailFilter.none;
              ref.read(tagFilterProvider.notifier).state = null;
            },
            child: Text(l10n.tr('clearFilter')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailList(
    EmailListState emailState,
    ThemeData theme,
    AppLocalizations l10n,
    AppSettings settings,
  ) {
    final emails = emailState.emails;
    _itemState = emailState;
    _itemSettings = settings;

    // Группировка по дате (мемоизация: пересчёт только при смене списка/языка).
    final ru = l10n.localeCode;
    final sort = ref.read(mailSortProvider);
    final laterView = ref.read(mailFilterProvider) == MailFilter.later;
    final byDate = sort == MailSort.dateNewest || sort == MailSort.dateOldest;
    // Закреплённые письма (1.6.49, как в Telegram) — над лентой по дате,
    // без фильтров и поиска.
    final pinned = (sort == MailSort.dateNewest &&
            !laterView &&
            !_isSearching &&
            ref.read(mailFilterProvider) == MailFilter.none &&
            ref.read(tagFilterProvider) == null)
        ? _pinnedHere()
        : const <EmailModel>[];
    final pinSig = [for (final e in pinned) '${e.accountId}|${e.id}|${e.isRead}|${e.isFlagged}'].join(';');
    if (_cachedGrouped == null ||
        !identical(emails, _cachedGroupedSource) ||
        _cachedGroupedRu != ru ||
        _cachedGroupedSort != sort ||
        _cachedGroupedLater != laterView ||
        _cachedPinSig != pinSig) {
      _cachedGroupedLater = laterView;
      _cachedPinSig = pinSig;
      final pinKeys = {for (final e in pinned) '${e.accountId}|${e.id}'};
      final rest = pinKeys.isEmpty
          ? emails
          : [for (final e in emails) if (!pinKeys.contains('${e.accountId}|${e.id}')) e];
      _cachedGrouped = laterView
          ? _groupByLater(emails, l10n)
          : (byDate
              ? [
                  if (pinned.isNotEmpty) ...[l10n.tr('pinnedBand'), ...pinned],
                  ..._groupByDate(rest, l10n),
                ]
              : List<dynamic>.from(emails));
      _cachedGroupedSource = emails;
      _cachedGroupedRu = ru;
      // Подпись группы для каждой строки — для плавающей даты.
      String? cur;
      _groupLabelAt = [
        for (final g in _cachedGrouped!) (g is String) ? (cur = g) : cur,
      ];
      _cachedGroupedSort = sort;
    }
    final grouped = _cachedGrouped!;
    // «↑ N новых» — только в ленте по дате (новые сверху).
    _trackNewAbove(emails, enabled: sort == MailSort.dateNewest && !laterView && !_isSearching && !_selectionMode);

    final list = ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      // Запас снизу под кнопку «Написать»: она закрывала метку папки и
      // время последнего письма, и прокрутить его из-под кнопки было нельзя.
      padding: const EdgeInsets.only(bottom: 96),
      // +1 для индикатора подгрузки снизу
      itemCount: grouped.length + (emailState.hasMore ? 1 : 0),
      itemBuilder: (context, index) => _RowMark(index: index, marks: _rowMarks, child: _itemAt(context, index)),
    );
    return Stack(children: [
      KeyedSubtree(key: _listBoxKey, child: list),
      // «↑ N новых» (1.6.48, как кнопка новых сообщений в Telegram): ниже
      // плавающей даты, чтобы не закрывать её.
      Positioned(
        top: Space.xxl + Space.m,
        left: 0,
        right: 0,
        child: ValueListenableBuilder<int>(
          valueListenable: _newAbove,
          builder: (context, n, _) => AnimatedSwitcher(
            duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
            child: n <= 0
                ? const SizedBox.shrink()
                : Center(
                    key: const ValueKey('newAbove'),
                    child: _NewAbovePill(label: l10n.plural('newAboveN', n), onTap: _jumpToNew),
                  ),
          ),
        ),
      ),
      // Плавающая дата: по центру сверху, во время прокрутки.
      Positioned(
        top: Space.s,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: ValueListenableBuilder<bool>(
            valueListenable: _floatVisible,
            builder: (context, visible, _) => AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: ValueListenableBuilder<String?>(
                valueListenable: _floatLabel,
                builder: (context, label, _) =>
                    label == null ? const SizedBox.shrink() : Center(child: _FloatingDateChip(label: label)),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Строка ленты по номеру (группы дат, письма, индикатор подгрузки).
  Widget _itemAt(BuildContext context, int index) {
        // Те же состояние и настройки, с которыми строится лента (в поиске —
        // состояние поиска, а не общей ленты).
        // Заданы в _buildEmailList до построения строк (без «??»: тип
        // провайдера шире, и анализатор считал результат nullable).
        final AppSettings settings = _itemSettings!;
        final l10n = AppLocalizations.of(context);
        final EmailListState emailState = _itemState!;
        final grouped = _cachedGrouped ?? const [];
        // Индикатор подгрузки
        if (index == grouped.length) {
          return emailState.isLoadingMore
              ? const Padding(
                  padding: EdgeInsets.all(Space.l),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const SizedBox(height: 80);
        }

        final item = grouped[index];

        // Заголовок группы
        // (СЕГОДНЯ / ВЧЕРА / дни) — серой полосой, как разделы бокового меню.
        if (item is String) return SectionBand.light(title: item);

        if (item is EmailModel) {
          // Отложенное письмо в Исходящих (Undo Send) — отдельный свайп «Отменить
          // отправку» вместо настраиваемых действий: убрать из очереди, вернуть в
          // Черновики (через готовый cancelUndoSend).
          if (item.folderId == 'outbox' && item.id.startsWith('undosend_')) {
            return Slidable(
              key: ValueKey('${item.id}_${item.accountId}'),
              endActionPane: ActionPane(
                motion: const BehindMotion(),
                extentRatio: 0.5,
                children: [
                  SlidableAction(
                    onPressed: (_) async {
                      final ok = await ref.read(offlineSendProvider).cancelUndoSend(item.id);
                      await ref.read(emailsProvider.notifier).refresh();
                      showInlineNotice(ok ? l10n.tr('cancelledToDrafts') : l10n.tr('alreadySent'));
                    },
                    backgroundColor: SwipeTone.of(context, AppColors.errorRed).$1,
                    foregroundColor: SwipeTone.of(context, AppColors.errorRed).$2,
                    icon: AppIcons.undo,
                    label: l10n.tr('undo'),
                  ),
                ],
              ),
              child: EmailListTile(
                email: item,
                showConversationIndicator: settings.groupByConversation,
                // Метка папки нужна там, где письма из разных папок: сводные
                // режимы и результаты поиска. Внутри папки она избыточна.
                showFolderBadge: _isSearching ||
                    ref.watch(unifiedModeProvider) ||
                    ref.watch(selectedFolderIdProvider) == null,
                // Хаб аккаунтов и группа: в одной ленте несколько ящиков.
                showAccountMark: _multiAccountView,
                // Общий ящик выделяем всегда, независимо от режима: перепутать
                // свою переписку с делегированной — дорогая ошибка.
                sharedMailboxEmail: _sharedMailboxOf(item.accountId),
                // Письмо ещё в очереди отправки (окно отмены) — открывать нечего.
                onTap: () {},
              ),
            );
          }
          // Метка строки — для выбора писем проведением пальцем (1.6.47).
          final row = MetaData(
            metaData: _SelRow(item.id),
            behavior: HitTestBehavior.translucent,
            child: Slidable(
            key: ValueKey('${item.id}_${item.accountId}'),
            // Свайп влево и вправо настраиваются независимо.
            //
            // Поведение зависит от числа назначенных действий:
            //  · одно действие — полный свайп выполняет его СРАЗУ, ждать выбора
            //    не нужно (быстрый разбор почты одним движением);
            //  · два действия — кнопки раскрываются и ждут выбора.
            startActionPane: _buildActionPane(
              primary: settings.swipeLeftPrimary,
              secondary: settings.swipeLeftSecondary,
              email: item,
              l10n: l10n,
              fromStart: true,
            ),
            endActionPane: _buildActionPane(
              primary: settings.swipeRightPrimary,
              secondary: settings.swipeRightSecondary,
              email: item,
              l10n: l10n,
              fromStart: false,
            ),
            // Касание строки (палец ещё на экране) — письмо читается из базы
            // заранее; тело готовится при нажатии (касанием начинается и
            // прокрутка ленты — готовить каждое письмо под пальцем незачем).
            child: Listener(
              onPointerDown: (ev) {
                if (_selectionMode) return;
                ref.read(mailOpenCacheProvider).prefetch(item.accountId, item.id, body: false);
                _pressStart(context, item, ev.position, settings.groupByConversation);
              },
              onPointerMove: (ev) {
                final at = _pressAt;
                if (at != null && (ev.position - at).distance > kTouchSlop) _pressCancel();
              },
              onPointerUp: (_) => _pressCancel(),
              onPointerCancel: (_) => _pressCancel(),
              // Свой context у строки (1.6.36): context построителя ленты —
              // это вся лента (RenderSliver, не RenderBox), и карточка по
              // удержанию падала на приведении типа — «не открывается в
              // ленте, только в беседах».
              child: Builder(builder: (rowCtx) => EmailListTile(
              email: item,
              // В «Позже» вместо даты получения — когда письмо вернётся.
              showLaterTime: ref.read(mailFilterProvider) == MailFilter.later,
              showConversationIndicator: settings.groupByConversation,
              showFolderBadge: _isSearching ||
                    ref.watch(unifiedModeProvider) ||
                    ref.watch(selectedFolderIdProvider) == null,
              showAccountMark: _multiAccountView,
              sharedMailboxEmail: _sharedMailboxOf(item.accountId),
              isSelected: _selectedEmailId == item.id,
              isInSelectionMode: _selectionMode,
              isChecked: _selectedIds.contains(item.id),
              onCheckChanged: () => _toggleSelect(item.id),
              onTap: () async {
                if (_selectionMode) {
                  _toggleSelect(item.id);
                  return;
                }
                unawaited(HapticFeedback.selectionClick());
                await _openEmail(context, item, settings.groupByConversation);
              },
              // На Windows и с мышью меню открывается правой кнопкой — раньше
              // до него можно было добраться только долгим нажатием в режиме
              // выбора. С 1.8.8 — та же карточка, что по удержанию (была
              // отдельная шторка со своим списком).
              onSecondaryTap: () => _showPeek(rowCtx, item, l10n),
              // Долгое нажатие: на строке — меню действий, на портрете —
              // выбор писем (09.10.2026).
              onLongPress: () {
                HapticFeedback.mediumImpact();
                // Карточка письма с быстрыми действиями (1.6.29, «как в
                // Telegram»); полный список — «Ещё…» в ней.
                _showPeek(rowCtx, item, l10n);
              },
              // Не отпуская палец — на кнопку карточки (1.6.46).
              holdTracker: HoldPointer.instance,
              // Не отпуская палец после удержания портрета — вести по ленте:
              // письма подряд отмечаются (1.6.47).
              avatarHoldTracker: _dragSelect,
              onAvatarLongPress: () {
                HapticFeedback.mediumImpact();
                if (_selectionMode) {
                  _toggleSelect(item.id);
                } else {
                  setState(() {
                    _selectionMode = true;
                    _selectedIds.add(item.id);
                  });
                }
              },
            )),
            ),
          ));
          // Постоянная панель папок (широкое окно): письмо можно перетащить
          // мышью на папку (1.6.28). Только мышью — пальцем строка, как
          // раньше, свайпается и прокручивается.
          // Draggable не умеет «только мышь» (supportedDevices у него нет):
          // перетаскивание — только когда подключена мышь, иначе палец
          // начинал бы перетаскивание вместо прокрутки.
          if (!_foldersDocked || _selectionMode || !RendererBinding.instance.mouseTracker.mouseIsConnected) {
            return row;
          }
          return Draggable<EmailModel>(
            data: item,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _DragChip(subject: item.subject.isEmpty ? l10n.tr('noSubject') : item.subject),
            childWhenDragging: Opacity(opacity: 0.4, child: row),
            child: row,
          );
        }

        return const SizedBox.shrink();
  }

  /// Какая группа сейчас вверху ленты — плашка с её датой. Если вверху сам
  /// заголовок группы (или лента у начала) — плашки нет: дата и так видна.
  void _updateFloatingDate() {
    if (_groupLabelAt.isEmpty || !_scrollController.hasClients) return;
    final listBox = _listBoxKey.currentContext?.findRenderObject();
    if (listBox is! RenderBox || !listBox.attached) return;
    final top = listBox.localToGlobal(Offset.zero).dy + 1;
    int? atTop;
    for (final e in _rowMarks.entries) {
      if (!e.value.mounted) continue;
      final ro = e.value.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final y = ro.localToGlobal(Offset.zero).dy;
      if (y <= top && y + ro.size.height > top) {
        atTop = e.key;
        break;
      }
    }
    final grouped = _cachedGrouped;
    String? label;
    if (atTop != null && atTop < _groupLabelAt.length && grouped != null && atTop < grouped.length) {
      label = grouped[atTop] is String ? null : _groupLabelAt[atTop];
    }
    if (_scrollController.position.pixels < 40) label = null;
    if (_floatLabel.value != label) _floatLabel.value = label;
    if (label != null && !_floatVisible.value) _floatVisible.value = true;
    _floatHide?.cancel();
    _floatHide = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _floatVisible.value = false;
    });
  }

  // ════════════════════════ СВАЙП-ДЕЙСТВИЯ ════════════════════════

  /// Собирает панель свайпа из назначенных действий.
  ///
  /// Поведение зависит от их числа:
  ///  · **одно действие** — полный свайп выполняет его СРАЗУ (`DismissiblePane`).
  ///    При разборе почты это главное: одно движение — письмо обработано;
  ///  · **два действия** — кнопки раскрываются и ждут выбора. Автосрабатывания
  ///    нет намеренно: когда вариантов несколько, случайный сильный свайп не
  ///    должен что-то удалять.
  ///
  /// Возвращает null, если действий не назначено — тогда свайп в эту сторону
  /// просто не работает.
  ActionPane? _buildActionPane({
    required SwipeAction primary,
    required SwipeAction secondary,
    required EmailModel email,
    required AppLocalizations l10n,
    required bool fromStart,
  }) {
    final hasPrimary = primary != SwipeAction.none;
    final hasSecondary = secondary != SwipeAction.none;
    if (!hasPrimary && !hasSecondary) return null;

    // Вид значков этой панели (1.6.21): сторона, одно/два действия, порог.
    final singleAction = hasPrimary != hasSecondary;
    _pane = (
      fromStart: fromStart,
      atEdge: singleAction,
      extentRatio: singleAction ? 0.28 : 0.5,
      armAt: singleAction ? 0.4 : null,
    );

    final actions = <CustomSlidableAction>[
      if (hasPrimary) _buildSwipeAction(primary, email, l10n, isPrimary: true),
      if (hasSecondary) _buildSwipeAction(secondary, email, l10n, isPrimary: false),
    ];

    // Одно действие — выполняем сразу при полном свайпе. Строка «уходит»
    // из списка только для действий, которые убирают письмо из папки
    // (архив, удаление, спам). Для остальных (прочитано, флаг, ответ…)
    // раньше строка тоже схлопывалась и оставалась пустым местом до
    // перерисовки — теперь действие выполняется, а строка возвращается.
    final single = actions.length == 1;
    final action = hasPrimary ? primary : secondary;
    final removes = action == SwipeAction.archive ||
        action == SwipeAction.delete ||
        action == SwipeAction.moveToJunk;
    return ActionPane(
      // Одно действие — панель стоит на месте, строка отъезжает и открывает
      // её от края, где и стоит значок: он виден с первых миллиметров
      // (1.6.21; с DrawerMotion значок выезжал вместе с панелью и был виден
      // только при длинном свайпе). Два действия — как раньше.
      motion: single ? const BehindMotion() : const DrawerMotion(),
      extentRatio: single ? 0.28 : 0.5,
      dismissible: single
          ? DismissiblePane(
              // По умолчанию строку нужно было протянуть на 75 % ширины —
              // почти через весь экран. 40 %: отпустили дальше — строка
              // сама доезжает до конца и действие срабатывает.
              dismissThreshold: 0.4,
              dismissalDuration: const Duration(milliseconds: 220),
              resizeDuration: const Duration(milliseconds: 220),
              closeOnCancel: true,
              // Удаление беседы из нескольких писем — сначала вопрос: строка
              // уходит, только когда выбор сделан (1.6.26).
              confirmDismiss: removes
                  ? (action == SwipeAction.delete && _conversationSize(email) > 1
                      ? () async {
                          final whole = await _askDeleteScope(l10n, _conversationSize(email));
                          if (whole == null) return false;
                          _deleteScope[_scopeKey(email)] = whole;
                          return true;
                        }
                      : null)
                  : () async {
                      _executeSwipeAction(action, email, l10n);
                      return false;
                    },
              onDismissed: () => _executeSwipeAction(action, email, l10n),
            )
          : null,
      children: actions,
    );
  }

  /// Выбор «вся беседа / только письмо», сделанный до ухода строки при
  /// полном свайпе.
  final Map<String, bool> _deleteScope = {};
  static String _scopeKey(EmailModel e) => '${e.accountId}/${e.id}';

  /// Выполнить действие свайпа напрямую (полный свайп при одном действии).
  /// Логика та же, что у кнопки, — вынесена, чтобы не расходилась.
  void _executeSwipeAction(SwipeAction action, EmailModel email, AppLocalizations l10n) {
    switch (action) {
      case SwipeAction.markRead:
        _toggleRead(email);
      case SwipeAction.flag:
        _toggleFlag(email);
      case SwipeAction.archive:
        _archiveEmail(email, l10n);
      case SwipeAction.delete:
        _deleteEmail(email, l10n, whole: _deleteScope.remove(_scopeKey(email)));
      case SwipeAction.moveToJunk:
        _moveToJunk(email, l10n);
      case SwipeAction.moveTo:
        _moveSingle(email, l10n);
      case SwipeAction.snooze:
        _snoozeSingle(email, l10n);
      case SwipeAction.reply:
        context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}');
      case SwipeAction.forward:
        _forward(email, l10n);
      case SwipeAction.createTask:
        _createTaskFromEmail(email, l10n);
      case SwipeAction.findBySender:
        _searchBySender(email);
      case SwipeAction.control:
        _toggleControl(email);
      case SwipeAction.toOgna:
        unawaited(_bulkOgna(emails: [email]));
      case SwipeAction.none:
        break;
    }
  }

  /// Переместить письмо в «Спам». Папка ищется ПО ТИПУ: её идентификатор у
  /// разных серверов различается (EWS `junkemail`, IMAP «Спам»/«Junk»).
  /// Раньше свайп «В спам» имел пустой обработчик и ничего не делал.
  Future<void> _moveToJunk(EmailModel email, AppLocalizations l10n) =>
      // С «Вернуть», как «В архив» и удаление (1.7.2+106; раньше перенос сразу).
      _moveWithUndo(email, FolderType.junk, l10n.tr('movedToJunk'), l10n.tr('junkFolderNotFound'));

  /// «Не спам»: из папки спама — во «Входящие» (карточка по удержанию).
  Future<void> _notJunk(EmailModel email, AppLocalizations l10n) =>
      _moveWithUndo(email, FolderType.inbox, l10n.tr('restoredToInbox'), l10n.tr('inboxFolderNotFound'));

  /// Письмо лежит в папке спама своего ящика.
  bool _inJunk(EmailModel e) {
    bool junk(List<FolderModel>? list) =>
        list?.any((f) => f.id == e.folderId && f.accountId == e.accountId && f.type == FolderType.junk) ?? false;
    return junk(ref.read(foldersProvider).value) || junk(ref.read(accountFoldersProvider(e.accountId)).value);
  }

  /// Переместить ОДНО письмо в выбранную папку (свайп «Переместить»).
  Future<void> _moveSingle(EmailModel email, AppLocalizations l10n) async {
    // Папки аккаунта ПИСЬМА из базы: foldersProvider знает только активный.
    final db = ref.read(databaseProvider);
    final folders = await (db.select(db.folders)
          ..where((f) => f.accountId.equals(email.accountId))
          ..orderBy([(f) => OrderingTerm(expression: f.sortOrder)]))
        .get();
    if (!mounted) return;
    // Карточкой (1.8.8), как меню «⋮». Только папки аккаунта этого
    // письма: переместить письмо между ящиками разных серверов нельзя.
    final targetId = await showChoiceSheet<String>(
      context,
      title: AppLocalizations.of(context).tr('moveToDots'),
      entries: [
        for (final f in folders.where((f) => f.id != email.folderId))
          AppMenuEntry(value: f.id, label: f.displayName, icon: folderIconOf(folderFromRow(f))),
      ],
    );
    final target = folders.where((f) => f.id == targetId).firstOrNull;
    if (target == null || !mounted) return;
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    if (account == null) return;
    await ref.read(emailActionsProvider).moveTo(account, email.id, email.folderId, target.id);
  }

  /// «Посмотреть позже» — свайпом, без открытия письма.
  Future<void> _snoozeSingle(EmailModel email, AppLocalizations l10n) async {
    await postponeEmails(context, ref, [email]);
  }

  /// «Позже» для выбранных писем.
  Future<void> _bulkLater() async {
    final list = _selectedEmails();
    if (list.isEmpty) return;
    final choice = await showLaterSheet(context);
    if (choice == null || !mounted) return;
    await applyLater(ref, list, choice);
    _exitSelection();
  }

  /// Задача из письма или беседы (свайп, карточка по удержанию, меню):
  /// карточка задачи с названием из темы и ссылкой на письмо — как в самом
  /// письме. Раньше задача создавалась молча, и казалось, что ничего не
  /// происходит (замечание 27.10.2026).
  Future<void> _createTaskFromEmail(EmailModel email, AppLocalizations l10n) async {
    if (!mounted) return;
    await showTaskEditorForEmail(context, email);
  }

  /// Встреча по письму или беседе: тема, участники и текст — из письма.
  /// Раньше отсюда открывалась пустая форма (замечание 27.10.2026).
  void _planMeeting(EmailModel email) {
    unawaited(context.push('/create-event', extra: {'email': email}));
  }

  /// Показать все письма отправителя (свайп «Найти по отправителю»).
  /// Переслать (запрет пересылки по грифу убран вместе с грифом, 1.5.9).
  void _forward(EmailModel email, AppLocalizations l10n) {
    context.push('/compose?forwardFromId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}');
  }

  void _consumeSearchQuery() {
    if (!mounted) return;
    final q = ref.read(mailSearchQueryProvider);
    if (q == null || q.trim().isEmpty) return;
    ref.read(mailSearchQueryProvider.notifier).state = null;
    setState(() {
      _isSearching = true;
      _searchController.text = q;
    });
    unawaited(ref.read(emailsProvider.notifier).search(q));
  }

  void _searchBySender(EmailModel email) {
    setState(() {
      _isSearching = true;
      _searchController.text = email.from.email;
    });
    ref.read(emailsProvider.notifier).search(email.from.email);
  }

  CustomSlidableAction _buildSwipeAction(
    SwipeAction action,
    EmailModel email,
    AppLocalizations l10n, {
    required bool isPrimary,
  }) {
    switch (action) {
      case SwipeAction.markRead:
        return _swipe(
          onPressed: (_) => _toggleRead(email),
          backgroundColor: AppColors.infoBlue,
          foregroundColor: Colors.white,
          icon: _rowUnread(email) ? AppIcons.mark_email_read : AppIcons.mark_email_unread,
          label: _rowUnread(email) ? l10n.tr('markRead') : l10n.tr('markUnread'),
        );
      case SwipeAction.flag:
        return _swipe(
          onPressed: (_) => _toggleFlag(email),
          backgroundColor: AppColors.warningYellow,
          foregroundColor: Colors.white,
          icon: AppIcons.flag,
          label: l10n.tr('flag'),
        );
      case SwipeAction.archive:
        return _swipe(
          onPressed: (_) => _archiveEmail(email, l10n),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.archive,
          label: l10n.tr('archive'),
        );
      case SwipeAction.delete:
        return _swipe(
          onPressed: (_) => _deleteEmail(email, l10n),
          backgroundColor: AppColors.errorRed,
          foregroundColor: Colors.white,
          icon: AppIcons.delete,
          label: l10n.delete,
        );
      case SwipeAction.moveToJunk:
        return _swipe(
          onPressed: (_) => _moveToJunk(email, l10n),
          backgroundColor: AppColors.accentOrange,
          foregroundColor: Colors.white,
          icon: AppIcons.report,
          label: l10n.tr('moveToJunk'),
        );
      case SwipeAction.moveTo:
        return _swipe(
          onPressed: (_) => _moveSingle(email, l10n),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.drive_file_move,
          label: l10n.tr('move'),
        );
      case SwipeAction.snooze:
        return _swipe(
          onPressed: (_) => _snoozeSingle(email, l10n),
          backgroundColor: AppColors.accentOrange,
          foregroundColor: Colors.white,
          icon: AppIcons.watch_later,
          label: l10n.tr('later'),
        );
      case SwipeAction.reply:
        return _swipe(
          onPressed: (_) => context.push('/compose?replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}'),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.reply,
          label: l10n.tr('reply'),
        );
      case SwipeAction.forward:
        return _swipe(
          onPressed: (_) => _forward(email, l10n),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.forward,
          label: l10n.tr('forward'),
        );
      case SwipeAction.createTask:
        return _swipe(
          onPressed: (_) => _createTaskFromEmail(email, l10n),
          backgroundColor: AppColors.successGreen,
          foregroundColor: Colors.white,
          icon: AppIcons.add_task,
          label: l10n.tr('tasksLabel'),
        );
      case SwipeAction.findBySender:
        return _swipe(
          onPressed: (_) => _searchBySender(email),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.person_search,
          label: l10n.tr('from'),
        );
      case SwipeAction.control:
        return _swipe(
          onPressed: (_) => _toggleControl(email),
          backgroundColor: AppColors.successGreen,
          foregroundColor: Colors.white,
          icon: AppIcons.task_alt,
          label: l10n.tr(_rowControl(email) == 0 ? 'controlSet' : 'controlClear'),
        );
      // В архив Ogneliss на устройстве (29.10.2026).
      case SwipeAction.toOgna:
        return _swipe(
          onPressed: (_) => unawaited(_bulkOgna(emails: [email])),
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          icon: AppIcons.inventory_2,
          label: l10n.tr('ognaArchive'),
        );
      case SwipeAction.none:
        return _swipe(
          onPressed: (_) {},
          backgroundColor: AppColors.tagGeneral,
          foregroundColor: Colors.white,
          icon: AppIcons.more_horiz,
          label: '',
        );
    }
  }

  /// Действие свайпа: крупная иконка без подписи (замечание 06.10.2026 —
  /// подписи мелкие и обрезались, иконку видно издалека). Подпись остаётся
  /// для экранного диктора.
  CustomSlidableAction _swipe({
    required void Function(BuildContext) onPressed,
    required Color backgroundColor,
    Color foregroundColor = Colors.white,
    required IconData icon,
    required String label,
  }) {
    // Спокойные тональные цвета вместо насыщенной заливки с белым значком.
    final (bg, fg) = SwipeTone.of(context, backgroundColor);
    final settings = ref.read(settingsProvider);
    final pane = _pane;
    return CustomSlidableAction(
      onPressed: onPressed,
      backgroundColor: bg,
      foregroundColor: fg,
      padding: EdgeInsets.zero,
      child: Semantics(
        label: label,
        button: true,
        child: ExcludeSemantics(
          child: SwipeActionIndicator(
            icon: icon,
            label: label,
            color: fg,
            fromStart: pane.fromStart,
            atEdge: pane.atEdge,
            extentRatio: pane.extentRatio,
            armAt: pane.armAt,
            animated: settings.swipeAnimated && !settings.reduceMotion,
          ),
        ),
      ),
    );
  }

  /// Панель, для которой сейчас собираются кнопки (см. _buildActionPane).
  ({bool fromStart, bool atEdge, double extentRatio, double? armAt}) _pane =
      (fromStart: true, atEdge: false, extentRatio: 0.5, armAt: null);

  // ════════════════════════ КОНТЕКСТНОЕ МЕНЮ ════════════════════════

  // ════════════════════════ РЕЖИМ ВЫБОРА (массовые действия) ════════════════════════

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelection() => setState(() { _selectionMode = false; _selectedIds.clear(); });

  void _selectAllLoaded() {
    final ids = ref.read(emailsProvider).emails.map((e) => e.id);
    setState(() => _selectedIds.addAll(ids));
  }

  // ── Массовые действия ──
  // Раньше все они брали АКТИВНЫЙ аккаунт и папку первого письма, а цели
  // переноса подставляли строками 'archive'/'trash'. В сводной ленте и в
  // «Всех аккаунтах» письма из других ящиков уходили не в тот аккаунт или
  // не переносились вовсе. Теперь выбранные письма группируются по
  // аккаунту, у каждого письма — своя папка, цели ищутся по типу папки.

  List<EmailModel> _selectedEmails() => ref
      .read(emailsProvider)
      .emails
      .where((e) => _selectedIds.contains(e.id))
      .toList();

  /// Массовое действие без ожидания: строки сразу уходят из списка (или
  /// меняют вид), выбор закрывается, а запросы к серверу идут следом по
  /// очереди, в фоне (замечание 09.10.2026: удаление и «прочитано» шли по
  /// одному письму, и экран ждал каждое). Сбой связи — действие ложится в
  /// очередь отправки (email_actions_service) и уйдёт при следующей
  /// синхронизации.
  void _bulkInBackground(
    Future<void> Function(AccountModel account, EmailModel email) op, {
    bool hide = false,
    VoidCallback? done,
    List<EmailModel>? emails,
  }) {
    final list = emails ?? _selectedEmails();
    final notifier = ref.read(emailsProvider.notifier);
    final accounts = {for (final a in ref.read(accountsProvider)) a.id: a};
    if (hide) {
      for (final e in list) {
        notifier.hideLocally(e);
      }
    }
    _exitSelection();
    unawaited(() async {
      for (final e in list) {
        final a = accounts[e.accountId];
        if (a == null) continue;
        try {
          await op(a, e);
        } catch (err) {
          AppLogger.warning('Массовое действие: $err');
        }
      }
      if (hide) {
        for (final e in list) {
          notifier.unhideLocally(e);
        }
      }
      done?.call();
    }());
  }

  Future<void> _bulkSetRead(bool read) async {
    final actions = ref.read(emailActionsProvider);
    final notifier = ref.read(emailsProvider.notifier);
    final list = _selectedEmails();
    for (final e in list) {
      notifier.applyLocalFlags(e.id, isRead: read);
    }
    _exitSelection();
    final accounts = {for (final a in ref.read(accountsProvider)) a.id: a};
    unawaited(() async {
      for (final e in list) {
        final a = accounts[e.accountId];
        if (a == null) continue;
        try {
          await actions.setRead(a, e.id, e.folderId, read);
        } catch (err) {
          AppLogger.warning('Массовое «прочитано»: $err');
        }
      }
    }());
  }

  Future<void> _bulkSetFlag(bool flag) async {
    final actions = ref.read(emailActionsProvider);
    final notifier = ref.read(emailsProvider.notifier);
    for (final e in _selectedEmails()) {
      notifier.applyLocalFlags(e.id, isFlagged: flag);
    }
    _bulkInBackground((a, e) => actions.setFlag(a, e.id, e.folderId, flag));
  }

  Future<void> _bulkDelete() async {
    final actions = ref.read(emailActionsProvider);
    final l10n = AppLocalizations.of(context);
    final selected = _selectedEmails();
    String key(EmailModel e) => '${e.accountId}/${e.id}';
    final picked = {for (final e in selected) key(e)};
    var list = selected;
    // Среди выбранных строк есть беседы из нескольких писем (группировка по
    // беседам) — спросить, удалить беседы целиком или только выбранные
    // письма (1.6.26).
    final convs = selected.where((e) => _conversationSize(e) > 1).toList();
    if (convs.isNotEmpty) {
      final total = selected.length - convs.length + convs.fold<int>(0, (s, e) => s + _conversationSize(e));
      final whole = await _askDeleteScope(l10n, total, bulk: true);
      if (whole == null || !mounted) return;
      if (whole) {
        final seen = <String>{};
        list = [];
        for (final e in selected) {
          for (final x in _conversationSize(e) > 1 ? await _conversationEmails(e) : [e]) {
            if (seen.add(key(x))) list.add(x);
          }
        }
        if (!mounted) return;
      }
    }
    _bulkInBackground(hide: true, emails: list, (a, e) async {
      final trashId = await _folderOfType(a.id, FolderType.trash);
      if (trashId != null && trashId != e.folderId) {
        await actions.moveTo(a, e.id, e.folderId, trashId);
      } else if (trashId != null && picked.contains(key(e))) {
        // Выбранное письмо уже в «Удалённых» — окончательное удаление.
        // Письма беседы, которые лежат там же, но не выбраны, не трогаем.
        await actions.delete(a, e.id, e.folderId);
      }
      // Папка «Удалённые» не найдена — ничего не удаляем безвозвратно.
    });
  }

  Future<void> _bulkMove(AppLocalizations l10n) async {
    final target = await _pickTargetFolder(l10n);
    if (target == null || !mounted) return;
    final actions = ref.read(emailActionsProvider);
    var skipped = 0;
    _bulkInBackground(hide: true, (a, e) async {
      String? to;
      if (target.type != FolderType.custom) {
        to = await _folderOfType(a.id, target.type);
      } else if (target.accountId == a.id) {
        to = target.id;
      }
      if (to == null || to == e.folderId) {
        skipped++;
        return;
      }
      await actions.moveTo(a, e.id, e.folderId, to);
    }, done: () {
      if (skipped > 0) showInlineError(l10n.tr('bulkMoveSkipped').replaceAll('{n}', '$skipped'));
    });
  }

  /// Выбор папки назначения. Системные папки — по типу (у каждого письма в
  /// своём аккаунте), пользовательские — с подписью ящика, если их несколько.
  Future<FolderModel?> _pickTargetFolder(AppLocalizations l10n) async {
    final folders = ref.read(foldersProvider).value ?? const <FolderModel>[];
    final selected = _selectedEmails();
    final accountIds = selected.map((e) => e.accountId).toSet();
    final multi = ref.read(accountsProvider).length > 1;
    final emailOf = {for (final a in ref.read(accountsProvider)) a.id: a.email};
    FolderModel sys(FolderType t, String name) => FolderModel(
        id: t.name, accountId: '', displayName: name, type: t);
    final options = <FolderModel>[
      sys(FolderType.inbox, l10n.inbox),
      sys(FolderType.archive, l10n.tr('archive')),
      sys(FolderType.junk, l10n.tr('junk')),
      sys(FolderType.trash, l10n.tr('trash')),
      for (final f in folders)
        if (f.type == FolderType.custom && accountIds.contains(f.accountId)) f,
    ];

    // Карточкой (1.8.8), как меню «⋮».
    final i = await showChoiceSheet<int>(
      context,
      title: l10n.tr('moveToDots'),
      entries: [
        for (final (i, o) in options.indexed)
          AppMenuEntry(
            value: i,
            label: o.displayName,
            icon: folderIconOf(o),
            subtitle: (multi && o.type == FolderType.custom) ? (emailOf[o.accountId] ?? '') : null,
          ),
      ],
    );
    return i == null ? null : options[i];
  }


  PreferredSizeWidget _buildSelectionAppBar(AppLocalizations l10n, ThemeData theme) {
    return AppBar(
      leading: IconButton(tooltip: l10n.tr('deselectAll'), icon: const Icon(AppIcons.close), onPressed: _exitSelection),
      title: Text('${_selectedIds.length}'),
      actions: [
        // Действия перенесены ВНИЗ экрана (см. _selectionBottomBar): на
        // современных телефонах до верхней панели не дотянуться одной рукой,
        // а массовые операции делают именно на ходу.
        AppMenuButton<String>(
          onSelected: (v) {
            if (v == 'all') _selectAllLoaded();
            if (v == 'control') _bulkControl();
            if (v == 'later') unawaited(_bulkLater());
            if (v == 'ogna') unawaited(_bulkOgna());
          },
          itemBuilder: (_) => [
            AppMenuEntry(value: 'all', icon: AppIcons.select_all, label: l10n.tr('selectAll')),
            AppMenuEntry(value: 'later', icon: AppIcons.watch_later, label: l10n.tr('later')),
            if (ref.read(settingsProvider).mailControl)
              AppMenuEntry(value: 'control', icon: AppIcons.task_alt, label: l10n.tr('controlSet')),
            // Выбранные письма — в архив Ogneliss (1.7.3); архива нет —
            // сначала создать (29.10.2026: пункт был скрыт до создания).
            AppMenuEntry(value: 'ogna', icon: AppIcons.inventory_2, label: l10n.tr('toOgnaArchive')),
          ],
        ),
      ],
    );
  }

  /// Открыть письмо из ленты: черновик — в редактор, широкое окно — в панель
  /// рядом, свёрнутая беседа — экран беседы, иначе — экран письма. Касание
  /// строки и касание карточки по удержанию (1.6.46).
  /// Закреплённые письма этой ленты: папка ящика или общая лента «Входящих».
  List<EmailModel> _pinnedHere() {
    final all = ref.watch(pinnedEmailsProvider).value ?? const <(PinRef, EmailModel)>[];
    if (all.isEmpty) return const [];
    final group = ref.read(activeGroupAccountIdsProvider);
    final accounts = ref.read(accountsProvider);
    final active = ref.read(activeAccountProvider);
    final folderId = ref.read(selectedFolderIdProvider);
    final unifiedAcross = group.isNotEmpty || ref.read(allAccountsModeProvider);
    final unified = unifiedAcross || ref.read(unifiedModeProvider) || folderId == null;
    final ids = group.isNotEmpty
        ? {for (final a in accounts) if (a.isActive && group.contains(a.id)) a.id}
        : unifiedAcross
            ? {for (final a in accounts) if (a.isActive) a.id}
            : {if (active != null) active.id};
    return [
      for (final (p, e) in all)
        if (p.shownIn(folderId: unified ? null : folderId, accountId: active?.id, accountIds: ids)) e,
    ];
  }

  /// Закрепить вверху / открепить (1.6.49).
  Future<void> _togglePin(EmailModel email) async {
    final inboxId = await ref.read(databaseProvider).folderIdOfType(email.accountId, FolderType.inbox.index);
    await ref.read(pinnedMailProvider.notifier).toggle(email, inbox: inboxId == email.folderId);
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _openEmail(BuildContext context, EmailModel item, bool grouped) async {
    // Черновик открывается на редактирование, а не на чтение:
    // иначе его нельзя было ни дописать, ни отправить.
    if (await _isDraft(item)) {
      if (!context.mounted) return;
      unawaited(context.push('/compose?draftId=${Uri.encodeQueryComponent(item.id)}'
          '&accountId=${Uri.encodeQueryComponent(item.accountId)}'));
      return;
    }
    if (!context.mounted) return;
    if (AdaptiveLayout.isSplit(context)) {
      // Лента и письмо рядом (широкое окно, планшет, раскрытый
      // складной): письмо — во встроенной панели
      setState(() {
        _selectedEmailId = item.id;
        _selectedAccountId = item.accountId;
      });
    } else if (_isCollapsedConversation(item, grouped)) {
      // Беседа из нескольких писем: сначала экран беседы, письмо
      // выбирается уже в нём (как в OfficeMail).
      unawaited(context.push(conversationPath(item.conversationId!, accountId: item.accountId)));
    } else {
      // Телефон: переход на отдельный экран. Встроенные картинки
      // письма начинают загружаться ещё до перехода.
      OpenTrace.start();
      ref.read(mailOpenCacheProvider).prefetch(item.accountId, item.id, images: true);
      // Письмо — в запасное окно браузера, пока идёт переход
      // (1.5.9): экран письма заберёт его уже загруженным. Если
      // палец уже задержался на строке — началось раньше
      // (_pressStart), повтор того же документа ничего не делает.
      _preloadOpen(context, item);
      // Соседние письма ленты — свайпом влево-вправо (1.6.49+95).
      final pager = ref.read(mailSwipePagerProvider) ? _pagerArgs(item) : null;
      if (pager != null) {
        unawaited(context.push(mailPagerPath(item.id, accountId: item.accountId), extra: pager));
      } else {
        unawaited(context.push(
          mailDetailPath(item.id, accountId: item.accountId),
        ));
      }
    }
  }

  /// Письма ленты по порядку (без черновиков) — для листания свайпом.
  /// null — листать нечего.
  MailPagerArgs? _pagerArgs(EmailModel item) {
    final items = <(String, String)>[];
    final seen = <String>{};
    var index = -1;
    for (final g in _cachedGrouped ?? const <dynamic>[]) {
      if (g is! EmailModel || g.isDraft || g.folderId == 'drafts') continue;
      if (!seen.add('${g.accountId}|${g.id}')) continue;
      if (g.id == item.id && g.accountId == item.accountId) index = items.length;
      items.add((g.accountId, g.id));
    }
    if (index < 0 || items.length < 2) return null;
    return MailPagerArgs(items, index);
  }

  /// Карточка письма по удержанию: строка «приподнимается», под ней —
  /// Ответить всем (или «Ответить», если отвечать больше некому), Переслать,
  /// Прочитано, На контроль (или флаг), Ещё…; касание карточки — открыть.
  /// Приглашение на встречу (1.6.47) — «Принять», «Под вопросом»,
  /// «Отклонить», ответ, «Ещё»; файлы письма — плашками в карточке.
  void _showPeek(BuildContext rowCtx, EmailModel email, AppLocalizations l10n) {
    // Место строки на экране — по её собственному context; не RenderBox (или
    // строка уже ушла с экрана) — карточка по центру, а не ошибка.
    final anchor = peekAnchorOf(rowCtx);
    final settings = ref.read(settingsProvider);
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final invite = peekCanRespondInvite(account, email);
    final convCount = settings.groupByConversation && email.conversationId != null
        ? (ref.read(conversationCountProvider)[conversationKey(email.accountId, email.conversationId!)] ?? 1)
        : 1;
    final q = 'replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}';
    final own = {for (final a in ref.read(accountsProvider)) ...OwnAddresses.of(a)};
    final all = peekWantsReplyAll(email, own);
    final grouped = settings.groupByConversation;
    unawaited(showMailPeek(
      context,
      email: email,
      anchor: anchor,
      conversationCount: convCount,
      previewLines: settings.peekPreviewLines,
      onOpen: _selectionMode ? null : () => unawaited(_openEmail(context, email, grouped)),
      fetchFile: (a) => peekFetchFile(ref, account, email, a, l10n),
      openFile: (a, path) => peekOpenFile(context, email, a, path),
      actions: [
        if (invite && account != null) ...peekInviteActions(context, ref, account, email, l10n),
        PeekAction(
          icon: all ? AppIcons.reply_all : AppIcons.reply,
          label: l10n.tr(all ? 'replyAll' : 'reply'),
          onTap: () => context.push(all ? '/compose?$q&replyAll=true' : '/compose?$q'),
        ),
        if (!invite) ...[
        PeekAction(
          icon: AppIcons.forward,
          label: l10n.tr('forward'),
          onTap: () => _forward(email, l10n),
        ),
        PeekAction(
          icon: _rowUnread(email) ? AppIcons.mark_email_read : AppIcons.mark_email_unread,
          label: _rowUnread(email) ? l10n.tr('peekRead') : l10n.tr('peekUnread'),
          onTap: () => _toggleRead(email),
        ),
        if (settings.mailControl)
          PeekAction(
            icon: AppIcons.task_alt,
            filled: _rowControl(email) != 0,
            // На контроле — кнопка снимает (раньше подпись не менялась).
            label: l10n.tr(_rowControl(email) == 0 ? 'peekControl' : 'peekControlOff'),
            onTap: () => _toggleControl(email),
          )
        else
          PeekAction(
            icon: AppIcons.flag,
            filled: email.isFlagged,
            label: l10n.tr('flag'),
            onTap: () => _toggleFlag(email),
          ),
        ],
      ],
      // «Ещё» — все действия по группам здесь же (1.6.49+95), вместо шторки.
      moreLabel: l10n.tr('peekMore'),
      more: _moreGroups(email, l10n),
    ));
  }

  /// Все действия с письмом по группам — для развёрнутого «Ещё» карточки.
  List<PeekGroup> _moreGroups(EmailModel email, AppLocalizations l10n) {
    final q = 'replyToId=${Uri.encodeQueryComponent(email.id)}&accountId=${Uri.encodeQueryComponent(email.accountId)}';
    final control = ref.read(settingsProvider).mailControl;
    final pinned = ref.read(pinnedMailProvider.notifier).isPinned(email.accountId, email.id);
    final muted = ref.read(mutedConversationsProvider.notifier).isMuted(email.accountId, email.conversationId);
    return [
      PeekGroup(title: l10n.tr('peekGroupReply'), items: [
        PeekAction(icon: AppIcons.reply, label: l10n.tr('reply'), onTap: () => context.push('/compose?$q')),
        PeekAction(
            icon: AppIcons.reply_all, label: l10n.tr('replyAll'), onTap: () => context.push('/compose?$q&replyAll=true')),
        PeekAction(icon: AppIcons.forward, label: l10n.tr('forward'), onTap: () => _forward(email, l10n)),
      ]),
      PeekGroup(title: l10n.tr('peekGroupMark'), items: [
        PeekAction(
          icon: _rowUnread(email) ? AppIcons.mark_email_read : AppIcons.mark_email_unread,
          label: _rowUnread(email) ? l10n.tr('markRead') : l10n.tr('markUnread'),
          onTap: () => _toggleRead(email),
        ),
        PeekAction(icon: AppIcons.flag, filled: email.isFlagged, label: l10n.tr('flag'), onTap: () => _toggleFlag(email)),
        if (control)
          PeekAction(
            icon: AppIcons.task_alt,
            filled: _rowControl(email) != 0,
            label: l10n.tr(_rowControl(email) == 0 ? 'controlSet' : 'controlClear'),
            onTap: () => _toggleControl(email),
          ),
        PeekAction(
          icon: AppIcons.watch_later,
          filled: email.laterState != 0,
          label: l10n.tr('later'),
          onTap: () => unawaited(_snoozeSingle(email, l10n)),
        ),
        PeekAction(icon: AppIcons.label, label: l10n.tr('addTag'), onTap: () => _showTagPicker(email, l10n)),
        PeekAction(
          icon: AppIcons.push_pin,
          filled: pinned,
          label: l10n.tr(pinned ? 'unpinMail' : 'pinMail'),
          onTap: () => unawaited(_togglePin(email)),
        ),
        // Беседа без уведомлений (1.8.13, как «Без звука» у чата в Telegram).
        if ((email.conversationId ?? '').isNotEmpty)
          PeekAction(
            icon: muted ? AppIcons.notifications_active : AppIcons.notifications_off,
            label: l10n.tr(muted ? 'convUnmute' : 'convMute'),
            onTap: () => unawaited(() async {
              final now = await ref.read(mutedConversationsProvider.notifier).toggle(email.accountId, email.conversationId!);
              showInlineNotice(l10n.tr(now ? 'convMutedNotice' : 'convUnmutedNotice'));
            }()),
          ),
      ]),
      PeekGroup(title: l10n.tr('peekGroupCreate'), items: [
        PeekAction(icon: AppIcons.calendar_today, label: l10n.tr('createEvent'), onTap: () => _planMeeting(email)),
        PeekAction(
            icon: AppIcons.check_box, label: l10n.tr('createTask'), onTap: () => unawaited(_createTaskFromEmail(email, l10n))),
      ]),
      PeekGroup(title: l10n.tr('peekGroupMove'), items: [
        if (!_selectionMode)
          PeekAction(
            icon: AppIcons.checklist,
            label: l10n.tr('selectEmails'),
            onTap: () => setState(() {
              _selectionMode = true;
              _selectedIds.add(email.id);
            }),
          ),
        PeekAction(icon: AppIcons.drive_file_move, label: l10n.tr('moveTo'), onTap: () => unawaited(_moveSingle(email, l10n))),
        PeekAction(icon: AppIcons.archive, label: l10n.tr('archive'), onTap: () => _archiveEmail(email, l10n)),
        // В архив Ogneliss на устройстве (29.10.2026: в карточке не было).
        PeekAction(
            icon: AppIcons.inventory_2,
            label: l10n.tr('toOgnaArchive'),
            onTap: () => unawaited(_bulkOgna(emails: [email]))),
        // «В спам» (1.7.2+106: в карточке не было); в папке спама — «Не спам».
        if (_inJunk(email))
          PeekAction(icon: AppIcons.inbox, label: l10n.tr('notSpam'), onTap: () => unawaited(_notJunk(email, l10n)))
        else
          PeekAction(icon: AppIcons.report, label: l10n.tr('moveToJunk'), onTap: () => unawaited(_moveToJunk(email, l10n))),
        PeekAction(
          icon: AppIcons.delete,
          label: l10n.delete,
          color: AppColors.errorText(context),
          onTap: () => unawaited(_deleteEmail(email, l10n)),
        ),
      ]),
    ];
  }

  // ════════════════════════ ДЕЙСТВИЯ ════════════════════════

  void _toggleRead(EmailModel email) {
    // Без вибрации (1.6.22): «прочитано» и флаг чаще всего ставят свайпом,
    // серией подряд — вибрация на каждое письмо утомляла.
    // Берём аккаунт письма (в unified/all-accounts активный аккаунт может быть другим).
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull
        ?? ref.read(activeAccountProvider);
    if (account == null) return;
    // Строка беседы с непрочитанными внутри — «Прочитано» для всей беседы
    // (1.7.2): раньше отмечалось только верхнее письмо, строка оставалась
    // жирной, а карточка предлагала «Непрочитано».
    final newRead = _rowUnread(email);
    // Мгновенно отражаем в UI, затем пишем в БД/сервер.
    ref.read(emailsProvider.notifier).applyLocalFlags(email.id, isRead: newRead);
    if (email.isRead != newRead) ref.read(emailActionsProvider).setRead(account, email.id, email.folderId, newRead);
    if (newRead && _rowIsConversation(email)) {
      unawaited(() async {
        final rest = await ref.read(databaseProvider).conversationMembers(email.accountId, email.conversationId!, unread: true);
        for (final m in rest) {
          if (m.id == email.id) continue;
          ref.read(emailsProvider.notifier).applyLocalFlags(m.id, isRead: true);
          unawaited(ref.read(emailActionsProvider).setRead(account, m.id, m.folderId, true));
        }
        ref.read(emailsProvider.notifier).invalidateConversationSizes();
      }());
    }
  }

  void _toggleFlag(EmailModel email) {
    // Без вибрации (1.6.22): «прочитано» и флаг чаще всего ставят свайпом,
    // серией подряд — вибрация на каждое письмо утомляла.
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull
        ?? ref.read(activeAccountProvider);
    if (account == null) return;
    final newFlag = !email.isFlagged;
    ref.read(emailsProvider.notifier).applyLocalFlags(email.id, isFlagged: newFlag);
    ref.read(emailActionsProvider).setFlag(account, email.id, email.folderId, newFlag);
  }

  /// Папка нужного типа В АККАУНТЕ ПИСЬМА. Раньше подставлялись строки
  /// 'archive'/'trash' и активный аккаунт: у IMAP папка называется
  /// «Archive»/«Архив», у EWS это id вида «AAMk…», а в сводной ленте письмо
  /// могло быть из другого ящика — перенос уходил не туда или не выполнялся.
  /// Строка — свёрнутая беседа из 2+ писем (в поиске беседы не сворачиваются).
  bool _isCollapsedConversation(EmailModel item, bool grouping) {
    if (!grouping || _isSearching) return false;
    final conv = item.conversationId;
    if (conv == null || conv.isEmpty) return false;
    return ref.read(conversationCountProvider.notifier).getCount(item.accountId, conv) > 1;
  }

  /// Запасное окно браузера для следующего письма (1.5.9, этап 2) — вместо
  /// прежнего прогрева движка: окно создаётся один раз и держится наготове.
  void _warmSpare() {
    if (!mounted) return;
    MailWebViewPool.enabled =
        ref.read(sharedPrefsProvider).getBool(ExperimentalKeys.webViewSpare) ?? true;
    unawaited(MailHtmlView.warmUp(
        width: MailHtmlView.bodyWidthOf(context), textScale: ref.read(settingsProvider).fontScale));
  }

  // ── Свежие письма — заранее (1.5.9) ──
  // Через 1,5 с после того, как лента успокоилась, тела первых непрочитанных
  // писем готовятся в простое (планировщик, приоритет prefetch: уступает
  // открытому письму и синхронизации). К нажатию очистка, цитата и документ
  // уже готовы.
  Timer? _warmTimer;
  List<EmailModel>? _warmFor;
  final Set<String> _warmed = <String>{};
  static const _warmCount = 6;

  void _scheduleWarmFresh(List<EmailModel> emails) {
    if (identical(emails, _warmFor)) return;
    _warmFor = emails;
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 1500), _warmFresh);
  }

  void _warmFresh() {
    if (!mounted) return;
    final scrolling = _scrollController.hasClients &&
        _scrollController.positions.any((p) => p.isScrollingNotifier.value);
    if (scrolling) {
      _warmTimer = Timer(const Duration(seconds: 1), _warmFresh);
      return;
    }
    final list = _warmFor ?? const <EmailModel>[];
    final todo = list
        .where((e) => !e.isRead && !e.isDraft && !_warmed.contains('${e.accountId}|${e.id}'))
        .take(_warmCount)
        .toList();
    if (todo.isEmpty) return;
    final cache = ref.read(mailOpenCacheProvider);
    unawaited(() async {
      for (final e in todo) {
        if (!mounted) return;
        _warmed.add('${e.accountId}|${e.id}');
        if (_warmed.length > 300) _warmed.remove(_warmed.first);
        await WorkScheduler.instance.run(WorkPriority.prefetch, () => cache.warm(e.accountId, e.id));
      }
    }());
  }

  // ── Нажатие — подготовка с касания (1.5.10) ──
  // Нажатие (onTap) приходит, когда палец поднят, — через 60–150 мс после
  // касания. Эти миллисекунды окно браузера заранее (MailWebViewPool) раньше
  // простаивало, а письмо должно успеть загрузиться в него к 70 % перехода.
  // Теперь подготовка тела и загрузка в окно начинаются, когда палец
  // задержался на строке [_pressDelay] без сдвига: так начинается нажатие,
  // а не прокрутка (прокрутка сдвигает палец дальше kTouchSlop раньше).
  // Долгое нажатие (меню) тоже начнёт подготовку — она дешёвая и пригодится,
  // если письмо всё же откроют.
  static const _pressDelay = Duration(milliseconds: 45);
  Timer? _pressTimer;
  Offset? _pressAt;

  void _pressStart(BuildContext context, EmailModel item, Offset at, bool grouped) {
    _pressCancel();
    // Планшет — письмо в панели рядом, беседа — свой экран, черновик —
    // редактор: окно заранее не нужно.
    if (item.isDraft || AdaptiveLayout.isSplit(context) || _isCollapsedConversation(item, grouped)) return;
    _pressAt = at;
    _pressTimer = Timer(_pressDelay, () {
      _pressTimer = null;
      if (!mounted || !context.mounted || _pressAt == null) return;
      ref.read(mailOpenCacheProvider).prefetch(item.accountId, item.id);
      _preloadOpen(context, item);
    });
  }

  void _pressCancel() {
    _pressTimer?.cancel();
    _pressTimer = null;
    _pressAt = null;
  }

  /// Письмо — в запасное окно браузера (простое письмо окну не нужно —
  /// preloadWebView это проверяет сам).
  void _preloadOpen(BuildContext context, EmailModel item) {
    final th = Theme.of(context);
    ref.read(mailOpenCacheProvider).preloadWebView(item.accountId, item.id,
        // Тело письма — с полями 16 dp (экран письма).
        width: MailHtmlView.bodyWidthOf(context),
        dark: th.brightness == Brightness.dark,
        pageColor: mailPageColor(th),
        textScale: ref.read(settingsProvider).fontScale);
  }

  /// Черновик: свой (локальный, папка «drafts») или из серверных «Черновиков».
  Future<bool> _isDraft(EmailModel item) async {
    if (item.isDraft || item.folderId == 'drafts') return true;
    // Тип папки — из папок ящика в памяти (поток папок уже есть): раньше
    // каждое нажатие на письмо ждало запроса в базу, а во время
    // синхронизации изолят базы занят записью — переход начинался позже
    // (1.5.9). База — только если папки ещё не загружены.
    final folders = ref.read(accountFoldersProvider(item.accountId)).value;
    if (folders != null) {
      for (final f in folders) {
        if (f.id == item.folderId) return f.type == FolderType.drafts;
      }
    }
    final drafts = await _folderOfType(item.accountId, FolderType.drafts);
    return drafts != null && drafts == item.folderId;
  }

  /// Папка типа [type] ящика. «Архив» и «Спам» — с распознаванием по
  /// названию, если список папок пришёл до 1.7.2+106 ([SpecialFolders]).
  Future<String?> _folderOfType(String accountId, FolderType type) {
    final db = ref.read(databaseProvider);
    return switch (type) {
      FolderType.archive => SpecialFolders.resolve(db, ref.read(sharedPrefsProvider), accountId, SpecialKind.archive),
      FolderType.junk => SpecialFolders.resolve(db, ref.read(sharedPrefsProvider), accountId, SpecialKind.junk),
      _ => db.folderIdOfType(accountId, type.index),
    };
  }

  /// Перенести письмо в папку типа [type] с «Отменить»: письмо сразу
  /// исчезает из списка, перенос выполняется через 7 секунд.
  Future<void> _moveWithUndo(EmailModel email, FolderType type, String doneText,
      String notFoundText) async {
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final targetId = await _folderOfType(email.accountId, type);
    if (account == null) return;
    // Папки нет — строкой вверху экрана с подсказкой, где её выбрать
    // (1.7.2+106: раньше — скрытой плашкой, и «В архив» будто не работала).
    if (targetId == null) {
      showInlineError(notFoundText);
      return;
    }
    if (targetId == email.folderId) return; // уже там
    if (!mounted) return;
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    notifier.hideLocally(email);
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: doneText,
        execute: () => actions.moveTo(account, email.id, email.folderId, targetId),
        undo: () async {},
        onUndo: () => notifier.unhideLocally(email),
        onSettled: () => notifier.unhideLocally(email),
      ),
    );
  }

  void _archiveEmail(EmailModel email, AppLocalizations l10n) {
    _moveWithUndo(email, FolderType.archive, l10n.tr('emailMoved'), l10n.tr('archiveFolderNotFound'));
  }

  Future<void> _deleteEmail(EmailModel email, AppLocalizations l10n, {bool? whole}) async {
    final trashId = await _folderOfType(email.accountId, FolderType.trash);
    // Уже в «Удалённых» — удаляем окончательно, но только после подтверждения.
    if (trashId != null && email.folderId == trashId) {
      if (!mounted) return;
      final ok = await confirmDestructive(context,
          title: l10n.tr('deleteForeverTitle'),
          message: l10n.tr((ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull?.isMsExchange ?? false)
              ? 'deleteForeverBodyExchange'
              : 'deleteForeverBody'));
      if (!ok) return;
      final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
      if (account == null) return;
      await ref.read(emailActionsProvider).delete(account, email.id, email.folderId, hard: true);
      return;
    }
    if (!mounted) return;
    // Строка ленты — беседа из нескольких писем (группировка по беседам):
    // спросить, удалить всю беседу или только это письмо (1.6.26, решение
    // владельца). Остальные действия по-прежнему — только над этим письмом.
    final n = _conversationSize(email);
    if (n > 1) {
      whole ??= await _askDeleteScope(l10n, n);
      if (whole == null || !mounted) return;
      if (whole) {
        await _deleteConversation(email, l10n);
        return;
      }
    }
    await _moveWithUndo(email, FolderType.trash, l10n.tr('emailDeleted'), l10n.tr('trashFolderNotFound'));
  }

  /// Сколько писем в беседе этой строки (1 — без группировки или одно письмо).
  int _conversationSize(EmailModel e) {
    if (!ref.read(settingsProvider).groupByConversation || e.conversationId == null) return 1;
    return ref.read(conversationCountProvider)[conversationKey(e.accountId, e.conversationId!)] ?? 1;
  }

  /// Выбор при удалении беседы: true — всю, false — только письмо(а),
  /// null — отмена.
  Future<bool?> _askDeleteScope(AppLocalizations l10n, int n, {bool bulk = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('convDeleteAskTitle')),
        content: Text(l10n.tr(bulk ? 'convDeleteAskBodyBulk' : 'convDeleteAskBody').replaceAll('{n}', '$n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr(bulk ? 'convDeleteOnlySelected' : 'convDeleteOnlyThis')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr(bulk ? 'convDeleteWholeBulk' : 'convDeleteWhole').replaceAll('{n}', '$n')),
          ),
        ],
      ),
    );
  }

  /// Письма беседы строки из базы (все папки ящика), без писем в очереди
  /// отправки.
  Future<List<EmailModel>> _conversationEmails(EmailModel e) async {
    final conv = e.conversationId;
    if (conv == null) return [e];
    final rows = await ref
        .read(databaseProvider)
        .watchConversationLight(conversationId: conv, accountId: e.accountId)
        .first;
    final list = [for (final r in rows) if (r.folderId != 'outbox') emailModelFromRow(r)];
    return list.isEmpty ? [e] : list;
  }

  /// Вся беседа — в «Удалённые», с отменой. Письма, которые уже в
  /// «Удалённых», не трогаются (окончательное удаление — только явно).
  Future<void> _deleteConversation(EmailModel email, AppLocalizations l10n) async {
    final account = ref.read(accountsProvider).where((a) => a.id == email.accountId).firstOrNull;
    final trashId = await _folderOfType(email.accountId, FolderType.trash);
    if (account == null || trashId == null) {
      showInlineError(l10n.tr('trashFolderNotFound'));
      return;
    }
    final all = await _conversationEmails(email);
    final toMove = all.where((e) => e.folderId != trashId).toList();
    if (toMove.isEmpty || !mounted) return;
    final byFolder = <String, List<String>>{};
    for (final e in toMove) {
      (byFolder[e.folderId] ??= []).add(e.id);
    }
    final notifier = ref.read(emailsProvider.notifier);
    final actions = ref.read(emailActionsProvider);
    for (final e in toMove) {
      notifier.hideLocally(e);
    }
    void unhide() {
      for (final e in toMove) {
        notifier.unhideLocally(e);
      }
    }
    EmailUndoManager.perform(
      context,
      UndoableAction(
        description: l10n.tr('convDeleted'),
        execute: () async {
          for (final entry in byFolder.entries) {
            await actions.batchMove(account, entry.value, entry.key, trashId);
          }
        },
        undo: () async {},
        onUndo: unhide,
        onSettled: unhide,
      ),
    );
  }

  /// Метки письма (1.8.8): карточкой, как меню «⋮»; нажатие ставит или
  /// снимает метку. Раньше шторка показывала метки, но нажатие ничего не
  /// меняло.
  Future<void> _showTagPicker(EmailModel email, AppLocalizations l10n) async {
    final tags = ref.read(categoriesProvider);
    if (tags.isEmpty) {
      showInlineNotice(l10n.tr('noTags'));
      return;
    }
    final t = await showChoiceSheet<String>(
      context,
      title: l10n.tr('addTag'),
      entries: [
        for (final tag in tags)
          AppMenuEntry(
            value: tag,
            label: tag,
            icon: AppIcons.label,
            iconColor: AppTheme.getTagColor(tag),
            checked: email.tags.contains(tag),
          ),
      ],
    );
    if (t == null || !mounted) return;
    final next = email.tags.contains(t) ? [for (final x in email.tags) if (x != t) x] : [...email.tags, t];
    unawaited(HapticFeedback.selectionClick());
    await ref.read(emailActionsProvider).setTags(email.id, next, accountId: email.accountId);
    await ref.read(emailsProvider.notifier).refresh();
  }

  void _showFilterSheet(BuildContext context, AppLocalizations l10n) {
    showAppSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      // Высота — по содержимому (до 90 % экрана), дальше прокрутка. Раньше
      // шторка была не выше 9/16 экрана, и ряд тегов уходил под её край
      // (09.10.2026: «фильтры за шторкой»).
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(l10n.tr('filterBy'), style: Theme.of(context).textTheme.titleMedium),
            ),
            Consumer(builder: (context, ref, _) {
              final current = ref.watch(mailFilterProvider);
              Widget tile(IconData icon, String label, MailFilter f) => ListTile(
                    leading: Icon(icon),
                    title: Text(label),
                    trailing: current == f
                        ? Icon(AppIcons.check, color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      ref.read(mailFilterProvider.notifier).state = f;
                      Navigator.of(ctx).pop();
                    },
                  );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tile(AppIcons.inbox, l10n.tr('allMail'), MailFilter.none),
                  tile(AppIcons.mark_email_unread, l10n.tr('unread'), MailFilter.unread),
                  // «Мне лично» — что требует ответа, в отличие от копий
                  // для сведения. Дополняет пункт «прочитано, где я в копии».
                  tile(AppIcons.person, l10n.tr('filterToMe'), MailFilter.toMe),
                  tile(AppIcons.today, l10n.tr('today'), MailFilter.today),
                  tile(AppIcons.flag, l10n.tr('flagged'), MailFilter.flagged),
                  // Как в меню почты: письма в работе.
                  if (ref.watch(settingsProvider).mailControl)
                    tile(AppIcons.task_alt, l10n.tr('controlFilter'), MailFilter.control),
                  tile(AppIcons.watch_later, l10n.tr('laterFilter'), MailFilter.later),
                  tile(AppIcons.star, 'VIP', MailFilter.vip),
                  tile(AppIcons.attach_file, l10n.tr('withAttachments'), MailFilter.attachments),
                ],
              );
            }),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
              child: Text(l10n.tr('byTag'), style: Theme.of(context).textTheme.titleSmall),
            ),
            SizedBox(
              height: 32 + 16 * context.textScale.clamp(1.0, TextScaleLimits.app),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l),
                children: ref.watch(categoriesProvider).map((tag) {
                  return Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: Consumer(builder: (context, ref, _) {
                      final selected = ref.watch(tagFilterProvider) == tag;
                      return FilterChip(
                        label: Text(tag, style: Theme.of(context).textTheme.labelMedium),
                        selected: selected,
                        onSelected: (_) {
                          ref.read(tagFilterProvider.notifier).state = selected ? null : tag;
                          Navigator.of(ctx).pop();
                        },
                        backgroundColor: AppTheme.getTagColor(tag).withValues(alpha: 0.1),
                      );
                    }),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: Space.l),
          ],
         ),
        ),
      ),
    );
  }

  void _handleMenuAction(String action, AppLocalizations l10n) {
    switch (action) {
      case 'recover_deleted':
        final acc = ref.read(activeAccountProvider);
        unawaited(context.push(Uri(path: '/settings/recover-deleted',
            queryParameters: {if (acc != null) 'accountId': acc.id}).toString()));
        break;
      case 'refresh':
        ref.read(emailsProvider.notifier).refresh();
        break;
      case 'mail_check':
        unawaited(showMailCheckSheet(context));
        break;
      case 'mark_all_read':
        _markAllRead();
        break;
      case 'read_where_cc':
        _markReadWhereCc(l10n);
        break;
      case 'empty_trash':
        _emptyTrash();
        break;
      case 'sort':
        _showSortSheet(l10n);
        break;
      case 'select_all':
        setState(() => _selectionMode = true);
        _selectAllLoaded();
        break;
    }
  }

  /// Выбор сортировки списка писем.
  void _showSortSheet(AppLocalizations l10n) {
    final current = ref.read(mailSortProvider);
    final options = <MailSort, String>{
      MailSort.dateNewest: l10n.tr('sortNewest'),
      MailSort.dateOldest: l10n.tr('sortOldest'),
      MailSort.senderAZ: l10n.tr('sortBySender'),
      MailSort.subjectAZ: l10n.tr('sortBySubject'),
      MailSort.sizeLargest: l10n.tr('sortLargest'),
      MailSort.sizeSmallest: l10n.tr('sortSmallest'),
    };
    // Карточкой (1.8.8), как меню «⋮»; текущая — с галочкой.
    unawaited(showChoiceSheet<MailSort>(
      context,
      title: l10n.tr('sortBy'),
      selected: current,
      entries: [for (final e in options.entries) AppMenuEntry(value: e.key, label: e.value)],
    ).then((v) {
      if (v != null) ref.read(mailSortProvider.notifier).state = v;
    }));
  }

  Future<void> _markAllRead() async {
    final unread = ref.read(emailsProvider).emails.where((e) => !e.isRead).toList();
    if (unread.isEmpty) return;
    await _setReadEach(unread);
  }

  /// «Прочитано» — каждому письму в его ящике и папке (1.8.13). Раньше —
  /// ящику, выбранному в ленте, и папке первого письма: во «Всей почте» и в
  /// группе ящиков IMAP отмечал прочитанным письмо с тем же номером в чужой
  /// папке, а письма других ящиков не отмечались вовсе.
  Future<void> _setReadEach(List<EmailModel> emails) async {
    final actions = ref.read(emailActionsProvider);
    final notifier = ref.read(emailsProvider.notifier);
    final accounts = {for (final a in ref.read(accountsProvider)) a.id: a};
    for (final e in emails) {
      notifier.applyLocalFlags(e.id, isRead: true);
    }
    for (final e in emails) {
      final a = accounts[e.accountId];
      if (a == null) continue;
      try {
        await actions.setRead(a, e.id, e.folderId, true);
      } catch (err) {
        AppLogger.warning('Прочитано: $err');
      }
    }
    await notifier.refresh();
  }

  /// Отметить прочитанными письма, где пользователь стоит В КОПИИ, но НЕ в «Кому».
  ///
  /// Это осознанно точечная операция, а не «разобрать всё»: массовая обработка
  /// опасна тем, что можно пропустить важное. Здесь под удар попадают только
  /// письма, адресованные не лично пользователю, — их обычно достаточно
  /// просмотреть. Решение принимает пользователь, вызывая пункт вручную.
  Future<void> _markReadWhereCc(AppLocalizations l10n) async {
    final state = ref.read(emailsProvider);
    final accounts = {for (final a in ref.read(accountsProvider)) a.id: a};

    // Свои адреса — ящика самого письма (во «Всей почте» их несколько).
    bool inCcOnly(EmailModel e) {
      final account = accounts[e.accountId];
      if (e.isRead || account == null) return false;
      final inTo = e.to.any((a) => OwnAddresses.isMine(account, a.email));
      final inCc = e.cc.any((a) => OwnAddresses.isMine(account, a.email));
      return inCc && !inTo;
    }

    final list = state.emails.where(inCcOnly).toList();
    final ids = [for (final e in list) e.id];
    if (ids.isEmpty) {
      showInlineNotice(l10n.tr('nothingToMark'));
      return;
    }

    // Подтверждение с числом писем: пользователь видит масштаб до применения.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('markReadWhereCc')),
        content: Text(l10n.tr('markReadWhereCcConfirm').replaceAll('{n}', '${ids.length}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.tr('markRead'))),
        ],
      ),
    );
    if (ok != true) return;

    await _setReadEach(list);
    if (!mounted) return;
    showInlineNotice(l10n.tr('markedReadN').replaceAll('{n}', '${ids.length}'));
  }

  /// Открытая сейчас папка активного аккаунта (null — сводная или не найдена).
  FolderModel? _currentFolder() {
    final id = ref.read(selectedFolderIdProvider);
    final account = ref.read(activeAccountProvider);
    if (id == null || account == null) return null;
    return (ref.read(foldersProvider).value ?? const <FolderModel>[])
        .where((f) => f.id == id && f.accountId == account.id)
        .firstOrNull;
  }

  /// Очистить открытую Корзину или Спам целиком — с подтверждением.
  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context);
    final account = ref.read(activeAccountProvider);
    final folder = _currentFolder();
    if (account == null || folder == null) return;
    final junk = folder.type == FolderType.junk;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(junk ? l10n.tr('clearJunk') : l10n.emptyTrashTitle),
        // Exchange хранит удалённое ещё ~14 дней (Recoverable Items) —
        // «безвозвратно» там неправда.
        content: Text(l10n.tr(account.isMsExchange ? 'emptyTrashBodyExchange' : 'emptyTrashBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.emptyAction)),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final (done, total) = await ref.read(folderActionsProvider).emptyFolder(account, folder);
      if (mounted && done < total) {
        showInlineError('${l10n.error}: ${total - done}');
      }
    } catch (e) {
      AppLogger.warning('Очистка папки: $e');
    }
    await ref.read(emailsProvider.notifier).refresh();
  }

  // ════════════════════════ ГРУППИРОВКА ════════════════════════

  /// «Позже»: «Вернулись», затем по дню возврата, в конце «Без даты».
  List<dynamic> _groupByLater(List<EmailModel> emails, AppLocalizations l10n) {
    final result = <dynamic>[];
    String? lastGroup;
    for (final email in emails) {
      final at = email.remindAt?.toLocal();
      final group = email.laterState == LaterState.returned
          ? l10n.tr('laterReturned').toUpperCase()
          : at == null
              ? l10n.tr('laterNoDate').toUpperCase()
              : _laterDayLabel(at, l10n);
      if (group != lastGroup) {
        result.add(group);
        lastGroup = group;
      }
      result.add(email);
    }
    return result;
  }

  String _laterDayLabel(DateTime at, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return l10n.tr('today').toUpperCase();
    if (day == today.add(const Duration(days: 1))) return l10n.tr('tomorrow').toUpperCase();
    return _dateGroupLabel(at, l10n);
  }

  List<dynamic> _groupByDate(List<EmailModel> emails, AppLocalizations l10n) {
    final result = <dynamic>[];
    String? lastGroup;

    for (final email in emails) {
      final group = _dateGroupLabel(email.receivedAt, l10n);
      if (group != lastGroup) {
        result.add(group);
        lastGroup = group;
      }
      result.add(email);
    }

    return result;
  }

  String _dateGroupLabel(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final emailDate = DateTime(date.year, date.month, date.day);

    if (emailDate == today) return l10n.tr('today').toUpperCase();
    if (emailDate == today.subtract(const Duration(days: 1))) {
      return l10n.tr('yesterday').toUpperCase();
    }

    final locale = l10n.localeCode;
    final dateStr = DateFormat('d MMMM', locale).format(date);
    // Прошлый (или будущий) год — вместо дня недели год: «1 января 2017»;
    // день недели давний — бесполезен, а год без него не узнать (09.10.2026).
    if (date.year != now.year) return '$dateStr ${date.year}';
    final dayName = DateFormat('EEEE', locale).format(date).toUpperCase();
    return '$dateStr · $dayName';
  }

  // ════════════════════════ SKELETON / EMPTY / ERROR ════════════════════════

  Widget _buildSkeletonList(ThemeData theme) {
    return Shimmer.fromColors(
      // Цвета из темы: в AMOLED/высококонтрастной теме серые плашки
      // Material выглядели чужеродно.
      baseColor: theme.colorScheme.surfaceContainerHighest,
      highlightColor: theme.colorScheme.surfaceContainerLow,
      child: ListView.builder(
        itemCount: 12,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 10),
          child: Row(
            children: [
              const CircleAvatar(radius: 24, backgroundColor: Colors.white),
              const SizedBox(width: Space.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 14, width: 160, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: Space.s),
                    Container(height: 12, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 6),
                    Container(height: 12, width: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations l10n) {
    // Если открыта папка, отключённая в настройках синхронизации, — объясняем,
    // почему пусто. Свайп вниз загрузит её разово (см. EmailsNotifier.refresh).
    final folderId = ref.watch(selectedFolderIdProvider);
    final disabled = folderId == null
        ? false
        : ref.watch(foldersProvider).maybeWhen(
              data: (fs) {
                for (final f in fs) {
                  if (f.id == folderId) return !f.isSynced;
                }
                return false;
              },
              orElse: () => false,
            );
    // Идёт синхронизация (первый вход: ящик загружается постепенно —
    // сначала папки, затем письма, контакты и календарь) — не «Нет писем»,
    // а «загружается, подождите» (замечание 10.10.2026: открыв папку сразу
    // после подключения, человек видел пустоту и думал, что писем нет).
    final syncing = ref.watch(syncStatusProvider) == SyncStatus.syncing;
    if (syncing && !disabled) {
      final first = ref.watch(activeAccountProvider)?.lastSyncAt == null;
      return EmptyState(
        icon: AppIcons.cloud_sync,
        title: l10n.tr(first ? 'firstSyncTitle' : 'folderLoadingTitle'),
        message: l10n.tr(first ? 'firstSyncHint' : 'folderLoadingHint'),
      );
    }
    // Включён фильтр («Непрочитанные», «С флажком», тег…) — пусто из-за
    // него (1.6.45): так и пишем, и сброс — одной кнопкой. Раньше «Нет
    // писем · Потяните вниз» выглядело как пустая папка.
    final filter = ref.watch(mailFilterProvider);
    final tag = ref.watch(tagFilterProvider);
    final filterParts = _filterParts(l10n, filter, tag);
    if (filterParts.isNotEmpty && !disabled) {
      return EmptyState(
        icon: AppIcons.filter_list,
        title: l10n.tr('filterEmptyTitle'),
        message: l10n.tr('filterPrefix').replaceAll('{parts}', filterParts.join(', ')),
        actionLabel: l10n.tr('clearFilter'),
        actionIcon: AppIcons.close,
        onAction: () {
          ref.read(mailFilterProvider.notifier).state = MailFilter.none;
          ref.read(tagFilterProvider.notifier).state = null;
        },
      );
    }
    return EmptyState(
      icon: disabled ? AppIcons.sync_disabled : AppIcons.inbox,
      title: l10n.tr('noEmails'),
      message: l10n.tr('pullToRefresh'),
      note: disabled ? l10n.tr('folderSyncDisabledHint') : null,
    );
  }

  Widget _buildErrorState(ThemeData theme, AppLocalizations l10n, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.cloud_off, size: 64, color: AppColors.errorRed),
            const SizedBox(height: Space.l),
            Text(l10n.tr('errorLoading'), style: theme.textTheme.titleMedium),
            const SizedBox(height: Space.s),
            Text(error, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.xl),
            FilledButton.icon(
              onPressed: () => ref.read(emailsProvider.notifier).refresh(),
              icon: const Icon(AppIcons.refresh),
              label: Text(l10n.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountAvatar(AccountModel? account) {
    if (account == null) {
      return const CircleAvatar(radius: 16, child: Icon(AppIcons.person, size: 18));
    }
    // Фото владельца (адресная книга организации, профиль Google) или буква
    // на цвете аккаунта; вокруг — кольцо цвета аккаунта.
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: Color(account.colorValue)),
      child: HeroEmailAvatar(
        emailId: 'appbar/${account.id}',
        initial: account.displayName.isNotEmpty ? initialOf(account.displayName) : '?',
        color: Color(account.colorValue),
        radius: 15,
        hero: false,
        email: account.email,
        photo: account.avatarUrl,
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: '${l10n.search}...',
        border: InputBorder.none,
        filled: false,
      ),
      onChanged: (query) {
        // Живой поиск с debounce через FTS5
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 300), () {
          ref.read(emailsProvider.notifier).search(query);
        });
      },
      onSubmitted: (query) {
        _searchDebounce?.cancel();
        // Историю пишем только по Enter: если сохранять на каждый символ,
        // она заполнится обрывками вроде «дог», «догов», «договор».
        ref.read(searchHistoryProvider).add(query);
        ref.read(emailsProvider.notifier).search(query);
      },
    );
  }
}


/// Быстрые фильтры над лентой (1.6.45, «Настройки → Почта»): одно нажатие —
/// фильтр, второе — сброс. Тот же [mailFilterProvider], что у шторки
/// фильтров и сведения пальцев.
class _QuickFilterBar extends ConsumerWidget {
  const _QuickFilterBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(mailFilterProvider);
    final control = ref.watch(settingsProvider.select((s) => s.mailControl));
    final items = <(MailFilter, IconData, String)>[
      (MailFilter.unread, AppIcons.mark_email_unread, l10n.tr('unread')),
      (MailFilter.toMe, AppIcons.person, l10n.tr('filterToMe')),
      (MailFilter.today, AppIcons.today, l10n.tr('today')),
      (MailFilter.flagged, AppIcons.flag, l10n.tr('flagged')),
      (MailFilter.attachments, AppIcons.attach_file, l10n.tr('withAttachments')),
      (MailFilter.vip, AppIcons.star, 'VIP'),
      if (control) (MailFilter.control, AppIcons.task_alt, l10n.tr('controlFilter')),
      (MailFilter.later, AppIcons.watch_later, l10n.tr('laterFilter')),
    ];
    return SizedBox(
      height: Sizes.tapTarget,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
        children: [
          for (final (f, icon, label) in items)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: FilterChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: current == f,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  ref.read(mailFilterProvider.notifier).state = current == f ? MailFilter.none : f;
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Жест двумя пальцами над списком писем. Слушает «сырые» касания, а не
/// участвует в разборе жестов — прокрутка и смахивания писем не мешают.
class _PinchFilter extends StatefulWidget {
  const _PinchFilter({required this.child, required this.onPinchIn, required this.onPinchOut});
  final Widget child;
  final VoidCallback onPinchIn;
  final VoidCallback onPinchOut;

  @override
  State<_PinchFilter> createState() => _PinchFilterState();
}

class _PinchFilterState extends State<_PinchFilter> {
  final Map<int, Offset> _points = {};
  double? _startDistance;
  bool _fired = false;

  double? _distance() {
    if (_points.length != 2) return null;
    final p = _points.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _points[e.pointer] = e.position;
    if (_points.length == 2) {
      _startDistance = _distance();
      _fired = false;
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_points.containsKey(e.pointer)) return;
    _points[e.pointer] = e.position;
    final start = _startDistance;
    final d = _distance();
    if (_fired || start == null || d == null || start < 40) return;
    // Порог мягче (было 0,65 и 1,5 — жест приходилось делать «на весь
    // экран», и казалось, что он не работает).
    final ratio = d / start;
    if (ratio < 0.8) {
      _fired = true;
      widget.onPinchIn();
    } else if (ratio > 1.25) {
      _fired = true;
      widget.onPinchOut();
    }
  }

  void _up(PointerEvent e) {
    _points.remove(e.pointer);
    if (_points.length < 2) _startDistance = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: widget.child,
      );
}

/// «Потянуть вниз — обновить» с коротким ходом.
///
/// Стандартный RefreshIndicator срабатывает, когда палец протянут на
/// четверть высоты списка, и только если жест начат точно у верхнего края.
/// На телефоне это ~150 dp: тянуть приходилось почти до низа экрана, а жест,
/// начатый на долю секунды раньше остановки прокрутки, не срабатывал вовсе
/// (замечание 06.10.2026). Здесь: срабатывание с любого начала жеста
/// (triggerMode.anywhere) и запуск обновления уже после [_kTrigger] dp
/// протяжки за верхний край.
/// Панель письма до выбора (широкое окно): тихая подсказка по центру.
/// Подпись письма под курсором при перетаскивании на папку.
class _DragChip extends StatelessWidget {
  final String subject;
  const _DragChip({required this.subject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.secondaryContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(AppIcons.mail, size: 18, color: theme.colorScheme.onSecondaryContainer),
            const SizedBox(width: Space.s),
            Flexible(
              child: Text(subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  final String text;
  const _DetailPlaceholder({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(AppIcons.mail, size: 48, color: muted.withValues(alpha: 0.5)),
          const SizedBox(height: Space.m),
          Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: muted), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _QuickPullRefresh extends StatefulWidget {
  const _QuickPullRefresh({required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<_QuickPullRefresh> createState() => _QuickPullRefreshState();
}

class _QuickPullRefreshState extends State<_QuickPullRefresh> {
  static const double _kTrigger = 72;
  final _key = GlobalKey<RefreshIndicatorState>();
  double _pulled = 0;
  bool _busy = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || _busy) return false;
    if (n is ScrollStartNotification || n is ScrollEndNotification) {
      _pulled = 0;
      return false;
    }
    // Android (ClampingScrollPhysics): протяжка за край — OverscrollNotification.
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0 &&
        n.metrics.pixels <= n.metrics.minScrollExtent) {
      _pulled += -n.overscroll;
    }
    // iOS/«пружинящая» прокрутка: позиция уходит выше начала списка.
    if (n is ScrollUpdateNotification && n.dragDetails != null &&
        n.metrics.pixels < n.metrics.minScrollExtent) {
      _pulled = n.metrics.minScrollExtent - n.metrics.pixels;
    }
    if (_pulled >= _kTrigger) {
      _pulled = 0;
      _busy = true;
      // Запуск после кадра: show() во время разбора уведомления прокрутки
      // перебивает собственную анимацию индикатора.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final st = _key.currentState;
        if (st == null) {
          _busy = false;
          return;
        }
        st.show().whenComplete(() => _busy = false);
      });
    }
    return false;
  }

  Future<void> _run() async {
    _busy = true;
    try {
      await widget.onRefresh();
    } finally {
      _busy = false;
      _pulled = 0;
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        key: _key,
        triggerMode: RefreshIndicatorTriggerMode.anywhere,
        onRefresh: _run,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      );
}

/// Отметка строки ленты: пока строка построена, её context — в [marks]
/// (по нему плавающая дата находит верхнюю строку).
class _RowMark extends StatefulWidget {
  final int index;
  final Map<int, BuildContext> marks;
  final Widget child;
  const _RowMark({required this.index, required this.marks, required this.child});

  @override
  State<_RowMark> createState() => _RowMarkState();
}

class _RowMarkState extends State<_RowMark> {
  @override
  void initState() {
    super.initState();
    widget.marks[widget.index] = context;
  }

  @override
  void didUpdateWidget(covariant _RowMark old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (identical(widget.marks[old.index], context)) widget.marks.remove(old.index);
      widget.marks[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (identical(widget.marks[widget.index], context)) widget.marks.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Плашка плавающей даты: та же форма, что у разделителей ленты
/// (SectionBand.light), по размеру текста, с лёгкой тенью поверх писем.
class _FloatingDateChip extends StatelessWidget {
  final String label;
  const _FloatingDateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: 6),
        // Как подписи дат в ленте: с 1.8.0 («воздушный» вид) — обычным
        // регистром и синим, в высоком контрасте — прописными.
        child: OgnelissLook.of(context).outlined
            ? Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              )
            : Text(label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                )),
      ),
    );
  }
}

/// Метка строки письма для [_DragSelect].
class _SelRow {
  final String id;
  const _SelRow(this.id);
}

/// Выбор писем проведением пальцем (1.6.47, «как в Telegram»): удержать
/// портрет — письмо отмечено и включён выбор; не отпуская, вести палец по
/// ленте — отмечаются все письма между первым и тем, что под пальцем. Если
/// первое письмо удержанием сняли — так же снимаются и остальные. Палец у
/// верхнего или нижнего края ленты — лента прокручивается сама.
class _DragSelect implements HoldTracker {
  _DragSelect(this._s);
  final _MailListScreenState _s;

  Offset? _startAt;
  Offset? _last;
  List<String> _order = const [];
  int? _anchor;
  Set<String> _base = const {};
  bool _value = true;
  Timer? _auto;
  double _autoSpeed = 0;

  /// Поле у края ленты, где она прокручивается сама, и скорость (точек за кадр).
  static const _edge = 56.0;
  static const _maxSpeed = 14.0;

  @override
  void begin(Offset global) {
    _startAt = global;
    _last = global;
    _anchor = null;
  }

  @override
  void move(Offset global) {
    if (_startAt == null || !_s.mounted) return;
    _last = global;
    // Начало — на первом движении: к нему портрет уже отметил (или снял)
    // первое письмо, и видно, отмечать или снимать остальные.
    if (_anchor == null && !_start()) return;
    _apply(global);
    _edgeScroll(global);
  }

  @override
  void end() => stop();

  void stop() {
    _auto?.cancel();
    _auto = null;
    _autoSpeed = 0;
    _startAt = null;
    _last = null;
    _anchor = null;
  }

  bool _start() {
    final at = _startAt;
    if (at == null) return false;
    final id = _rowAt(at);
    if (id == null) return false;
    _order = [
      for (final x in _s._cachedGrouped ?? const <dynamic>[])
        if (x is EmailModel) x.id,
    ];
    final i = _order.indexOf(id);
    if (i < 0) return false;
    _anchor = i;
    _value = _s._selectedIds.contains(id);
    _base = {..._s._selectedIds};
    return true;
  }

  /// Письмо под точкой экрана.
  String? _rowAt(Offset global) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, global, View.of(_s.context).viewId);
    for (final e in result.path) {
      final t = e.target;
      if (t is RenderMetaData && t.metaData is _SelRow) return (t.metaData as _SelRow).id;
    }
    return null;
  }

  void _apply(Offset global) {
    final a = _anchor;
    if (a == null) return;
    final id = _rowAt(global);
    if (id == null) return;
    final j = _order.indexOf(id);
    if (j < 0) return;
    final next = {..._base};
    for (var k = a < j ? a : j; k <= (a < j ? j : a); k++) {
      _value ? next.add(_order[k]) : next.remove(_order[k]);
    }
    final cur = _s._selectedIds;
    if (next.length == cur.length && next.containsAll(cur)) return;
    // ignore: invalid_use_of_protected_member
    _s.setState(() {
      cur
        ..clear()
        ..addAll(next);
      if (cur.isNotEmpty) _s._selectionMode = true;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _edgeScroll(Offset global) {
    final box = _s._listBoxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    double speed = 0;
    if (global.dy < top + _edge) {
      speed = -_maxSpeed * ((top + _edge - global.dy) / _edge).clamp(0.2, 1.0);
    } else if (global.dy > bottom - _edge) {
      speed = _maxSpeed * ((global.dy - (bottom - _edge)) / _edge).clamp(0.2, 1.0);
    }
    _autoSpeed = speed;
    if (speed == 0) {
      _auto?.cancel();
      _auto = null;
      return;
    }
    _auto ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final c = _s._scrollController;
      final at = _last;
      if (!_s.mounted || !c.hasClients || at == null || _autoSpeed == 0) {
        _auto?.cancel();
        _auto = null;
        return;
      }
      final p = c.position;
      final to = (p.pixels + _autoSpeed).clamp(p.minScrollExtent, p.maxScrollExtent).toDouble();
      if (to == p.pixels) return;
      c.jumpTo(to);
      _apply(at);
    });
  }
}

/// «↑ N новых» над лентой (1.6.48).
class _NewAbovePill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NewAbovePill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      liveRegion: true,
      label: label,
      child: Material(
        color: scheme.primary,
        shape: const StadiumBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(AppIcons.arrow_upward, size: Sizes.iconInline, color: scheme.onPrimary),
                  const SizedBox(width: Space.xs),
                  Text(label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.onPrimary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// lib/services/notifications/notification_service.dart
// Уведомления: каналы по категориям, inline reply, smart actions.

import 'dart:ui' show Color, Locale, PlatformDispatcher;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import 'notification_action_handler.dart' show NotificationPinGuard;
import '../../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/settings/providers/quiet_hours_provider.dart';
import '../../data/providers/shared_prefs_provider.dart';
import 'package:flutter/services.dart';
import 'notification_background.dart';
import 'notification_text.dart';
import 'messenger_notifications.dart';
import '../security/managed_config.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService(ref.read(sharedPrefsProvider)));

// Фоновый обработчик кнопок уведомления — notification_background.dart.

class NotificationService {
  final SharedPreferences? _prefs;
  NotificationService([this._prefs]);

  static const pendingActionsKey = 'pending_notification_actions';

  /// Действия, нажатые в уведомлениях, пока приложение было выгружено.
  /// Очередь очищается при чтении.
  static Future<List<({String action, String? payload, String? input})>> takePendingActions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(pendingActionsKey) ?? const <String>[];
    if (list.isEmpty) return const [];
    await prefs.remove(pendingActionsKey);
    final out = <({String action, String? payload, String? input})>[];
    for (final raw in list) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        out.add((action: m['a'] as String, payload: m['p'] as String?, input: m['i'] as String?));
      } catch (_) {}
    }
    return out;
  }

  // Настройки звука/вибрации уведомлений. Ключи совпадают с settings_provider._K
  // (notificationSound='s_notif_sound', notificationVibration='s_notif_vib').
  // Раньше эти тумблеры существовали в UI, но НЕ читались — звук/вибрация были
  // всегда включены независимо от настройки.
  bool get _soundOn => _prefs?.getBool('s_notif_sound') ?? true;
  bool get _vibrationOn => _prefs?.getBool('s_notif_vib') ?? true;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Платформы, где используемая версия flutter_local_notifications (17.x)
  /// умеет показывать уведомления. На Windows плагин `initialize()` молча
  /// возвращает true, а `show()`/`zonedSchedule()`/`cancel()` бросают
  /// UnimplementedError. Без этой проверки исключение из уведомления
  /// прерывало бы вызывающий код (например, обработку новых писем при
  /// синхронизации). Нативные уведомления Windows — отдельная задача
  /// (flutter_local_notifications 19+ с WindowsInitializationSettings).
  static bool get isPlatformSupported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux);

  static bool _unsupportedLogged = false;
  static bool _skipOnThisPlatform() {
    if (isPlatformSupported) return false;
    if (!_unsupportedLogged) {
      _unsupportedLogged = true;
      AppLogger.info('Уведомления ОС на этой платформе не поддерживаются — пропускаем');
    }
    return true;
  }

  /// Строка на языке интерфейса. Уведомления создаются и в фоновом изоляте,
  /// где нет BuildContext, поэтому язык читается из настроек (или системы).
  /// Раньше тексты уведомлений и названия каналов были только по-русски.
  String _t(String key) => AppLocalizations(Locale(_lang())).tr(key);

  /// Язык уведомлений: из настроек, иначе системный, иначе английский.
  String _lang() {
    final supported = AppLocalizations.supportedCodes;
    var lang = _prefs?.getString('s_locale');
    if (lang == null || !supported.contains(lang)) {
      final sys = PlatformDispatcher.instance.locale.languageCode;
      lang = supported.contains(sys) ? sys : 'en';
    }
    return lang;
  }

  /// «3 новых письма» с правильной формой числа для языка.
  String _newMailCount(int n) {
    final ru = _t('ntfNewMailOne') == 'новое письмо';
    String key;
    if (ru) {
      final m10 = n % 10, m100 = n % 100;
      key = (m10 == 1 && m100 != 11)
          ? 'ntfNewMailOne'
          : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) ? 'ntfNewMailFew' : 'ntfNewMailMany';
    } else {
      key = n == 1 ? 'ntfNewMailOne' : 'ntfNewMailMany';
    }
    return '$n ${_t(key)}';
  }

  /// Колбэк действий уведомления (подключается из main к NotificationActionHandler).
  void Function(String actionId, String? payload, String? input)? onResponse;

  Future<void> initialize() async {
    // Строки уведомлений (1.7.3 — файлы assets/l10n): и в фоновом изоляте.
    await AppLocalizations.load(_lang());
    if (_initialized) return;
    if (_skipOnThisPlatform()) {
      _initialized = true;
      return;
    }

    tzdata.initializeTimeZones(); // база часовых поясов для отложенных уведомлений
    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
    // iPhone и iPad (1.12.x, аудит устройств, просьба владельца 05.11.2026):
    // разрешение на уведомления при запуске не спрашивается — системный
    // вопрос появлялся на заставке до входа в ящик, без пояснения, а в
    // фоновой задаче задать его нельзя. Спрашивает шаг первой настройки
    // после входа (AppPermissions, permission_handler: alert, badge, sound)
    // и строка «Включить» в ленте. Mac — как раньше: экрана разрешений там нет.
    final askNow = kIsWeb || !Platform.isIOS;
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: askNow,
      requestBadgePermission: askNow,
      requestSoundPermission: askNow,
      notificationCategories: [
        DarwinNotificationCategory('EMAIL', actions: [
          // Ответ прямо из уведомления, как на Android (quick_reply с полем ввода).
          DarwinNotificationAction.text('quick_reply', _t('ntfReply'),
              buttonTitle: _t('ntfReply'), placeholder: _t('ntfReplyInput'),
              options: {DarwinNotificationActionOption.authenticationRequired}),
          // Те же действия, что на Android: Ответить · Прочитано · Удалить.
          DarwinNotificationAction.plain('mark_read', _t('ntfMarkRead')),
          DarwinNotificationAction.plain('delete', _t('ntfDelete'),
              options: {DarwinNotificationActionOption.destructive}),
        ]),
        // Приглашение на встречу (письмо Exchange с запросом ответа).
        DarwinNotificationCategory('INVITE', actions: [
          DarwinNotificationAction.plain('invite_accept', _t('accept')),
          DarwinNotificationAction.plain('invite_tentative', _t('meetingTentative')),
          DarwinNotificationAction.plain('invite_decline', _t('decline'),
              options: {DarwinNotificationActionOption.destructive}),
        ]),
        DarwinNotificationCategory('MEETING', actions: [
          DarwinNotificationAction.plain('open_event', _t('ntfOpen')),
          DarwinNotificationAction.plain('join', _t('ntfJoin')),
          DarwinNotificationAction.plain('dismiss', _t('ntfDismiss')),
        ]),
      ],
    );

    await _plugin.initialize(
      // macOS и Linux (1.8.13): без своих настроек плагин бросал ArgumentError
      // при запуске, и уведомлений на компьютере не было вовсе.
      InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
        linux: LinuxInitializationSettings(defaultActionName: _t('ntfOpen')),
      ),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );

    // Android каналы
    if (!kIsWeb && Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // Каналы писем создаются по факту в варианте со звуком/вибрацией
        // ('email_default_sv' и т. п.). Базовые 'email_default'/'email_vip' и
        // 'sync' ничем не использовались и в настройках Android выглядели
        // дублями («Почта», «Почта», «Синхронизация»).
        for (final unused in const ['email_default', 'email_vip', 'sync']) {
          await android.deleteNotificationChannel(unused);
        }
        await android.createNotificationChannel(AndroidNotificationChannel(
          'meeting_reminders', _t('ntfChMeetings'), description: _t('ntfChMeetingsDesc'), importance: Importance.high,
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          'reminders', _t('ntfChReminders'), description: _t('ntfChRemindersDesc'), importance: Importance.high,
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          'task_reminders', _t('ntfChTasks'), description: _t('ntfChTasksDesc'), importance: Importance.high,
        ));
      }
    }

    _initialized = true;
    AppLogger.info('Notifications initialized');
  }

  /// Показать уведомление о новом письме.
  /// [smartReplyLabels]/[smartReplyBodies] — умные быстрые ответы (локальный ИИ):
  /// подписи на кнопках и готовый текст (отправляется обработчиком).
  Future<void> showEmailNotification({
    required String accountId,
    required String emailId,
    required String senderName,
    required String subject,

    /// Подпись ящика для шторки. Показывается, когда подключено несколько
    /// аккаунтов: иначе непонятно, куда пришло письмо. Для общих
    /// (делегированных) ящиков подпись обязательна — реагировать на чужую
    /// почту как на свою опасно.
    String? mailboxLabel,

    /// Общий (делегированный) ящик — помечаем явно.
    bool isSharedMailbox = false,
    String? preview,
    String? fromEmail,
    String folderId = 'inbox',
    bool isVip = false,
    List<String> smartReplyLabels = const [],
    List<String> smartReplyBodies = const [],

    /// Папка, если это не «Входящие» (письмо разложило серверное правило) —
    /// показывается в уведомлении, чтобы было ясно, где его искать.
    String? folderLabel,

    /// Время получения письма — в шторке вместо времени показа.
    DateTime? receivedAt,

    /// Не звонить повторно (вторая и следующие строки одной пачки писем).
    bool silent = false,

    /// Приглашение на встречу: кнопки «Принять», «Под вопросом», «Отклонить»
    /// вместо «Ответить / Прочитано / Удалить».
    bool isInvite = false,

    /// Правило «без звука»: тихий канал — в шторке, без звука и вибрации.
    bool quiet = false,

    /// Фото отправителя из контактов (data URI) — для вида «как в
    /// мессенджерах» (1.9.x); нет — кружок с буквой.
    String? senderPhoto,

    /// Короткая подпись ящика («я» в беседе Android) — всегда, даже когда
    /// ящик один и [mailboxLabel] не показывается.
    String? accountLabel,

    /// Строк начала письма (NotificationLines, 1.10.3) и текст письма, если
    /// он уже загружен: превью короче, чем нужно для 8 и 12 строк.
    int previewLines = NotificationLines.byDefault,
    String? fullText,

    /// Цвет и буква ящика (несколько ящиков, оценка интерфейса 12.11.2026):
    /// Android — большой значок справа кружком цвета ящика и цвет шапки.
    /// Маленький значок система разрешает только однотонным знаком
    /// приложения.
    int? accountColor,
    String? accountInitial,
  }) async {
    if (_skipOnThisPlatform()) return;
    if (!_initialized) await initialize();
    // Тихие часы — не показываем уведомления о письмах. Исключение — VIP:
    // ради них список VIP и заводят (раньше тихие часы глушили и их).
    if (!isVip && _prefs != null && QuietHours.isQuietNow(_prefs)) {
      AppLogger.info('Уведомление о письме не показано: тихие часы');
      return;
    }
    // Политика организации (MDM, 1.10.5): в уведомлении ни отправителя, ни
    // темы, ни текста — «Новое сообщение»; быстрых ответов с текстом тоже
    // нет. Копия политики — в prefs: уведомление показывает и фон.
    final hideContent = ManagedPolicy.fromPrefs(_prefs).hideNotificationContent;
    if (hideContent) {
      senderName = _t('newMessage');
      subject = '';
      preview = null;
      fullText = null;
      senderPhoto = null;
      fromEmail = null;
      smartReplyLabels = const [];
      smartReplyBodies = const [];
      folderLabel = null;
    }
    final payload = jsonEncode({
      'type': 'email',
      'accountId': accountId,
      'emailId': emailId,
      'folderId': folderId,
      'fromEmail': fromEmail,
      'subject': subject,
      'smartReplies': smartReplyBodies,
    });
    // PIN приложения (2.0.0): без кнопок — нажатие открывает приложение, и
    // оно спрашивает PIN (NotificationPinGuard).
    final pinLocked = NotificationPinGuard.pinSet(_prefs);
    final actions = pinLocked
        ? <AndroidNotificationAction>[]
        : isInvite
        ? <AndroidNotificationAction>[
            AndroidNotificationAction('invite_accept', _t('accept')),
            AndroidNotificationAction('invite_tentative', _t('meetingTentative')),
            AndroidNotificationAction('invite_decline', _t('decline')),
          ]
        : <AndroidNotificationAction>[
      // Ответ прямо из шторки: обрабатывает фоновый обработчик и при открытом,
      // и при выгруженном приложении (09.10.2026). С showsUserInterface: true
      // приложение открывалось, а текст ответа терялся: при холодном запуске
      // доходило только «открыть письмо», без кнопки и введённого текста.
      AndroidNotificationAction('quick_reply', _t('ntfReply'),
          inputs: [AndroidNotificationActionInput(label: _t('ntfReplyInput'))]),
    ];
    if (!isInvite && !pinLocked) {
      for (var i = 0; i < smartReplyLabels.length && i < 2; i++) {
        actions.add(AndroidNotificationAction('smart_reply_$i', smartReplyLabels[i]));
      }
      // Android показывает не больше трёх кнопок: Ответить · Прочитано ·
      // Удалить. Флажок и архив прежде вытесняли «Удалить» — самое частое
      // действие с уведомлением о письме.
      actions.add(AndroidNotificationAction('mark_read', _t('ntfMarkRead')));
      actions.add(AndroidNotificationAction('delete', _t('ntfDelete')));
    }

    // Раскладка (1.8.13, NotificationText): жирным — только отправитель,
    // ниже тема, в раскрытом — тема и начало текста без цитаты и подписи;
    // папка и короткая подпись ящика — в шапке уведомления.
    final badge = await _bumpBadge();
    final title = NotificationText.title(senderName, shared: isSharedMailbox);
    final subj = hideContent ? '' : NotificationText.subject(subject, noSubject: _t('noSubject'));
    final source = (fullText != null && fullText.trim().isNotEmpty && NotificationLines.wantsBody(previewLines))
        ? fullText
        : preview;
    final text = NotificationText.preview(source, max: NotificationLines.maxChars(previewLines));
    // Как в мессенджерах (1.9.x, просьба владельца 31.10.2026): отправитель
    // с фото или буквой. Выключено — уведомление прежнего вида. VIP
    // (1.10.5) — кольцо и звёздочка на портрете; без портрета — «VIP» в
    // шапке.
    final messenger = MessengerNotify.styleOn(_prefs) && (Platform.isAndroid || Platform.isIOS);
    final subText = NotificationText.subText(folder: folderLabel, mailbox: mailboxLabel, vip: isVip && !messenger);
    // Строка текста: на Android — тема (свёрнутое уведомление), на iPhone и
    // Mac тема — подзаголовок, а в тексте — начало письма и последней
    // строкой папка и ящик (шапки, как на Android, там нет).
    // Linux — тема и текст: раскрывать уведомление там нечем.
    final apple = Platform.isIOS || Platform.isMacOS;
    final body = apple
        ? [if (text.isNotEmpty) text, if (subText != null) subText].join('\n')
        : (Platform.isAndroid ? subj : NotificationText.big(subj, text));
    final darwin = DarwinNotificationDetails(
        presentAlert: true, presentSound: _soundOn && !silent && !quiet, presentBadge: true, badgeNumber: badge,
        subtitle: subj,
        categoryIdentifier: isInvite ? 'INVITE' : 'EMAIL', threadIdentifier: 'email_$accountId');

    final avatar = messenger
        ? await MessengerNotify.avatar(
            name: senderName, email: fromEmail, photo: senderPhoto,
            highContrast: _prefs?.getBool('s_high_contrast') ?? false, vip: isVip)
        : null;
    final id = notificationIdForEmail(accountId, emailId);
    // iPhone: нативно, с INSendMessageIntent (AppDelegate.swift). Не вышло —
    // плагином, как раньше.
    if (messenger && Platform.isIOS) {
      final shown = await MessengerNotify.showIos(MessengerNotify.iosArgs(
        id: id, title: title, subtitle: subj, body: body,
        threadId: 'email_$accountId', category: isInvite ? 'INVITE' : 'EMAIL',
        sound: _soundOn && !silent && !quiet, badge: badge, payload: payload,
        senderEmail: fromEmail, avatar: avatar,
      ));
      if (shown) return;
    }
    // Android: беседа для VIP (или для всех писем, 1.11.0) — ярлык с
    // человеком; уведомление с его id попадает в раздел «Беседы» (можно
    // сделать приоритетным), а в свёрнутом слева — портрет, а не значок
    // приложения.
    String? shortcutId;
    if (MessengerNotify.wantsShortcut(
        android: Platform.isAndroid, styleOn: messenger, vipConversationsOn: MessengerNotify.vipConversationsOn(_prefs),
        allConversationsOn: MessengerNotify.allConversationsOn(_prefs), isVip: isVip, email: fromEmail)) {
      shortcutId = await MessengerNotify.pushShortcut(
          name: senderName, email: fromEmail!, accountId: accountId, emailId: emailId, avatar: avatar);
    }

    // Ящик и папка в уведомлении-переписке (2.3.2, замечание владельца
    // 11.11.2026: «нет информации, на какой аккаунт пришло письмо»). На
    // Android 12+ шапка такого уведомления не показывает subText. Без
    // ярлыка беседы подпись идёт названием беседы — система ставит его в
    // шапку: «Ogneliss Mail · ящик · время». С ярлыком (VIP, «беседы для
    // всех») название заняло бы место имени отправителя — там подпись
    // последней строкой текста.
    // Обычный вид (не «как в мессенджерах»): кружок ящика большим значком —
    // ящик виден и в свёрнутом уведомлении.
    final boxIcon = Platform.isAndroid && !messenger && mailboxLabel != null && accountColor != null
        ? await MessengerNotify.renderInitials(
            letter: accountInitial ?? mailboxLabel.substring(0, 1).toUpperCase(),
            fill: accountColor,
            letterColor: 0xFFFFFFFF)
        : null;
    final headerInStyle =
        Platform.isAndroid && messenger && subText != null && await _androidSdk() >= 31;
    final styleHeader = headerInStyle && shortcutId == null ? subText : null;
    final styleTail = headerInStyle && shortcutId != null ? subText : null;

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        // Android 8+ фиксирует звук/вибрацию на уровне КАНАЛА (не отдельного
        // уведомления). Поэтому вариант кодируем в id канала — при смене настройки
        // используется правильно сконфигурированный канал.
        android: AndroidNotificationDetails(
          quiet && !isVip
              ? 'email_quiet'
              : '${isVip ? 'email_vip' : 'email_default'}_${_soundOn ? 's' : 'n'}${_vibrationOn ? 'v' : 'n'}',
          quiet && !isVip ? _t('ntfChQuiet') : (isVip ? _t('ntfChVip') : _t('ntfChMail')),
          importance: quiet && !isVip ? Importance.low : (isVip ? Importance.max : Importance.high),
          priority: quiet && !isVip ? Priority.low : (isVip ? Priority.max : Priority.high),
          category: AndroidNotificationCategory.email,
          // VIP (1.10.5) — золотой значок и название приложения в шапке.
          // Несколько ящиков — цвет ящика (значок и название в шапке).
          color: isVip
              ? const Color(NotificationText.vipColor)
              : (mailboxLabel != null && accountColor != null ? Color(accountColor) : null),
          largeIcon: boxIcon == null ? null : ByteArrayAndroidBitmap(boxIcon),
          // На экране блокировки — без отправителя и темы (они видны только
          // после разблокировки): переписка не читается с чужого стола.
          visibility: NotificationVisibility.private,
          groupKey: 'email_$accountId',
          actions: actions,
          playSound: _soundOn && !(quiet && !isVip),
          enableVibration: _vibrationOn && !(quiet && !isVip),
          // Пачка писем: звонит только первое уведомление.
          onlyAlertOnce: silent,
          // Число на значке приложения (лаунчеры с поддержкой счётчика).
          number: badge,
          when: receivedAt?.millisecondsSinceEpoch,
          showWhen: true,
          // Полный текст превью по раскрытию.
          subText: subText,
          styleInformation: emailAndroidStyle(
            messenger: messenger,
            title: title,
            subject: subj,
            preview: text,
            subText: subText,
            selfName: accountLabel ?? mailboxLabel ?? '',
            fromEmail: fromEmail,
            avatar: avatar,
            isVip: isVip,
            when: receivedAt ?? DateTime.now(),
            header: styleHeader,
            tail: styleTail,
          ),
          shortcutId: shortcutId,
        ),
        // iPhone и Mac: отправитель — заголовок, тема — подзаголовок, текст
        // ниже (как в Почте iPhone).
        iOS: darwin,
        macOS: darwin,
      ),
      payload: payload,
    );
  }

  /// «Письмо не доставлено» (1.9.x, отчёты о доставке, просьба владельца
  /// 31.10.2026): вместо обычного уведомления о письме робота — кому не
  /// дошло и почему. Нажатие открывает само отправленное письмо: там
  /// «Отправить снова» и «Изменить адрес». Тихие часы действуют.
  Future<void> showDeliveryFailureNotification({
    required String accountId,
    required String emailId,
    required String folderId,
    required String subject,
    required String recipient,
    required String reasonKey,
    String? status,
    int more = 0,
  }) async {
    if (_skipOnThisPlatform()) return;
    if (!_initialized) await initialize();
    if (_prefs != null && QuietHours.isQuietNow(_prefs)) {
      AppLogger.info('Уведомление «письмо не доставлено» не показано: тихие часы');
      return;
    }
    final title = _t('dsnNotifTitle');
    // Политика организации (MDM): без адресата и темы — только причина.
    final hide = ManagedPolicy.fromPrefs(_prefs).hideNotificationContent;
    final line = '${hide ? '' : '$recipient — '}${_t(reasonKey)}${status == null ? '' : ' ($status)'}'
        '${more > 0 ? ' · +$more' : ''}';
    final subj = hide ? '' : NotificationText.subject(subject, noSubject: _t('noSubject'));
    final darwin = DarwinNotificationDetails(
        presentAlert: true, presentSound: _soundOn, subtitle: subj, threadIdentifier: 'email_$accountId');
    await _plugin.show(
      notificationIdForEmail(accountId, emailId),
      title,
      line,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'email_default_${_soundOn ? 's' : 'n'}${_vibrationOn ? 'v' : 'n'}',
          _t('ntfChMail'),
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.email,
          visibility: NotificationVisibility.private,
          groupKey: 'email_$accountId',
          playSound: _soundOn,
          enableVibration: _vibrationOn,
          styleInformation: BigTextStyleInformation(NotificationText.big(subj, line), contentTitle: title),
        ),
        iOS: darwin,
        macOS: darwin,
      ),
      payload: jsonEncode({'type': 'email', 'accountId': accountId, 'emailId': emailId, 'folderId': folderId}),
    );
  }

  /// Вид уведомления о письме на Android. [messenger] — «как в
  /// мессенджерах» (1.9.x): MessagingStyle, отправитель — Person с фото или
  /// буквой, сообщение — тема и ниже начало письма. Иначе — прежний
  /// BigTextStyle (жирным отправитель, ниже тема и текст).
  static StyleInformation emailAndroidStyle({
    required bool messenger,
    required String title,
    required String subject,
    required String preview,
    String? subText,
    String selfName = '',
    String? fromEmail,
    Uint8List? avatar,
    bool isVip = false,
    required DateTime when,

    /// Подпись ящика и папки в шапке уведомления-переписки (Android 12+).
    String? header,

    /// Она же — последней строкой текста (уведомление с ярлыком беседы).
    String? tail,
  }) {
    if (!messenger) {
      return BigTextStyleInformation(
        NotificationText.big(subject, preview),
        contentTitle: title,
        summaryText: subText,
      );
    }
    final text = NotificationText.big(subject, preview);
    return MessengerNotify.androidStyle(
      selfName: selfName,
      sender: MessengerNotify.androidSender(title: title, email: fromEmail, avatar: avatar, vip: isVip),
      text: (tail == null || tail.trim().isEmpty) ? text : '$text\n${tail.trim()}',
      when: when,
      header: header,
    );
  }

  /// Версия Android (SDK); 0 — не Android или не узнали.
  static int? _sdk;
  static Future<int> _androidSdk() async {
    if (_sdk != null) return _sdk!;
    if (kIsWeb || !Platform.isAndroid) return _sdk = 0;
    try {
      return _sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    } catch (_) {
      return 0;
    }
  }

  /// Пробное уведомление (1.6.45, «Проверка почты»): тем же каналом и с теми
  /// же звуком и вибрацией, что уведомление о письме. Не пришло — значит,
  /// уведомления о почте выключены в телефоне (разрешение, категория
  /// «Почта», режим «Не беспокоить»), и это видно сразу, а не через день
  /// «приложение перестало сообщать». Тихие часы не действуют: проверку
  /// человек запускает сам.
  Future<bool> showTestNotification() async {
    if (_skipOnThisPlatform()) return false;
    if (!_initialized) await initialize();
    try {
      await _plugin.show(
        stableId('mail_test'),
        _t('ntfTestTitle'),
        _t('ntfTestBody'),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'email_default_${_soundOn ? 's' : 'n'}${_vibrationOn ? 'v' : 'n'}',
            _t('ntfChMail'),
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.email,
            playSound: _soundOn,
            enableVibration: _vibrationOn,
          ),
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: _soundOn, presentBadge: false),
        ),
        payload: jsonEncode({'type': 'test'}),
      );
      AppLogger.info('Пробное уведомление показано');
      return true;
    } catch (e) {
      AppLogger.warning('Пробное уведомление: $e');
      return false;
    }
  }

  /// Сводное уведомление группы писем ящика (Android сворачивает в него
  /// отдельные уведомления). [accountEmail] — подпись в шапке (короткая
  /// подпись ящика или «Письма за время фокуса»); [lines] — до 6 строк
  /// обычным шрифтом (NotificationText.summaryLine).
  Future<void> showSummaryNotification({
    required String accountId,
    required String accountEmail,
    required int count,
    List<String> lines = const [],
    /// Ящик «без звука» (1.6.45): сводка — тихим каналом.
    bool quiet = false,
  }) async {
    if (_skipOnThisPlatform()) return;
    if (!_initialized) await initialize();
    if (_prefs != null && QuietHours.isQuietNow(_prefs)) return;
    // Политика организации (MDM): в сводке — только число писем.
    if (ManagedPolicy.fromPrefs(_prefs).hideNotificationContent) lines = const [];

    final badge = await _badge();
    await _plugin.show(
      notificationIdForSummary(accountId),
      _newMailCount(count),
      accountEmail.isEmpty ? null : accountEmail,
      NotificationDetails(
        android: AndroidNotificationDetails(
          quiet ? 'email_quiet' : 'email_default_${_soundOn ? "s" : "n"}${_vibrationOn ? "v" : "n"}',
          quiet ? _t('ntfChQuiet') : _t('ntfChMail'),
          importance: quiet ? Importance.low : Importance.high,
          visibility: NotificationVisibility.private,
          groupKey: 'email_$accountId',
          setAsGroupSummary: true,
          number: badge > 0 ? badge : count,
          // Сводка не звонит сама — звонит первое письмо пачки.
          onlyAlertOnce: true,
          playSound: _soundOn && !quiet,
          enableVibration: _vibrationOn && !quiet,
          category: AndroidNotificationCategory.email,
          subText: accountEmail.isEmpty ? null : accountEmail,
          styleInformation: lines.isEmpty
              ? null
              : InboxStyleInformation(
                  lines.take(6).toList(),
                  contentTitle: _newMailCount(count),
                  summaryText: accountEmail.isEmpty ? null : accountEmail,
                ),
        ),
        iOS: DarwinNotificationDetails(
            presentAlert: true, presentSound: _soundOn && !quiet, presentBadge: true, badgeNumber: badge > 0 ? badge : null),
      ),
      payload: jsonEncode({'type': 'mail_summary', 'accountId': accountId}),
    );
  }

  /// Стабильный id уведомления. String.hashCode в Dart не обязан совпадать
  /// между запусками — уведомление, показанное в фоновом изоляте, нельзя
  /// было бы снять из приложения. FNV-1a, 31 бит.
  static int stableId(String key) {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h & 0x7FFFFFFF;
  }

  // ── Значок приложения ──
  // Число на значке — сколько писем пришло с последнего открытия (а не
  // сколько непрочитанных): открыли приложение — значок сброшен, даже если
  // письма остались непрочитанными. Счётчик — в SharedPreferences: письма
  // приходят и в фоновом процессе.
  static const badgeKey = 'badge_new_mail';

  Future<int> _bumpBadge() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final n = (p.getInt(badgeKey) ?? 0) + 1;
      await p.setInt(badgeKey, n);
      return n;
    } catch (_) {
      return 1;
    }
  }

  Future<int> _badge() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.reload();
      return p.getInt(badgeKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Открыли приложение: сбросить значок. На Android точку и число на
  /// значке рисует лаунчер по уведомлениям в шторке, поэтому уведомления о
  /// письмах снимаются (письма остаются непрочитанными, как в Gmail);
  /// напоминания и встречи не трогаем.
  Future<void> clearMailBadge() async {
    if (_skipOnThisPlatform()) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(badgeKey, 0);
      if (Platform.isAndroid) {
        if (!_initialized) await initialize();
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final active = await android?.getActiveNotifications() ?? const <ActiveNotification>[];
        for (final n in active) {
          final ch = n.channelId ?? '';
          if (ch.startsWith('email_default') || ch.startsWith('email_vip') || ch == 'email_quiet') {
            final id = n.id;
            if (id != null) await _plugin.cancel(id, tag: n.tag);
          }
        }
      } else if (Platform.isIOS) {
        await const MethodChannel('ogneliss/platform').invokeMethod<void>('clearBadge');
      }
    } catch (e) {
      AppLogger.debug('Значок: $e');
    }
  }

  static int notificationIdForEmail(String accountId, String emailId) =>
      stableId('mail|$accountId|$emailId');

  static int notificationIdForSummary(String accountId) => stableId('mailsum|$accountId');

  /// Снять уведомление о письме (прочитано или удалено в приложении).
  Future<void> cancelEmail(String accountId, String emailId) =>
      cancelScheduled(notificationIdForEmail(accountId, emailId));

  /// Запланировать отложенное уведомление о письме на конкретное время через ОС
  /// (срабатывает даже при полностью выгруженном приложении — AlarmManager/APNs).
  /// Планируем по абсолютному моменту (UTC), поэтому не зависим от имени часового пояса.
  /// Снуз письма. Через общий _schedule — значит с тем же фолбэком на неточное
  /// планирование, если нет разрешения на точные будильники.
  /// «Посмотреть позже»: письмо вернулось. Кнопки — отложить ещё раз,
  /// не открывая приложение.
  Future<void> scheduleEmailReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) {
    // Политика организации «без содержимого» (MDM, 1.10.5) — и в
    // напоминании «Посмотреть позже» (1.12.x, аудит экрана блокировки):
    // там отправитель и тема письма.
    final hide = ManagedPolicy.fromPrefs(_prefs).hideNotificationContent;
    return _schedule(
        id: id,
        title: hide ? _t('ntfChSnooze') : title,
        body: hide ? _t('newMessage') : body,
        when: when,
        channelId: 'email_reminders',
        channelName: _t('ntfChSnooze'),
        channelDesc: _t('ntfChSnoozeDesc'),
        payload: payload,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction('later_1h', _t('laterIn1h')),
          AndroidNotificationAction('later_tomorrow', _t('laterTomorrow')),
        ],
      );
  }

  /// Напоминание о встрече: срабатывает за `minutesBefore` до начала.
  /// Тихие часы намеренно НЕ применяются — встречу пропускать нельзя.
  Future<void> scheduleEventReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    /// Есть ссылка на онлайн-встречу — кнопка «Подключиться».
    bool canJoin = false,
    /// «Будильником» Android (настройка календаря, по умолчанию включено).
    bool alarmClock = true,
    /// Ящик, чья это встреча (несколько ящиков, 2.3.2): в шапке уведомления.
    String? mailbox,
  }) => _schedule(
        id: id,
        title: title,
        body: body,
        when: when,
        subText: mailbox,
        channelId: 'event_reminders',
        channelName: _t('ntfChMeetings'),
        channelDesc: _t('ntfChMeetingsDesc'),
        payload: payload,
        category: AndroidNotificationCategory.event,
        // Встреча — время критично: «будильник» срабатывает точно даже в
        // глубоком сне и не откладывается оболочками производителей. Обычный
        // точный сигнал HyperOS/MIUI и ColorOS задерживали на 10–15 минут
        // («Начинается сейчас» приходило в 17:13 о встрече в 17:00).
        alarmClock: alarmClock,
        actions: [
          if (canJoin)
            AndroidNotificationAction('join', _t('ntfJoin'), showsUserInterface: true),
          AndroidNotificationAction('snooze', _t('ntfSnooze10')),
        ],
      );

  /// Напоминание о задаче (по сроку). Тихие часы не применяются.
  Future<void> scheduleTaskReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    /// Ящик, чья это задача (несколько ящиков, 2.3.2): в шапке уведомления.
    String? mailbox,
  }) => _schedule(
        id: id,
        title: title,
        body: body,
        when: when,
        subText: mailbox,
        channelId: 'task_reminders',
        channelName: _t('ntfChTasks'),
        channelDesc: _t('ntfChTasksDesc'),
        payload: payload,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction('task_done', _t('ntfTaskDone')),
          AndroidNotificationAction('snooze', _t('ntfSnooze1h')),
        ],
      );

  /// Утренняя сводка: одно тихое уведомление в выбранное время («3 встречи,
  /// 2 задачи, 4 письма на контроле»), нажатие открывает «Мой день».
  Future<void> scheduleDigest({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
  }) => _schedule(
        id: id,
        title: title,
        body: body,
        when: when,
        // Со звуком (09.10.2026): тихую сводку в 8:00 не замечали — время
        // пользователь выбирает сам, значит, ждёт уведомления. Новый id
        // канала: настройки старого («без звука») Android не даёт изменить.
        channelId: 'morning_digest_v2',
        channelName: _t('ntfChDigest'),
        channelDesc: _t('ntfChDigestDesc'),
        payload: payload,
        category: AndroidNotificationCategory.reminder,
      );

  /// Общая часть планирования: время уже должно быть в будущем.
  Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String channelId,
    required String channelName,
    required String channelDesc,
    String? payload,
    List<AndroidNotificationAction> actions = const [],
    AndroidNotificationCategory? category,
    bool alarmClock = false,
    /// Без звука и вибрации, обычная важность (сводка, а не напоминание).
    bool quiet = false,
    /// Подпись в шапке уведомления (ящик): Android — рядом с названием
    /// приложения, iPhone и Mac — подзаголовок.
    String? subText,
  }) async {
    if (_skipOnThisPlatform()) return;
    if (!_initialized) await initialize();
    if (when.isBefore(DateTime.now())) return; // прошедшее не планируем

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: quiet ? Importance.defaultImportance : Importance.high,
        priority: quiet ? Priority.defaultPriority : Priority.high,
        playSound: !quiet && _soundOn,
        enableVibration: !quiet && _vibrationOn,
        category: category,
        actions: actions.isEmpty ? null : actions,
        subText: subText,
        styleInformation: BigTextStyleInformation(body, summaryText: subText),
      ),
      iOS: DarwinNotificationDetails(presentSound: !quiet && _soundOn, subtitle: subText),
    );
    final at = tz.TZDateTime.from(when.toUtc(), tz.UTC);

    Future<void> put(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id, title, body, at, details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );

    try {
      await put(alarmClock ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // Android 13+ НЕ выдаёт разрешение на точные будильники по умолчанию, а
      // пользователь может его отозвать. Без обработки напоминание просто не
      // приходило бы — молча. Планируем неточно: сдвиг в несколько минут
      // несравнимо лучше пропущенной встречи.
      if (e.code == 'exact_alarms_not_permitted') {
        try {
          await put(AndroidScheduleMode.inexactAllowWhileIdle);
          AppLogger.info(
              'Напоминание ($channelId) запланировано НЕточно: нет разрешения '
              'на точные будильники');
        } catch (e2) {
          AppLogger.warning('scheduleReminder ($channelId) inexact failed: $e2');
        }
      } else {
        AppLogger.warning('scheduleReminder ($channelId) failed: ${e.code} ${e.message}');
      }
    } catch (e) {
      AppLogger.warning('scheduleReminder ($channelId) failed: $e');
    }
  }

  /// Отменить запланированное уведомление (при снятии/переносе напоминания).
  Future<void> cancelScheduled(int id) async {
    if (_skipOnThisPlatform()) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      AppLogger.warning('cancelScheduled failed: $e');
    }
  }

  /// Payload уведомления, нажатием на которое запущено приложение
  /// (холодный старт). Кнопки уведомлений сюда не попадают.
  Future<String?> launchPayload() async {
    if (_skipOnThisPlatform()) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d == null || !d.didNotificationLaunchApp) return null;
      final r = d.notificationResponse;
      if (r == null || (r.actionId ?? '').isNotEmpty) return null;
      // Намерение разобрано — гасим его (Android): иначе следующий возврат
      // на экран снова открыл бы то же письмо. См. MainActivity, канал
      // ogneliss/launch_intent.
      if (Platform.isAndroid) {
        try {
          await const MethodChannel('ogneliss/launch_intent').invokeMethod<void>('consume');
        } catch (_) {}
      }
      return r.payload;
    } catch (_) {
      return null;
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Точные будильники здесь не запрашиваются: запрос открывает экран
      // настроек Android. Это делается из «Настройки → Разрешения».
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return true;
  }

  Future<void> showReminderNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (_skipOnThisPlatform()) return;
    if (!_initialized) await initialize();
    await _plugin.show(
      id, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders', _t('ntfChReminders'),
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true),
      ),
      payload: payload,
    );
  }

  /// Payload уведомления для журнала: тип и ключи, без темы и адресов.
  static String payloadSummary(String? payload) {
    if (payload == null || payload.isEmpty) return '—';
    if (!payload.startsWith('{')) {
      final i = payload.indexOf(':');
      return i < 0 ? payload : payload.substring(0, i);
    }
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return [
        m['type'] ?? 'email',
        for (final k in const ['emailId', 'folderId', 'id']) if (m[k] != null) '$k=${m[k]}',
      ].join(' ');
    } catch (_) {
      return '?';
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    // Без темы и адреса из payload (1.8.12): журнал уходит в поддержку.
    AppLogger.info('Notification action: ${response.actionId} / ${payloadSummary(response.payload)}');
    onResponse?.call(response.actionId ?? '', response.payload, response.input);
  }
}

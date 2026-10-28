// lib/features/settings/providers/settings_provider.dart
// Провайдер настроек с поддержкой:
// - Режим загрузки писем (fetchMode)
// - Настройки свайпов
// - Вкл/выкл модулей (ИИ, шаблоны, DLP)
// - Конфигурация для каждой платформы

import '../../../core/platform/orientation_policy.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/providers/shared_prefs_provider.dart';
import '../../../l10n/app_localizations.dart' show AppLocalizations;

/// Режим загрузки писем
enum EmailFetchMode {
  full,            // Полное письмо с вложениями
  noAttachments,   // Тело без вложений (по умолчанию)
  headersOnly,     // Только заголовки — тело при открытии
  partial500k,     // Первые 500 КБ
  partial100k,     // Первые 100 КБ
  partial50k,      // Первые 50 КБ
}

/// Действие свайпа
/// Действия, назначаемые на свайпы в списке писем.
///
/// Список намеренно ограничен тем, что реально используют при разборе почты:
/// добавлять все возможные операции — значит превратить настройку в простыню,
/// в которой пользователь не разберётся. Порядок соответствует частоте
/// применения.
enum SwipeAction {
  markRead,
  flag,
  archive,
  delete,
  moveToJunk,
  moveTo,       // выбор папки
  snooze,       // отложить (напомнить позже)
  reply,
  forward,
  createTask,   // задача из письма
  findBySender, // все письма отправителя
  none,
  // Новые — только в конец: в настройках хранится номер действия.
  control,      // «На контроле» — поставить/снять
}

/// Модель настроек
/// Выбор темы для UI. [reading] — «Чтение»: светлая тёплая «бумага» во
/// всём приложении (меньше синего, мягкий контраст для долгого чтения).
enum AppThemeChoice { system, light, dark, amoled, reading }

class AppSettings {
  // ── Общие ──
  final ThemeMode themeMode;
  final bool amoled; // AMOLED-вариант тёмной темы (чистый чёрный)
  /// Тема «Чтение» (тёплая светлая). Вместе с ней themeMode = light.
  final bool reading;
  /// Цвета от обоев (Android 12+, Material You). Выключено — фирменные цвета.
  final bool dynamicColor;
  /// Поворот экрана на телефоне (на планшете разрешён всегда).
  final bool allowRotation;
  /// Тёплый (кремовый) фон письма в светлой теме.
  final bool warmPage;
  /// «На контроле»: пункты в письме и списке, проверка ответов, раздел в
  /// «Моём дне». Выключено — всё скрыто, отметки сохраняются.
  final bool mailControl;
  /// Вкладка «Мой день» (в «Ещё»).
  final bool myDay;
  /// Утренняя сводка — одно уведомление в [morningDigestMinutes] (минуты от
  /// полуночи). Выключено по умолчанию.
  final bool morningDigest;
  final int morningDigestMinutes;
  final Locale locale;
  final double fontScale;
  /// Масштаб интерфейса (1.6.12): 0 — авто по ширине экрана и шрифту
  /// (UiZoom.auto), иначе — выбранный вручную (0,85…1,1).
  final double uiScale;
  final bool isFirstLaunch;
  final bool licenseAccepted;

  // ── Доступность ──
  final bool highContrast;
  final bool dyslexiaFont;
  final bool reduceMotion;
  /// Анимации интерфейса: переходы между экранами, появление строк, общий
  /// аватар «список → письмо». Выключено по умолчанию (07.10.2026 выглядели
  /// рваными); «Уменьшить движение» и системная настройка важнее.
  final bool uiAnimations;
  final int colorBlindMode;

  // ── Уведомления ──
  final bool notificationsEnabled;
  final bool notificationSound;
  final bool notificationVibration;

  // ── Синхронизация ──
  final bool syncOnlyWifi;
  /// Держать приложение живым в фоне (Android foreground service).
  final bool backgroundKeepAlive;
  final int syncIntervalMinutes;

  // ── Загрузка писем ──
  final EmailFetchMode emailFetchMode;

  /// Предзагружать вложения только по Wi-Fi. Действует, когда режим загрузки —
  /// «полное письмо с вложениями»: по мобильной сети это дорого и незаметно
  /// съедает трафик.
  final bool attachmentsWifiOnly;
  final bool groupByConversation;

  // ── Свайпы ──
  final SwipeAction swipeLeftPrimary;
  final SwipeAction swipeLeftSecondary;
  final SwipeAction swipeRightPrimary;
  final SwipeAction swipeRightSecondary;
  /// Свайпы в беседе — свои, по одному на сторону (полный свайп выполняет).
  final SwipeAction swipeConvLeft;
  final SwipeAction swipeConvRight;
  /// «Разобрать входящие»: свой набор (как у беседы) или как в ленте —
  /// первые действия свайпа вправо и влево (10.10.2026).
  final bool swipeTriageCustom;
  final SwipeAction swipeTriageLeft;
  final SwipeAction swipeTriageRight;
  /// Живой свайп (1.6.21): значок действия виден с первых миллиметров,
  /// проявляется и растёт по мере свайпа, у порога срабатывания — отклик и
  /// лёгкая вибрация. Выключается в настройках свайпов.
  final bool swipeAnimated;

  /// Строк текста письма под темой в ленте (1–4, по умолчанию 1) и в
  /// карточке по удержанию (по умолчанию 3), 1.6.31. Пустые строки письма
  /// пропускаются, переносы сохраняются.
  final int previewLines;
  final int peekPreviewLines;

  /// Свайпы разбора с учётом «как в ленте»: (вправо, влево).
  (SwipeAction, SwipeAction) get triageSwipes => swipeTriageCustom
      ? (swipeTriageLeft, swipeTriageRight)
      : (swipeLeftPrimary, swipeRightPrimary);

  // ── Модули (вкл/выкл) ──
  final bool dlpEnabled;
  final bool autoRulesEnabled;

  // ── Аккаунт ──
  final String? activeAccountId;
  final int autoLockMinutes;

  // ── Подпись ──
  final bool autoInsertSignature;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.amoled = false,
    this.reading = false,
    this.dynamicColor = true,
    this.allowRotation = false,
    this.warmPage = false,
    this.mailControl = true,
    this.myDay = true,
    this.morningDigest = false,
    this.morningDigestMinutes = 8 * 60,
    this.locale = const Locale('ru'),
    this.fontScale = 1.0,
    this.uiScale = 0,
    this.isFirstLaunch = true,
    this.licenseAccepted = false,
    this.highContrast = false,
    this.dyslexiaFont = false,
    this.reduceMotion = false,
    this.uiAnimations = false,
    this.colorBlindMode = 0,
    this.notificationsEnabled = true,
    this.notificationSound = true,
    this.notificationVibration = true,
    this.syncOnlyWifi = false,
    this.backgroundKeepAlive = true,
    this.syncIntervalMinutes = 15,
    this.emailFetchMode = EmailFetchMode.noAttachments,
    this.groupByConversation = true,
    this.swipeLeftPrimary = SwipeAction.markRead,
    this.swipeLeftSecondary = SwipeAction.flag,
    this.swipeRightPrimary = SwipeAction.archive,
    this.swipeRightSecondary = SwipeAction.delete,
    this.swipeConvLeft = SwipeAction.markRead,
    this.swipeConvRight = SwipeAction.delete,
    this.swipeTriageCustom = false,
    this.swipeAnimated = true,
    this.previewLines = 1,
    this.peekPreviewLines = 3,
    this.swipeTriageLeft = SwipeAction.archive,
    this.swipeTriageRight = SwipeAction.delete,
    this.dlpEnabled = true,
    this.autoRulesEnabled = true,
    this.activeAccountId,
    this.autoLockMinutes = 5,
    this.autoInsertSignature = true,
    this.attachmentsWifiOnly = true,
  });

  /// Текущий выбор темы из themeMode + amoled.
  AppThemeChoice get themeChoice {
    if (reading) return AppThemeChoice.reading;
    if (amoled) return AppThemeChoice.amoled;
    switch (themeMode) {
      case ThemeMode.light: return AppThemeChoice.light;
      case ThemeMode.dark: return AppThemeChoice.dark;
      case ThemeMode.system: return AppThemeChoice.system;
    }
  }

  AppSettings copyWith({
    bool? attachmentsWifiOnly,
    ThemeMode? themeMode,
    bool? amoled,
    bool? reading,
    bool? dynamicColor,
    bool? allowRotation,
    bool? warmPage,
    bool? mailControl,
    bool? myDay,
    bool? morningDigest,
    int? morningDigestMinutes,
    Locale? locale,
    double? fontScale,
    double? uiScale,
    bool? isFirstLaunch,
    bool? licenseAccepted,
    bool? highContrast,
    bool? dyslexiaFont,
    bool? reduceMotion,
    bool? uiAnimations,
    int? colorBlindMode,
    bool? notificationsEnabled,
    bool? notificationSound,
    bool? notificationVibration,
    bool? syncOnlyWifi,
    bool? backgroundKeepAlive,
    int? syncIntervalMinutes,
    EmailFetchMode? emailFetchMode,
    bool? groupByConversation,
    SwipeAction? swipeLeftPrimary,
    SwipeAction? swipeLeftSecondary,
    SwipeAction? swipeRightPrimary,
    SwipeAction? swipeRightSecondary,
    SwipeAction? swipeConvLeft,
    SwipeAction? swipeConvRight,
    bool? swipeTriageCustom,
    bool? swipeAnimated,
    int? previewLines,
    int? peekPreviewLines,
    SwipeAction? swipeTriageLeft,
    SwipeAction? swipeTriageRight,
    bool? dlpEnabled,
    bool? autoRulesEnabled,
    String? activeAccountId,
    int? autoLockMinutes,
    bool? autoInsertSignature,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      amoled: amoled ?? this.amoled,
      reading: reading ?? this.reading,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      allowRotation: allowRotation ?? this.allowRotation,
      warmPage: warmPage ?? this.warmPage,
      mailControl: mailControl ?? this.mailControl,
      myDay: myDay ?? this.myDay,
      morningDigest: morningDigest ?? this.morningDigest,
      morningDigestMinutes: morningDigestMinutes ?? this.morningDigestMinutes,
      locale: locale ?? this.locale,
      fontScale: fontScale ?? this.fontScale,
      uiScale: uiScale ?? this.uiScale,
      isFirstLaunch: isFirstLaunch ?? this.isFirstLaunch,
      licenseAccepted: licenseAccepted ?? this.licenseAccepted,
      highContrast: highContrast ?? this.highContrast,
      dyslexiaFont: dyslexiaFont ?? this.dyslexiaFont,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      uiAnimations: uiAnimations ?? this.uiAnimations,
      colorBlindMode: colorBlindMode ?? this.colorBlindMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationSound: notificationSound ?? this.notificationSound,
      notificationVibration: notificationVibration ?? this.notificationVibration,
      syncOnlyWifi: syncOnlyWifi ?? this.syncOnlyWifi,
      backgroundKeepAlive: backgroundKeepAlive ?? this.backgroundKeepAlive,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      emailFetchMode: emailFetchMode ?? this.emailFetchMode,
      attachmentsWifiOnly: attachmentsWifiOnly ?? this.attachmentsWifiOnly,
      groupByConversation: groupByConversation ?? this.groupByConversation,
      swipeLeftPrimary: swipeLeftPrimary ?? this.swipeLeftPrimary,
      swipeLeftSecondary: swipeLeftSecondary ?? this.swipeLeftSecondary,
      swipeRightPrimary: swipeRightPrimary ?? this.swipeRightPrimary,
      swipeRightSecondary: swipeRightSecondary ?? this.swipeRightSecondary,
      swipeConvLeft: swipeConvLeft ?? this.swipeConvLeft,
      swipeConvRight: swipeConvRight ?? this.swipeConvRight,
      swipeTriageCustom: swipeTriageCustom ?? this.swipeTriageCustom,
      swipeAnimated: swipeAnimated ?? this.swipeAnimated,
      previewLines: previewLines ?? this.previewLines,
      peekPreviewLines: peekPreviewLines ?? this.peekPreviewLines,
      swipeTriageLeft: swipeTriageLeft ?? this.swipeTriageLeft,
      swipeTriageRight: swipeTriageRight ?? this.swipeTriageRight,
      dlpEnabled: dlpEnabled ?? this.dlpEnabled,
      autoRulesEnabled: autoRulesEnabled ?? this.autoRulesEnabled,
      activeAccountId: activeAccountId ?? this.activeAccountId,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
      autoInsertSignature: autoInsertSignature ?? this.autoInsertSignature,
    );
  }
}

/// Ключи SharedPreferences
class _K {
  static const themeMode = 's_theme';
  static const amoled = 's_amoled';
  static const reading = 's_reading';
  static const dynamicColor = 's_dynamic_color';
  // Читает и OrientationPolicy (до создания провайдеров).
  static const allowRotation = 's_allow_rotation';
  static const warmPage = 's_warm_page';
  static const mailControl = 's_mail_control';
  static const myDay = 's_my_day';
  // Те же ключи читает ReminderSchedulerService (фоновая синхронизация).
  static const morningDigest = 's_morning_digest';
  static const morningDigestMinutes = 's_morning_digest_min';
  static const locale = 's_locale';
  static const fontScale = 's_font_scale';
  static const uiScale = 's_ui_scale';
  static const isFirstLaunch = 's_first_launch';
  static const licenseAccepted = 's_license_accepted';
  static const highContrast = 's_high_contrast';
  static const dyslexiaFont = 's_dyslexia';
  static const reduceMotion = 's_reduce_motion';
  static const uiAnimations = 's_ui_animations';
  static const colorBlindMode = 's_color_blind';
  static const notificationsEnabled = 's_notif_on';
  static const notificationSound = 's_notif_sound';
  static const notificationVibration = 's_notif_vib';
  static const syncOnlyWifi = 's_sync_wifi';
  // v2: прежний ключ в ранних сборках включался по умолчанию, и постоянное
  // уведомление появлялось без ведома пользователя. Новый ключ — выбор
  // сделан осознанно (по умолчанию выключено).
  static const backgroundKeepAlive = 's_bg_keep_alive_v2';
  static const syncInterval = 's_sync_interval';
  static const emailFetchMode = 's_fetch_mode';
  static const attachmentsWifiOnly = 's_att_wifi_only';
  static const groupByConversation = 's_group_conv';
  static const swipeLP = 's_swipe_lp';
  static const swipeLS = 's_swipe_ls';
  static const swipeRP = 's_swipe_rp';
  static const swipeRS = 's_swipe_rs';
  static const swipeCL = 's_swipe_conv_l';
  static const swipeCR = 's_swipe_conv_r';
  static const swipeTC = 's_swipe_triage_custom';
  static const swipeAnim = 's_swipe_animated';
  static const previewLines = 's_preview_lines';
  static const peekPreviewLines = 's_peek_preview_lines';
  static const swipeTL = 's_swipe_triage_l';
  static const swipeTR = 's_swipe_triage_r';
  static const aiEnabled = 's_ai_on';
  static const smartReplies = 's_smart_replies';
  static const dlpEnabled = 's_dlp_on';
  static const autoRules = 's_auto_rules';
  static const voiceControl = 's_voice';
  static const activeAccount = 's_active_acc';
  static const autoLock = 's_auto_lock';
  static const autoSignature = 's_auto_sig';
}

/// Провайдер настроек
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return SettingsNotifier(prefs);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _p;

  SettingsNotifier(this._p) : super(const AppSettings()) {
    _load();
  }

  /// Язык интерфейса: сохранённый, если он поддерживается; иначе — язык
  /// системы (ru/en/de/fr), иначе английский. Раньше по умолчанию всегда
  /// был русский, а сохранённые es/it/zh (их не было в переводах)
  /// показывали русский интерфейс.
  static String _initialLanguage(String? saved) {
    // Языки — по файлам assets/l10n/*.xml (1.7.3).
    final supported = AppLocalizations.supportedCodes;
    if (saved != null && supported.contains(saved)) return saved;
    final system = ui.PlatformDispatcher.instance.locale.languageCode;
    return supported.contains(system) ? system : 'en';
  }

  void _load() {
    state = AppSettings(
      themeMode: ThemeMode.values[(_p.getInt(_K.themeMode) ?? 0).clamp(0, 2)],
      amoled: _p.getBool(_K.amoled) ?? false,
      reading: _p.getBool(_K.reading) ?? false,
      dynamicColor: _p.getBool(_K.dynamicColor) ?? true,
      allowRotation: _p.getBool(_K.allowRotation) ?? false,
      warmPage: _p.getBool(_K.warmPage) ?? false,
      mailControl: _p.getBool(_K.mailControl) ?? true,
      myDay: _p.getBool(_K.myDay) ?? true,
      morningDigest: _p.getBool(_K.morningDigest) ?? false,
      morningDigestMinutes: _p.getInt(_K.morningDigestMinutes) ?? 8 * 60,
      locale: Locale(_initialLanguage(_p.getString(_K.locale))),
      fontScale: _p.getDouble(_K.fontScale) ?? 1.0,
      uiScale: _p.getDouble(_K.uiScale) ?? 0,
      isFirstLaunch: _p.getBool(_K.isFirstLaunch) ?? true,
      licenseAccepted: _p.getBool(_K.licenseAccepted) ?? false,
      highContrast: _p.getBool(_K.highContrast) ?? false,
      dyslexiaFont: _p.getBool(_K.dyslexiaFont) ?? false,
      reduceMotion: _p.getBool(_K.reduceMotion) ?? false,
      uiAnimations: _p.getBool(_K.uiAnimations) ?? false,
      colorBlindMode: _p.getInt(_K.colorBlindMode) ?? 0,
      notificationsEnabled: _p.getBool(_K.notificationsEnabled) ?? true,
      notificationSound: _p.getBool(_K.notificationSound) ?? true,
      notificationVibration: _p.getBool(_K.notificationVibration) ?? true,
      syncOnlyWifi: _p.getBool(_K.syncOnlyWifi) ?? false,
      // По умолчанию включено: у новых ящиков режим «Мгновенно», и без
      // фоновой работы push в свёрнутом приложении не работал вовсе.
      // Сервис запускается только при ящиках с push (keepAliveNeeded).
      backgroundKeepAlive: _p.getBool(_K.backgroundKeepAlive) ?? true,
      syncIntervalMinutes: _p.getInt(_K.syncInterval) ?? 15,
      emailFetchMode: EmailFetchMode.values[(_p.getInt(_K.emailFetchMode) ?? 1).clamp(0, 5)],
      attachmentsWifiOnly: _p.getBool(_K.attachmentsWifiOnly) ?? true,
      groupByConversation: _p.getBool(_K.groupByConversation) ?? true,
      swipeLeftPrimary: SwipeAction.values[_p.getInt(_K.swipeLP) ?? 0],
      swipeLeftSecondary: SwipeAction.values[_p.getInt(_K.swipeLS) ?? 1],
      swipeRightPrimary: SwipeAction.values[_p.getInt(_K.swipeRP) ?? 2],
      swipeRightSecondary: SwipeAction.values[_p.getInt(_K.swipeRS) ?? 3],
      swipeConvLeft: SwipeAction.values[(_p.getInt(_K.swipeCL) ?? 0).clamp(0, SwipeAction.values.length - 1)],
      swipeConvRight: SwipeAction.values[(_p.getInt(_K.swipeCR) ?? 3).clamp(0, SwipeAction.values.length - 1)],
      swipeTriageCustom: _p.getBool(_K.swipeTC) ?? false,
      swipeAnimated: _p.getBool(_K.swipeAnim) ?? true,
      previewLines: (_p.getInt(_K.previewLines) ?? 1).clamp(1, 4),
      peekPreviewLines: (_p.getInt(_K.peekPreviewLines) ?? 3).clamp(1, 4),
      swipeTriageLeft: SwipeAction.values[(_p.getInt(_K.swipeTL) ?? SwipeAction.archive.index).clamp(0, SwipeAction.values.length - 1)],
      swipeTriageRight: SwipeAction.values[(_p.getInt(_K.swipeTR) ?? SwipeAction.delete.index).clamp(0, SwipeAction.values.length - 1)],
      dlpEnabled: _p.getBool(_K.dlpEnabled) ?? true,
      autoRulesEnabled: _p.getBool(_K.autoRules) ?? true,
      activeAccountId: _p.getString(_K.activeAccount),
      autoLockMinutes: _p.getInt(_K.autoLock) ?? 5,
      autoInsertSignature: _p.getBool(_K.autoSignature) ?? true,
    );
  }

  // ── Сеттеры (каждый сохраняет в SharedPreferences) ──
  Future<void> setThemeMode(ThemeMode v) async {
    await _p.setInt(_K.themeMode, v.index);
    state = state.copyWith(themeMode: v);
  }

  Future<void> setAmoled(bool v) async {
    await _p.setBool(_K.amoled, v);
    state = state.copyWith(amoled: v);
  }

  Future<void> _setReading(bool v) async {
    await _p.setBool(_K.reading, v);
    state = state.copyWith(reading: v);
  }

  Future<void> setMailControl(bool v) async {
    await _p.setBool(_K.mailControl, v);
    state = state.copyWith(mailControl: v);
  }

  Future<void> setMyDay(bool v) async {
    await _p.setBool(_K.myDay, v);
    state = state.copyWith(myDay: v);
  }

  Future<void> setMorningDigest(bool v) async {
    await _p.setBool(_K.morningDigest, v);
    state = state.copyWith(morningDigest: v);
  }

  Future<void> setMorningDigestMinutes(int v) async {
    await _p.setInt(_K.morningDigestMinutes, v);
    state = state.copyWith(morningDigestMinutes: v);
  }

  Future<void> setDynamicColor(bool v) async {
    await _p.setBool(_K.dynamicColor, v);
    state = state.copyWith(dynamicColor: v);
  }

  Future<void> setAllowRotation(bool v) async {
    await _p.setBool(_K.allowRotation, v);
    state = state.copyWith(allowRotation: v);
    await OrientationPolicy.apply(force: true);
  }

  Future<void> setWarmPage(bool v) async {
    await _p.setBool(_K.warmPage, v);
    state = state.copyWith(warmPage: v);
  }

  /// Единый выбор темы (Система / Светлая / Тёмная / AMOLED / Чтение).
  Future<void> setThemeChoice(AppThemeChoice c) async {
    await _setReading(c == AppThemeChoice.reading);
    switch (c) {
      case AppThemeChoice.reading:
        await setThemeMode(ThemeMode.light);
        await setAmoled(false);
        break;
      case AppThemeChoice.system:
        await setThemeMode(ThemeMode.system);
        await setAmoled(false);
        break;
      case AppThemeChoice.light:
        await setThemeMode(ThemeMode.light);
        await setAmoled(false);
        break;
      case AppThemeChoice.dark:
        await setThemeMode(ThemeMode.dark);
        await setAmoled(false);
        break;
      case AppThemeChoice.amoled:
        await setThemeMode(ThemeMode.dark);
        await setAmoled(true);
        break;
    }
  }

  Future<void> setLocale(Locale v) async {
    await _p.setString(_K.locale, v.languageCode);
    state = state.copyWith(locale: v);
  }

  Future<void> setFontScale(double v) async {
    final clamped = v.clamp(0.8, 2.0);
    await _p.setDouble(_K.fontScale, clamped);
    state = state.copyWith(fontScale: clamped);
  }

  /// 0 — авто; иначе 0,85…1,1.
  Future<void> setUiScale(double v) async {
    final value = v <= 0 ? 0.0 : v.clamp(0.85, 1.1).toDouble();
    await _p.setDouble(_K.uiScale, value);
    state = state.copyWith(uiScale: value);
  }

  Future<void> markFirstLaunchDone() async {
    await _p.setBool(_K.isFirstLaunch, false);
    state = state.copyWith(isFirstLaunch: false);
  }

  Future<void> acceptLicense() async {
    await _p.setBool(_K.licenseAccepted, true);
    state = state.copyWith(licenseAccepted: true);
  }

  Future<void> setHighContrast(bool v) async {
    await _p.setBool(_K.highContrast, v);
    state = state.copyWith(highContrast: v);
  }

  Future<void> setDyslexiaFont(bool v) async {
    await _p.setBool(_K.dyslexiaFont, v);
    state = state.copyWith(dyslexiaFont: v);
  }

  Future<void> setReduceMotion(bool v) async {
    await _p.setBool(_K.reduceMotion, v);
    state = state.copyWith(reduceMotion: v);
  }

  Future<void> setUiAnimations(bool v) async {
    await _p.setBool(_K.uiAnimations, v);
    state = state.copyWith(uiAnimations: v);
  }

  Future<void> setColorBlindMode(int v) async {
    await _p.setInt(_K.colorBlindMode, v);
    state = state.copyWith(colorBlindMode: v);
  }

  Future<void> setNotificationsEnabled(bool v) async {
    await _p.setBool(_K.notificationsEnabled, v);
    state = state.copyWith(notificationsEnabled: v);
  }

  Future<void> setNotificationSound(bool v) async {
    await _p.setBool(_K.notificationSound, v);
    state = state.copyWith(notificationSound: v);
  }

  Future<void> setNotificationVibration(bool v) async {
    await _p.setBool(_K.notificationVibration, v);
    state = state.copyWith(notificationVibration: v);
  }

  Future<void> setSyncOnlyWifi(bool v) async {
    await _p.setBool(_K.syncOnlyWifi, v);
    state = state.copyWith(syncOnlyWifi: v);
  }

  Future<void> setSyncInterval(int minutes) async {
    await _p.setInt(_K.syncInterval, minutes);
    state = state.copyWith(syncIntervalMinutes: minutes);
  }

  Future<void> setBackgroundKeepAlive(bool v) async {
    await _p.setBool(_K.backgroundKeepAlive, v);
    state = state.copyWith(backgroundKeepAlive: v);
  }

  Future<void> setEmailFetchMode(EmailFetchMode v) async {
    await _p.setInt(_K.emailFetchMode, v.index);
    state = state.copyWith(emailFetchMode: v);
  }

  Future<void> setAttachmentsWifiOnly(bool v) async {
    await _p.setBool(_K.attachmentsWifiOnly, v);
    state = state.copyWith(attachmentsWifiOnly: v);
  }

  Future<void> setPreviewLines(int v) async {
    final n = v.clamp(1, 4);
    await _p.setInt(_K.previewLines, n);
    state = state.copyWith(previewLines: n);
  }

  Future<void> setPeekPreviewLines(int v) async {
    final n = v.clamp(1, 4);
    await _p.setInt(_K.peekPreviewLines, n);
    state = state.copyWith(peekPreviewLines: n);
  }

  Future<void> setGroupByConversation(bool v) async {
    await _p.setBool(_K.groupByConversation, v);
    state = state.copyWith(groupByConversation: v);
  }

  Future<void> setSwipeLeftPrimary(SwipeAction v) async {
    await _p.setInt(_K.swipeLP, v.index);
    state = state.copyWith(swipeLeftPrimary: v);
  }

  Future<void> setSwipeLeftSecondary(SwipeAction v) async {
    await _p.setInt(_K.swipeLS, v.index);
    state = state.copyWith(swipeLeftSecondary: v);
  }

  Future<void> setSwipeRightPrimary(SwipeAction v) async {
    await _p.setInt(_K.swipeRP, v.index);
    state = state.copyWith(swipeRightPrimary: v);
  }

  Future<void> setSwipeRightSecondary(SwipeAction v) async {
    await _p.setInt(_K.swipeRS, v.index);
    state = state.copyWith(swipeRightSecondary: v);
  }

  Future<void> setSwipeConvLeft(SwipeAction v) async {
    await _p.setInt(_K.swipeCL, v.index);
    state = state.copyWith(swipeConvLeft: v);
  }

  Future<void> setSwipeConvRight(SwipeAction v) async {
    await _p.setInt(_K.swipeCR, v.index);
    state = state.copyWith(swipeConvRight: v);
  }

  Future<void> setSwipeTriageCustom(bool v) async {
    await _p.setBool(_K.swipeTC, v);
    // Включили свой набор — начинаем с того, что было в ленте.
    if (v && _p.getInt(_K.swipeTL) == null) {
      await setSwipeTriageLeft(state.swipeLeftPrimary);
      await setSwipeTriageRight(state.swipeRightPrimary);
    }
    state = state.copyWith(swipeTriageCustom: v);
  }

  Future<void> setSwipeAnimated(bool v) async {
    await _p.setBool(_K.swipeAnim, v);
    state = state.copyWith(swipeAnimated: v);
  }

  Future<void> setSwipeTriageLeft(SwipeAction v) async {
    await _p.setInt(_K.swipeTL, v.index);
    state = state.copyWith(swipeTriageLeft: v);
  }

  Future<void> setSwipeTriageRight(SwipeAction v) async {
    await _p.setInt(_K.swipeTR, v.index);
    state = state.copyWith(swipeTriageRight: v);
  }

  Future<void> setDlpEnabled(bool v) async {
    await _p.setBool(_K.dlpEnabled, v);
    state = state.copyWith(dlpEnabled: v);
  }

  Future<void> setAutoRulesEnabled(bool v) async {
    await _p.setBool(_K.autoRules, v);
    state = state.copyWith(autoRulesEnabled: v);
  }

  Future<void> setActiveAccountId(String? id) async {
    if (id != null) {
      await _p.setString(_K.activeAccount, id);
    } else {
      await _p.remove(_K.activeAccount);
    }
    state = state.copyWith(activeAccountId: id);
  }

  Future<void> setAutoLockMinutes(int v) async {
    await _p.setInt(_K.autoLock, v);
    state = state.copyWith(autoLockMinutes: v);
  }

  Future<void> setAutoInsertSignature(bool v) async {
    await _p.setBool(_K.autoSignature, v);
    state = state.copyWith(autoInsertSignature: v);
  }

  /// Сбросить все настройки
  Future<void> resetAll() async {
    final keys = [
      // AMOLED, «Работать в фоне» и «Вложения только по Wi-Fi» раньше
      // сбросом не затрагивались.
      _K.amoled, _K.reading, _K.dynamicColor, _K.allowRotation, _K.warmPage, _K.mailControl, _K.myDay, _K.morningDigest, _K.morningDigestMinutes, _K.backgroundKeepAlive, _K.attachmentsWifiOnly,
      _K.themeMode, _K.locale, _K.fontScale, _K.uiScale, _K.highContrast,
      _K.dyslexiaFont, _K.reduceMotion, _K.uiAnimations, _K.colorBlindMode,
      _K.notificationsEnabled, _K.notificationSound, _K.notificationVibration,
      _K.syncOnlyWifi, _K.syncInterval, _K.emailFetchMode,
      _K.groupByConversation, _K.swipeLP, _K.swipeLS, _K.swipeRP, _K.swipeRS, _K.swipeCL, _K.swipeCR, _K.swipeAnim, _K.previewLines, _K.peekPreviewLines,
      _K.aiEnabled, _K.smartReplies, _K.dlpEnabled, _K.autoRules,
      _K.voiceControl, _K.activeAccount, _K.autoLock, _K.autoSignature,
    ];
    for (final key in keys) {
      await _p.remove(key);
    }
    state = const AppSettings(isFirstLaunch: false);
  }
}

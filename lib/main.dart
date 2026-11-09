// lib/main.dart
// Точка входа приложения Ogneliss Mail.
// Разрешения ОС запрашиваются по месту использования (core/permissions).
// Инициализирует БД, SecureStorage, уведомления, фоновые задачи.
// Поддержка Android, iOS, Windows, macOS, Linux.

import 'core/platform/native_drag_drop.dart';
import 'core/platform/device_time_zone.dart';
import 'widgets/common/scroll_edge_fade.dart';
import 'services/widget_mail_actions.dart' show widgetMailActionsProvider;
import 'services/weather/weather_service.dart' show WeatherApi;
import 'services/documents/doc_preview_settings.dart';
import 'services/sync/sync_schedule.dart';
import 'core/theme/mail_page_color.dart' show mailPageWarm;
import 'core/platform/orientation_policy.dart';
import 'dart:io';
import 'core/theme/app_icons.dart';
import 'package:flutter/material.dart';
import 'core/theme/tokens.dart';
import 'core/platform/app_shortcuts.dart';
import 'services/home_widget_service.dart';
import 'services/calendar/quick_create_service.dart';
import 'widgets/common/quiet_scaffold_messenger.dart';
import 'widgets/common/inline_notice.dart' show InlineNoticeLayer;
import 'widgets/common/animated_appearance.dart' show uiAnimations;
import 'services/mail/own_addresses.dart';
import 'features/mail/message_window.dart';
import 'features/mail/message_window_host.dart';
import 'features/mail/widgets/mail_html_view.dart' show MailHtmlView;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'core/device/device_user_agent.dart';
import 'package:flutter/foundation.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/appearance.dart' show PresetSpec;
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'core/network/connectivity_service.dart';
import 'services/sync/sync_service.dart';
import 'core/navigation/app_router.dart';
import 'core/security/certificate_pinning_service.dart';
import 'core/network/app_http_overrides.dart';
import 'core/network/certificate_pinning_bridge.dart';
import 'data/database/app_database.dart';
import 'data/providers/database_provider.dart';
import 'data/providers/shared_prefs_provider.dart';
import 'l10n/app_localizations.dart';
import 'features/settings/providers/settings_provider.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/notification_action_handler.dart';
import 'services/notifications/email_reminder_service.dart';
import 'services/notifications/notification_router.dart';
import 'services/background/background_service.dart';
import 'services/integration/share_intent_service.dart';
import 'services/integration/mailto_service.dart';
import 'services/desktop/window_tray_service.dart';
import 'widgets/desktop/tray_window_listener.dart';
import 'services/mail/attachment_cache_service.dart';
import 'services/search/attachment_text_index.dart';
import 'services/mail/mention_scanner.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notifications/reminder_scheduler_service.dart';
import 'dart:async';
import 'services/sync/imap_push_service.dart';
import 'widgets/common/app_lock_gate.dart';
import 'core/security/trusted_ca_store.dart';
import 'core/security/account_ca_sync.dart';
import 'features/mail/providers/mail_providers.dart' show accountsProvider;
import 'features/compose/widgets/mail_editor.dart' show registerMailEditorLicense;
import 'services/translation/translator.dart' show registerTranslationLicense;
import 'widgets/common/text_scale_cap.dart';
import 'widgets/common/quick_long_press.dart' show HoldTiming;
import 'widgets/common/ui_zoom.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Глобальный контейнер Riverpod для фоновых сервисов
late ProviderContainer globalContainer;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // Окно письма на компьютере (1.9.x): свой движок Flutter — только показ
    // письма, без базы и служб приложения (message_window.dart).
    final windowMail = await MessageWindow.payloadOfThisEngine();
    if (windowMail != null) {
      runApp(MessageWindowApp(payload: windowMail));
      return;
    }
    registerMailEditorLicense();
    // Ядро перетаскивания на Rust (super_drag_and_drop, 1.15.0): лицензии крейтов.
    NativeDragDrop.registerLicenses();
    // Google ML Kit (перевод писем на Android, 1.9.x) — условия Google.
    registerTranslationLicense();
    // Погода в «Моём дне» (1.15.1): данные MET Norway (CC BY 4.0, NLOD 2.0) и
    // города GeoNames (CC BY 4.0) — через сервер Ogneliss; подписи источников.
    // Пока владелец не принял условия сервисов, погоды нет — и строк тоже.
    if (WeatherApi.termsAccepted) {
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(['MET Norway (weather data)'],
            'Weather forecasts in My Day come from the Norwegian Meteorological Institute '
            '(MET Norway), Locationforecast 2.0, used free of charge under its Terms of Service.\n'
            'Data licence: Creative Commons Attribution 4.0 International (CC BY 4.0) and the '
            'Norwegian Licence for Open Government Data (NLOD) 2.0.\n'
            'https://api.met.no/doc/License');
        yield const LicenseEntryWithLineBreaks(['GeoNames (city search)'],
            'City search for the weather uses the GeoNames geographical database '
            '(cities15000), licensed under Creative Commons Attribution 4.0 (CC BY 4.0).\n'
            'https://www.geonames.org/');
      });
    }
    // Шрифт интерфейса Roboto (Apache 2.0) — на странице «Лицензии».
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString('assets/fonts/pdf/Roboto-LICENSE.txt');
      yield LicenseEntryWithLineBreaks(const ['Roboto'], text);
    });
    // Шрифт для дислексии (SIL OFL 1.1 требует передавать лицензию вместе со
    // шрифтом) и лицензия самого приложения (Apache 2.0: LICENSE и NOTICE
    // должны быть видны и в собранных из кода версиях).
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString('assets/fonts/OpenDyslexic-OFL.txt');
      yield LicenseEntryWithLineBreaks(const ['OpenDyslexic'], text);
    });
    // Редактор писем HugeRTE (MIT) и DOMPurify в его сборке (Apache 2.0):
    // тексты — и в «Текстах лицензий» (1.8.13), а не только в файлах
    // assets/editor.
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString('assets/editor/LICENSE-hugerte.txt');
      yield LicenseEntryWithLineBreaks(const ['HugeRTE'], text);
      yield const LicenseEntryWithLineBreaks(['DOMPurify'],
          'Copyright 2024 Dr.-Ing. Mario Heiderich, Cure53 and other contributors.\n\n'
          'DOMPurify is dual-licensed under the Mozilla Public License 2.0 and the '
          'Apache License 2.0; it is used here under the Apache License 2.0 '
          '(full text: https://www.apache.org/licenses/LICENSE-2.0).\n'
          'Source: https://github.com/cure53/DOMPurify');
    });
    // Firebase Cloud Messaging (сигналы сервера на Android, 1.9.x) —
    // библиотека Android, а не пакет pub.dev: текст лицензии сам не попадает
    // в список. Apache 2.0 — тот же текст, что у приложения (LICENSE).
    if (!kIsWeb && Platform.isAndroid) {
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString('LICENSE');
        yield LicenseEntryWithLineBreaks(const ['Firebase Cloud Messaging'],
            'Firebase Android SDK (firebase-messaging and the Firebase libraries it uses)\n'
            'Copyright Google LLC. Licensed under the Apache License, Version 2.0.\n'
            'Source: https://github.com/firebase/firebase-android-sdk\n'
            'Uses Google Play services (Google APIs Terms of Service).\n\n$license');
        // Сигналы без сервисов Google (UnifiedPush, 1.10.x): connector и его
        // зависимости — Google Tink, сборка tink-android (Apache 2.0), и
        // protobuf lite внутри неё (BSD-3).
        yield LicenseEntryWithLineBreaks(const ['UnifiedPush connector'],
            'UnifiedPush android-connector\n'
            'Copyright UnifiedPush contributors. Licensed under the Apache License, Version 2.0.\n'
            'Source: https://codeberg.org/UnifiedPush/android-connector\n\n$license');
        yield LicenseEntryWithLineBreaks(const ['Tink'],
            'Tink Cryptography API (tink-android)\n'
            'Copyright Google LLC. Licensed under the Apache License, Version 2.0.\n'
            'Source: https://github.com/tink-crypto/tink-java\n\n$license');
        yield const LicenseEntryWithLineBreaks(['Protocol Buffers'], _protobufLicense);
        // Отчёт консоли MDM (2.2.0, MdmBridge.kt): KeyedAppStates.
        yield LicenseEntryWithLineBreaks(const ['AndroidX Enterprise Feedback'],
            'androidx.enterprise:enterprise-feedback 1.1.0 (Android Jetpack)\n'
            'Copyright The Android Open Source Project. Licensed under the Apache License, Version 2.0.\n'
            'Source: https://android.googlesource.com/platform/frameworks/support/+/androidx-main/enterprise\n\n$license');
      });
    }
    LicenseRegistry.addLicense(() async* {
      final notice = await rootBundle.loadString('NOTICE');
      final license = await rootBundle.loadString('LICENSE');
      yield LicenseEntryWithLineBreaks(const [AppConstants.appName], '$notice\n\n$license');
    });

    // Честный User-Agent из реальных системных данных (модель/ОС/версия) —
    // вычисляется один раз. Не блокирует старт надолго; при сбое — фолбэк.
    await DeviceUserAgent.warmUp();

    // Данные локалей для intl (DateFormat/NumberFormat с 'ru'/'en').
    // GlobalMaterialLocalizations инициализирует только ТЕКУЩУЮ локаль —
    // делаем явно для обеих, иначе форматирование чужой локалью упадёт.
    await initializeDateFormatting('ru');
    await initializeDateFormatting('en');
    await initializeDateFormatting('de');
    await initializeDateFormatting('fr');
    // Строки интерфейса (1.7.3 — файлы assets/l10n/<код>.xml): язык из
    // настроек или системы и английский — до первого кадра: их читают и
    // экраны, и службы без дерева виджетов (уведомления, трей).
    await AppLocalizations.load(_startLanguage(await SharedPreferences.getInstance()));

    // Ориентация: телефон — портрет; планшет и складной телефон — любая.
    // С targetSdk 36 Android сам игнорирует блокировку ориентации на экранах
    // от 600 dp, поэтому интерфейс планшета обязан работать и в альбомной.
    // Пересчитывается при раскрытии/складывании (MainShell.didChangeMetrics).
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await OrientationPolicy.apply();
      // Рисуем под системными панелями (edge-to-edge) на всех версиях Android,
      // а не только с 15-й, где это обязательно: одинаковый вид везде.
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    // Логирование — до окна и трея: ошибки их запуска тоже должны попасть в файл.
    await AppLogger.init();
    try {
      final info = await PackageInfo.fromPlatform();
      AppConstants.appVersion = '${info.version} (${info.buildNumber})';
    } catch (_) {}
    AppLogger.info('Запуск приложения ${AppConstants.appName} v${AppConstants.appVersion}');

    // Настройка окна для Desktop + сворачивание в трей
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      await WindowTrayService.init();
    }
    AppLogger.info('Платформа: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');

    // Глобальный перехват ошибок → в лог-файл (иначе рантайм-ошибки в виджетах и
    // async-колбэках не записываются). Дефолтное поведение (красный экран в
    // debug) сохраняем через presentError.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      AppLogger.error('FlutterError: ${details.exceptionAsString()}',
          details.exception, details.stack);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      AppLogger.error('Необработанная async-ошибка', error, stack);
      return true; // обработано — не роняем изолят
    };

    // SharedPreferences
    final sharedPrefs = await SharedPreferences.getInstance();
    AppLogger.loadSettings(sharedPrefs.getInt(AppLogger.detailedPrefsKey));
    // Все адреса владельцев ящиков (вход под одним адресом, ящик — под другим).
    OwnAddresses.load(sharedPrefs);
    // Широкие письма — по ширине экрана сразу или кнопкой (1.5.11).
    MailHtmlView.fitWide = sharedPrefs.getBool(MailHtmlView.fitWideKey) ?? false;
    // Какие документы показывать в приложении (1.11.x).
    DocPreviewSettings.load(sharedPrefs);
    SyncSchedule.load(sharedPrefs);
    // Имя пояса устройства — для приглашений Exchange (1.6.2).
    unawaited(DeviceTimeZone.load(sharedPrefs));
    // Удержание до карточки письма — 250 мс или системная задержка, если
    // она длиннее (спец. возможности Android, 1.6.46).
    unawaited(HoldTiming.init());

    // Certificate pinning (гибкие правила) + глобальный HttpOverrides
    final pinningService = CertificatePinningService(sharedPrefs);
    // Доверенные корпоративные CA-домены (по умолчанию пусто; настраивается).
    // В других организациях администратор настраивает свои правила/домены.
    if (pinningService.trustedCaDomains.isEmpty) {
      await pinningService.setTrustedCaDomains(
          <String>[]);
    }
    // Сертификат OAuth-прокси проверяется как у любого сайта (07.11.2026,
    // аудит безопасности): раньше хост прокси попадал в «доверенные домены»
    // и для него принимался ЛЮБОЙ сертификат — подмена в чужом Wi-Fi
    // получала бы refresh-токены. У ogneliss.ru — настоящий сертификат
    // (GlobalSign). Своя сборка с самоподписанным прокси — только явно:
    // --dart-define=OAUTH_PROXY_SELF_SIGNED=true (docs/guides/OWN_VERSION.md).
    if (AppConstants.oauthProxyBaseUrl.isNotEmpty) {
      try {
        final proxyHost = Uri.parse(AppConstants.oauthProxyBaseUrl).host;
        if (proxyHost.isNotEmpty) {
          // Убрать доверие, сохранённое прежними версиями.
          await pinningService.removeTrustedCaDomain(proxyHost);
          if (AppConstants.oauthProxySelfSigned) {
            await pinningService.ensureTrustedCaDomain(proxyHost, exactHost: true);
          }
        }
      } catch (_) {}
    }
    CertificatePinningBridge.instance = pinningService;
    HttpOverrides.global = AppHttpOverrides();
    // Дополнительные центры сертификации (Минцифры, установленные на
    // устройство, импортированные) — до первого сетевого запроса.
    await TrustedCaStore.init(sharedPrefs);

    // База данных. Ключ шифрования читаем заранее: если хранилище ключей
    // не готово, лучше сразу показать понятную причину, чем падать на
    // первом запросе к базе где-то внутри экранов.
    if (!kIsWeb) {
      try {
        await DbEncryption.getOrCreateKey();
      } catch (e) {
        throw DbKeyUnavailableException(e);
      }
    }
    final database = AppDatabase();

    // Глобальный контейнер
    globalContainer = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(sharedPrefs),
        databaseProvider.overrideWithValue(database),
        certPinningProvider.overrideWithValue(pinningService),
      ],
    );
    // ЦС Минцифры, включённый для отдельных ящиков, — по адресам их серверов.
    globalContainer.listen(accountsProvider, (_, next) => syncCaAccounts(next),
        fireImmediately: true);

    // Разрешения ОС при запуске НЕ запрашиваются: системный диалог до первого
    // кадра держал заставку (в журнале — минута ожидания), а точные будильники
    // открывали экран настроек при каждом запуске. Теперь — по месту
    // использования и один раз после входа (lib/core/permissions/app_permissions.dart).

    // Инициализация уведомлений
    try {
      final notificationService = globalContainer.read(notificationServiceProvider);
      await notificationService.initialize();
      // Восстановление связи → отправляем накопленное. Хук вешаем здесь, а не
      // внутри сервиса сети: иначе слой сети зависел бы от слоя синхронизации.
      // Без этого офлайн-очередь ждала бы ручного обновления, а пользователь
      // считал бы письма отправленными.
      final net = globalContainer.read(connectivityServiceProvider.notifier);
      Timer? netDebounce;
      net.onReconnected = () {
        AppLogger.info('Связь восстановлена — запускаем синхронизацию очереди');
        unawaited(globalContainer.read(syncServiceProvider).syncAll());
        // Push за время без сети мог умереть — проверить и поднять.
        unawaited(globalContainer.read(imapPushServiceProvider)
            .ensureAlive(poke: true, reason: 'связь восстановлена'));
      };
      // Смена сети (Wi-Fi ↔ мобильная): соединения push перезапускаются.
      // Пауза 5 с — при переключении сеть «мигает» несколько раз подряд.
      net.onNetworkChanged = () {
        netDebounce?.cancel();
        netDebounce = Timer(const Duration(seconds: 5), () {
          if (globalContainer.read(settingsProvider).syncIntervalMinutes < 0) return;
          unawaited(globalContainer.read(imapPushServiceProvider).restartAll(reason: 'смена сети'));
        });
      };
      // Локальные уведомления живут в расписании ОС — перевыставляем при старте:
      // за время простоя данные могли измениться (синк, правки на другом устройстве).
      // Не в момент запуска: первые секунды — отрисовка ленты и push; пересчёт
      // напоминаний (запросы к базе, вызовы AlarmManager) подождёт 8 с.
      unawaited(Future<void>.delayed(const Duration(seconds: 8),
          () => globalContainer.read(reminderSchedulerProvider).rescheduleAll(force: true)));
      // Push для IMAP-ящиков (IDLE на отдельном соединении). Раньше IDLE был
      // реализован, но не вызывался — письма приходили лишь по таймеру.
      // ...кроме режима синхронизации «Никогда» (-1), где push выключен.
      if (globalContainer.read(settingsProvider).syncIntervalMinutes >= 0) {
        unawaited(globalContainer.read(imapPushServiceProvider).start());
      }
      // Подключаем обработчик действий (ответить/флаг/архив/умный ответ).
      final actionHandler = globalContainer.read(notificationActionHandlerProvider);
      final notificationRouter = globalContainer.read(notificationRouterProvider);
      notificationService.onResponse = (actionId, payload, input) {
        // Нажатие на само уведомление — переход к письму/встрече/задаче;
        // кнопка — действие.
        if (actionId.isEmpty) {
          notificationRouter.open(payload);
        } else {
          actionHandler.handleAction(actionId, payload, input);
        }
      };
      // Приложение запущено нажатием на уведомление (процесс был выгружен).
      unawaited(notificationRouter.checkLaunch(notificationService));
      // Кнопки уведомлений, нажатые при выгруженном приложении (очередь из
      // notificationBackgroundHandler) — выполняем сейчас.
      unawaited(actionHandler.runPending());
      // Напоминания о встречах и задачах планируются в ОС (rescheduleAll выше);
      // прежние ежеминутные таймеры дублировали их и удалены. Здесь — только
      // служебная уборка отложенных писем.
      globalContainer.read(emailReminderProvider).start();
    } catch (e) {
      AppLogger.warning('Уведомления: не удалось инициализировать: $e');
    }

    // Фоновая синхронизация
    try {
      final bgService = globalContainer.read(backgroundServiceProvider);
      await bgService.initialize();
    } catch (e) {
      AppLogger.warning('Фоновые задачи: не удалось инициализировать: $e');
    }

    // Кеш вложений (LRU) — инициализация
    try {
      await globalContainer.read(attachmentCacheProvider).init();
      // Убираем вложения, которых не открывали дольше 3 дней: кэш нужен, чтобы
      // не качать повторно то, чем пользуются, а не копить всё подряд.
      unawaited(globalContainer.read(attachmentCacheProvider).evictStale());
      // Поиск по тексту вложений: файлы, положенные в кэш, — в индекс.
      globalContainer.read(attachmentTextIndexProvider).start();
    } catch (e) {
      AppLogger.warning('Attachment cache: не удалось инициализировать: $e');
    }
    // @-упоминания (2.2.0): значок «@» в ленте и фильтр «Упоминания».
    try {
      globalContainer.read(mentionScannerProvider).start();
    } catch (e) {
      AppLogger.warning('Упоминания: не удалось запустить проверку: $e');
    }

    // Новое письмо из другого приложения. Поверх текущего экрана (push), а
    // не вместо всей истории (go): после закрытия редактора приложение
    // оставалось на пустом белом экране (замечание 11.10.2026). После
    // первого кадра — при холодном запуске навигатор ещё не готов.
    void openCompose(Map<String, String> params) {
      final uri = Uri(path: '/compose', queryParameters: params.isEmpty ? null : params).toString();
      void go() => globalContainer.read(appRouterProvider).push(uri);
      if (WidgetsBinding.instance.hasScheduledFrame || !WidgetsBinding.instance.firstFrameRasterized) {
        WidgetsBinding.instance.addPostFrameCallback((_) => go());
      } else {
        go();
      }
    }

    // Интеграция с системным "Поделиться"
    try {
      final shareService = globalContainer.read(shareIntentProvider);
      // Подписка — до init: письмо, с которым приложение запущено, приходит
      // в поток сразу при init и без подписчика терялось.
      shareService.stream.listen((payload) async {
        final params = <String, String>{};
        // Текст — между приветствием и подписью (раньше заменял письмо
        // целиком, и подпись с приветствием пропадали).
        if (payload.text != null) params['quick'] = payload.text!;
        if (payload.filePaths.isNotEmpty) params['attachments'] = payload.filePaths.join('|');
        // Адресаты и тема, если их передало приложение-отправитель.
        final extra = await MailtoService.takeShare();
        if (extra != null) params.addAll(extra.toQuery()..remove('quick'));
        openCompose(params);
      });
      await shareService.init();
    } catch (e) {
      AppLogger.warning('Share intent: не удалось инициализировать: $e');
    }

    // mailto: и «Написать письмо» (ACTION_SENDTO) из других приложений.
    unawaited(MailtoService.init((r) => openCompose(r.toQuery())).catchError((Object e) {
      AppLogger.warning('mailto: $e');
    }));

    // Быстрые действия по долгому нажатию на значок приложения.
    unawaited(AppShortcuts.init(globalContainer));
    // Виджеты рабочего стола (Android и iPhone): нажатия и данные.
    unawaited(HomeWidgetService.init(globalContainer, (t) => AppShortcuts.openType(globalContainer, t)));
    // Встречи и задачи, созданные в виджете «Календарь» без входа в
    // приложение: вызов из окна виджета и очередь, накопленная раньше
    // (аккаунты грузятся асинхронно — разбор чуть позже).
    HomeWidgetService.onCreate = () => globalContainer.read(quickCreateProvider).drain();
    unawaited(Future<void>.delayed(const Duration(seconds: 3), () => globalContainer.read(quickCreateProvider).drain()));
    // «Прочитано» и «В архив» из виджета «Почта» (08.11.2026): вызов из
    // виджета и очередь, накопленная раньше.
    HomeWidgetService.onMailAction = () => globalContainer.read(widgetMailActionsProvider).drain();
    unawaited(Future<void>.delayed(const Duration(seconds: 3), () => globalContainer.read(widgetMailActionsProvider).drain()));

    // Цвет значков системных панелей задаётся по теме в MailApp.builder
    // (раньше всегда тёмные — в тёмной теме их не было видно).

    runApp(
      UncontrolledProviderScope(
        container: globalContainer,
        child: const MailApp(),
      ),
    );
    // Просьбы окон писем (ответить, переслать, удалить…) — компьютер.
    unawaited(MessageWindowHost.start(globalContainer));
  } catch (e, stack) {
    AppLogger.error('Критическая ошибка при запуске', e, stack);
    runApp(_ErrorApp(error: e.toString()));
  }
}

/// Корневой виджет приложения
class MailApp extends ConsumerWidget {
  const MailApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    // Цвета от обоев (Android 12+). Из цвета обоев строится полная схема
    // Material 3 (fromSeed) — у схем самого плагина на части версий нет
    // ролей surfaceContainer*, и карточки сливались с фоном.
    return DynamicColorBuilder(builder: (ColorScheme? lightDyn, ColorScheme? darkDyn) {
    final useDyn = settings.dynamicColor && !kIsWeb && Platform.isAndroid;
    final lightScheme = useDyn && lightDyn != null
        ? ColorScheme.fromSeed(seedColor: lightDyn.primary)
        : null;
    final darkScheme = useDyn && (darkDyn ?? lightDyn) != null
        ? ColorScheme.fromSeed(seedColor: (darkDyn ?? lightDyn)!.primary, brightness: Brightness.dark)
        : null;
    // Анимации отдельных элементов (появление строк, Hero, смена содержимого)
    // выключены навсегда (решение 09.10.2026: дёргались на тестовых
    // телефонах). Выезд, сдвиг и раскрытие панелей — обычные переходы.
    uiAnimations = false;
    mailPageWarm = settings.warmPage || settings.reading;
    // Шрифт интерфейса (1.8.8): его читают все темы ниже.
    AppTheme.fontFamily = AppTheme.familyFor(settings.uiFont);
    // «Оформление» (1.9.x, просьба владельца 31.10.2026): цветовая тема,
    // акцент, оттенок ленты, скругление, плотность, анимация открытия
    // письма. Системное «Убрать анимацию» — только как признак (без
    // подписки на весь MediaQuery: клавиатура перестраивала бы приложение).
    final appearance =
        settings.appearance(systemNoAnimations: MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    Radii.scale = appearance.radiusScale;
    // Цвета обоев, пока обои их дают, заменяют цветовую тему и акцент — и
    // чёрный тёмный вариант «Полночи» тоже.
    final blackDark =
        lightScheme == null && darkScheme == null && PresetSpec.of(appearance.preset).blackDark && !settings.highContrast;
    // Переходы между экранами — обычные (сдвиг, предиктивный «назад»);
    // «Уменьшить движение» выключает и их. Переменная пропала при удалении
    // настройки «Анимации интерфейса» — сборка 1.5.1 падала (10.10.2026).
    final animated = !settings.reduceMotion;
    return TrayWindowListener(
      child: MaterialApp.router(
      routerConfig: router,
      // На десктопе/вебе список можно тянуть мышью (по умолчанию Flutter
      // разрешает перетаскивание только пальцем/стилусом). Полезно и для
      // сенсорных экранов с подключённой мышью.
      scrollBehavior: const _AppScrollBehavior(),
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // Темы (с учётом высокого контраста и шрифта для дислексии)
      // «Чтение» — своя тёплая светлая тема; высокий контраст важнее неё.
      theme: AppTheme.withTransitions(
          settings.reading && !settings.highContrast
              ? AppTheme.readingTheme(settings.fontScale, dyslexiaFont: settings.dyslexiaFont, appearance: appearance)
              : AppTheme.lightTheme(settings.fontScale,
                  highContrast: settings.highContrast,
                  dyslexiaFont: settings.dyslexiaFont,
                  dynamicScheme: lightScheme,
                  appearance: appearance),
          animated),
      darkTheme: AppTheme.withTransitions(
          settings.amoled || blackDark
              ? AppTheme.amoledTheme(settings.fontScale,
                  highContrast: settings.highContrast,
                  dyslexiaFont: settings.dyslexiaFont,
                  dynamicScheme: darkScheme,
                  appearance: appearance)
              : AppTheme.darkTheme(settings.fontScale,
                  highContrast: settings.highContrast,
                  dyslexiaFont: settings.dyslexiaFont,
                  dynamicScheme: darkScheme,
                  appearance: appearance),
          animated),
      themeMode: settings.themeMode,
      // Плавная смена темы (светлая↔тёмная) вместо резкого переключения.
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeInOut,

      // Локализация
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // Масштаб шрифта + отключение анимаций для доступности
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Масштаб из настроек приложения умножается на системный (раньше
        // заменял его — пользователь с крупным шрифтом в системе получал
        // мелкий текст). Системное «Убрать анимацию» тоже учитывается.
        final systemScale = mq.textScaler.scale(14) / 14;
        // Масштаб интерфейса (1.6.12): на узких экранах и с крупным шрифтом
        // всё приложение рисуется чуть мельче, чтобы элементы помещались
        // (UiZoom). Шрифт для расчёта — итоговый, с пределом ×1,6.
        final effectiveText = (systemScale * settings.fontScale).clamp(0.8, TextScaleLimits.app);
        final zoom = UiZoom.resolve(settings.uiScale, mq.size, effectiveText);
        UiZoom.current = zoom;
        _logInsetsOnce(context, zoom);
        final zmq = UiZoom.scaleData(mq, zoom);
        // Нижний и боковые системные отступы забирает SafeArea ниже — поэтому
        // из данных для экранов они убираются. Раньше здесь копировались
        // исходные отступы, и панели внизу (вкладки, кнопки письма) добавляли
        // высоту системной панели ещё раз: под ними оставалась пустая полоса.
        Widget result = MediaQuery(
          data: zmq.removePadding(removeLeft: true, removeRight: true, removeBottom: true).copyWith(
            // Общий предел ×1,6: при системном ×2 (Android 14) вёрстка
            // большинства экранов разваливалась — жалобы тестировщиков.
            textScaler: (settings.fontScale == 1.0
                    ? mq.textScaler
                    : TextScaler.linear((systemScale * settings.fontScale).clamp(0.8, 3.0)))
                .clamp(maxScaleFactor: TextScaleLimits.app),
            disableAnimations: settings.reduceMotion || mq.disableAnimations,
          ),
          // Экран PIN — над навигатором, закрывает любое открытое окно.
          // Свой ScaffoldMessenger: чёрные плашки выключены во всём приложении.
          // Ошибки — строкой вверху (InlineNoticeLayer), не плашкой.
          child: QuietScaffoldMessenger(
              child: AppLockGate(child: InlineNoticeLayer(child: child ?? const SizedBox.shrink()))),
        );
        result = UiZoomBox(zoom: zoom, child: result);
        // Коррекция цвета для дальтонизма (дальтонизация): различия, которые
        // человек с протанопией/дейтеранопией/тританопией не видит, переносятся
        // в различимые оттенки. Раньше настройка сохранялась, но ни на что не
        // влияла.
        final cb = _colorBlindMatrix(settings.colorBlindMode);
        if (cb != null) {
          result = ColorFiltered(colorFilter: ColorFilter.matrix(cb), child: result);
        }
        // Прозрачные системные панели (edge-to-edge) и значки под цвет темы.
        // Экраны с AppBar задают стиль строки состояния сами; это — для
        // экранов без него и для панели навигации.
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // Цвета панелей не задаются (09.10.2026): прозрачными их делает
          // enableEdgeToEdge() в MainActivity, а setStatusBarColor/
          // setNavigationBarColor в Android 15 устарели (замечание Google Play).
          value: SystemUiOverlayStyle(
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          // Нижний и боковые системные отступы (жестовая полоса, кнопки
          // навигации, вырез в альбомной ориентации) приложение задаёт само —
          // с Android 15/16 система их больше не резервирует. Сверху отступ
          // дают AppBar и SafeArea экранов: строка состояния остаётся под
          // цветом заголовка. Полоса под навигацией — цвета нижней панели
          // (она теперь темнее фона): панель и системная полоса — одно целое.
          child: ColoredBox(
            color: Theme.of(context).navigationBarTheme.backgroundColor ??
                Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(top: false, child: result),
          ),
        );
      },
    ),
    );
    });
  }
}

/// Матрица дальтонизации (Fidaner и др.: исходный цвет + сдвиг ошибки
/// восприятия) для режима: 1 — протанопия, 2 — дейтеранопия, 3 — тританопия.
List<double>? _colorBlindMatrix(int mode) {
  switch (mode) {
    case 1:
      return const [
        1, 0, 0, 0, 0,
        -0.2549, 1.2549, 0, 0, 0,
        0.3031, -0.5451, 1.242, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 2:
      return const [
        1, 0, 0, 0, 0,
        -0.4375, 1.4375, 0, 0, 0,
        0.2625, -0.5625, 1.3, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 3:
      return const [
        1.05, -0.3825, 0.3325, 0, 0,
        0, 1.2345, -0.2345, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
    default:
      return null;
  }
}

/// Экран ошибки запуска
class _ErrorApp extends StatelessWidget {
  final String error;
  const _ErrorApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.error, size: 64, color: AppColors.errorRed),
                const SizedBox(height: Space.l),
                const Text('Ошибка запуска', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: Space.s),
                Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF6B7280))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Прокрутка перетаскиванием мышью (десктоп/веб) и стилусом.
/// По умолчанию Flutter на десктопе разрешает только колесо и полосу прокрутки.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };

  /// Тень у края вертикального списка, за которым есть ещё пункты
  /// (ScrollEdgeFade, 10.10.2026) — одно правило для меню, панелей,
  /// шторок и настроек.
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    final inner = super.buildScrollbar(context, child, details);
    if (axisDirectionToAxis(details.direction) != Axis.vertical) return inner;
    // Многострочные поля ввода — без тени: у них своя рамка.
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) return inner;
    return ScrollEdgeFade(child: inner);
  }
}

/// Один раз за запуск — системные отступы экрана в журнал: по ним видно,
/// сколько места внизу занимает системная панель навигации на конкретном
/// телефоне (кнопки или жестовая полоса).
bool _insetsLogged = false;
void _logInsetsOnce(BuildContext context, double zoom) {
  if (_insetsLogged) return;
  final mq = MediaQuery.maybeOf(context);
  if (mq == null || mq.size.isEmpty) return;
  _insetsLogged = true;
  String f(EdgeInsets e) =>
      'l${e.left.toStringAsFixed(0)} t${e.top.toStringAsFixed(0)} r${e.right.toStringAsFixed(0)} b${e.bottom.toStringAsFixed(0)}';
  AppLogger.info('Экран: ${mq.size.width.toStringAsFixed(0)}×${mq.size.height.toStringAsFixed(0)} dp, '
      'dpr ${mq.devicePixelRatio.toStringAsFixed(2)}, шрифт ×${mq.textScaler.scale(1).toStringAsFixed(2)}, '
      'отступы ${f(mq.viewPadding)}, жесты ${f(mq.systemGestureInsets)}, '
      'масштаб интерфейса ${(zoom * 100).round()}%');
}

/// Язык интерфейса при запуске: сохранённый в настройках, иначе системный,
/// если он есть в приложении, иначе английский (как SettingsNotifier).
String _startLanguage(SharedPreferences prefs) {
  final saved = prefs.getString('s_locale');
  if (saved != null && AppLocalizations.supportedCodes.contains(saved)) return saved;
  final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return AppLocalizations.supportedCodes.contains(system) ? system : 'en';
}

/// Protocol Buffers (BSD-3-Clause) — protobuf lite внутри Google Tink (UnifiedPush, 1.10.x).
const _protobufLicense = '''Protocol Buffers for Java
Copyright 2008 Google Inc. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
copyright notice, this list of conditions and the following disclaimer
in the documentation and/or other materials provided with the
distribution.
    * Neither the name of Google Inc. nor the names of its
contributors may be used to endorse or promote products derived from
this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Code generated by the Protocol Buffer compiler is owned by the owner
of the input file used when generating it.  This code is not
standalone and requires a support library to be linked with it.  This
support library is itself covered by the above license.''';

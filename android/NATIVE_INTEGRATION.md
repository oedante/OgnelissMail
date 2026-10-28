# Подключение нативных плагинов (Android)

В `lib/services/**` есть три `MethodChannel`, которым нужна нативная часть.
Без неё вызовы бросают `MissingPluginException`, а функции молча не работают
(контакты/календарь) или показывают ошибку (голос). Файлы обработчиков лежат в
`android/app/src/main/kotlin/com/ogneliss/mail/` (пакет приложения — `com.ogneliss.mail`):

| Канал | Файл | Функция |
|---|---|---|
| `ogneliss/device_contacts` | `DeviceContactsPlugin.kt` | импорт/экспорт контактов |
| `ogneliss/device_calendar` | `DeviceCalendarPlugin.kt` | экспорт событий в календарь |
| `ogneliss/speech` | `SpeechRecognizerPlugin.kt` | распознавание речи (голосовые команды) |
| `ogneliss/foreground_sync` | `ForegroundSyncPlugin.kt` + `SyncForegroundService.kt` | работа в фоне (синк при свёрнутом приложении) |

## `MainActivity`

`MainActivity.kt` лежит в архиве (`kotlin/com/ogneliss/mail/MainActivity.kt`) и
уже регистрирует все каналы. Наследуется от `FlutterFragmentActivity` — этого
требует `local_auth` (биометрический вход). Копию, которую создаёт
`flutter create` (`kotlin/com/ogneliss/ogneliss/`), скрипты настройки удаляют,
а `applicationId`/`namespace` в Gradle приводят к `com.ogneliss.mail`.

## Разрешения

Уже объявлены в `AndroidManifest.xml`:
`READ_CONTACTS`, `WRITE_CONTACTS`, `READ_CALENDAR`, `WRITE_CALENDAR`,
`RECORD_AUDIO`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`. Сервис
`SyncForegroundService` объявлен в манифесте (`foregroundServiceType="dataSync"`).
Запрос у пользователя выполняется на стороне Dart (`permission_handler`).

## Работа в фоне (Android)

`SyncForegroundService` держит процесс живым, когда приложение свёрнуто, поэтому
УЖЕ существующие Dart-таймеры (`BackgroundService._foregroundSyncTimer → syncAll`)
и IMAP IDLE продолжают работать в главном изоляте — без отдельного изолята и
мультиизолятной БД. Включается тумблером «Работать в фоне» (по умолчанию выкл. —
показывает постоянное уведомление). Старт при сворачивании, стоп при возврате
(`main_shell` + `foreground_sync_controller.dart`). Покрывает «свёрнуто»; при
смахивании из недавних процесс завершается. OEM-«убийцы батареи» (Xiaomi/Huawei/
Samsung) могут мешать — тестировать на реальных устройствах.

## Проверка

Dart-код каждой функции сначала зовёт лёгкий метод `ping`. Если нативная часть
подключена — раздел/функция работают; если нет — UI-раздел скрыт (контакты/
календарь) либо показывается честная ошибка (голос) / тихо пропускается (фон).
То есть после интеграции ничего «фиктивного» не остаётся.

## iOS — фоновый синк через BGTaskScheduler

**Dart-часть уже готова:** `BackgroundService.initialize()` вызывает
`Workmanager().initialize(callbackDispatcher)` + `registerPeriodicTask('periodic_sync', …)`,
а `callbackDispatcher` реально синхронизирует (поднимает контейнер + шифрованную
БД + уведомления в фоновом изоляте). Пакет `workmanager: ^0.9.0` мостит это на
iOS BGTaskScheduler. Осталась НАТИВНАЯ регистрация iOS.

Сделано в этом архиве:
- `Info.plist` → `UIBackgroundModes` (fetch, processing) и
  `BGTaskSchedulerPermittedIdentifiers` = [`periodic_sync`] (совпадает с именем
  задачи в Dart). С 1.6.42 — ещё `processing_sync` (BGProcessingTask, в
  AppDelegate `WorkmanagerPlugin.registerBGProcessingTask`; заявку ставит Dart —
  `BackgroundService.submitIosProcessing`).

Нужно добавить в `ios/Runner/AppDelegate.swift` (файла нет в архиве — он в
рабочем дереве):

```swift
import UIKit
import Flutter
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Идентификатор ДОЛЖЕН совпадать с _TaskNames.periodicSync и записью в
    // BGTaskSchedulerPermittedIdentifiers (Info.plist).
    WorkmanagerPlugin.registerTask(withIdentifier: "periodic_sync")
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "periodic_sync",
      frequency: NSNumber(value: 15 * 60) // iOS сам решает реальное время
    )

    // Плагины должны регистрироваться и в фоновом изоляте.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // Нативные обработчики каналов (контакты/календарь/речь). Нужен messenger
    // от FlutterViewController.
    if let controller = window?.rootViewController as? FlutterViewController {
      DeviceContactsPlugin.register(with: controller.binaryMessenger)
      DeviceCalendarPlugin.register(with: controller.binaryMessenger)
      SpeechRecognizerPlugin.shared.register(with: controller.binaryMessenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

### Файлы iOS-плагинов (в архиве, `ios/Runner/`)
`DeviceContactsPlugin.swift` (CNContactStore), `DeviceCalendarPlugin.swift`
(EventKit), `SpeechRecognizerPlugin.swift` (SFSpeechRecognizer + AVAudioEngine).
Добавьте их в target Runner в Xcode. Usage-descriptions
(`NSCalendarsUsageDescription`, `NSMicrophoneUsageDescription`,
`NSSpeechRecognitionUsageDescription`, `NSContactsUsageDescription`) уже в
Info.plist. Разрешения запрашивает Dart (`permission_handler`); Swift страхуется
нативным запросом (EventKit/Speech). Контракт каналов и методов идентичен
Android-плагинам — Dart-код не меняется.

Проверить на реальном устройстве: распознавание речи и EventKit в симуляторе
работают ограниченно.

**Честно об ожиданиях:** BGTaskScheduler — ОППОРТУНИСТИЧЕСКИЙ. iOS сам решает,
когда запускать (учитывает заряд, сеть, привычки пользователя) — обычно раз в
несколько часов, не по точному интервалу, и не запускается вовсе, если
пользователь редко открывает приложение или включён Low Power Mode. Это НЕ
непрерывный фон (такого на iOS нет) — для near-real-time нужен APNs silent-push
(отдельный бэкенд). Проверять на реальном устройстве (в симуляторе BGTask можно
триггерить вручную через отладчик).

## iOS — нативные обработчики (РЕАЛИЗОВАНЫ)

Контакты/календарь/речь на iOS реализованы (см. `ios/Runner/*.swift` выше):
- контакты — `CNContactStore` (`DeviceContactsPlugin.swift`);
- календарь — `EventKit` (`DeviceCalendarPlugin.swift`);
- речь — `SFSpeechRecognizer` + `AVAudioEngine` (`SpeechRecognizerPlugin.swift`).
Каналы и имена методов идентичны Android (`ping`/`getContacts`/`addContact`/
`addEvent`/`startListening`/`stopListening`, колбэки `onSpeechResult`/
`onSpeechError`/`onSpeechPartial`) — Dart-код общий, не меняется. Остаётся добавить
файлы в target Runner и вызвать регистрацию в AppDelegate (сниппет выше).

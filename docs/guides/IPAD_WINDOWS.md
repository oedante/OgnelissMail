# iPad: письмо в отдельном окне и обязательный переход на сцены (UIScene)

Исследование 07.11.2026 (технические хвосты, пункт 19). Кода для iPad в
приложении пока нет: здесь — что нужно сделать, в каком порядке и какие
шаги в Xcode делает владелец.

## 0. Срочное: без сцен приложение с Xcode 27 не запустится

Apple, TN3187 «Migrating to the UIKit scene-based life cycle» (обновлена
23.06.2025):

> In the next major release following iOS 26, UIScene lifecycle will be
> required when building with the latest SDK; otherwise, your app won't
> launch.

Следующая после iOS 26 версия — iOS 27 (Xcode 27). У приложения сцен нет:
в `ios/Runner/Info.plist` нет `UIApplicationSceneManifest`, всё — в
`AppDelegate` (`didFinishLaunchingWithOptions`, `application(_:open:)`).
Пока сборка идёт в Xcode 26, это только строка в журнале («UIScene
lifecycle will soon be required»). **Как только сборка пойдёт в Xcode 27
(iOS 27 SDK) — приложение не откроется.** App Store, по сторонним
сводкам, потребует iOS 27 SDK для новых сборок с весны 2027 года.

Flutter с 3.41 переводит на сцены сам, но только неизменённый
`AppDelegate`; наш изменён (каналы, виджеты, фоновые задачи, MDM), поэтому
переход — вручную. Flutter 3.47 нужные части уже содержит
(`FlutterSceneDelegate`, `FlutterImplicitEngineDelegate`).

### Что меняется в коде (могу сделать я)

1. `Info.plist` — манифест сцен с классом Flutter:
   `UIApplicationSceneManifest` → `UIApplicationSupportsMultipleScenes` =
   NO (для шага 0; YES — в шаге 1) → `UISceneConfigurations` →
   `UIWindowSceneSessionRoleApplication` → одна конфигурация:
   `UISceneClassName` = `UIWindowScene`, `UISceneDelegateClassName` =
   `$(PRODUCT_MODULE_NAME).SceneDelegate`, `UISceneConfigurationName` =
   `flutter`, `UISceneStoryboardFile` = `Main`.
2. `AppDelegate.swift`: класс получает протокол
   `FlutterImplicitEngineDelegate`; регистрация плагинов
   (`GeneratedPluginRegistrant`) и всех своих каналов (календарь,
   контакты, виджеты, push, перевод, MDM, платформа) переезжает из
   `didFinishLaunchingWithOptions` в
   `didInitializeImplicitFlutterEngine(_ engineBridge:)` — через
   `engineBridge.pluginRegistry` и `registrar(forPlugin:)` оттуда же. В
   `didFinishLaunchingWithOptions` остаются: очистка при первом запуске,
   исключение из резервной копии, фоновые задачи (`periodic_sync`,
   `processing_sync`), делегат уведомлений.
3. `SceneDelegate` — подкласс `FlutterSceneDelegate`; класс можно положить
   в тот же `AppDelegate.swift` — тогда новый файл добавлять в проект
   Xcode не нужно. В нём — нажатия на виджет: `scene(_:openURLContexts:)`
   (сейчас `application(_:open:options:)`) и холодный запуск по ссылке
   виджета `connectionOptions.urlContexts` (сейчас `launchOptions[.url]`).
4. Плагины: события запуска, ссылок и быстрых действий нужны
   `quick_actions_ios` 1.2.5, `receive_sharing_intent` 1.9.0 и
   `workmanager_apple` 0.9.11 — все трое сцены уже поддерживают
   (`addSceneDelegate`). Уведомления (`flutter_local_notifications`) идут
   через делегат центра уведомлений — от сцен не зависят. Остальные
   плагины событий `AppDelegate` не используют. Поиск окна для показа
   (`AppDelegate.swift`, строка ~628) уже идёт через `connectedScenes`.

Проверка — сборка iOS в Actions (компиляция) и телефон владельца: запуск,
вход в ящик, нажатие на виджет при закрытом и открытом приложении,
«Поделиться» файлом в приложение, быстрые действия значка, уведомление о
письме и переход по нему, фоновая проверка почты, Face ID, вложение в
«Файлы».

### Шаги владельца в Xcode для шага 0

Нет: всё в `Info.plist` и `AppDelegate.swift`. Проверить в Xcode → Runner →
General → Deployment Info, что «Supports multiple windows» снят (он
отражает `UIApplicationSupportsMultipleScenes`), и собрать как обычно.

## 1. Письмо в отдельном окне на iPad

### Что есть во Flutter

Официальная страница Flutter о переходе на сцены: «Flutter doesn't fully
support multiple scenes yet, but support is in progress». Официальные окна
Flutter (`RegularWindowController`) — только Windows, macOS, Linux. Значит,
на iPad окно делается так же, как у нас на компьютере: **каждое окно —
свой движок Flutter**, движки — из одной `FlutterEngineGroup` (общие
шрифты и контекст графики; каждый следующий движок, по документации
Flutter, — порядка сотен килобайт, а не десятки мегабайт).

### Почему это ложится на готовое

Окно письма на компьютере (`lib/features/mail/message_window.dart`) уже
устроено так: отдельный движок без базы и плагинов получает готовое
письмо строкой JSON (`MessageWindowPayload`: шапка, очищенный HTML,
картинки, вложения), а «Ответить», «Переслать», «Удалить», ссылки и
вложения просит главное окно по каналу. На iPad меняется только способ
открыть окно и передать строку; показ письма (`DesktopMailBody`) — тот же.

### Как устроить

1. Dart: `openInNewWindow` на iPad вызывает канал `ogneliss/windows`,
   метод `open`, с той же строкой JSON. Точка входа окна — функция с
   `@pragma('vm:entry-point')` (например, `messageWindowMain(List<String>
   args)`), args[0] — строка письма.
2. Swift (`AppDelegate.swift`):
   - открыть окно: `UIApplication.shared.requestSceneSessionActivation(nil,
     userActivity: NSUserActivity(activityType: "com.ogneliss.mail.message"),
     options: …)`, письмо — в `userInfo`;
   - выбрать конфигурацию: `application(_:configurationForConnecting:options:)`
     — у сессии с этим видом действия — конфигурация `message` с классом
     `MessageSceneDelegate`, иначе — `flutter` (главное окно);
   - `MessageSceneDelegate`: движок из общей `FlutterEngineGroup`
     (`makeEngine(withEntrypoint: "messageWindowMain", libraryURI:
     "package:ogneliss/features/mail/message_window.dart",
     initialRoute: nil, entrypointArgs: [json])`), `FlutterViewController`
     на нём — корень окна сцены; плагины этому движку — **только нужные**
     (ссылки, «Поделиться», путь к файлам), не весь
     `GeneratedPluginRegistrant`: фоновые задачи и уведомления — одни на
     приложение;
   - мост действий: канал окна → канал главного движка (как
     `MessageWindow.channelName` на компьютере); главное окно делает
     действие и, если нужно, выходит вперёд
     (`requestSceneSessionActivation` с сессией главной сцены);
   - восстановление: `stateRestorationActivity` сцены — то же действие с
     письмом, iPadOS вернёт окна после перезапуска; письма уже нет —
     «Письмо не найдено».
3. Перетаскивание письма из ленты к краю экрана (как в «Почте» Apple) —
   по желанию, потом: элемент перетаскивания с `NSUserActivity` того же
   вида; ядро перетаскивания (super_drag_and_drop) это умеет на iPad.

### Шаги владельца в Xcode для шага 1

1. Runner → General → Deployment Info: отметить «Supports multiple
   windows» (это `UIApplicationSupportsMultipleScenes` = YES; могу
   поставить и в `Info.plist`, Xcode покажет отметку сам).
2. Там же убедиться, что «Requires full screen» снят — иначе iPadOS окна
   не даёт.
3. Runner → Info → «Activity types» (`NSUserActivityTypes`): строка
   `com.ogneliss.mail.message` (могу добавить в `Info.plist` сам).
4. Новых файлов в проект Xcode добавлять не нужно, если классы сцен
   лежат в `AppDelegate.swift`. Если владелец предпочтёт отдельный
   `SceneDelegate.swift` — File → Add Files to "Runner"…, цель Runner.
5. Проверка на iPad: письмо → «Ещё» → «Открыть в отдельном окне» →
   окно рядом (Split View) или поверх (Stage Manager); в окне «Ответить» —
   ответ в главном окне; закрыть приложение и открыть снова — окна
   вернулись; iPhone — пункта нет.

### Оценка

Шаг 0 — около дня работы и проверка владельцем на телефоне (обязателен в
любом случае). Шаг 1 после него — 2–3 дня: Dart-часть почти готова
(окно компьютера), основная работа — Swift-мост и проверка на iPad
владельцем (симулятора iPad и Xcode в этом окружении нет).

## Источники

- Apple, TN3187: https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle
- Apple, «Supporting multiple windows on iPad»: https://developer.apple.com/documentation/uikit/supporting-multiple-windows-on-ipad
- Flutter, «Migrate to the UIScene lifecycle» (исходник страницы — репозиторий flutter/website, `sites/docs/src/content/release/breaking-changes/uiscenedelegate.md`)
- Flutter, «Multiple Flutter screens or views» (FlutterEngineGroup): https://docs.flutter.dev/add-to-app/multiple-flutters

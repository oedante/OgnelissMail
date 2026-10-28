# iPhone: новая версия без перенастройки Xcode (с 1.6.12)

## Что изменилось

Раньше каждый архив проекта привозил свой `project.pbxproj`. При распаковке он
затирал всё, что было выбрано в Xcode: Team, App Groups, цель виджетов. Теперь:

- В архиве **нет** файлов, которые Xcode меняет при настройке:

  | Файл | Что в нём | В архиве |
  |---|---|---|
  | `ios/Runner.xcodeproj/project.pbxproj` | Team (если выбран в Xcode), возможности (App Groups), цель виджетов | нет; рядом лежит `project.pbxproj.base` |
  | `ios/Runner/Runner.entitlements` | App Groups | нет |
  | `ios/Flutter/Signing.xcconfig` | Team для сборки | нет; постоянная копия — `~/.ogneliss/ios_signing.xcconfig` |
  | `ios/Runner.xcworkspace/contents.xcworkspacedata` | связь с Pods | нет; его ведёт `pod install` |
  | `*/xcuserdata/` | личные настройки Xcode | нет |

- Остальное — `Info.plist`, `Podfile`, `AppDelegate.swift`, `*.xcconfig` в
  `ios/Flutter`, `ios/OgnelissWidgets/` — приходит с архивом. Их править не нужно.
- Team хранится **вне проекта**: `~/.ogneliss/ios_signing.xcconfig`.
  `scripts/build_ios.sh` при каждом запуске копирует его в
  `ios/Flutter/Signing.xcconfig`, а Xcode берёт Team оттуда (через `Debug.xcconfig`
  и `Release.xcconfig`, у виджетов — через `Widgets.xcconfig`).

## Один раз

1. **Team ID**: developer.apple.com → Membership → Team ID (10 символов).
2. На Mac в папке проекта:
   ```bash
   scripts/build_ios.sh --team ABCDE12345
   ```
   Скрипт создаст `~/.ogneliss/ios_signing.xcconfig`:
   ```
   DEVELOPMENT_TEAM = ABCDE12345
   CODE_SIGN_STYLE = Automatic
   ```
   Можно создать этот файл и вручную: две строки выше.
3. **Xcode → Settings → Accounts**: войти в Apple ID команды. Сертификаты и
   профили автоматическая подпись создаст сама.
4. **Новая папка проекта** (архив распакован не поверх старой): `build_ios.sh`
   сам создаст `project.pbxproj` из `project.pbxproj.base`. Если собираете
   только в Xcode:
   ```bash
   cp ios/Runner.xcodeproj/project.pbxproj.base ios/Runner.xcodeproj/project.pbxproj
   ```
5. **Виджеты** (по желанию) — `ios/OgnelissWidgets/README.md`. Эти настройки
   Xcode теперь сохраняются между версиями.

**Если Team уже выбирали в Xcode**, ничего страшного: Xcode записал его в
`project.pbxproj`, а этот файл больше не перезаписывается. Значения в
`project.pbxproj` и в `Signing.xcconfig` должны совпадать.

## Каждая новая версия

1. Распакуйте архив **поверх** папки проекта, с заменой файлов.
2. Соберите одним из способов:
   - `scripts/build_ios.sh --upload` — IPA и сразу в TestFlight (нужны `ASC_KEY_ID`
     и `ASC_ISSUER_ID`, см. `BUILD_IOS.md`);
   - `scripts/build_ios.sh` — только IPA, загрузка через Transporter;
   - `scripts/build_ios.sh --prepare`, затем в Xcode `ios/Runner.xcworkspace` →
     Any iOS Device → Product → Archive.

   Все три способа запускают `flutter pub get` и `pod install`. В 1.6.12 он
   обязателен: добавился плагин `ogneliss_native_http` для iOS. Без скрипта:
   ```bash
   flutter pub get && (cd ios && pod install)
   ```
3. Версию и номер сборки задаёт `pubspec.yaml` (например, `1.6.12+56`).
   В Xcode их не меняйте.

**Если изменился `project.pbxproj.base`**, скрипт предупредит: «В архиве
изменился базовый файл проекта Xcode». Ваш `project.pbxproj` при этом не
трогается, а что перенести вручную, будет написано в CHANGELOG. С 1.5.2 этот
файл ни разу не менялся.

**Сборка с Windows** (`scripts/ios_remote_build.ps1`): те же файлы не
копируются на Mac, поэтому настройки Xcode на Mac сохраняются. `teamId` берётся
из `scripts/ios_remote.json`.

## Подпись и загрузка без сборки в Xcode (1.6.12)

`scripts/build_ios.sh` теперь собирает архив через flutter, а подписывает и
загружает через `xcodebuild -exportArchive -allowProvisioningUpdates`.
Автоматическая подпись сама создаёт сертификат распространения и профиль,
поэтому ошибка «не может подписать сертификатом» должна уйти:

```bash
scripts/build_ios.sh --upload   # архив → подпись → загрузка в TestFlight
```

- Ключ App Store Connect API (`ASC_KEY_ID`, `ASC_ISSUER_ID`) не обязателен.
  Без него загрузка идёт учётной записью из Xcode → Settings → Accounts.
- Если подпись всё же не прошла, скрипт откроет готовый архив в Organizer
  Xcode: Distribute App → App Store Connect → Upload. Пересобирать в Xcode не
  нужно, архив уже собран из терминала.

**«No such module 'flutter_local_notifications'» / «'workmanager_apple'» в
AppDelegate при сборке в Xcode.** Код здесь ни при чём: из терминала тот же
код собирается. Xcode не видит модули плагинов (Pods). Обычно причина одна
из трёх:

1. Открыт `ios/Runner.xcodeproj`. Открывать нужно `ios/Runner.xcworkspace`:
   только в нём есть проект Pods.
2. После распаковки архива или `flutter clean` не выполнен `pod install`:
   ```bash
   scripts/build_ios.sh --prepare
   ```
   Эта команда выполняет pub get, pod install и генерирует настройки Flutter.
   Затем закройте и снова откройте `Runner.xcworkspace`.
3. Остался старый кэш Xcode: Product → Clean Build Folder (⇧⌘K), закрыть
   Xcode, затем
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
   ```
   и снова пункт 2.

Выбирайте схему **Runner** (не RunnerTests) и устройство **Any iOS Device
(arm64)**.

## Проверка до TestFlight: консоль и симулятор

**1. Консоль (Windows или Mac): движок с профилем iPhone.** Логика входа та
же, что в приложении, но TLS — Dart. Подходит, чтобы проверить сервер, логин,
домен, Provision и список папок.

```bash
cd packages/mail_engine
dart pub get
dart run bin/connect_test.dart --email ivanov@corp.ru --server mail.corp.ru --domain CORP --as iphone --mail
dart run bin/connect_test.dart --email ivanov@corp.ru --server mail.corp.ru --domain CORP --as android
```

Пароль спросит скрыто (или задайте `OGN_PASSWORD`). Итог — строка
«✓ ПОДКЛЮЧЕНО … eas @ хост» и список папок, или «✗ НЕ ПОДКЛЮЧИЛОСЬ» с
причиной. Ошибка 403 «If you are not a bot» с профилем iphone в консоли
ожидаема для шлюза, проверяющего отпечаток TLS: решающая проверка — шаг 2.
На сервере появится «мобильное устройство» OGNCLI… — его можно удалить в OWA.

**2. Симулятор iPhone на Mac: настоящий сетевой стек iOS.** Приложение
целиком, с новым плагином NSURLSession, без подписи и TestFlight.

```bash
scripts/build_ios.sh --run
```

Скрипт выполнит pub get и pod install, запустит первый доступный симулятор
iPhone (в Xcode 26 это iPhone 17…, «iPhone 16» может не быть) и приложение в нём.
- Если в `flutter devices` только «macOS» и «Chrome», в Xcode не установлен
  симулятор iOS: `xcodebuild -downloadPlatform iOS` (несколько ГБ) или
  Xcode → Settings → Components → iOS.
- `config/dart_defines.json` для проверки Exchange не нужен (он нужен только для
  входа через OAuth-прокси). Для полноценной сборки скопируйте его на Mac сами,
  в архив он не входит.
- iPhone по кабелю: `DEVICE=<id из flutter devices> scripts/build_ios.sh --run`.

В приложении войдите в ящик. В консоли `flutter run` и в журнале
приложения («Настройки → Диагностика») должны быть:
- «Проверка доступа: вариант «как Почта iPhone»»;
- User-Agent `Apple-iPhone…/…` (модель берётся у симулируемого iPhone);
- «Exchange: подключение через движок ✓».

В симуляторе нет фоновой проверки почты и push-уведомлений. Сеть — как у
Mac: если шлюз доступен только из сети организации, на Mac нужен VPN.

## Проверка входа на iPhone (1.6.12)

- Режим «Совместимость со шлюзом — как Почта iPhone» на iPhone включён по
  умолчанию: запросы идут через сетевой стек iOS, User-Agent `Apple-iPhone…`,
  а при регистрации устройства передаются модель и версия iOS.
- При входе в журнале: «Проверка доступа: вариант «как Почта iPhone»» и, если
  первый не подошёл, второй вариант. Не вошли — пришлите журнал из диагностики.
- В ошибках сети теперь виден код iOS, например `NSURLErrorDomain -1200`
  (сбой TLS) или `-1202` (сертификат не подтверждён).
- 403 «If you are not a bot» после прежних неудачных попыток: шлюз мог временно
  запомнить адрес. Повторите через 15–30 минут или с другой сети.
- Если адрес сервера не находится автоматически (так было у acmegroup.example),
  укажите сервер вручную.

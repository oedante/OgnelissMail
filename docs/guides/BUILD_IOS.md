# Сборка для iPhone и iPad

> С 1.6.12 архив проекта не затирает настройки Xcode (Team, App Groups, виджеты): `docs/guides/IOS_XCODE_SETUP.md`.

iOS-приложение собирает только Xcode, а он есть только на macOS. Из Android
Studio под Windows собрать iOS напрямую нельзя — но можно запускать сборку
на Mac из Android Studio одной кнопкой (вариант Б) или в облаке (вариант В).

## Вариант А. Прямо на Mac

### 1. Один раз: окружение

```bash
# Xcode — из App Store (последняя версия: App Store принимает сборки только с актуальным SDK).
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS          # симулятор iOS

# Homebrew (если нет): https://brew.sh
brew install cocoapods
brew install --cask flutter               # или: git clone -b stable https://github.com/flutter/flutter ~/flutter
flutter --version                         # нужен 3.38 или новее
flutter doctor                            # раздел Xcode должен быть зелёным
```

Вход в Apple ID команды: **Xcode → Settings → Accounts → «+» → Apple ID**.
Без него автоматическая подпись не создаст сертификат и профиль.

### 2. Проект на Mac

Скопируйте архив проекта (или `git clone`) и **`config/dart_defines.json`**
с Windows — в архиве его нет (секреты). Затем:

```bash
cd ogneliss-mail
chmod +x scripts/*.sh
scripts/build_ios.sh --check                 # проверка окружения
scripts/build_ios.sh --team ABCDE12345       # запомнить Team ID (developer.apple.com → Membership)
scripts/build_ios.sh --run                   # запуск на iPhone (по кабелю) или в симуляторе
```

Скрипт сам выполнит `flutter pub get`, сгенерирует код базы
(`build_runner`, если его нет) и `pod install`. Не запускайте на Mac
`scripts/setup.sh` — он для первичного создания платформ, iOS-проект уже есть.

Первый запуск на своём iPhone: на телефоне **Настройки → Конфиденциальность и
безопасность → Режим разработчика** — включить; после установки
**Основные → VPN и управление устройством** — доверять разработчику.

### 3. Сборка для TestFlight

```bash
scripts/build_ios.sh                         # → build/ios/ipa/*.ipa
```

Загрузка — одно из:
- приложение **Transporter** (App Store, бесплатно): войти Apple ID, перетащить IPA;
- из командной строки с ключом App Store Connect API:
  ```bash
  mkdir -p ~/.appstoreconnect/private_keys
  cp AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
  ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-... scripts/build_ios.sh --upload
  ```
- **Xcode → Window → Organizer** → архив → Distribute App → App Store Connect
  (архив лежит в `build/ios/archive/Runner.xcarchive`).

Через 10–30 минут сборка появится в App Store Connect → TestFlight.

### Android Studio на Mac

Android Studio на Mac собирает и iOS: откройте проект, в списке устройств
выберите iPhone или симулятор и запустите обычную конфигурацию
**«Ogneliss Mail (debug)»** — `--dart-define-from-file` в ней уже есть.
Перед первым запуском выполните `scripts/build_ios.sh --run` (pod install).

## Вариант Б. Из Android Studio под Windows — сборка на Mac по SSH

Код правите в Android Studio на Windows, кнопка запускает сборку на Mac и
возвращает IPA в `build\ios\ipa\`.

Один раз:
1. На Mac: **Системные настройки → Основные → Общий доступ → Удалённый вход** — включить.
2. На Mac — окружение из варианта А, шаг 1, и вход в Apple ID в Xcode.
3. На Windows (PowerShell):
   ```powershell
   ssh-keygen -t ed25519            # Enter на все вопросы
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh oleg@192.168.1.50 "mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"
   copy scripts\ios_remote.example.json scripts\ios_remote.json   # заполнить host, user, teamId
   ```
   В `ios_remote.json` поле `keychainPassword` — пароль входа на Mac: по SSH
   связка ключей заблокирована, без неё подпись не пройдёт. Файл в git не попадает.
4. Android Studio → конфигурации запуска **«iOS: IPA на Mac (SSH)»** и
   **«iOS: IPA → TestFlight (SSH)»** (нужен включённый плагин Shell Script —
   он встроен). Или из терминала:
   ```powershell
   .\scripts\ios_remote_build.ps1 -Check
   .\scripts\ios_remote_build.ps1            # IPA
   .\scripts\ios_remote_build.ps1 -Upload    # IPA → TestFlight (нужны ascKeyId/ascIssuerId и .p8 на Mac)
   ```

## Вариант В. Облако Codemagic (без своего Mac)

`codemagic.yaml` в корне; настройка — docs/store/APP_STORE.md, §3.

## Если не собирается

| Ошибка | Что сделать |
|---|---|
| `No profiles for 'com.ogneliss.mail'` / `Signing requires a development team` | задать `--team`, войти в Apple ID в Xcode; один раз открыть `ios/Runner.xcworkspace` и нажать Signing & Capabilities → Try Again |
| `CocoaPods could not find compatible versions` | `cd ios && pod repo update && pod install` |
| `errSecInternalComponent` при сборке по SSH | не задан или неверен `keychainPassword` |
| `The sandbox is not in sync with the Podfile.lock` | `cd ios && pod install` |
| Ошибки в `*.g.dart` | `dart run build_runner build --delete-conflicting-outputs` |
| `altool` сообщает об устаревании | загрузить через Transporter |

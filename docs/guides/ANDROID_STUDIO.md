# Ogneliss Mail в Android Studio: запуск, проверка, публикация

Короткая версия по шагам (сервер + Android Studio) — `QUICKSTART.md`.

Проект — Flutter-приложение. В Android Studio открывается **корень проекта**
(папка с `pubspec.yaml`), а не папка `android\`.

Удобнее всего проверять под **Windows**: телефон не нужен, сборка и
перезапуск быстрее. Под Android можно запускать на **эмуляторе** (тоже без
телефона) или на телефоне по USB или Wi-Fi.

---

## Шпаргалка

Все команды — в терминале Android Studio (View → Tool Windows → Terminal),
в папке проекта.

| Что | Команда |
|---|---|
| Подготовка (один раз и после обновления архива) | `powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -Platforms "android,windows"` |
| Запуск под Windows | `flutter run -d windows --dart-define-from-file=config/dart_defines.json` |
| Список устройств и эмуляторов | `flutter devices` · `flutter emulators` |
| Запуск эмулятора | `flutter emulators --launch <id>` |
| Запуск на эмуляторе/телефоне | `flutter run -d <id> --dart-define-from-file=config/dart_defines.json` |
| Проверка кода | `flutter analyze` |
| Тесты | `flutter test` |
| Перегенерация кода базы (после правки таблиц) | `dart run build_runner build` |
| Ключ для Google Play (один раз) | `powershell -ExecutionPolicy Bypass -File scripts\create_upload_key.ps1` |
| Сборка для Google Play (AAB) | `flutter build appbundle --release --dart-define-from-file=config/dart_defines.json` |
| APK для установки вручную | `flutter build apk --release --dart-define-from-file=config/dart_defines.json` |
| Сборка Windows | `build_windows.bat` |

Во время `flutter run`: `r` — hot reload, `R` — перезапуск, `q` — выход.

---

## 1. Что установить (один раз)

| Что | Зачем | Как проверить |
|---|---|---|
| **Android Studio** (Narwhal 2025.1 или новее) | среда разработки, Android SDK, эмулятор | — |
| Плагины **Flutter** и **Dart** (File → Settings → Plugins → Marketplace) | запуск, отладка, hot reload | кнопка ▶ рядом со списком устройств |
| **Flutter SDK 3.38+** (Dart 3.10+) в пути без пробелов и кириллицы | компилятор | `flutter --version` |
| **Git** | Flutter и пакеты скачиваются через него | `git --version` |
| В SDK Manager (Settings → Languages & Frameworks → Android SDK): **Android SDK Platform 36**, вкладка SDK Tools — **Build-Tools**, **NDK (Side by side)**, **CMake**, **Command-line Tools**, **Android Emulator** | сборка APK (NDK нужен шифрованной SQLite), эмулятор | `flutter doctor` → Android toolchain ✓ |
| **Visual Studio 2022** (Community подходит), нагрузка **«Разработка классических приложений на C++»** с компонентом **C++ ATL** | сборка под Windows. Это не VS Code | `flutter doctor` → Visual Studio ✓ |
| **Режим разработчика Windows** | без него Flutter не подключает плагины под Windows | `start ms-settings:developers` → включить |
| **NuGet** в PATH | редактор писем под Windows (WebView2) | `nuget help` |

Flutter и NuGet из PowerShell:

```powershell
git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\src\flutter\bin", "User")
winget install Microsoft.NuGet
```

Закройте и снова откройте терминал (и Android Studio), затем:

```powershell
flutter doctor
flutter doctor --android-licenses     # принять лицензии Android SDK: y, y, y…
```

Нужны зелёные строки **Flutter**, **Windows Version**, **Visual Studio**,
**Android toolchain** и **Android Studio**.

Если в сети есть корпоративный прокси, перед командами задайте:

```powershell
$env:HTTPS_PROXY = "http://proxy.company.ru:3128"; $env:HTTP_PROXY = $env:HTTPS_PROXY
```

## 2. Подготовка проекта (один раз)

1. Распакуйте архив в короткий путь без пробелов и кириллицы, например
   `C:\dev\ogneliss`.
2. Android Studio → File → Open → `C:\dev\ogneliss`. Если Flutter SDK не
   найден: Settings → Languages & Frameworks → Flutter → Flutter SDK path =
   `C:\src\flutter`.
3. В терминале Android Studio:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -Platforms "android,windows"
   ```

   Скрипт создаёт папку `windows\`, скачивает пакеты (`flutter pub get`),
   генерирует код базы данных (`build_runner`) и иконки, создаёт
   `config\dart_defines.json`. Первый запуск — 5–10 минут.
4. Откройте `config\dart_defines.json` и впишите ключ OAuth-прокси:

   ```json
   {
     "OAUTH_PROXY_URL": "https://www.ogneliss.ru/oauth",
     "OAUTH_PROXY_KEY": "<вывод команды install-oauth-proxy.sh key на сервере>",
     "SUPPORT_EMAIL": "<адрес ИТ-поддержки>"
   }
   ```

   `SUPPORT_EMAIL` — адрес, на который «Журнал → Отправить в поддержку»
   отправляет журнал (пусто — адресат вписывается вручную); подставьте
   реальный адрес вашей поддержки.

   Без ключа не будет работать вход Google, Яндекс, Mail.ru и Yahoo.
   Exchange и IMAP с паролем от ключа не зависят. Файл в `.gitignore`;
   `setup.ps1` вписанное значение не затирает.
5. Android Studio предложит «Get dependencies» — согласитесь. Первая
   синхронизация Gradle (при запуске под Android) скачивает около 1 ГБ.

## 3. Запуск под Windows (рекомендуется для проверки)

1. В списке устройств на панели инструментов выберите **Windows (desktop)**.
2. В списке конфигураций — **Ogneliss Mail (debug)**.
3. **Run** (Shift+F10) или **Debug** (Shift+F9). Первая сборка — несколько
   минут, следующие — секунды.
4. Изменили код — **Hot reload** (Ctrl+\\), если не применилось —
   **Hot restart** (Ctrl+Shift+\\).

То же из терминала:

```powershell
flutter run -d windows --dart-define-from-file=config/dart_defines.json
```

**Что под Windows проверить нельзя** (работает только на Android): проверка
блокировки экрана телефона по политике Exchange (на Windows политика
выполняется PIN-кодом приложения), администратор устройства, синхронизация
с контактами и календарём телефона, «Поделиться» из других приложений.
Подробнее о Windows-версии — `BUILD_WINDOWS.md`, разделы 5–6.

## 4. Запуск на эмуляторе Android (без телефона)

1. Включите виртуализацию: в «Компонентах Windows» — **Платформа
   низкоуровневой оболочки Windows** (Windows Hypervisor Platform), в BIOS —
   VT-x / AMD-V. Перезагрузка.
2. Android Studio → **Device Manager** → **+** → Create Virtual Device →
   **Pixel 8** → образ **API 35 (x86_64, Google APIs)** → Finish → ▶.
3. В списке устройств выберите эмулятор → **Run**.

Из терминала:

```powershell
flutter emulators                               # список, например Pixel_8_API_35
flutter emulators --launch Pixel_8_API_35
flutter devices                                 # id эмулятора, обычно emulator-5554
flutter run -d emulator-5554 --dart-define-from-file=config/dart_defines.json
```

Эмулятор выходит в сеть через компьютер, в том числе через VPN, поэтому
корпоративный Exchange доступен так же, как с компьютера.

**Проверка политики Exchange на эмуляторе.** После подключения ящика с
политикой приложение покажет «Нужна блокировка экрана». В эмуляторе: Settings
→ Security → Screen lock → PIN, вернитесь в приложение — почта откроется.
Требования сервера видны в журнале приложения строкой «Политики: …».

## 5. Запуск на телефоне (по желанию)

1. На телефоне: Настройки → О телефоне → 7 раз нажать «Номер сборки»;
   затем в «Для разработчиков» включить **Отладку по USB** (или **Отладку по
   Wi-Fi**).
2. USB: подключите телефон, разрешите отладку в появившемся окне.
   Wi-Fi (Android 11+): Device Manager → **Pair Devices Using Wi-Fi** → QR-код.
3. `flutter devices` — телефон в списке → выберите его в Android Studio → **Run**.

Сборку **debug** нельзя поставить рядом с версией из магазина: у них один
идентификатор пакета и разные ключи подписи. Перед установкой из магазина
удалите debug-версию.

### Release на телефоне (быстрее debug)

Debug-сборка заметно тормозит: код выполняется интерпретатором с проверками.
Для ежедневной проверки на телефоне ставьте release:

```powershell
flutter devices                                  # id телефона, например NX721J
flutter run --release -d <id> --dart-define-from-file=config/dart_defines.json
```

В Android Studio: Run → **Edit Configurations…** → конфигурация main.dart →
поле **Additional run args**:
`--release --dart-define-from-file=config/dart_defines.json`.

- Подписывается ключом загрузки из `android/key.properties`, если файл есть
  (иначе — отладочным ключом).
- **Первый раз** после debug-версии Android откажется ставить поверх
  («подписи не совпадают»): удалите приложение `adb uninstall com.ogneliss.mail`
  и добавьте ящики заново. Дальше release ставится поверх release.
- Горячей перезагрузки (r / R) в release нет — после правок снова `flutter run`.
- Журнал приложения пишется и в release: Настройки → Журнал (логи).

Только собрать и поставить без запуска отладчика:

```powershell
flutter build apk --release --dart-define-from-file=config/dart_defines.json
flutter install -d <id>
```

## 6. Проверка перед сборкой

```powershell
flutter analyze        # ожидается: No issues found (или только info)
flutter test           # ожидается: All tests passed!
```

В Android Studio то же — конфигурация **Тесты (test/)**.

## 7. Ключ для Google Play (один раз)

В Google Play приложение подписывается двумя ключами:

- **ключ загрузки** (upload key) — ваш, им подписывается AAB при загрузке;
- **ключ подписи приложения** — хранит Google («Подписание приложений
  Google Play»), им подписаны установки на телефонах.

Потерю ключа загрузки можно исправить через поддержку Play Console (сброс
ключа), но это занимает дни. Создайте его скриптом:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create_upload_key.ps1
```

Скрипт:

1. находит `keytool` (из Android Studio);
2. спрашивает пароль (дважды, на экран не выводится);
3. создаёт ключ RSA 4096 на 10 000 дней в
   `%USERPROFILE%\.ogneliss\upload-keystore.jks` — **вне проекта**, чтобы ключ
   не попал в архив;
4. сохраняет рядом `upload_certificate.pem` — его просит Google при сбросе
   ключа загрузки;
5. записывает `android\key.properties` (в `.gitignore`; доступ — только вашей
   учётной записи Windows) и печатает отпечатки SHA-1 и SHA-256.

**Сразу сохраните** `upload-keystore.jks` и пароль в надёжном месте: сейф
паролей, зашифрованный носитель. Не в почте и не в мессенджере.

Варианты:

```powershell
# своё название организации в сертификате
.\scripts\create_upload_key.ps1 -DName "CN=Ogneliss Mail, O=Ogneliss, C=RU"
# не хранить пароль в key.properties — задавать при сборке
.\scripts\create_upload_key.ps1 -NoSavePassword
$env:OGNELISS_KEYSTORE_PASSWORD = "<пароль>"
```

Без `android\key.properties` выпускаемая сборка подписывается отладочным
ключом: на телефон её поставить можно, а магазины её не примут.

## 8. Сборка для публикации

1. Увеличьте версию в `pubspec.yaml`. Число после `+` (versionCode) должно
   расти при **каждой** загрузке в магазин:

   ```yaml
   version: 1.0.1+2
   ```

2. Соберите:

   ```powershell
   flutter build appbundle --release --dart-define-from-file=config/dart_defines.json
   ```

   Результат: `build\app\outputs\bundle\release\app-release.aab`.

3. Проверьте, что сборка подписана ключом загрузки (отпечаток SHA-256 должен
   совпасть с напечатанным скриптом):

   ```powershell
   keytool -printcert -jarfile build\app\outputs\bundle\release\app-release.aab
   ```

   Если `keytool` не в PATH:
   `& "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe" -printcert -jarfile …`

Другие варианты:

- APK для установки вручную или в RuStore:
  `flutter build apk --release --dart-define-from-file=config/dart_defines.json`
  → `build\app\outputs\flutter-apk\app-release.apk`.
- Windows: `build_windows.bat` → `build\windows\x64\runner\Release\`.
  Переносите папку целиком, а не только `.exe`.

## 9. Первая публикация в Google Play

1. Аккаунт разработчика Play Console. Для организации нужен номер D-U-N-S.
   У новых **личных** аккаунтов Google требует сначала закрытое тестирование
   (около 12 тестировщиков, 14 дней); у аккаунтов организаций такого
   требования нет.
2. Create app. Идентификатор пакета `com.ogneliss.mail` после первой загрузки
   сменить нельзя.
3. Начните с трека **Internal testing**: загрузите AAB, при первой загрузке
   оставьте включённым **«Подписание приложений Google Play»**.
4. Заполните:
   - **Data safety** — что приложение хранит и передаёт. Почта и пароли
     хранятся на устройстве в зашифрованном виде; на OAuth-прокси уходит
     только обмен кодами авторизации.
   - **Политика конфиденциальности** — по ссылке на сайте (текст:
     `docs/legal/PRIVACY_POLICY.md`).
   - **App access** — проверяющему нужен способ войти: тестовый ящик
     (IMAP или Exchange) или объяснение, что вход только для сотрудников.
   - Возрастной рейтинг, целевая аудитория, тексты страницы
     (`docs/store/STORE_LISTING.md` на 4 языках).
5. Приложение использует права администратора устройства (только тайм-аут
   блокировки экрана) и разрешение REQUEST_PASSWORD_COMPLEXITY. Будьте
   готовы объяснить проверяющим: так выполняются политики безопасности
   Exchange организации. Тексты для этого — раздел «Безопасность» в
   `docs/guides/USER_GUIDE.md`.

Для распространения только внутри организации (без публичной страницы) —
**Managed Google Play** через консоль MDM; AAB тот же.

## 10. Журнал приложения

Журнал ведётся всегда, на Android и на Windows, и в выпускаемой сборке
тоже: ошибки со стеком вызовов, шаги подключения и синхронизации, коды
ответов сервера. Адреса маскируются (`i***@corp.ru`), пароли и токены
в журнал не попадают. Размер — до 15 МБ, затем удаляется старая треть.

| Где | Путь |
|---|---|
| Windows | `%APPDATA%\com.ogneliss\Ogneliss Mail\logs\ogneliss.log` |
| Android | внутренняя папка приложения (`files/logs/ogneliss.log`); снаружи — только через экран «Журнал» |

В приложении: **Настройки → Журнал** или ссылка **«Журнал для поддержки»**
под ошибкой на экране входа.

- **Отправить в поддержку** — письмо из самого приложения: адресат
  `SUPPORT_EMAIL` из `config\dart_defines.json`, тема, шаблон текста и
  вложение `ogneliss-diagnostics-….zip`. Внутри архива — журнал и сводка:
  версия, устройство, ящики (тип, сервер, последняя ошибка), политика
  Exchange, состояние блокировки экрана, настройки сертификатов. Если ящика
  ещё нет (вход не удался): на Android откроется «Поделиться», на Windows —
  «Сохранить».
- **Сохранить журнал** — тот же архив через системный диалог: на Windows
  «Сохранить как», на Android — выбор папки, например «Загрузки».
- **Поделиться** (Android) — любая почта, мессенджер или диск.
- **Подробный журнал (24 часа)** — добавляет заголовки, фрагменты ответов
  сервера и деревья WBXML. Включайте, когда воспроизводите проблему: в журнал
  могут попасть фрагменты писем. Через сутки выключается сам. Куки и
  заголовки авторизации не записываются и в этом режиме.

При запуске из Android Studio журнал дополнительно выводится в окно **Run**
(в сборке debug).

## 11. Частые проблемы

| Сообщение | Что делать |
|---|---|
| `Building with plugins requires symlink support` | Включите режим разработчика: `start ms-settings:developers` |
| `Unable to find suitable Visual Studio toolchain` | Установите нагрузку «Разработка классических приложений на C++» в Visual Studio 2022 |
| `Nuget is not installed` | `winget install Microsoft.NuGet`, перезапустите Android Studio |
| `Target of URI doesn't exist: …g.dart` | Не сгенерирован код базы: `dart run build_runner build` |
| `flutter.sdk not set in local.properties` | `flutter pub get` в корне проекта |
| Ошибка NDK / `sqlite3` при первой Android-сборке | Установите NDK (Side by side) в SDK Manager; нужную версию Flutter пишет в тексте ошибки |
| `Failed to find target with hash string 'android-37'` | SDK Manager → SDK Platforms → отметьте Android SDK Platform 37 → Apply |
| `Android sdkmanager did not install NDK …` | SDK Manager → SDK Tools → Show Package Details → NDK (Side by side) нужной версии |
| `Android license status unknown` | `flutter doctor --android-licenses` |
| `Java version … 25 … incompatible with Gradle` | Сборке Android нужна Java 17 или 21: `winget install EclipseAdoptium.Temurin.21.JDK`, затем `flutter config --jdk-dir "<папка jdk-21…>"` и `cd android; .\gradlew --stop` |
| `this and base files have different roots`, `Starting AGP 9+, only the new DSL…` | С 1.6.3 проект на **AGP 9.1.0 / Gradle 9.3.1 / Kotlin 2.4.0** (как шаблон Flutter 3.47). В `android\gradle.properties` должны быть `android.newDsl=false` и `android.builtInKotlin=false` — без них часть плагинов не собирается |
| `WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP)` | Предупреждение, не ошибка: эти плагины ещё не перешли на встроенный Kotlin AGP 9. Пока в `gradle.properties` `android.builtInKotlin=false`, сборка идёт. Включать `true` — когда список станет пустым |
| Эмулятор не запускается, «HAXM / hypervisor» | Включите «Платформу низкоуровневой оболочки Windows» и виртуализацию в BIOS |
| `Keystore was tampered with, or password was incorrect` | Неверный пароль в `android\key.properties` или в `OGNELISS_KEYSTORE_PASSWORD` |
| Play Console: «подписано не тем ключом» | Сборка подписана отладочным ключом — нет `android\key.properties`; или загружен ключ не того проекта |
| Play Console: «version code уже используется» | Увеличьте число после `+` в `version:` в `pubspec.yaml` |
| Android Studio открыла папку `android\` как отдельный проект | Закройте её и откройте корень проекта, иначе не будет Flutter-запуска и hot reload |
| Вход Google/Яндекс: «собрано без ключа OAuth-прокси» | Впишите `OAUTH_PROXY_KEY` в `config\dart_defines.json` и перезапустите |

## 12. Где что лежит

| Путь | Что |
|---|---|
| `lib/` | приложение (Dart) |
| `packages/mail_engine/` | протокольный движок EWS / ActiveSync / IMAP / OAuth |
| `android/app/src/main/kotlin/com/ogneliss/mail/` | нативная часть Android (контакты, календарь, речь, фон, «Поделиться», безопасность устройства) |
| `android/app/build.gradle.kts` | пакет `com.ogneliss.mail`, подпись, minSdk |
| `config/dart_defines.json` | адрес и ключ OAuth-прокси (в git не попадает) |
| `scripts/` | `setup.ps1`, `build_windows.ps1`, `create_upload_key.ps1` |
| `server/oauth-proxy/` | OAuth-прокси и его установщик (`OAUTH_PROXY_DEBIAN.md`) |
| `test/` | модульные тесты |
| `docs/` | документация, аудит |

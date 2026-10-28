# Сборка Ogneliss Mail под Windows

Инструкция для первой и последующих сборок на компьютере с Windows 10/11 (x64).
Первая сборка занимает 10–20 минут (скачиваются пакеты, SQLite, PDFium,
WebView2 SDK), повторные — 1–3 минуты.

---

## 1. Что установить (один раз)

| Что | Зачем | Как проверить |
|---|---|---|
| **Flutter SDK 3.38 или новее** (Dart 3.10+) | компилятор и инструменты | `flutter --version` |
| **Visual Studio 2022** (Community подходит), нагрузка **«Разработка классических приложений на C++»** | сборка Windows-части | `flutter doctor` → строка Visual Studio ✓ |
| **Git** | Flutter и пакеты скачиваются через него | `git --version` |
| **Режим разработчика Windows** | без него Flutter не создаёт ссылки на плагины | `start ms-settings:developers` → включить |

**Visual Studio — это не Visual Studio Code.** VS Code — только редактор; для
сборки нужна именно Visual Studio с компилятором C++. В установщике отметьте
нагрузку «Разработка классических приложений на C++» и убедитесь, что в
составе выбраны:
- MSVC v143 (или новее) — средства сборки C++ x64/x86;
- Windows 11 SDK (10.0.22621 или новее);
- C++ CMake tools for Windows;
- C++ ATL для последних средств сборки (нужен части плагинов).

**Flutter**: распакуйте SDK в путь без пробелов и кириллицы (например,
`C:\src\flutter`) и добавьте `C:\src\flutter\bin` в PATH. Если Flutter уже
стоит, но старее 3.38: `flutter upgrade`.

**Проверка окружения:**
```powershell
flutter doctor
```
Должны быть зелёные строки **Windows Version** и **Visual Studio**. Строки про
Android и Chrome для сборки под Windows не важны.

Остальное скрипт сборки проверит и при необходимости сделает сам:
- **NuGet** (нужен редактору писем на WebView2) — скачается в `tools\nuget`;
- **WebView2 Runtime** уже есть в Windows 10/11; если редактор письма
  открывается пустым — установите «Microsoft Edge WebView2 Runtime».

**Интернет при первой сборке обязателен:** pub.dev (пакеты), GitHub
(готовая сборка SQLite, PDFium) и nuget.org. Если в сети корпоративный
прокси, задайте перед сборкой:
```powershell
$env:HTTPS_PROXY = "http://proxy.company.ru:3128"
$env:HTTP_PROXY  = $env:HTTPS_PROXY
```

---

## 2. Подготовка проекта

1. Распакуйте архив `ogneliss_android_studio.zip` в **короткий путь без пробелов и
   кириллицы**, например `D:\VS\OgnelissMail`. Длинные пути ломают MSBuild.
2. Если в папке был старый вариант проекта — удалите в ней `.dart_tool\`,
   `build\` и `pubspec.lock`. Папку `windows\` от прошлых сборок можно
   оставить: скрипт её проверит и дополнит.
3. *(Нужно только для входа через Google, Яндекс, Mail.ru.)* Скопируйте
   `scripts\.env.build.example` в `scripts\.env.build` и заполните
   `OAUTH_PROXY_URL` и `OAUTH_PROXY_KEY`. Для Exchange (ActiveSync/EWS) и
   IMAP с паролем это не требуется.

> **Не выполняйте `flutter pub upgrade --major-versions`.** Эта команда
> переписывает ограничения версий в `pubspec.yaml` на самые новые — и
> подтягивает версии пакетов с изменённым API (например, `enough_mail` 2.2,
> `flutter_local_notifications` 19+), под которые код не написан. Обычный
> `flutter pub get` (его вызывает скрипт) безопасен.

---

## 3. Сборка одной командой

Из корня проекта:

```bat
build_windows.bat
```
(двойной щелчок в Проводнике тоже работает)

или в PowerShell:
```powershell
.\scripts\build_windows.ps1            # релизная сборка
.\scripts\build_windows.ps1 -Run       # отладочный запуск с горячей перезагрузкой
.\scripts\build_windows.ps1 -Clean     # с полной очисткой (после смены версий)
.\scripts\build_windows.ps1 -SkipAnalyze
```

Что делает скрипт:
1. Проверяет Flutter (Dart 3.10+), режим разработчика, NuGet.
2. Создаёт `windows\`, если её нет (`flutter create --platforms=windows`;
   код в `lib\` не перезаписывается).
3. Дописывает в `windows\CMakeLists.txt` исправление для новых версий MSVC
   (ошибка `STL1011 <experimental/coroutine>` в `local_auth_windows` и
   `permission_handler_windows`).
4. `flutter pub get` → генерация кода БД (`build_runner`) → иконки.
5. `flutter analyze` — отчёт в `build\logs\analyze_<время>.txt`.
6. `flutter build windows --release` с параметрами OAuth-прокси.

**Результат:** `build\windows\x64\runner\Release\OgnelissMail.exe` (окно и свойства файла — «Ogneliss Mail»).
Чтобы перенести приложение на другой компьютер, копируйте **всю папку
`Release`** (exe, dll и папку `data`), а не только exe.

**Журнал каждой сборки** сохраняется в `build\logs\build_windows_<время>.log`.
Если сборка не прошла — пришлите этот файл и `analyze_<время>.txt`.

---

## 4. Если нужно вручную (без скрипта)

```powershell
flutter config --enable-windows-desktop
flutter create --platforms=windows --org com.ogneliss --project-name ogneliss .
```
Откройте `windows\CMakeLists.txt` и сразу после строки `project(...)` добавьте:
```cmake
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")
```
Название и имя exe скрипт тоже правит сам; вручную — в `windows\runner\Runner.rc`
(`CompanyName` = `com.ogneliss`, `FileDescription`/`ProductName` = `Ogneliss Mail`,
`OriginalFilename` = `OgnelissMail.exe`), `windows\runner\main.cpp`
(`window.Create(L"Ogneliss Mail", ...)`) и `windows\CMakeLists.txt`
(`set(BINARY_NAME "OgnelissMail")`).

Затем:
```powershell
flutter pub get
dart run build_runner build
dart run flutter_launcher_icons
flutter analyze
flutter build windows --release --dart-define=OAUTH_PROXY_URL=https://www.ogneliss.ru/oauth --dart-define=OAUTH_PROXY_KEY=<ключ>
```
Отладочный запуск: `flutter run -d windows`.

---

## 5. Где приложение хранит данные

| Что | Где |
|---|---|
| База данных | `%APPDATA%\com.ogneliss\Ogneliss Mail\ogneliss.db` (имя папки берётся из `windows\runner\Runner.rc`: CompanyName\ProductName; это AppData, не «Документы» — их часто синхронизирует OneDrive, и он блокирует файл базы во время записи). Файл **зашифрован** (SQLite3 Multiple Ciphers), ключ — в защищённом хранилище Windows. Базу от прежней сборки приложение шифрует само при первом запуске. Если ключ утерян, файл переименовывается в `ogneliss.db.unreadable-<время>`, и почта заново загружается с сервера |
| Журнал приложения | `%APPDATA%\com.ogneliss\Ogneliss Mail\logs\ogneliss.log` (до 15 МБ, затем старая треть удаляется). В приложении: Настройки → Журнал — «Сохранить журнал», «Отправить в поддержку», «Открыть папку журнала» |
| Пароли и токены | зашифрованное хранилище Windows (через `flutter_secure_storage`), не в базе |
| Журналы сборки | `build\logs\` в папке проекта |

Чтобы начать «с чистого листа» (например, после смены схемы БД во время
тестов), закройте приложение (в том числе из трея) и удалите папку
`%APPDATA%\com.ogneliss\Ogneliss Mail`.

---

## 6. Что работает на Windows, а что нет

**Работает:** Exchange по ActiveSync и EWS (гибрид), IMAP/SMTP, календарь,
контакты, задачи, заметки, HTML-редактор письма (WebView2), просмотр PDF,
вложения, офлайн-очередь, сворачивание в трей (закрытие окна прячет его в
трей; выход — правый щелчок по значку → «Выход»).

**Пока не работает на Windows (это не ошибка сборки):**
- **Системные уведомления** о новых письмах. Используемая версия плагина
  уведомлений Windows не поддерживает; приложение это учитывает и пишет в
  журнал «Уведомления ОС на этой платформе не поддерживаются». Переход на
  версию 19+ — в техническом долге.
- **Фоновая синхронизация при закрытом приложении** (WorkManager есть только
  на Android/iOS). На компьютере почта синхронизируется, пока приложение
  запущено или свёрнуто в трей.
- **«Поделиться» из других приложений** в письмо.
- **Вход через Google/Яндекс/Mail.ru** — только через OAuth-прокси
  (`OAUTH_PROXY_URL`): откроется системный браузер, ответ вернётся на
  `http://localhost:<порт>`. Брандмауэр может спросить разрешение — разрешите.

---

## 7. Типичные ошибки

| Сообщение | Причина и решение |
|---|---|
| `Building with plugins requires symlink support` | Не включён режим разработчика: `start ms-settings:developers` |
| `Unable to find suitable Visual Studio toolchain` | Не установлена нагрузка «Разработка классических приложений на C++» (см. раздел 1) |
| `error C2338: STL1011 ... <experimental/coroutine>` | Нет исправления в `windows\CMakeLists.txt`. Скрипт добавляет его сам; при ручной сборке — раздел 4, затем `flutter clean` |
| `Nuget is not installed` / ошибки `flutter_inappwebview_windows` | Нет NuGet в PATH. Скрипт скачивает его в `tools\nuget`; вручную: положить `nuget.exe` в любую папку из PATH |
| `version solving failed` | Конфликт версий пакетов. Не правьте `pubspec.yaml` наугад — пришлите вывод `flutter pub get` |
| `Directives must appear before any declarations`, `Expected to find ';'` | Синтаксическая ошибка в коде — пришлите журнал сборки |
| `These options have been removed and were ignored: --delete-conflicting-outputs` | Предупреждение новой версии `build_runner`, на сборку не влияет |
| `LNK1104: cannot open file ...OgnelissMail.exe` | Приложение ещё запущено (возможно, свёрнуто в трей). Выйдите через меню трея или диспетчер задач |
| `The filename or extension is too long` / ошибки путей MSBuild | Слишком длинный путь к проекту: перенесите в `D:\VS\OgnelissMail` или включите длинные пути: `reg add HKLM\SYSTEM\CurrentControlSet\Control\FileSystem /v LongPathsEnabled /t REG_DWORD /d 1 /f` |
| `Failed to load dynamic library 'sqlite3.dll'` при запуске | SQLite не скачался во время сборки (нет доступа к GitHub). Проверьте интернет/прокси, выполните сборку с `-Clean` |
| Ошибка сборки в хуке `sqlite3` («source: sqlite3mc», загрузка `sqlite3mc…`) | Сборка SQLite с шифрованием скачивается с GitHub (релизы пакета `sqlite3`). Нужен доступ к github.com / objects.githubusercontent.com; через прокси — переменные `HTTPS_PROXY`/`HTTP_PROXY` перед сборкой |
| Редактор письма — белый прямоугольник | Нет WebView2 Runtime — установите «Microsoft Edge WebView2 Runtime» |
| Скрипт PowerShell «отключён в этой системе» | Запускайте через `build_windows.bat` (он передаёт `-ExecutionPolicy Bypass`) |
| Сборка падает на случайных файлах, «доступ запрещён» | Антивирус блокирует папку `build\`. Добавьте папку проекта в исключения |

---

## 8. Первый запуск: проверка ActiveSync

От этого теста зависит решение по переходу на Kotlin, поэтому проверьте
основные сценарии и пришлите журнал приложения (Настройки → Диагностика →
Журнал), даже если всё прошло успешно.

1. **Подключение.** Добавьте корпоративный ящик. В журнале должны быть строки
   `MailEngine ...: подключено (eas, <сервер>)` и, если сервер отдаёт адрес
   EWS, `Гибрид EAS+EWS включён`.
2. **Папки и письма.** Список папок совпадает с Outlook; во «Входящих» видны
   письма за выбранный период, у писем есть получатели (кому/копия).
3. **Длинное письмо с таблицей.** Открывается полностью и с форматированием
   (тело догружается при открытии).
4. **Вложение.** Откройте письмо с файлом — файл скачивается и открывается.
5. **Изменения с компьютера.** В Outlook отметьте письмо прочитанным, поставьте
   флаг, удалите другое письмо → в приложении «Обновить» → изменения видны.
6. **Изменения с телефона/ПК-клиента.** Отметьте прочитанным и перенесите письмо
   в приложении → в Outlook видно то же.
7. **Пересылка с вложением** — письмо уходит с файлами (сервер прикладывает их
   сам, без скачивания).
8. **Офлайн.** Отключите сеть, отметьте письмо прочитанным и отправьте ответ →
   включите сеть → через несколько секунд ответ уходит, отметка доходит до
   сервера.
9. **Календарь.** События видны; удалённое в Outlook событие пропадает после
   обновления. Повторяющаяся встреча (например, ежедневная планёрка) видна
   в каждом дне, а не только в первом.
10. **Push.** Оставьте приложение открытым и отправьте себе письмо с другого
    устройства — оно появляется за секунды, без нажатия «Обновить» (в журнале
    `EAS push`/`Ping`).
11. **Шифрование базы.** После первого запуска в журнале нет ошибок открытия
    базы; файл `ogneliss.db` не начинается с текста `SQLite format 3` (можно
    проверить, открыв его в «Блокноте»: в начале — нечитаемые символы).

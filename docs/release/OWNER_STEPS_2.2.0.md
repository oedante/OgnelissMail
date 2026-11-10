# 2.2.0 — что сделать владельцу (09.11.2026)

2.2.0 (146). «Что нового» — `STORE_NOTES_2.2.0.md`. Версию в pubspec.yaml
не меняли (2.2.0+146 — с 08.11.2026).

## 1. Сервер ogneliss.ru — до выпуска

1. **Модели перевода для Windows** — `server/translate-models/README.md`:
   `sudo bash install-translate-models.sh install` (~670 МБ, нужны docker,
   curl, python3), раздел `location ^~ /mail/translate/` в Nginx Proxy
   Manager, затем `… check`. Без этого перевод на Windows виден, но языки
   не скачаются.
2. Прокси погоды (`server/weather-proxy`) — если ещё не развёрнут
   (`OWNER_STEPS_1.15.1.md`).

## 1а. Вход в Microsoft без сервера (по желанию, 10.11.2026)

Регистрация в Entra готова (ID клиента `64ce9eb1-5e0e-473c-9fd2-2ebe4554f986`).
Один ID — для всех платформ; платформа «Android» с хэшем подписи не нужна
(она для входа через Microsoft Authenticator, мы входим через браузер).

1. В Entra: «Мобильные и классические приложения» — адреса
   `com.ogneliss.mail://oauth/microsoft` и `http://localhost`; «Параметры →
   Разрешить потоки общедоступных клиентов» — Да; «Supported accounts» —
   организации и личные учётные записи; разрешения — как в шапке
   `lib/services/mail/oauth/direct_oauth.dart`.
2. В `config/dart_defines.json` — строка
   `"MS_CLIENT_ID": "64ce9eb1-5e0e-473c-9fd2-2ebe4554f986"`. Тот же файл
   берут сборки Android, iPhone, Mac и Windows; `scripts\setup.ps1` его
   больше не затирает. Для сборок на GitHub — то же в секрете
   `DART_DEFINES_JSON` (и в Codemagic, если используется).
3. Проверить на тестовой сборке: добавить ящик Outlook.com и ящик
   Microsoft 365 на телефоне и на компьютере. Ошибка «redirect_uri is not
   valid» — адрес из п. 1 не в той платформе (должен быть не «Web»).
   Ящики, добавленные раньше через сервер, продолжают работать через него.
   Без строки в п. 2 вход — как сейчас, через сервер ogneliss.ru.

## 1б. Вход в Яндекс без сервера (телефон и Mac)

Включён в сборке (ClientID `3c992385b6a24ce1992a7937d5954877`, тот же, что в
приложении). В oauth.yandex.ru у приложения должны быть платформы
«iOS-приложение» (App ID `<Team ID>.com.ogneliss.mail`) и
«Android-приложение» (`com.ogneliss.mail`, SHA-256 ключа подписи Google Play
и своего ключа загрузки — для RuStore и APK), права `mail:imap_full`,
`mail:smtp`, `login:info`, `login:email`, `calendar:all`,
`addressbook:all`. Проверить до выпуска: добавить ящик Яндекса на Android,
iPhone и Mac — браузер, выбор учётной записи, возврат в приложение; почта,
календарь и контакты синхронизируются. Ошибка в браузере про redirect_uri
— не та платформа или отпечаток в регистрации. В журнале — «OAuth (yandex):
вход без сервера входа».

## 2. Магазины

- **Google Play**: новых разрешений нет. Ключи управления (MDM) для ИТ-служб
  расширены — Play сам покажет их администраторам (`app_restrictions.xml`).
  Если в «Безопасности данных» указано, что приложение ничего не отправляет
  на свои серверы, — уточнить: на Windows языки перевода скачиваются с
  ogneliss.ru (текст писем не передаётся). Android это не касается.
- **Apple**: `project.pbxproj`, `Runner.entitlements`, `Info.plist` не
  менялись — в Xcode включать ничего не нужно.
- **Microsoft Store / сайт (Windows)**: в описание можно добавить «Перевод
  писем на компьютере — Bergamot (Mozilla), без отправки текста в интернет».

## 3. Сборка

Архив исходников — `tool/dev/make_archive.sh`; распаковать поверх папки
проекта.

- **Android**: `build_android.bat` (как у 2.1.0).
- **iPhone, iPad и Mac** — подробно ниже, в «3а».
- **Windows**: `scripts\build_windows.ps1` — сам допишет строку в
  `windows\CMakeLists.txt` и скачает движок перевода из npm (проверка
  sha256). В журнале — «Bergamot 0.4.9: …»; рядом с exe появится папка
  `data\bergamot`. Нужен доступ к registry.npmjs.org.
- **GitHub**: метка `v2.2.0` собирает все платформы; сборка Windows на
  GitHub проверяет, что `data/bergamot` на месте.

## 3а. iPhone, iPad и Mac

**В Xcode ничего менять не нужно.** `project.pbxproj`,
`Runner.entitlements`, `Info.plist` в 2.2.0 не менялись (кроме значков).
Вход в Google, Microsoft и Яндекс без сервера идёт через системное окно
входа (ASWebAuthenticationSession): схемы возврата (`com.ogneliss.mail`,
`yx3c99…`) оно ловит само — регистрировать их, добавлять Associated Domains
или SDK Яндекса не надо. Папку `macos/` пересоздавать не нужно.

**Единственное условие — `config/dart_defines.json` на Mac.** В архиве его
нет (там ключ прокси). Ключи `MS_CLIENT_ID` и `GOOGLE_*` попадут в сборку,
только если файл с ними лежит в `config/` той папки, где идёт сборка:
- сборка из Windows по SSH (`ios_remote_build.ps1`) копирует его сама;
- сборка прямо на Mac — скопировать файл вручную (тот же, что на Windows).
Нет строки `MS_CLIENT_ID` или `GOOGLE_IOS_CLIENT_ID` — этот вход идёт, как
раньше, через сервер. Скрипт пишет «⚠ Нет config/dart_defines.json», если
файла нет совсем.

### Вариант 1. Из Windows по SSH (только iPhone и iPad)

Один раз: на Mac «Удалённый вход» (SSH), ключ SSH с Windows, файл
`scripts\ios_remote.json` (образец — `scripts\ios_remote.example.json`:
адрес Mac, пользователь, Team ID, по желанию ключ App Store Connect и пароль
входа на Mac — без него подпись по SSH не пройдёт). Дальше:

```powershell
.\scripts\ios_remote_build.ps1 -Check     # проверить Xcode, Flutter, CocoaPods на Mac
.\scripts\ios_remote_build.ps1            # IPA → build\ios\ipa\ на Windows
.\scripts\ios_remote_build.ps1 -Upload    # IPA и сразу в TestFlight
```

Проект копируется на Mac без `project.pbxproj`, `Runner.entitlements` и
`Signing.xcconfig` — настройки Xcode на Mac не затираются.

### Вариант 2. Прямо на Mac (iPhone, iPad и Mac)

1. Распаковать архив поверх папки проекта, положить `config/dart_defines.json`.
2. Один раз — команда разработчика (запоминается вне проекта):
   ```bash
   scripts/build_ios.sh --team ABCDE12345
   ```
3. iPhone и iPad:
   ```bash
   scripts/build_ios.sh --check     # окружение
   scripts/build_ios.sh --run       # запуск на iPhone по кабелю или в симуляторе
   scripts/build_ios.sh             # IPA
   scripts/build_ios.sh --upload    # IPA и выгрузка в TestFlight
   scripts/build_ios.sh --prepare   # только подготовить → Xcode: Product → Archive
   ```
4. Mac (Intel и Apple Silicon одной сборкой):
   ```bash
   scripts/build_macos.sh --run       # запуск на этом Mac
   scripts/build_macos.sh             # .app в build/macos/Build/Products/Release
   scripts/build_macos.sh --archive   # архив для App Store → Xcode Organizer
   scripts/build_macos.sh --upload    # архив и выгрузка в TestFlight
   ```
   `--setup` — только если папки `macos/` ещё нет (её создаёт скрипт сам).

Ключ App Store Connect API (по желанию; без него — учётная запись Xcode):
`export ASC_KEY_ID=… ASC_ISSUER_ID=…`, файл
`~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`. Сборка по SSH —
ещё `KEYCHAIN_PASSWORD=<пароль входа на Mac>`. `--keep-lock` — не обновлять
версии пакетов (по умолчанию — как в сборке на GitHub). Подробно —
`docs/guides/BUILD_IOS.md` и `docs/guides/TESTFLIGHT.md`.

### Что проверить на iPhone и Mac после сборки

- Добавить ящик Яндекса, Outlook.com и Gmail: открывается окно входа
  провайдера, после выбора учётной записи — обратно в приложение. В
  журнале — «OAuth (yandex|microsoft|google): вход без сервера входа».
- Gmail, пока Google проверяет приложение: клиенты iOS, Android и Desktop
  должны быть в том же проекте Google Cloud, что и экран согласия, —
  тогда вход ведёт себя так же, как через сервер. Если Google не пускает
  или пишет «Google hasn't verified this app» — убрать строки `GOOGLE_*` из
  `dart_defines.json`, и Gmail пойдёт через сервер, как раньше.

## 4. Проверка на устройствах

- **Свайпы**: логика прежняя — одно действие на стороне срабатывает
  сразу, два — кнопки на выбор. После «Прочитано», «Флаг», «На контроль»
  (свайпом или кнопкой) — плашка с результатом и «Отменить» (лента и
  беседа); в беседе у письма — отметка «На контроле»; подписи папок —
  только архив, корзина, спам, свои папки. «Настройки → Свайпы → Короткий и
  длинный свайп» — по желанию: короткий — первое действие, длинный —
  второе, значок и подпись меняются, пока тянешь. При первом запуске после
  обновления первая строка один раз сама отъезжает (подсказка).
- **Нижняя панель** (телефон): «Настройки → Общие → Нижняя панель» —
  нажать место «Контакты» → «Мой день»: внизу «Мой день», «Контакты»
  появились в «Избранном» меню. Место «Почты» — только перестановка с
  другим разделом; место «Меню» — «Слева» / «Справа» (меню выезжает с той
  же стороны, то же — «Меню ящиков и папок» выше). «Поручения» и
  «Вложения» с панели открываются с панелью, «+» в «Поручениях» —
  «Поручить». «Как по умолчанию» — прежняя панель.
- **Совместимость со шлюзом** (Exchange, Windows, Mac, Linux): переключатель
  в ящике называется по платформе («как Почта Windows и Outlook», «как
  Почта Apple», «как Thunderbird…»); на шлюзе, который пропускает только
  известные программы, ящик должен подключаться.
- **«Мой день»**: доска (по умолчанию) и шкала; «Просрочено»; долгое нажатие
  на задачу — Сегодня / Завтра / След. неделя / Без срока / Выполнено /
  Удалить / Дата…; перетаскивание задачи на шкалу.
- **Поручения**: раздел меню; «Поручить» из письма и из календаря («+»);
  исполнитель с другой почтой отвечает «Принято» / «Готово» — статус
  меняется сам; поручение со сроком сегодня — в «Моём дне».
- **Перевод на Windows**: письмо на английском → «Перевести» → «Скачать»
  (русский и английский, ~45 МБ) → перевод; «Настройки → Почта → Перевод →
  Языки на устройстве» — список и удаление. Если перевода нет совсем — нет
  папки `data\bergamot` рядом с exe (сборка без движка).
- **MDM** (если есть тестовая консоль): `docs/guides/MDM.md`, отчёт консоли
  на Android.
- ✓/✓✓ у своих писем, «@» в ленте, «Найти в письме» (F4), «+» в быстром
  ответе — по «Что нового».

Ошибки — журналом (Настройки → Журнал → Отправить) или снимком экрана.

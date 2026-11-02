# 1.10.0 — что сделать владельцу (проверено 01–02.11.2026)

Сейчас у пользователей 1.8.12; после неё менялось только приложение. Здесь —
всё, что нужно сделать от 1.8.12 до 1.10.0, в том числе первая настройка
сигналов сервера: для iPhone — Push и ключ APNs у Apple, для Android —
Firebase у Google. Раньше их не настраивали.

## Порядок целиком

1. **Apple Developer** — Push у App ID и ключ APNs, шаг 2. Около 10
   минут; ключ нужен серверу.
2. **Firebase** — проект, приложение Android и ключ сервисного аккаунта,
   шаг 3. Около 15 минут; ключ нужен серверу, а ключи `FIREBASE_*` — сборке.
3. **Сервер** — архив `ogneliss-server-1.10.0.zip`, шаг 4. Служба сигналов
   ставится сразу с ключами из шагов 2 и 3.
4. **Сайт** — архив сайта и `deploy_site.sh`, шаг 6, «Политика
   конфиденциальности». Политика должна быть на сайте раньше, чем вы
   отправите приложение в магазины.
5. **Секреты GitHub** — шаг 1, вместе с ключами `FIREBASE_*` из шага 3.
   Затем метка `v1.10.0` на `main`: GitHub соберёт APK, App Bundle и сборки
   для компьютера и выложит страницу выпуска с «Что нового».
6. **Проверка на телефоне** — шаг 8, до выпуска для всех:
   - Android — внутреннее тестирование Google Play (Internal testing) или
     APK со страницы выпуска на телефоне без версии из Google Play (шаг 1,
     в конце);
   - iPhone — TestFlight.
7. **Google Play:**
   - App Bundle (`.aab`) — из артефакта сборки `ogneliss-android-…` в
     Actions или собрать из архива исходников;
   - «Что нового» — из `STORE_NOTES_1.10.0.md`;
   - «Безопасность данных» и строка о Google Translate — шаг 6;
   - сначала поэтапное развёртывание на 10–20 %.
8. **App Store:**
   - Xcode — шаг 5, в том числе Push Notifications;
   - сборка из архива исходников → TestFlight;
   - сборку 1.10.0 добавить в группу открытого тестирования (External
     Testing), из которой работает ссылка TestFlight на сайте. Apple
     проверяет каждую сборку для внешних тестировщиков, обычно до суток;
     до этого по ссылке ставится прежняя сборка;
   - в App Store Connect номер 1.8.12 поменять на 1.10.0;
   - «Конфиденциальность приложения» — шаг 6;
   - Notes, демо-ящик и видео — `APP_REVIEW_NOTES.md`.

Ниже по каждому шагу: что проверено в репозитории, что сделать вам и
готовые тексты.

## 1. Секреты GitHub — `guides/GITHUB_SECRETS.md`

GitHub собирает приложение из открытого репозитория. Там нет ваших
настроек входа и ключа подписи Android, поэтому их нужно один раз передать
GitHub как секреты. Значение секрета после сохранения не видно никому, в
том числе вам, и не попадает в сборки чужих копий репозитория.

Проверено: сборка (`.github/workflows/ci.yml`) читает ровно пять секретов,
ключи в `config/dart_defines.example.json` совпадают с теми, что читает
приложение.

### Куда вписывать

1. github.com → репозиторий **oedante/OgnelissMail** → вкладка
   **Settings** (вверху справа).
2. Слева **Secrets and variables → Actions** → кнопка **New repository
   secret**.
3. **Name** — имя ровно как в таблице ниже, **Secret** — значение →
   **Add secret**.
4. Заменить значение позже — карандаш рядом с секретом (**Update**).

### Пять секретов

| Секрет | Что вписать | Откуда взять |
|---|---|---|
| `DART_DEFINES_JSON` | содержимое файла `config/dart_defines.json` целиком, от `{` до `}` | ваш файл, см. ниже |
| `ANDROID_KEYSTORE_BASE64` | файл ключа загрузки `upload-keystore.jks`, переведённый в одну строку base64 | см. ниже |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища ключей | строка `storePassword=` в `android/key.properties` |
| `ANDROID_KEY_ALIAS` | имя ключа, обычно `upload` | строка `keyAlias=` там же |
| `ANDROID_KEY_PASSWORD` | пароль ключа | строка `keyPassword=` там же |

**`config/dart_defines.json`** — файл с настройками сборки. Он есть только
у вас, в папке проекта, рядом с `config/dart_defines.example.json`; в
архиве исходников его нет, и при распаковке нового архива он не
затирается. С ним вы собирали 1.8.12 для магазинов.

1. Откройте его в текстовом редакторе. Если файла нет (папку проекта
   заменяли целиком) — возьмите из прежней папки или из Codemagic
   (Environment variables), если собирали там. Нет и там — скопируйте
   `config/dart_defines.example.json` в `config/dart_defines.json` и
   заполните по таблице ниже.
2. Добавьте четыре ключа `FIREBASE_*` из шага 3, п. 3. Между строками —
   запятые, после последней строки запятой нет.
3. Проверьте, что файл читается:
   - Windows (PowerShell, в папке проекта):
     `Get-Content config\dart_defines.json -Raw | ConvertFrom-Json`;
   - macOS: `python3 -m json.tool config/dart_defines.json`.

   Ошибка — не хватает запятой или кавычки.
4. Выделите всё (Ctrl+A), скопируйте и вставьте в секрет
   `DART_DEFINES_JSON`.

Что значит каждый ключ файла:

| Ключ | Что это | Откуда взять |
|---|---|---|
| `OAUTH_PROXY_URL` | адрес сервера входа | оставить `https://www.ogneliss.ru/oauth` |
| `OAUTH_PROXY_KEY` | ключ приложения для сервера входа и службы сигналов | на сервере: `sudo grep '^PROXY_API_KEY=' /opt/mailserver/oauth-proxy/.env` — значение после `=` (если OAuth-прокси стоит без Docker — файл `/etc/ogneliss-oauth-proxy/oauth-proxy.env`). Не совпадает с сервером — вход и сигналы отвечают «HTTP 401» |
| `SUPPORT_EMAIL` | адресат письма «Отправить в поддержку» из журнала приложения | ваш адрес поддержки, тот же, что в Google Play |
| `GOOGLE_ANDROID_CLIENT_ID` | вход в Gmail прямо в Google, без сервера входа — Android | console.cloud.google.com → APIs & Services → Credentials → OAuth 2.0 Client IDs → клиент типа **Android** → Client ID (`…apps.googleusercontent.com`) |
| `GOOGLE_IOS_CLIENT_ID` | то же — iPhone и iPad | там же, клиент типа **iOS** |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | то же — компьютер | там же, клиент типа **Desktop app** → Client ID и Client secret |
| `MS_CLIENT_ID` | вход Outlook.com и Exchange Online (Microsoft 365) | entra.microsoft.com → App registrations → ваше приложение → Overview → **Application (client) ID** |
| `PUSH_RELAY_URL` | адрес службы сигналов | оставить `https://www.ogneliss.ru/push` |
| `PUSH_WAKE_MODE` | вид сигналов iPhone | оставить `silent` |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | Firebase для Android | шаг 3, п. 3 |
| `PUSH_WAKE_ANDROID_PRIORITY` | приоритет сигналов Android | оставить `normal` |

- Значения `GOOGLE_*` и `MS_CLIENT_ID`, которые уже есть в вашем файле, не
  меняйте: с ними работает 1.8.12. Если какое-то пусто, вход этой службы
  идёт через сервер входа — это тоже работает.
- Ключи `MAILRU_CLIENT_SECRET` (старый вход без сервера) и
  `OGNELISS_EXCHANGE` (Exchange и так включён) есть в коде, но не нужны.

**Ключ подписи Android.** Это тот же ключ загрузки, которым вы подписываете
App Bundle для Google Play.

1. Найдите файл `android/key.properties` в папке проекта. В нём четыре
   строки:
   - `storeFile` — где лежит ключ, обычно
     `C:\Users\<вы>\.ogneliss\upload-keystore.jks`;
   - `keyAlias` — обычно `upload`;
   - `storePassword` и `keyPassword` — пароли. Скрипт
     `create_upload_key.ps1` ставит в обе строки один и тот же пароль.
     Если строк с паролями нет (ключ создавали с `-NoSavePassword`), пароль
     — тот, что вы вводили при создании ключа; он же в переменной
     `OGNELISS_KEYSTORE_PASSWORD`, если собирали с ней.
2. Переведите файл ключа в строку base64 и вставьте её в секрет
   `ANDROID_KEYSTORE_BASE64` целиком:
   - Windows (PowerShell):
     `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.ogneliss\upload-keystore.jks")) | Set-Clipboard`
     — строка уже в буфере обмена, вставьте её (Ctrl+V);
   - macOS: `base64 -i upload-keystore.jks | pbcopy`.
3. По желанию — проверить, что ключ тот самый. Play Console → приложение →
   «Тестирование и выпуск» → «Настройка» → «Целостность приложения» →
   «Подписание приложений» (названия пунктов могут немного отличаться) →
   отпечаток SHA-1 **ключа загрузки** должен совпасть с выводом
   `keytool -list -v -keystore upload-keystore.jks -alias upload`.

### Проверить секреты до выпуска

GitHub → вкладка **Actions** → слева **CI/CD** → **Run workflow** → ветка
`main`, «Собрать Android» отмечено → **Run workflow**. Через 20–25 минут
откройте запуск → сводка (Summary): не должно быть предупреждений «Без
DART_DEFINES_JSON» и «Без ключа подписи».

### Выпуск — метка `v1.10.0`

После сервера, сайта и проверки секретов:

1. GitHub → **Releases** (справа на главной странице репозитория) →
   **Draft a new release**.
2. **Choose a tag** → впишите `v1.10.0` → «Create new tag: v1.10.0 on
   publish». Target — `main`.
3. Название и описание можно не заполнять: сборка сама заполнит их из
   `STORE_NOTES_1.10.0.md`. → **Publish release**.

Или из терминала в папке с клоном репозитория:
`git tag v1.10.0 && git push origin v1.10.0`.

Что собирает метка:

- Android: APK по архитектурам и App Bundle;
- iOS и macOS — без подписи;
- Windows и Linux;
- тесты на эмуляторе.

Страница выпуска с файлами появляется, если собрался Android. Тесты на
эмуляторе на выпуск не влияют. Тест окна письма на эмуляторе иногда
падает: из трёх прогонов 01.11 в двух падал разный тест, третий прошёл
целиком. Красный значок у задачи «emulator» выпуск не останавливает.

**APK с GitHub и версия из Google Play.** Google Play переподписывает
приложение своим ключом, поэтому APK с GitHub не встанет поверх версии из
Google Play («Приложение не установлено»), и наоборот. Если на телефоне
стоит версия из Google Play, проверяйте 1.10.0 так:

- загрузите App Bundle во внутреннее тестирование Google Play (Internal
  testing) и обновитесь оттуда;
- или проверьте APK на другом телефоне.

## 2. Apple Developer: Push и ключ APNs — `guides/IOS_PUSH_SETUP.md`

Без этого iPhone не получает сигналы «проверь почту». Тогда свёрнутое
приложение проверяет почту, только когда iOS сама его разбудит, — иногда
раз в час и реже. Остальное работает.

Проверено:

- приложение регистрирует токен уведомлений у службы сигналов
  (`AppDelegate.swift`, `push_wake_service.dart`);
- по умолчанию сигналы тихие (`PUSH_WAKE_MODE=silent` в
  `config/dart_defines.example.json`): ни расширения уведомлений, ни
  особого права Apple не нужно;
- `Info.plist` уже содержит фоновый режим `remote-notification`;
- служба шлёт сигналы с темой `com.ogneliss.mail` не чаще раза в 20 минут:
  чаще iOS тихие сигналы всё равно придерживает.

Что сделать: developer.apple.com → Account → **Certificates, Identifiers &
Profiles**.

1. **Identifiers → `com.ogneliss.mail`** → вкладка Capabilities → отметить
   **Push Notifications** → Save. Сертификаты (кнопка Configure рядом) не
   нужны: используем ключ.
2. **Keys → «+»:**
   - Key Name: `Ogneliss Push`;
   - отметить **Apple Push Notifications service (APNs)** → Configure;
   - Environment — **Sandbox & Production**, если есть такой вариант, иначе
     **Production**; Key Restriction — **Team Scoped (All Topics)**;
   - Save → Continue → **Register**.
3. **Download** — файл `AuthKey_XXXXXXXXXX.p8`. Скачать его можно только
   один раз. Запишите:
   - **Key ID** — 10 символов, они же в имени файла;
   - **Team ID** — Account → Membership details.
4. Копию `.p8` сохраните в менеджере паролей или на зашифрованном носителе.
   Это секрет, как `key.properties` и `*.jks`: не в проект, не в архив, не
   в почту. При утечке — **Revoke** на той же странице и новый ключ.

Ключ Production нужен для TestFlight и App Store. Ключ «Sandbox &
Production» подходит ещё и для сборок, запущенных прямо из Xcode.

Право фильтрации уведомлений (`IOS_PUSH_SETUP.md`, п. 1.1 и 1.3) для 1.10.0
не нужно. Оно понадобится для следующего этапа — расширения уведомлений,
которого пока нет в коде. Заявку можно подать заранее: Apple отвечает
неделями.

## 3. Firebase: сигналы для Android через Google — `guides/ANDROID_PUSH_SETUP.md`

То же, что ключ APNs для iPhone, только у Google: сервис Firebase Cloud
Messaging (FCM). Он бесплатный (план Spark), карта не нужна.

Без Firebase сигналы на Android получают только те, кто сам поставит
приложение UnifiedPush (ntfy и др.). У остальных свёрнутое приложение
проверяет почту, только когда Android разрешит: в глубоком сне он
откладывает проверки, а с Android 15 даёт фоновой синхронизации не больше 6
часов в сутки.

Проверено:

- `firebase-messaging` подключён в Android-части (BoM 35.1.0) без
  `google-services.json` и без Flutter-плагинов; параметры проекта
  берутся из dart-defines `FIREBASE_*`;
- пока этих ключей нет, варианта «Через Google» в настройках нет,
  остальное работает;
- с ключами сигналы по умолчанию идут через Google, UnifiedPush — по
  выбору в настройках;
- служба сигналов проверяет ключ сервисного аккаунта пробным сообщением
  Google (`validate_only` — никуда не доставляется);
- лицензии записаны в `docs/LICENSING.md`.

Что сделать:

1. **Проект.** console.firebase.google.com — лучше под аккаунтом
   разработчика, а не личным:
   - **Create a project** → имя, например `ogneliss-mail`;
   - Google Analytics — **выключить**;
   - Create project. План остаётся **Spark** (бесплатный).
2. **Приложение Android.** Обзор проекта → **Add app** → значок Android:
   - Android package name: `com.ogneliss.mail`;
   - App nickname — любое, **SHA-1 не нужен**;
   - **Register app** → **Download google-services.json**. Файл нужен,
     только чтобы взять из него значения. В проект его не класть;
   - шаги «Add Firebase SDK» пропустить: Next → Next → Continue to
     console.
3. **Четыре ключа в `config/dart_defines.json`.** Значения — из
   `google-services.json` (или ⚙ Project settings → General):

   | Ключ | Где в `google-services.json` |
   |---|---|
   | `FIREBASE_PROJECT_ID` | `project_info.project_id` |
   | `FIREBASE_SENDER_ID` | `project_info.project_number` |
   | `FIREBASE_APP_ID` | `client[0].client_info.mobilesdk_app_id` |
   | `FIREBASE_API_KEY` | `client[0].api_key[0].current_key` |

   - `PUSH_WAKE_ANDROID_PRIORITY` оставить `normal`;
   - эти значения не секретные: они есть в каждой сборке;
   - затем обновить секрет `DART_DEFINES_JSON` в GitHub (шаг 1) —
     содержимое файла целиком. В Codemagic — тоже, если собираете там.
     Без этого сборки по метке `v1.10.0` выйдут без сигналов через Google.
4. **FCM API.** ⚙ Project settings → вкладка **Cloud Messaging**: строка
   «Firebase Cloud Messaging API (V1)» должна быть *Enabled*. Если
   *Disabled* — ⋮ → Manage API in Google Cloud Console → **Enable**. Legacy
   API не нужен.
5. **Ключ сервисного аккаунта — для сервера.** ⚙ Project settings →
   вкладка **Service accounts** → Firebase Admin SDK → **Generate new
   private key** → Generate key. Скачается JSON
   `ogneliss-mail-…-firebase-adminsdk-….json`.
   - Это секрет, как `.p8`: менеджер паролей, не в почту, не в проект.
   - Утёк — Google Cloud Console → IAM & Admin → Service accounts → Keys
     → удалить и создать новый.
6. **Ключ на сервер** — шаг 4, той же командой, что и ключ APNs.

## 4. Сервер

Отдельный архив `ogneliss-server-1.10.0.zip` (обе службы) и короткая
памятка `СЕРВЕР_1.10.0.md` к нему. Папки те же, что `server/` в архиве
исходников. Распаковать на сервере: `unzip ogneliss-server-1.10.0.zip -d
/root/ogneliss-server`; ниже пути — от `/root/ogneliss-server/server`.

**OAuth-прокси.** Проверено:

- `server/oauth-proxy/package-lock.json` — body-parser 1.20.9 и qs 6.16.2
  (исправления уязвимостей);
- точка `GET /bimi` (`bimi.js`) включена по умолчанию (выключить —
  `BIMI=0` в `.env`);
- `install-oauth-proxy.sh update` копирует `server.js`, `bimi.js`,
  `package.json` и `package-lock.json`, перед этим сохраняет копию прежних
  файлов, секреты не трогает;
- синтаксис скриптов в порядке, 11 тестов BIMI проходят.

Обновить сервер:

```bash
sudo bash /root/ogneliss-server/server/oauth-proxy/install-oauth-proxy.sh update
sudo bash /root/ogneliss-server/server/oauth-proxy/install-oauth-proxy.sh check
```

Проверить снаружи, что BIMI отвечает: `curl -H "x-api-key: <OAUTH_PROXY_KEY>"
"https://www.ogneliss.ru/oauth/bimi?d=paypal.com"`. Ответ — JSON с полями
`policy` и `logo`.

**Служба сигналов — поставить с ключами APNs и Firebase.** Она нужна для
iPhone (шаг 2), для Android через Google (шаг 3) и для Android без сервисов
Google (UnifiedPush). Проверено:

- `install-push-relay.sh install` при первом запуске ставит службу в
  `/opt/mailserver/push-relay`, берёт ключ приложения из OAuth-прокси и
  проверяет ключи пробными сигналами Apple и Google;
- если служба уже стояла, та же команда обновляет её: `.env`, ключи и
  токены остаются, прежний `.env` сохраняется в `backup-<дата>`;
- скрипт копирует новый `webpush.js` и один раз создаёт ключ VAPID
  (`keys/vapid.pem`, нужен `openssl`);
- 7 автотестов проходят, в том числе шифрование по примеру из RFC 8291 и
  полный путь «регистрация → зашифрованный сигнал → удаление адреса по 410».

Скопировать ключи на сервер (со своего компьютера):

```bash
scp AuthKey_XXXXXXXXXX.p8 root@СЕРВЕР:/root/
scp ogneliss-mail-…-firebase-adminsdk-….json root@СЕРВЕР:/root/ogneliss-firebase.json
```

Установить (Team ID и имя файла `.p8` — свои, из шага 2):

```bash
sudo bash /root/ogneliss-server/server/push-relay/install-push-relay.sh install \
     --team ВАШ_TEAM_ID --key /root/AuthKey_XXXXXXXXXX.p8 \
     --fcm-service-account /root/ogneliss-firebase.json
```

- В выводе должны быть строки «ключ production принят Apple» и «ключ
  Firebase принят Google».
- Затем удалите `/root/AuthKey_…p8` и `/root/ogneliss-firebase.json`:
  копии лежат в `/opt/mailserver/push-relay/keys`.
- Firebase ещё не готов — запустите без строки `--fcm-service-account`, а
  ключ добавьте позже командой `key` (ниже).

Открыть адрес `/push` снаружи — Nginx Proxy Manager (панель
`http://IP-сервера:81`). При первой установке скрипт сам об этом напомнит.

1. Хост `ogneliss.ru` → Edit → вкладка **Advanced**.
2. Если там уже есть раздел «Сигналы для iPhone» (`location ^~ /push/`) —
   ничего не менять.
3. Если нет — сначала скопируйте прежнее содержимое, чтобы вернуть его при
   ошибке. Потом добавьте в конец поля этот блок (он же — в
   `site/nginx-landing.conf` архива сайта) → Save:

```nginx
location ^~ /push/ {
    access_log off;
    error_log /dev/null;
    client_max_body_size 8k;
    set $push push-relay;
    proxy_pass http://$push:8788;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 5s;
    proxy_read_timeout 20s;
}
```

Журнал запросов для этого адреса выключен — так обещано в политике
конфиденциальности (раздел 6.2).

Проверить:

```bash
sudo bash /root/ogneliss-server/server/push-relay/install-push-relay.sh check
curl https://www.ogneliss.ru/push/vapid     # ответ: {"key":"B…"}
```

В `check` все строки должны быть с ✓. Ошибки — `server/push-relay/README.md`,
раздел «Если не работает».

Добавить или заменить ключ Firebase позже:
`sudo bash …/install-push-relay.sh key --fcm-service-account
/root/ogneliss-firebase.json`.

## 5. Xcode

- **Push Notifications** — TARGETS → Runner → Signing & Capabilities →
  «+ Capability» → Push Notifications. Xcode сам добавит `aps-environment`
  в `Runner.entitlements`. Там же в **Background Modes** должна стоять
  галочка **Remote notifications**: она берётся из `Info.plist` архива.
  Если её нет — отметить. Keychain Sharing и цель расширения уведомлений
  из `IOS_PUSH_SETUP.md`, п. 2.1–2.2, для 1.10.0 не нужны. Новых файлов
  Swift с 1.8.12 нет: изменились только существующие, добавлять в проект
  ничего не нужно.
- **Communication Notifications** — `guides/IOS_COMMUNICATION_NOTIFICATIONS.md`,
  п. 2: TARGETS → Runner → Signing & Capabilities → + Capability.
  `Info.plist` уже содержит `NSUserActivityTypes` → `INSendMessageIntent`.
  Код в `AppDelegate.swift` готов. Без этой возможности уведомления
  обычного вида.
- **Siri и «Команды»** — включать ничего не нужно: App Intents в коде
  (`guides/IOS_SHORTCUTS.md`).
- **Перевод** — Xcode 16 или новее. Проверить запуск на iOS 15–17. Если
  падает с «Library not loaded: …/Translation.framework», подключить
  `Translation.framework` как Optional (`guides/TRANSLATION_SETUP.md`).

## 6. Тексты для сайта и магазинов

### Политика конфиденциальности

Обновлена в исходниках сайта (архив сайта приложен) на русском,
английском, немецком и французском. Редакция 1.7, действует с 1 ноября
2026 года. Что изменилось:

- **6.2 «Сигналы проверки почты»** — теперь и Android: через Google
  Firebase Cloud Messaging или через выбранный распространитель UnifiedPush
  (адрес и ключи шифрования вместо токена, сигнал зашифрован); приложение
  уже ссылается на этот раздел;
- **новый 6.3 «Логотипы отправителей (BIMI)»** — на сервер уходит только
  домен; кэш домен → логотип до 7 суток; домены не пишутся в журнал;
- **новый 6.4 «Перевод писем на устройстве»** — ML Kit на Android: модели
  скачиваются у Google, статистика работы без текста писем; Apple
  Translation на iOS;
- **таблица в разделе 3** — добавлены токен FCM, домен отправителя и текст
  при переводе; убрана строка о подсказках фраз (их убрали в 1.9.0);
- **разделы 7, 8, 9.1 и 11** — исправлено «не использует серверы
  push-уведомлений Google», добавлены передача Google и разрешение FCM;
- **раздел 4.4** — вместо абзаца о подсказках фраз: перевод писем, в том
  числе писем Gmail, идёт на устройстве, текст никуда не отправляется.

Выложить: `sudo bash deploy_site.sh /root/ogneliss-site-2026-11-02-v1.10.0-2.zip`
на сервере сайта. Скрипт сначала делает резервную копию страниц.

### Сайт: Google Play и TestFlight

В том же архиве сайта (02.11.2026) страница Ogneliss Mail на четырёх
языках:

- кнопка «Скачать в Google Play» ведёт на страницу приложения в магазине
  (было — «Тестирование в Google Play»);
- кнопка «iPhone и iPad: бета в TestFlight» ведёт на открытую ссылку
  `https://testflight.apple.com/join/tpZkBsSz` (было — приглашение по
  письму);
- раздел «Где установить» — то же текстом.

Сайт собран из версии 28.10 (архив сайта к 1.8.7). Если вы с тех пор
правили сайт у себя — сверьте файл `mail_src/content_*.py`.

### App Store Connect → «Конфиденциальность приложения» (App Privacy)

С этой версией iPhone впервые отправляет на сервер токен уведомлений. Если
в анкете его ещё нет, добавьте:

- «Идентификаторы» → «Идентификатор устройства»;
- цель — «Функциональность приложения»;
- не связан с личностью пользователя;
- не используется для отслеживания.

Перевод на iPhone идёт на устройстве (Apple Translation), логотипы BIMI —
домен чужого отправителя: в анкету они не попадают.

### Google Play → «Безопасность данных» (Data safety)

Что добавить к тому, что уже указано:

| Тип данных | Собирается | Передаётся третьим лицам | Зачем | Можно отказаться |
|---|---|---|---|---|
| Идентификаторы устройства или другие (токен FCM) | да | нет (Google — обработчик) | Функциональность приложения | да, переключатель «Сигналы сервера» |
| Идентификаторы устройства или другие (адрес UnifiedPush и ключи шифрования — только если выбран распространитель) | да | нет | Функциональность приложения | да, тот же переключатель |
| Сведения о приложении и производительности → Диагностика (статистика ML Kit) | да | нет (Google — обработчик) | Аналитика | да, перевод не обязателен |
| Идентификаторы устройства или другие (идентификатор установки ML Kit) | да | нет | Аналитика | да |

Во всех строках: данные передаются в зашифрованном виде; запрос на
удаление — по почте из политики.

Отсюда не открылась страница Google «ML Kit Data disclosure»
(developers.google.com/ml-kit/android/data-disclosure): сеть сеанса не
пускает на этот адрес. Сверьте с ней строки про ML Kit: там перечислено,
что отмечать.

Домен отправителя для BIMI в форму не попадает: это не данные
пользователя, а часть адреса чужого отправителя.

### Google Play → описание приложения: строка о Google Translate

Её требуют условия ML Kit. Добавить в конец полного описания:

- ru: `Перевод писем на Android выполняется на устройстве с помощью Google
  Translate (ML Kit): https://cloud.google.com/translate`
- en: `On Android, messages are translated on the device by Google Translate
  (ML Kit): https://cloud.google.com/translate`

В остальных языках описания — та же фраза на языке описания или
английская строка.

## 7. Apple

Notes, демо-ящик и видео — `release/APP_REVIEW_NOTES.md`. Номер версии
отклонённой записи в App Store Connect поменять с 1.8.12 на 1.10.0 и
выбрать сборку 1.10.0 (131).

## 8. Проверить на телефоне

1. **Первая загрузка нового ящика:** добавить ящик — «Входящие» заполняются
   сразу, без ожидания интервала.
2. **Темы и плотность ленты:** «Настройки → Оформление» — темы, цвет
   акцента, плотность (компактная, обычная, просторная). Включить
   «Анимация открытия письма»: на телефоне письмо закрывается свайпом вниз.
3. **Перевод:** письмо на другом языке → полоса «Перевести» → язык
   скачивается (Android, около 30 МБ) → «Показать оригинал». В «Написать»:
   «⋮ → Перевести», заменить или оставить оба текста. На iPhone нужна
   iOS 18 или новее.
4. **Даты в письмах:** письмо со словами «завтра в 15:00» или «12.11» — дата
   подчёркнута пунктиром. Нажатие открывает карточку «Встреча»,
   «Напоминание», «Копировать», «Открыть в календаре».
5. **Уведомления (Android):** письмо от контакта с фото — в уведомлении
   крупное фото отправителя. «Настройки → Уведомления → Уведомления как в
   мессенджерах».
6. **Siri и «Команды» (iPhone):** «Привет, Siri, новое письмо в Ogneliss
   Mail». В приложении «Команды» — действия Ogneliss Mail. Android:
   долгое нажатие на значок — «Написать письмо», «Создать встречу», «Мой
   день».
7. **Значки недоставленных писем:** письмо на несуществующий адрес
   (`nobody-12345@gmail.com`). Через несколько минут в «Отправленных»
   красная отметка; в письме — строка состояния и отчёт сервера.
8. **Заблокировать отправителя:** меню письма → «Заблокировать
   отправителя» → «Заблокировать». Письмо уходит в «Спам», следующее письмо
   с того же адреса — сразу туда и без уведомления. Список и «Снять» —
   «Настройки → VIP и правила → Заблокированные отправители и чистка». У
   ящика с Sieve или Exchange — правило появится и на сервере.
9. **Чистка:** меню письма рассылки → «Чистка» → «Оставлять только
   последнее письмо»: во «Входящих» остаётся одно письмо этого отправителя.
10. **Предупреждение о подделке:** письмо с адреса вида
    `support@sberbamk.ru` или с именем вашего контакта, но с чужого адреса,
    — красная плашка над письмом.
11. **Сигналы без Google (Android):** поставить ntfy (F-Droid или Google
    Play), в Ogneliss Mail — «Настройки → Уведомления → Как приходят сигналы
    → Через ntfy». Под переключателем — «Зарегистрировано …», через интервал
    — «Последний сигнал …». Нужна обновлённая служба сигналов (шаг 4).
12. **Клавиши (компьютер):** в открытом письме Ctrl+Q и Ctrl+U — прочитано
    и не прочитано, Insert — флажок, Backspace — в архив, F9 — проверить
    почту.
13. **Сигналы через Google (Android с сервисами Google Play, сборка с
    ключами `FIREBASE_*`):**
    - «Настройки → Уведомления → Сигналы сервера», «Как приходят
      сигналы» — «Через Google»; под переключателем «Зарегистрировано …»;
    - на сервере `install-push-relay.sh check` — «android 1»;
    - сверните приложение (можно и смахнуть из недавних) и подождите
      интервал — появится «Последний сигнал: …»;
    - «Android: Firebase options are empty» — в сборке пуст один из
      `FIREBASE_*` (шаг 3, п. 3; секрет `DART_DEFINES_JSON`);
    - «Android: SERVICE_NOT_AVAILABLE» — на телефоне нет сервисов Google
      Play или связи с Google.
14. **Сигналы сервера (iPhone, сборка из TestFlight):**
    - «Настройки → Уведомления → Сигналы сервера (iPhone)» — под
      переключателем «Зарегистрировано …»;
    - на сервере `install-push-relay.sh check` — «установок 1 (production
      1 …)»;
    - сверните приложение (не смахивайте) на 20–40 минут — в настройках
      появится «Последний сигнал: …»;
    - «Не удалось: iOS: …» — у цели Runner нет Push Notifications (шаг 5);
    - «Не удалось: … HTTP 401» — ключ приложения на сервере не совпадает со
      сборкой: `OAUTH_PROXY_KEY` в секрете `DART_DEFINES_JSON` должен
      совпадать с `PUSH_API_KEY` в `/opt/mailserver/push-relay/.env` (скрипт
      берёт его из `PROXY_API_KEY` OAuth-прокси);
    - iOS вправе придерживать тихие сигналы: энергосбережение, низкий
      заряд, приложение давно не открывали.

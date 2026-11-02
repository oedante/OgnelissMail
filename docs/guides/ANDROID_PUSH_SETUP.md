# Android: сигналы сервера для проверки почты в фоне — что сделать владельцу

Составлено 01.11.2026 (1.9.x, просьба владельца 31.10.2026). То же, что
«Сигналы сервера» на iPhone (`IOS_PUSH_SETUP.md`), но через Firebase Cloud
Messaging (FCM) — бесплатный сервис Google.

**Для выпуска 1.10.0** — по `release/OWNER_STEPS_1.10.0.md`, шаги 3 и 4: те
же пункты с командами для архива сервера 1.10.0.

**Коротко:** п. 1–2 (консоль Firebase) → п. 3 (`config/dart_defines.json`) →
п. 4 (ключ на сервер) → сборка → п. 5 (проверка) → п. 6 (политика, Google
Play).

## Как это работает

1. Приложение при запуске получает от Google токен FCM и регистрирует его на
   «будильнике» `ogneliss.ru/push` (та же служба `server/push-relay`, что для
   iPhone) с выбранным интервалом — 15, 30 или 60 минут. На сервер уходят
   только токен, интервал и вид сигнала — ни адресов, ни паролей, ни писем.
   Регистрация обновляется раз в сутки при запуске.
2. Сервер раз в интервал отправляет через FCM сообщение без текста
   (`{"w":"1"}`).
3. Телефон принимает его даже при выгруженном приложении. Приложение ставит
   проверку почты (разовая задача WorkManager) и проверяет ящики так же, как
   плановая проверка; о новых письмах — обычные уведомления.
4. Зачем: Android 15 даёт фоновой службе синхронизации не больше 6 часов в
   сутки, а в глубоком сне (Doze) откладывает проверки WorkManager.

Пока в сборке нет параметров Firebase (п. 3), функции нет и всё работает как
раньше. Сборки iPhone, Windows, macOS и Linux не меняются: Firebase
подключён только в Android-части (библиотекой Android, без Flutter-плагинов
FlutterFire и без `google-services.json`).

**Приоритет сигнала.** По умолчанию — обычный (`normal`): телефон не спит —
сигнал приходит сразу; в глубоком сне Android доставит его в ближайшее окно
обслуживания (обычно раз в 15–60 минут, ночью реже). Высокий (`high`) будит
сразу, но Google понижает приоритет приложениям, чьи срочные сообщения не
заканчиваются видимым уведомлением, а сигнал «проверь почту» чаще всего
пустой. Поэтому начинаем с `normal`; `high` — только для пробы, лучше с
интервалом 30–60 минут (п. 3).

## 1. Проект Firebase (бесплатный план Spark)

1. Откройте **console.firebase.google.com** под тем Google-аккаунтом, которым
   ведёте проект (лучше аккаунт разработчика, а не личный).
2. **Create a project** (Создать проект) → имя, например `ogneliss-mail` →
   Google Analytics — **выключите** (не нужен) → Create project.
3. План остаётся **Spark** (бесплатный): FCM бесплатен без ограничения числа
   сообщений, на Blaze переходить и привязывать карту не нужно.

## 2. Приложение Android в проекте

1. Обзор проекта → **Add app** → значок **Android**.
2. **Android package name:** `com.ogneliss.mail` (это `applicationId` в
   `android/app/build.gradle.kts`). Своя версия с другим идентификатором
   (`OWN_VERSION.md`) — её `applicationId`.
3. App nickname — любое; **SHA-1 не нужен** (для FCM не требуется).
4. **Register app** → **Download google-services.json** — файл пригодится,
   чтобы взять из него значения (п. 3), но **в проект его не кладите**
   (`android/app/` его и не читает, а `.gitignore` исключает). Шаги «Add
   Firebase SDK» пропустите (Next → Next → Continue to console): всё нужное
   уже есть в коде.

## 3. Параметры в `config/dart_defines.json`

Добавьте четыре строки (образец — `config/dart_defines.example.json`).
Значения — в консоли Firebase: ⚙ **Project settings** → вкладка **General**,
или в скачанном `google-services.json`:

| Ключ в `dart_defines.json` | Где в консоли | Где в `google-services.json` |
|---|---|---|
| `FIREBASE_PROJECT_ID` | Project ID (`ogneliss-mail-xxxxx`) | `project_info.project_id` |
| `FIREBASE_SENDER_ID` | Project number (12 цифр; он же Sender ID на вкладке Cloud Messaging) | `project_info.project_number` |
| `FIREBASE_APP_ID` | Your apps → Android → App ID (`1:1234…:android:abcd…`) | `client[0].client_info.mobilesdk_app_id` |
| `FIREBASE_API_KEY` | ключ Android (начинается с `AIza`) — проще взять из файла | `client[0].api_key[0].current_key` |

Пример:

```json
  "FIREBASE_API_KEY": "AIza…",
  "FIREBASE_APP_ID": "1:123456789012:android:0123456789abcdef",
  "FIREBASE_SENDER_ID": "123456789012",
  "FIREBASE_PROJECT_ID": "ogneliss-mail-xxxxx",
  "PUSH_WAKE_ANDROID_PRIORITY": "normal"
```

- Эти значения не секретные (они есть в каждой сборке), но
  `dart_defines.json` и так в `.gitignore`.
- GitHub (и Codemagic, если собираете там): обновите секрет
  `DART_DEFINES_JSON` (содержимое файла целиком).
- `PUSH_WAKE_ANDROID_PRIORITY` — `normal` (по умолчанию) или `high` (см.
  «Приоритет сигнала» выше). Менять сервер для этого не нужно.
- По желанию — ограничить ключ: Google Cloud Console → APIs & Services →
  Credentials → «Android key (auto created by Firebase)» → Application
  restrictions: Android apps (`com.ogneliss.mail` + SHA-1 ключа загрузки **и**
  ключа подписи Google Play — оба в Play Console → Настройка → Целостность
  приложения). Если SHA-1 указаны неверно, приложение не получит токен
  («Не удалось: Android: …»). Не уверены — не ограничивайте.

## 4. Ключ сервисного аккаунта — на сервер

1. Консоль Firebase → ⚙ Project settings → вкладка **Cloud Messaging**:
   строка **Firebase Cloud Messaging API (V1)** — *Enabled*. Если *Disabled* —
   ⋮ → Manage API in Google Cloud Console → **Enable**. Старый «Legacy API»
   не нужен.
2. Вкладка **Service accounts** → Firebase Admin SDK → **Generate new private
   key** → Generate key. Скачается JSON
   (`ogneliss-mail-xxxxx-firebase-adminsdk-….json`). У этого аккаунта уже есть
   право отправки.
   - Вариант с минимальными правами: Google Cloud Console → IAM & Admin →
     Service accounts → Create service account `push-relay` → роль
     **Firebase Cloud Messaging API Admin** → у аккаунта Keys → Add key →
     JSON.
   - Это **секрет**: храните в менеджере паролей, по почте не пересылайте, в
     git не кладите. Потеряли или утёк — там же удалите ключ (Keys → Delete)
     и создайте новый.
3. На сервер — код службы из нового архива и ключ (сеть и Nginx Proxy
   Manager не меняются — тот же адрес `/push`):

   ```bash
   scp -r server/push-relay root@СЕРВЕР:/root/
   scp ogneliss-mail-xxxxx-firebase-adminsdk-….json root@СЕРВЕР:/root/ogneliss-firebase.json
   sudo bash /root/push-relay/install-push-relay.sh install \
        --fcm-service-account /root/ogneliss-firebase.json
   rm /root/ogneliss-firebase.json
   ```

   Повторный `install` = обновление: `.env`, ключ Apple и токены iPhone
   остаются. Скрипт кладёт ключ в
   `/opt/mailserver/push-relay/keys/fcm-service-account.json` (читает только
   служба), прописывает `FCM_SERVICE_ACCOUNT_FILE` в `.env` и отправляет
   Google проверочное сообщение (`validate_only` — никуда не доставляется).
   Строка **«ключ Firebase принят Google»** значит, что ключ и право отправки
   в порядке. Ошибки — `server/push-relay/README.md`, «Если не работает».
4. Позже заменить ключ:
   `sudo bash /root/push-relay/install-push-relay.sh key --fcm-service-account НОВЫЙ.json`.

## 5. Проверка

1. Соберите Android с новым `dart_defines.json`
   (`flutter build appbundle --dart-define-from-file=config/dart_defines.json`
   или Codemagic) и установите на телефон с сервисами Google Play.
2. В приложении: **Настройки → Уведомления → Сигналы сервера** — включено по
   умолчанию; под переключателем «Зарегистрировано …». Если «Не удалось: …»:

   | Текст | Причина |
   |---|---|
   | `Android: SERVICE_NOT_AVAILABLE` / `MISSING_INSTANCEID_SERVICE` | нет сервисов Google Play или нет связи с Google |
   | `Android: Firebase options are empty` | в сборке пуст один из `FIREBASE_*` (п. 3) |
   | `Android: …API key…` / `…INVALID…` | неверные `FIREBASE_*` или ограничения ключа (п. 3) |
   | `… HTTP 400` | на сервере старая версия службы — п. 4.3 |
   | `… HTTP 401` | ключ приложения на сервере не совпадает со сборкой (`PUSH_API_KEY` = `OAUTH_PROXY_KEY`) |

3. На сервере: `sudo bash /root/push-relay/install-push-relay.sh check` —
   «установок N (… android 1)».
4. Сверните приложение (можно и смахнуть из недавних), выключите экран и
   подождите интервал. В настройках появится «Последний сигнал: …», в отчёте
   диагностики — строка «Сигналы сервера (Android, FCM): …», в журнале фоновой
   работы — записи «сигнал сервера».
5. По желанию — глубокий сон: `adb shell dumpsys deviceidle force-idle`. С
   обычным приоритетом сигнал придёт в окно обслуживания
   (`adb shell dumpsys deviceidle unforce` — вернуть).

## 6. Политика конфиденциальности и Google Play

- **Политика на сайте, раздел 6.2** — дополнить для Android: сигнал идёт
  через Google Firebase Cloud Messaging; токен уведомлений выдаёт Google, на
  сервере `ogneliss.ru/push` хранится так же, как токен iPhone (что, сколько,
  как удаляется — `server/push-relay/README.md`); нужны сервисы Google Play;
  выключить — тем же переключателем. Ссылка на условия Google:
  firebase.google.com/support/privacy. Выложить сайт — `site/DEPLOY.md`.
- **Google Play Console → Безопасность данных (Data safety):** «Идентификаторы
  устройства или другие идентификаторы» — собираются (токен FCM), цель —
  «Функциональность приложения», третьим лицам не передаются, пользователь
  может отказаться (переключатель), передача зашифрована.
- **RuStore** — то же в описании данных, если там его спрашивают.

## 7. Без сервисов Google — UnifiedPush (1.10.x)

Тот же «будильник», но сигнал доставляет приложение-распространитель
UnifiedPush на телефоне — его человек ставит сам: **ntfy** (F-Droid, Google
Play), NextPush (с Nextcloud), Sunup и др. Firebase для этого не нужен.

**Как работает.**
1. В Ogneliss Mail: «Настройки → Уведомления → Как приходят сигналы» —
   список установленных распространителей, выбрать нужный. Нет ни одного —
   там же подсказка поставить ntfy.
2. Распространитель выдаёт приложению адрес Web Push (например,
   `https://ntfy.sh/upXXXX`) и ключи шифрования этой установки; приложение
   регистрирует их на `ogneliss.ru/push` с `platform: unifiedpush`.
3. Сервер раз в интервал отправляет на этот адрес сигнал `{"w":"1"}`,
   зашифрованный по Web Push (RFC 8291) и подписанный ключом VAPID (RFC
   8292). Расшифровать его может только приложение на телефоне.
4. Распространитель будит приложение, оно ставит ту же проверку почты, что
   по сигналу FCM.

**Сервер.** Обновить службу (`install-push-relay.sh install` из нового
архива): установщик копирует `webpush.js` и один раз создаёт ключ VAPID
`keys/vapid.pem` (нужен `openssl`). Ключ не менять — установки,
зарегистрированные с прежним ключом, перестанут получать сигналы.
Проверка: `curl https://www.ogneliss.ru/push/vapid` → `{"key":"B…"}`.

Сервер ходит только на адреса `https://` с портом 443, которые указывают на
публичные адреса: внутрь своей сети по адресу из приложения он не пойдёт.

**Проверка на телефоне.** Поставить ntfy, выбрать его в настройках
Ogneliss Mail, дождаться «Зарегистрировано …», свернуть приложение и
подождать интервал — «Последний сигнал …». ntfy показывает регистрацию
Ogneliss Mail в своём списке подписок.

**Политика.** Раздел 6.2 уже описывает UnifiedPush: адрес и ключи вместо
токена, сигнал зашифрован и идёт через сервер распространителя, выбранный
человеком. В «Безопасности данных» — та же строка, что для токена FCM.

## Ограничения

- Через Google нужны **сервисы Google Play**. Телефоны без них (Huawei и
  Honor с HMS, прошивки без Google, сборки из RuStore) получают сигналы
  через UnifiedPush — раздел ниже.
- Приложение, остановленное принудительно (Настройки Android → Приложения →
  Остановить), сигналов не получает, пока его не откроют, — так устроен
  Android. Смахивание из недавних не мешает.
- Оболочки Xiaomi, Huawei, Honor и др. могут не давать запуск в фоне без
  «Автозапуска» — те же настройки, что уже подсказывает экран разрешений
  приложения.
- До Android 12 сигнал высокого приоритета ставит обычную (не срочную)
  задачу: в глубоком сне она ждёт окна обслуживания.

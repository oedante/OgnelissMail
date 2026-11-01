# push-relay — сигналы «проверь почту» для iPhone и Android

Служба для Ogneliss Mail 1.7.2+ (iPhone) и 1.9.x+ (Android). iOS не даёт
стороннему почтовому приложению регулярно проверять почту в фоне: когда будить
свёрнутое приложение, решает система, иногда раз в час и реже. Android 15
ограничивает фоновую службу синхронизации шестью часами в сутки, а в глубоком
сне (Doze) откладывает и проверки WorkManager. Служба раз в выбранный
пользователем интервал (15, 30 или 60 минут) отправляет пустой сигнал — на
iPhone через Apple Push Notification service (APNs), на Android через Firebase
Cloud Messaging (FCM). Получив его, приложение само, с телефона, проверяет
почтовые ящики и показывает уведомления о новых письмах.

Зачем и почему так — `docs/plan/IOS_BACKGROUND_DELIVERY.md`, что сделать
в Apple Developer и Xcode — `docs/guides/IOS_PUSH_SETUP.md`, в Firebase для
Android — `docs/guides/ANDROID_PUSH_SETUP.md`.

## Что служба знает

| Хранится (файл `data/tokens.json`) | Не хранится и не передаётся |
|---|---|
| токен уведомлений Apple или Google — случайный, свой у каждой установки | адреса, имена, пароли, токены входа |
| окружение (production / sandbox / fcm), интервал, вид сигнала | письма, контакты, календарь |
| время регистрации и последнего сигнала | IP-адреса (журнала запросов нет) |

К почтовым серверам служба не обращается. В журнал контейнера пишутся только
счётчики. Токен удаляется, когда пользователь выключает функцию, когда Apple
отвечает, что приложение удалено (410), когда Google отвечает `UNREGISTERED`
или `INVALID_ARGUMENT`, и сам — если приложение 30 дней не обновляло
регистрацию (приложение обновляет её раз в сутки при запуске).
Так это описано и в политике конфиденциальности Mail, раздел 6.2 (для
Android раздел нужно дополнить — `ANDROID_PUSH_SETUP.md`, п. 6).

## Виды сигнала

iPhone:

- **silent** (этап 1, сейчас): `content-available`, приоритет 5. iOS пропускает
  2–3 таких сигнала в час и не будит приложение, закрытое смахиванием, поэтому
  служба шлёт их не чаще раза в 20 минут (`MIN_SILENT_MINUTES`).
- **alert** (этап 2, после одобрения Apple права на фильтрацию уведомлений):
  обычный push с `mutable-content` для расширения уведомлений. Включается
  сборкой приложения (`PUSH_WAKE_MODE=alert`), сервер менять не нужно.

Android — сообщение FCM только с данными (`{"w":"1"}`, без уведомления),
`ttl` — интервал, но не больше 15 минут, `collapse_key` — один на все сигналы:

- **normal** (по умолчанию): обычный приоритет. Телефон не спит — сигнал
  приходит сразу; в глубоком сне Android доставит его в ближайшее окно
  обслуживания.
- **high**: высокий приоритет — будит и в глубоком сне. Google понижает до
  обычного приоритет приложениям, чьи срочные сообщения не заканчиваются
  видимым уведомлением, а сигнал «проверь почту» чаще всего пустой. Поэтому
  high — только по выбору сборки (`PUSH_WAKE_ANDROID_PRIORITY=high`) и лучше
  с интервалом 30–60 минут; сервер менять не нужно.

## Установка

Сервер — тот же, где OAuth-прокси и сайт: Docker, Nginx Proxy Manager
(контейнер `proxy-manager`), каталог `/opt/mailserver`.

Понадобятся из Apple Developer (`IOS_PUSH_SETUP.md`, п. 1.4): файл ключа
`AuthKey_<KEYID>.p8` и Team ID (10 символов, Membership details). Для
Android — ключ сервисного аккаунта Firebase, JSON
(`ANDROID_PUSH_SETUP.md`, п. 4); его можно поставить и позже командой `key`.

1. Скопируйте на сервер эту папку и ключ:

   ```bash
   scp -r server/push-relay root@СЕРВЕР:/root/
   scp AuthKey_XXXXXXXXXX.p8 root@СЕРВЕР:/root/
   ```

2. Установите:

   ```bash
   sudo bash /root/push-relay/install-push-relay.sh install \
        --team ABCDE12345 --key /root/AuthKey_XXXXXXXXXX.p8
   ```

   Скрипт кладёт службу в `/opt/mailserver/push-relay`, подключает контейнер к
   сети Nginx Proxy Manager (той же, что у `oauth-proxy`), берёт ключ
   приложения из `.env` OAuth-прокси (`PROXY_API_KEY` — с ним собрано
   приложение) и отправляет пробный сигнал Apple на несуществующий токен:
   строка «ключ production принят Apple» значит, что ключ, Team ID и Bundle ID
   верны. Затем удалите `/root/AuthKey_…p8` (копия — в
   `/opt/mailserver/push-relay/keys`, оригинал храните в менеджере паролей:
   Apple второй раз его не выдаст).

   Сигналы для Android — тот же скрипт с ключом Firebase (при первой
   установке — тем же вызовом `install`, добавив флаг):

   ```bash
   scp ogneliss-firebase.json root@СЕРВЕР:/root/
   sudo bash /root/push-relay/install-push-relay.sh key \
        --fcm-service-account /root/ogneliss-firebase.json
   ```

   Строка «ключ Firebase принят Google» значит, что ключ и право отправки в
   порядке. Затем удалите `/root/ogneliss-firebase.json` (копия — в
   `/opt/mailserver/push-relay/keys/fcm-service-account.json`).

3. Nginx Proxy Manager (панель `http://IP-сервера:81`): хост `ogneliss.ru` →
   Edit → **Advanced** → замените содержимое поля целиком на
   `site/nginx-landing.conf` из архива проекта (новый раздел «Сигналы для
   iPhone», `location ^~ /push/`). Сначала скопируйте прежнее содержимое —
   чтобы вернуть при ошибке. Save.

   > Можно и через **Custom locations** (`/push` → `push-relay`, порт 8788,
   > в настройках location — `access_log off;`), но там имя контейнера
   > записывается в `proxy_pass` как есть, и nginx проверяет его при запуске:
   > не поднялся контейнер — не стартует весь NPM, как было с `dialer-static`
   > 09.10.2026. Раздел в Advanced ищет контейнер при запросе. (Так же сейчас
   > подключён `/oauth` — при желании его можно перенести в Advanced таким же
   > разделом.)

4. Проверьте:

   ```bash
   sudo bash /root/push-relay/install-push-relay.sh check
   ```

   Все строки — ✓. Снаружи: `curl -s https://www.ogneliss.ru/push/healthz` →
   `{"ok":true,"ready":true,"fcm":true}` (`fcm` — есть ли ключ Firebase).

## Команды

| Команда | Что делает |
|---|---|
| `install` | первая установка; повторный запуск — как `update` |
| `update` | новый код из архива; `.env`, ключи и токены остаются (копия `.env` — в `backup-*`) |
| `key --key AuthKey_….p8 [--team ID]` | заменить ключ APNs или Team ID |
| `key --sandbox --key AuthKey_….p8` | отдельный ключ Sandbox — для сборок прямо из Xcode |
| `key --fcm-service-account FILE.json` | поставить или заменить ключ Firebase (Android) |
| `check` | контейнер, счётчики, пробные сигналы Apple и Google, адрес снаружи |
| `remove` | удалить контейнер (каталог с ключом и токенами остаётся) |

Ключ Sandbox не нужен, если проверяете через TestFlight или если ключ создан
«Sandbox & Production»: без отдельного ключа Sandbox служба подписывает
сигналы Sandbox ключом Production.

## Файлы на сервере

```
/opt/mailserver/push-relay/
  .env                     настройки и ключ приложения (600)
  keys/AuthKey_<KEYID>.p8  ключ APNs (640, читает только служба)
  keys/fcm-service-account.json  ключ Firebase для Android (640)
  data/tokens.json         токены установок
  docker-compose.push.yml  создаёт установщик
  server.js, Dockerfile, package.json
```

Зависимостей нет (Node.js 24, модули `http2`, `crypto` и встроенный `fetch`;
JWT для Google подписывается тем же `crypto`). Контейнер — только для чтения,
без прав, порт 8788 наружу не открыт: доступ только через NPM. Исходящие
соединения: `api.push.apple.com`, `oauth2.googleapis.com`,
`fcm.googleapis.com` (443).

Автотест (локальные заглушки Google, сеть не нужна): `npm test` в этой папке
(Node.js 18+).

## API (под `/push`)

| Запрос | Ответ |
|---|---|
| `GET /healthz` | `{"ok":true,"ready":<есть ключ APNs>,"fcm":<есть ключ Firebase>}`; изнутри контейнера — ещё счётчики |
| `POST /register` `{token, env, interval, mode}` + `x-api-key` | 204 (iPhone) |
| `POST /register` `{token, platform:"android", interval, mode:"normal"\|"high"}` + `x-api-key` | 204 (Android) |
| `POST /unregister` `{token[, platform]}` + `x-api-key` | 204 |
| `POST /probe` — только изнутри контейнера | принимают ли Apple и Google ключи |

Ограничение — 60 запросов в минуту с одного адреса (счётчик только в памяти).

## Если не работает

| Что видно | Причина и что сделать |
|---|---|
| `check`: «Apple не принимает ключ (403 InvalidProviderToken)» | неверны Key ID (имя файла), Team ID или ключ отозван — `key --key … --team …` |
| «подпись просрочена (ExpiredProviderToken)» | часы сервера: `timedatectl` (NTP должен быть включён) |
| «ключ не для Bundle ID (TopicDisallowed…)» | ключ с ограничением по теме — создайте ключ «Team Scoped (All Topics)» |
| «нет связи с Apple» | нет исходящего HTTPS из Docker к `api.push.apple.com:443` |
| снаружи 301/302/404 | в Advanced хоста нет раздела `location ^~ /push/` — п. 3 |
| снаружи 502 | контейнер не запущен или не в сети NPM: `docker network connect <сеть> push-relay` |
| в приложении «Не удалось: iOS: …aps-environment…» | у цели Runner нет Push Notifications — `IOS_PUSH_SETUP.md`, п. 2.1 |
| в приложении «Не удалось: … HTTP 401» | `PUSH_API_KEY` в `.env` не совпадает с `OAUTH_PROXY_KEY` сборки |
| сигналы отправляются, а телефон не просыпается | для тихих сигналов это нормально иногда: iOS придерживает их в режиме энергосбережения, при низком заряде, после смахивания приложения и у давно не открывавшегося приложения |
| `check`: «FCM: Google не принимает ключ (401)» | ключ сервисного аккаунта отозван или часы сервера расходятся — новый ключ: `key --fcm-service-account …` |
| «FCM: нет права отправки (403)» | в Google Cloud не включён Firebase Cloud Messaging API или у аккаунта нет роли — `ANDROID_PUSH_SETUP.md`, п. 4 |
| «FCM: проект не найден (404)» | ключ от другого проекта Firebase, чем приложение (`FIREBASE_PROJECT_ID` сборки) |
| в приложении (Android) «Не удалось: Android: SERVICE_NOT_AVAILABLE…» | на телефоне нет сервисов Google Play или нет связи с Google — сигналы на таком телефоне не работают, приложение проверяет почту как раньше |
| в приложении (Android) «Не удалось: … HTTP 400» | на сервере старая версия службы без Android — `update` |
| Android: сигналы отправляются, а проверки идут реже | обычный приоритет: в глубоком сне Android копит сигналы до окна обслуживания; так и задумано (п. «Виды сигнала») |

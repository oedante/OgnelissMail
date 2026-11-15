# Ogneliss Mail 2.5.5 — что сделать владельцу

Главное в 2.5.5 (решение владельца 15.11.2026): **вход — напрямую у служб.**
Google, Microsoft и Яндекс на телефонах и Mac входят и обновляют токены
прямо из приложения (OAuth 2.0 с PKCE). Сервер входа остаётся **только для
Яндекса на Windows и Linux** — у Яндекса там нет входа для приложений без
веб-клиента. Ключей Google, Microsoft, Mail.ru и Yahoo на сервере больше
нет: токены и данные Google через серверы Ogneliss не проходят. Сигналы о
новой почте и погода остаются. Логотипы отправителей (BIMI) переехали в
службу погоды и у ящиков Google не ищутся.

Порядок важен: сначала сборка и служба погоды, потом консоли и `.env`
сервера. Приложения до 2.5.5 после этого войти в Google и Microsoft уже не
смогут (Яндекс у них продолжит работать).

## 1. Сборка: клиенты служб в `config/dart_defines.json`

Без клиента служба на этой платформе входит только паролем приложения
(Gmail, Яндекс) или не входит совсем (Outlook.com, Exchange Online).

| Ключ | Где взять |
|---|---|
| `GOOGLE_ANDROID_CLIENT_ID` | console.cloud.google.com → APIs & Services → Credentials → клиент типа **Android**: пакет `com.ogneliss.mail`, SHA-1 ключа подписи из Play Console (App integrity → App signing key) и SHA-1 ключа загрузки для своих сборок; в «Advanced settings» клиента включить **Custom URI scheme** |
| `GOOGLE_IOS_CLIENT_ID` | там же, клиент типа **iOS**, Bundle ID `com.ogneliss.mail` (он же для Mac) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | там же, клиент типа **Desktop app** (Windows и Linux; секрет такого клиента Google секретом не считает) |
| `MS_CLIENT_ID` | entra.microsoft.com → App registrations → приложение → Overview → Application (client) ID |
| `OAUTH_PROXY_URL`, `OAUTH_PROXY_KEY` | оставить как есть: сервер входа для Яндекса на Windows и Linux, ключ — и для сигналов |
| `BIMI_URL` | не задавать (по умолчанию `https://www.ogneliss.ru/weather`) |

Тот же файл — в секрете GitHub `DART_DEFINES_JSON`. Проверка в сборке:
«Журнал для поддержки» → строка «Вход: напрямую у служб (Google да,
Microsoft да, …)». «нет — пароль приложения» — клиента нет.

Яндекс напрямую входит на телефонах и Mac, на Windows и Linux — через
сервер входа (в журнале: «Яндекс через сервер входа»).

## 2. Служба погоды — с логотипами

Скопируйте на сервер папку `server/weather-proxy` из архива и выполните:

```bash
sudo bash install-weather-proxy.sh install
```
```bash
sudo bash install-weather-proxy.sh check
```

Проверка: `https://www.ogneliss.ru/weather/healthz` — в ответе есть `"bimi"`.
В Nginx Proxy Manager ничего менять не нужно.

## 3. Консоли служб — убрать веб-клиенты

- **Google Cloud**:
  - Credentials → удалить OAuth-клиент типа **Web application** (адрес возврата `https://www.ogneliss.ru/oauth/callback`). Клиенты Android, iOS и Desktop app оставить.
  - Data Access → убрать `gmail.settings.basic`, сохранить и отправить на проверку.
- **Microsoft Entra** → App registrations → приложение:
  - Authentication → удалить платформу **Web** (адрес `…/oauth/callback`). Оставить «Mobile and desktop applications» (`com.ogneliss.mail://oauth/microsoft`, `http://localhost`), «Allow public client flows» = Yes.
  - Certificates & secrets → удалить секрет клиента (им пользовался сервер).
- **Яндекс** (oauth.yandex.ru): веб-платформу (адрес возврата `https://www.ogneliss.ru/oauth/callback`) **оставить** — через неё входят Windows и Linux. Платформы iOS и Android — тоже оставить.
- **Mail.ru** (o2.mail.ru) и **Yahoo**: удалить приложения сервера входа — Mail.ru и Yahoo подключаются паролем приложения.

## 4. Сервер входа — только Яндекс

После выхода 2.5.5 уберите из `.env` сервера ключи Google, Microsoft,
Mail.ru и Yahoo и выключите там логотипы (они теперь в службе погоды):

```bash
sudo bash ~/set-oauth-env.sh --yandex-only --dry-run
```
```bash
sudo bash ~/set-oauth-env.sh --yandex-only
```

Скрипт — `server/oauth-proxy/set-oauth-env.sh` (скачать: `curl -fsSLo
~/set-oauth-env.sh https://raw.githubusercontent.com/oedante/OgnelissMail/claude/next/server/oauth-proxy/set-oauth-env.sh`).
Копия прежнего `.env` остаётся рядом. Проверка:
`https://www.ogneliss.ru/oauth/healthz` — в `config` у `google`, `microsoft`,
`mailru`, `yahoo` стоит `"clientId": false`, у `yandex` — `true`.

## 5. Что увидят пользователи

- Ящики Google и Microsoft, добавленные через сервер входа, один раз
  покажут «Требуется вход» — «Войти снова» входит уже напрямую у службы.
- Ящики Яндекса работают как раньше (их токены по-прежнему обновляет
  сервер, если ящик добавлен через него).
- Логотипы отправителей у писем Gmail больше не показываются (вместо них
  буква).

## 6. Сайт и письмо Google

- Выложить сайт из архива `site-2026-11-15-v3.zip`: политика 1.9 (вход
  напрямую; сервер входа — только Яндекс на Windows и Linux), страница
  «Серверы и данные», Mac и TestFlight.
- Ответить Google в той же переписке письмом из ответа Claude (после
  шагов 1–4: тогда всё в нём — правда).

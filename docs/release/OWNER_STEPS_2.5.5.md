# Ogneliss Mail 2.5.5 — что сделать владельцу

Главное в 2.5.5 (решение владельца 15.11.2026): **сервера входа больше нет.**
Вход и обновление токенов идут только из приложений напрямую у Google,
Microsoft и Яндекса (OAuth 2.0 с PKCE). Токены и данные Google не проходят
через серверы Ogneliss. Сигналы о новой почте (push-relay) и погода
остаются. Логотипы отправителей (BIMI) переехали в службу погоды и у ящиков
Google не ищутся.

Порядок важен: сначала сборка и служба погоды, потом консоли и снятие
сервера входа. Приложения до 2.5.5 после снятия сервера войти в Google,
Microsoft и Яндекс уже не смогут.

## 1. Сборка: клиенты служб в `config/dart_defines.json`

Без клиента служба на этой платформе входит только паролем приложения
(Gmail, Яндекс) или не входит совсем (Outlook.com, Exchange Online).

| Ключ | Где взять |
|---|---|
| `GOOGLE_ANDROID_CLIENT_ID` | console.cloud.google.com → APIs & Services → Credentials → клиент типа **Android**: пакет `com.ogneliss.mail`, SHA-1 ключа подписи из Play Console (App integrity → App signing key) и SHA-1 ключа загрузки для своих сборок; в «Advanced settings» клиента включить **Custom URI scheme** |
| `GOOGLE_IOS_CLIENT_ID` | там же, клиент типа **iOS**, Bundle ID `com.ogneliss.mail` (он же для Mac) |
| `GOOGLE_DESKTOP_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_SECRET` | там же, клиент типа **Desktop app** (Windows и Linux; секрет такого клиента Google секретом не считает) |
| `MS_CLIENT_ID` | entra.microsoft.com → App registrations → приложение → Overview → Application (client) ID |
| `OAUTH_PROXY_KEY` | оставить как есть — теперь это только ключ сигналов сервера |
| `OAUTH_PROXY_URL` | больше не читается, можно удалить |
| `BIMI_URL` | не задавать (по умолчанию `https://www.ogneliss.ru/weather`) |

Тот же файл — в секрете GitHub `DART_DEFINES_JSON`. Проверка в сборке:
«Журнал для поддержки» → строка «Вход: напрямую у служб (Google да,
Microsoft да, …)». «нет — пароль приложения» — клиента нет.

Яндекс напрямую входит на телефонах и Mac. На Windows и Linux — паролем
приложения (у Яндекса нет входа для этих систем без сервера).

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
- **Яндекс** (oauth.yandex.ru) → приложение: удалить платформу «Веб-сервисы» (адрес возврата `…/oauth/callback`), оставить iOS и Android. Если у сервера было отдельное приложение Яндекса (`YANDEX_CLIENT_ID` в `.env` сервера не совпадает с идентификатором в приложении), удалить его целиком.
- **Mail.ru** (o2.mail.ru) и **Yahoo**: удалить приложения сервера входа — Mail.ru и Yahoo подключаются паролем приложения.

## 4. Снять сервер входа

После выхода 2.5.5 (тестировщики обновились):

```bash
sudo bash remove-oauth-proxy.sh --dry-run
```
```bash
sudo bash remove-oauth-proxy.sh
```

Скрипт лежит в `server/oauth-proxy`. Он сохраняет `.env` и данные в
`/root/oauth-proxy-removed-<дата>`, удаляет контейнер, образ и том.
Затем в Nginx Proxy Manager (хост ogneliss.ru → Advanced) удалите раздел
`location /oauth…`; разделы `/push/` и `/weather/` не трогайте. Проверка:
`https://www.ogneliss.ru/oauth/healthz` — 404.

## 5. Что увидят пользователи

- Ящики, добавленные через сервер входа, один раз покажут «Требуется
  вход» — «Войти снова» входит уже напрямую у службы.
- Ящик Яндекса на Windows или Linux, добавленный через сервер: войти
  снова через Яндекс там нельзя — удалить ящик и добавить паролем
  приложения (экран входа сам предложит пароль и ссылку на страницу
  паролей Яндекса).
- Логотипы отправителей у писем Gmail больше не показываются (вместо них
  буква).

## 6. Сайт и письмо Google

- Выложить сайт из архива `site-2026-11-15-v2.zip`: политика 1.9 без
  сервера входа, страница «Серверы и данные», Mac и TestFlight.
- Ответить Google в той же переписке письмом из ответа Claude (после
  шагов 1–4: тогда всё в нём — правда).

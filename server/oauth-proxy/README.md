# Ogneliss OAuth Proxy

Stateless-посредник OAuth: держит `client_secret` **на сервере**, ловит redirect
провайдера, меняет код на токены и обновляет их по refresh. Приложение секретов
не видит — в него уходит только access-токен и зашифрованный refresh-blob.

## Зачем

* **Секреты не в APK.** Клиент OAuth — этот прокси (тип «веб» в консолях), а не
  мобильное приложение. Отсюда: один client_id на все платформы, никаких
  package name / SHA-256, и `client_secret` невозможно вытащить реверсом.
* **Один redirect_uri** для всех провайдеров и всех платформ.
* **Обновление токенов** — на сервере (`POST /token` с blob).

## Файлы

| Файл | Назначение |
|---|---|
| `install-oauth-proxy.sh` | **Установщик** для Debian 11/12: `install`, `update`, `check`, `key`. Docker рядом с почтой (за Nginx Proxy Manager) или systemd + nginx на чистом сервере. Инструкция — `docs/guides/OAUTH_PROXY_DEBIAN.md`. |
| `setup-oauth-ogneliss.sh` | Устарел: вызывает `install-oauth-proxy.sh --mode docker`. Раньше содержал старую копию server.js. |
| `setup-mail-tls-ogneliss.sh` | Установка валидного TLS-сертификата в docker-mailserver (чтобы почтовые клиенты подключались по 993/587). |
| `server.js`, `package.json`, `package-lock.json`, `Dockerfile`, `docker-compose.oauth.yml` | Исходники прокси; установщик берёт их из этой папки — копируйте на сервер папку целиком. |
| `.env.example` | Шаблон конфигурации. Реальный `.env` — только на сервере, в git не коммитится. |
| `../../docs/guides/OAUTH_UPDATE_2026-10.md` | **Обновление 10.2026**: календарь и контакты Gmail/Яндекса, Mail.ru — пошагово. |
| `PROVIDERS.md` | Что заполнять в консолях Google / Яндекс / Microsoft / Mail.ru. |
| `docs/guides/OAUTH_UPDATE_2026-10.md` | **Обновление октября 2026:** права календаря и контактов (Google, Яндекс), пароль приложения Mail.ru, порядок шагов. |
| `OGNELISS-OAUTH.md` | Два режима размещения (путь на домене / поддомен) + настройка NPM. |
| `MAIL-TLS-OGNELISS.md` | TLS для `mail.ogneliss.ru`. |

## Установка

Скопируйте на сервер **всю папку** `server/oauth-proxy`, затем:

```bash
# Сервер с почтой, прокси уже работает (как на ogneliss.ru) — обновить:
sudo bash install-oauth-proxy.sh update

# Первая установка рядом с почтой (Docker + Nginx Proxy Manager):
sudo bash install-oauth-proxy.sh install --base-url https://www.ogneliss.ru/oauth

# Чистый Debian 11/12 (Node.js + systemd + nginx + Let's Encrypt):
sudo bash install-oauth-proxy.sh install --base-url https://oauth.ogneliss.ru --email admin@ogneliss.ru

# Проверка и ключ для сборки приложения:
sudo bash install-oauth-proxy.sh check
sudo bash install-oauth-proxy.sh key
```

`ENC_SECRET`, `PROXY_API_KEY` и `STATE_SECRET` создаются один раз и при
обновлении не меняются. Подробно — `docs/guides/OAUTH_PROXY_DEBIAN.md`.

## Эндпоинты

При `BASE_URL=https://www.ogneliss.ru/oauth` все пути идут с префиксом `/oauth`.

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/` | заглушка (статус + список эндпоинтов) |
| GET | `/healthz` | проверка живости: `{"ok":true,"providers":[...]}` |
| GET | `/oauth/:provider/login?redirect=` | старт авторизации (302 к провайдеру) |
| GET | `/callback` | приём кода, обмен на токены, возврат в приложение |
| POST | `/exchange` | одноразовый код `oc` + `cv` → токены (PKCE), нужен API-ключ |
| GET/POST | `/token` | выдать действующий access (авто-refresh), нужен API-ключ |
| POST | `/refresh`, `/revoke` | обновление / отзыв |

## Поток в приложении

```
app → <BASE_URL>/oauth/google/login?redirect=com.ogneliss.mail://oauth
прокси → провайдер (redirect_uri = <BASE_URL>/callback)
провайдер → прокси /callback?code=...    (обмен на токены, secret на сервере)
прокси → app  com.ogneliss.mail://oauth?oc=..&provider=..   (одноразовый код)
app → POST <BASE_URL>/exchange {oc, cv} + x-api-key → {access_token, rt, ...}
```

Возврат в приложение: своя схема (Android/iOS/macOS) или `http://localhost:{port}`
(Windows/Linux) — оба варианта разрешены в `ALLOWED_REDIRECTS` / проверке loopback.

## Модель токенов — stateless (важно)

Базы нет. Refresh-токен шифруется ключом `ENC_SECRET` (AES-256-GCM) и хранится
**в приложении** как blob. На `/token` приложение присылает blob, прокси
расшифровывает, обновляет и возвращает новый access. Потеря `ENC_SECRET` = все
blob'ы недействительны (потребуется повторный вход).

## Безопасность

* `.env` — права `600`, в git не коммитится (`.gitignore`).
* `PROXY_API_KEY` — обязателен для `/token`, `/refresh`, `/revoke`.
* `ALLOWED_REDIRECTS` — защита от open-redirect (плюс разрешён loopback).
* `STATE_SECRET` — подпись `state` (защита CSRF).
* Секреты, попавшие в git-историю или чат, **перевыпускать** в консолях провайдеров.

## Сборка приложения под этот прокси

```bash
flutter build apk \
  --dart-define=OAUTH_PROXY_URL=https://www.ogneliss.ru/oauth \
  --dart-define=OAUTH_PROXY_KEY=<PROXY_API_KEY из .env>
```

Проще — через единый скрипт сборки: `scripts/setup.sh --build apk`
(читает секреты из `.env.build`, см. корневой `README.md`).

## Изменения безопасности (аудит, октябрь 2026)

- **PKCE между приложением и прокси.** Новые версии приложения передают на
  `/oauth/:provider/login` параметр `cc` (SHA-256 от случайного секрета).
  Тогда в адрес возврата уходит только одноразовый код `oc` (действует
  2 минуты), а токены приложение получает по `POST /exchange {oc, cv}` с
  заголовком `x-api-key`. Старые версии приложения (без `cc`) по-прежнему
  получают `at`/`rt` в адресе возврата.
- Ответы с ошибками — `text/plain` (значение `error` от провайдера больше не
  вставляется в HTML).
- Сравнение ключа API и подписи state — за постоянное время; неверная
  подпись даёт 400, а не 500.
- Запуск останавливается, если не заданы `STATE_SECRET` или `PROXY_API_KEY`
  (раньше подставлялся случайный ключ, и после перезапуска все refresh-blob
  становились недействительными). Если `ENC_SECRET` не задан, ключ шифрования,
  как и раньше, выводится из `STATE_SECRET` — ранее выданные blob продолжают
  работать.
- Заголовки `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `Cache-Control: no-store`; ограничение тела запроса 16 КБ.

Порядок обновления: сначала сервер (он совместим со старыми приложениями),
затем приложение.

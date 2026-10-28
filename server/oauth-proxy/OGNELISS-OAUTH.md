# OAuth-прокси Ogneliss на домене (рядом с почтовым сервером)

Почтовый сервер уже занимает порты 80/443 через **Nginx Proxy Manager (NPM)**. Поэтому
OAuth-прокси запускается **контейнером** в той же Docker-сети, а NPM проксирует
поддомен `oauth.ogneliss.ru` на него с валидным Let's Encrypt. Это снимает прежнее
ограничение самоподписанного IP — **Google и Microsoft теперь работают**.

## Шаги

### 1. DNS
Добавьте A-запись: `oauth.ogneliss.ru` → `217.114.43.126`.
(Почта остаётся на `mail.ogneliss.ru` — не трогаем.)

### 2. Развернуть контейнер OAuth-прокси
Скопируйте на сервер всю папку `server/oauth-proxy` и запустите от root (подробно — `docs/guides/OAUTH_PROXY_DEBIAN.md`):
```bash
sudo bash install-oauth-proxy.sh install --base-url https://oauth.ogneliss.ru
```
Скрипт: создаёт `/opt/mailserver/oauth-proxy/` со встроенными server.js/Dockerfile/
compose, генерирует секреты в `.env` (BASE_URL=https://oauth.ogneliss.ru), определяет
сеть NPM, собирает и запускает контейнер `oauth-proxy` в этой сети.

### 3. Proxy Host в NPM (панель http://217.114.43.126:81)
Hosts → Proxy Hosts → Add:
- Domain Names: `oauth.ogneliss.ru`
- Scheme: `http`, Forward Hostname: `oauth-proxy`, Forward Port: `8787`
- SSL → Request a new Let's Encrypt Certificate, Force SSL, HTTP/2.

Проверка: `curl https://oauth.ogneliss.ru/healthz` → `{"ok":true,...}`.

### 4. Провайдеры
Заполните `client_id`/`client_secret` в `/opt/mailserver/oauth-proxy/.env` (см.
PROVIDERS.md), redirect_uri в консолях: `https://oauth.ogneliss.ru/oauth/callback`.
Затем: `cd /opt/mailserver/oauth-proxy && docker compose -f docker-compose.oauth.yml up -d`.

### 5. Сборка приложения
```bash
flutter build apk \
  --dart-define=OAUTH_PROXY_URL=https://oauth.ogneliss.ru \
  --dart-define=OAUTH_PROXY_KEY=<PROXY_API_KEY из .env>
```
Схема редиректа приложения теперь `com.ogneliss.mail://oauth`. С валидным TLS домена
доверять самоподписанному сертификату больше НЕ нужно (но авто-механизм в приложении
остаётся безвредным).

## Почему контейнер, а не systemd+nginx
NPM уже владеет 80/443 — второй nginx конфликтовал бы. Контейнер в сети NPM позволяет
проксировать по имени (`oauth-proxy:8787`) и получить сертификат Let's Encrypt штатно.

## Два режима размещения прокси

Прокси можно повесить либо на **свой поддомен**, либо **на путь основного домена**.
Режим задаётся одной переменной `BASE_URL` — всё остальное (пути маршрутов,
`redirect_uri`, инструкции для NPM) выводится из неё автоматически.

### Вариант 1 — путь на домене (рекомендуется, если платный сертификат покрывает www)

```bash
sudo bash install-oauth-proxy.sh install --base-url https://www.ogneliss.ru/oauth
```

* Отдельный сертификат **не нужен** — используется имеющийся для `www.ogneliss.ru`.
* В NPM: Proxy Host для `www.ogneliss.ru` → вкладка **Custom locations** → Add location:
  * Define location: `/oauth`
  * Scheme: `http`, Forward Hostname: `oauth-proxy`, Forward Port: `8787`
* `redirect_uri` для консолей провайдеров: `https://www.ogneliss.ru/oauth/callback`
* Сборка приложения: `--dart-define=OAUTH_PROXY_URL=https://www.ogneliss.ru/oauth`

### Вариант 2 — отдельный поддомен

```bash
sudo bash install-oauth-proxy.sh install --base-url https://oauth.ogneliss.ru
```

* Нужен **сертификат на этот поддомен**. Платный GlobalSign для `ogneliss.ru`
  покрывает `www`, `autodiscover`, `mail`, `owa` и `ogneliss.ru`, но **не `oauth.*`** —
  поэтому в NPM выбирайте **Request a new SSL Certificate (Let's Encrypt)**, иначе
  браузер будет ругаться на несоответствие имени.
* `redirect_uri`: `https://oauth.ogneliss.ru/oauth/callback`

### Проверка (для обоих режимов)

```bash
curl $BASE_URL/healthz     # {"ok":true,"providers":[...]}
curl $BASE_URL/            # заглушка со списком эндпоинтов
```

В логе контейнера при старте видно и режим, и точный redirect_uri:
```
oauth-proxy listening on 0.0.0.0:8787 (base https://www.ogneliss.ru/oauth, path '/oauth')
redirect_uri для консолей провайдеров: https://www.ogneliss.ru/oauth/callback
```

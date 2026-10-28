# OAuth-прокси на Debian 11/12: установка и настройка

OAuth-прокси нужен для входа в Gmail, Яндекс, Mail.ru, Yahoo и Outlook.com.
Прокси хранит `client_secret` провайдеров на сервере, меняет код авторизации на
токены и обновляет их. Приложение секретов не видит. Exchange и IMAP с паролем
работают без прокси.

Всё делает один скрипт: `server/oauth-proxy/install-oauth-proxy.sh`.

---

## 1. Что понадобится

| Что | Зачем |
|---|---|
| Сервер Debian 11, 12 или 13 (подходит и Ubuntu 22.04+), доступ root | здесь будет работать прокси |
| Домен с HTTPS, например `www.ogneliss.ru` | Google и Microsoft не принимают IP и самоподписанный сертификат |
| `client_id` и `client_secret` провайдеров | см. `server/oauth-proxy/PROVIDERS.md` |

> **Debian 11.** Бесплатная поддержка Debian 11 (LTS) закончилась
> 31 августа 2026 года. Прокси на нём работает, но обновлений безопасности
> системы больше нет. Запланируйте переход на Debian 12. Скрипт для Debian 12
> тот же.

## 2. Какой вариант выбрать

Скрипт определяет вариант сам. Если на сервере есть `/opt/mailserver` или
контейнер Nginx Proxy Manager, выбирается **docker**, иначе **native**.

| | docker | native |
|---|---|---|
| Где | рядом с почтовым сервером в Docker | на чистом сервере |
| Веб-сервер | Nginx Proxy Manager (уже стоит) | nginx из Debian, ставится скриптом |
| Сертификат | тот, что уже в NPM | Let's Encrypt (бесплатно, автопродление) или свой, например GlobalSign |
| Как работает сейчас на ogneliss.ru | **да** | — |
| Файл настроек | `/opt/mailserver/oauth-proxy/.env` | `/etc/ogneliss-oauth-proxy/oauth-proxy.env` |

Адрес прокси задаётся одним параметром `--base-url`:

- `https://www.ogneliss.ru/oauth` — **путь на сайте** (рекомендуется).
  Подходит существующий сертификат `www`, отдельная DNS-запись не нужна.
- `https://oauth.ogneliss.ru` — **свой поддомен**. Нужны DNS-запись и
  сертификат именно на этот поддомен (GlobalSign для `ogneliss.ru` его не
  покрывает).

Тот же адрес указывается в сборке приложения (`OAUTH_PROXY_URL`). Из него
получается `redirect_uri` для консолей провайдеров:
`https://www.ogneliss.ru/oauth/callback` (путь на сайте) или
`https://oauth.ogneliss.ru/oauth/callback` (поддомен).

## 3. Скопировать файлы на сервер

Нужна **вся папка** `server/oauth-proxy`: скрипт берёт из неё `server.js` и
`package-lock.json`.

С Windows (PowerShell, OpenSSH встроен в Windows 10/11):

```powershell
scp -r C:\dev\ogneliss\server\oauth-proxy root@IP-СЕРВЕРА:/root/
```

Или через WinSCP: перетащите папку `oauth-proxy` в `/root/`.

Дальше все команды выполняются на сервере:

```bash
ssh root@IP-СЕРВЕРА
cd /root/oauth-proxy
```

## 4А. Сервер с почтой (docker) — как сейчас на ogneliss.ru

Прокси там уже работает, поэтому достаточно **обновить** его:

```bash
sudo bash install-oauth-proxy.sh update
```

Что делает обновление:

1. Сохраняет копию старых файлов и `.env` в `/opt/mailserver/oauth-proxy/backup-ДАТА/`.
2. Заменяет `server.js` на версию после аудита: одноразовый код вместо токенов
   в адресе возврата.
3. Дописывает в `.env` недостающие параметры. `ENC_SECRET`, `PROXY_API_KEY` и
   `STATE_SECRET` **не меняет**: пользователи остаются в своих аккаунтах, а
   уже собранные приложения продолжают работать.
4. Пересобирает и перезапускает контейнер `oauth-proxy`, затем запускает
   проверку (раздел 7).

Сначала обновите сервер, потом раздавайте новую версию приложения. Новый
прокси работает и со старыми версиями приложения, а новое приложение со
старым прокси войти не сможет.

**Первая установка рядом с почтой** (если прокси ещё не было):

```bash
sudo bash install-oauth-proxy.sh install --base-url https://www.ogneliss.ru/oauth
```

В конце скрипт напишет, что настроить в Nginx Proxy Manager (`http://IP:81`):

- **Путь на сайте:** Hosts → Proxy Hosts → хост `www.ogneliss.ru` → вкладка
  *Custom locations* → *Add location*: location `/oauth`, scheme `http`,
  hostname `oauth-proxy`, port `8787`.
- **Поддомен:** новый Proxy Host `oauth.ogneliss.ru` → `oauth-proxy:8787`.
  На вкладке SSL выберите Let's Encrypt, включите Force SSL.

## 4Б. Чистый сервер (native)

1. DNS: A-запись домена указывает на IP сервера. Порты 80 и 443 должны быть
   открыты снаружи.
2. Установка с бесплатным сертификатом Let's Encrypt:

   ```bash
   sudo bash install-oauth-proxy.sh install \
     --base-url https://oauth.ogneliss.ru \
     --email admin@ogneliss.ru
   ```

   Со своим сертификатом (например, GlobalSign; в первом файле — сертификат и
   цепочка, во втором — закрытый ключ):

   ```bash
   sudo bash install-oauth-proxy.sh install \
     --base-url https://oauth.ogneliss.ru \
     --tls existing --cert /etc/ssl/ogneliss/fullchain.pem \
     --cert-key /etc/ssl/ogneliss/privkey.pem
   ```

Что ставится:

| Компонент | Где |
|---|---|
| Node.js 24 (репозиторий NodeSource; в Debian 11 из коробки только Node 12) | `/usr/bin/node` |
| Прокси | `/opt/ogneliss-oauth-proxy/` |
| Настройки и секреты (права 640, root:ogneliss-oauth) | `/etc/ogneliss-oauth-proxy/oauth-proxy.env` |
| Служба systemd от отдельного пользователя `ogneliss-oauth`, с ограничениями доступа | `ogneliss-oauth-proxy.service`, слушает только `127.0.0.1:8787` |
| Сайт nginx | `/etc/nginx/sites-available/ogneliss-oauth-proxy.conf` |
| Блок `location` для прокси | `/etc/nginx/snippets/ogneliss-oauth-proxy.conf` |
| Журнал nginx без параметров запроса (коды OAuth в журнал не попадают) | `/var/log/nginx/ogneliss-oauth.access.log` |

Если в nginx **уже есть сайт с этим доменом**, его файл скрипт не трогает и
просит добавить одну строку внутрь `server { … }`, который слушает 443:

```nginx
include snippets/ogneliss-oauth-proxy.conf;
```

После этого выполните `nginx -t && systemctl reload nginx`.

## 5. Провайдеры: client_id и client_secret

Откройте файл настроек:

```bash
nano /opt/mailserver/oauth-proxy/.env               # docker
nano /etc/ogneliss-oauth-proxy/oauth-proxy.env      # native
```

Заполните пары `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`, `YANDEX_…`,
`MAILRU_…`, `YAHOO_…`, `MS_…`. Значения пишите **без кавычек**. Затем
примените изменения:

```bash
cd /opt/mailserver/oauth-proxy && docker compose -f docker-compose.oauth.yml up -d   # docker
systemctl restart ogneliss-oauth-proxy                                              # native
```

`docker compose restart` не перечитывает `.env`. Нужна именно команда `up -d`.
Если на сервере старый Docker без `docker compose`, пишите `docker-compose`.

Если секреты у вас в отдельном файле `KEY=VALUE`, их можно подгрузить одной
командой:

```bash
sudo bash install-oauth-proxy.sh update --secrets /root/provider-secrets.env
shred -u /root/provider-secrets.env
```

Из такого файла берутся только параметры провайдеров. `ENC_SECRET`,
`PROXY_API_KEY` и `STATE_SECRET` пропускаются.

В консоли каждого провайдера тип приложения — **«Веб»**. `redirect_uri` —
ровно тот, что напечатала команда `check`. Подробности по каждому провайдеру —
в `server/oauth-proxy/PROVIDERS.md`.

> **Yahoo и Mail.ru.** Прежние client secret этих провайдеров были переданы
> через чат, поэтому их нужно считать раскрытыми. Перевыпустите оба в
> консолях провайдеров и впишите новые только в `.env` на сервере.

## 6. Ключ для сборки приложения

```bash
sudo bash install-oauth-proxy.sh key
```

Команда выводит готовое содержимое `config/dart_defines.json`:

```json
{
  "OAUTH_PROXY_URL": "https://www.ogneliss.ru/oauth",
  "OAUTH_PROXY_KEY": "…"
}
```

Сохраните его в `config/dart_defines.json` проекта: конфигурации запуска
Android Studio подхватят файл сами. Не пересылайте ключ через мессенджеры и
почту.

**Без ключа вход через прокси не работает.** Приложение получает токены
командой `POST /exchange`, а она требует ключ. Если сборка сделана без
ключа, при попытке входа появится сообщение «приложение собрано без ключа
OAuth-прокси».

## 7. Проверка

```bash
sudo bash install-oauth-proxy.sh check
```

| Строка | Что значит, если ✗ | Что делать |
|---|---|---|
| служба / контейнер | прокси не запущен | `journalctl -u ogneliss-oauth-proxy -n 50` или `docker logs oauth-proxy` |
| локально отвечает | процесс запущен, но не отвечает | смотрите журнал; частая причина — в `.env` нет `STATE_SECRET` или `PROXY_API_KEY` |
| снаружи отвечает | не доходит через nginx/NPM | проверьте location `/oauth` в NPM или строку `include` в nginx, DNS, сертификат |
| `/exchange` → 404 | на сервере старая версия прокси | `sudo bash install-oauth-proxy.sh update` |
| ключ не принят | прокси запущен со старым `.env` | `docker compose … up -d` или `systemctl restart …` |
| сертификат истекает | осталось меньше 14 дней | Let's Encrypt продлевается сам (`systemctl status certbot.timer`); GlobalSign — заменить файлы |
| провайдер «не настроен» | нет `client_id`/`client_secret` | раздел 5 |

## 8. Обслуживание

**Обновление** (после нового архива проекта): скопируйте папку
`server/oauth-proxy` и выполните `sudo bash install-oauth-proxy.sh update`.

**Журналы:**

```bash
docker logs --tail 100 oauth-proxy               # docker
journalctl -u ogneliss-oauth-proxy -n 100        # native
```

**Резервная копия.** Главное — файл `.env`/`oauth-proxy.env`. Скрипт
сохраняет его при каждом обновлении в `backup-ДАТА/` рядом с прокси (права
только для root). Храните копию и вне сервера, в защищённом месте.

**Что будет, если поменять секрет:**

| Секрет | Последствия |
|---|---|
| `ENC_SECRET` | все пользователи OAuth-аккаунтов должны войти заново |
| `PROXY_API_KEY` | нужно пересобрать и раздать приложение с новым ключом |
| `STATE_SECRET` | прервутся входы, начатые в эту минуту; больше ничего |
| client secret провайдера | ничего для пользователей, если поменять в `.env` и перезапустить |

## 9. Частые проблемы

- **`apt-get update` на Debian 11 выдаёт 404.** После окончания поддержки
  репозитории bullseye со временем переезжают на `archive.debian.org`.
  Замените адреса в `/etc/apt/sources.list` или обновитесь до Debian 12.
- **certbot не получил сертификат.** DNS ещё не указывает на сервер или
  порт 80 закрыт. Повтор: `certbot --nginx -d ДОМЕН`.
- **`redirect_uri_mismatch` у Google.** В консоли указан другой адрес.
  Скопируйте `redirect_uri` из вывода `check` в точности, со схемой `https`.
- **Порты 80/443 заняты** (вариант native). На сервере уже работает другой
  веб-сервер или NPM. Для NPM запускайте с `--mode docker`.
- **`$'\r': command not found`.** Скрипт сохранён в Windows с окончаниями строк
  CRLF (например, после правки в Блокноте). Исправить на сервере:
  `sed -i 's/\r$//' install-oauth-proxy.sh`.
- **После правки `.env` ничего не изменилось.** Используйте
  `docker compose … up -d`, а не `restart`.

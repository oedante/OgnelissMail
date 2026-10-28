# OAuth-прокси: секреты провайдеров

Установка, обновление и проверка прокси — **`OAUTH_PROXY_DEBIAN.md`**
(скрипт `server/oauth-proxy/install-oauth-proxy.sh`).

Секреты OAuth-провайдеров (`client_secret`) **не хранятся в приложении** — их
извлекли бы из APK. Они живут только в файле настроек прокси на сервере:

- `/opt/mailserver/oauth-proxy/.env` — вариант Docker рядом с почтой;
- `/etc/ogneliss-oauth-proxy/oauth-proxy.env` — вариант systemd.

## Переменные

```env
BASE_URL=https://www.ogneliss.ru/oauth   # совпадает с OAUTH_PROXY_URL в сборке
PROXY_API_KEY=…   # ключ приложения; совпадает с OAUTH_PROXY_KEY в сборке
STATE_SECRET=…    # подпись state
ENC_SECRET=…      # шифрование refresh-токенов; смена = все входят заново

GOOGLE_CLIENT_ID=…   GOOGLE_CLIENT_SECRET=…
MS_CLIENT_ID=…       MS_CLIENT_SECRET=…
YANDEX_CLIENT_ID=…   YANDEX_CLIENT_SECRET=…
MAILRU_CLIENT_ID=…   MAILRU_CLIENT_SECRET=…
YAHOO_APP_ID=…  YAHOO_CLIENT_ID=…  YAHOO_CLIENT_SECRET=…
```

Значения — без кавычек. Клиент у каждого провайдера регистрируется как **веб**
(секрет нужен и Google), `redirect_uri` = `<BASE_URL>/callback` при адресе с
путём или `<BASE_URL>/oauth/callback` при поддомене — точное значение печатает
`install-oauth-proxy.sh check`.

## Соответствие приложению

- Публичные `client_id` в `lib/core/constants/app_constants.dart` не секретны.
- Секретов в приложении нет; ключ прокси (`OAUTH_PROXY_KEY`) задаётся при
  сборке через `config/dart_defines.json` и без него вход через прокси
  не работает.
- Адрес возврата в приложение: `com.ogneliss.mail://oauth` (Android/iOS) или
  `http://127.0.0.1:<порт>/` (Windows/Linux) — оба разрешены на прокси.

Client secret Yahoo и Mail.ru, переданные ранее через чат, считаются
раскрытыми — перевыпустите их в консолях провайдеров.

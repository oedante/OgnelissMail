# Прокси погоды Ogneliss Mail

Погода в «Моём дне» (1.15.1). Решение владельца 07.11.2026: условия
MET Norway приняты, но данные пользователей сторонним сервисам не
передаются. Поэтому приложение ходит не к MET Norway и не к поиску
городов, а к этой службе на сервере Ogneliss:

- **прогноз** — служба берёт его у MET Norway (Locationforecast 2.0) от
  имени сервера и хранит до срока `Expires`: на один город — один запрос
  к MET для всех пользователей. MET видит адрес сервера и координаты
  города (до сотых), но не IP и не устройство человека;
- **поиск города** — по списку GeoNames (города от 15 000 жителей,
  CC BY 4.0), который лежит на сервере. Наружу запрос не уходит.

В журнал пишутся только счётчики раз в час. IP, координаты и строки
поиска не сохраняются; в nginx для `/weather/` — `access_log off`.

## Установка (рядом с push-relay)

1. Скопируйте папку `server/weather-proxy` на сервер, например в
   `/root/weather-proxy`, и запустите от root:

   ```bash
   sudo bash /root/weather-proxy/install-weather-proxy.sh install
   ```

   Установщик кладёт файлы в `/opt/mailserver/weather-proxy`, скачивает
   список городов GeoNames (около 3 МБ: `cities15000.zip`,
   `admin1CodesASCII.txt`, `countryInfo.txt` с download.geonames.org),
   находит сеть Nginx Proxy Manager (как у push-relay) и запускает
   контейнер `weather-proxy` (порт 8789 внутри сети, наружу не открыт).

2. Nginx Proxy Manager (панель `http://IP-сервера:81`): хост `ogneliss.ru`
   → Edit → **Advanced** → добавьте раздел рядом с `location ^~ /push/`
   (сначала скопируйте прежнее содержимое — вернуть при ошибке):

   ```nginx
   # Погода «Моего дня»: прогноз MET Norway и поиск городов — через сервер,
   # без журналов адресов.
   location ^~ /weather/ {
       access_log off;
       error_log /dev/null;
       limit_except GET { deny all; }
       set $weather weather-proxy;
       proxy_pass http://$weather:8789;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
       proxy_set_header X-Forwarded-Proto $scheme;
       proxy_connect_timeout 5s;
       proxy_read_timeout 20s;
   }
   ```

   Save. (Тот же раздел — в `site/nginx-landing.conf` архива сайта, чтобы не
   потерялся при следующем обновлении сайта.)

3. Проверьте:

   ```bash
   sudo bash /root/weather-proxy/install-weather-proxy.sh check
   ```

   Ожидается: «служба отвечает в контейнере», «поиск города работает»,
   «прогноз MET Norway получен».

4. Список городов меняется редко — обновлять раз в несколько месяцев:
   `sudo bash /root/weather-proxy/install-weather-proxy.sh cities`.

## Адреса в приложении

- прогноз: `https://www.ogneliss.ru/weather/forecast?lat=55.8&lon=49.11`
  (тело — ответ MET как есть, `Expires`, `Last-Modified`;
  `If-Modified-Since` → 304);
- поиск: `https://www.ogneliss.ru/weather/search?q=Казань&accept-language=ru`
  (формат как у Nominatim `format=jsonv2`: `name`, `display_name`, `lat`,
  `lon`).

Сменить или выключить их без обновления приложения — файл
`https://ogneliss.ru/mail/services.json` (docs/guides/WEATHER.md, раздел 2).

## Проверка без сервера

```bash
cd server/weather-proxy && npm test
```

Заглушка MET Norway и три города: координаты до сотых, кэш до `Expires`,
304, поиск по-русски и по-латински, ё и е.

## Условия и атрибуция

- MET Norway — Terms of Service (https://api.met.no/doc/TermsOfService):
  User-Agent службы с адресом проекта, не больше 4 знаков в координатах,
  кэш по `Expires` и `If-Modified-Since`, пауза 10 минут после 429,
  весь трафик приложения — не больше 20 запросов в секунду (кэш на сервере
  это обеспечивает). Данные — CC BY 4.0 и NLOD 2.0; подпись «Данные: MET
  Norway» со ссылкой на лицензию — в окне погоды.
- GeoNames — CC BY 4.0 (https://www.geonames.org/); подпись «Города:
  GeoNames» со ссылкой — в окне поиска города.

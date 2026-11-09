# Модели перевода Ogneliss Mail (Windows)

Перевод писем на Windows (2.2.0) — движок Bergamot в самом приложении, а
языки (модели Firefox Translations, Mozilla, MPL-2.0) приложение скачивает
отсюда — решение владельца 09.11.2026: не у Google и не у Mozilla напрямую.
Текст писем на сервер не приходит: только запросы файлов моделей при
скачивании языка. Журнал адресов в nginx выключен.

Объём — около 670 МБ (29 пар: английский ↔ болгарский, чешский, немецкий,
испанский, эстонский, персидский, французский, итальянский, нидерландский,
польский, португальский, русский, украинский; исландский, норвежский
(букмол и нюношк) → английский). Можно оставить только нужные пары:
`PAIRS="enru ruen enuk uken" …`.

## Установка (рядом с weather-proxy и push-relay)

1. Скопируйте папку `server/translate-models` на сервер, например в
   `/root/translate-models`, и запустите от root:

   ```bash
   sudo bash /root/translate-models/install-translate-models.sh install
   ```

   Установщик (нужны docker, curl, python3):
   - скачивает `registry.json` набора 0.3.3 из хранилища проекта Bergamot
     (`storage.googleapis.com/bergamot-models-sandbox/0.3.3`) и файлы пар;
   - сверяет размер и sha256 каждого файла со списком; не совпал — файл не
     кладётся, а пара не попадает в `index.json`;
   - кладёт всё в `/opt/mailserver/translate-models/www/v1` вместе с
     `LICENSE-MPL-2.0.txt` и `README.txt` (откуда модели);
   - запускает контейнер `translate-models` (nginx 1.27, только чтение,
     порт 8790 внутри сети Nginx Proxy Manager, наружу не открыт).

2. Nginx Proxy Manager (панель `http://IP-сервера:81`): хост `ogneliss.ru`
   → Edit → **Advanced** → добавьте раздел рядом с `location ^~ /weather/`
   (сначала скопируйте прежнее содержимое — вернуть при ошибке):

   ```nginx
   # Модели перевода для Windows (Firefox Translations, MPL-2.0).
   location ^~ /mail/translate/ {
       access_log off;
       limit_except GET { deny all; }
       set $translate translate-models;
       proxy_pass http://$translate:8790;
       proxy_set_header Host $host;
       proxy_connect_timeout 5s;
       proxy_read_timeout 60s;
       proxy_buffering on;
   }
   ```

   Save. (Тот же раздел — в `site/nginx-landing.conf` архива сайта, чтобы не
   потерялся при следующем обновлении сайта.) Если у хоста ogneliss.ru уже
   есть свой `location /mail/` со статическими страницами — раздел выше
   ставится **перед** ним (`^~` и более длинный префикс выигрывают).

3. Проверьте:

   ```bash
   sudo bash /root/translate-models/install-translate-models.sh check
   ```

   Ожидается: «раздача отвечает в контейнере», «index.json доступен», «файл
   модели скачивается».

## Обновление

Набор 0.3.3 больше не меняется (репозиторий Mozilla в архиве с 15.12.2025).
Повторный запуск `… models` докачает только то, чего нет или что не
совпало, и пересоберёт `index.json`.

## Адреса в приложении

- список: `https://ogneliss.ru/mail/translate/v1/index.json` — формат
  `registry.json` Bergamot: `{"enru": {"model": {"name", "size",
  "expectedSha256Hash"}, "lex": {…}, "vocab": {…}}, …}`; приложение читает
  его не чаще раза в неделю (и перед скачиванием языка);
- файлы: `https://ogneliss.ru/mail/translate/v1/<пара>/<name>`.

Код в приложении — `lib/services/translation/bergamot/bergamot_models.dart`
(`bergamotModelsBase`).

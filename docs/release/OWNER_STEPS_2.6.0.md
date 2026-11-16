# Ogneliss Mail 2.6.0 — что сделать владельцу

2.6.0 (158) выходит вместо 2.5.5: та не выпускалась, поэтому шаги 2.5.5
(вход напрямую у служб, сервер входа только для Яндекса на Windows и Linux,
логотипы в службе погоды) делаются сейчас, вместе с 2.6.0. «Что нового» —
от 2.5.3: `STORE_NOTES_2.6.0.md`.

| | Нужно? |
|---|---|
| Ключи сборки (`config/dart_defines.json`, секрет GitHub) | да — раздел 1 (ключи 2.5.5) |
| Служба погоды на сервере | да — раздел 2 (логотипы отправителей) |
| Консоли Google, Microsoft, Яндекса, Mail.ru, Yahoo | да — раздел 3 |
| `.env` сервера входа | да — раздел 4, после выхода 2.6.0 |
| Сайт | да — раздел 5 (один архив) |
| Письмо Google | да — раздел 6 |
| Xcode, Android Studio, база, новые зависимости | не нужно |

Порядок важен: сначала сборка и служба погоды, потом консоли и `.env`
сервера. Версии до 2.6.0 после этого войти в Google и Microsoft уже не
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
| `PUSH_*`, `FIREBASE_*` | как были |
| `SUPPORT_EMAIL` | по желанию (2.6.0): задан — кнопка «Связаться с нами» в окне «Вход через систему организации» открывает письмо на этот адрес; пусто — раздел «Рабочая почта» сайта с вашими адресами |
| `BIMI_URL` | не задавать (по умолчанию `https://www.ogneliss.ru/weather`) |

Тот же файл — в секрете GitHub `DART_DEFINES_JSON` (Settings → Secrets and
variables → Actions). Проверка в сборке: «Журнал для поддержки» → строка
«Вход: напрямую у служб (Google да, Microsoft да, …)». «нет — пароль
приложения» — клиента нет.

## 2. Служба погоды — с логотипами

Скопируйте на сервер папку `server/weather-proxy` из архива
`ogneliss-server-2.6.0.zip` и выполните:

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

## 4. Сервер входа — только Яндекс (после выхода 2.6.0)

Уберите из `.env` сервера ключи Google, Microsoft, Mail.ru и Yahoo и
выключите там логотипы (они теперь в службе погоды):

```bash
sudo bash ~/set-oauth-env.sh --yandex-only --dry-run
```
```bash
sudo bash ~/set-oauth-env.sh --yandex-only
```

Скрипт — `server/oauth-proxy/set-oauth-env.sh` из архива сервера
(положите его в домашнюю папку). Копия прежнего `.env` остаётся рядом.
Проверка: `https://www.ogneliss.ru/oauth/healthz` — в `config` у `google`,
`microsoft`, `mailru`, `yahoo` стоит `"clientId": false`, у `yandex` — `true`.

## 5. Сайт

Архив один — `ogneliss-site-2026-11-16.zip`: папка сайта целиком, в том же
виде, что на сервере (`site/dialer`: готовые страницы и исходники, из
которых они собраны). Выкладывается как раньше — распаковать поверх папки
сайта на сервере; контейнер перезапускать не нужно. Что нового по
сравнению с сайтом на сервере:

- политика 1.9: вход напрямую у служб, сервер входа — только Яндекс на
  Windows и Linux; страница «Серверы и данные»; Mac и TestFlight (это было
  в v3);
- второй адрес ermishin.oleg@icloud.com рядом с oedante@gmail.com — в
  контактах, внизу страниц и в документах;
- раздел «Рабочая почта» на странице Ogneliss Mail (ru, en, de, fr,
  `#corporate`): Exchange, Microsoft 365, IMAP организации, MDM; вход через
  систему организации — форк открытого кода или консультация. На него
  ведёт кнопка «Связаться с нами» в приложении.

## 6. Письмо Google

Ответить в той же переписке письмом `letter-google.txt` — после шагов 1–4
(тогда всё в нём — правда).

## 7. Тег для сборки на GitHub: `v2.6.0`

Сначала — секрет `DART_DEFINES_JSON` (раздел 1). Потом:

```bash
git fetch origin
```
```bash
git tag -a v2.6.0 -m "Ogneliss Mail 2.6.0" origin/claude/next
```
```bash
git push origin v2.6.0
```

Если сначала сливаете `claude/next` в `main` — вместо `origin/claude/next`
укажите `origin/main`. По тегу CI соберёт Android, iOS и macOS без подписи,
Windows и Linux; страница выпуска заполнится из `STORE_NOTES_2.6.0.md`.
iOS и macOS для TestFlight подписываете у себя в Xcode, как обычно.

## 8. Что увидят пользователи

- Ящики Google и Microsoft, добавленные через сервер входа, один раз
  покажут «Требуется вход» — «Войти снова» входит уже напрямую у службы.
- Ящики Яндекса работают как раньше.
- Логотипы отправителей у писем Gmail больше не показываются (вместо них
  буква).
- Рабочая почта по IMAP: при добавлении ящика организации серверы, порты,
  календарь и контакты находятся сами. Записи DNS (MX, SRV) приложение
  спрашивает у DNS самого устройства: на Android 10+ (на Android 7–9 —
  как раньше, по именам узлов), iPhone, Mac, Windows и Linux.
- Поручения: исправления работают, когда обновятся обе стороны — у
  отправителя (повторные напоминания, внешние адресаты) и у получателя
  (беседа). Уже пришедшие копии напоминаний можно удалить вручную.

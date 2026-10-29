# mail_engine — универсальный движок синхронизации почты

Чистый Dart-пакет (без Flutter). Универсален — **не привязан к конкретному серверу/домену/организации**.
Поддерживает: Exchange (EAS/EWS с автоопределением через Autodiscover), Microsoft Graph (Exchange Online),
IMAP/SMTP, OAuth2, CalDAV, CardDAV.
Один движок для теста и для приложения — без дублирования методов под каждый протокол.

## Оси архитектуры
- **Транспорт**: EAS / EWS / Microsoft Graph / IMAP-SMTP / CalDAV / CardDAV.
- **Аутентификация** (ортогонально транспорту): Basic / OAuth2 / AppPassword.
- **Возможности** (Capabilities): mail/calendar/contacts/tasks/notes/push/policies.
- **Политики** (SecurityPolicy): из EAS Provision; иначе null.

## Проверка подключения из консоли (`bin/connect_test.dart`, 1.6.12)
```
cd packages/mail_engine
dart pub get
dart run bin/connect_test.dart --email ivanov@corp.ru --server mail.corp.ru --domain CORP --as iphone --mail
```
Тот же путь, что в приложении: OPTIONS → Provision → FolderSync (→ Sync «Входящих» с `--mail`).
Профили `--as`: `iphone` (как Почта iPhone), `android` (режим совместимости Android), `ogneliss` (без совместимости).
Пароль — `OGN_PASSWORD` или скрытый ввод. Ничего не отправляет и не удаляет; полный список параметров — в начале файла.
TLS здесь — Dart, не iOS: 403 «If you are not a bot» с профилем `iphone` из консоли не доказывает, что iPhone не войдёт.
Настоящий сетевой стек iOS — симулятор iPhone на Mac (`docs/guides/IOS_XCODE_SETUP.md`).

Примеры серверов (любой провайдер, не зашиты в код):
- Yandex IMAP `imap.yandex.ru:993`, SMTP `smtp.yandex.ru:465`, CalDAV `https://caldav.yandex.ru`, CardDAV `https://carddav.yandex.ru`.
- Gmail IMAP `imap.gmail.com:993`, SMTP `smtp.gmail.com:465` (нужен OAuth-token или пароль приложения).
- Exchange — указать сервер вида `mail.company.ru` или оставить пусто для Autodiscover.

## Статус реализации (29.10.2026, Ogneliss Mail 1.8.11)
- **EAS** (`EasEngine`) — рабочий движок приложения: OPTIONS и выбор версии
  (16.1 → 16.0 → 14.1 → 14.0; сервер только с 12.x — понятный отказ),
  Provision (политики, удалённое стирание, «политики нет» — Status 2),
  FolderSync, Sync почты и PIM (календарь, контакты, задачи, заметки),
  ItemOperations, SendMail / SmartReply / SmartForward с постоянным ClientId
  (повтор из очереди не даёт дубля), MoveItems, Ping, Search,
  ResolveRecipients, MeetingResponse. Вход по паролю (Basic) и OAuth
  (Bearer, Exchange Online). Сеанс между запусками (`saveSession`).
- **Autodiscover** — POX (Outlook и MobileSync в своих пространствах имён),
  redirectAddr, redirectUrl, 302 на POST, метод HTTP-перенаправления;
  перенаправления — только https и только в домене почты.
- **Microsoft Graph** (`GraphEngine`, 1.8.11) — у ящиков Exchange Online то,
  что шло по EWS (Microsoft отключает EWS в Exchange Online с октября 2026,
  окончательно — в апреле 2027): своя карточка и карточки коллег (People,
  каталог, руководитель), фото, MailTips, переговорные (`/places`), состав
  рассылок, категории Outlook, правила «Входящих» (список, вкл./выкл.,
  создание, удаление), папки почты и «Восстановить удалённые». Токен движок
  просит у приложения (`GraphTokenSource`, после 401 — с `force`), как
  `EasEngine` просит токен ActiveSync. Права — `GraphEngine.consentScopes`
  (при входе) и `GraphEngine.tokenScopes` (токен). Проверка из консоли —
  `bin/graph_check.dart` (только чтение, токен — `OGN_GRAPH_TOKEN`).
- **EWS** (`EwsEngine`) — только пробное подключение при входе (GetFolder);
  рабочий стек EWS — в приложении (`lib/services/mail/ews`, NTLMv2 с
  привязкой к каналу, OAuth).
- **IMAP/SMTP** (`ImapSmtpEngine`) — приложением не используется: рабочий
  стек — `lib/services/mail/imap` (обновление токена, переподключение, IDLE).
  Здесь UID-команды исправлены, но нет обновления токена, синхронизации по
  UIDVALIDITY и копии в «Отправленные» — не подключать без доработки.
- **CalDAV/CardDAV**: discovery + выборка элементов.

## Request Line и протокол (EAS)
- По умолчанию — **plain query-string** (как Почта iPhone и проверенный рабочий
  PowerShell в журналах Exchange). Base64 command line — только по явному
  `AccountConfig.easBase64Override` (консоль `bin/connect_test.dart`); при
  неуспехе команды на Base64 — один повтор на 14.1 + plain query-string.
- Версия — по заголовку `MS-ASProtocolVersions` ответа OPTIONS.

## Подробный debug
Единый логгер `DebugLog(verbose: true)` печатает по каждому транспорту:
- исходящий запрос: метод, URL, заголовки (Authorization скрыт), размер тела + hex-превью (+ текст, если печатаемо);
- входящий ответ: HTTP-статус, заголовки, размер + hex/текст-превью, тайминг (мс);
- расшифровку WBXML (дерево Provision-ответов).
Так сразу видно, на каком транспорте и из-за чего падение. Лог доступен через `res.log` и `DebugLog.dump()`.

## Безопасность
- Пароли/токены не хранятся в коде; в тесте вводятся в рантайме (скрытый ввод).
- Весь трафик — напрямую к серверам провайдера, без сторонних релеев.

# Сервер входа 1.8.11: Exchange Online и Microsoft Graph

Что нового на сервере входа (`server/oauth-proxy`), что сделать в Microsoft
Entra и как проверить. Сервер push-уведомлений (`server/push-relay`) в 1.8.11
не менялся.

## Что изменилось

- Новый провайдер **`exchange`** — Exchange Online (Microsoft 365) по
  ActiveSync: вход только рабочими учётными записями (`/organizations`),
  токен для ActiveSync и EWS (`outlook.office365.com`).
- При входе сервер просит согласие и на права **Microsoft Graph** (без
  согласия администратора). Организация не разрешает сотрудникам давать
  согласие — вход повторяется без Graph: ActiveSync работает и так, в журнале
  сервера — «согласие на Microsoft Graph не получено».
- **`POST /token`** с `"resource": "graph"` — токен Microsoft Graph тем же
  входом (в ответе — `"resource": "graph"`). Ошибки Microsoft — с кодом
  `aadsts` (например, `AADSTS65001` — нет согласия), без секретов.
- **`/healthz`** — в `providers` есть `exchange`, в `config.exchange` —
  `"graph": true`.
- Прежние провайдеры (Google, Microsoft/Outlook.com, Яндекс, Mail.ru, Yahoo)
  и выданные приложениям входы не меняются: секреты (`ENC_SECRET`,
  `STATE_SECRET`, `PROXY_API_KEY`) установщик не трогает.

Зачем: Microsoft отключает EWS в Exchange Online (с 1 октября 2026 — по
организациям, окончательно — в апреле 2027). Почта, календарь и контакты
ящика Exchange Online идут по ActiveSync, а адресная книга, подсказки
MailTips, фото коллег, правила сервера, «Восстановить удалённые»,
переговорные и состав рассылок — через Microsoft Graph (в приложении —
почтовый движок, `packages/mail_engine`, `GraphEngine`).

Приложение идёт на сервер входа за Exchange Online, только если в сборке нет
своего клиента Microsoft (`MS_CLIENT_ID` в `config/dart_defines.json`); со
своим клиентом вход и токен Graph — напрямую у Microsoft, сервер не нужен.
Прежний сервер (без `exchange`) приложение узнаёт по `/healthz` и вход в
Exchange Online через него не предлагает.

## 1. Обновить сервер

Архив `ogneliss-server-1.8.11.zip` — на сервер, затем (Debian/Ubuntu, root):

```bash
unzip ogneliss-server-1.8.11.zip -d ~/ogneliss-server-1.8.11
cd ~/ogneliss-server-1.8.11/server/oauth-proxy
sudo bash install-oauth-proxy.sh update     # код прокси, секреты — как были
sudo bash install-oauth-proxy.sh check      # проверка
```

`update` сам делает резервную копию, обновляет `server.js` и добавляет в
`.env` недостающие строки:

```
EXO_CLIENT_ID=          # пусто — клиент MS_CLIENT_ID / MS_CLIENT_SECRET
EXO_CLIENT_SECRET=
EXO_GRAPH=1             # 0 — не просить согласие на Microsoft Graph
```

Обычно их не нужно заполнять: Exchange Online входит тем же клиентом, что и
Outlook.com (`MS_CLIENT_ID`). Отдельный клиент — заполнить `EXO_CLIENT_ID` и
`EXO_CLIENT_SECRET` (`nano` файла `.env`, путь установщик показывает) и
перезапустить прокси:

- Docker (рядом с почтой): `cd /opt/mailserver/oauth-proxy && docker compose -f docker-compose.oauth.yml up -d`
- systemd: `systemctl restart ogneliss-oauth-proxy`

`check` должен показать:

```
✓ снаружи отвечает: https://www.ogneliss.ru/oauth/healthz
✓ Exchange Online и Microsoft Graph: есть (прокси 1.8.11)
…
✓ Exchange Online (клиент Microsoft): настроен
```

## 2. Microsoft Entra: клиент сервера входа

Entra admin center (https://entra.microsoft.com) → App registrations →
клиент сервера (тот, чей Application ID записан в `MS_CLIENT_ID`):

1. **Supported account types** — «Accounts in any organizational directory
   and personal Microsoft accounts» (Authentication → Supported account
   types). Только личные учётные записи — Exchange Online не войдёт.
2. **Authentication → Web → Redirect URIs** — адрес возврата сервера:
   `https://www.ogneliss.ru/oauth/callback` (свой — `<BASE_URL>/callback`,
   его печатает `install-oauth-proxy.sh check`).
3. **Certificates & secrets** — действующий client secret (его значение —
   в `MS_CLIENT_SECRET`). Срок секрета истёк — создать новый и записать.
4. **API permissions** (всё — Delegated):

| API | Право | Зачем | Согласие администратора |
|---|---|---|---|
| Office 365 Exchange Online | `EAS.AccessAsUser.All` | почта, календарь, контакты (ActiveSync) | нет |
| Office 365 Exchange Online | `EWS.AccessAsUser.All` | онлайн-архив, общие ящики, подпись — пока EWS открыт | нет |
| Microsoft Graph | `User.Read` | своя карточка и фото | нет |
| Microsoft Graph | `User.ReadBasic.All` | фото коллег | нет |
| Microsoft Graph | `People.Read` | должность, отдел, кабинет, телефоны коллег | нет |
| Microsoft Graph | `Mail.ReadWrite` | подсказки MailTips, «Восстановить удалённые» | нет |
| Microsoft Graph | `MailboxSettings.ReadWrite` | правила сервера, категории Outlook | нет |
| Microsoft Graph | `offline_access`, `openid`, `email`, `profile` | вход и обновление токена | нет |
| Microsoft Graph | `IMAP.AccessAsUser.All`, `SMTP.Send` | Outlook.com по IMAP/SMTP (как раньше) | нет |
| Microsoft Graph | `Place.Read.All` | переговорные (по желанию) | **да** |
| Microsoft Graph | `GroupMember.Read.All` | состав рассылок (по желанию) | **да** |
| Microsoft Graph | `User.Read.All` | руководитель в карточке коллеги (по желанию) | **да** |

«Office 365 Exchange Online» — во вкладке «APIs my organization uses» (поиск
по названию). `Calendars.*`, `Contacts.*`, `Mail.Read`, `Mail.ReadBasic`,
`Mail.Send` из вашего списка приложение не использует — можно оставить или
удалить, на работу это не влияет.

Тот же список прав — и у клиента приложения для входа без сервера
(`MS_CLIENT_ID` в `config/dart_defines.json`, платформа «Mobile and desktop
applications», адреса `com.ogneliss.mail://oauth/microsoft` и
`http://localhost`, «Allow public client flows» = Yes) —
`docs/guides/OAUTH_SETUP.md`.

## 3. Организации, где сотрудники не дают согласие сами

Сотрудник входит — ActiveSync работает, а в «Настройки ящика → Microsoft
Graph» — «Нет согласия». Администратор этой организации (не вы, если ящик
чужой) даёт согласие за всех одним из способов:

- Entra admin center → Enterprise applications → Ogneliss → Permissions →
  **Grant admin consent for <организация>**;
- или ссылкой (подставить свой Application ID):
  `https://login.microsoftonline.com/organizations/adminconsent?client_id=<Application ID>`
  — Microsoft покажет все права клиента, «Accept» выдаёт их организации.

Права с согласием администратора (`Place.Read.All`, `GroupMember.Read.All`,
`User.Read.All`) приложение получает только так. Затем сотрудник —
«Настройки ящика → Войти снова» (ящики, вошедшие до 1.8.10, согласия на
Graph не давали — им тоже «Войти снова»).

## 4. Проверка

```bash
curl -s https://www.ogneliss.ru/oauth/healthz
# {"ok":true,"providers":["google","microsoft","exchange","yandex","mailru","yahoo"],
#  "config":{… "exchange":{"clientId":true,"clientSecret":true,"auth":"body","graph":true} …}, …}

curl -sI "https://www.ogneliss.ru/oauth/oauth/exchange/login?redirect=com.ogneliss.mail://oauth" | grep -i location
# Location: https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?…
#   scope=…EAS.AccessAsUser.All…EWS.AccessAsUser.All…graph.microsoft.com/User.Read…
```

Журнал прокси (Docker: `docker logs --tail 50 oauth-proxy`, systemd:
`journalctl -u ogneliss-oauth-proxy -n 50`) после входа в Exchange Online:
`GET /callback → 302`; строка «согласие на Microsoft Graph не получено» —
организация не дала согласие (раздел 3); «exchange refresh_token → HTTP 400
invalid_grant (AADSTS65001 …)» на `resource=graph` — то же.

Что выдаёт Graph конкретному токену — из консоли, тем же движком, что в
приложении (только чтение):

```bash
cd packages/mail_engine && dart pub get
OGN_GRAPH_TOKEN=<токен Graph> dart run bin/graph_check.dart --person коллега@организация.ru
```

## Откат

`install-oauth-proxy.sh update` перед обновлением сохраняет копию (путь
печатает строкой «резервная копия: …»). Вернуть: скопировать `server.js`
из копии в каталог прокси и перезапустить. Приложение 1.8.11 с прежним
сервером работает (вход в Exchange Online через сервер — недоступен, Graph —
по прямому входу), прежние версии приложения с новым сервером — тоже.

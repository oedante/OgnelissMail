# Настройка OAuth-провайдеров для Ogneliss

Прокси развёрнут рядом с почтой (`/opt/mailserver/oauth-proxy`) и доступен по адресу
из `BASE_URL`. Рекомендуемый режим — **путь на основном домене**:
`https://www.ogneliss.ru/oauth` (годится имеющийся сертификат GlobalSign, который
покрывает `www`, но не `oauth.*`).

Ниже — как зарегистрировать приложение у каждого провайдера и вписать значения в
`/opt/mailserver/oauth-proxy/.env`. После правок:

```bash
cd /opt/mailserver/oauth-proxy && docker compose -f docker-compose.oauth.yml up -d
```

(`restart` не перечитывает `.env` — нужна именно `up -d`. Установка, обновление
и проверка прокси — `install-oauth-proxy.sh`, см. `docs/guides/OAUTH_PROXY_DEBIAN.md`.)

> **Ключевое ограничение.** Google и Microsoft **не принимают** голый IP и
> самоподписанный сертификат как `redirect_uri` — нужен домен с валидным сертификатом.
> Для **Яндекс** и **Mail.ru** требования мягче.

Секреты живут ТОЛЬКО в `.env` на сервере, в приложение не попадают.

---


## ⚠️ Главное: тип приложения — ВЕЗДЕ «Веб» (не Android/iOS!)

Приложение ходит к провайдерам **через прокси**, а не напрямую. Полный цикл:

```
приложение → https://www.ogneliss.ru/oauth/oauth/google/login?redirect=com.ogneliss.mail://oauth
   прокси   → провайдер, redirect_uri = https://www.ogneliss.ru/oauth/callback
   провайдер → прокси /callback?code=...        (прокси меняет code на токены,
                                                 client_secret не покидает сервер)
   прокси   → приложение com.ogneliss.mail://oauth?at=...
```

Отсюда два следствия:

1. **Провайдер видит только HTTPS-адрес прокси.** Схема `com.ogneliss.mail://oauth` —
   это внутреннее дело прокси и приложения; в консолях её указывать **не нужно** и
   нельзя (Google/Яндекс её не примут).
2. **Тип клиента — «Веб-приложение» / «Веб-сервисы»**, потому что OAuth-клиентом
   является веб-сервер (прокси), а не мобильное приложение. Типы «Android» и «iOS»
   предназначены для приложений, которые общаются с провайдером напрямую и не имеют
   client_secret — это не наш случай.
3. **Один клиент на все платформы.** Отдельные client ID для Android/iOS/desktop
   не нужны: клиент один — прокси. Ни package name, ни SHA-256 fingerprint не требуются.

**Единый redirect_uri для всех провайдеров** (режим «путь на домене»):

```
https://www.ogneliss.ru/oauth/callback
```

(в режиме поддомена — `https://oauth.ogneliss.ru/oauth/callback`; точное значение
скрипт печатает при запуске и контейнер пишет в лог при старте)

### Что заполнять по консолям

| Провайдер | Тип приложения | Redirect URI | Отдельно |
|---|---|---|---|
| **Google** | **Web application** | `https://www.ogneliss.ru/oauth/callback` | Authorized JavaScript origins — **оставить пустым** |
| **Яндекс** | только **Веб-сервисы** | то же | Галку «Android-приложение» **снять** — иначе консоль требует package name и SHA-256, которые не нужны |
| **Microsoft** | платформа **Web** | то же | — |
| **Mail.ru** | веб-сайт | то же | — |


## 1. Google (Gmail)

1. Откройте **Google Cloud Console** → https://console.cloud.google.com → создайте
   проект (или выберите существующий).
2. **APIs & Services → Library** → найдите **Gmail API** → **Enable**.
3. **APIs & Services → OAuth consent screen**:
   - User type: **External** (или Internal для Google Workspace).
   - Заполните название, поддержку, домены. Добавьте тестовых пользователей (если
     приложение в статусе Testing).
   - Scopes: добавьте `https://mail.google.com/`.
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - Application type: **Web application**.
   - **Authorized redirect URIs**: `https://www.ogneliss.ru/oauth/callback`
     (голый IP Google отклонит — нужен домен + валидный TLS).
   - Создайте → скопируйте **Client ID** и **Client secret**.
5. В `.env`:
   ```
   GOOGLE_CLIENT_ID=<client id>.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=<client secret>
   GOOGLE_SCOPE=https://mail.google.com/ openid email profile
   ```

---

> **Важно про проверку Google:** scope `https://mail.google.com/` относится к
> *restricted* — для внешних пользователей Google требует верификацию приложения.
> Для корпоративного использования проще: если домен в Google Workspace —
> публиковать приложение как **Internal**; иначе на время отладки добавить себя
> в **Test users** (тогда работает без верификации, но refresh_token живёт 7 дней).

## 2. Microsoft (Outlook / Office 365, через EWS)

1. **Azure Portal** → https://portal.azure.com → **Azure Active Directory (Microsoft
   Entra ID) → App registrations → New registration**.
   - Name: Ogneliss.
   - Supported account types: обычно **Accounts in any organizational directory and
     personal Microsoft accounts** (или под вашу организацию).
   - **Redirect URI**: платформа **Web**, значение `https://www.ogneliss.ru/oauth/callback`.
2. После создания скопируйте **Application (client) ID**.
3. **Certificates & secrets → New client secret** → скопируйте **Value** (это
   `MS_CLIENT_SECRET`, показывается один раз).
4. **API permissions → Add a permission → APIs my organization uses** → найдите
   **Office 365 Exchange Online** → **Delegated permissions** →
   `EWS.AccessAsUser.All` → Add. (Для IMAP/SMTP вместо EWS —
   `IMAP.AccessAsUser.All`, `SMTP.Send`.) При необходимости — **Grant admin consent**.
5. В `.env`:
   ```
   MS_CLIENT_ID=<application client id>
   MS_CLIENT_SECRET=<secret value>
   MS_SCOPE=https://outlook.office365.com/EWS.AccessAsUser.All offline_access openid email
   ```

> Токен, выданный под EWS-scope, приложение использует для Exchange-транспорта (EWS).

---

## 3. Яндекс (Yandex Mail)

> **Платформы приложений**: отметить ТОЛЬКО «Веб-сервисы» и вписать Redirect URI.
> «Suggest Hostname» — пусто. Галку «Android-приложение» снять.
> **Доступы** (галочки в консоли) нужны почтовые: чтение/удаление писем в ящике
> (`mail:imap_full`) и отправка по SMTP (`mail:smtp`) — оба уже прописаны в
> `YANDEX_SCOPE`. «Доступ к адресу электронной почты» — полезен для определения
> адреса ящика.


1. **Yandex OAuth** → https://oauth.yandex.ru → **Создать приложение**.
2. Платформа: **Веб-сервисы**.
   - **Redirect URI (Callback URI)**: `https://oauth.ogneliss.ru/oauth/callback`
     (IP+self-signed у Яндекса обычно проходит; если нет — используйте домен).
3. Доступы (**Права**): раздел **Яндекс.Почта (IMAP/SMTP)** →
   `mail:imap_full` и `mail:smtp`; раздел **Календарь** → «Чтение и изменение
   содержимого календарей и списков дел» (`calendar:all`); раздел **Адресная
   книга** → «Чтение и изменение содержимого адресной книги»
   (`addressbook:all`). Без двух последних Яндекс ответит `invalid_scope` на
   входе. После добавления прав пользователи входят в Яндекс заново.
4. Создайте → скопируйте **ID** и **Пароль** приложения.
5. В `.env`:
   ```
   YANDEX_CLIENT_ID=<client id>
   YANDEX_CLIENT_SECRET=<client secret>
   YANDEX_SCOPE=mail:imap_full mail:smtp calendar:all addressbook:all
   ```

---

## 4. Mail.ru

1. **Mail.ru для разработчиков** → https://oauth.mail.ru → создать приложение.
2. **Redirect URI**: `https://oauth.ogneliss.ru/oauth/callback`.
3. Права: `openid`, `email`, `profile`, `mail.imap`, `offline_access`.
   Redirect URI должен совпадать с адресом прокси **посимвольно** (схема,
   `www`, слеш на конце) — проверьте строку `redirect_uri для консолей
   провайдеров` в `docker logs oauth-proxy`.
4. Скопируйте **client_id** и **client_secret**.

   Как прокси работает с Mail.ru (по документации OAuth Mail): PKCE
   (`code_challenge` S256, `code_verifier` при обмене — обязателен),
   `prompt=consent` (иначе нет refresh_token), ключ клиента — в заголовке
   Basic, адрес и имя — из `/api/v1/oidc/userinfo`, `state` — 256 бит.

   ⚠️ С 1 июля 2025 года **новые** приложения OAuth Mail работают только
   для «продуктовых запросов», а вход на сайты переведён на VK ID. Приложения,
   созданные раньше, продолжают работать. Если приложение создано позже и
   Mail.ru отвечает `invalid_client`, `unauthorized_client` или `access_denied`
   на `mail.imap`, — нужно написать в поддержку OAuth Mail и попросить доступ
   к `mail.imap` для почтового клиента (IMAP/SMTP по XOAUTH2). Через VK ID
   доступ к почте по IMAP не выдаётся.

   **VK ID не замена OAuth Mail:** его права — `vkid.personal_info`, `email`,
   `phone` (и расширенные вроде `friends`), доступа к ящику по IMAP среди них
   нет; токен VK ID для XOAUTH2 на imap.mail.ru не годится. Приложение
   VK ID нужно только для «Войти через VK» как способа узнать человека —
   почтовому клиенту это не помогает. Рабочий путь без OAuth Mail —
   пароль для внешнего приложения (в приложении: Mail.ru → «Или по паролю
   для внешнего приложения»).
5. В `.env`:
   ```
   MAILRU_CLIENT_ID=<client id>
   MAILRU_CLIENT_SECRET=<client secret>
   MAILRU_SCOPE=openid email profile mail.imap offline_access
   ```
6. Календарь Mail.ru по OAuth недоступен: приложение входит в
   `calendar.mail.ru` по **паролю внешнего приложения** (пользователь вводит
   его в Настройки → Аккаунты → «Календарь и контакты»). Контакты Mail.ru
   сторонним программам не отдаёт.

---

## Проверка

```bash
# применить изменения .env
cd /opt/mailserver/oauth-proxy && docker compose -f docker-compose.oauth.yml up -d

# в логе видно режим и точный redirect_uri:
docker logs oauth-proxy | tail -2
#   oauth-proxy listening on 0.0.0.0:8787 (base https://www.ogneliss.ru/oauth, path '/oauth')
#   redirect_uri для консолей провайдеров: https://www.ogneliss.ru/oauth/callback

curl https://www.ogneliss.ru/oauth/healthz
# {"ok":true,"providers":["google","microsoft","yandex","mailru"]}

# старт авторизации (должен быть 302 к провайдеру)
curl -i "https://www.ogneliss.ru/oauth/oauth/yandex/login?redirect=com.ogneliss.mail://oauth"
# ожидается 302 Location: https://oauth.yandex.ru/authorize?...
```

## Сборка приложения под прокси

```bash
flutter build apk \
  --dart-define=OAUTH_PROXY_URL=https://www.ogneliss.ru/oauth \
  --dart-define=OAUTH_PROXY_KEY=<PROXY_API_KEY из /opt/mailserver/oauth-proxy/.env>
```

> При self-signed TLS приложение должно **доверять сертификату** `oauth.ogneliss.ru`
> (в настройках приложения — тумблер «Доверять самоподписанным сертификатам», см.
> раздел безопасности). Для продакшена рекомендуется домен + Let's Encrypt.

## Импорт подписей (доп. scopes)

Чтобы работал импорт подписи через API (кнопка «Импорт из ящика» и авто-импорт
при подключении):
- **Google**: добавьте scope `https://www.googleapis.com/auth/gmail.settings.basic`
  (в `.env` уже включён в GOOGLE_SCOPE). Приложение читает `settings/sendAs`.
- **Microsoft**: добавьте `MailboxSettings.Read` (в `.env` включён в MS_SCOPE) —
  для Exchange Online (Graph `/me/mailboxSettings`). Для on-prem Exchange scope
  не нужен (EWS GetUserConfiguration по EWS-доступу).
- **Яндекс/Mail.ru/IMAP**: отдельных scopes не требуется — подпись извлекается
  эвристикой из папки «Отправленные».

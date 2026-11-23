# Проверка Google — подача 2: только календарь и контакты

С 2.6.7 почта Gmail — по паролю приложения (IMAP/SMTP), `https://mail.google.com/`
не запрашивается. Вход Google — только для календаря и контактов. Прежняя
заявка (с почтой) — `GOOGLE_VERIFICATION.md`; здесь — для новой подачи.

Разрешения, которые просит приложение (`direct_oauth.dart`, `oauth_service.dart`),
и которые должны стоять в консоли (Google Auth Platform → Data Access) — строка
в строку:

- `openid`, `email`, `profile`
- `https://www.googleapis.com/auth/calendar`
- `https://www.googleapis.com/auth/carddav`
- `https://www.googleapis.com/auth/contacts.readonly`
- `https://www.googleapis.com/auth/contacts.other.readonly`

---

## 1. Тестовый аккаунт для проверяющих — можно и нужно

У приложения нет своего входа, но вход Google в нём идёт после ящика Gmail
(экран «Gmail — app password»), и Google-аккаунт при входе должен быть тем же,
что и ящик. Проверяющему со своим аккаунтом пришлось бы включать двухэтапную
проверку и создавать пароль приложения — проще дать готовый тестовый аккаунт.

1. Новый аккаунт Google только для проверки (например, `ogneliss.review@gmail.com`),
   без личных данных. Язык — English.
2. Двухэтапная проверка — включить (без неё Google не даёт пароль
   приложения). Создать **пароль приложения** (myaccount.google.com →
   Security → App passwords) — 16 букв.
3. **Резервные коды** (Security → 2-Step Verification → Backup codes) — 10
   одноразовых кодов: по ним проверяющий пройдёт второй шаг входа без вашего
   телефона.
4. Наполнить: 2–3 события в Google Calendar и второй календарь `Work`;
   5–10 контактов, один — человек с фото профиля Google, у карточки которого
   своего фото нет; «Другой контакт» с фото (кто писал аккаунту, но не
   сохранён); пара писем во «Входящих».
5. В ответе Google — адрес, пароль аккаунта, пароль приложения и 3–4
   резервных кода (§3, «Testing»). Только в ответе на их письмо — не в
   консоли и не в открытых местах.
6. После одобрения: сменить пароль аккаунта, удалить пароль приложения,
   выпустить новые резервные коды.

Google может спросить «Verify it's you» при входе из другой страны — тогда
пригодятся резервные коды. Если проверяющие ответят, что заходить не будут
и им хватит видео, — ничего страшного: данные просто не понадобятся.

---

## 2. Сценарий видео (6–7 минут)

Запись — на Mac или Windows (приложение и браузер на одном экране, видна
адресная строка) или на телефоне с записью экрана и вторым экраном с
браузером. Язык приложения и аккаунта — English. Звук не обязателен,
подписи — текстом (iMovie/Clipchamp) по-английски, как в таблице.

Подготовка: тестовый аккаунт (§1) ещё не добавлен в приложение; на
myaccount.google.com/permissions доступа Ogneliss Mail нет. Вкладки браузера
под тестовым аккаунтом: Google Calendar, Google Contacts (и «Other
contacts»), Cloud Console → Data Access, myaccount.google.com/permissions.
Второй ящик B — для приглашения на встречу.

| Время | Сцена | Что показать | Подпись |
|---|---|---|---|
| 0:00 | Титул | Название, проект, Client ID | «Ogneliss Mail — OAuth verification demo. Project: [PROJECT_ID]. OAuth client: [CLIENT_ID]» |
| 0:10 | Консоль | Google Auth Platform → Data Access: семь разрешений, `mail.google.com` нет | «Scopes configured in Cloud Console» |
| 0:30 | Ящик | Приложение → Add Account → Google. Экран «Gmail — app password»: адрес, пароль приложения; переключатель **Google Calendar and Contacts** включён → Sign In | «Gmail mail uses an app password (IMAP/SMTP). Google sign-in is used only for Calendar and Contacts» |
| 0:55 | Вход Google | Браузер: **приблизить адресную строку** — `client_id` и `scope=` (calendar, carddav, contacts.readonly, contacts.other.readonly). Выбрать аккаунт. «Google hasn't verified this app» → Advanced → Go to Ogneliss Mail | «OAuth 2.0 with PKCE, directly with Google» |
| 1:20 | Согласие | Экран согласия: **раскрыть каждый пункт**, медленно прокрутить, отметить все → Continue. В приложении — «Google Calendar and Contacts connected» | «Consent screen — all requested scopes expanded» |
| 1:50 | **calendar** — чтение | Calendar: события основного календаря и `Work` | «calendar — Google CalDAV: all calendars» |
| 2:05 | Создать | New Event «Demo meeting» завтра 10:00 → Google Calendar (F5): есть | «Create event → Google Calendar» |
| 2:25 | Изменить | Перенести на 11:00, новое название → Google Calendar: изменилось | «Edit event» |
| 2:40 | Приглашение | Ящик B приглашает тестовый аккаунт (Google Calendar). В приложении — письмо-приглашение → Accept → Google Calendar: «Going — Yes» | «Respond to invitation — written to the user's calendar» |
| 3:10 | Удалить | Удалить «Demo meeting» → подтвердить → Google Calendar: нет | «Delete event» |
| 3:25 | **carddav** — чтение | Contacts: список контактов Google | «carddav — Google CardDAV: contacts» |
| 3:35 | Создать | New contact «Demo Contact», почта, телефон → Google Contacts: есть | «Create contact → Google Contacts» |
| 3:55 | Изменить | Добавить компанию → Google Contacts: изменилось | «Edit contact» |
| 4:10 | Удалить | Delete contact → Google Contacts: пропал | «Delete contact» |
| 4:25 | **contacts.readonly** | Письмо от сохранённого контакта — у него **фото профиля Google**; в Google Contacts у карточки своего фото нет | «contacts.readonly — Google profile photo of a saved contact (People API: emailAddresses, photos only; read-only)» |
| 4:55 | **contacts.other.readonly** | Google Contacts → Other contacts: человек. В приложении — его фото у письма | «contacts.other.readonly — profile photo of an "Other contacts" person (emailAddresses, photos only; read-only)» |
| 5:20 | Второй путь | Settings → Accounts → ящик → Google Calendar and Contacts: «connected» | «Calendar and Contacts can also be connected later from the account settings» |
| 5:35 | Удаление | Settings → Accounts → ящик → Delete account → подтвердить. myaccount.google.com/permissions (F5): Ogneliss Mail нет | «Removing the account deletes local data and revokes the token» |
| 6:00 | Конец | — | «Data is stored only on the device (encrypted). No developer server receives Google data» |

Советы: перед каждым «→ Google» обновлять страницу (F5); в приложении при
необходимости потянуть список вниз; сорвалось — переснять сцену, не
вырезать. Загрузка: YouTube → «Доступ по ссылке» (Unlisted).

---

## 3. Ответ Google (по-английски, Reply на их письмо)

Подставить значения в `[квадратных скобках]`, метки времени — из записи.

```
Hello Third-Party Data Safety Team,

Confirming narrower scopes. Ogneliss Mail no longer requests
https://mail.google.com/: Gmail mail is connected with a user-created app
password over IMAP/SMTP, and Google sign-in is used only for Calendar and
Contacts. The restricted scope has been removed from the app and from the
Data Access page of the Cloud Console.

1. Requested scopes (app and Cloud Console match exactly)

openid, email, profile,
https://www.googleapis.com/auth/calendar,
https://www.googleapis.com/auth/carddav,
https://www.googleapis.com/auth/contacts.readonly,
https://www.googleapis.com/auth/contacts.other.readonly

2. Why each scope is needed

- calendar: the app's Calendar uses Google's CalDAV API to show all the
  user's calendars, create, edit and delete events and record responses to
  meeting invitations. calendar.readonly cannot write. The app does not
  share or delete whole calendars.
- carddav: Contacts sync through Google's CardDAV API: view, search, create,
  edit and delete contacts. CardDAV has no narrower scope.
- contacts.readonly: read-only, People API people.connections.list with
  personFields=emailAddresses,photos only, to show the Google profile photo
  of saved contacts next to their messages. CardDAV does not return profile
  photos.
- contacts.other.readonly: read-only, People API otherContacts.list with
  readMask=emailAddresses,photos only, to show the profile photo of people in
  "Other contacts". No other scope covers "Other contacts".

3. Data handling

Sign-in is OAuth 2.0 for native apps with PKCE, directly between the device
and Google; no developer server receives codes, tokens or user data. Tokens
are kept in the OS keychain/keystore; Google data is stored only on the
device in an encrypted database and exchanged only with Google. It is not
sold, not used for advertising or AI training and not transferred to third
parties. Deleting the account in the app deletes its data and revokes the
token. Privacy policy: https://www.ogneliss.ru/mail/privacy

4. Demo video

[VIDEO_URL]

- 0:10 scopes in the Cloud Console
- 0:30 adding Gmail with an app password; 0:55 Google sign-in, client ID
  and scopes in the address bar; 1:20 consent screen, all scopes expanded
- 1:50 calendar: view, create, edit, invitation response, delete — each
  reflected in Google Calendar
- 3:25 carddav: view, create, edit, delete — reflected in Google Contacts
- 4:25 contacts.readonly: profile photo of a saved contact
- 4:55 contacts.other.readonly: profile photo of an "Other contacts" person
- 5:35 account removal: local data deleted, access revoked

5. Testing

A test account is ready (Calendar and Contacts are filled in):
- Google account: [TEST_EMAIL]
- Password: [PASSWORD]
- App password for adding the Gmail mailbox in the app: [APP_PASSWORD]
- 2-Step Verification backup codes: [CODE1] [CODE2] [CODE3]

Steps: install the app (Android: https://play.google.com/store/apps/details?id=com.ogneliss.mail;
iOS/macOS: [APP_STORE_OR_TESTFLIGHT_LINK]) → Add Account → Google → enter
the address and the app password, keep "Google Calendar and Contacts" on →
Sign In → sign in to Google with the same account and allow access.
Calendar and Contacts tabs: + to create; tap an item to edit or delete.
Invitations: open an invitation email → Accept / Tentative / Decline.

Best regards,
[NAME], Ogneliss Mail
```

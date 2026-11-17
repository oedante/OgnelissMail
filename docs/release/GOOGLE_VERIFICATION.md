# Проверка Google (OAuth app verification) — план, видео, ответ

Письмо Third-Party Data Safety Team от 17.11.2026. Проверка **не пройдена**,
Google просит четыре вещи:

1. **Оценку безопасности CASA** в лаборатории из списка ADA — из-за
   разрешения `https://mail.google.com/` (restricted). Обязательна и для
   приложений, которые работают только на устройстве.
2. **Обоснование** каждого из пяти разрешений: почему нельзя обойтись более
   узким.
3. **Совпадение разрешений**: что просит приложение = что в консоли, строка в
   строку.
4. **Новое видео**: каждое разрешение в работе, изменения видны в самом
   аккаунте Google (Gmail, Календарь, Контакты), экран согласия со всеми
   развёрнутыми разрешениями.

Ниже: решения владельца (§1), план по шагам (§2), сценарий видео (§3),
обоснования для консоли (§4), текст ответа (§5), инструкции для проверяющих
(§6). Тексты для Google — по-английски, их можно копировать как есть,
подставив значения в `[квадратных скобках]`.

---

## 1. Решения владельца

### 1.1. CASA — платно, раз в год

- Без CASA Google не одобрит `https://mail.google.com/`. Обойти нельзя:
  любое чтение Gmail через OAuth требует restricted-разрешения, а IMAP/SMTP
  принимают только `https://mail.google.com/`.
- Цена: по открытым данным на конец 2024 года Tier 2 у TAC Security стоит
  **540 $ за приложение в год** (цена со скидкой, согласованной Google).
  У других лабораторий из списка ADA цены обычно выше. Нынешнюю цену смотреть на сайте
  лаборатории. Продление — **ежегодно**.
- Как идёт: Google сообщает уровень (обычно Tier 2) → регистрация на портале
  лаборатории → сканирование приложения (сборка или исходники) и анкета по
  OWASP ASVS → исправление замечаний → лаборатория выдаёт Letter of
  Validation и сама передаёт его Google. Обычно 2–6 недель.
- По правилу CLAUDE.md (платные ресурсы разработки) — **решение за вами**.

Варианты:

| | Что получаем | Чего стоит |
|---|---|---|
| **А. Пройти CASA** (рекомендую, если Gmail нужен широкой аудитории) | Вход Google без предупреждения «приложение не проверено» и без лимита 100 пользователей; Gmail, Календарь и Контакты Google у всех | ~540 $/год и 2–6 недель; ответы на анкету безопасности (помогу) |
| **Б. Остаться без проверки** | Как сейчас: предупреждение при входе, до 100 новых пользователей через OAuth. Сверх лимита — Gmail по паролю приложения (уже сделано, 2.5.4); календарь и контакты Google без OAuth недоступны | Бесплатно |
| **В. Корпоративные клиенты на Google Workspace** (дополнение к Б) | Администратор организации отмечает Ogneliss Mail как доверенное (Admin console → Security → API controls → App access control, по Client ID). По документации Google для пользователей такого домена предупреждения и лимита нет — уточнить при первом клиенте | Бесплатно, делает администратор клиента |

### 1.2. Фото собеседников (`contacts.readonly`, `contacts.other.readonly`)

Рекомендую **оставить в заявке**: возможность видна пользователю и
повторяет Gmail, разрешения только на чтение, поля — только адрес и фото.
Убирать их нет смысла: без CASA заявка всё равно не пройдёт, а CASA от этих
разрешений не зависит. Если Google откажет именно по ним — уберём их из
консоли и соберём выпуск с `--dart-define=GOOGLE_PEOPLE_SCOPES=false`. Код
для этого уже есть.

Про «Critical Note» (не включать непроверенные разрешения в рабочие сборки):
это правило для уже проверенных приложений, которые добавляют новое. Наше
приложение не проверено целиком: предупреждение и лимит 100 действуют и без
фото. Перевыпускать сборки не нужно. Если хотите строго по букве — следующую
сборку для магазинов соберите с флагом `GOOGLE_PEOPLE_SCOPES=false`, а видео
записывайте на сборке без флага.

---

## 2. План по шагам

| # | Шаг | Кто |
|---|---|---|
| 0 | Решение по CASA (§1.1) и по фото (§1.2) | владелец |
| 1 | Консоль: выровнять список разрешений (§2.1) | владелец |
| 2 | Подготовить тестовые ящики и данные (§2.2) | владелец |
| 3 | Записать видео по сценарию (§3), загрузить на YouTube «доступ по ссылке» | владелец |
| 4 | В «Центре проверки» вставить обоснования (§4) | владелец |
| 5 | CASA (если «А»): регистрация в лаборатории, скан, анкета; ответы на вопросы анкеты — по §5 п.2, остальное — спросите меня | владелец + помогу |
| 6 | Ответить на письмо Google текстом §5 со ссылкой на видео | владелец |
| 7 | Через год — продление CASA (поставить напоминание) | владелец |

### 2.1. Консоль Google Cloud — точное совпадение

Google Auth Platform → **Доступ к данным (Data Access)**. В списке должно
быть **ровно это** — ни больше, ни меньше:

| Разрешение | Тип |
|---|---|
| `openid` | обычное |
| `.../auth/userinfo.email` (в коде — `email`) | обычное |
| `.../auth/userinfo.profile` (в коде — `profile`) | обычное |
| `https://mail.google.com/` | restricted |
| `https://www.googleapis.com/auth/calendar` | sensitive |
| `https://www.googleapis.com/auth/carddav` | sensitive |
| `https://www.googleapis.com/auth/contacts.readonly` | sensitive |
| `https://www.googleapis.com/auth/contacts.other.readonly` | sensitive |

Всё прочее (например, `calendar.readonly`, `calendar.events`, любые
`gmail.*`, `drive.*`) — **удалить** и сохранить. Именно так приложение
просит разрешения: `lib/services/mail/oauth/direct_oauth.dart`
(`_googleScopes`). Список в движке (`packages/mail_engine/.../oauth_helper.dart`)
приведён к тому же виду 17.11.2026 — раньше там были `calendar.readonly` и
`userinfo.email`; приложение его не использует, но код открыт.

Ещё в консоли:

- **Branding**: название «Ogneliss Mail», логотип, домашняя страница
  `https://www.ogneliss.ru/mail`, политика `https://www.ogneliss.ru/mail/privacy`,
  условия использования, авторизованный домен `ogneliss.ru`.
- Политика на сайте — **версия с разделом про People API** (обновление сайта
  2.6.2: строки `contacts.readonly` и `contacts.other.readonly` в таблице
  разрешений, раздел 4.3 Limited Use). Если обновление ещё не выложено —
  выложить до ответа.
- **Clients**: Android, iOS, Desktop. Если остался клиент «Web application»
  от старого сервера входа (Google сейчас входит без сервера) — удалить его,
  а из `.env` прокси убрать `GOOGLE_*`. Тогда честно: ни один сервер не
  касается данных Google, и анкета CASA короче.
- Publishing status — оставить **In production**.

> Проверить самому до отправки (у меня из этой сессии developers.google.com
> недоступен): на странице *CalDAV API Developer's Guide* в разделе об
> авторизации указано разрешение `https://www.googleapis.com/auth/calendar`.
> Если там названо и более узкое (например, `calendar.events`) — скажите,
> поменяю в коде до записи видео.

### 2.2. Подготовка к записи

Запись — на **Mac** (или Windows): приложение и браузер на одном экране,
адресная строка с `client_id` видна на экране согласия, изменения в Gmail
показываются сразу рядом.

1. **Ящик A** (главный, тестовый Gmail): язык аккаунта Google — English.
   В приложении язык — English (Settings → Language).
2. **Ящик B** (второй Gmail): для писем в A и приглашения на встречу.
3. Данные в ящике A:
   - 10–20 писем, хотя бы одно с вложением (PDF);
   - ярлык (label) `Projects` с парой писем;
   - подпись в Gmail (Settings → Signature), например «Best regards, Test»;
   - **сохранённый контакт** — человек с фото профиля Google, у карточки
     контакта своего фото нет (например, ящик B с фото профиля);
   - **«Другой контакт»** (Other contacts): человек с фото профиля Google,
     которому A отвечал, но не сохранял (третий ящик C с фото или знакомый);
     в Google Contacts → Other contacts он должен быть виден;
   - пара событий в Google Calendar, второй календарь (например, `Work`).
4. Ящик A **ещё не добавлен** в приложение. На
   `https://myaccount.google.com/permissions` у ящика A убрать доступ Ogneliss
   Mail, если он был: тогда Google покажет полный экран согласия.
5. Окна браузера (вкладки, вход под A): Gmail, Google Calendar, Google
   Contacts, Google Cloud Console → Data Access, myaccount.google.com/permissions.
6. Запись экрана: macOS — Cmd+Shift+5 (весь экран, 1080p и выше), Windows —
   Win+G. Звук не обязателен; подписи — текстом на экране (титры можно
   добавить в iMovie/Clipchamp) или голосом по-английски.
7. Длина 8–12 минут. Не ускорять, не вырезать середину действий. Каждое
   действие: сделать в приложении → переключиться на Google → обновить
   страницу → показать результат.

---

## 3. Сценарий видео

Подписи на экране — по-английски (как ниже в кавычках). Метки времени из
таблицы перенести в ответ (§5).

| Время | Сцена | Что показать | Подпись на экране |
|---|---|---|---|
| 0:00 | Титул | Название, проект, Client ID | «Ogneliss Mail — OAuth verification demo. Project: [PROJECT_ID]. OAuth client (Desktop): [CLIENT_ID]» |
| 0:10 | Консоль | Google Cloud Console → Google Auth Platform → Data Access: список из пяти разрешений | «Scopes configured in Cloud Console» |
| 0:30 | Вход | Приложение → Add Account → Google. Открывается браузер: **приблизить адресную строку** — видны `client_id` и `scope=` с теми же разрешениями. Выбрать ящик A. Если есть «Google hasn't verified this app» — Advanced → Go to Ogneliss Mail | «Sign-in: OAuth 2.0 with PKCE, directly with Google» |
| 1:00 | Согласие | Экран согласия: **раскрыть каждый пункт** («Show all» / стрелки у пунктов), медленно прокрутить, чтобы все пять разрешений были читаемы. Отметить все → Continue. Вернуться в приложение | «Consent screen — all requested scopes expanded» |
| 1:40 | **mail.google.com** — чтение | Inbox загрузился; меню папок: Inbox, Sent, Drafts, Spam, Trash, ярлык `Projects`. Открыть письмо, открыть вложение PDF | «https://mail.google.com/ — IMAP: folders, messages, attachments» |
| 2:10 | Поиск на сервере | Поиск по слову из старого письма, результат с сервера | «Server-side search (IMAP SEARCH)» |
| 2:25 | Отправка | Новое письмо ящику B, отправить. Gmail (A) → Sent: письмо есть. (По желанию: вкладка ящика B → письмо пришло) | «Send via SMTP → appears in Gmail Sent» |
| 2:55 | Ответ и черновик | Ответить на письмо — отправить. Начать новое письмо, закрыть → сохранено в Drafts. Gmail → Drafts: черновик есть | «Reply; draft saved to Gmail Drafts» |
| 3:20 | Флаги | Mark Unread, Flag (звезда). Gmail: письмо жирное и со звездой. Вернуть Mark Read | «Read/unread and star are synced to Gmail» |
| 3:40 | Перенос и архив | Move to → `Projects`. Archive другого письма. Gmail: письмо под ярлыком, второе — не во «Входящих», есть во «Вся почта» | «Move to label, archive» |
| 4:05 | Ярлыки | New folder `Demo` → в Gmail появился ярлык. Rename folder → `Demo 2`. Delete folder → в Gmail пропал | «Create / rename / delete labels» |
| 4:30 | Спам | Отметить письмо как Spam. Gmail → Spam: оно там | «Report spam» |
| 4:45 | Удаление | Удалить письмо → Gmail → Trash: оно там | «Delete → moved to Gmail Trash» |
| 5:00 | **Удаление навсегда** | В приложении открыть Trash → это письмо → удалить → «Delete permanently?» → подтвердить. Gmail → Trash: обновить — письма нет. В поиске Gmail `in:anywhere "<тема>"` — ничего. Затем Empty Trash в приложении → Gmail Trash пуст | «Permanent deletion (IMAP EXPUNGE) — message purged from Gmail» |
| 5:40 | Подпись | Settings → Signatures → Import from mailbox → подпись из Gmail. Рядом — Gmail Settings → Signature, тот же текст | «Gmail signature imported (Gmail API sendAs, read-only)» |
| 6:00 | Новое письмо | Из ящика B отправить письмо A → появляется в приложении (и уведомление) | «New mail in real time (IMAP IDLE)» |
| 6:20 | **calendar** — чтение | Calendar: события обоих календарей (основной и `Work`) | «https://www.googleapis.com/auth/calendar — CalDAV» |
| 6:35 | Создать | New Event «Demo meeting» на завтра 10:00 → Google Calendar: событие есть | «Create event → Google Calendar» |
| 6:55 | Изменить | Перенести на 11:00, сменить название → Google Calendar: изменилось | «Edit event» |
| 7:10 | Приглашение | Из ящика B (Google Calendar) пригласить A на встречу. В приложении — письмо-приглашение → Accept. Google Calendar (A): «Going — Yes»; у B — A принял | «Respond to invitation — written to the user's calendar» |
| 7:40 | Удалить | Удалить «Demo meeting» → «Delete event?» → Google Calendar: события нет | «Delete event» |
| 7:55 | **carddav** — чтение | Contacts: список контактов Google | «https://www.googleapis.com/auth/carddav — CardDAV» |
| 8:05 | Создать | New contact «Demo Contact», почта и телефон → Google Contacts: есть | «Create contact → Google Contacts» |
| 8:25 | Изменить | Добавить телефон/компанию → Google Contacts: изменилось | «Edit contact» |
| 8:40 | Удалить | «Delete contact?» → Google Contacts: пропал (виден в Trash контактов) | «Delete contact» |
| 8:55 | **contacts.readonly** | Inbox: у письма сохранённого контакта — его **фото профиля Google**; открыть карточку контакта: в Google Contacts у карточки своего фото нет — фото из профиля. Рядом Gmail показывает то же фото | «contacts.readonly — Google profile photo of a saved contact (People API: emailAddresses, photos only). CardDAV does not return profile photos» |
| 9:20 | **contacts.other.readonly** | Google Contacts → Other contacts: человек C. В приложении у его письма — его фото профиля | «contacts.other.readonly — photo of a person from "Other contacts" (read-only, emailAddresses + photos only)» |
| 9:45 | Удаление данных | Settings → Accounts → ящик A → Delete account → подтвердить: ящик и его письма исчезли из приложения. myaccount.google.com/permissions → обновить: Ogneliss Mail больше нет в списке | «Removing the account deletes all local data and revokes the token» |
| 10:10 | Конец | — | «Data is stored only on the device (encrypted). No developer server receives Google data» |

Советы:

- Перед каждым «→ Gmail» обновлять страницу Gmail (F5), чтобы было видно, что
  изменение пришло с сервера.
- Синхронизация в приложении: при необходимости потянуть список вниз.
- Если что-то сорвалось — переснять сцену, а не вырезать.
- Загрузка: YouTube → «Доступ по ссылке» (Unlisted), не «Ограниченный».

---

## 4. Обоснования для консоли (Verification Center → по разрешению)

Скопировать в поля обоснования соответствующих разрешений.

**https://mail.google.com/**

> Ogneliss Mail is a native email client (Android, iOS, macOS, Windows,
> Linux). It connects to Gmail with the standard IMAP and SMTP protocols,
> using the same open-source mail engine it uses for every other provider.
> Gmail's IMAP and SMTP (XOAUTH2) accept only the https://mail.google.com/
> scope; no narrower Gmail scope (gmail.readonly, gmail.modify,
> gmail.compose, gmail.send) authorizes IMAP or SMTP. User-facing features
> that use this scope: reading all folders/labels and messages with
> attachments; new-mail notifications in real time (IMAP IDLE); server-side
> search; sending, replying and forwarding (SMTP) and saving drafts; marking
> messages read/unread and starred; moving messages between labels,
> archiving and reporting spam; creating, renaming and deleting labels;
> moving messages to Trash and, when the user confirms "Delete permanently"
> or "Empty Trash", permanently deleting them (IMAP EXPUNGE) — permanent
> deletion is not possible with any narrower scope; importing the user's
> Gmail signature (users.settings.sendAs.list, read-only). All processing
> happens on the user's device; mail is stored only on the device in an
> encrypted database and is exchanged only with Google.

**https://www.googleapis.com/auth/calendar**

> The app's Calendar shows and edits the user's Google Calendar through
> Google's CalDAV API (the same CalDAV implementation is used for other
> providers). Features: viewing events of all the user's calendars;
> creating, editing and deleting events (including a single occurrence of a
> recurring event); responding to meeting invitations received by email
> (Accept / Tentative / Decline), which writes the response to the event in
> the user's calendar. calendar.readonly cannot create, edit or delete events
> or record invitation responses. CalDAV access to Google Calendar is
> authorized with this scope. The app does not create, share or delete whole
> calendars and does not change sharing settings.

**https://www.googleapis.com/auth/carddav**

> The app's Contacts section syncs the user's Google Contacts through
> Google's CardDAV API (the same CardDAV implementation is used for other
> providers): viewing and searching contacts, address autocomplete and
> sender names in the mailbox, creating, editing and deleting contacts.
> CardDAV is authorized only with this scope; there is no narrower or
> read-only CardDAV scope, and write access is required for create, edit and
> delete.

**https://www.googleapis.com/auth/contacts.readonly**

> Used only to show the Google profile photo of people in the user's saved
> contacts next to their messages and on their contact card, as Gmail does.
> CardDAV returns only the photo stored on the contact card itself, not the
> person's Google profile photo, so the carddav scope cannot provide it. The
> app calls People API people.connections.list with
> personFields=emailAddresses,photos only — no other fields are requested —
> and never writes. This is the narrowest scope that allows
> people.connections.list.

**https://www.googleapis.com/auth/contacts.other.readonly**

> Used only to show the Google profile photo of people in the user's "Other
> contacts" (people the user has exchanged mail with but has not saved) next
> to their messages. The app calls People API otherContacts.list with
> readMask=emailAddresses,photos only and never writes. This is the only
> scope that allows otherContacts.list; neither carddav nor contacts.readonly
> covers "Other contacts".

---

## 5. Ответ на письмо (по-английски)

Отвечать на то же письмо (Reply). Пункт 6 — по решению §1.1.

> Hello Third-Party Data Safety Team,
>
> Thank you for the review. Please find our clarifications and the new
> demonstration video below.
>
> **1. About the app**
>
> Ogneliss Mail is a native email, calendar and contacts client for
> Android, iOS, macOS, Windows and Linux (project [PROJECT_ID]; OAuth
> clients: Android, iOS and Desktop). It works with Gmail through the
> standard IMAP/SMTP (mail), CalDAV (calendar) and CardDAV (contacts)
> protocols, using the same open-source engine as for other providers. It is
> not an integration platform: each scope backs a visible feature of the
> app.
>
> **2. Data handling**
>
> - Sign-in is OAuth 2.0 for native apps with PKCE, directly between the
>   device and Google. No developer server receives authorization codes,
>   tokens or Google user data.
> - Tokens are kept in the OS keychain/keystore. Google user data is stored
>   only on the user's device in an encrypted (SQLCipher) database and is
>   exchanged only with Google.
> - Google user data is not sold, not used for advertising, not used to
>   train AI models and not transferred to third parties.
> - Deleting the account in the app deletes all of its data from the device
>   and revokes the token (oauth2.googleapis.com/revoke). Users can also
>   revoke access at myaccount.google.com/permissions.
> - Privacy policy: https://www.ogneliss.ru/mail/privacy (section 4 lists
>   every scope and includes the Limited Use statement).
>
> **3. Scope justification**
>
> - https://mail.google.com/ — Gmail's IMAP and SMTP (XOAUTH2) accept only
>   this scope; no narrower Gmail scope authorizes IMAP or SMTP. It backs
>   reading all labels and messages, real-time notifications (IMAP IDLE),
>   server search, sending/replying/forwarding, drafts, read/star flags,
>   moving between labels, archive, spam, creating/renaming/deleting labels,
>   moving to Trash and permanent deletion (Delete permanently, Empty Trash),
>   which no narrower scope allows, and importing the user's Gmail
>   signature.
> - https://www.googleapis.com/auth/calendar — the Calendar uses Google's
>   CalDAV API to show all the user's calendars and to create, edit and
>   delete events and record responses to invitations. calendar.readonly
>   cannot write. The app does not share or delete whole calendars.
> - https://www.googleapis.com/auth/carddav — Contacts sync through Google's
>   CardDAV API: view, search, create, edit and delete contacts. CardDAV has
>   no narrower scope.
> - https://www.googleapis.com/auth/contacts.readonly — read-only, People API
>   people.connections.list with personFields=emailAddresses,photos only, to
>   show the Google profile photo of saved contacts next to their messages
>   (as Gmail does). CardDAV does not return profile photos.
> - https://www.googleapis.com/auth/contacts.other.readonly — read-only,
>   People API otherContacts.list with readMask=emailAddresses,photos only,
>   to show the profile photo of people in "Other contacts" next to their
>   messages. No other scope covers "Other contacts".
>
> **4. Scope alignment**
>
> The app requests exactly: openid, email, profile,
> https://mail.google.com/, https://www.googleapis.com/auth/calendar,
> https://www.googleapis.com/auth/carddav,
> https://www.googleapis.com/auth/contacts.readonly and
> https://www.googleapis.com/auth/contacts.other.readonly. The Data Access
> page of the Cloud Console now lists exactly the same scopes; scopes that
> were not used by the app have been removed. [Если лишних в консоли не было —
> последнюю фразу убрать.]
>
> **5. Demo video**
>
> [VIDEO_URL]
>
> - 0:10 — scopes configured in the Cloud Console
> - 0:30 — sign-in, OAuth client ID in the address bar, consent screen with
>   all scopes expanded
> - 1:40 — https://mail.google.com/: folders, messages, search, send, reply,
>   drafts, flags, labels, archive, spam, delete; 5:00 — permanent deletion
>   shown purged in Gmail; 5:40 — signature import
> - 6:20 — calendar: view, create, edit, invitation response, delete, each
>   reflected in Google Calendar
> - 7:55 — carddav: view, create, edit, delete, reflected in Google Contacts
> - 8:55 — contacts.readonly: profile photo of a saved contact
> - 9:20 — contacts.other.readonly: profile photo of an "Other contacts"
>   person
> - 9:45 — account removal: local data deleted, access revoked
>
> **6. Security assessment**
>
> [Вариант А:] We are completing the CASA assessment with [LAB_NAME]; the
> lab will submit the Letter of Validation to Google.
>
> [Вариант Б — пункт 6 не писать.]
>
> **7. Testing**
>
> The app has no login of its own, so no test credentials are needed:
> please sign in with any Google account. Steps are in the next section.
>
> Best regards,
> [NAME], Ogneliss Mail

## 6. Инструкции для проверяющих (добавить в конец ответа)

> **How to test**
>
> 1. Install Ogneliss Mail: Android — Google Play
>    (https://play.google.com/store/apps/details?id=com.ogneliss.mail);
>    iOS / macOS — [TESTFLIGHT_OR_APP_STORE_LINK]; Windows and Linux —
>    [GITHUB_RELEASES_LINK].
> 2. Open the app → **Add Account** → **Google** → sign in with any Google
>    account and allow access. The Inbox opens.
> 3. Mail: open the menu (☰) for folders/labels; long-press (or right-click)
>    a message for Move to, Archive, Spam, Flag, Mark Read/Unread, Delete.
>    Permanent deletion: open **Trash** → delete a message → **Delete
>    permanently?** → confirm, or menu → **Empty Trash**. Signature import:
>    **Settings → Signatures → Import from mailbox**.
> 4. Calendar: **Calendar** tab → **+** (New Event); tap an event to edit or
>    delete. Invitations: open an invitation email → **Accept / Tentative /
>    Decline**.
> 5. Contacts: **Contacts** tab → **+** (New contact); open a contact to edit
>    or delete.
> 6. Profile photos: messages from your saved contacts and "Other contacts"
>    who have a Google profile photo show it next to the message (loaded in
>    the background during the first sync after sign-in).
> 7. Remove the account: **Settings → Accounts → [account] → Delete
>    account**.

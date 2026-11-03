# App Review — ответ на Guideline 2.1 (Information Needed)

Apple, 31.10.2026, версия 1.8.12 (128): «Information Needed — New App
Submission». Apple просит в поле **Notes** шесть пунктов: видео с устройства,
назначение и аудиторию, как войти, внешние сервисы, различия по регионам,
документы для регулируемых отраслей. Текст ниже отвечает на них по порядку.
Его нужно вставить в **App Store Connect → приложение → версия → App Review
Information → Notes** (по-английски, до 4000 знаков; в нём ~3650). Демо-ящик
указывается в полях **Sign-In Information** той же страницы.

## Что сделать владельцу

### 1. Какую сборку отправлять

Лучше сразу новую: в 1.8.12 нет исправлений и функций 1.9–1.10. Порядок
такой:

1. Версия в `main` уже 1.10.4 (135): собрать в Xcode из архива исходников
   и выложить в TestFlight.
2. В App Store Connect на странице отклонённой версии поменять номер
   **1.8.12 → 1.10.4**. Это можно, пока версия не одобрена.
3. Выбрать новую сборку.

Если отправлять 1.8.12 как есть, в Notes удалить строки про BIMI
(«Sender logos») и перевод («Apple Translation»): этих функций там ещё нет.

Перед отправкой проверить сборку на своём iPhone через TestFlight. Apple об
этом прямо напоминает: проверка идёт на настоящих устройствах.

### 2. Демо-ящик для проверяющего

У приложения нет своих учётных записей, поэтому проверяющему нужен готовый
почтовый ящик. Требования к нему:

- **Вход без кода из SMS и без проверки «новое устройство».** Проверяющий в
  США. Google и Яндекс через свою страницу входа (OAuth) почти наверняка
  попросят подтверждение, и проверка встанет.
- **Проще всего — Mail.ru с паролем приложения** (или свой домен по IMAP с
  обычным паролем):
  1. Завести ящик, например `ogneliss.review@mail.ru`.
  2. В «Безопасность → Пароли для внешних приложений» создать пароль
     приложения.
  3. В Sign-In Information: User name — адрес, Password — пароль
     приложения.
  4. Вход в приложении: адрес → «Далее» → поле «Пароль для внешнего
     приложения» → ящик.
- **Положить в ящик заранее:**
  - 6–10 писем: обычное, с вложением (PDF или XLSX), с картинкой, рассылку,
    цепочку из 2–3 ответов;
  - приглашение на встречу (.ics);
  - 1–2 контакта.
- **Не удалять ящик и не менять пароль**, пока идёт проверка и пока
  приложение в магазине: проверяющие заходят и при следующих версиях.

### 3. Видео с iPhone

- Последняя iOS, запись экрана из Пункта управления, 2–4 минуты.
- **Начать с запуска приложения**, после чистой установки: удалить
  приложение и поставить из TestFlight. Так в начале видно лицензионное
  соглашение и первый вход.
- На видео — только демо-ящик, без своих писем и ящиков.

Порядок съёмки, как в Notes:

1. Запуск → заставка → лицензионное соглашение: отметить согласие →
   «Принять и продолжить» → знакомство («Пропустить» или пролистать).
2. «Вход в почту»: показать кнопки «или выберите почту» (Google, Microsoft,
   Яндекс…).
   Затем ввести адрес демо-ящика → «Далее» → пароль приложения → «Входящие»
   загрузились.
3. Открыть письмо → открыть вложение → назад.
4. «Ответить» → пара слов → «Отправить».
5. «Новое письмо» → адрес (можно сам демо-ящик) → тема, текст → прикрепить
   файл или фото → «Отправить».
6. Поиск по ленте (слово из темы).
7. Меню письма → «Заблокировать отправителя» → «Заблокировать»: письмо
   уходит в «Спам», новые письма с этого адреса — тоже. Это ответ Apple на
   «механизм жалоб и блокировки». Затем открыть «Спам» → письмо → «Не
   спам», в меню — «Разблокировать отправителя».
8. Календарь → встреча. Контакты → контакт.
9. Настройки → «Аккаунты» → демо-ящик → «Удалить аккаунт» → подтвердить.
   Ящик и все его данные исчезают с устройства. Это ответ на «account
   deletion».
   Если после этого нужно продолжить, ящик можно добавить снова; на видео
   удаление — последним.

Где отправить видео (.mov или .mp4):

- в **App Review Information → Attachment**, если поле есть;
- или в ответе Apple в «Сообщениях» (Resolution Center), там можно
  прикрепить файл;
- если файл не принимается — ссылка на Яндекс Диск или Google Drive с
  доступом по ссылке, вписать в последнюю строку Notes.

### 4. Отправка

1. Вставить Notes, заменив `<…>`.
2. Заполнить Sign-In Information.
3. Прикрепить видео.
4. «Повторно отправить на проверку».
5. В «Сообщениях» коротко ответить: «The requested information and a
   screen recording have been added to App Review Information. Thank you.»

## Notes (вставить)

```
Ogneliss Mail is a free email, calendar and contacts client for anyone who already has an email account, personal or work. It has no accounts of its own: users connect existing mailboxes (Microsoft Exchange / Exchange Online, Gmail, Outlook.com, iCloud Mail, Yandex, Mail.ru or any IMAP/SMTP server). There is no registration, no paid content, no in-app purchases, subscriptions or ads, and no content is shared between users of the app.

1. SCREEN RECORDING
Recorded on an iPhone with the latest iOS, starting from launch: licence agreement, sign-in to the demo mailbox, inbox, reading a message and attachment, reply, new message with an attachment, search, Block sender / Not spam, calendar, contacts, and removing the mailbox in Settings.
Account creation and deletion: the app does not create accounts, so there is no registration and no provider account to delete. Settings > Accounts > (mailbox) > Delete account removes the mailbox and all its data from the device. Mail is not user-generated content shared inside the app. Unwanted senders can be blocked (message menu > Block sender): their messages go to Junk without notifications; the list is in Settings > VIPs and rules. Messages from spoofed or lookalike senders show a warning.

2. PURPOSE AND AUDIENCE
For people and organisations that use several mailboxes, including corporate Exchange, and want one private app instead of several. Value: mail, calendar, contacts, tasks and notes of all mailboxes in one place, with work features (shared mailboxes, out-of-office replies, server rules, delivery tracking, scheduled send). Mail is stored only on the device in an encrypted database; the developer never receives messages, contacts or passwords. The app is for the general public, not for a single organisation.

3. HOW TO SIGN IN
The demo mailbox is in Sign-In Information (<service, e.g. Mail.ru>). Launch > tick the licence checkbox > "Accept and continue" > "Skip" > "Sign In to Mail" > enter the demo address > Next > enter the password from Sign-In Information > the inbox opens in a few seconds. It contains sample messages, an attachment, a meeting invitation and a contact. Any other mailbox works too; Google, Microsoft and Yandex use their own sign-in pages (OAuth).

4. EXTERNAL SERVICES
- The user's own mail providers: IMAP/SMTP, Exchange ActiveSync and EWS, Microsoft Graph, CalDAV/CardDAV.
- OAuth 2.0 sign-in with Google, Microsoft, Yandex and Mail.ru. The code-for-token exchange runs on the developer's stateless server (https://www.ogneliss.ru/oauth), so the client secret is not in the app; the server stores no mail, addresses or tokens.
- Sender logos (BIMI): the same server is asked for the logo of a sender's domain; only the domain name is sent.
- Apple Push Notification service: the developer's relay (https://www.ogneliss.ru/push) sends "check mail" signals; it knows only the device token, never addresses or messages.
- Apple Translation framework (iOS 18+) for on-device translation of messages.
No payment processors, analytics, advertising or cloud AI services are used.

5. REGIONS
The app works the same in all regions; the interface is available in 27 languages. For Russian mail servers that use the Russian Trusted Root CA, its certificates can be turned on for a single mailbox (off by default); nothing changes elsewhere.

6. REGULATED CONTENT
Not a regulated industry; no protected third-party material. Exchange support is an independent implementation of Microsoft's published Open Specifications; the app is free and open source (Apache 2.0): https://github.com/oedante/OgnelissMail

Screen recording: <attached / link>
```

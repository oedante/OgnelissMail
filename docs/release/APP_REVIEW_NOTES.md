# App Review — ответ на Guideline 2.1 (Information Needed)

Apple, 31.10.2026, версия 1.8.12 (128): нужны видео с устройства и сведения
о приложении. Текст ниже — в поле **App Store Connect → версия → App Review
Information → Notes** (по-английски, до 4000 знаков). Демо-ящик — в поля
**Sign-In Information** (User name / Password) той же страницы.

## Что сделать владельцу

1. **Демо-ящик для проверяющего.** Приложение не создаёт своих учётных
   записей — оно открывает уже существующие почтовые ящики. Проверяющему
   нужен рабочий ящик: заведите отдельный тестовый (например, Яндекс или
   Mail.ru с паролем приложения, либо свой домен по IMAP), положите в него
   несколько писем, встречу и контакт. Адрес и пароль приложения — в
   Sign-In Information; в Notes ниже вписать, какой это сервис.
2. **Видео с iPhone** (последняя iOS, запись экрана из Пункта управления),
   с запуска приложения:
   запуск → «Добавить ящик» → вход в демо-ящик → «Входящие» → открыть
   письмо → «Ответить», написать и отправить → «Новое письмо» с вложением →
   поиск → календарь (открыть встречу) → контакты → настройки →
   «Настройки → Аккаунты → ящик → Удалить аккаунт» (показывает, что данные
   удаляются). Видео загрузить в Notes как вложение (App Store Connect
   позволяет прикрепить файл к ответу) или ссылкой.
3. Вставить текст ниже, заменив `<…>`, и нажать «Повторно отправить на
   проверку».

## Notes (вставить)

```
Ogneliss Mail is a free email, calendar and contacts client. It has no accounts of its own: users connect mailboxes they already have (Microsoft Exchange / Exchange Online, Gmail, Outlook.com, iCloud, Yandex, Mail.ru or any IMAP/SMTP server). There is no registration, no paid content, no in-app purchases, no subscriptions, no ads and no user-generated content shared with other users.

PURPOSE AND AUDIENCE
People and organisations who use several mailboxes, including corporate Exchange, and want one private app for mail, calendar, contacts, tasks and notes. Mail is stored only on the device (encrypted database); the developer does not receive messages, contacts or passwords.

DEMO ACCOUNT
Sign-In Information contains a test mailbox at <service, e.g. Yandex Mail>. To sign in: launch the app → "Add mailbox" → enter the address → <"Sign in with Yandex" / enter the app password> → the inbox loads in a few seconds. The mailbox already has sample messages, an event and a contact.

MAIN FEATURES
- Mail: read, reply, forward, compose with attachments, search, conversations, folders, swipe actions, scheduled send and undo send.
- Calendar, contacts, tasks and notes of the connected mailbox (Exchange, CalDAV/CardDAV).
- Settings → Accounts lets the user remove a mailbox; this deletes all its data from the device. Because the app does not create accounts, no account deletion with a provider is involved.

EXTERNAL SERVICES
- The user's own mail providers (IMAP/SMTP, Exchange ActiveSync/EWS, Microsoft Graph, CalDAV/CardDAV).
- OAuth 2.0 sign-in with Google, Microsoft, Yandex and Mail.ru. The code-for-token exchange runs on the developer's stateless sign-in server (https://www.ogneliss.ru/oauth), so the OAuth client secret never ships in the app; the server keeps no mail, addresses or tokens (the app holds them, the refresh token encrypted).
- Apple Push Notification service: the developer's relay (https://www.ogneliss.ru/push) sends silent "check mail" signals; it knows only the device push token and the chosen interval, never addresses or messages.
No payment processors, analytics or AI services are used.

REGIONS
The app works the same in all regions; the interface is available in 27 languages. It includes the Russian Trusted Root CA certificates so that Russian mail servers that use them can be reached; this does not change behaviour elsewhere.

REGULATED CONTENT
The app does not operate in a regulated industry and contains no protected third-party material. Exchange support is an independent implementation of Microsoft's published Open Specifications.

A screen recording made on an iPhone with the latest iOS is attached: <link or "attached">.
```

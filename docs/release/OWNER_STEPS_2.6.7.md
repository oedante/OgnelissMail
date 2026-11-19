# Ogneliss Mail 2.6.7 — что сделать владельцу

2.6.7 (166) — почта Gmail по паролю приложения (без
`https://mail.google.com/`), виджет календаря со всеми делами и вкладкой
«Мой день». «Что нового» — `STORE_NOTES_2.6.7.md`. Ключи, Xcode, база
данных и зависимости не менялись.

| | Нужно? |
|---|---|
| Тег `v2.6.7` | да — раздел 1 |
| Google Cloud Console: убрать доступ к почте, отправить на проверку | да — раздел 2 |
| Ответ Google «Confirming narrower scopes» | да — раздел 3, после раздела 2 |
| Сервер входа (если работает): `GOOGLE_SCOPE` | да, если он включён — раздел 4 |
| Сайт | да — архив сайта прислан отдельно |

## 1. Тег для сборки на GitHub: `v2.6.7`

После слияния PR в `main`:

```bash
git fetch origin
```
```bash
git tag -a v2.6.7 -m "Ogneliss Mail 2.6.7" origin/main
```
```bash
git push origin v2.6.7
```

## 2. Google Cloud Console — убрать доступ к почте

Лучше — когда 2.6.7 уже в Google Play и App Store (прежние сборки ещё
просят доступ к почте).

1. console.cloud.google.com → проект Ogneliss → **Google Auth Platform →
   Data Access** (или «APIs & Services → OAuth consent screen → Scopes»).
2. Удалите `https://mail.google.com/` из списка (Restricted scopes).
   Остаются: `openid`, `email`, `profile`, `.../auth/calendar`,
   `.../auth/carddav`, `.../auth/contacts.readonly`,
   `.../auth/contacts.other.readonly`.
3. **Save**, затем **Verification Center → Submit for verification**
   (в обосновании и видео — только календарь и контакты; из видео уберите
   фрагмент про почту). Вход Google в видео: экран «Gmail — пароль
   приложения» с включённым «Календарь и контакты Google» → «Войти» →
   страница согласия Google (видны права календаря и контактов) → календарь
   и контакты в приложении. Второй путь — «Настройки → Аккаунты → ящик →
   Календарь и контакты Google».
4. Gmail API в проекте больше не нужен — его можно отключить
   («APIs & Services → Enabled APIs → Gmail API → Disable»), это не
   обязательно.

## 3. Ответ Google

Ответьте прямо на их письмо (Third-Party Data Safety Team), одной строкой,
как они просили:

```
Confirming narrower scopes
```

При желании — вторым абзацем:

```
Ogneliss Mail 2.6.7 no longer requests https://mail.google.com/. Gmail is
now connected with a user-created app password over IMAP/SMTP; Google
sign-in is used only for Calendar and Contacts. The restricted scope has
been removed from the OAuth consent screen.
```

## 4. Сервер входа (только если он работает)

В `.env` сервера `server/oauth-proxy` уберите `https://mail.google.com/` из
`GOOGLE_SCOPE` и перезапустите контейнер. Новое значение —
`server/oauth-proxy/PROVIDERS.md`.

## 5. Что проверить

- **Новый ящик Gmail.** «Добавить ящик» → плитка Google (или адрес
  …@gmail.com → «Далее»): экран «Gmail — пароль приложения» с короткой
  инструкцией, кнопка «Создать пароль приложения» открывает страницу Google.
  Введите пароль как есть, с пробелами — ящик добавится, письма придут.
- **Календарь и контакты Google.** При добавлении Gmail оставьте
  «Календарь и контакты Google» включённым: после пароля откроется страница
  Google — войдите тем же аккаунтом. Другим аккаунтом — сообщение «Вы вошли
  как … — это другой ящик», календарь не подключается. Выключили — позже
  «Настройки → Аккаунты → ящик → Календарь и контакты Google».
- **Ящик Gmail, добавленный раньше через Google.** После обновления — «Не
  удаётся войти» → «Войти снова» → тот же экран с паролем приложения. Письма
  и папки на месте, календарь Google этого ящика работает.
- **Виджет «Календарь»** (Android): задачи, поручения и приглашения в днях;
  вкладка «Мой день»; выходные красным.

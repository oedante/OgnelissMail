# OAuth на всех платформах — настройка

Единый вход реализован в `lib/services/mail/oauth/cross_platform_oauth.dart`
(`crossPlatformOAuthProvider`). Маршрутизация по платформе:

| Платформа | Механизм | Redirect URI |
|---|---|---|
| Android / iOS / macOS | `flutter_appauth` (системный браузер) | `com.example.mail:/oauth2redirect` |
| Windows / Linux | loopback HTTP-сервер на `127.0.0.1` + системный браузер | `http://127.0.0.1:<случайный порт>/` |
| Web | popup + `web/oauth2redirect.html` (postMessage) | `<origin>/oauth2redirect.html` |

Desktop и Web используют единый `OAuthHelper` движка (code-flow + **PKCE S256**),
секрет клиента в коде не зашит (публичный клиент + PKCE).

## Что зарегистрировать в кабинетах провайдеров (redirect URIs)
Для **каждого** clientId добавить все нужные redirect:
- `com.example.mail:/oauth2redirect` (мобильные/macOS);
- `http://127.0.0.1` (loopback — Google/Yandex разрешают любой порт для «Desktop app»);
- `https://<ваш-web-домен>/oauth2redirect.html` (web).

clientId задаются в `lib/core/constants/app_constants.dart`
(`googleClientId`, `yandexClientId`, `mailruClientId`).

## Нативная конфигурация (после `flutter create` платформенных папок)

### Android — `android/app/build.gradle`, блок `defaultConfig`:
```gradle
manifestPlaceholders += [appAuthRedirectScheme: 'com.example.mail']
```

### iOS / macOS — `Info.plist` (внутри корневого `<dict>`):
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>com.example.mail</string></array>
    <key>CFBundleURLName</key>
    <string>OAuth Callback</string>
  </dict>
</array>
```

### Web
Файл `web/oauth2redirect.html` уже в проекте — он возвращает код в приложение
через `postMessage`. Дополнительной настройки не требуется.

## Подключение к экрану добавления аккаунта
Вместо прямого вызова `OAuthService.authenticateGoogle()` использовать:
```dart
final result = await ref.read(crossPlatformOAuthProvider).authenticate('google');
// 'google' | 'yandex' | 'mailru' | 'yahoo'
```
Это автоматически выберет нужный для платформы механизм.

## Microsoft Entra: Exchange Online и Microsoft Graph (1.8.10)

Вход без сервера входа — клиент `MS_CLIENT_ID` (`config/dart_defines.json`),
регистрация «Accounts in any organizational directory and personal Microsoft
accounts», платформа «Mobile and desktop applications», адреса возврата
`com.ogneliss.mail://oauth/microsoft` и `http://localhost`, «Allow public
client flows» = Yes (подробно — в начале `lib/services/mail/oauth/direct_oauth.dart`).

Microsoft отключает EWS в Exchange Online (с 1 октября 2026 — по
организациям, окончательно — в апреле 2027). Почта, календарь, контакты и
автоответ ящика Exchange Online идут по ActiveSync и от этого не зависят;
адресная книга, подсказки MailTips, фото коллег, правила сервера, «Восстановить
удалённые», переговорные и состав рассылок с 1.8.10 идут через Microsoft Graph
(с 1.8.11 — в движке: `packages/mail_engine`, `GraphEngine`; токен Graph —
`lib/services/mail/oauth/graph_tokens.dart`), EWS — запасной путь, пока он открыт.

«API permissions» регистрации (все — Delegated):

| API | Право | Зачем | Согласие администратора |
|---|---|---|---|
| Office 365 Exchange Online | `EAS.AccessAsUser.All` | почта, календарь, контакты (ActiveSync) | нет |
| Office 365 Exchange Online | `EWS.AccessAsUser.All` | онлайн-архив, общие ящики, импорт подписи — пока EWS открыт | нет |
| Microsoft Graph | `User.Read` | своя карточка и фото | нет |
| Microsoft Graph | `User.ReadBasic.All` | фото коллег | нет |
| Microsoft Graph | `People.Read` | должность, отдел, кабинет, телефоны коллег | нет |
| Microsoft Graph | `Mail.ReadWrite` | подсказки MailTips, «Восстановить удалённые» | нет |
| Microsoft Graph | `MailboxSettings.ReadWrite` | правила сервера, категории Outlook | нет |
| Microsoft Graph | `Place.Read.All` | переговорные (по желанию) | **да** |
| Microsoft Graph | `GroupMember.Read.All` | состав рассылок (по желанию) | **да** |
| Microsoft Graph | `User.Read.All` | руководитель в карточке коллеги (по желанию) | **да** |
| Microsoft Graph | `IMAP.AccessAsUser.All`, `SMTP.Send`, `offline_access`, `openid`, `email`, `profile` | Outlook.com по IMAP/SMTP и вход | нет |

`Calendars.*`, `Contacts.*`, `Mail.Read`, `Mail.ReadBasic`, `Mail.Send` приложение
не использует — их можно не добавлять.

При входе в Exchange Online приложение просит согласие на права без
согласия администратора (`GraphEngine.consentScopes`). Если организация
не разрешает сотрудникам давать согласие, вход повторяется без прав Graph
(ActiveSync работает и так), а в настройках ящика пункт «Microsoft Graph»
показывает «Нет согласия». Тогда администратор организации открывает
регистрацию в своём Entra («Enterprise applications» → Ogneliss Mail →
«Permissions» → «Grant admin consent»); права с согласием администратора
(`Place.Read.All`, `GroupMember.Read.All`, `User.Read.All`) приложение получает
только так. Токен Graph выдаёт тот же refresh-токен
(`scope=https://graph.microsoft.com/.default offline_access`) — со всеми
правами, на которые есть согласие.

Ящики, вошедшие до 1.8.10, согласия на Graph не давали: «Настройки ящика →
Войти снова».

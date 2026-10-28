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

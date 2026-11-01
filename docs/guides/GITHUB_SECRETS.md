# Секреты GitHub для сборок релиза

Сборки в GitHub Actions (`.github/workflows/ci.yml`) делаются из
репозитория, где нет ни настроек входа и серверов (`config/dart_defines.json`),
ни ключа подписи Android (`android/key.properties`, `*.jks`) — они только у
вас. Без секретов сборка с GitHub собирается, но вход через OAuth (Gmail,
Яндекс, Mail.ru, Outlook), сигналы сервера и BIMI в ней не работают, а APK
подписан отладочным ключом.

## Куда вписывать

GitHub → репозиторий **oedante/OgnelissMail** → **Settings → Secrets and
variables → Actions → New repository secret**. Имя — ровно как ниже, значение
— вставить и **Add secret**. После сохранения значение больше не видно (только
заменить); в сборки чужих форков секреты не попадают.

## Что вписывать

| Секрет | Значение | Откуда взять |
|---|---|---|
| `DART_DEFINES_JSON` | содержимое файла `config/dart_defines.json` целиком (JSON) | ваш файл, с которым вы собираете для магазинов |
| `ANDROID_KEYSTORE_BASE64` | ключ загрузки `.jks` в base64, одной строкой | см. ниже |
| `ANDROID_KEYSTORE_PASSWORD` | пароль хранилища ключей | `storePassword` в `android/key.properties` |
| `ANDROID_KEY_ALIAS` | имя ключа | `keyAlias` в `android/key.properties` |
| `ANDROID_KEY_PASSWORD` | пароль ключа | `keyPassword` в `android/key.properties` |

Ключ в base64:

- **macOS:** `base64 -i upload-keystore.jks | pbcopy` — строка уже в буфере обмена;
- **Linux:** `base64 -w0 upload-keystore.jks`;
- **Windows (PowerShell):**
  `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Clipboard`.

### Что должно быть в `DART_DEFINES_JSON`

Те же ключи, что в `config/dart_defines.example.json`, с вашими значениями:
`OAUTH_PROXY_URL`, `OAUTH_PROXY_KEY`, `SUPPORT_EMAIL`,
`GOOGLE_ANDROID_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_DESKTOP_CLIENT_ID`,
`GOOGLE_DESKTOP_CLIENT_SECRET`, `MS_CLIENT_ID`, `PUSH_RELAY_URL`,
`PUSH_WAKE_MODE`. С версии после 1.9.0 к ним добавляются (если вы
настроили Firebase — `ANDROID_PUSH_SETUP.md`): `FIREBASE_API_KEY`,
`FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` и, по желанию,
`PUSH_WAKE_ANDROID_PRIORITY`. Обновили `config/dart_defines.json` — обновите и
секрет.

## Чем сборки с GitHub отличаются от магазинных

- **Android.** APK с GitHub подписан вашим **ключом загрузки**. Если в Google
  Play включена подпись приложений Google (Play App Signing), Play
  переподписывает приложение своим ключом — APK с GitHub **не встанет поверх**
  версии из Google Play (и наоборот). Сборки с GitHub — для проверки и
  установки вручную; в Play по-прежнему загружается ваш App Bundle.
- **iOS и macOS** собираются без подписи (`--no-codesign`) — это проверка,
  что проект собирается; для App Store собирайте в Xcode из архива
  исходников. Сертификаты Apple в GitHub не нужны.
- **Windows и Linux** — без подписи кода.

## Проверка

GitHub → **Actions → CI/CD → Run workflow** (ветка `main`, «Собрать Android»).
В сводке сборки не должно быть предупреждений «Без DART_DEFINES_JSON» и «Без
ключа подписи».

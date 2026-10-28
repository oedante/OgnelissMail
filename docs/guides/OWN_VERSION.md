# Своя версия Ogneliss Mail

Код открыт по лицензии Apache 2.0 (`LICENSE`), поэтому любая организация
или разработчик может собрать и выпустить свою версию — например, для своих
сотрудников — без договора и без оплаты. Эта инструкция — о том, как
технически это сделать. Лицензионные условия — `docs/LICENSING.md`.

## 1. Условия лицензии и что не входит в репозиторий

Выпуская свою версию:

- приложите текст лицензии Apache 2.0 и сохраните файл `NOTICE` —
  приложение уже показывает оба в «Настройки → О приложении → Тексты
  лицензий», достаточно не удалять их из `pubspec.yaml` и `lib/main.dart`;
- пометьте изменённые файлы (например, комментарием и историей git);
- дайте версии своё название, значок и идентификатор — лицензия не даёт
  прав на название «Ogneliss» и значки (`TRADEMARKS.md`);
- **Exchange:** патентное обещание Microsoft для разработчиков открытого ПО
  не действует для коммерческого распространения (продажа, подписки,
  платные обновления, плата за подключение). Бесплатная версия для своих
  сотрудников — некоммерческое распространение; если собираетесь брать
  деньги за распространение — выясните лицензирование с Microsoft
  (`docs/LICENSING.md`, раздел 3).

В репозитории нет (у вас будет своё): ключей подписи Android (`*.jks`,
`key.properties`), файла с ключами входа (`config/dart_defines.json`, образец —
`config/dart_defines.example.json`), ключа APNs (`*.p8`), настроек серверов
(`.env`), учётных записей разработчика в Google Play и App Store. Серверы
входа и сигналов автора обслуживают только его сборки.

## 2. Что понадобится

- **Инструменты:** Flutter 3.38 или новее (Dart 3.10+), Android Studio с
  Android SDK и Java 17; для iOS — Mac с Xcode 16 или новее и CocoaPods.
- **Учётные записи разработчика** — на вашу организацию:
  - Android: Google Play Console. Для выпуска только своим сотрудникам —
    частное приложение в управляемом Google Play (Managed Google Play) или
    установка через вашу систему управления устройствами (MDM);
  - iOS: Apple Developer Program для организации. Для сотрудников — Custom App
    через Apple Business Manager (приложение видно только вашей организации)
    или Apple Developer Enterprise Program (внутреннее распространение, если
    организация к нему допущена).
- **Сервер с доменом и HTTPS** — только если нужны вход через аккаунты
  Google, Microsoft 365 / Outlook.com, Яндекса, Mail.ru (сервер входа) или
  сигналы проверки почты на iPhone в фоне (сервер сигналов). Если сотрудники
  подключают только Exchange по логину и паролю — серверы не нужны.

## 3. Название, идентификаторы и значок

Идентификатор вашей версии — например, `ru.company.mail`. Он должен быть
другим: идентификатор `com.ogneliss.mail` занят в магазинах, и две версии на
одном телефоне иначе будут мешать друг другу.

| Что | Где |
|---|---|
| Название на телефоне | `android/app/src/main/AndroidManifest.xml` (`android:label`); `ios/Runner/Info.plist` (`CFBundleDisplayName`, `CFBundleName`) |
| Названия виджетов | Android: строки `widget_*` в `android/app/src/main/res/values*/strings.xml`; iOS: `ios/OgnelissWidgets/*.lproj` |
| Идентификатор Android | `android/app/build.gradle.kts` (`namespace`, `applicationId`); пакет Kotlin — перенести каталог `android/app/src/main/kotlin/com/ogneliss/mail` и поправить строки `package`; `android/baselineprofile`; `packages/ogneliss_native_http/android` |
| Идентификатор iOS | `PRODUCT_BUNDLE_IDENTIFIER` в `ios/Runner.xcodeproj/project.pbxproj` (приложение, тесты, расширение виджетов) |
| Схема ссылок (вход, виджеты) | `com.ogneliss.mail://…` → своя: `AndroidManifest.xml` (фильтры `oauth` и `oauth2redirect`), `build.gradle.kts` (`appAuthRedirectScheme`), `ios/Runner/Info.plist` (`CFBundleURLTypes`), `lib/core/constants/app_constants.dart` (`googleRedirectUri`, `oauthProxyRedirect`), `lib/services/mail/oauth/oauth_proxy_flow.dart` (`kAppScheme`), `lib/services/mail/oauth/direct_oauth.dart` (`appScheme`), `ios/Runner/WidgetBridgePlugin.swift` и `AppDelegate.swift` (ссылки виджетов), настройки сервера входа (адрес возврата в приложение) |
| Группа приложений iOS (виджеты) | `group.com.ogneliss.mail`: `ios/Runner/WidgetBridgePlugin.swift`, `ios/OgnelissWidgets/OgnelissWidgets.swift`, файлы `*.entitlements` приложения и виджетов; на портале Apple — App Group с тем же именем |
| Учётная запись Android (контакты и календарь в телефоне) | `com.ogneliss.mail.account`: `android/app/src/main/res/xml/account_authenticator.xml`, `sync_calendar.xml`, `sync_contacts.xml` и та же строка в Kotlin (`PhoneAccountServices.kt`); подпись учётной записи в телефоне — `lib/services/device/phone_mirror_service.dart` («Ogneliss — …») |
| Константа пакета | `lib/core/constants/app_constants.dart` (`packageId`) |
| Значок приложения | `assets/icons/app_icon.png` → `dart run flutter_launcher_icons` (раздел `flutter_launcher_icons` в `pubspec.yaml`); значок виджетов и уведомлений Android — `android/app/src/main/res/drawable*` |
| Логотип в приложении | `assets/brand/` (экран входа, «О приложении», заставка) |
| Тексты с названием и контактами | `assets/l10n/<код>.xml` — все языки (поиск по слову «Ogneliss»; адрес поддержки — строки `faq_*`); инструмент — `tool/l10n/l10n.py`; вопросы и ответы — `lib/features/help/faq_content.dart` |
| Страница после входа | `lib/services/mail/oauth/direct_oauth.dart` (заголовок «Ogneliss Mail») |
| Календарь | `PRODID:-//Ogneliss//…` в `lib/services/mail/dav/ical_parser.dart` и `lib/services/calendar/itip_reply.dart` — по желанию |

Внутренние имена менять не нужно: каналы `ogneliss/…` между Dart и нативным
кодом, файлы базы и ключи настроек, служебные заголовки писем
`X-Ogneliss-Classification` и `X-Ogneliss-Handling` (гриф письма — их читают
и другие копии приложения), метки правил Sieve. Пользователь их не видит.

Проверка после переименования: поиск по проекту `com.ogneliss` и
`Ogneliss` (без учёта регистра) — оставшееся должно быть только в
комментариях, внутренних именах из абзаца выше и в `NOTICE`.

## 4. Документы вашей версии

- **Политика конфиденциальности и условия** — ваши: замените адреса
  `termsUrl`, `eulaUrl`, `privacyUrl`, `licensesUrl` и правообладателя в
  `lib/core/constants/app_constants.dart`. Образец — документы на
  https://ogneliss.ru/mail/ (четыре языка). Если запускаете сервер входа
  или сервер сигналов, опишите в политике, какие данные они обрабатывают
  (раздел 6 нашей политики — образец).
- **Открытые компоненты** — сохраните: тексты лицензий библиотек
  показываются в приложении («Настройки → О приложении → Тексты
  лицензий») и собираются автоматически; список основных — в
  `docs/LICENSING.md`.
- **Наименование «Ogneliss»** и наш значок в вашей версии не используются
  (`TRADEMARKS.md`).

## 5. Вход через аккаунты (по необходимости)

Сервер входа хранит секреты OAuth и обменивает код авторизации на токены
(почта через него не идёт). Ключи входа разработчика Ogneliss не передаются:
регистрируете свои приложения у провайдеров и разворачиваете свой сервер.

1. Зарегистрируйте приложения: Google Cloud (Gmail, Календарь, Контакты),
   Microsoft Entra ID (Microsoft 365, Outlook.com, Exchange Online), Яндекс
   OAuth, Mail.ru — адреса возврата на ваш сервер (`OAUTH_SETUP.md`).
   Для Gmail Google требует проверку приложения, а для доступа к почте —
   ещё и оценку безопасности (CASA): это недели и отдельные расходы. Если
   Gmail сотрудникам не нужен, Google можно не подключать.
2. Разверните `server/oauth-proxy` на своём домене
   (`OAUTH_PROXY_SETUP.md`, для Debian — `OAUTH_PROXY_DEBIAN.md`).
3. В `config/dart_defines.json` (образец — `config/dart_defines.example.json`)
   укажите свой `OAUTH_PROXY_URL` и идентификаторы клиентов.

## 6. Сигналы для iPhone (по необходимости)

Сервер сигналов будит приложение на iPhone для проверки почты в фоне
(содержимого писем в сигнале нет). Нужен ключ APNs вашей учётной записи Apple
и свой сервер: `server/push-relay/README.md`, `docs/guides/IOS_PUSH_SETUP.md`.
Адрес — `PUSH_RELAY_URL` в `config/dart_defines.json`. Без сервера приложение
проверяет почту в фоне так, как позволяет iOS.

## 7. Подпись и сборка

- **Android:** свой ключ загрузки (`scripts/create_upload_key.ps1` или
  `keytool`) и файл `android/key.properties` — как в
  `docs/guides/ANDROID_STUDIO.md` (раздел о подписи). Сборка:

  ```bash
  flutter clean && flutter pub get
  dart run build_runner build --delete-conflicting-outputs
  flutter build appbundle --release --dart-define-from-file=config/dart_defines.json
  ```

- **iOS:** на портале Apple — App ID приложения и расширения виджетов, App
  Group, возможности Push Notifications и Background Modes (если нужен сервер
  сигналов). Затем:

  ```bash
  scripts/build_ios.sh --prepare --team ВАШ_TEAM_ID
  scripts/build_ios.sh --upload
  ```

  Подробно — `docs/guides/BUILD_IOS.md`.

Перед первой сборкой — проверки без устройства: `flutter analyze`,
`flutter test`, `python3 scripts/check_structure.py`,
`python3 tool/dev/l10n_check.py`.

## 8. Выпуск для сотрудников

- **Android:** Play Console → «Расширенные настройки» → «Управляемый
  Google Play»: сделать приложение частным для вашей организации; или
  установка через MDM.
- **iOS:** App Store Connect → «Цены и доступность» → способ
  распространения «Частное» (Custom App) для вашей организации в Apple
  Business Manager; сотрудники получают приложение через ABM или MDM.
- **Exchange:** если включена проверка устройств ActiveSync (разрешённые
  клиенты), добавьте свою версию в разрешённые; строка клиента — в
  `lib/core/device/device_user_agent.dart`.

## 9. Обновления

Чтобы переносить новые версии без боли:

- подключите этот репозиторий как `upstream` и держите свои изменения
  отдельными коммитами поверх него: `git fetch upstream`, затем слияние в
  вашу ветку;
- по возможности меняйте только места из таблицы раздела 3 и свои файлы:
  чем меньше правок в общем коде, тем проще слияние;
- что изменилось в каждой версии — история коммитов и выпуски на GitHub.

## 10. Связь

Ошибки и предложения — GitHub Issues этого репозитория; уязвимости — по
`SECURITY.md`.

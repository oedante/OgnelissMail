# iPhone: push-уведомления для проверки почты в фоне — что сделать владельцу

Составлено 20.10.2026, обновлено 23.10.2026 (1.7.2: этап 1 — тихие сигналы —
готов: служба `server/push-relay`, приложение, политика). Зачем и почему именно
так — `docs/plan/IOS_BACKGROUND_DELIVERY.md`.

**Коротко, что сделать для этапа 1 (1.7.2):** п. 1.2 и 1.4 (портал Apple) →
п. 2.1 без Keychain Sharing (Xcode) → п. 3А (сервер) → TestFlight → п. 5.

## Как это будет работать

1. Сервер-«будильник» раз в 15 минут отправляет через Apple (APNs) пустое
   уведомление-сигнал. В нём нет ни писем, ни адресов — только «проверь почту».
2. На iPhone сигнал принимает **расширение уведомлений** (Notification Service
   Extension, отдельная маленькая программа внутри приложения). Оно само, с
   телефона, обращается к вашему почтовому серверу и за несколько секунд
   проверяет «Входящие».
3. Есть новые письма — показывает уведомление «отправитель — тема» (с учётом
   настроек: VIP, тихие часы, ящики). Нет — ничего не показывает. Чтобы можно
   было ничего не показывать, нужно **право фильтрации** от Apple (п. 1.3).
4. Расширение запускается на каждый такой сигнал — даже если приложение
   смахнули из переключателя. Пока права фильтрации нет, сервер шлёт тихие
   сигналы (iOS пропускает не больше 2–3 в час, без гарантий).

Сервер — свой на ogneliss.ru (хранит только токен установки) или тема FCM
(сервер не хранит ничего, токен у Google). Выбор не влияет на шаги 1–2;
отличается только шаг 3.

**Кто что делает.** Владелец — шаги ниже (портал Apple, Xcode, сервер,
политика). Код — расширение, регистрация в приложении, сервер, тексты для
политики и App Review — приходит в архиве проекта; шаги 2 и 3 выполняются,
когда в архиве появятся `ios/OgnelissNotifications/` и сервер.

## 1. Apple Developer — можно сделать сейчас

Сайт: developer.apple.com → **Account → Certificates, Identifiers & Profiles**.
Право фильтрации запрашивает только **Account Holder** (владелец учётной
записи разработчика — вы). Ответа Apple ждут неделями, поэтому п. 1.3 —
первым делом.

### 1.1. App ID расширения

**Identifiers → «+» → App IDs → App** → Continue:
- Description: `Ogneliss Mail Notifications`;
- Bundle ID: **Explicit**, `com.ogneliss.mail.notifications`;
- Capabilities: отметьте **App Groups** → Continue → Register.

Затем откройте этот App ID → App Groups → **Configure** → отметьте
`group.com.ogneliss.mail` (та же группа, что у виджетов) → Save.

### 1.2. Push у приложения

**Identifiers → `com.ogneliss.mail`** → вкладка Capabilities → отметьте
**Push Notifications** → Save. Сертификаты push (кнопка Configure рядом)
**не нужны** — используем ключ (п. 1.4).

### 1.3. Заявка на право фильтрации уведомлений

**Identifiers → `com.ogneliss.mail.notifications`** → вкладка **Capability
Requests** → найдите *Notification Service Extension filtering* (или похожее
название с «Notification… Filtering») → **Request**. Если вкладки нет —
форма по ссылке developer.apple.com/contact/request/notification-service.

Форма (20.10.2026) принимает четыре случая: мессенджеры со сквозным
шифрованием, оповещения о землетрясениях, образовательные платформы,
медицинские корпоративные приложения. Наш — первый: приложение шифрует письма
S/MIME (как Outlook), закрытые ключи и пароли ящиков — только на телефоне, и
сервер не может решить, показывать ли уведомление, не получив доступа к
ящику. Описывать всё как есть: не «мессенджер», а почта с S/MIME и сервером,
который ничего не знает.

Поля формы:
- **Имя, почта, организация** — подставляются из учётной записи.
- **URL магазина приложений** — пусто, пока приложения нет в App Store.
- **Идентификатор приложения (Apple ID)** — **число** из App Store Connect →
  Мои приложения → Ogneliss Mail → «Информация о приложении» → Apple ID
  (например, 67xxxxxxxx). Не Team ID, не Key ID и не префикс App ID. Если
  записи приложения в App Store Connect ещё нет — создайте её («+» → «Новое
  приложение», Bundle ID `com.ogneliss.mail`).
- **Идентификатор пакета расширения службы уведомлений** —
  `com.ogneliss.mail.notifications` (строка Bundle ID из п. 1.1, не
  10-символьный код из портала).
- **Вариант использования** — первый пункт («Обеспечивает сквозное шифрование
  сообщений и не может фильтровать уведомления на сервере…»).

**Почему существующие API не подходят:**

> Ogneliss Mail is an email client for Exchange ActiveSync, EWS and IMAP
> accounts that supports end-to-end encrypted email (S/MIME, compatible with
> Outlook). Mail credentials and S/MIME private keys never leave the device. Our servers
> never receive message content, email addresses or credentials.
>
> iOS gives a third-party mail app no reliable way to check the user's own mail
> server in the background: BGAppRefreshTask runs at the system's discretion,
> and background (content-available) pushes are limited to a few per hour and
> are not delivered after the app is force-quit. A Notification Service
> Extension runs for every alert push, so our relay sends a content-free alert
> push (mutable-content) at a fixed interval, and the extension checks the
> user's mail server directly from the device.
>
> The relay cannot filter these pushes on the server. It has no access to the
> mailbox and cannot decrypt S/MIME messages, so it cannot know whether new mail
> has arrived. Filtering on the server would require giving our server the
> user's mail credentials, which would break the encryption and privacy
> guarantees of the app. Only the device can check.

**Почему приложение не показывает видимое уведомление на каждый push:**

> The push is only a content-free wake-up signal. When the extension finds new
> messages, it always shows a visible notification with the sender and subject,
> following the notification settings the user chose in the app. When there is
> no new mail, there is nothing to tell the user: an empty notification every
> 15 minutes would be noise, so the extension passes empty content to suppress
> it. Notifications about new mail are never suppressed, and the extension does
> not hide any other content.

**Какие системные и сетевые ресурсы нужны расширению:**

> One short TLS connection from the device to the user's own mail server
> (Exchange ActiveSync or EWS over HTTPS, or IMAP over TLS) to check the inbox
> for messages newer than the last check and fetch only their headers (sender,
> subject). It reads the account credentials from the app's shared keychain and
> the last-check state from the shared App Group container. A typical run takes
> a few seconds and a few kilobytes of data and finishes well within the
> extension time limit. No location, Bluetooth, audio or other hardware, and no
> connection to our servers.

**Как часто запускается и что его запускает:**

> Only our relay's scheduled wake-up push triggers the extension: at most once
> every 15 minutes per device. The user can choose 15, 30 or 60 minutes or turn
> background checks off in the app settings. No other pushes are sent to the
> extension. The relay sets a collapse ID and a short expiration, so if the
> device is offline, pushes do not pile up — only the latest wake-up is
> delivered.

Статус: та же вкладка → кнопка **Status**. После одобрения: App ID
`com.ogneliss.mail.notifications` → вкладка **Capabilities** → включите
одобренную возможность → **Save**.

### 1.4. Ключ APNs (.p8)

**Keys → «+»**:
- Key Name: `Ogneliss Push Production`;
- отметьте **Apple Push Notifications service (APNs)** → **Configure**:
  Environment — **Production**, Key Restriction — **Team Scoped (All Topics)**
  (названия полей могут немного отличаться) → Save → Continue → **Register**.
- **Download** — файл `AuthKey_XXXXXXXXXX.p8` скачивается **один раз**,
  повторно его не дадут. Запишите **Key ID** (10 символов) и **Team ID**
  (правый верхний угол страницы или Membership details).

Production-ключ нужен для TestFlight и App Store. Для сборок, запущенных
прямо из Xcode (Debug), нужен второй ключ с Environment **Sandbox** — по
желанию; проверять можно и через TestFlight. В каждом окружении — не больше
двух ключей. Если ключ APNs «для обоих окружений» у вас уже есть, он тоже
подойдёт.

**Хранение.** `.p8` — секрет, как `key.properties` и `*.jks`: не в проект, не в
архив, не в почту. Копия — в менеджере паролей или на зашифрованном носителе.
При утечке — **Revoke** на той же странице и новый ключ.

## 2. Xcode — когда в архиве появится `ios/OgnelissNotifications/`

Откройте `ios/Runner.xcworkspace`. (`project.pbxproj` вы не получаете —
поэтому шаги руками, как для виджетов.)

### 2.1. Цель Runner → Signing & Capabilities

- **«+ Capability» → Push Notifications** (Xcode добавит `aps-environment` в
  `Runner.entitlements`);
- **Background Modes** (уже есть: fetch, processing) → дополнительно отметьте
  **Remote notifications**;
- **«+ Capability» → Keychain Sharing** → группа `com.ogneliss.mail.shared`.

### 2.2. Новая цель — расширение уведомлений

1. **File → New → Target… → Notification Service Extension** → Next:
   - Product Name: `OgnelissNotifications`;
   - Language: Swift; Embed in Application: **Runner** → Finish;
   - «Activate scheme?» → **Cancel**.
2. Удалите сгенерированные `NotificationService.swift` и `Info.plist`
   (**Move to Trash**) и перетащите в группу `OgnelissNotifications` файлы из
   `ios/OgnelissNotifications/` архива. Target — только
   **OgnelissNotifications**, «Copy items if needed» — не нужно.
3. **Runner (проект) → Info → Configurations**: для OgnelissNotifications в
   Debug, Release и Profile — `Notifications.xcconfig` (версия и номер сборки
   как у приложения, иначе App Store отклонит сборку).
4. Цель **OgnelissNotifications → Build Settings**:
   - iOS Deployment Target: **15.0**;
   - Info.plist File: `OgnelissNotifications/Info.plist`, Generate Info.plist
     File: **No**;
   - Marketing Version и Current Project Version — удалите значения (Delete);
   - Code Signing Entitlements:
     `OgnelissNotifications/OgnelissNotifications.entitlements`;
   - Bundle Identifier: `com.ogneliss.mail.notifications`.
5. **Signing & Capabilities** цели OgnelissNotifications: тот же Team;
   **App Groups** → `group.com.ogneliss.mail`; **Keychain Sharing** →
   `com.ogneliss.mail.shared` (как у Runner).
6. **Build Phases** цели OgnelissNotifications → Copy Bundle Resources: должен
   быть `PrivacyInfo.xcprivacy`.
7. Цель **Runner → Build Phases**: «Embed Foundation Extensions» (теперь там
   `OgnelissWidgets.appex` и `OgnelissNotifications.appex`) — **выше** «Thin
   Binary», иначе «Cycle inside Runner».

### 2.3. После одобрения права фильтрации

В архиве будет `OgnelissNotifications.entitlements` с ключом
`com.apple.developer.usernotifications.filtering`. Сначала включите
возможность у App ID (п. 1.3), затем соберите. Если Xcode пишет «Provisioning
profile doesn't include the …filtering entitlement»: проверьте, что
возможность включена у `com.ogneliss.mail.notifications`, и обновите профили
(**Xcode → Settings → Accounts → Download Manual Profiles**, или снимите и
снова поставьте «Automatically manage signing»).

## 3. Сервер — один из двух вариантов

### А. Свой «будильник» на ogneliss.ru — выбран (решение владельца 20.10.2026)

Служба `server/push-relay` (подробно — `server/push-relay/README.md`):
контейнер Docker рядом с OAuth-прокси за Nginx Proxy Manager, адрес
`https://www.ogneliss.ru/push` (он же вписан в приложение, `PUSH_RELAY_URL`).
Хранит только токен APNs (случайный, свой у каждой установки), окружение,
интервал и время последнего сигнала; журнала запросов с IP нет. Токен
удаляется, когда пользователь выключает функцию, когда Apple отвечает, что
приложение удалено, и сам — после 30 дней без обновления регистрации.

1. Скопируйте на сервер папку `server/push-relay` из архива и ключ из п. 1.4:
   ```bash
   scp -r server/push-relay root@СЕРВЕР:/root/
   scp AuthKey_XXXXXXXXXX.p8 root@СЕРВЕР:/root/
   ```
2. Установите (Team ID — Membership details на developer.apple.com):
   ```bash
   sudo bash /root/push-relay/install-push-relay.sh install \
        --team ABCDE12345 --key /root/AuthKey_XXXXXXXXXX.p8
   ```
   Служба ляжет в `/opt/mailserver/push-relay`, ключ приложения возьмётся из
   OAuth-прокси, а пробный сигнал Apple проверит ключ: нужна строка «ключ
   production принят Apple». Затем удалите `/root/AuthKey_…p8` (копия — в
   `/opt/mailserver/push-relay/keys`).
3. Nginx Proxy Manager: хост `ogneliss.ru` → Edit → **Advanced** → замените
   содержимое целиком на `site/nginx-landing.conf` из архива (новый раздел
   «Сигналы для iPhone»; прежнее содержимое сначала скопируйте) → Save.
4. Проверка: `sudo bash /root/push-relay/install-push-relay.sh check` — все
   строки ✓.

Ключ Sandbox (для сборок прямо из Xcode) — по желанию:
`install-push-relay.sh key --sandbox --key /root/AuthKey_YYYYYYYYYY.p8`.

### Б. Тема FCM (не выбран, для справки)

1. console.firebase.google.com → **Add project** (Google Analytics —
   **выключить**).
2. **Add app → iOS**: Bundle ID `com.ogneliss.mail` → скачать
   `GoogleService-Info.plist`.
3. **Project settings → Cloud Messaging → Apple app configuration → APNs
   Authentication Key → Upload**: `.p8`, Key ID, Team ID (для Production;
   Sandbox — если есть ключ).
4. Для Android: **Add app → Android**, `com.ogneliss.mail` →
   `google-services.json`.
5. **Project settings → Service accounts → Generate new private key** — JSON
   для отправки сообщений; он только на сервере.
6. `GoogleService-Info.plist`, `google-services.json` и JSON сервисного
   аккаунта — **не в архив проекта** (добавлю в исключения сборщика архива,
   как `dart_defines.json`).

Сервер в этом варианте — одна задача по расписанию: раз в 15 минут сообщение
в тему `wake`. Токены и подписки хранит Google.

## 4. Политика конфиденциальности и магазины

- **Политика на сайте — готово** (политика Mail 1.5 от 23.10.2026, раздел 6.2
  «Сигналы проверки почты на iPhone», и разделы 7–8): что такое токен
  уведомлений, где хранится, что ни адреса, ни пароли, ни письма на сервер не
  передаются, как выключить. Выложить сайт — `site/DEPLOY.md`.
- **App Store Connect → App Privacy**: перепроверить ответы. Токен не связан с
  личностью и не используется для отслеживания; для FCM — свериться с
  рекомендациями Firebase для анкеты Apple.
- **App Store Connect → версия → App Review Information → Notes**:
  > Background mail checks use content-free wake-up pushes from our relay
  > (it stores only the APNs device token). The Notification Service Extension
  > checks the user's own mail server directly from the device and shows a
  > notification only when new mail arrives. No mail content, addresses or
  > credentials are sent to our servers.
- **Google Play → Data safety** — только для варианта FCM (идентификаторы
  устройства, назначение — функциональность приложения).

## 5. Проверка

Этап 1 (тихие сигналы, 1.7.2):

1. Сборка через TestFlight (Production) или из Xcode (Sandbox — нужен ключ
   Sandbox или ключ «для обоих окружений»).
2. В приложении: **Настройки → Уведомления → Сигналы сервера (iPhone)** —
   включено по умолчанию; под переключателем «Зарегистрировано …». Если
   «Не удалось: iOS: …» — у цели Runner нет Push Notifications (п. 2.1);
   «… HTTP 401» — ключ приложения на сервере не совпадает со сборкой.
3. На сервере `install-push-relay.sh check` — «установок 1 (production 1 …)».
4. Сверните приложение (не смахивайте), подождите 20–40 минут. В настройках
   появится «Последний сигнал: …», в «Проверке почты» (точка состояния в
   шапке ленты) — «Последняя проверка в фоне: … · сигнал сервера», в пакете
   диагностики — строки «ФОН сигнал iOS». iOS вправе придерживать тихие
   сигналы (энергосбережение, низкий заряд, приложение давно не открывали).

Расширение уведомлений (этап 2):

1. Соберите через TestFlight (Production) или из Xcode с Sandbox-ключом.
2. Токен уведомлений для пробного сигнала: отладочная сборка из Xcode пишет
   его в журнал («Сигналы сервера (отладка): токен …», консоль Xcode);
   выпускаемые сборки токен не пишут.
3. Тестовый сигнал без сервера — **Push Notifications Console**:
   icloud.developer.apple.com/dashboard/notifications → вход учётной записью
   разработчика → Bundle ID `com.ogneliss.mail` → окружение как у сборки →
   Device token → тип **alert**, в теле `"mutable-content": 1` → Send. Там же —
   журнал доставки по токену.
4. Пришлите себе письмо, заблокируйте телефон, отправьте сигнал — должно
   прийти уведомление с темой письма. Без нового письма — после одобрения
   права ничего не появится.
5. Смахните приложение из переключателя и повторите п. 4 — должно работать
   так же.
6. На Mac: **Console.app** → устройство → фильтр `OgnelissNotifications` —
   строки расширения.

## Тест до одобрения Apple (этап 1)

Можно выпустить в тест без права фильтрации и без расширения уведомлений:
сервер шлёт **тихие** сигналы (content-available) не чаще 3 раз в час — так
рекомендует Apple, чаще iOS всё равно придерживает. Приложение просыпается,
проверяет почту и показывает уведомления, как при фоновом обновлении.

- Нужно от владельца: п. 1.2, 1.4; в Xcode — только **Push Notifications** и
  **Background Modes → Remote notifications** у Runner (п. 2.1 без Keychain
  Sharing; `UIBackgroundModes → remote-notification` в `Info.plist` уже
  есть); п. 3А (сервер); выложить сайт с политикой 1.5 (п. 4).
- Проверка (п. 5.3): в Push Notifications Console тип **background**,
  приоритет 5, тело `{"aps":{"content-available":1}}`.
- Ожидаемый эффект: дополнительные пробуждения к обычному фоновому
  обновлению; без гарантий, не после смахивания приложения и не у давно не
  открывавшегося приложения. Главная польза этапа — проверка всей цепочки
  (ключ, сервер, токены, политика) до расширения уведомлений.

## Порядок

1. Сейчас: п. 1.1–1.4 (заявка на право подана — ждём ответа Apple).
2. Выбор сервера: А (решено 20.10.2026).
3. Этап 1 (тихие сигналы, см. выше) — код в 1.7.2 → п. 2.1, 3А → TestFlight → п. 5.
4. Расширение уведомлений (код в архиве) → п. 2 → TestFlight → п. 5.
5. После одобрения права — п. 2.3, сервер переключается с тихих сигналов на
   обычные.

# Виджеты iPhone (WidgetKit)

Шесть виджетов: «Мой день», «Почта», «Календарь», «Календарь: неделя» (средний и большой), «Календарь: месяц» (большой), «Заметки» — те же, что на Android (на Android неделя и месяц — вкладки одного виджета календаря; на iPhone переключатель внутри виджета требует iOS 17, поэтому это отдельные виджеты). С 1.7.0 в «Календарь: месяц» на iOS 17 и новее день выбирается касанием, месяц — стрелками (AppIntents). Код уже в проекте:

- `ios/OgnelissWidgets/`: расширение виджетов (`OgnelissWidgets.swift`, `Info.plist`, `Widgets.xcconfig`, `PrivacyInfo.xcprivacy`, подписи на всех 27 языках приложения в `*.lproj/Localizable.strings`). Права виджетов `OgnelissWidgets.entitlements` в архиве лежат в `ios/xcode-base/OgnelissWidgets/` (распаковка поверх папки их не затирает); `scripts/build_ios.sh` (например, `--check`) сам кладёт копию в `ios/OgnelissWidgets/`, если её там нет;
- `ios/Runner/WidgetBridgePlugin.swift`: канал `ogneliss/widget` в приложении (уже подключён к цели Runner). Приложение кладёт JSON виджетов в App Group `group.com.ogneliss.mail` и обрабатывает нажатия (`com.ogneliss.mail://widget?t=…`).

Сама цель расширения в `project.pbxproj` не добавлена: её надёжнее создать в Xcode, чем править файл проекта вручную. Пока цели нет, приложение собирается и работает как раньше, просто без виджетов.

## Что заполнять

Ничего в `config/dart_defines.json` и никаких ключей: виджеты не обращаются к
серверам. Нужно только один раз в Xcode — цель расширения и общая группа
App Group `group.com.ogneliss.mail` у приложения и у виджетов (через неё
приложение передаёт виджетам письма, встречи и заметки). При автоматической
подписи группу и App ID `com.ogneliss.mail.widgets` на developer.apple.com
Xcode зарегистрирует сам. Эти настройки хранятся в `project.pbxproj` и
`Runner.entitlements`, которых нет в архиве, — новые версии их не затирают.

Android: настраивать ничего не нужно — виджеты уже в приложении. Mac:
виджетов пока нет.

## Подключение в Xcode (один раз, около 10 минут)

0. Один раз запустите `scripts/build_ios.sh --check` — он положит
   `OgnelissWidgets.entitlements` на место (см. выше).
1. Откройте `ios/Runner.xcworkspace`.
2. **File → New → Target… → Widget Extension.**
   - Product Name: `OgnelissWidgets`;
   - снимите все галочки «Include …» (Live Activity, Control, Configuration App Intent);
   - Embed in Application: **Runner**.

   На вопрос «Activate scheme?» ответьте **Cancel**, чтобы осталась схема Runner.
   **Xcode 16 и новее** (папка цели — «синхронизированная», файлы в ней
   попадают в цель сами): перед этим шагом закройте Xcode и переименуйте в
   Finder `ios/OgnelissWidgets` в `ios/OgnelissWidgets.src`, чтобы Xcode
   создал свою папку цели, не смешивая шаблон с нашими файлами. После
   создания цели закройте Xcode,
   удалите из новой `ios/OgnelissWidgets` все файлы шаблона (`*.swift`,
   `Assets.xcassets`, `Info.plist`), перенесите туда всё содержимое
   `ios/OgnelissWidgets.src` и удалите пустую `.src`. Откройте Xcode снова;
   выделите в группе `OgnelissWidgets` файлы `Info.plist`,
   `OgnelissWidgets.entitlements` и `Widgets.xcconfig` и в File inspector →
   Target Membership снимите галочку `OgnelissWidgets` (это настройки, а не
   ресурсы; иначе «Multiple commands produce …/Info.plist»). Шаг 3 тогда
   пропустите.
3. **Xcode 15 и старше:** Xcode создаст папку `OgnelissWidgets` со своими файлами. Удалите сгенерированные `OgnelissWidgets.swift`, `OgnelissWidgetsBundle.swift`, `Assets.xcassets` и `Info.plist` (**Move to Trash**). Затем перетащите в группу `OgnelissWidgets` файлы из `ios/OgnelissWidgets/` этого архива: `OgnelissWidgets.swift`, `Info.plist`, `OgnelissWidgets.entitlements`, `Widgets.xcconfig`, `PrivacyInfo.xcprivacy` (1.7.0) и папки `*.lproj`. При добавлении:
   - галочка Target — только **OgnelissWidgets**;
   - «Copy items if needed» не нужна, файлы уже на месте.
4. Проект **Runner → Info → Configurations**: для цели OgnelissWidgets в Debug, Release и Profile укажите файл `Widgets.xcconfig` (из папки `OgnelissWidgets`). Тогда версия и номер сборки расширения совпадут с приложением, иначе App Store отклонит сборку.
5. Цель **OgnelissWidgets → Build Settings**:
   - iOS Deployment Target: **15.0**;
   - Info.plist File: `OgnelissWidgets/Info.plist`; Generate Info.plist File: **No**;
   - Marketing Version и Current Project Version: удалите значения (Delete), чтобы действовали версии из `Widgets.xcconfig`;
   - Code Signing Entitlements: `OgnelissWidgets/OgnelissWidgets.entitlements`;
   - Bundle Identifier: `com.ogneliss.mail.widgets`.
5a. **1.7.0 — выбор дня в «Календарь: месяц» (iOS 17+).** Цель **OgnelissWidgets → Build Phases → Link Binary With Libraries → «+»** → `AppIntents.framework`, в столбце Status выберите **Optional**. Кнопки внутри виджета работают только с iOS 17, а приложение поддерживает iOS 15: без «Optional» расширение на iOS 15 не загрузится. Проверьте также, что `PrivacyInfo.xcprivacy` есть в **Build Phases → Copy Bundle Resources** цели OgnelissWidgets (если цель уже создана раньше — перетащите файл и отметьте только эту цель).
6. **Signing & Capabilities:**
   - у цели **Runner**: «+ Capability» → **App Groups** → отметить или создать `group.com.ogneliss.mail`;
   - у цели **OgnelissWidgets**: тот же Team и та же группа `group.com.ogneliss.mail`.

   При автоматической подписи Xcode сам зарегистрирует группу и обновит профили. При ручной подписи добавьте App Group к App ID `com.ogneliss.mail` и создайте App ID и профиль для `com.ogneliss.mail.widgets` на developer.apple.com.
7. Цель **Runner → Build Phases**: убедитесь, что фаза «Embed Foundation Extensions» с `OgnelissWidgets.appex` стоит **выше** фазы «Thin Binary» (иначе Flutter-сборка выдаёт «Cycle inside Runner»; если ошибки нет, ничего не трогайте).
8. Соберите: `flutter build ipa` или Archive в Xcode.

## Если что-то не так

- **«Provisioning profile "…" has app ID "com.ogneliss.mail", which does not
  match the bundle ID "com.ogneliss.mail.OgnelissWidgets"».** Цели виджетов
  достался профиль приложения, а профиль годится только для своего
  идентификатора. Цель **OgnelissWidgets → Signing & Capabilities**:
  - проще всего — **Automatically manage signing**, Team тот же: Xcode сам
    заведёт App ID и профиль виджетов и группу App Group;
  - если подписываете вручную: developer.apple.com → Identifiers → «+» →
    App ID `com.ogneliss.mail.widgets` (Bundle Identifier цели — такой же)
    с возможностью App Groups → `group.com.ogneliss.mail`; Profiles → «+» →
    App Store → этот App ID → скачать и открыть двойным щелчком; выбрать его
    в Provisioning Profile цели виджетов. У App ID `com.ogneliss.mail` тоже
    включите App Groups с той же группой и перевыпустите профиль приложения
    (`ogneliss_mail_appstore`): старый профиль группу не знает.
- **«OgnelissWidgetsExtension has conflicting provisioning settings …
  iPhone Distribution has been manually specified».** Цель виджетов (Xcode
  называет её `OgnelissWidgetsExtension` — это нормально) подписывается
  автоматически, а «iPhone Distribution» пришёл с уровня проекта. Цель →
  **Build Settings** → All и Levels → поиск «Code Signing Identity»: в
  столбце цели виджетов для Debug, Release и Profile (и строк «Any iOS SDK»)
  — **Apple Development**. Приложение это не затрагивает. При отправке в
  App Store (Archive → Distribute App → App Store Connect, подпись
  «Automatically manage signing») Xcode сам переподпишет виджеты
  распространительским сертификатом. С `Widgets.xcconfig` из архива 2.5.2 и
  новее значение уже задано (если файл выбран в Configurations, шаг 4).
- **«Your team has no devices from which to generate a provisioning
  profile» / «No profiles for '…OgnelissWidgets' were found».** Автоматической
  подписи для сборки нужен профиль разработчика, а его выпускают только на
  зарегистрированные устройства. Если приложение подписано вручную профилем
  App Store, подпишите так же и виджеты (устройства не нужны):
  1. developer.apple.com → Certificates, Identifiers & Profiles →
     Identifiers. Группы `group.com.ogneliss.mail` нет — «+» → App Groups →
     создать.
  2. «+» → App IDs → App: Bundle ID (Explicit) — тот же, что у цели виджетов
     в Xcode (лучше `com.ogneliss.mail.widgets`), отметить **App Groups** →
     Register; затем в нём App Groups → Configure → `group.com.ogneliss.mail`.
  3. App ID `com.ogneliss.mail`: включить App Groups с той же группой → Save.
  4. Profiles → «+» → Distribution → **App Store Connect** → App ID виджетов
     → тот же сертификат Distribution, что у приложения → имя, например
     `ogneliss_widgets_appstore` → Download, открыть двойным щелчком.
     Профиль приложения (`ogneliss_mail_appstore`) — Edit → Save → Download
     заново: после включения App Groups старый недействителен.
  5. Xcode, цель виджетов: Bundle Identifier — как в шаге 2; Signing &
     Capabilities → снять **Automatically manage signing** → Provisioning
     Profile (Release) — `ogneliss_widgets_appstore`; Build Settings → Code
     Signing Identity (Release) — та же, что у Runner (Apple Distribution /
     iPhone Distribution).
  6. Archive → Distribute App → App Store Connect → Manually manage
     signing — профили приложения и виджетов.

  Другой путь — автоматическая подпись: один раз подключить iPhone кабелем к
  Mac, выбрать его вверху Xcode как устройство для запуска и согласиться
  зарегистрировать (или добавить UDID в Devices на developer.apple.com).
- **Нет папки `ios/OgnelissWidgets.src`.** Её не бывает в архиве — это
  переименованная перед созданием цели `ios/OgnelissWidgets` (шаг 2,
  Xcode 16+). Если цель уже создана без переименования, оставьте как есть
  и проверьте папку `ios/OgnelissWidgets`: в ней должны быть наши файлы —
  `OgnelissWidgets.swift` (первая строка
  `// ios/OgnelissWidgets/OgnelissWidgets.swift`, около 1300 строк),
  `Info.plist`, `Widgets.xcconfig`, `PrivacyInfo.xcprivacy`,
  `OgnelissWidgets.entitlements`, `README.md` и папки `*.lproj`. Файлы
  шаблона Xcode (`OgnelissWidgetsBundle.swift`, `…LiveActivity.swift`,
  `…Control.swift`, `AppIntent.swift`, `Assets.xcassets`) удалите — иначе
  два `@main`. Если Xcode заменил наш `OgnelissWidgets.swift` или
  `Info.plist` своими — возьмите их из архива (`ios/OgnelissWidgets/`), а
  права — из `ios/xcode-base/OgnelissWidgets/`. Затем Target Membership
  (шаг 2) и шаги 4–7.

## Проверка

- «Календарь: месяц» на iOS 17 и новее: касание числа — встречи этого дня под сеткой (выбранный день — кольцом, сегодня — заливкой), стрелки «‹ ›» — соседний месяц (от прошлого до третьего вперёд). Через 6 часов виджет сам возвращается к сегодняшнему дню. На iOS 15–16 — текущий месяц и встречи сегодняшнего дня.

- Откройте приложение, дождитесь синхронизации и сверните его. Затем на рабочем столе: долгое нажатие → «+» → Ogneliss → выберите виджет.
- Нажатие на виджет открывает нужный экран: письмо, встречу, заметку, «Мой день», новое письмо или новую встречу.
- С PIN-кодом в приложении виджеты не показывают темы писем, названия встреч и текст заметок.
- iOS обновляет виджеты по своему бюджету (обычно раз в 15–60 минут). Приложение просит перерисовать их после каждой синхронизации и при сворачивании.

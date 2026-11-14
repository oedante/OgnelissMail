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

## Проверка

- «Календарь: месяц» на iOS 17 и новее: касание числа — встречи этого дня под сеткой (выбранный день — кольцом, сегодня — заливкой), стрелки «‹ ›» — соседний месяц (от прошлого до третьего вперёд). Через 6 часов виджет сам возвращается к сегодняшнему дню. На iOS 15–16 — текущий месяц и встречи сегодняшнего дня.

- Откройте приложение, дождитесь синхронизации и сверните его. Затем на рабочем столе: долгое нажатие → «+» → Ogneliss → выберите виджет.
- Нажатие на виджет открывает нужный экран: письмо, встречу, заметку, «Мой день», новое письмо или новую встречу.
- С PIN-кодом в приложении виджеты не показывают темы писем, названия встреч и текст заметок.
- iOS обновляет виджеты по своему бюджету (обычно раз в 15–60 минут). Приложение просит перерисовать их после каждой синхронизации и при сворачивании.

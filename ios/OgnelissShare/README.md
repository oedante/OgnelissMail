# «Поделиться» на iPhone и iPad (расширение OgnelissShare)

Жалоба пользователей iPhone 27.11.2026: «через „Поделиться“ файлом или
картинкой приложение не отображается». На iOS приложение появляется в
списке «Поделиться» только с расширением Share Extension — отдельной целью
в проекте Xcode. Код расширения готов (эта папка), приложение уже умеет
принимать то, что прислало расширение (receive_sharing_intent 1.9, через
Swift Package Manager — как в `scripts/build_ios.sh`): файлы, фото, видео,
текст, ссылку — открывается новое письмо с вложениями.

Файлы:
- `ShareViewController.swift` — расширение (сразу открывает приложение);
- `Info.plist` — что принимает: фото и видео (до 50 / 10), файлы (до 50),
  текст, ссылку; общая группа `group.com.ogneliss.mail` (та же, что у
  виджетов);
- `Share.xcconfig` — версия и сборка как у приложения;
- `OgnelissShare.entitlements` — права (App Group). В архиве лежит в
  `ios/xcode-base/OgnelissShare/`; `scripts/build_ios.sh` кладёт копию на
  место, если её нет.

В `ios/Runner/Info.plist` уже добавлены схема ссылки
`ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)` и ключ `AppGroupId` — через них
расширение открывает приложение. Пока цели нет, приложение собирается и
работает как раньше.

## Подключение в Xcode (один раз, около 10 минут)

0. Один раз запустите `scripts/build_ios.sh --check` — он положит
   `OgnelissShare.entitlements` на место.
1. Откройте `ios/Runner.xcworkspace`.
2. **File → New → Target… → Share Extension.** Product Name:
   `OgnelissShare`, Embed in Application: **Runner**. На вопрос «Activate
   scheme?» — **Cancel**.
   - **Xcode 16 и новее** (папка цели «синхронизированная»): как с
     виджетами — перед этим шагом закройте Xcode и переименуйте
     `ios/OgnelissShare` в `ios/OgnelissShare.src`; после создания цели
     закройте Xcode, удалите из новой `ios/OgnelissShare` файлы шаблона
     (`ShareViewController.swift`, `Base.lproj/MainInterface.storyboard`,
     `Info.plist`), перенесите туда содержимое `.src` и удалите её. Откройте
     Xcode; у файлов `Info.plist`, `OgnelissShare.entitlements`,
     `Share.xcconfig` и `README.md` в File inspector → Target Membership
     снимите галочку `OgnelissShare`.
   - **Xcode 15 и старше:** удалите сгенерированные
     `ShareViewController.swift`, `MainInterface.storyboard`, `Info.plist`
     (Move to Trash) и перетащите в группу `OgnelissShare` файлы этой папки
     (Target — только **OgnelissShare**, «Copy items» не нужна).
3. **Runner → Info → Configurations:** для цели OgnelissShare в Debug,
   Release и Profile — файл `Share.xcconfig`.
4. Цель **OgnelissShare → Build Settings:**
   - iOS Deployment Target: **15.0**;
   - Info.plist File: `OgnelissShare/Info.plist`; Generate Info.plist File:
     **No**;
   - Marketing Version и Current Project Version — удалите значения
     (Delete), чтобы действовали версии из `Share.xcconfig`;
   - Code Signing Entitlements: `OgnelissShare/OgnelissShare.entitlements`;
   - Bundle Identifier: **`com.ogneliss.mail.share`** (обязательно с
     префиксом приложения: по нему расширение находит приложение и группу).
5. Цель **OgnelissShare → General → Frameworks and Libraries → «+»** →
   библиотека **`receive-sharing-intent`** из пакета `receive_sharing_intent`
   (Swift Package Manager). Без неё — «No such module receive_sharing_intent».
6. **Signing & Capabilities** цели **OgnelissShare**: тот же Team, «+
   Capability» → **App Groups** → `group.com.ogneliss.mail` (у Runner она
   уже есть — с виджетами).
7. Цель **Runner → Build Phases:** перетащите **Embed Foundation
   Extensions** выше **Thin Binary** (иначе «Cycle inside Runner»).
8. Соберите и запустите на телефоне: в «Фото» → «Поделиться» и в «Файлах»
   → «Поделиться» появится **Ogneliss** (если нет — пролистайте ряд
   приложений до «Ещё» и включите). Выбранные фото и файлы откроются новым
   письмом с вложениями.

App ID `com.ogneliss.mail.share` на developer.apple.com при автоматической
подписи Xcode зарегистрирует сам. Эти настройки хранятся в
`project.pbxproj`, которого нет в архиве, — новые версии их не затирают.

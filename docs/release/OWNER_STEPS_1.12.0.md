# 1.12.0 — что сделать владельцу (04.11.2026)

1.12.0 (138) — это 1.11.0 (137) плюс предпросмотр документов и исправления
после проверки 04.11.2026 («Что нового» — `STORE_NOTES_1.12.0.md`).

**По сравнению с 1.11.0 у Apple, Google, на сервере и в Xcode ничего нового
делать не нужно.** Новых разрешений, прав и возможностей нет;
`project.pbxproj`, `Runner.entitlements` и `Info.plist` не менялись. Если
шаги из `OWNER_STEPS_1.11.0.md` ещё не сделаны, сначала сделайте их:

- ключ APNs и Firebase;
- сервер;
- политика на сайте;
- секреты GitHub;
- Push Notifications в Xcode.

Новое для вас:

- сборка с номером 138 (Android и iOS);
- тексты «Что нового»;
- проверка документов на телефоне (шаг 4);
- подтверждение патентных условий форматов (шаг 5).

Архив исходников — `ogneliss-mail-1.12.0+138.zip`:

- распаковывается поверх прежней папки проекта;
- настройки Xcode не затирает (файлы проекта Xcode лежат в `ios/xcode-base/`
  и берутся, только если своих нет);
- `config/dart_defines.json` в архиве нет (это секреты): берите прежний.

## 1. Android

**Вариант А — GitHub (без своей сборки).** Метка `v1.12.0` на `main`:

1. Откройте GitHub → **Releases** → **Draft a new release**.
2. **Choose a tag** → `v1.12.0` → Target `main` → **Publish release**.
   Или в терминале: `git tag v1.12.0 && git push origin v1.12.0`.

Сборка соберёт APK и App Bundle (`.aab`) и выложит страницу выпуска с «Что
нового». App Bundle — в артефакте `ogneliss-android-…` задачи сборки в
Actions. Подробно — `OWNER_STEPS_1.11.0.md`, шаг 1, «Выпуск — метка».

**Вариант Б — у себя** (Android Studio или терминал в папке проекта,
`config/dart_defines.json` и ключ подписи `android/key.properties` — как
раньше):

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build appbundle --release --dart-define-from-file=config/dart_defines.json
```

App Bundle — `build/app/outputs/bundle/release/app-release.aab`.

**Google Play Console:**

1. Ogneliss Mail → **Тестирование → Внутреннее тестирование** (или сразу
   **Рабочая версия**) → **Создать выпуск** → загрузить `.aab`.
2. «Что нового» — блок «Google Play — все 27 языков» из
   `STORE_NOTES_1.12.0.md`: скопировать целиком, от `<ru-RU>` до последнего
   `</ja-JP>`, в одно поле.
3. Рабочая версия — поэтапно, сначала 10–20 %.

## 2. iPhone и iPad: сборка на Mac и TestFlight

Нужен Mac с Xcode (последняя версия из App Store), Flutter 3.38 или новее и
CocoaPods. Окружение один раз — `guides/BUILD_IOS.md`, вариант А, шаг 1.

### 2.1. Папка проекта

1. Распакуйте `ogneliss-mail-1.12.0+138.zip` **поверх** прежней папки
   `ogneliss-mail` (Finder: «Заменить», или в Терминале
   `unzip -o ogneliss-mail-1.12.0+138.zip -d ~/` при распаковке в домашнюю
   папку).
2. Проверьте, что на месте `config/dart_defines.json` — тот же файл, что
   для Android. Новая папка — скопируйте его с компьютера, где собирали
   раньше.

### 2.2. Сборка

В Терминале:

```bash
cd ~/ogneliss-mail
chmod +x scripts/*.sh
scripts/build_ios.sh --check      # Xcode, Flutter, CocoaPods
scripts/build_ios.sh              # → build/ios/ipa/*.ipa
```

Скрипт сам выполнит `flutter pub get`, сгенерирует код базы
(`build_runner`) и `pod install`. Подпись — командой, которую вы указали
раньше (`--team`). Её настройки хранятся вне проекта
(`~/.ogneliss/ios_signing.xcconfig`), новый архив их не трогает. Первый
раз на этом Mac: `scripts/build_ios.sh --team ABCDE12345`; Team ID — на
developer.apple.com → Membership.

Номер сборки 138 и версия 1.12.0 берутся из `pubspec.yaml` сами.

### 2.3. Отправка в TestFlight — один из способов

- **Transporter** (бесплатное приложение Apple из Mac App Store): войти
  своим Apple ID → перетащить `build/ios/ipa/Ogneliss Mail.ipa` (имя файла
  может отличаться) → **Deliver**.
- **Xcode:** **Window → Organizer** → **Archives** → архив 1.12.0 (138) →
  **Distribute App** → **App Store Connect** → **Upload**. Архив —
  `build/ios/archive/Runner.xcarchive`, если в Organizer его нет: открыть
  его двойным щелчком.
- **Из Терминала** с ключом App Store Connect API (если он у вас есть):
  ```bash
  ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
    scripts/build_ios.sh --upload
  ```
  Файл ключа — `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`.

Если сборка или подпись не проходит — таблица «Если не собирается» в
`guides/BUILD_IOS.md`.

### 2.4. App Store Connect

1. Через 10–30 минут сборка 138 появится в **TestFlight** (статус
   «Обработка» → «Готово к тестированию»). На вопрос о шифровании —
   как раньше (`store/APP_STORE.md`, §6).
2. **TestFlight → группа открытого тестирования** (External Testing, из
   неё работает ссылка на сайте) → **«+» Сборки** → 138. Поле «Что
   тестировать» — например:
   `Документы во вложениях (DOCX, XLSX, PPTX, ODT, ODS, ODP), шапки цитат на
   языке приложения, перевод писем.`
   Apple проверяет сборку для внешних тестировщиков, обычно до суток.
3. Для выпуска в App Store: **Распространение → iOS-приложение → «+»
   Версия** → `1.12.0`. Если там ещё неотправленная 1.11.0 — просто
   поменяйте номер на 1.12.0. Затем выберите сборку 138.
4. «Что нового в этой версии» — блоки `<ru-RU>`, `<en-US>`, `<de-DE>`,
   `<fr-FR>` из раздела «App Store» файла `STORE_NOTES_1.12.0.md`, каждый —
   в свою локализацию (без строк с тегами).
5. Notes, демо-ящик и видео для проверяющих — `APP_REVIEW_NOTES.md`.

## 3. Mac (если выпускаете приложение для Mac)

Приложение для Mac собирается из той же папки на Mac
(`guides/BUILD_ALL_PLATFORMS.md`, раздел 3, способ Б). Папку `macos/`
скрипт создаёт у вас один раз, новый архив её не затирает:

```bash
scripts/build_macos.sh --setup     # только первый раз
scripts/build_macos.sh             # release-сборка
open macos/Runner.xcworkspace
```

В Xcode: **Product → Archive** → **Distribute App** → **App Store
Connect** → **Upload**. Сборка появится в TestFlight на вкладке **macOS**
той же карточки приложения. Платформу macOS в App Store Connect один раз
добавляют кнопкой **«+»** в карточке приложения.

## 4. Проверить на телефоне (TestFlight и внутреннее тестирование)

Документы удобно прислать себе письмом. Образцы есть в архиве в
`test/fixtures/office/`: `text_sample.docx`, `sheet_sample.xlsx`,
`slides.pptx`, `text_sample.odt`, `sheet_sample.ods`, `slides.odp`,
`sheet_cp1251.csv`.

1. **Android:**
   - DOCX открывается текстом;
   - XLSX — сеткой (листы внизу, касание ячейки показывает её текст
     сверху, масштаб двумя пальцами);
   - PPTX — слайдами, касание — во весь экран;
   - CSV из русского Excel — таблицей с русскими буквами.
2. **iPhone:**
   - DOCX, XLSX, PPTX открывает Просмотр iOS, как раньше;
   - ODT, ODS, ODP — само приложение (раньше было «Поделиться»).
3. **Настройки → Почта → Просмотр документов:**
   - выключите «Таблицы» — XLSX откроется своей программой;
   - выключите «CSV таблицей» — CSV откроется текстом.
4. **Документ с паролем** (XLSX с паролем на открытие) — строка «Документ
   защищён паролем» и кнопка другого приложения.
5. **Пересланное письмо Outlook** с английской шапкой: «От:», «Отправлено:
   четверг, 22 октября 2026 г. 14:48», «Кому:», «Копия:», «Тема:».
6. **Перевод:**
   - русское письмо с подписью на двух языках — без плашки «Перевести»;
   - английское письмо — с плашкой «Язык письма: английский».
7. **Календарь:** встреча 23:30–00:00 → включить «Весь день» → событие на
   один день.

## 5. Патентные условия форматов

`LICENSING.md`, раздел 6:

- Office Open XML, OpenDocument и RTF — в списке Microsoft Open
  Specification Promise. В отличие от обещания для Exchange ActiveSync, в
  нём нет условия о некоммерческом распространении.
- Для ODF есть ещё обещание Sun и режим OASIS без отчислений.

Из облачного сеанса страницы Microsoft и OASIS не открылись, цитаты сверены
по выдержкам поисковика. Откройте по ссылкам из раздела 6:

1. страницу OSP — проверьте, что в списке есть Office Open XML, OpenDocument
   и RTF;
2. заявление Sun.

Если всё так — ничего менять не нужно; если нет — напишите, обсудим до
выпуска.

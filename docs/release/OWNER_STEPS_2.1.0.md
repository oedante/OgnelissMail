# 2.1.0 — что сделать владельцу (08.11.2026)

2.1.0 (145) — это 2.0.0 (144) с исправленной сборкой (PR #59); в
приложении нового нет. «Что нового» — `STORE_NOTES_2.1.0.md` (тексты те же,
что у 2.0.0).

**Если шаги 2.0.0 ещё не сделаны — сначала они** (`OWNER_STEPS_2.0.0.md`):
в Play Console декларация службы переднего плана «Особое использование»
(Special use) вместо «Синхронизации данных» — без неё Google сборку не
примет. У Apple нового нет: `project.pbxproj`, `Runner.entitlements`,
`Info.plist` не менялись, в Xcode включать ничего не нужно. Секреты GitHub
и сервер — без изменений.

## Сборка

Архив `ogneliss-mail-2.1.0+145.zip` распаковать поверх папки проекта.

- **Android** (Windows, терминал Android Studio): `build_android.bat` —
  `build\out\ogneliss-mail-2.1.0+145.aab` (Google Play) и `.apk`. Скрипт сам
  обновит пакеты до версий сборки на GitHub (`flutter pub upgrade`) — это и
  чинит ошибку `writeRange` в `zip_view.dart`. Без `android\key.properties`
  сборка подписывается отладочным ключом (Google Play её не примет).
- **iPhone и iPad** (Mac): `scripts/build_ios.sh --upload` — IPA и выгрузка
  в TestFlight; с Windows — `scripts\ios_remote_build.ps1 -Upload`.
  Подробно — `docs/guides/TESTFLIGHT.md`.
- Сообщения «[SEVERE] RustBuilder: Failed to find lib.name …» при сборке —
  не ошибка: сборка продолжается.

## Выпуск на GitHub

Выпуск собирается по метке `v2.1.0` (метки без «v» сборку не запускают):
APK, iOS и macOS без подписи, Windows, Linux и SHA256SUMS — в «Assets»
выпуска, текст — «Что нового» из `STORE_NOTES_2.1.0.md`.

## Проверка на телефоне

Как у 2.0.0 (`OWNER_STEPS_2.0.0.md`, раздел «Проверка на телефоне»):
виджеты, фоновая работа, PIN. Дополнительно — вложение-архив: открыть
.zip из письма (список файлов), открыть файл из архива.

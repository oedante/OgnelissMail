# Скрипты сборки Ogneliss

> **Windows — проще всего:** `build_windows.bat` в корне проекта
> (обёртка над `scripts/build_windows.ps1`). Подробности —
> [`docs/guides/BUILD_WINDOWS.md`](../docs/guides/BUILD_WINDOWS.md).

Подготовка окружения перед первой компиляцией.

## Linux / macOS
```bash
chmod +x scripts/setup.sh
./scripts/setup.sh                 # полная настройка
./scripts/setup.sh --reset-db      # + пересоздать сгенерированный код БД
./scripts/setup.sh --clean         # + flutter clean
./scripts/setup.sh --clean-logs      # + удалить *.log и logs/
./scripts/setup.sh --icons-only    # только иконки (вкл. трей)
./scripts/setup.sh --no-doctor     # пропустить flutter doctor
./scripts/setup.sh --platforms=android,web,linux
# по умолчанию создаются все платформы: android,ios,web,windows,macos,linux
```

## Windows (PowerShell)
```powershell
# при необходимости разрешить запуск скриптов в текущей сессии:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\setup.ps1
.\scripts\setup.ps1 -ResetDb
.\scripts\setup.ps1 -Clean
.\scripts\setup.ps1 -IconsOnly
.\scripts\setup.ps1 -Platforms "windows,web"
```

## Что делает скрипт
1. Проверяет наличие Flutter/Dart в PATH (и `flutter doctor`).
2. Включает desktop-поддержку для текущей ОС.
3. Создаёт недостающие платформенные папки (`flutter create . --platforms=…`),
   не затрагивая `lib/`.
4. `flutter pub get` — зависимости.
5. `build_runner` — генерация кода БД (drift). С `--reset-db` сначала удаляет
   сгенерированные `*.g.dart`/`*.drift.dart` и локальную dev-базу.
6. `flutter_launcher_icons` — иконки приложения из `assets/icons/app_icon.png`.
7. Создаёт служебные директории.

## После скрипта
- Проставьте OAuth `clientId` в `lib/core/constants/app_constants.dart`.
- Примените нативные сниппеты из `OAUTH_SETUP.md` (если создавались новые
  платформенные папки): Gradle `manifestPlaceholders`, iOS `Info.plist`.
- Запуск: `flutter run -d windows|macos|linux|chrome` или на устройстве.

> Примечание: рабочая база данных создаётся на устройстве в каталоге приложения
> (`mail_app.db`) и пересоздаётся миграциями при запуске; скрипт её на
> устройстве не трогает — `--reset-db` чистит только генерируемый код и dev-копии.

## Сборка приложения (шаги 9–10)

Скрипт не только готовит окружение, но и **собирает** приложение, подставляя
секреты как `--dart-define` (в исходниках их нет).

```bash
cp .env.build.example .env.build     # один раз: OAUTH_PROXY_URL, OAUTH_PROXY_KEY
./setup.sh --build=apk               # настройка + компиляция
```

| Цель | Результат |
|---|---|
| `apk` | `build/app/outputs/flutter-apk/app-release.apk` |
| `appbundle` | `build/app/outputs/bundle/release/app-release.aab` |
| `windows` | `build/windows/x64/runner/Release/` |
| `web` | `build/web/` |

`.env.build` в `.gitignore`. Ключ прокси — `PROXY_API_KEY` из
`/opt/mailserver/oauth-proxy/.env` на сервере.

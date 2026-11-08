# Как участвовать в Ogneliss Mail

Спасибо, что помогаете. Ниже — как собрать проект, что проверить перед
изменением и какие правила проекта обязательны. Правила для ИИ-помощника —
[CLAUDE.md](CLAUDE.md), они же действуют для людей.

## Сборка и проверка

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # код базы (drift)
flutter analyze
flutter test                                               # ~1700 тестов
```

- Flutter — версия из `.github/workflows/ci.yml` (сейчас 3.47.x).
- Ядро перетаскивания вложений собирается из исходников на Rust: нужен
  rustup (`docs/release/OWNER_STEPS_1.15.0.md`, шаг 1).
- Сборки по платформам — `docs/guides/BUILD_ALL_PLATFORMS.md`,
  `BUILD_IOS.md`, `BUILD_WINDOWS.md`; ключи сборки (OAuth, Firebase) —
  `config/dart_defines.example.json` и `docs/guides/GITHUB_SECRETS.md`.
- Серверные части (`server/oauth-proxy`, `server/push-relay`,
  `server/weather-proxy`) — Node без зависимостей, тесты: `npm test` в
  папке службы.
- Снимки экранов для проверки вида: `flutter test tool/shots --update-goldens`
  (результат — `tool/shots/out/*.png`).

CI (GitHub Actions) на каждый PR: анализ, тесты, проверка лицензий и
уязвимостей зависимостей; сборки Android, iOS, компьютеров и проверка на
эмуляторе Android — по запуску вручную.

## Правила проекта

1. **Новая зависимость — только после проверки лицензии и условий**
   (пакет, библиотека, шрифт, значки, внешний сервис). Платное,
   GPL/LGPL/AGPL, «только некоммерческое», патентные условия — сначала
   обсудить с владельцем. Бесплатное — текст лицензии в приложении
   («Настройки → О приложении → Тексты лицензий») и строка в
   [docs/LICENSING.md](docs/LICENSING.md), раздел 2.
2. **Ошибки пользователю — только критические** (нужны его действия или
   риск потерять данные), остальное — повтор или пропуск и запись в журнал:
   [docs/guides/ERRORS.md](docs/guides/ERRORS.md).
3. **Данные людей — не наружу.** Внешние сервисы — через сервер Ogneliss
   (пример — погода, `server/weather-proxy`); в журнал — без паролей,
   токенов, текста писем и адресов (`AppLogger.mask`).
4. **Если ogneliss.ru недоступен**, почта работает:
   [docs/guides/SERVER_DOWN.md](docs/guides/SERVER_DOWN.md). Новая служба на
   сервере — с описанием поведения при его недоступности.
5. **Строки интерфейса — на 27 языках** (`assets/l10n/*.xml`), через
   `l10n.tr('ключ')`; без строк, вшитых в код.
6. **Версию** (`pubspec.yaml`) и **файлы проекта Xcode**
   (`project.pbxproj`, `Runner.entitlements`) не менять: это делает
   владелец.
7. Комментарии и документы — по-русски, понятно человеку без контекста:
   что и почему (с датой и поводом), а не пересказ кода.

## Ошибки безопасности

Не в открытых задачах — по адресу из [SECURITY.md](SECURITY.md).

## Лицензия

Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)); товарные знаки —
[TRADEMARKS.md](TRADEMARKS.md). Присылая изменения, вы соглашаетесь
распространять их на тех же условиях.

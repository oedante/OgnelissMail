# 2.5.3 — что сделать владельцу (14.11.2026)

2.5.3 (155) — решение владельца 14.11.2026: 2.5.2 (выложена в TestFlight,
номер 154 занят) и исправления того же дня — письма IMAP и поиск по дате,
версия виджетов iPhone для App Store. «Что нового» — от опубликованной
2.4.0: `STORE_NOTES_2.5.3.md`.

| | Нужно? |
|---|---|
| Android, Windows | собрать как обычно (номер сборки 155) |
| Xcode iPhone, цель виджетов | один раз — раздел 1 (версия виджетов) |
| Mac | как 2.5.2 (`OWNER_STEPS_2.5.2.md`, раздел 3) |
| Сервер, сайт, зависимости, база | не менялись |

## 1. iPhone: версия виджетов (предупреждение TestFlight 90473)

У цели виджетов остались версии Xcode (1.0 и 1) вместо версии приложения.
Один раз:

0. Удалить файлы шаблона, которые Xcode создал вместе с целью (второй
   `@main` — ошибка сборки; `scripts/build_ios.sh` теперь сам называет их и
   останавливается):

   ```bash
   rm -f ios/OgnelissWidgets/OgnelissWidgetsBundle.swift ios/OgnelissWidgets/OgnelissWidgetsControl.swift ios/OgnelissWidgets/OgnelissWidgetsLiveActivity.swift ios/OgnelissWidgets/AppIntent.swift
   ```

   В Xcode они пропадут из папки OgnelissWidgets сами (папка
   синхронизируется). Ошибки «widgetURL» в `OgnelissWidgets.swift`
   исправлены в коде.
1. Проект **Runner → Info → Configurations**: в Debug, Release и Profile для
   строки **OgnelissWidgetsExtension** — **Widgets** (`Widgets.xcconfig`).
2. Цель **OgnelissWidgetsExtension → Build Settings** (All, Levels):
   «Marketing Version» — выделить строку, **Delete** (станет
   `$(FLUTTER_BUILD_NAME)`); то же для «Current Project Version» (станет
   `$(FLUTTER_BUILD_NUMBER)`).
3. Product → Clean Build Folder, затем `scripts/build_ios.sh --upload` или
   Archive. В TestFlight предупреждения 90473 быть не должно. Проверка в
   архиве: Runner.app → PlugIns → OgnelissWidgetsExtension.appex →
   Info.plist — 2.5.3 и 155.

Если **Widgets** нет в списке Configurations — вписать 2.5.3 и 155 в
Marketing Version и Current Project Version цели вручную (и менять в каждой
версии). Подробно — `ios/OgnelissWidgets/README.md`, «Если что-то не так».

## 2. Проверить

1. **Лента Gmail или Яндекса** — после первой синхронизации письма идут
   строго по времени получения; в журнале — «IMAP …: даты писем по времени
   прихода — исправлено N» (один раз на папку).
2. **Поиск** — например, по фамилии частого собеседника при «Сначала
   новые»: сверху самые свежие письма, заголовки дней не повторяются.
   «Сначала старые» в меню сортировки — наоборот.
3. **Mac** — как в 2.5.2: «Расширенные настройки → Графика» —
   «Автоматически · Сейчас: Skia» на Mac с Intel.

## 3. Выпуск и магазины

- Метка `v2.5.3` на main (коммит слияния PR с этим файлом).
- App Store Connect: версия macOS — блок «App Store — Mac»; iOS — «iPhone и
  iPad» (строку про виджеты — только если они в сборке). Google Play — блок
  «все 27 языков».

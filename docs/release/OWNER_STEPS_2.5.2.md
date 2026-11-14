# 2.5.2 — что сделать владельцу (14.11.2026)

2.5.2 (154) — решение владельца 14.11.2026: 2.5.1 и исправления по сборке на
Mac с Intel (Flutter 3.47.7, Xcode 26.5) — выбор движка рисования на Mac, сборка iPhone с
Swift Package Manager, инструкция виджетов iPhone. Список изменений и
тексты для магазинов — `STORE_NOTES_2.5.2.md`.

| | Нужно? |
|---|---|
| Android, Windows | собрать как обычно (номер сборки 154); изменения — для Mac |
| Xcode iPhone: `project.pbxproj`, `Runner.entitlements` | только если подключаете виджеты — раздел 2 |
| Сервер, сайт, зависимости, база | не менялись |

## 1. Перед сборкой на Mac

```bash
flutter upgrade
```

На GitHub собирается свежий stable; у вас был 3.47.7. Swift Package Manager
переключать не нужно: `scripts/build_ios.sh` включает его сам,
`scripts/build_macos.sh` — выключает.

## 2. iPhone

Без виджетов — как обычно: `scripts/build_ios.sh --upload`.

С виджетами — один раз в Xcode, по `ios/OgnelissWidgets/README.md`
(раздел «Если что-то не так» — все ошибки, которые уже встречались):

1. Подпись: зарегистрированных устройств нет — у **обеих** целей ручная
   подпись профилями App Store: `ogneliss_mail_appstore` (перевыпустить
   после включения App Groups) и `ogneliss_widgets_appstore` для App ID
   `com.ogneliss.mail.widgets`.
2. Цель **Runner → Build Phases**: «Embed Foundation Extensions» — сразу
   под «Copy Bundle Resources», выше «Embed Frameworks», «Thin Binary» и
   «[CP] Embed Pods Frameworks» (иначе «Cycle inside Runner»). Затем
   Product → Clean Build Folder.
3. Archive → Distribute App → App Store Connect → Manually manage signing.

## 3. Mac

```bash
scripts/build_macos.sh --run
```

Скрипт кладёт новое окно Mac (`MainFlutterWindow.swift`) и `FLTEnableImpeller
= false` в `Info.plist` (запасной вариант). Проверить:

1. «Настройки → Расширенные настройки → Графика» — «Автоматически · Сейчас:
   Skia» (на Mac с Intel). Названия языков в «Общие → Язык» читаются,
   «Черновики», «Спам», «Корзина» — без шума вместо букв, лента не дёргается.
2. Для сравнения — «Новый движок (Impeller)» → «Перезапустить»: приложение
   откроется заново с Impeller (на Intel — снова шум). Верните
   «Автоматически».
3. На Mac с Apple Silicon (если есть): «Автоматически · Сейчас: Impeller».

Затем `scripts/build_macos.sh --upload`.

## 4. Выпуск и магазины

- Метка `v2.5.2` на main (коммит слияния PR с этим файлом).
- App Store Connect: версия macOS — блок «App Store — Mac»; версия iOS —
  блок «iPhone и iPad» (строку про виджеты — только если они в сборке).
- Google Play — блок «все 27 языков».

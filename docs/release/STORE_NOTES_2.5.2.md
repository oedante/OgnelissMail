# «Что нового» — 2.5.2 (154)

2.5.1 и исправления 14.11.2026 по сборке владельца на Mac с Intel
(Flutter 3.47.7, Xcode 26.5). Решение владельца 14.11.2026 — 2.5.2. Шаги
владельца — `OWNER_STEPS_2.5.2.md`.

## Сделано

- **Mac: выбор движка рисования — как на Android** («Настройки → Расширенные
  настройки → Графика»): «Автоматически» — прежний движок Skia на Mac с
  Intel и Impeller на Apple Silicon, «Совместимость (Skia)», «Новый движок
  (Impeller)»; кнопка «Перезапустить». Во Flutter 3.47 Impeller и новая
  отрисовка текста включены на Mac по умолчанию; на Mac с Intel часть букв
  рассыпалась в шум («Почт▒», «▒ерновики», список языков почти нечитаем),
  интерфейс дёргался. Flutter решает по ключу `FLTEnableImpeller` из
  `Info.plist`; приложение подменяет ответ на него при запуске (GraphicsBridge
  в `tool/desktop/macos/MainFlutterWindow.swift`). `false` в `Info.plist`
  (сборка пишет сама) — запасной вариант. В журнале и диагностике — чем
  рисует и видеокарта.
- **Сборка для iPhone:** `scripts/build_ios.sh` сам включает Swift Package
  Manager (новые версии `receive_sharing_intent` собираются только так),
  `scripts/build_macos.sh` — выключает (плагины Mac — через CocoaPods, как на
  GitHub). Настройка Flutter общая — переключать вручную не нужно.
- **Виджеты iPhone — инструкция** (`ios/OgnelissWidgets/README.md`): что
  заполнять (ничего, кроме цели и App Group), где права виджетов в архиве,
  шаги для Xcode 16+, подпись без зарегистрированных устройств (ручные
  профили App Store у обеих целей), «Cycle inside Runner» — порядок фаз.

Код приложения для iPhone, Android и Windows с 2.5.1 не менялся. Манифест
Android, `Info.plist` iPhone, зависимости и схема базы (30) — без изменений.

## Кратко (RU / EN)

**RU.** На Mac с процессором Intel текст больше не рассыпается, интерфейс
не дёргается; движок рисования можно выбрать в настройках. Исправления и
улучшения стабильности.

**EN.** On Intel-based Macs, text no longer gets garbled and the interface
no longer stutters; the rendering engine can be chosen in Settings. Bug
fixes and stability improvements.

## App Store — Mac (ru, en, de, fr)

Версия macOS в App Store Connect, поле «Что нового в этой версии».

```
<ru-RU>
• На Mac с процессором Intel текст больше не рассыпается, интерфейс не дёргается
• Выбор движка рисования: Настройки → Расширенные настройки → Графика
• Исправления и улучшения стабильности
</ru-RU>
<en-US>
• On Intel-based Macs, text no longer gets garbled and the interface no longer stutters
• Choose the rendering engine: Settings → Advanced settings → Graphics
• Bug fixes and stability improvements
</en-US>
<de-DE>
• Auf Macs mit Intel-Prozessor wird Text nicht mehr verstümmelt und die Oberfläche ruckelt nicht mehr
• Grafik-Engine wählbar: Einstellungen → Erweiterte Einstellungen → Grafik
• Fehlerbehebungen und Stabilitätsverbesserungen
</de-DE>
<fr-FR>
• Sur les Mac à processeur Intel, le texte ne se brouille plus et l’interface ne saccade plus
• Choix du moteur de rendu : Réglages → Réglages avancés → Graphismes
• Corrections de bugs et amélioration de la stabilité
</fr-FR>
```

## App Store — iPhone и iPad (ru, en, de, fr)

Если цель виджетов в этой сборке подключена — первая строка про виджеты
(виджеты на iPhone выходят впервые); если нет — уберите её.

```
<ru-RU>
• Виджеты на экране «Домой»: «Мой день», почта, календарь, заметки
• Исправления и улучшения стабильности
</ru-RU>
<en-US>
• Home Screen widgets: My day, Mail, Calendar, Notes
• Bug fixes and stability improvements
</en-US>
<de-DE>
• Widgets für den Home-Bildschirm: Mein Tag, E-Mail, Kalender, Notizen
• Fehlerbehebungen und Stabilitätsverbesserungen
</de-DE>
<fr-FR>
• Widgets d’écran d’accueil : Ma journée, E-mail, Calendrier, Notes
• Corrections de bugs et amélioration de la stabilité
</fr-FR>
```

## Google Play — все 27 языков (одним полем)

```
<ru-RU>
• Исправления и улучшения стабильности
</ru-RU>
<en-US>
• Bug fixes and stability improvements
</en-US>
<de-DE>
• Fehlerbehebungen und Stabilitätsverbesserungen
</de-DE>
<fr-FR>
• Corrections de bugs et amélioration de la stabilité
</fr-FR>
<ar>
• إصلاحات للأخطاء وتحسينات في الاستقرار
</ar>
<hu-HU>
• Hibajavítások és stabilitási fejlesztések
</hu-HU>
<vi>
• Sửa lỗi và cải thiện độ ổn định
</vi>
<da-DK>
• Fejlrettelser og forbedret stabilitet
</da-DK>
<iw-IL>
• תיקוני באגים ושיפורי יציבות
</iw-IL>
<id>
• Perbaikan bug dan peningkatan stabilitas
</id>
<es-ES>
• Corrección de errores y mejoras de estabilidad
</es-ES>
<it-IT>
• Correzioni di bug e miglioramenti della stabilità
</it-IT>
<zh-CN>
• 问题修复和稳定性改进
</zh-CN>
<ko-KR>
• 버그 수정 및 안정성 개선
</ko-KR>
<nl-NL>
• Bugfixes en verbeterde stabiliteit
</nl-NL>
<no-NO>
• Feilrettinger og bedre stabilitet
</no-NO>
<pl-PL>
• Poprawki błędów i większa stabilność
</pl-PL>
<pt-BR>
• Correções de bugs e melhorias de estabilidade
</pt-BR>
<ro>
• Remedieri de erori și îmbunătățiri de stabilitate
</ro>
<sk>
• Opravy chýb a vyššia stabilita
</sk>
<th>
• แก้ไขข้อบกพร่องและปรับปรุงความเสถียร
</th>
<tr-TR>
• Hata düzeltmeleri ve kararlılık iyileştirmeleri
</tr-TR>
<fi-FI>
• Virhekorjauksia ja vakauden parannuksia
</fi-FI>
<hi-IN>
• बग सुधार और स्थिरता में सुधार
</hi-IN>
<cs-CZ>
• Opravy chyb a vyšší stabilita
</cs-CZ>
<sv-SE>
• Buggfixar och förbättrad stabilitet
</sv-SE>
<ja-JP>
• 不具合の修正と安定性の向上
</ja-JP>
```

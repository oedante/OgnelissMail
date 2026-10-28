# Архитектура редактора письма (Ogneliss)

## Требования
Корпоративная почта: нужны **таблицы**, **вставка из буфера с сохранением оформления**
(Word/Excel/Outlook), редактирование и подписи. Цели: **Android, iOS, macOS, Windows**
(Linux — вне целей).

## Проблема WebView на десктопе
Настоящий HTML-редактор (contenteditable) — единственный способ качественной вставки из
Office и работы с таблицами. Но он требует WebView. Поддержка `flutter_inappwebview`
(на нём работает `html_editor_enhanced`):

| Платформа | inappwebview | Примечание |
|-----------|--------------|------------|
| Android   | ✅ полно     | — |
| iOS       | ✅ полно     | — |
| macOS     | ✅ полно     | — |
| Windows   | ⚠️ эксперим. (6.x) | нужен **WebView2 Runtime** |
| Linux     | ❌ нет        | вне целей |

> Важно: замена `html_editor_enhanced` на «свой TinyMCE» НЕ убирает это ограничение —
> TinyMCE тоже работает поверх WebView. Выигрыш TinyMCE — не кроссплатформенность, а
> **качество** (вставка из Office, сложные таблицы, слияние ячеек). Ограничение — в WebView.

## Текущее решение (Путь 1)
Условный редактор в `compose_screen.dart` (`_useHtmlEditor`):
- **html_editor_enhanced** на Android/iOS/macOS/Web/Windows — таблицы (кнопка table),
  вставка с оформлением (нативно), вывод HTML.
- **простой TextField** — фолбэк на Linux и везде, где WebView недоступен (Linux некритичен, упрощённый режим по согласованию). flutter_quill УБРАН (вместе с vsc_quill_delta_to_html) — устранён риск конфликта импортов с html_editor_enhanced.
- Тело письма для отправки: `_getBodyHtmlAsync()` (getText у html-редактора; Delta→HTML у
  Quill). Кэш `_lastHtml` через `onChangeContent`.
- Рендер таблиц во **входящих**: `flutter_html_table` + `TableHtmlExtension` в карточке.

### Windows: что нужно
- Установленный **Microsoft Edge WebView2 Runtime** (на большинстве Win10/11 уже есть; в
  инсталлятор стоит включить bootstrapper WebView2).
- Протестировать стабильность рендеринга и вставки. Если ок — менять ничего не нужно.

### Если Windows нестабилен — три варианта (по возрастанию усилий)
1. **Тривиально:** убрать `Platform.isWindows` из `_useHtmlEditor` → на Windows будет
   flutter_quill (без таблиц, но стабильно). Одна строка.
2. **Путь 2 (компромисс):** отдельная реализация редактора на `webview_windows`
   (нативный WebView2) только для Windows, через `if (Platform.isWindows)`. Это НЕ
   переключение backend у html_editor_enhanced (он завязан на inappwebview), а **свой**
   HTML-редактор (например, локальный TinyMCE) в `webview_windows`.
3. **Единый свой редактор (лучшее качество):** самохостируемый редактор на ядре
   TinyMCE — **HugeRTE** (MIT-форк TinyMCE 6). *Исправлено 05.10.2026:* сам TinyMCE
   с версии 7 распространяется под GPLv2+ (или коммерческой лицензией) и для закрытой
   поставки не подходит; CKEditor 5 — тоже GPL/коммерческая. Подробно — `docs/plan/COMPOSE_EDITOR.md` в `assets/editor/`, запуск в `flutter_inappwebview`, мост JS↔Flutter
   (`getContent`/`setContent`/`onChange`, вставка HTML). Работает офлайн, одинаково на
   Android/iOS/macOS; на Windows — тот же inappwebview+WebView2. Это заменяет Summernote
   (в html_editor_enhanced) на TinyMCE и даёт максимальное качество вставки из Office.

## Рекомендация
- Сначала **протестировать Путь 1** на всех целях (особенно Windows + WebView2).
- Если качество вставки Summernote устраивает — оставить как есть.
- Если нужна вставка из Office «как в Outlook» / сложные таблицы — перейти на
  **HugeRTE (MIT-форк TinyMCE 6)** в inappwebview (вариант 3), с фолбэком на простой TextField
  для Linux/без-WebView2.

## Подписи с таблицами
Экран настройки подписи сейчас — плоское текстовое поле. Чтобы подписи тоже поддерживали
таблицы, туда нужно подключить тот же HTML-редактор (отдельная доработка).

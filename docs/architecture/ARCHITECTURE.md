# Mail — архитектура и руководство разработчика

Техническая документация проекта `mail_app` (Flutter/Dart). Пользовательское
описание — в `README.md`, план и статусы — в `docs/ROADMAP.md`, карточка для ИБ —
в `docs/SECURITY_REVIEW_IB.md`.

## Стек
- **Flutter/Dart**, state-management — **Riverpod**.
- БД — **Drift** (SQLite), кодоген через `build_runner`.
- Навигация — **go_router**. Защищённое хранилище — `flutter_secure_storage`.
- Почтовый движок — внутренний пакет **`packages/mail_engine`** (ActiveSync/WBXML).
- Локализация — собственная плоская карта (RU/EN), без `intl`-генерации.

## Структура `lib/`
```
core/        константы, темы, навигация, логирование, безопасность (pinning, secure storage)
data/        models (account/email/folder/contact/task...), database (Drift), providers
features/    экраны по доменам: mail, calendar, contacts, tasks, notes, compose, settings, dashboard, auth
l10n/        app_localizations.dart — плоская карта {key:{ru,en}} + геттеры
services/    ai, sync, notifications, rules, mail (транспорты/движок/oauth), security, ...
widgets/     общие виджеты
main.dart    инициализация: уведомления, обработчик действий, напоминания, фоновая синхронизация
```

## Транспорты почты
Три транспорта за абстракцией `MailTransport`, маршрутизация — фабрикой
(`mailTransportFactoryProvider.forAccount(account)`):

| Транспорт | Когда | Реализация |
|---|---|---|
| **EWS** (Exchange Web Services, SOAP) | `account.usesEws` (Exchange или организации с `ewsUrl`) | `services/mail/ews/` |
| **EAS** (ActiveSync 16.1, WBXML) | `account.usesEas` (ActiveSync или организации без `ewsUrl`) | `packages/mail_engine` (единственная реализация; старый `services/mail/activesync/` удалён) |
| **IMAP/SMTP** | `account.isImap` / OAuth-почта | `services/mail/imap/` (`enough_mail`) |

Признаки транспорта — геттеры в `AccountModel` (`usesEws/usesEas/isImap/isOAuth`).

### Движок `mail_engine`
Path-зависимость. Содержит WBXML-кодек, команды ActiveSync (`FolderSync`, `Sync`,
`SendMail`, `ItemOperations`, `FolderCreate/Delete/Update`, `Ping`), `OAuthHelper`
(обмен/refresh токена). `MailEngineService` — мост из приложения (в т.ч.
`fetchFullBody` через `ItemOperations`).

## Синхронизация (`services/sync/sync_service.dart`)
1. Папки → письма постранично (с учётом режима «только заголовки»).
2. Для входящих — локальный AI-анализ (`AiAnalyzerService`, в изоляте) с учётом
   роли получателя (To/Cc, см. И2).
3. Применение правил (`AutoRulesService.getMatchingActions`): теги, категории,
   прочитано, флаг, **перемещение** (Этап 6, клиентская часть).
4. Богатое уведомление о новых письмах с умными ответами; VIP — усиленный канал.

## Правила и локальный ИИ
- **`AutoRulesService`** (prefs): модель `AutoRule` (условия/действия/приоритет/
  AND-OR), CRUD, reorder, **набор по умолчанию**, **экспорт/импорт JSON**, сброс.
  UI — `features/settings/screens/rules_screen.dart`.
- **`AiAnalyzerService`**: категория, тональность, срочность, сущности; при `Cc`
  снижает срочность/негатив (И2).
- **`SmartReplyService`**: 3 варианта ответа; в режиме `ccOnly` — только
  «FYI-пересылка» и «Событие/напоминание» (`SmartReplyKind.createEvent`).

## VIP (`services/mail/focus_mode_service.dart`)
VIP-отправители + VIP-слова в теме + высокий приоритет → `isVip(email)`. Управление —
`features/settings/screens/vip_settings_screen.dart` (`/vip-settings`). VIP-письма
дают уведомление на канале `email_vip` (importance.max).

## Виртуальные папки
- **«Вся почта»** (в пределах аккаунта) — `getUnifiedInboxPage` (без Спама/Корзины/
  Черновиков).
- **«Хаб аккаунтов»** — `getAllAccountsUnifiedPage` (все аккаунты, без Спама/Корзины).
Пункты в боковом меню; режимы — провайдеры `unifiedModeProvider`/`allAccountsModeProvider`.

## Уведомления (`services/notifications/`)
- Каналы Android: `email_default`, `email_vip`, `sync`, `reminders`, `task_reminders`.
- Планировщики: `meeting_reminder_service` (встречи), `task_reminder_service` (сроки задач).
- `notification_action_handler` — действия (ответить/умный ответ/флаг/архив);
  подключён к нажатиям в `main` через колбэк `onResponse`.

## OAuth
- Прямой кроссплатформенный флоу: мобайл/macOS — `flutter_appauth` (custom scheme
  `com.example.mail:/oauth2redirect`); Windows/Linux — loopback;
  Web — popup + `web/oauth2redirect.html`; PKCE S256.
- **Корпоративный прокси** (секреты на сервере, refresh без повторного входа):
  - `server/oauth-proxy/` — Node/Express для Debian 11 (stateful или stateless).
  - Клиент `OAuthProxyClient` (`services/mail/oauth/oauth_proxy_client.dart`):
    `loginUrl`, `handleRedirect`, `getAccessToken` (кэш + авто-refresh). Включается
    через `--dart-define=OAUTH_PROXY_URL=...,OAUTH_PROXY_KEY=...`.

Redirect по платформам и регистрация у провайдеров — см. `OAUTH_SETUP.md`.

## Матрица возможностей транспортов (Этап 7П)
`services/mail/transport_capabilities.dart` — `TransportCapabilities.forAccount()`
с флагами `serverMove/Flag/Delete/MarkRead`, `serverSearch`, `serverFolders`,
`serverRules`, `recall`, `freeBusy`, `gal`, `push`. Провайдер
`transportCapabilitiesProvider` — для скрытия недоступных действий в UI.

| | EWS | EAS | IMAP |
|---|---|---|---|
| move/flag/delete/read/search/folders | ✓ | ✓ | ✓ |
| serverRules | ✓ | ✗ | ✗ |
| recall | ✓ | ✗ | ✗ |
| freeBusy / gal | ✓ | ✓ | ✗ |
| push | stream | Ping | IDLE |

## Локализация
`lib/l10n/app_localizations.dart` — плоская карта `{ключ:{ru,en}}` (~480 ключей),
доступ `l10n.tr('key')` + геттеры (`l10n.cancel`, `l10n.save`, `l10n.isRussian`...).
Правило: `const`-виджет не должен оборачивать `l10n.tr(...)`.

## Сборка и первый запуск
```bash
./scripts/setup.sh            # Linux/macOS: flutter/dart, платформы, pub get, build_runner, иконки
./scripts/setup.sh --reset-db # пересоздать сгенерированный код БД
.\scripts\setup.ps1           # Windows
```
Скрипт ставит/проверяет инструменты, создаёт недостающие платформенные папки
(`flutter create`), тянет зависимости, гоняет `build_runner` (Drift) и
`flutter_launcher_icons`. Подробности — `scripts/README.md`.

> Кодоген (`*.g.dart`) в этом репозитории не закоммичен — генерируется локально
> скриптом. Тестовая БД создаётся на устройстве и мигрируется при запуске.

## Контроль качества
Сборка проверяется без компилятора структурно: баланс скобок (с учётом строк/
комментариев/`${}`), отсутствие `const`-обёрток над `l10n.tr`, отсутствие
дублей ключей локализации. Полная компиляция — на машине разработчика.

## Статусы этапов
См. `docs/ROADMAP.md` (маршрут `0 → 2 → 3 → [4→5→6] → 7 → 7П → 8` + идеи И1–И3).

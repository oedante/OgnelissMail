# Документация Ogneliss

> **Новый диалог с Claude — начать с [HANDOFF.md](HANDOFF.md)**: правила, состояние, что дальше.

Документы разложены по разделам:

- **legal/** — юридические документы
  - `PRIVACY_POLICY.md` — политика конфиденциальности (RU/EN)
  - `TERMS_OF_USE.md` — условия использования (RU/EN)
  - `LICENSES.md` — сведения о лицензиях (приложение + сторонние компоненты)
- **roadmap/** — план и история
  - `ROADMAP.md` — дорожная карта (статусы этапов, история работ)
  - `CHANGELOG.md` — журнал изменений
- **guides/** — инструкции
  - `USER_GUIDE.md` — руководство пользователя (RU/EN)
  - `PRE_BUILD_CHECKLIST.md` — предсборочный чек-лист
  - `QUICKSTART.md` — запуск по шагам: сервер и Android Studio
  - `OAUTH_PROXY_DEBIAN.md` — установка и проверка OAuth-прокси на Debian 11/12
  - `OAUTH_PROXY_SETUP.md` — переменные и секреты OAuth-прокси
  - `OAUTH_SETUP.md` — настройка OAuth-провайдеров
  - `OAUTH_UPDATE_2026-10.md` — обновление OAuth: календарь и контакты Gmail, Яндекса, Mail.ru
  - `WINDOWS_BUILD_FIX.md` — сборка под Windows
- **store/** — публикация в магазинах
  - `STORE_LISTING.md` — тексты карточек (RU/EN)
  - `PUBLISHING_COMPLIANCE.md` — требования сторов
- **security/** — безопасность
  - `SECURITY_REVIEW.md` — проверка кода (безопасность/быстродействие/параллельность)
  - `SECURITY_REVIEW_IB.md` — обзор ИБ
- **architecture/** — архитектура и анализ
  - `ARCHITECTURE.md`, `EDITOR-ARCHITECTURE.md`, `TASK_WORKFLOW_DESIGN.md`,
    `ANALYSIS.md`, `UNWIRED-ANALYSIS.md`

В корне проекта остаются `README.md`, `CHANGELOG.md` и `ROADMAP.md`
(рабочие копии по конвенции).

> Секреты OAuth-провайдеров в документации и репозитории отсутствуют — они
> размещаются только на сервере прокси (см. `guides/OAUTH_PROXY_SETUP.md`).

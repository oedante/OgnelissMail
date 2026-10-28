# Проверки без Flutter (tool/dev)

В облачной среде разработки нет Flutter, Android SDK и Xcode — код не
компилируется. Эти скрипты ловят частые ошибки до сборки. Запуск — из корня
проекта.

| Скрипт | Что делает |
|---|---|
| `python3 tool/dev/brace_check.py <файлы.dart>` | баланс скобок с учётом строк и интерполяции → «checked N bad 0» |
| `python3 tool/dev/dup_member_check.py [пути]` | повторно объявленные члены класса («… is already declared in this scope») → «повторов 0» |
| `python3 tool/dev/removed_files.py` | обновить `tool/dev/removed_files.txt` — удалённые из проекта файлы для `scripts/remove_stale_files.ps1` и `.sh` (запускает `make_archive.sh`; список только пополняется; `.vscode/`, `.idea/`, `.github/`, `ios/`, `macos/`, `config/` не попадают никогда) |
| `python3 tool/dev/l10n_check.py` | ключи `l10n.tr('…')` / `plural('…')`, которых нет в `assets/l10n/en.xml` (и неиспользуемые) |
| `python3 tool/dev/l10n_set.py strings.json` | добавить/заменить строки: `{"key": {"ru": …, "en": …, "de": …, "fr": …}}` — в `assets/l10n/<код>.xml` (с 1.7.3); множественное число — формы через «|» (ru: one\|few\|many, en/de/fr: one\|other). Остальные команды — `python3 tool/l10n/l10n.py -h` |
| `python3 scripts/precompile_check.py` | импорты и типы (много ложных срабатываний на part-файлах и пакете mail_engine) |
| `python3 tool/ui/ui_lint.py --files` | отступы и шрифты числами, цвета Material, `Icons.*` вместо `AppIcons` |
| `python3 tool/dev/site_serve.py site/` | локальный сервер сайта с теми же адресами, что в nginx (порт 8765) |
| `python3 tool/dev/site_shots.py /,/mail/,/mail/ru/privacy [top]` | снимки страниц (Playwright, Chromium): компьютер/телефон, светлая/тёмная; пишет PNG в текущую папку — запускать из временной папки |

После проверок — `flutter analyze` и `flutter test`: на GitHub (Actions, после каждого push в master) и у владельца перед сборкой.

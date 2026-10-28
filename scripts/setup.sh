#!/usr/bin/env bash
# ============================================================================
# Mail — скрипт первичной настройки окружения (Linux / macOS)
# Выполняет все шаги перед компиляцией:
#   проверка Flutter/Dart, включение desktop, создание платформенных папок,
#   pub get, генерация иконок, генерация кода БД (drift/build_runner),
#   директории, опциональный сброс БД и очистка.
#
# Использование:
#   ./scripts/setup.sh                 # полная настройка
#   ./scripts/setup.sh --reset-db      # + пересоздать сгенерированный код БД
#   ./scripts/setup.sh --clean         # + flutter clean перед настройкой
#   ./scripts/setup.sh --clean-logs    # + удалить *.log и logs/
#   ./scripts/setup.sh --icons-only    # только перегенерировать иконки (вкл. трей)
#   ./scripts/setup.sh --no-doctor     # пропустить flutter doctor
#   ./scripts/setup.sh --platforms=android,web,linux   # явный список платформ
# По умолчанию создаются папки всех платформ (android,ios,web,windows,macos,linux);
# сборка каждой требует своего хоста.
# ============================================================================
set -euo pipefail

# ── Цвета ──
if [ -t 1 ]; then BLU='\033[0;34m'; GRN='\033[0;32m'; RED='\033[0;31m'; YEL='\033[1;33m'; NC='\033[0m'; else BLU=''; GRN=''; RED=''; YEL=''; NC=''; fi
step() { echo -e "\n${BLU}▶ $*${NC}"; }
ok()   { echo -e "${GRN}✓ $*${NC}"; }
warn() { echo -e "${YEL}⚠ $*${NC}"; }
die()  { echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

# ── Корень проекта (на уровень выше scripts/) ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"
[ -f pubspec.yaml ] || die "pubspec.yaml не найден. Запускайте из корня проекта или scripts/setup.sh"

# ── Разбор флагов ──
RESET_DB=0; DO_CLEAN=0; ICONS_ONLY=0; RUN_DOCTOR=1; PLATFORMS=""; CLEAN_LOGS=0
BUILD_TARGET=""; BUILD_MODE="release"
for arg in "$@"; do
  case "$arg" in
    --reset-db) RESET_DB=1 ;;
    --clean) DO_CLEAN=1 ;;
    --clean-logs) CLEAN_LOGS=1 ;;
    --icons-only) ICONS_ONLY=1 ;;
    --no-doctor) RUN_DOCTOR=0 ;;
    --platforms=*) PLATFORMS="${arg#*=}" ;;
    --build=*) BUILD_TARGET="${arg#*=}" ;;
    --debug) BUILD_MODE="debug" ;;
    --profile) BUILD_MODE="profile" ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) warn "Неизвестный аргумент: $arg" ;;
  esac
done

# ── Определение ОС и платформ по умолчанию ──
# Папки всех платформ можно создать на любом хосте (это лишь шаблоны); СБОРКА
# каждой платформы требует своего хоста (Windows→windows, macOS→ios/macos).
OS="$(uname -s)"
case "$OS" in
  Linux)  HOST="linux";  DEFAULT_PLATFORMS="android,ios,web,windows,macos,linux" ;;
  Darwin) HOST="macos";  DEFAULT_PLATFORMS="android,ios,web,windows,macos,linux" ;;
  *) die "Неподдерживаемая ОС: $OS (используйте setup.ps1 для Windows)" ;;
esac
[ -n "$PLATFORMS" ] || PLATFORMS="$DEFAULT_PLATFORMS"
ok "ОС: $OS · платформы: $PLATFORMS"

# ── 1. Проверка инструментов ──
step "Проверка Flutter и Dart"
command -v flutter >/dev/null 2>&1 || die "Flutter не найден в PATH. Установите: https://docs.flutter.dev/get-started/install"
command -v dart >/dev/null 2>&1 || warn "dart не в PATH отдельно (обычно идёт с Flutter) — продолжаем"
flutter --version | head -1 || true
ok "Flutter найден"

if [ "$ICONS_ONLY" -eq 1 ]; then
  step "Перегенерация иконок (только иконки)"
  flutter pub get
  dart run flutter_launcher_icons
  ok "Иконки обновлены"; exit 0
fi

if [ "$RUN_DOCTOR" -eq 1 ]; then
  step "flutter doctor"
  flutter doctor || warn "flutter doctor сообщил о проблемах — проверьте вывод выше"
fi

# ── 2. Очистка (опционально) ──
if [ "$DO_CLEAN" -eq 1 ]; then
  step "flutter clean"
  flutter clean || true
  ok "Очищено"
fi

# ── 3. Включение desktop и создание недостающих платформенных папок ──
step "Включение платформ и создание недостающих папок"
case "$HOST" in
  linux) flutter config --enable-linux-desktop >/dev/null 2>&1 || true ;;
  macos) flutter config --enable-macos-desktop >/dev/null 2>&1 || true ;;
esac
# Создаём отсутствующие платформенные папки, не затрагивая lib/
MISSING=""
IFS=',' read -ra PLATS <<< "$PLATFORMS"
# Папка может существовать частично (в архиве есть только манифест и Kotlin-код
# android/), поэтому проверяем ключевой файл каждой платформы.
platform_ready() {
  case "$1" in
    android) [ -f android/app/build.gradle ] || [ -f android/app/build.gradle.kts ] ;;
    ios)     [ -f ios/Runner.xcodeproj/project.pbxproj ] ;;
    macos)   [ -f macos/Runner.xcodeproj/project.pbxproj ] ;;
    windows) [ -f windows/CMakeLists.txt ] ;;
    linux)   [ -f linux/CMakeLists.txt ] ;;
    web)     [ -f web/index.html ] ;;
    *)       [ -d "$1" ] ;;
  esac
}
for pl in "${PLATS[@]}"; do
  platform_ready "$pl" || MISSING="${MISSING:+$MISSING,}$pl"
done
if [ -n "$MISSING" ]; then
  warn "Нет платформенных файлов: $MISSING — создаём через flutter create (существующие файлы не перезаписываются)"
  flutter create . --platforms="$MISSING" --project-name ogneliss --org com.ogneliss >/dev/null
  ok "Платформенные файлы созданы: $MISSING"
else
  ok "Все нужные платформенные папки на месте"
fi

# Идентификатор пакета и название приложения — на каждом запуске (правки
# идемпотентны и чинят дерево, созданное раньше с другими значениями).
# flutter create даёт com.ogneliss.ogneliss, нужен com.ogneliss.mail.
# OAuth-схема возврата — com.ogneliss.mail://oauth (как id пакета; разрешена
# на прокси в ALLOWED_REDIRECTS). Запасной путь без прокси (flutter_appauth)
# использует отдельную схему com.ogneliss.mail.appauth.
BUNDLE_ID="com.ogneliss.mail"
APP_TITLE="Ogneliss Mail"
EXE_NAME="OgnelissMail"
sedi() { local f="$1"; shift; [ -f "$f" ] && sed -i -E "$@" "$f"; return 0; }
for gf in android/app/build.gradle android/app/build.gradle.kts; do
  sedi "$gf" \
    -e "s/applicationId = \"[^\"]*\"/applicationId = \"$BUNDLE_ID\"/" \
    -e "s/applicationId \"[^\"]*\"/applicationId \"$BUNDLE_ID\"/" \
    -e "s/namespace = \"[^\"]*\"/namespace = \"$BUNDLE_ID\"/" \
    -e "s/namespace \"[^\"]*\"/namespace \"$BUNDLE_ID\"/"
done
# flutter_appauth объявляет в манифесте схему возврата через плейсхолдер
# appAuthRedirectScheme; без него сборка Android падает на слиянии манифестов.
if [ -f android/app/build.gradle.kts ] && ! grep -q appAuthRedirectScheme android/app/build.gradle.kts; then
  sed -i -E '0,/applicationId = "[^"]*"/s//&\n        manifestPlaceholders["appAuthRedirectScheme"] = "com.ogneliss.mail.appauth"/' android/app/build.gradle.kts
fi
if [ -f android/app/build.gradle ] && ! grep -q appAuthRedirectScheme android/app/build.gradle; then
  sed -i -E "0,/applicationId \"[^\"]*\"/s//&\n        manifestPlaceholders += [appAuthRedirectScheme: 'com.ogneliss.mail.appauth']/" android/app/build.gradle
fi
# MainActivity лежит в архиве (com/ogneliss/mail); копия flutter create не нужна.
rm -rf android/app/src/main/kotlin/com/ogneliss/ogneliss
if [ -f ios/Runner.xcodeproj/project.pbxproj ]; then
  sed -i "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*\.RunnerTests;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID.RunnerTests;/g" ios/Runner.xcodeproj/project.pbxproj
  sed -i "/RunnerTests/! s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*;/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;/g" ios/Runner.xcodeproj/project.pbxproj
fi
sedi macos/Runner/Configs/AppInfo.xcconfig \
  -e "s/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID/" \
  -e "s/^PRODUCT_NAME = .*/PRODUCT_NAME = $APP_TITLE/"
sedi linux/CMakeLists.txt \
  -e "s/set\(APPLICATION_ID \"[^\"]*\"\)/set(APPLICATION_ID \"$BUNDLE_ID\")/" \
  -e "s/set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$EXE_NAME\")/"
sedi linux/runner/my_application.cc \
  -e "s/gtk_header_bar_set_title\(header_bar, \"[^\"]*\"\)/gtk_header_bar_set_title(header_bar, \"$APP_TITLE\")/" \
  -e "s/gtk_window_set_title\(window, \"[^\"]*\"\)/gtk_window_set_title(window, \"$APP_TITLE\")/"
sedi windows/runner/Runner.rc \
  -e "s/(VALUE \"CompanyName\", )\"[^\"]*\"/\1\"com.ogneliss\"/" \
  -e "s/(VALUE \"FileDescription\", )\"[^\"]*\"/\1\"$APP_TITLE\"/" \
  -e "s/(VALUE \"ProductName\", )\"[^\"]*\"/\1\"$APP_TITLE\"/" \
  -e "s/(VALUE \"InternalName\", )\"[^\"]*\"/\1\"$EXE_NAME\"/" \
  -e "s/(VALUE \"OriginalFilename\", )\"[^\"]*\"/\1\"$EXE_NAME.exe\"/"
sedi windows/runner/main.cpp -e "s/window\.Create\(L\"[^\"]*\"/window.Create(L\"$APP_TITLE\"/"
sedi windows/CMakeLists.txt -e "s/set\(BINARY_NAME \"[^\"]*\"\)/set(BINARY_NAME \"$EXE_NAME\")/"
sedi web/manifest.json \
  -e "s/\"name\": *\"[^\"]*\"/\"name\": \"$APP_TITLE\"/" \
  -e "s/\"short_name\": *\"[^\"]*\"/\"short_name\": \"$APP_TITLE\"/"
sedi web/index.html \
  -e "s#<title>[^<]*</title>#<title>$APP_TITLE</title>#" \
  -e "s/(name=\"apple-mobile-web-app-title\" content=)\"[^\"]*\"/\1\"$APP_TITLE\"/"
ok "Пакет: $BUNDLE_ID, название: $APP_TITLE"

# ── 4. Зависимости ──
step "Загрузка зависимостей (flutter pub get)"
flutter pub get
ok "Зависимости загружены"

# ── 5. Сброс/генерация кода БД (drift) ──
if [ "$RESET_DB" -eq 1 ]; then
  step "Сброс сгенерированного кода БД"
  find lib -name "*.g.dart" -delete 2>/dev/null || true
  find lib -name "*.drift.dart" -delete 2>/dev/null || true
  # Локальная dev-база (если кто-то клал её в проект) — удаляем
  find . -maxdepth 2 -name "ogneliss.db" -delete 2>/dev/null || true
  warn "Сгенерированный код БД удалён — будет создан заново. База на устройстве пересоздаётся миграциями при запуске."
fi

step "Генерация кода (drift / build_runner)"
dart run build_runner build
ok "Код БД сгенерирован"

# ── 6. Иконки приложения ──
step "Генерация иконок приложения"
dart run flutter_launcher_icons || warn "flutter_launcher_icons завершился с предупреждением (проверьте assets/icons/app_icon.png)"
ok "Иконки сгенерированы"

# ── 6b. Иконки системного трея (десктоп) ──
# Трей-иконку flutter_launcher_icons не делает — готовим отдельно. Гарантируем
# наличие assets/icons/tray_icon.png (копия app_icon.png, если нет) и, при
# наличии ImageMagick, .ico для Windows-трея.
step "Иконки системного трея"
SRC_ICON="assets/icons/app_icon.png"
TRAY_PNG="assets/icons/tray_icon.png"
if [ -f "$SRC_ICON" ]; then
  [ -f "$TRAY_PNG" ] || { cp "$SRC_ICON" "$TRAY_PNG"; ok "Создан $TRAY_PNG (из app_icon.png)"; }
  if command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; then
    CONV=$(command -v magick || command -v convert)
    "$CONV" "$SRC_ICON" -define icon:auto-resize=16,24,32,48,256 assets/icons/tray_icon.ico 2>/dev/null \
      && ok "Создан assets/icons/tray_icon.ico (Windows-трей)" || warn "Не удалось создать .ico"
  else
    warn "ImageMagick не найден — .ico для Windows-трея не создан (положите assets/icons/tray_icon.ico вручную)"
  fi
else
  warn "Нет $SRC_ICON — трей-иконки пропущены"
fi
ok "Трей-иконки готовы"

# ── 7. Очистка логов ──
# Логи приложения живут в каталоге данных на устройстве (в репозитории их нет),
# здесь чистим локальные артефакты логов сборки/запуска, если появились.
if [ "$CLEAN_LOGS" -eq 1 ]; then
  step "Очистка логов"
  find . -type f -name "*.log" -not -path "./.git/*" -delete 2>/dev/null || true
  rm -rf logs 2>/dev/null || true
  ok "Логи очищены"
else
  warn "Очистка логов пропущена (добавьте --clean-logs, чтобы удалить *.log и logs/)"
fi

# ── 8. Служебные директории ──
step "Создание служебных директорий"
mkdir -p build/outputs .dart_tool
ok "Директории готовы"

# ── 9. Секреты сборки (--dart-define) ──
# Секреты НЕ хранятся в исходниках. Берём их из scripts/.env.build (в .gitignore)
# либо из переменных окружения. Шаблон — scripts/.env.build.example.
step "Секреты сборки"
DEFINES=()
ENV_BUILD="$ROOT/scripts/.env.build"
if [ -f "$ENV_BUILD" ]; then
  # shellcheck disable=SC1090
  set -a; . "$ENV_BUILD"; set +a
  ok "Прочитан scripts/.env.build"
else
  warn "scripts/.env.build не найден — используются переменные окружения (если заданы)"
  echo "    Создать: cp scripts/.env.build.example scripts/.env.build"
fi

add_define() {  # add_define ИМЯ ЗНАЧЕНИЕ
  [ -n "$2" ] && DEFINES+=("--dart-define=$1=$2")
}
add_define OAUTH_PROXY_URL     "${OAUTH_PROXY_URL:-}"
add_define OAUTH_PROXY_KEY     "${OAUTH_PROXY_KEY:-}"
# MAILRU_CLIENT_SECRET в сборку не передаём: секрет живёт только на прокси.

if [ -n "${OAUTH_PROXY_URL:-}" ]; then
  ok "OAuth через прокси: $OAUTH_PROXY_URL"
  [ -z "${OAUTH_PROXY_KEY:-}" ] && warn "OAUTH_PROXY_KEY пуст — /token вернёт 401"
else
  warn "OAUTH_PROXY_URL не задан — OAuth пойдёт легаси-путём (нужны clientId в app_constants)"
fi

# Те же значения — в config/dart_defines.json: его подхватывают конфигурации
# запуска Android Studio (--dart-define-from-file). Файл в .gitignore.
mkdir -p "$ROOT/config"
# Значения, вписанные в файл вручную, не затираем, если переменная не задана.
python3 - "$ROOT/config/dart_defines.json" "${OAUTH_PROXY_URL:-}" "${OAUTH_PROXY_KEY:-}" "${SUPPORT_EMAIL:-}" <<'PY' \
  && ok "config/dart_defines.json обновлён (для Android Studio)" \
  || warn "Не удалось записать config/dart_defines.json (нужен python3)"
import json, os, sys
path = sys.argv[1]
old = {}
if os.path.exists(path):
    try:
        old = json.load(open(path, encoding="utf-8"))
    except Exception:
        old = {}
def pick(key, env, default):
    return env or old.get(key) or default
json.dump({
    "OAUTH_PROXY_URL": pick("OAUTH_PROXY_URL", sys.argv[2], "https://www.ogneliss.ru/oauth"),
    "OAUTH_PROXY_KEY": pick("OAUTH_PROXY_KEY", sys.argv[3], ""),
    "SUPPORT_EMAIL": pick("SUPPORT_EMAIL", sys.argv[4], ""),
}, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY

# ── 10. Сборка (если запрошена) ──
if [ -n "$BUILD_TARGET" ]; then
  step "Сборка: $BUILD_TARGET ($BUILD_MODE)"
  case "$BUILD_TARGET" in
    apk|appbundle|ios|ipa|windows|macos|linux|web) ;;
    *) die "Неизвестная цель --build=$BUILD_TARGET (apk|appbundle|ios|ipa|windows|macos|linux|web)"; exit 1 ;;
  esac
  echo "  flutter build $BUILD_TARGET --$BUILD_MODE ${DEFINES[*]}"
  flutter build "$BUILD_TARGET" "--$BUILD_MODE" "${DEFINES[@]}"
  ok "Сборка завершена"
  case "$BUILD_TARGET" in
    apk)       echo "    → build/app/outputs/flutter-apk/app-$BUILD_MODE.apk" ;;
    appbundle) echo "    → build/app/outputs/bundle/${BUILD_MODE}/app-$BUILD_MODE.aab" ;;
    windows)   echo "    → build/windows/x64/runner/${BUILD_MODE^}/" ;;
    web)       echo "    → build/web/" ;;
  esac
fi

# ── Итог ──
echo -e "\n${GRN}══════════════════════════════════════════════════${NC}"
if [ -n "$BUILD_TARGET" ]; then
  ok "Готово: настройка + сборка $BUILD_TARGET"
else
  ok "Настройка завершена. Запуск:"
  echo "    flutter run -d $HOST ${DEFINES[*]}     # десктоп"
  echo "    flutter run -d chrome ${DEFINES[*]}    # web"
  echo ""
  echo "  Сборка одной командой (настройка + компиляция):"
  echo "    ./scripts/setup.sh --build=apk         # Android"
  echo "    ./scripts/setup.sh --build=windows     # Windows"
  echo "    ./scripts/setup.sh --build=web         # Web"
fi
echo -e "${YEL}Секреты:${NC} scripts/.env.build (в .gitignore). Настройка прокси —"
echo "    server/oauth-proxy/PROVIDERS.md"

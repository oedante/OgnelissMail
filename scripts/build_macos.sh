#!/usr/bin/env bash
# Сборка Ogneliss Mail для Mac (macOS 11+, Apple Silicon и Intel).
#
#   scripts/build_macos.sh --setup             один раз: создать папку macos/ и настроить её
#                                              (песочница, сеть, связка ключей, схема входа OAuth)
#   scripts/build_macos.sh --run               запуск на этом Mac (debug)
#   scripts/build_macos.sh                     сборка release → build/macos/Build/Products/Release/*.app
#   scripts/build_macos.sh --archive           архив для Mac App Store (Intel + Apple Silicon)
#                                              и открыть его в Xcode (Organizer → Distribute App)
#   scripts/build_macos.sh --upload            архив и сразу выгрузка в App Store Connect (TestFlight)
#
# Сборка универсальная: одно приложение для Mac с Intel и с Apple Silicon (M1
# и новее); скрипт проверяет это (lipo) после архива.
# Команда разработчика — та же, что у iPhone (~/.ogneliss/ios_signing.xcconfig,
# scripts/build_ios.sh --team) или TEAM_ID=ABCDE12345.
# Ключ App Store Connect API (по желанию, иначе — учётная запись Xcode):
#   ASC_KEY_ID, ASC_ISSUER_ID; файл ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
# KEYCHAIN_PASSWORD — пароль входа на Mac, если сборка идёт по SSH.
# Подробно — docs/guides/TESTFLIGHT.md и BUILD_ALL_PLATFORMS.md, раздел «Mac».
#
# Папка macos/ в архив проекта не входит: она создаётся на Mac этим скриптом
# и дальше живёт у вас (подпись и настройки Xcode не затираются новым архивом).
# Секреты сборки — config/dart_defines.json (тот же файл, что для Android/iPhone).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=build
while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup) MODE=setup ;;
    --run) MODE=run ;;
    --archive) MODE=archive ;;
    --upload) MODE=upload ;;
    --team) TEAM_ID="$2"; shift ;;
    *) echo "Неизвестный параметр: $1"; exit 2 ;;
  esac
  shift
done

[[ "$(uname)" == "Darwin" ]] || { echo "Сборка для Mac — только на macOS."; exit 1; }
command -v flutter >/dev/null || { echo "Flutter не найден (brew install --cask flutter)."; exit 1; }
# Rust (rustup) — ядро перетаскивания вложений (super_drag_and_drop, 1.15.0)
# собирается из исходников; нужную версию Rust rustup скачает сам.
command -v rustup >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/rustup" ] || {
  echo "Нет Rust (rustup). Установите: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh  (или https://rustup.rs)"; exit 1; }

# Файлы, удалённые из проекта, но оставшиеся после распаковки архива поверх
# папки, — убрать (как scripts/remove_stale_files.ps1 на Windows).
bash scripts/remove_stale_files.sh

PB=/usr/libexec/PlistBuddy
plist_set() { # файл ключ тип значение
  "$PB" -c "Set :$2 $4" "$1" 2>/dev/null || "$PB" -c "Add :$2 $3 $4" "$1"
}

setup() {
  if [[ ! -d macos ]]; then
    echo "▶ Создаю папку macos/ (flutter create)…"
    flutter config --enable-macos-desktop >/dev/null
    flutter create --platforms=macos --org com.ogneliss --project-name ogneliss . >/dev/null
  fi

  # Значок программы вместо стандартного значка Flutter (1.10.5).
  cp assets/branding/macos/app_icon_*.png macos/Runner/Assets.xcassets/AppIcon.appiconset/
  # Окно с переводом писем (Apple Translation, macOS 15+, 1.11.0).
  cp tool/desktop/macos/MainFlutterWindow.swift macos/Runner/MainFlutterWindow.swift

  echo "▶ Права приложения (песочница Mac App Store)…"
  for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    [[ -f "$f" ]] || continue
    plist_set "$f" com.apple.security.app-sandbox bool true
    plist_set "$f" com.apple.security.network.client bool true             # почтовые серверы
    plist_set "$f" com.apple.security.files.user-selected.read-write bool true  # вложения: открыть/сохранить
    plist_set "$f" com.apple.security.files.downloads.read-write bool true
    plist_set "$f" com.apple.security.print bool true                      # печать письма
    # Связка ключей (пароли ящиков, flutter_secure_storage): своя группа.
    "$PB" -c "Delete :keychain-access-groups" "$f" 2>/dev/null || true
    "$PB" -c "Add :keychain-access-groups array" "$f"
    "$PB" -c "Add :keychain-access-groups:0 string \$(AppIdentifierPrefix)com.ogneliss.mail" "$f"
  done

  echo "▶ Info.plist: категория, вход через OAuth (com.ogneliss.mail://oauth)…"
  local info=macos/Runner/Info.plist
  plist_set "$info" LSApplicationCategoryType string public.app-category.productivity
  "$PB" -c "Delete :CFBundleURLTypes" "$info" 2>/dev/null || true
  "$PB" -c "Add :CFBundleURLTypes array" "$info"
  "$PB" -c "Add :CFBundleURLTypes:0 dict" "$info"
  "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLName string com.ogneliss.mail.oauth" "$info"
  "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$info"
  "$PB" -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string com.ogneliss.mail" "$info"

  echo "▶ Имя и идентификатор (как у iPhone — одна запись в App Store Connect для universal purchase)…"
  local cfg=macos/Runner/Configs/AppInfo.xcconfig
  if [[ -f "$cfg" ]]; then
    sed -i '' -E 's/^PRODUCT_NAME = .*/PRODUCT_NAME = Ogneliss Mail/' "$cfg"
    sed -i '' -E 's/^PRODUCT_BUNDLE_IDENTIFIER = .*/PRODUCT_BUNDLE_IDENTIFIER = com.ogneliss.mail/' "$cfg"
    grep -q '^PRODUCT_COPYRIGHT' "$cfg" && sed -i '' -E 's/^PRODUCT_COPYRIGHT = .*/PRODUCT_COPYRIGHT = © Ogneliss/' "$cfg"
  fi

  echo "▶ Минимальная macOS — 11.0 (нужно редактору письма и уведомлениям)…"
  [[ -f macos/Podfile ]] && sed -i '' -E "s/^#? *platform :osx, '[0-9.]+'/platform :osx, '11.0'/" macos/Podfile
  sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = [0-9.]+;/MACOSX_DEPLOYMENT_TARGET = 11.0;/g' macos/Runner.xcodeproj/project.pbxproj

  echo "✓ macOS настроен. Команду разработчика выберите один раз в Xcode:"
  echo "  open macos/Runner.xcworkspace → Runner → Signing & Capabilities → Team."
}

prepare() {
  [[ -d macos ]] || setup
  # Шаги — с выводом и понятной ошибкой: 09.11.2026 pod install с выводом в
  # /dev/null падал молча, и скрипт заканчивался сразу после build_runner.
  echo "▶ Пакеты (flutter pub get)…"
  flutter pub get || { echo "✗ flutter pub get не прошёл — ошибка выше."; exit 1; }
  # Код базы — всегда заново, под установленную версию drift (см. build_ios.sh).
  # «W These options have been removed … --delete-conflicting-outputs» —
  # предупреждение нового build_runner, не ошибка (старые без ключа спрашивают).
  echo "▶ Код базы (build_runner)…"
  dart run build_runner build --delete-conflicting-outputs || { echo "✗ build_runner не прошёл — ошибка выше."; exit 1; }
  echo "▶ CocoaPods (pod install)…"
  if ! (cd macos && pod install --repo-update); then
    echo "✗ pod install не прошёл — причина в строках с [!] выше."
    echo "  Частое: «required a higher minimum deployment target» — поднимите platform :osx в macos/Podfile;"
    echo "  «CDN: trunk … failed» — нет сети до cdn.cocoapods.org, повторите позже."
    exit 1
  fi
}

DEFINES=()
if [[ -f config/dart_defines.json ]]; then
  DEFINES=(--dart-define-from-file=config/dart_defines.json)
else
  echo "⚠ config/dart_defines.json нет — вход через Google/Яндекс работать не будет (Exchange и IMAP — да)."
fi

# Архив для Mac App Store (TestFlight) — 08.11.2026, просьба владельца
# «как отправить в TestFlight сборку для macOS (Intel и M)».
ARCHIVE=build/macos/archive/Runner.xcarchive
AUTH=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  KEYFILE="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
  [[ -f "$KEYFILE" ]] || { echo "Нет файла ключа $KEYFILE"; exit 1; }
  AUTH=(-authenticationKeyPath "$KEYFILE" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

team_id() {
  if [[ -n "${TEAM_ID:-}" ]]; then echo "$TEAM_ID"; return; fi
  sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$HOME/.ogneliss/ios_signing.xcconfig" 2>/dev/null | head -1 || true
}

archive_mac() {
  prepare
  if [[ -n "${KEYCHAIN_PASSWORD:-}" ]]; then
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
  fi
  # Rust (ядро перетаскивания вложений) — для обеих архитектур Mac.
  if command -v rustup >/dev/null 2>&1; then
    rustup target add aarch64-apple-darwin x86_64-apple-darwin >/dev/null || true
  fi
  # Версия, номер сборки и dart-define попадают в настройки Xcode (Flutter/ephemeral).
  flutter build macos --release ${DEFINES[@]+"${DEFINES[@]}"}
  local team
  team=$(team_id)
  [[ -n "$team" ]] || echo "⚠ Команда не задана: --team ABCDE12345 или Team в Xcode (Signing & Capabilities)."
  rm -rf "$ARCHIVE"
  echo "▶ Архив (Intel + Apple Silicon)…"
  xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ${team:+DEVELOPMENT_TEAM=$team} \
    -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} archive
  local app bin archs
  app=$(ls -d "$ARCHIVE"/Products/Applications/*.app | head -1)
  bin="$app/Contents/MacOS/$("$PB" -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
  archs=$(lipo -archs "$bin")
  echo "Архитектуры: $archs"
  if [[ "$archs" != *x86_64* || "$archs" != *arm64* ]]; then
    echo "✗ Сборка не универсальная — на Mac с Intel или с M она не запустится."
    exit 1
  fi
  echo "✓ Архив: $ARCHIVE ($("$PB" -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")," \
    "сборка $("$PB" -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"))"
}

export_mac() { # $1: upload | export
  local team opts
  team=$(team_id)
  opts="$(mktemp -d)/ExportOptions.plist"
  cat > "$opts" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>signingStyle</key><string>automatic</string>
  ${team:+<key>teamID</key><string>$team</string>}
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$opts" \
    -exportPath build/macos/export -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}
}

case "$MODE" in
  setup) setup ;;
  archive)
    archive_mac
    echo "Открываю архив в Xcode: Distribute App → App Store Connect → Upload."
    open "$ARCHIVE" || true
    ;;
  upload)
    archive_mac
    echo "▶ Выгрузка в App Store Connect…"
    if export_mac upload; then
      echo "✓ Загружено: через 10–30 минут сборка появится в App Store Connect → TestFlight (macOS)."
    else
      echo "✗ Выгрузка не прошла. Архив готов — открываю в Xcode: Distribute App → App Store Connect."
      echo "  Частые причины: не выбрана команда; в App Store Connect у приложения нет платформы macOS"
      echo "  (карточка → «+» → macOS); номер сборки уже загружен (поднимите build в pubspec.yaml)."
      open "$ARCHIVE" || true
      exit 1
    fi
    ;;
  run) prepare; flutter run -d macos ${DEFINES[@]+"${DEFINES[@]}"} ;;
  build)
    prepare
    flutter build macos --release ${DEFINES[@]+"${DEFINES[@]}"}
    echo "✓ Готово: build/macos/Build/Products/Release/"
    echo "  Для Mac App Store: open macos/Runner.xcworkspace → Product → Archive."
    ;;
esac

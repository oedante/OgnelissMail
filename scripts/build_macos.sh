#!/usr/bin/env bash
# Сборка Ogneliss Mail для Mac (macOS 11+, Apple Silicon и Intel).
#
#   scripts/build_macos.sh --setup             один раз: создать папку macos/ и настроить её
#                                              (песочница, сеть, связка ключей, схема входа OAuth)
#   scripts/build_macos.sh --run               запуск на этом Mac (debug)
#   scripts/build_macos.sh                     сборка release → build/macos/Build/Products/Release/*.app
#
# Выгрузка в Mac App Store — через Xcode: macos/Runner.xcworkspace →
# Product → Archive → Distribute App → App Store Connect. Подробно —
# docs/guides/BUILD_ALL_PLATFORMS.md, раздел «Mac».
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
    *) echo "Неизвестный параметр: $1"; exit 2 ;;
  esac
  shift
done

[[ "$(uname)" == "Darwin" ]] || { echo "Сборка для Mac — только на macOS."; exit 1; }
command -v flutter >/dev/null || { echo "Flutter не найден (brew install --cask flutter)."; exit 1; }

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
  flutter pub get >/dev/null
  # Код базы — всегда заново, под установленную версию drift (см. build_ios.sh).
  dart run build_runner build --delete-conflicting-outputs
  (cd macos && pod install --repo-update >/dev/null)
}

DEFINES=()
if [[ -f config/dart_defines.json ]]; then
  DEFINES=(--dart-define-from-file=config/dart_defines.json)
else
  echo "⚠ config/dart_defines.json нет — вход через Google/Яндекс работать не будет (Exchange и IMAP — да)."
fi

case "$MODE" in
  setup) setup ;;
  run) prepare; flutter run -d macos ${DEFINES[@]+"${DEFINES[@]}"} ;;
  build)
    prepare
    flutter build macos --release ${DEFINES[@]+"${DEFINES[@]}"}
    echo "✓ Готово: build/macos/Build/Products/Release/"
    echo "  Для Mac App Store: open macos/Runner.xcworkspace → Product → Archive."
    ;;
esac

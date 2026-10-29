#!/usr/bin/env bash
# Сборка Ogneliss Mail для iPhone/iPad на Mac.
#
#   scripts/build_ios.sh --check              проверить окружение (Xcode, Flutter, CocoaPods)
#   scripts/build_ios.sh --run                запуск на iPhone (по кабелю/Wi-Fi) или в симуляторе
#   scripts/build_ios.sh                      IPA для TestFlight / App Store
#   scripts/build_ios.sh --upload             IPA и выгрузка в App Store Connect (TestFlight)
#   scripts/build_ios.sh --team ABCDE12345    запомнить команду разработчика (один раз)
#   scripts/build_ios.sh --prepare            только подготовить (pub get, pod install, подпись)
#                                             — дальше Product → Archive в Xcode
#
# Команда разработчика хранится ВНЕ проекта: ~/.ogneliss/ios_signing.xcconfig.
# Новый архив проекта её не затирает — при каждом запуске скрипт копирует её
# в ios/Flutter/Signing.xcconfig. Файл проекта Xcode (project.pbxproj) в архив
# не входит (там — project.pbxproj.base): настройки, сделанные в Xcode,
# сохраняются. Подробно — docs/guides/IOS_XCODE_SETUP.md.
#
# Переменные окружения (по желанию):
#   TEAM_ID            — команда разработчика (вместо --team)
#   ASC_KEY_ID, ASC_ISSUER_ID — ключ App Store Connect API для --upload; файл ключа
#                        ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
#   KEYCHAIN_PASSWORD  — пароль входа на Mac: при сборке по SSH (из Windows)
#                        связка ключей заблокирована, и подпись без неё не пройдёт.
# Секреты сборки — config/dart_defines.json (тот же файл, что для Android).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=build
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE=check ;;
    --run) MODE=run ;;
    --prepare) MODE=prepare ;;
    --upload) MODE=upload ;;
    --team) TEAM_ID="$2"; shift ;;
    *) echo "Неизвестный параметр: $1"; exit 2 ;;
  esac
  shift
done

say() { printf '\n== %s\n' "$*"; }
fail() { printf '\n✗ %s\n' "$*"; exit 1; }

say "Окружение"
xcodebuild -version >/dev/null 2>&1 || fail "Нет Xcode. App Store → Xcode, затем: sudo xcodebuild -license accept && xcodebuild -runFirstLaunch"
xcodebuild -version | head -1
command -v flutter >/dev/null || fail "Нет flutter в PATH (brew install --cask flutter или git clone -b stable https://github.com/flutter/flutter)"
FV=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')
echo "Flutter $FV"
case "$FV" in 3.3[89]*|3.[4-9]*|[4-9].*) ;; *) fail "Нужен Flutter 3.38 или новее (сейчас $FV): flutter upgrade" ;; esac
command -v pod >/dev/null || fail "Нет CocoaPods: brew install cocoapods"
echo "CocoaPods $(pod --version)"
xcrun simctl list runtimes 2>/dev/null | grep -q iOS || echo "⚠ Нет симулятора iOS: xcodebuild -downloadPlatform iOS"
[[ "$MODE" == check ]] && { flutter doctor -v | sed -n '1,40p'; exit 0; }

# Файлы, удалённые из проекта, но оставшиеся после распаковки архива поверх
# папки, — убрать (как scripts/remove_stale_files.ps1 на Windows).
bash scripts/remove_stale_files.sh

# Файл проекта Xcode: в архиве его нет (чтобы не затирать настройки Xcode),
# есть project.pbxproj.base. Новая папка — берём базовый.
PBX=ios/Runner.xcodeproj/project.pbxproj
if [[ ! -f "$PBX" && -f "$PBX.base" ]]; then
  cp "$PBX.base" "$PBX"
  echo "Файл проекта Xcode создан из project.pbxproj.base"
fi
if [[ -f "$PBX.base" ]]; then
  NEW=$(shasum -a 256 "$PBX.base" | cut -c1-16)
  OLD=$(cat ios/Runner.xcodeproj/.base_seen 2>/dev/null || true)
  if [[ -n "$OLD" && "$OLD" != "$NEW" ]]; then
    echo "⚠ В архиве изменился базовый файл проекта Xcode (project.pbxproj.base)."
    echo "  Ваш project.pbxproj не тронут; что поменялось и нужно ли переносить — CHANGELOG."
  fi
  echo "$NEW" > ios/Runner.xcodeproj/.base_seen
fi
# Языки iPhone (1.8.0): InfoPlist.strings и подписи виджетов на всех языках
# приложения — недостающие дописываются в проект Xcode (остальное в нём не
# трогается; копия прежнего — project.pbxproj.bak).
if [[ -f "$PBX" ]]; then
  python3 scripts/ios_localizations.py "$PBX" || echo "⚠ Языки iPhone не добавлены в проект Xcode — запустите: python3 scripts/ios_localizations.py"
fi

# Команда разработчика: ~/.ogneliss/ios_signing.xcconfig (вне проекта) →
# ios/Flutter/Signing.xcconfig (в git и архив не попадает).
KEEP="$HOME/.ogneliss/ios_signing.xcconfig"
if [[ -n "${TEAM_ID:-}" ]]; then
  mkdir -p "$(dirname "$KEEP")"
  printf 'DEVELOPMENT_TEAM = %s\nCODE_SIGN_STYLE = Automatic\n' "$TEAM_ID" > "$KEEP"
  echo "Команда разработчика: $TEAM_ID (сохранена в $KEEP)"
fi
if [[ -f "$KEEP" ]]; then
  cp "$KEEP" ios/Flutter/Signing.xcconfig
  grep DEVELOPMENT_TEAM "$KEEP" | sed 's/^/Подпись: /'
elif [[ -f ios/Flutter/Signing.xcconfig ]]; then
  # Файл от прежних версий скрипта — сохраняем его и вне проекта.
  mkdir -p "$(dirname "$KEEP")"
  cp ios/Flutter/Signing.xcconfig "$KEEP"
elif [[ ! -f ios/Flutter/Signing.xcconfig ]]; then
  echo "⚠ Команда не задана: укажите --team ABCDE12345 (developer.apple.com → Membership → Team ID)"
  echo "  или выберите Team в Xcode: ios/Runner.xcworkspace → Runner → Signing & Capabilities."
fi

# Сборка для App Store без Team не подпишется — останавливаемся сразу, а не
# после 10 минут сборки (симулятору и --prepare Team не нужен).
if [[ ( "$MODE" == build || "$MODE" == upload ) && ! -f ios/Flutter/Signing.xcconfig ]]; then
  fail "Сначала один раз: scripts/build_ios.sh --team ABCDE12345 --upload
  Team ID: developer.apple.com → Account → Membership details (10 символов)."
fi

# Пустой массив + set -u в bash 3.2 (macOS) — «unbound variable» (17.10):
# поэтому ниже массив раскрывается как ${DEFINES[@]+"${DEFINES[@]}"}.
DEFINES=()
if [[ -f config/dart_defines.json ]]; then
  DEFINES+=(--dart-define-from-file=config/dart_defines.json)
else
  echo "⚠ Нет config/dart_defines.json — вход через OAuth-прокси (Gmail, Яндекс, Mail.ru, Outlook) работать не будет"
fi

say "Зависимости"
flutter pub get
# Код базы (drift) — всегда заново, под установленную версию drift: файл,
# сгенерированный другой версией drift_dev, не собирается («Method not found:
# '$_getPrefetchedDataByColumns'», 29.10.2026 — в архиве лежал файл от drift
# 2.35.3, а на Mac стоял 2.35.2). Без изменений — секунды.
dart run build_runner build --delete-conflicting-outputs
(cd ios && pod install --repo-update)

if [[ -n "${KEYCHAIN_PASSWORD:-}" ]]; then
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
fi

if [[ "$MODE" == prepare ]]; then
  # Версия, номер сборки и dart-define — в Generated.xcconfig, как при flutter build.
  flutter build ios --config-only --release ${DEFINES[@]+"${DEFINES[@]}"}
  say "Готово к сборке в Xcode"
  echo "open ios/Runner.xcworkspace → схема Runner, Any iOS Device (arm64) → Product → Archive"
  exit 0
fi

if [[ "$MODE" == run ]]; then
  say "Запуск"
  # Устройство: DEVICE=<id или имя> (iPhone по кабелю — см. flutter devices);
  # иначе — симулятор iPhone: запущенный или первый доступный (в Xcode 26 —
  # iPhone 17…, «iPhone 16» может не быть).
  DEV=()
  if [[ -n "${DEVICE:-}" ]]; then
    DEV=(-d "$DEVICE")
  else
    xcrun simctl list runtimes 2>/dev/null | grep -q '^iOS' ||
      fail "Нет симулятора iOS: xcodebuild -downloadPlatform iOS (несколько ГБ), затем снова --run"
    SIM=$(xcrun simctl list devices booted | grep -E '^ +iP(hone|ad)' | grep -Eo '[0-9A-F-]{36}' | head -1 || true)
    if [[ -z "$SIM" ]]; then
      SIM=$(xcrun simctl list devices available | grep -E '^ +iPhone' | grep -Eo '[0-9A-F-]{36}' | head -1 || true)
      [[ -n "$SIM" ]] || fail "Нет симулятора iPhone: Xcode → Window → Devices and Simulators → Simulators → +"
      xcrun simctl boot "$SIM" || true
    fi
    open -a Simulator || true
    echo "Симулятор: $(xcrun simctl list devices | grep "$SIM" | sed 's/^ *//')"
    DEV=(-d "$SIM")
  fi
  flutter run "${DEV[@]}" ${DEFINES[@]+"${DEFINES[@]}"}
  exit 0
fi

say "Сборка IPA $(grep '^version:' pubspec.yaml | awk '{print $2}')"
# Архив собирает flutter. Подпись и IPA — xcodebuild с -allowProvisioningUpdates:
# автоматическая подпись сама создаёт сертификат распространения и профиль.
# У «flutter build ipa» без этого архив собирался, а подпись падала
# («No signing certificate "iOS Distribution"», 17.10.2026) — и сборку
# приходилось загружать из Xcode, где AppDelegate не находил модули плагинов.
ARCHIVE=build/ios/archive/Runner.xcarchive
rm -rf "$ARCHIVE" build/ios/ipa
flutter build ipa --release ${DEFINES[@]+"${DEFINES[@]}"} || true
[[ -d "$ARCHIVE" ]] || fail "Архив не собран — ошибка выше (это не подпись)"

TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' ios/Flutter/Signing.xcconfig 2>/dev/null | head -1 || true)
export_archive() { # $1: export | upload
  local opts
  opts="$(mktemp -d)/ExportOptions.plist"
  cat > "$opts" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>signingStyle</key><string>automatic</string>
  ${TEAM:+<key>teamID</key><string>$TEAM</string>}
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$opts" \
    -exportPath build/ios/ipa -allowProvisioningUpdates
}
organizer_hint() {
  echo "Архив готов: $ARCHIVE — открываю в Xcode (Organizer)."
  echo "Там: Distribute App → App Store Connect → Upload. Собирать заново в Xcode не нужно."
  open "$ARCHIVE" || true
}

IPA=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
if [[ -z "$IPA" ]]; then
  say "Подпись (xcodebuild -exportArchive)"
  [[ -n "$TEAM" ]] || echo "⚠ Команда не задана: scripts/build_ios.sh --team ABCDE12345"
  export_archive export || { organizer_hint; fail "Подпись не прошла: войдите в Apple ID команды в Xcode → Settings → Accounts"; }
  IPA=$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
fi
[[ -n "$IPA" ]] && echo "Готово: $IPA"

if [[ "$MODE" == upload ]]; then
  say "Выгрузка в App Store Connect"
  if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
    xcrun altool --upload-app -t ios -f "$IPA" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  else
    # Без ключа API — учётной записью Xcode (Settings → Accounts).
    export_archive upload || { organizer_hint; fail "Выгрузка не прошла"; }
  fi
  echo "Сборка загружена: через 10–30 минут она появится в App Store Connect → TestFlight."
else
  echo "Загрузка: scripts/build_ios.sh --upload, приложение Transporter (перетащить IPA)"
  echo "или open $ARCHIVE → Distribute App."
fi

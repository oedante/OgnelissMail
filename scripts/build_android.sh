#!/usr/bin/env bash
# Сборка Ogneliss Mail для Android на Mac или Linux (на Windows —
# build_android.bat в корне проекта, то же самое).
#
#   scripts/build_android.sh                  App Bundle и APK (release)
#   scripts/build_android.sh --aab            только App Bundle (Google Play)
#   scripts/build_android.sh --apk            только APK (установка вручную)
#   scripts/build_android.sh --run            запуск на телефоне или эмуляторе
#                                             (DEVICE=<id> — какое устройство)
#   scripts/build_android.sh --clean          flutter clean перед сборкой
#   scripts/build_android.sh --test           и тесты перед сборкой
#   scripts/build_android.sh --keep-lock      не обновлять версии пакетов
#   scripts/build_android.sh --skip-analyze   без flutter analyze
#
# Пакеты — те же версии, что в проверочной сборке на GitHub (flutter pub
# upgrade): pubspec.lock в архив не входит, а прежний держал старые версии —
# 08.11.2026 закреплённый archive 4.5.2 сломал сборку («writeRange isn't
# defined in a superclass»). --keep-lock — свои версии (flutter pub get).
#
# Ключ подписи — android/key.properties (scripts/create_upload_key.ps1 или
# вручную, см. android/app/build.gradle.kts); без него release подписывается
# отладочным ключом. Секреты сборки — config/dart_defines.json.
# Готовые файлы с номером версии — build/out/, журнал — build/logs/.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET=both
MODE=build
CLEAN=0
TEST=0
KEEP_LOCK=0
ANALYZE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) TARGET=aab ;;
    --apk) TARGET=apk ;;
    --run) MODE=run ;;
    --clean) CLEAN=1 ;;
    --test) TEST=1 ;;
    --keep-lock) KEEP_LOCK=1 ;;
    --skip-analyze) ANALYZE=0 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "Неизвестный параметр: $1"; exit 2 ;;
  esac
  shift
done

mkdir -p build/logs build/out
STAMP=$(date +%Y%m%d_%H%M%S)
LOG="build/logs/build_android_$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

say() { printf '\n== %s\n' "$*"; }
warn() { printf '!! %s\n' "$*"; }
fail() { printf '\n✗ %s\nПолный журнал: %s\n' "$*" "$LOG"; exit 1; }
# Упала команда (flutter, dart) — где искать подробности.
trap 'printf "\n✗ Сборка остановилась (код %s). Полный журнал: %s\n" "$?" "$LOG"' ERR

VER=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "Ogneliss Mail $VER — сборка для Android"

# Файлы, удалённые из проекта, но оставшиеся после распаковки архива поверх
# папки, — убрать: иначе flutter analyze находит ошибки в несуществующем коде.
bash scripts/remove_stale_files.sh

say "Окружение"
command -v flutter >/dev/null || fail "Нет flutter в PATH (docs/guides/QUICKSTART.md)"
FV=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')
echo "Flutter $FV"
case "$FV" in 3.3[89]*|3.[4-9]*|[4-9].*) ;; *) fail "Нужен Flutter 3.38 или новее (сейчас $FV): flutter upgrade" ;; esac
# Rust (rustup) — ядро перетаскивания вложений (super_drag_and_drop) собирается
# из исходников и для Android; версию Rust и цели Android rustup скачает сам.
command -v rustup >/dev/null 2>&1 || [ -x "$HOME/.cargo/bin/rustup" ] ||
  fail "Нет Rust (rustup): curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh  (или https://rustup.rs)"
echo "Rust (rustup) найден"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK" ]]; then
  for d in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do [[ -d "$d" ]] && { SDK="$d"; break; }; done
fi
if [[ -n "$SDK" && -d "$SDK" ]]; then
  echo "Android SDK: $SDK"
  [[ -d "$SDK/ndk" ]] || warn "В Android SDK нет NDK (Android Studio → SDK Manager → SDK Tools → NDK): без него не соберутся шифрованная база и ядро на Rust"
else
  warn "Android SDK не найден (ANDROID_HOME) — проверьте: flutter doctor"
fi
if [[ "$MODE" == build ]]; then
  if [[ -f android/key.properties ]]; then
    echo "Подпись: ключ загрузки (android/key.properties)"
  else
    warn "Нет android/key.properties — сборка будет подписана отладочным ключом (не для Google Play)"
  fi
fi

if [[ "$CLEAN" == 1 ]]; then
  say "flutter clean"
  flutter clean
fi

if [[ "$KEEP_LOCK" == 1 ]]; then
  say "Пакеты: flutter pub get (свои версии из pubspec.lock)"
  flutter pub get
else
  say "Пакеты: flutter pub upgrade (те же версии, что в сборке на GitHub)"
  flutter pub upgrade
fi

say "Код базы (drift / build_runner)"
# --delete-conflicting-outputs: файл от другой версии drift не собирается.
dart run build_runner build --delete-conflicting-outputs
[[ -f lib/data/database/app_database.g.dart ]] || fail "app_database.g.dart не сгенерирован — ошибки build_runner выше"

if [[ "$ANALYZE" == 1 ]]; then
  say "flutter analyze (отчёт: build/logs/analyze_$STAMP.txt)"
  AN="build/logs/analyze_$STAMP.txt"
  flutter analyze --no-fatal-infos --no-fatal-warnings > "$AN" 2>&1 || true
  tail -15 "$AN"
  ERRS=$(grep -cE '^\s*error ' "$AN" || true)
  if [[ "$ERRS" != 0 ]]; then warn "Ошибок анализатора: $ERRS — сборка, скорее всего, не пройдёт. Пришлите $AN"; else echo "Ошибок анализатора нет"; fi
fi

# native_toolchain_rust 1.0.6 пишет «[SEVERE] RustBuilder: Failed to find
# lib.name … type 'Null' is not a subtype of type 'String'», когда в Cargo.toml
# нет lib.name, — и берёт package.name. Это не ошибка, сборка идёт дальше.
RUST_NOTE="Сообщения «[SEVERE] RustBuilder: Failed to find lib.name …» — не ошибка, сборка продолжается."

if [[ "$TEST" == 1 ]]; then
  say "flutter test"
  echo "$RUST_NOTE"
  flutter test
fi

DEFINES=()
if [[ -f config/dart_defines.json ]]; then
  DEFINES+=(--dart-define-from-file=config/dart_defines.json)
else
  warn "Нет config/dart_defines.json — вход через OAuth-прокси (Gmail, Яндекс, Mail.ru, Outlook) работать не будет"
fi

if [[ "$MODE" == run ]]; then
  say "flutter run"
  echo "$RUST_NOTE"
  DEV=()
  [[ -n "${DEVICE:-}" ]] && DEV=(-d "$DEVICE")
  # Пустой массив + set -u в bash 3.2 (macOS) — «unbound variable»: раскрытие
  # ${A[@]+"${A[@]}"}.
  flutter run ${DEV[@]+"${DEV[@]}"} ${DEFINES[@]+"${DEFINES[@]}"}
  exit $?
fi

OUT=()
if [[ "$TARGET" == both || "$TARGET" == aab ]]; then
  say "flutter build appbundle --release"
  echo "$RUST_NOTE"
  flutter build appbundle --release ${DEFINES[@]+"${DEFINES[@]}"}
  AAB=build/app/outputs/bundle/release/app-release.aab
  [[ -f "$AAB" ]] || fail "Нет $AAB — ошибка в выводе сборки выше"
  cp "$AAB" "build/out/ogneliss-mail-$VER.aab"
  OUT+=("build/out/ogneliss-mail-$VER.aab")
fi
if [[ "$TARGET" == both || "$TARGET" == apk ]]; then
  say "flutter build apk --release"
  echo "$RUST_NOTE"
  flutter build apk --release ${DEFINES[@]+"${DEFINES[@]}"}
  APK=build/app/outputs/flutter-apk/app-release.apk
  [[ -f "$APK" ]] || fail "Нет $APK — ошибка в выводе сборки выше"
  cp "$APK" "build/out/ogneliss-mail-$VER.apk"
  OUT+=("build/out/ogneliss-mail-$VER.apk")
fi

echo
for f in "${OUT[@]}"; do echo "Готово: $PWD/$f ($(du -h "$f" | cut -f1))"; done
echo "App Bundle (.aab) — в Google Play Console; APK — установка на телефон вручную."
echo "Журнал сборки: $LOG"

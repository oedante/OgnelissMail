#!/usr/bin/env bash
# Архив проекта для владельца (HANDOFF, правило 1): <OUT>/ogneliss-mail-<версия>.zip,
# внутри — папка ogneliss-mail (как у владельца). OUT — первый параметр, по
# умолчанию build/out.
#
#   tool/dev/make_archive.sh [OUT]
#
# Источник — коммит HEAD (git archive): только файлы из git — без сборки,
# кэшей, сгенерированного кода и секретов (config/dart_defines.json,
# key.properties, *.jks, ключи APNs *.p8, .env служб, файлы Firebase).
#
# Не входят и файлы, которые Xcode меняет у владельца при настройке подписи
# (1.6.12): project.pbxproj (Team, App Groups, Push, цель виджетов),
# Runner.entitlements, Signing.xcconfig, xcuserdata, contents.xcworkspacedata
# (его ведёт pod install). Файл проекта Xcode кладётся как
# project.pbxproj.base — для новой папки (scripts/build_ios.sh берёт его, если
# project.pbxproj нет).
#
# 29.10.2026: архивы 1.8.8–1.8.12 собирались мимо этого скрипта (git archive
# целиком) — project.pbxproj из git затёр у владельца настройки Xcode. Скрипт
# теперь работает из любой копии репозитория, а не только из /home/claude/src.
#
# 1.10.5 (замечание владельца 03.11.2026: «в папке ios перезаписываются файлы
# проекта Xcode — может, не добавлять их туда?»): и остальные файлы, которые
# Xcode ведёт сам, — схема сборки, настройки рабочих пространств, права
# виджетов (OgnelissWidgets.entitlements) — лежат в архиве не на своих
# местах, а в ios/xcode-base/ (тот же путь внутри). Распаковка поверх папки
# их не трогает; scripts/build_ios.sh берёт копию из xcode-base, только если
# своего файла нет (новая папка).
#
# Код базы (app_database.g.dart) в архив не кладётся: его генерирует
# build_runner под установленную версию drift (scripts/build_ios.sh,
# build_windows.ps1, setup.sh) — файл от другой версии drift не собирается.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/build/out}"
cd "$ROOT"
python3 tool/dev/removed_files.py >/dev/null
VER=$(grep '^version:' pubspec.yaml | awk '{print $2}')
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
ZIP="$OUT/ogneliss-mail-$VER.zip"
rm -f "$OUT"/ogneliss-mail-*.zip

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git archive --prefix=ogneliss-mail/ HEAD | tar -x -C "$TMP"
P="$TMP/ogneliss-mail"
# Список удалённых файлов — свежий (только что обновлён, мог быть не закоммичен).
cp tool/dev/removed_files.txt "$P/tool/dev/removed_files.txt"

# Проект Xcode — под именем .base; настройки Xcode владельца — не трогаем.
mv "$P/ios/Runner.xcodeproj/project.pbxproj" "$P/ios/Runner.xcodeproj/project.pbxproj.base"
rm -f "$P/ios/Runner.xcodeproj/.base_seen" "$P/ios/Runner.xcodeproj/project.pbxproj.bak" \
  "$P/ios/Runner/Runner.entitlements" "$P/ios/Flutter/Signing.xcconfig" \
  "$P/ios/Runner.xcworkspace/contents.xcworkspacedata"
find "$P" -name xcuserdata -prune -exec rm -rf {} +
# Файлы, которые Xcode ведёт сам, — в ios/xcode-base/ (см. выше).
XB="$P/ios/xcode-base"
for f in Runner.xcodeproj/project.xcworkspace Runner.xcodeproj/xcshareddata \
         Runner.xcworkspace/xcshareddata OgnelissWidgets/OgnelissWidgets.entitlements; do
  if [[ -e "$P/ios/$f" ]]; then
    mkdir -p "$XB/$(dirname "$f")"
    mv "$P/ios/$f" "$XB/$f"
  fi
done
rmdir "$P/ios/Runner.xcworkspace" 2>/dev/null || true
# Секреты — на случай, если когда-нибудь окажутся в git.
rm -f "$P/config/dart_defines.json"
find "$P" \( -name key.properties -o -name '*.jks' -o -name '*.p8' -o -name .env \
  -o -name google-services.json -o -name GoogleService-Info.plist \) -delete
rm -rf "$P/server/push-relay/data" "$P/server/push-relay/keys"

(cd "$TMP" && zip -qr -X "$ZIP" ogneliss-mail)

BASE=$(unzip -l "$ZIP" | grep -c "project.pbxproj.base$" || true)
[[ "$BASE" == 1 ]] || { echo "✗ в архиве нет ios/Runner.xcodeproj/project.pbxproj.base"; exit 1; }
SECRETS=$(unzip -l "$ZIP" | grep -c "dart_defines.json$\|key.properties\|\.jks$\|\.p8$\|/\.env$" || true)
XCODE=$(unzip -l "$ZIP" | grep -v "/ios/xcode-base/" | grep -c "project.pbxproj$\|Runner.entitlements\|Signing.xcconfig\|xcuserdata\|Runner.xcworkspace/contents.xcworkspacedata\|xcshareddata\|project.xcworkspace\|OgnelissWidgets.entitlements" || true)
GEN=$(unzip -l "$ZIP" | grep -c "app_database.g.dart" || true)
echo "$ZIP"
echo "секретов в архиве: $SECRETS; файлов настройки Xcode: $XCODE; сгенерированного кода базы: $GEN"
[[ "$SECRETS" == 0 && "$XCODE" == 0 && "$GEN" == 0 ]] || { echo "✗ архив не годится"; exit 1; }

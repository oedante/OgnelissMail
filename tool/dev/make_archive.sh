#!/usr/bin/env bash
# Архив проекта для владельца (HANDOFF, правило 1): /home/claude/out/ogneliss-mail-<версия>.zip
#
# Не входят: секреты (config/dart_defines.json, key.properties, *.jks, ключи APNs
# *.p8, .env служб, файлы Firebase), сборка,
# кэши и файлы, которые Xcode меняет у владельца при настройке подписи
# (1.6.12): project.pbxproj (Team, App Groups, цель виджетов), Runner.entitlements,
# Signing.xcconfig, xcuserdata, contents.xcworkspacedata (его ведёт pod install).
# Файл проекта Xcode кладётся рядом как project.pbxproj.base — для новой папки
# (scripts/build_ios.sh берёт его, если project.pbxproj нет).
set -euo pipefail
SRC=/home/claude/src
OUT=/home/claude/out
cd "$SRC/ogneliss-mail"
python3 tool/dev/removed_files.py >/dev/null
VER=$(grep '^version:' pubspec.yaml | awk '{print $2}')
ZIP="$OUT/ogneliss-mail-$VER.zip"
mkdir -p "$OUT"
rm -f "$OUT"/ogneliss-mail-*.zip
cd "$SRC"
zip -qr "$ZIP" ogneliss-mail -x 'ogneliss-mail/build/*' 'ogneliss-mail/.dart_tool/*' 'ogneliss-mail/.git/*' \
  '*/node_modules/*' 'ogneliss-mail/ios/Pods/*' 'ogneliss-mail/config/dart_defines.json' \
  '*/__pycache__/*' '*.pyc' 'ogneliss-mail/site/dist/*' \
  '*/key.properties' '*.jks' '*.p8' '*/.env' '*/google-services.json' '*/GoogleService-Info.plist' \
  'ogneliss-mail/server/push-relay/data/*' 'ogneliss-mail/server/push-relay/keys/*' \
  'ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj' 'ogneliss-mail/ios/Runner.xcodeproj/.base_seen' \
  'ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj.bak' \
  'ogneliss-mail/ios/Runner/Runner.entitlements' 'ogneliss-mail/ios/Flutter/Signing.xcconfig' \
  'ogneliss-mail/ios/Runner.xcworkspace/contents.xcworkspacedata' '*/xcuserdata/*'
# Свежий project.pbxproj (если он есть в рабочей папке) — под именем .base;
# если его нет, в архиве остаётся уже лежащий рядом project.pbxproj.base.
if [[ -f ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj ]]; then
  TMP=$(mktemp -d)
  mkdir -p "$TMP/ogneliss-mail/ios/Runner.xcodeproj"
  cp ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj "$TMP/ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj.base"
  (cd "$TMP" && zip -q "$ZIP" ogneliss-mail/ios/Runner.xcodeproj/project.pbxproj.base)
  rm -rf "$TMP"
fi
BASE=$(unzip -l "$ZIP" | grep -c "project.pbxproj.base$" || true)
[[ "$BASE" == 1 ]] || { echo "✗ в архиве нет ios/Runner.xcodeproj/project.pbxproj.base"; exit 1; }
SECRETS=$(unzip -l "$ZIP" | grep -c "dart_defines.json\|key.properties\|\.jks\|\.p8$\|/\.env$" || true)
XCODE=$(unzip -l "$ZIP" | grep -c "project.pbxproj$\|Runner.entitlements\|Signing.xcconfig\|xcuserdata" || true)
echo "$ZIP"
echo "секретов в архиве: $SECRETS; файлов настройки Xcode: $XCODE"
[[ "$SECRETS" == 0 && "$XCODE" == 0 ]] || { echo "✗ архив не годится"; exit 1; }

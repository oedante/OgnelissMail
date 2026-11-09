#!/usr/bin/env bash
# Движок перевода для Windows (2.2.0): Bergamot Translator из npm
# (@browsermt/bergamot-translator, MPL-2.0) — в build/bergamot, откуда
# tool/bergamot/bergamot.cmake кладёт его рядом с exe (data\bergamot).
# Пакет и файлы сверяются с tool/bergamot/engine.sha256: другой файл —
# ошибка. Файлы не меняются; рядом — тексты лицензий.
#
#   bash tool/bergamot/fetch_engine.sh                 — скачать (из корня проекта)
#   bash tool/bergamot/fetch_engine.sh ПАКЕТ.tgz       — из файла
#
# Запускает .github/workflows/ci.yml (build-windows); на компьютере
# владельца — tool/bergamot/fetch_engine.ps1 (scripts/build_windows.ps1).
set -euo pipefail

HERE="tool/bergamot"
[ -f "$HERE/engine.sha256" ] || { echo "Bergamot: запускайте из корня проекта" >&2; exit 2; }
OUT="${BERGAMOT_OUT:-build/bergamot}"
TGZ_NAME="$(awk '/\.tgz$/ {print $2}' "$HERE/engine.sha256")"
VERSION="${TGZ_NAME#bergamot-translator-}"; VERSION="${VERSION%.tgz}"
URL="https://registry.npmjs.org/@browsermt/bergamot-translator/-/$TGZ_NAME"

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
want() { awk -v f="$1" '$2 == f {print $1}' "$HERE/engine.sha256"; }

complete() {
  local f
  for f in $(awk '$2 ~ /^package\// {print $2}' "$HERE/engine.sha256"); do
    [ -f "$OUT/${f#package/}" ] && [ "$(sha "$OUT/${f#package/}")" = "$(want "$f")" ] || return 1
  done
  [ -f "$OUT/LICENSE-MPL-2.0.txt" ] && [ -f "$OUT/THIRD-PARTY-NOTICES.txt" ]
}

if complete; then echo "Bergamot $VERSION: уже на месте ($OUT)"; exit 0; fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if [ -n "${1:-}" ]; then
  cp "$1" "$TMP/$TGZ_NAME"
else
  echo "Bergamot $VERSION: $URL"
  curl -fsSL --retry 4 --retry-delay 2 -o "$TMP/$TGZ_NAME" "$URL"
fi
[ "$(sha "$TMP/$TGZ_NAME")" = "$(want "$TGZ_NAME")" ] || { echo "Bergamot: sha256 пакета не совпал" >&2; exit 1; }
mkdir -p "$TMP/x"
tar -xzf "$TMP/$TGZ_NAME" -C "$TMP/x"
rm -rf "$OUT.tmp"; mkdir -p "$OUT.tmp/worker"
for f in $(awk '$2 ~ /^package\// {print $2}' "$HERE/engine.sha256"); do
  [ "$(sha "$TMP/x/$f")" = "$(want "$f")" ] || { echo "Bergamot: sha256 $f не совпал" >&2; exit 1; }
  cp "$TMP/x/$f" "$OUT.tmp/${f#package/}"
done
cp "$HERE/LICENSE-MPL-2.0.txt" "$HERE/THIRD-PARTY-NOTICES.txt" "$OUT.tmp/"
rm -rf "$OUT"; mkdir -p "$(dirname "$OUT")"; mv "$OUT.tmp" "$OUT"
echo "Bergamot $VERSION: $OUT"

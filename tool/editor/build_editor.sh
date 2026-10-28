#!/usr/bin/env bash
# Сборка редактора писем (HugeRTE) в assets/editor/.
#
#   npm pack hugerte@1.0.14 && tar xzf hugerte-1.0.14.tgz      → ./package
#   npm pack tinymce-i18n && tar xzf tinymce-i18n-*.tgz -C i18n → ./i18n/package
#   tool/editor/build_editor.sh ./package ./i18n/package
#
# Результат — плоская папка без подкаталогов (Flutter не включает подпапки
# assets автоматически):
#   hugerte.bundle.js  ядро + модель + тема + иконки + плагины + языки
#   skin.css / skin-dark.css               оформление панели (oxide)
#   content.css / content-dark.css         оформление текста в редакторе
#   LICENSE-hugerte.txt                    лицензия MIT
# Мост с приложением — assets/editor/bridge.js (пишется вручную).
#
# Языки — пакеты TinyMCE 6 (лицензия MIT, как у TinyMCE 6) из tinymce-i18n,
# вызов tinymce.addI18n заменяется на hugerte.addI18n.
set -euo pipefail
PKG="${1:?путь к пакету hugerte}"
I18N="${2:?путь к пакету tinymce-i18n}"
OUT="$(cd "$(dirname "$0")/../.." && pwd)/assets/editor"
mkdir -p "$OUT"

PLUGINS="lists advlist link autolink table charmap searchreplace"
{
  cat "$PKG/hugerte.min.js"; echo
  cat "$PKG/models/dom/model.min.js"; echo
  cat "$PKG/themes/silver/theme.min.js"; echo
  cat "$PKG/icons/default/icons.min.js"; echo
  for p in $PLUGINS; do cat "$PKG/plugins/$p/plugin.min.js"; echo; done
  for l in ru de fr_FR; do
    sed 's/^tinymce\.addI18n(/hugerte.addI18n(/' "$I18N/langs6/$l.js"; echo
  done
} > "$OUT/hugerte.bundle.js"

cp "$PKG/skins/ui/oxide/skin.min.css" "$OUT/skin.css"
cp "$PKG/skins/ui/oxide-dark/skin.min.css" "$OUT/skin-dark.css"
cat "$PKG/skins/ui/oxide/content.min.css" "$PKG/skins/content/default/content.min.css" > "$OUT/content.css"
cat "$PKG/skins/ui/oxide-dark/content.min.css" "$PKG/skins/content/dark/content.min.css" > "$OUT/content-dark.css"
cp "$PKG/license.txt" "$OUT/LICENSE-hugerte.txt"

grep -q 'hugerte.addI18n("ru"' "$OUT/hugerte.bundle.js" || { echo "нет русского языка" >&2; exit 1; }
ls -la "$OUT"

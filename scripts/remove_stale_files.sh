#!/usr/bin/env bash
# Удаляет файлы, которые убраны из проекта, но остались в папке после
# распаковки нового архива поверх старого (распаковка только добавляет и
# заменяет файлы). То же, что scripts/remove_stale_files.ps1 на Windows.
# Список — tool/dev/removed_files.txt (обновляется при каждой сборке архива).
# Запуск из любой папки:  bash scripts/remove_stale_files.sh
set -euo pipefail
cd "$(dirname "$0")/.."
LIST=tool/dev/removed_files.txt
[[ -f "$LIST" ]] || exit 0
removed=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line=${line%$'\r'}
  [[ -z "$line" || "$line" == \#* ]] && continue
  # Только пути внутри проекта.
  [[ "$line" == /* || "$line" == *..* ]] && continue
  if [[ -f "$line" ]]; then
    rm -f -- "$line"
    echo "удалён: $line"
    removed=$((removed + 1))
  fi
done < "$LIST"
[[ $removed -gt 0 ]] && echo "Устаревших файлов удалено: $removed"
exit 0

# Удаляет файлы, которые убраны из проекта, но остались в папке после
# распаковки нового архива поверх старого (распаковка только добавляет и
# заменяет файлы). Без этого flutter analyze и flutter test находят ошибки в
# уже несуществующем коде.
# Запуск из корня проекта:  powershell -ExecutionPolicy Bypass -File scripts\remove_stale_files.ps1
$root = Split-Path -Parent $PSScriptRoot
$list = Join-Path $root 'tool\dev\removed_files.txt'
$removed = 0
Get-Content $list -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') } | ForEach-Object {
    $path = Join-Path $root ($_ -replace '/', '\')
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "удалён: $_"
        $removed++
    }
}
Write-Host "Готово, удалено файлов: $removed"

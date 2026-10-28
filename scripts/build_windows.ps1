<#
.SYNOPSIS
  Ogneliss — сборка и запуск под Windows одной командой.

.DESCRIPTION
  Делает всё, что нужно перед первой компиляцией, и собирает приложение:
    1. проверяет Flutter (Dart 3.10+), Visual Studio, режим разработчика, NuGet;
    2. создаёт папку windows\ (если её нет) и правит windows\CMakeLists.txt
       под новые версии MSVC;
    3. flutter pub get → генерация кода БД (build_runner) → иконки;
    4. flutter analyze (отчёт в файл, сборку не останавливает);
    5. flutter build windows (или flutter run -d windows с ключом -Run).
  Весь вывод пишется в build\logs\build_windows_<время>.log — этот файл
  удобно прислать целиком, если что-то пошло не так.

.EXAMPLE
  .\scripts\build_windows.ps1              # релизная сборка
  .\scripts\build_windows.ps1 -Run         # отладочный запуск (горячая перезагрузка)
  .\scripts\build_windows.ps1 -Clean       # flutter clean перед сборкой
  .\scripts\build_windows.ps1 -SkipAnalyze # без flutter analyze (быстрее)
#>
param(
  [switch]$Run,
  [switch]$Clean,
  [switch]$SkipAnalyze,
  [switch]$SkipIcons,
  [ValidateSet('release', 'debug', 'profile')]
  [string]$Mode = 'release'
)

# 'Continue', а не 'Stop': в Windows PowerShell 5.1 любая строка, которую
# flutter/dart пишут в stderr (обычные предупреждения), при 'Stop' обрывала бы
# скрипт. Успех внешних команд проверяем по $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root
if (-not (Test-Path 'pubspec.yaml')) { Write-Host 'pubspec.yaml не найден' -ForegroundColor Red; exit 1 }

# Файлы, удалённые из проекта, но оставшиеся после распаковки архива поверх
# папки, — убрать: иначе flutter analyze находит ошибки в несуществующем коде.
& (Join-Path $ScriptDir 'remove_stale_files.ps1')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -ItemType Directory -Force -Path 'build\logs' | Out-Null
$LogFile = Join-Path $Root "build\logs\build_windows_$stamp.log"
Start-Transcript -Path $LogFile -Force | Out-Null

function Step($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "!!  $m" -ForegroundColor Yellow }
function Fail($m) {
  Write-Host "XX  $m" -ForegroundColor Red
  Write-Host "Полный журнал: $LogFile" -ForegroundColor Yellow
  Stop-Transcript | Out-Null
  exit 1
}
# Запуск внешней команды с проверкой кода возврата.
# Вывод команды идёт на экран и в журнал (Out-Host), наружу функция
# возвращает только признак успеха.
function Exec([string]$what, [scriptblock]$cmd, [switch]$Soft) {
  & $cmd 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) {
    if ($Soft) { Warn "$what завершилось с кодом $LASTEXITCODE (продолжаем)"; return $false }
    Fail "$what завершилось с ошибкой (код $LASTEXITCODE)"
  }
  return $true
}

# ── 1. Проверки окружения ────────────────────────────────────────────────────
Step 'Проверка окружения'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail 'Flutter не найден в PATH. Установите Flutter SDK (см. docs\guides\BUILD_WINDOWS.md, шаг 1).'
}
$verJson = (& flutter --version --machine 2>$null) -join "`n"
try {
  $ver = $verJson | ConvertFrom-Json
  Write-Host "Flutter $($ver.frameworkVersion), Dart $($ver.dartSdkVersion)"
  $dart = ($ver.dartSdkVersion -split '[ .-]')
  if ([int]$dart[0] -lt 3 -or ([int]$dart[0] -eq 3 -and [int]$dart[1] -lt 10)) {
    Fail "Нужен Dart 3.10+ (Flutter 3.38+). Выполните: flutter upgrade"
  }
  Ok 'Версия Flutter подходит'
} catch {
  Warn 'Не удалось разобрать версию Flutter — продолжаем'
}

# Режим разработчика: без него Flutter не создаст символические ссылки
# плагинов (ошибка «Building with plugins requires symlink support»).
$devMode = $false
try {
  $v = Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' -ErrorAction Stop
  $devMode = ($v -eq 1)
} catch {}
if ($devMode) { Ok 'Режим разработчика Windows включён' }
else {
  Warn 'Режим разработчика Windows выключен. Откройте: start ms-settings:developers'
  Warn 'и включите «Режим разработчика» — иначе сборка с плагинами не пройдёт.'
}

# NuGet нужен плагину WebView (редактор писем, flutter_inappwebview_windows).
# Если его нет — скачиваем nuget.exe в tools\nuget и добавляем в PATH сессии.
if (-not (Get-Command nuget -ErrorAction SilentlyContinue)) {
  $nugetDir = Join-Path $Root 'tools\nuget'
  $nugetExe = Join-Path $nugetDir 'nuget.exe'
  if (-not (Test-Path $nugetExe)) {
    Warn 'nuget.exe не найден — скачиваю (нужен редактору писем на WebView2)'
    New-Item -ItemType Directory -Force -Path $nugetDir | Out-Null
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nugetExe -UseBasicParsing -ErrorAction Stop
    } catch {
      Fail "Не удалось скачать nuget.exe: $_. Скачайте вручную в $nugetExe"
    }
  }
  $env:PATH = "$nugetDir;$env:PATH"
}
Ok 'NuGet доступен'

# ── 2. Очистка (по запросу) ──────────────────────────────────────────────────
if ($Clean) {
  Step 'flutter clean'
  Exec 'flutter clean' { flutter clean } | Out-Null
}

# ── 3. Платформенная папка windows\ ──────────────────────────────────────────
Step 'Папка windows\'
Exec 'flutter config' { flutter config --enable-windows-desktop } | Out-Null
if (-not (Test-Path 'windows\CMakeLists.txt')) {
  Warn 'windows\ отсутствует — создаю (lib\ и assets\ не перезаписываются)'
  Exec 'flutter create' { flutter create --platforms=windows --org com.ogneliss --project-name ogneliss . } | Out-Null
  Ok 'windows\ создана'
} else {
  Ok 'windows\ на месте'
}

# Новые MSVC (VS 2022 17.10+, VS 2026) убрали <experimental/coroutine>, который
# ещё подключают плагины local_auth_windows и permission_handler_windows.
# Без этого определения сборка падает с error C2338 STL1011.
$cm = 'windows\CMakeLists.txt'
$cmText = Get-Content $cm -Raw
if ($cmText -notmatch '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS') {
  $fix = @(
    '',
    '# --- Ogneliss: plugin compatibility with new MSVC (STL1011, <experimental/coroutine>)',
    'add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)',
    'set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")'
  )
  $lines = [System.Collections.Generic.List[string]](Get-Content $cm)
  $idx = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*project\(') { $idx = $i; break }
  }
  if ($idx -lt 0) { Fail 'В windows\CMakeLists.txt не найдена строка project(...)' }
  $lines.InsertRange($idx + 1, [string[]]$fix)
  Set-Content -Path $cm -Value $lines -Encoding ASCII
  Ok 'windows\CMakeLists.txt дополнен (coroutine fix)'
  if (Test-Path 'build\windows') {
    Warn 'Удаляю build\windows — CMake должен перечитать настройки'
    Remove-Item -Recurse -Force 'build\windows'
  }
} else {
  Ok 'CMake-исправление уже применено'
}

# Название и идентификаторы для Windows: заголовок окна, свойства exe,
# имя exe. CompanyName\ProductName из Runner.rc задают и папку данных:
# %APPDATA%\com.ogneliss\Ogneliss Mail. Правка идемпотентна — работает и для
# папки windows\, созданной раньше с другими значениями.
$AppTitle = 'Ogneliss Mail'
$ExeName  = 'OgnelissMail'
function Patch-File([string]$path, [hashtable]$repl) {
  if (-not (Test-Path $path)) { Warn "$path не найден — пропуск"; return }
  # UTF-8 без BOM: rc.exe и CMake не любят BOM, а Get-Content в PowerShell 5.1
  # читает UTF-8 без BOM как ANSI.
  $full = (Resolve-Path $path).Path
  $t = [IO.File]::ReadAllText($full)
  $orig = $t
  foreach ($k in $repl.Keys) { $t = $t -replace $k, $repl[$k] }
  if ($t -ne $orig) {
    [IO.File]::WriteAllText($full, $t, (New-Object System.Text.UTF8Encoding $false))
    Ok "$path обновлён"
  }
}
Patch-File 'windows\runner\Runner.rc' @{
  '(VALUE "CompanyName", )"[^"]*"'      = '$1"com.ogneliss"'
  '(VALUE "FileDescription", )"[^"]*"'  = "`$1`"$AppTitle`""
  '(VALUE "ProductName", )"[^"]*"'      = "`$1`"$AppTitle`""
  '(VALUE "InternalName", )"[^"]*"'     = "`$1`"$ExeName`""
  '(VALUE "OriginalFilename", )"[^"]*"' = "`$1`"$ExeName.exe`""
}
Patch-File 'windows\runner\main.cpp' @{
  'window\.Create\(L"[^"]*"' = "window.Create(L`"$AppTitle`""
}
Patch-File 'windows\CMakeLists.txt' @{
  'set\(BINARY_NAME "[^"]*"\)' = "set(BINARY_NAME `"$ExeName`")"
}

# ── 4. Зависимости и генерация кода ──────────────────────────────────────────
Step 'flutter pub get'
Exec 'flutter pub get' { flutter pub get } | Out-Null

Step 'Генерация кода БД (drift / build_runner)'
Exec 'build_runner' { dart run build_runner build } | Out-Null
if (-not (Test-Path 'lib\data\database\app_database.g.dart')) {
  Fail 'app_database.g.dart не сгенерирован — смотрите ошибки build_runner выше'
}
Ok 'app_database.g.dart сгенерирован'

if (-not $SkipIcons) {
  Step 'Иконки приложения'
  Exec 'flutter_launcher_icons' { dart run flutter_launcher_icons } -Soft | Out-Null
}

# ── 5. Статический анализ ────────────────────────────────────────────────────
if (-not $SkipAnalyze) {
  Step 'flutter analyze (отчёт: build\logs\analyze_<время>.txt)'
  $an = Join-Path $Root "build\logs\analyze_$stamp.txt"
  & flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Tee-Object -FilePath $an | Select-Object -Last 15
  $errs = (Select-String -Path $an -Pattern '^\s*error\s' -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($errs -gt 0) { Warn "Ошибок анализатора: $errs — сборка, скорее всего, не пройдёт. Пришлите $an" }
  else { Ok 'Ошибок анализатора нет' }
}

# ── 6. Секреты сборки (--dart-define) ────────────────────────────────────────
Step 'Параметры сборки'
$defines = @()
$envBuild = Join-Path $ScriptDir '.env.build'
if (Test-Path $envBuild) {
  Get-Content $envBuild | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
      $k, $v = $line -split '=', 2
      if ($v) { Set-Item -Path "env:$($k.Trim())" -Value $v.Trim() }
    }
  }
  Ok 'Прочитан scripts\.env.build'
} else {
  Warn 'scripts\.env.build не найден — OAuth (Google/Яндекс/Mail.ru) работать не будет.'
  Warn 'Exchange/ActiveSync и IMAP с паролем это не затрагивает.'
}
# Только адрес и ключ прокси. Секреты провайдеров (client_secret) в сборку
# не передаются никогда — они живут на сервере прокси.
foreach ($k in @('OAUTH_PROXY_URL', 'OAUTH_PROXY_KEY', 'SUPPORT_EMAIL')) {
  $val = [Environment]::GetEnvironmentVariable($k)
  if ($val) { $defines += "--dart-define=$k=$val"; Write-Host "  $k задан" }
}
# Нет переменных — берём config\dart_defines.json (его же используют
# конфигурации запуска Android Studio; туда вписывается ключ прокси).
$cfgFile = Join-Path $Root 'config\dart_defines.json'
if ($defines.Count -eq 0 -and (Test-Path $cfgFile)) {
  $defines += '--dart-define-from-file=config/dart_defines.json'
  Ok 'Параметры из config\dart_defines.json'
}

# ── 7. Сборка или запуск ─────────────────────────────────────────────────────
if ($Run) {
  Step 'flutter run -d windows'
  & flutter run -d windows @defines
  Stop-Transcript | Out-Null
  exit $LASTEXITCODE
}

Step "flutter build windows --$Mode"
Exec 'flutter build windows' { flutter build windows "--$Mode" @defines } | Out-Null
$cfg = (Get-Culture).TextInfo.ToTitleCase($Mode)
$out = Join-Path $Root "build\windows\x64\runner\$cfg"
Ok "Готово: $out\$ExeName.exe"
Write-Host ''
Write-Host 'Для переноса на другой компьютер копируйте ПАПКУ целиком (exe + dll + data\).' -ForegroundColor Gray
Write-Host "Журнал сборки: $LogFile" -ForegroundColor Gray
Stop-Transcript | Out-Null

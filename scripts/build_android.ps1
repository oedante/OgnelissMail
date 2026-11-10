<#
.SYNOPSIS
  Ogneliss Mail — сборка для Android одной командой (Windows, терминал
  Android Studio). Обёртка — build_android.bat в корне проекта.

.DESCRIPTION
  1. Убирает файлы, удалённые из проекта (остаются после распаковки нового
     архива поверх папки).
  2. Проверяет Flutter (Dart 3.10+), Rust (rustup), Android SDK и ключ подписи.
  3. Пакеты — те же версии, что в проверочной сборке на GitHub
     (flutter pub upgrade). pubspec.lock в архив не входит, а прежний
     держал старые версии: 08.11.2026 закреплённый archive 4.5.2 сломал
     сборку («writeRange isn't defined in a superclass»). -KeepLock —
     оставить свои версии (flutter pub get).
  4. Код базы (build_runner) → flutter analyze (отчёт в файл) → по желанию
     flutter test.
  5. App Bundle для Google Play и APK для установки вручную; копии с номером
     версии — в build\out\.
  Весь вывод пишется в build\logs\build_android_<время>.log — этот файл
  удобно прислать целиком, если что-то пошло не так.

.EXAMPLE
  .\build_android.bat                       # App Bundle и APK (release)
  .\build_android.bat -Target aab           # только App Bundle (Google Play)
  .\build_android.bat -Target apk           # только APK (установка вручную)
  .\build_android.bat -Run                  # запуск на телефоне или эмуляторе
  .\build_android.bat -Run -Device emulator-5554
  .\build_android.bat -Clean                # flutter clean перед сборкой
  .\build_android.bat -Test                 # и тесты перед сборкой
  .\build_android.bat -KeepLock             # не обновлять версии пакетов
#>
param(
  [ValidateSet('both', 'aab', 'apk')]
  [string]$Target = 'both',
  [switch]$Run,
  [string]$Device = '',
  [switch]$Clean,
  [switch]$Test,
  [switch]$SkipAnalyze,
  [switch]$KeepLock,
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
$LogFile = Join-Path $Root "build\logs\build_android_$stamp.log"
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
# Запуск внешней команды с проверкой кода возврата. Вывод — на экран и в
# журнал (Out-Host), наружу — только признак успеха.
function Exec([string]$what, [scriptblock]$cmd, [switch]$Soft) {
  & $cmd 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) {
    if ($Soft) { Warn "$what завершилось с кодом $LASTEXITCODE (продолжаем)"; return $false }
    Fail "$what завершилось с ошибкой (код $LASTEXITCODE)"
  }
  return $true
}

$Version = ((Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value)
Write-Host "Ogneliss Mail $Version — сборка для Android" -ForegroundColor Cyan

# ── 1. Окружение ─────────────────────────────────────────────────────────────
Step 'Проверка окружения'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail 'Flutter не найден в PATH. Установите Flutter SDK (docs\guides\ANDROID_STUDIO.md, раздел 1).'
}
$verJson = (& flutter --version --machine 2>$null) -join "`n"
try {
  $ver = $verJson | ConvertFrom-Json
  Write-Host "Flutter $($ver.frameworkVersion), Dart $($ver.dartSdkVersion)"
  $dart = ($ver.dartSdkVersion -split '[ .-]')
  if ([int]$dart[0] -lt 3 -or ([int]$dart[0] -eq 3 -and [int]$dart[1] -lt 10)) {
    Fail 'Нужен Dart 3.10+ (Flutter 3.38+). Выполните: flutter upgrade'
  }
  Ok 'Версия Flutter подходит'
} catch {
  Warn 'Не удалось разобрать версию Flutter — продолжаем'
}
# Rust (rustup) — ядро перетаскивания вложений (super_drag_and_drop) собирается
# из исходников и для Android; нужную версию Rust и цели Android rustup
# скачает сам (по rust-toolchain.toml пакета).
if (-not (Get-Command rustup -ErrorAction SilentlyContinue) -and -not (Test-Path "$env:USERPROFILE\.cargo\bin\rustup.exe")) {
  Fail 'Нет Rust (rustup). Установите rustup-init.exe с https://rustup.rs (вариант по умолчанию).'
}
Ok 'Rust (rustup) найден'
# Android SDK: Flutter берёт путь из flutter config, ANDROID_HOME или папки
# Android Studio по умолчанию. Не нашли нигде — предупреждаем, сборка скажет точнее.
$sdk = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, "$env:LOCALAPPDATA\Android\Sdk") |
  Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($sdk) {
  Ok "Android SDK: $sdk"
  if (-not (Test-Path (Join-Path $sdk 'ndk'))) {
    Warn 'В Android SDK нет NDK: Android Studio → Settings → Android SDK → SDK Tools → NDK (Side by side).'
    Warn 'Без NDK не соберутся шифрованная база (SQLite) и ядро перетаскивания (Rust).'
  }
} else {
  Warn 'Android SDK не найден (ANDROID_HOME, %LOCALAPPDATA%\Android\Sdk). Проверьте: flutter doctor'
}

# Ключ подписи: без android\key.properties release подписывается отладочным
# ключом — для телефона подходит, Google Play и RuStore такую сборку не примут.
if ($Mode -eq 'release' -and -not $Run) {
  if (Test-Path 'android\key.properties') {
    Ok 'Подпись: ключ загрузки (android\key.properties)'
  } else {
    Warn 'Нет android\key.properties — сборка будет подписана отладочным ключом (не для Google Play).'
    Warn 'Ключ загрузки (один раз): powershell -ExecutionPolicy Bypass -File scripts\create_upload_key.ps1'
  }
}

# ── 2. Очистка (по запросу) ──────────────────────────────────────────────────
if ($Clean) {
  Step 'flutter clean'
  Exec 'flutter clean' { flutter clean } | Out-Null
}

# ── 3. Пакеты и код базы ─────────────────────────────────────────────────────
if ($KeepLock) {
  Step 'Пакеты: flutter pub get (свои версии из pubspec.lock)'
  Exec 'flutter pub get' { flutter pub get } | Out-Null
} else {
  Step 'Пакеты: flutter pub upgrade (те же версии, что в сборке на GitHub)'
  Exec 'flutter pub upgrade' { flutter pub upgrade } | Out-Null
}

Step 'Генерация кода БД (drift / build_runner)'
# --delete-conflicting-outputs: файл от другой версии drift не собирается.
Exec 'build_runner' { dart run build_runner build --delete-conflicting-outputs } | Out-Null
if (-not (Test-Path 'lib\data\database\app_database.g.dart')) {
  Fail 'app_database.g.dart не сгенерирован — смотрите ошибки build_runner выше'
}
Ok 'app_database.g.dart сгенерирован'

# ── 4. Проверка кода ─────────────────────────────────────────────────────────
if (-not $SkipAnalyze) {
  Step 'flutter analyze (отчёт: build\logs\analyze_<время>.txt)'
  $an = Join-Path $Root "build\logs\analyze_$stamp.txt"
  & flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Tee-Object -FilePath $an | Select-Object -Last 15
  $errs = (Select-String -Path $an -Pattern '^\s*error\s' -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($errs -gt 0) { Warn "Ошибок анализатора: $errs — сборка, скорее всего, не пройдёт. Пришлите $an" }
  else { Ok 'Ошибок анализатора нет' }
}

# Ядро Rust (super_native_extensions) собирается из исходников; сборщик сам
# ставит Rust нужной версии и цель (packages/native_toolchain_rust, 2.3.0).
$rustNote = 'Первая сборка ядра Rust (перетаскивание вложений) — несколько минут: скачиваются Rust нужной версии и цель платформы.'

if ($Test) {
  Step 'flutter test'
  Write-Host $rustNote -ForegroundColor Gray
  Exec 'flutter test' { flutter test } | Out-Null
  Ok 'Тесты прошли'
}

# ── 5. Параметры сборки (--dart-define) ──────────────────────────────────────
Step 'Параметры сборки'
$defines = @()
if (Test-Path 'config\dart_defines.json') {
  $defines += '--dart-define-from-file=config/dart_defines.json'
  Ok 'Параметры из config\dart_defines.json'
} else {
  Warn 'Нет config\dart_defines.json — вход через OAuth-прокси (Gmail, Яндекс, Mail.ru, Outlook) работать не будет.'
  Warn 'Exchange/ActiveSync и IMAP с паролем это не затрагивает.'
}

# ── 6. Запуск или сборка ─────────────────────────────────────────────────────
if ($Run) {
  Step 'flutter run'
  Write-Host $rustNote -ForegroundColor Gray
  $runArgs = @()
  if ($Device) { $runArgs += @('-d', $Device) }
  if ($PSBoundParameters.ContainsKey('Mode')) { $runArgs += "--$Mode" }
  & flutter run @runArgs @defines
  $code = $LASTEXITCODE
  Stop-Transcript | Out-Null
  exit $code
}

New-Item -ItemType Directory -Force -Path 'build\out' | Out-Null
$results = @()
$suffix = if ($Mode -eq 'release') { '' } else { "-$Mode" }

if ($Target -eq 'both' -or $Target -eq 'aab') {
  Step "flutter build appbundle --$Mode"
  Write-Host $rustNote -ForegroundColor Gray
  Exec 'flutter build appbundle' { flutter build appbundle "--$Mode" @defines } | Out-Null
  $aab = "build\app\outputs\bundle\$Mode\app-$Mode.aab"
  if (-not (Test-Path $aab)) { Fail "Нет $aab — смотрите вывод сборки выше" }
  $dst = "build\out\ogneliss-mail-$Version$suffix.aab"
  Copy-Item $aab $dst -Force
  $results += $dst
}

if ($Target -eq 'both' -or $Target -eq 'apk') {
  Step "flutter build apk --$Mode"
  Write-Host $rustNote -ForegroundColor Gray
  Exec 'flutter build apk' { flutter build apk "--$Mode" @defines } | Out-Null
  $apk = "build\app\outputs\flutter-apk\app-$Mode.apk"
  if (-not (Test-Path $apk)) { Fail "Нет $apk — смотрите вывод сборки выше" }
  $dst = "build\out\ogneliss-mail-$Version$suffix.apk"
  Copy-Item $apk $dst -Force
  $results += $dst
}

Write-Host ''
foreach ($r in $results) {
  $mb = [math]::Round((Get-Item $r).Length / 1MB, 1)
  Ok "Готово: $(Join-Path $Root $r) ($mb МБ)"
}
Write-Host ''
Write-Host 'App Bundle (.aab) — в Google Play Console; APK — установка на телефон вручную.' -ForegroundColor Gray
Write-Host "Журнал сборки: $LogFile" -ForegroundColor Gray
Stop-Transcript | Out-Null

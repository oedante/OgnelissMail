<#
.SYNOPSIS
  Mail — скрипт первичной настройки окружения (Windows / PowerShell).
.DESCRIPTION
  Выполняет шаги перед компиляцией: проверка Flutter/Dart, включение desktop,
  создание недостающих платформенных папок, pub get, генерация иконок,
  генерация кода БД (drift/build_runner), служебные директории, опциональный
  сброс БД и очистка.
.EXAMPLE
  .\scripts\setup.ps1
  .\scripts\setup.ps1 -ResetDb
  .\scripts\setup.ps1 -Clean
  .\scripts\setup.ps1 -IconsOnly
  .\scripts\setup.ps1 -NoDoctor
  .\scripts\setup.ps1 -Platforms "windows,web"
#>
param(
  [ValidateSet('','apk','appbundle','windows','web','ios','ipa','macos','linux')]
  [string]$Build = '',
  [ValidateSet('release','debug','profile')]
  [string]$Mode = 'release',
  [switch]$ResetDb,
  [switch]$Clean,
  [switch]$IconsOnly,
  [switch]$NoDoctor,
  [switch]$CleanLogs,
  [string]$Platforms = "android,ios,web,windows,macos,linux"
)
$ErrorActionPreference = "Stop"

function Step($m){ Write-Host "`n> $m" -ForegroundColor Blue }
function Ok($m){ Write-Host "OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "XX $m" -ForegroundColor Red; exit 1 }

# Корень проекта (на уровень выше scripts/)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root
if (-not (Test-Path "pubspec.yaml")) { Die "pubspec.yaml не найден. Запускайте из корня проекта." }
Ok "Платформы: $Platforms"

# 1. Проверка инструментов
Step "Проверка Flutter и Dart"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Die "Flutter не найден в PATH. Установите: https://docs.flutter.dev/get-started/install/windows"
}
flutter --version | Select-Object -First 1
Ok "Flutter найден"

if ($IconsOnly) {
  Step "Перегенерация иконок (только иконки)"
  flutter pub get
  dart run flutter_launcher_icons
  Ok "Иконки обновлены"; exit 0
}

if (-not $NoDoctor) {
  Step "flutter doctor"
  flutter doctor
}

# 2. Очистка
if ($Clean) {
  Step "flutter clean"
  flutter clean
  Ok "Очищено"
}

# 3. Включение desktop и создание недостающих платформенных папок
Step "Включение Windows desktop и создание недостающих папок"
flutter config --enable-windows-desktop | Out-Null
$missing = @()
# Папка может существовать частично (в архиве лежат только манифест и
# Kotlin-код android\), поэтому проверяем ключевой файл платформы.
$marker = @{
  'android' = @('android\app\build.gradle', 'android\app\build.gradle.kts');
  'ios'     = @('ios\Runner.xcodeproj\project.pbxproj');
  'macos'   = @('macos\Runner.xcodeproj\project.pbxproj');
  'windows' = @('windows\CMakeLists.txt');
  'linux'   = @('linux\CMakeLists.txt');
  'web'     = @('web\index.html')
}
foreach ($pl in ($Platforms -split ",")) {
  $pl = $pl.Trim()
  if (-not $pl) { continue }
  $files = $marker[$pl]
  $has = $false
  if ($files) { foreach ($f in $files) { if (Test-Path $f) { $has = $true } } } else { $has = Test-Path $pl }
  if (-not $has) { $missing += $pl }
}
if ($missing.Count -gt 0) {
  $m = ($missing -join ",")
  Warn "Нет платформенных файлов: $m — создаём через flutter create (существующие файлы не перезаписываются)"
  flutter create . --platforms="$m" --project-name ogneliss --org com.ogneliss | Out-Null
  Ok "Платформенные файлы созданы: $m"
} else {
  Ok "Все нужные платформенные папки на месте"
}

# Идентификатор пакета и название приложения — на каждом запуске (правки
# идемпотентны и чинят дерево, созданное раньше с другими значениями).
# flutter create даёт <org>.<project> = com.ogneliss.ogneliss, нужен com.ogneliss.mail.
# OAuth-схема возврата — com.ogneliss.mail://oauth (как id пакета; разрешена
# на прокси в ALLOWED_REDIRECTS). Запасной путь без прокси (flutter_appauth)
# использует отдельную схему com.ogneliss.mail.appauth.
$bundleId = "com.ogneliss.mail"
$appTitle = "Ogneliss Mail"
$exeName  = "OgnelissMail"
function Patch([string]$path, [hashtable]$repl) {
  if (-not (Test-Path $path)) { return }
  # UTF-8 без BOM: Get-Content/Set-Content в Windows PowerShell 5.1 портят
  # кириллицу и добавляют BOM, который не любят rc.exe и часть инструментов.
  $full = (Resolve-Path $path).Path
  $t = [IO.File]::ReadAllText($full); $o = $t
  foreach ($k in $repl.Keys) { $t = $t -replace $k, $repl[$k] }
  if ($t -ne $o) {
    [IO.File]::WriteAllText($full, $t, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  обновлён $path"
  }
}
foreach ($gf in @("android/app/build.gradle", "android/app/build.gradle.kts")) {
  Patch $gf @{
    'applicationId\s*=\s*"[^"]*"' = "applicationId = `"$bundleId`"";
    'applicationId\s+"[^"]*"'      = "applicationId `"$bundleId`"";
    'namespace\s*=\s*"[^"]*"'     = "namespace = `"$bundleId`"";
    'namespace\s+"[^"]*"'          = "namespace `"$bundleId`""
  }
}
# flutter_appauth объявляет в манифесте схему возврата через плейсхолдер
# appAuthRedirectScheme; без него сборка Android падает на слиянии манифестов.
foreach ($gf in @("android/app/build.gradle.kts", "android/app/build.gradle")) {
  if (-not (Test-Path $gf)) { continue }
  $full = (Resolve-Path $gf).Path
  $t = [IO.File]::ReadAllText($full)
  if ($t -match 'appAuthRedirectScheme') { continue }
  if ($gf.EndsWith('.kts')) {
    $line = '        manifestPlaceholders["appAuthRedirectScheme"] = "com.ogneliss.mail.appauth"'
    $re = [regex]'applicationId\s*=\s*"[^"]*"'
  } else {
    $line = "        manifestPlaceholders += [appAuthRedirectScheme: 'com.ogneliss.mail.appauth']"
    $re = [regex]'applicationId\s+"[^"]*"'
  }
  $t2 = $re.Replace($t, { param($m) $m.Value + "`n" + $line }, 1)
  if ($t2 -ne $t) {
    [IO.File]::WriteAllText($full, $t2, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  добавлен appAuthRedirectScheme в $gf"
  }
}
# MainActivity лежит в архиве (com\ogneliss\mail); сгенерированная flutter create
# копия в другом пакете не нужна.
if (Test-Path "android/app/src/main/kotlin/com/ogneliss/ogneliss") {
  Remove-Item -Recurse -Force "android/app/src/main/kotlin/com/ogneliss/ogneliss"
}
Patch "ios/Runner.xcodeproj/project.pbxproj" @{
  'PRODUCT_BUNDLE_IDENTIFIER = [^;]*\.RunnerTests;' = "PRODUCT_BUNDLE_IDENTIFIER = $bundleId.RunnerTests;";
  ('PRODUCT_BUNDLE_IDENTIFIER = (?!' + [regex]::Escape($bundleId) + ')[^;]*(?<!RunnerTests);') = "PRODUCT_BUNDLE_IDENTIFIER = $bundleId;"
}
Patch "macos/Runner/Configs/AppInfo.xcconfig" @{
  '(?m)^PRODUCT_BUNDLE_IDENTIFIER = .*$' = "PRODUCT_BUNDLE_IDENTIFIER = $bundleId";
  '(?m)^PRODUCT_NAME = .*$'              = "PRODUCT_NAME = $appTitle"
}
Patch "linux/CMakeLists.txt" @{
  'set\(APPLICATION_ID "[^"]*"\)' = "set(APPLICATION_ID `"$bundleId`")";
  'set\(BINARY_NAME "[^"]*"\)'    = "set(BINARY_NAME `"$exeName`")"
}
Patch "linux/runner/my_application.cc" @{
  'gtk_header_bar_set_title\(header_bar, "[^"]*"\)' = "gtk_header_bar_set_title(header_bar, `"$appTitle`")";
  'gtk_window_set_title\(window, "[^"]*"\)'         = "gtk_window_set_title(window, `"$appTitle`")"
}
Patch "windows/runner/Runner.rc" @{
  '(VALUE "CompanyName", )"[^"]*"'      = '$1"com.ogneliss"';
  '(VALUE "FileDescription", )"[^"]*"'  = "`$1`"$appTitle`"";
  '(VALUE "ProductName", )"[^"]*"'      = "`$1`"$appTitle`"";
  '(VALUE "InternalName", )"[^"]*"'     = "`$1`"$exeName`"";
  '(VALUE "OriginalFilename", )"[^"]*"' = "`$1`"$exeName.exe`""
}
Patch "windows/runner/main.cpp" @{ 'window\.Create\(L"[^"]*"' = "window.Create(L`"$appTitle`"" }
Patch "windows/CMakeLists.txt" @{ 'set\(BINARY_NAME "[^"]*"\)' = "set(BINARY_NAME `"$exeName`")" }
Patch "web/manifest.json" @{
  '"name":\s*"[^"]*"'       = "`"name`": `"$appTitle`"";
  '"short_name":\s*"[^"]*"' = "`"short_name`": `"$appTitle`""
}
Patch "web/index.html" @{
  '<title>[^<]*</title>' = "<title>$appTitle</title>";
  '(name="apple-mobile-web-app-title" content=)"[^"]*"' = "`$1`"$appTitle`""
}
Ok "Пакет: $bundleId, название: $appTitle"

# Новые MSVC (VS 2022 17.10+, VS 2026) превратили устаревание
# <experimental/coroutine> в ошибку STL1011; этот заголовок ещё подключают
# плагины flutter_inappwebview_windows, local_auth_windows,
# permission_handler_windows. Определение в корневом CMakeLists действует на
# все подпроекты плагинов (как в build_windows.ps1).
$cm = "windows/CMakeLists.txt"
if (Test-Path $cm) {
  $cmFull = (Resolve-Path $cm).Path
  $cmText = [IO.File]::ReadAllText($cmFull)
  if ($cmText -notmatch '_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS') {
    $fixLines = @(
      '',
      '# --- Ogneliss: plugin compatibility with new MSVC (STL1011, experimental/coroutine)',
      'add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)',
      'set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS")',
      ''
    )
    $fix = $fixLines -join "`n"
    $re = [regex]'(?m)^\s*project\([^\r\n]*\)[^\r\n]*\r?\n'
    $cmNew = $re.Replace($cmText, { param($m) $m.Value + $fix }, 1)
    if ($cmNew -eq $cmText) { Warn "В $cm не найдена строка project(...) — исправление STL1011 не добавлено" }
    else {
      [IO.File]::WriteAllText($cmFull, $cmNew, (New-Object System.Text.UTF8Encoding $false))
      Ok "windows/CMakeLists.txt: добавлено исправление STL1011 для новых MSVC"
      if (Test-Path "build/windows") { Remove-Item -Recurse -Force "build/windows" }
    }
  }
}

# 4. Зависимости
Step "Загрузка зависимостей (flutter pub get)"
flutter pub get
if ($LASTEXITCODE -ne 0) { Die "flutter pub get завершился с ошибкой (см. вывод выше)" }
Ok "Зависимости загружены"

# 5. Сброс/генерация кода БД (drift)
if ($ResetDb) {
  Step "Сброс сгенерированного кода БД"
  Get-ChildItem -Path lib -Recurse -Include *.g.dart,*.drift.dart -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Get-ChildItem -Path . -Recurse -Filter ogneliss.db -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Warn "Сгенерированный код БД удалён. База на устройстве пересоздаётся миграциями при запуске."
}
Step "Генерация кода (drift / build_runner)"
dart run build_runner build
if ($LASTEXITCODE -ne 0) { Die "Генерация кода не удалась — без неё проект не соберётся (см. вывод выше)" }
Ok "Код БД сгенерирован"

# 6. Иконки
Step "Генерация иконок приложения"
# Только для платформ, папки которых есть: иначе flutter_launcher_icons падает
# на первой отсутствующей (например, ios\) и не доходит до Windows и web.
$hasIos = Test-Path "ios/Runner/Assets.xcassets/AppIcon.appiconset"
$hasAndroid = Test-Path "android/app/src/main/res"
$hasWeb = Test-Path "web/index.html"
$hasWin = Test-Path "windows/runner/resources"
function YN($b) { if ($b) { 'true' } else { 'false' } }
$iconCfg = @"
flutter_launcher_icons:
  android: $(YN $hasAndroid)
  ios: $(YN $hasIos)
  image_path: "assets/icons/app_icon.png"
  adaptive_icon_background: "#1D4F91"
  adaptive_icon_foreground: "assets/icons/app_icon_foreground.png"
  remove_alpha_ios: true
  min_sdk_android: 21
  web:
    generate: $(YN $hasWeb)
    image_path: "assets/icons/app_icon.png"
  windows:
    generate: $(YN $hasWin)
    image_path: "assets/icons/app_icon.png"
    icon_size: 256
"@
New-Item -ItemType Directory -Force -Path "build" | Out-Null
$iconCfgPath = "build/launcher_icons.yaml"
[IO.File]::WriteAllText((Join-Path $Root $iconCfgPath), $iconCfg, (New-Object System.Text.UTF8Encoding $false))
dart run flutter_launcher_icons -f $iconCfgPath
if ($LASTEXITCODE -ne 0) { Warn "flutter_launcher_icons: иконки не созданы (см. вывод выше), сборка возможна и без них" }
else { Ok "Иконки приложения: android=$(YN $hasAndroid) ios=$(YN $hasIos) web=$(YN $hasWeb) windows=$(YN $hasWin)" }

Step "Иконки системного трея"
$srcIcon = "assets/icons/app_icon.png"; $trayPng = "assets/icons/tray_icon.png"
if (Test-Path $srcIcon) {
  if (-not (Test-Path $trayPng)) { Copy-Item $srcIcon $trayPng; Ok "Создан $trayPng" }
  $magick = (Get-Command magick -ErrorAction SilentlyContinue)
  if ($magick) { & magick $srcIcon -define "icon:auto-resize=16,24,32,48,256" assets/icons/tray_icon.ico; Ok "Создан tray_icon.ico" }
  elseif (-not (Test-Path "assets/icons/tray_icon.ico")) { Warn "ImageMagick не найден — положите assets/icons/tray_icon.ico вручную для Windows-трея" }
} else { Warn "Нет $srcIcon — трей-иконки пропущены" }
Ok "Иконки сгенерированы"

# 7. Служебные директории
Step "Создание служебных директорий"
if ($CleanLogs) {
  Step "Очистка логов"
  Get-ChildItem -Recurse -Filter *.log -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "\\.git\\" } | Remove-Item -Force -ErrorAction SilentlyContinue
  if (Test-Path "logs") { Remove-Item -Recurse -Force "logs" -ErrorAction SilentlyContinue }
  Ok "Логи очищены"
} else { Warn "Очистка логов пропущена (-CleanLogs, чтобы удалить *.log и logs\)" }

New-Item -ItemType Directory -Force -Path "build\outputs" | Out-Null
Ok "Директории готовы"

# ── 9. Секреты сборки (--dart-define) ──
# Секреты в исходниках не хранятся: читаем scripts\.env.build (в .gitignore).
Step "Секреты сборки"
$defines = @()
$envBuild = Join-Path $PSScriptRoot ".env.build"
if (Test-Path $envBuild) {
  Get-Content $envBuild | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
      $k, $v = $line -split "=", 2
      if ($v) { Set-Item -Path "env:$($k.Trim())" -Value $v.Trim() }
    }
  }
  Ok "Прочитан scripts\.env.build"
} else {
  Warn "scripts\.env.build не найден — берём переменные окружения (если заданы)"
  Write-Host "    Создать: Copy-Item scripts\.env.build.example scripts\.env.build"
}
# MAILRU_CLIENT_SECRET сюда НЕ входит: секрет живёт только на прокси-сервере
# и в сборку (exe/APK) попадать не должен — его извлекают из бинарника.
foreach ($k in @("OAUTH_PROXY_URL", "OAUTH_PROXY_KEY")) {
  $val = [Environment]::GetEnvironmentVariable($k)
  if ($val) { $defines += "--dart-define=$k=$val" }
}

# Те же значения — в config\dart_defines.json: его подхватывают конфигурации
# запуска Android Studio (--dart-define-from-file). Файл в .gitignore.
# Значения, уже вписанные в файл вручную (например, ключ из «install-oauth-proxy.sh
# key»), не затираем, если переменная окружения не задана.
$cfgDir = Join-Path (Split-Path $PSScriptRoot -Parent) "config"
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$cfgFile = Join-Path $cfgDir "dart_defines.json"
$old = $null
if (Test-Path $cfgFile) { try { $old = Get-Content $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $old = $null } }
function Pick($envVal, $oldVal, $default) { if ($envVal) { $envVal } elseif ($oldVal) { $oldVal } else { $default } }
$json = [ordered]@{
  OAUTH_PROXY_URL = Pick $env:OAUTH_PROXY_URL $old.OAUTH_PROXY_URL "https://www.ogneliss.ru/oauth";
  OAUTH_PROXY_KEY = Pick $env:OAUTH_PROXY_KEY $old.OAUTH_PROXY_KEY "";
  # Адрес ИТ-поддержки для «Журнал → Отправить в поддержку».
  SUPPORT_EMAIL   = Pick $env:SUPPORT_EMAIL $old.SUPPORT_EMAIL ""
} | ConvertTo-Json
[IO.File]::WriteAllText($cfgFile, $json, (New-Object Text.UTF8Encoding $false))
Ok "config\dart_defines.json обновлён (для Android Studio)"
Ok "OAuth-прокси: $(Pick $env:OAUTH_PROXY_URL $old.OAUTH_PROXY_URL 'https://www.ogneliss.ru/oauth')"
if (-not (Pick $env:OAUTH_PROXY_KEY $old.OAUTH_PROXY_KEY "")) {
  Warn "В config\dart_defines.json пуст OAUTH_PROXY_KEY — вход Google/Яндекс/Mail.ru/Yahoo работать не будет (Exchange и IMAP — будут)"
}

# ── 10. Сборка (если запрошена) ──
if ($Build) {
  Step "Сборка: $Build ($Mode)"
  # Ключи сборки — из config\dart_defines.json: там уже объединены переменные
  # окружения и значения, вписанные вручную.
  Write-Host "  flutter build $Build --$Mode --dart-define-from-file=config/dart_defines.json"
  & flutter build $Build "--$Mode" "--dart-define-from-file=config/dart_defines.json"
  if ($LASTEXITCODE -ne 0) { throw "Сборка завершилась с ошибкой" }
  Ok "Сборка завершена"
  switch ($Build) {
    "apk"       { Write-Host "    -> build\app\outputs\flutter-apk\app-$Mode.apk" }
    "appbundle" { Write-Host "    -> build\app\outputs\bundle\$Mode\app-$Mode.aab" }
    "windows"   { Write-Host "    -> build\windows\x64\runner\$((Get-Culture).TextInfo.ToTitleCase($Mode))\" }
    "web"       { Write-Host "    -> build\web\" }
  }
}

# Итог
Write-Host "`n==================================================" -ForegroundColor Green
if ($Build) {
  Ok "Готово: настройка + сборка $Build"
} else {
  Ok "Настройка завершена. Запуск:"
  Write-Host "    flutter run -d windows --dart-define-from-file=config/dart_defines.json"
  Write-Host "    flutter run -d chrome  --dart-define-from-file=config/dart_defines.json"
  Write-Host ""
  Write-Host "  Сборка одной командой (настройка + компиляция):"
  Write-Host "    .\scripts\setup.ps1 -Build apk        # Android"
  Write-Host "    .\scripts\setup.ps1 -Build windows    # Windows"
  Write-Host "    .\scripts\setup.ps1 -Build web        # Web"
}
Warn "Секреты: scripts\.env.build (в .gitignore). Настройка прокси — server\oauth-proxy\PROVIDERS.md"

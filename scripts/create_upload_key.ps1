<#
.SYNOPSIS
  Ogneliss Mail — ключ загрузки (upload key) для Google Play и RuStore.
.DESCRIPTION
  Создаёт ключ подписи ВНЕ папки проекта (по умолчанию
  %USERPROFILE%\.ogneliss\upload-keystore.jks), записывает
  android\key.properties для Gradle и сертификат upload_certificate.pem
  (его просит Google Play при сбросе ключа загрузки).

  Google Play App Signing: этим ключом вы подписываете AAB при загрузке,
  а ключ, которым приложение подписано на телефонах, хранит Google.
  Потерю ключа загрузки можно исправить через поддержку Play Console,
  но лучше не терять: сохраните .jks и пароль в надёжном месте
  (сейф паролей, зашифрованный носитель), не в почте и не в мессенджерах.

  Пароль запрашивается дважды и не выводится на экран. В key.properties
  он попадает, только если не указан -NoSavePassword; тогда при сборке
  задайте переменную окружения OGNELISS_KEYSTORE_PASSWORD.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\create_upload_key.ps1
.EXAMPLE
  .\scripts\create_upload_key.ps1 -DName "CN=Ogneliss Mail, O=Ogneliss, C=RU"
.EXAMPLE
  .\scripts\create_upload_key.ps1 -NoSavePassword
#>
param(
  [string]$KeystorePath = (Join-Path $env:USERPROFILE ".ogneliss\upload-keystore.jks"),
  [string]$Alias = "upload",
  [string]$DName = "CN=Ogneliss Mail, O=Ogneliss, C=RU",
  [switch]$NoSavePassword
)
$ErrorActionPreference = "Stop"
function Ok($m){ Write-Host "OK $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Die($m){ Write-Host "XX $m" -ForegroundColor Red; exit 1 }

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$KeyProps = Join-Path $Root "android\key.properties"

# 1. keytool: PATH, JAVA_HOME или JDK, встроенный в Android Studio.
$keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytool -and $env:JAVA_HOME) {
  $c = Join-Path $env:JAVA_HOME "bin\keytool.exe"; if (Test-Path $c) { $keytool = $c }
}
if (-not $keytool) {
  foreach ($c in @(
      "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
      "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe",
      "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe")) {
    if (Test-Path $c) { $keytool = $c; break }
  }
}
if (-not $keytool) { Die "keytool не найден. Установите Android Studio или задайте JAVA_HOME." }
Ok "keytool: $keytool"

# 2. Не затираем существующий ключ: с новым ключом обновление в магазине не загрузить.
if (Test-Path $KeystorePath) {
  Die "Ключ уже есть: $KeystorePath. Скрипт его не перезаписывает. Другой путь: -KeystorePath"
}
$inProject = (Resolve-Path $Root).Path
if ([IO.Path]::GetFullPath($KeystorePath).StartsWith($inProject, [StringComparison]::OrdinalIgnoreCase)) {
  Die "Ключ нельзя класть внутрь проекта ($inProject): он попадёт в архив. Укажите путь вне проекта."
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $KeystorePath) | Out-Null

# 3. Пароль (не короче 8 символов; один и тот же для хранилища и ключа — так
#    требует формат PKCS12).
function Plain([Security.SecureString]$s) {
  $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}
$p1 = Plain (Read-Host "Пароль ключа (не короче 8 символов)" -AsSecureString)
$p2 = Plain (Read-Host "Повторите пароль" -AsSecureString)
if ($p1 -ne $p2) { Die "Пароли не совпадают" }
if ($p1.Length -lt 8) { Die "Пароль короче 8 символов" }

# Пароль передаём через переменную окружения, а не аргументом: аргументы
# видны другим процессам в списке задач.
$env:OG_KS_PASS = $p1
try {
  Write-Host "`n> Создание ключа (RSA 4096, 10 000 дней)" -ForegroundColor Blue
  & $keytool -genkeypair -v -storetype PKCS12 -keystore $KeystorePath -alias $Alias `
    -keyalg RSA -keysize 4096 -validity 10000 -dname $DName `
    -storepass:env OG_KS_PASS -keypass:env OG_KS_PASS
  if ($LASTEXITCODE -ne 0) { Die "keytool завершился с ошибкой" }

  $pem = Join-Path (Split-Path -Parent $KeystorePath) "upload_certificate.pem"
  & $keytool -exportcert -rfc -keystore $KeystorePath -alias $Alias -file $pem -storepass:env OG_KS_PASS
  if ($LASTEXITCODE -ne 0) { Warn "Сертификат не экспортирован" } else { Ok "Сертификат: $pem" }

  Write-Host "`n> Отпечатки ключа загрузки" -ForegroundColor Blue
  & $keytool -list -v -keystore $KeystorePath -alias $Alias -storepass:env OG_KS_PASS |
    Select-String -Pattern "SHA1:|SHA256:" | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
} finally {
  Remove-Item Env:\OG_KS_PASS -ErrorAction SilentlyContinue
}

# 4. android\key.properties (в .gitignore). Gradle читает его как Java
#    properties: кодировка ISO-8859-1, обратный слэш — экранирование. Поэтому
#    путь — с прямыми слэшами, а кириллица (папка пользователя «Олег») и
#    спецсимволы пароля записываются как \uXXXX и \\.
function PropEscape([string]$v) {
  $sb = New-Object Text.StringBuilder
  foreach ($ch in $v.ToCharArray()) {
    $code = [int]$ch
    if ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ($code -gt 126 -or $code -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
    elseif ('=:#! '.Contains([string]$ch)) { [void]$sb.Append('\').Append($ch) }
    else { [void]$sb.Append($ch) }
  }
  $sb.ToString()
}
$storeFile = ([IO.Path]::GetFullPath($KeystorePath)) -replace '\\', '/'
$lines = @("storeFile=$(PropEscape $storeFile)", "keyAlias=$(PropEscape $Alias)")
if (-not $NoSavePassword) {
  $lines += "storePassword=$(PropEscape $p1)"
  $lines += "keyPassword=$(PropEscape $p1)"
}
if (Test-Path $KeyProps) {
  $bak = "$KeyProps.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
  Move-Item $KeyProps $bak
  Warn "Прежний key.properties сохранён как $bak"
}
[IO.File]::WriteAllLines($KeyProps, $lines, (New-Object Text.UTF8Encoding $false))
# Доступ к файлу — только текущему пользователю.
try {
  icacls $KeyProps /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
} catch { Warn "Не удалось ограничить права на $KeyProps" }
$p1 = $null; $p2 = $null
Ok "Записан $KeyProps"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Green
Ok "Ключ загрузки создан: $KeystorePath"
Write-Host "  Дальше:"
Write-Host "  1. Сохраните копию .jks и пароль в надёжном месте (не в проекте)."
if ($NoSavePassword) {
  Write-Host "  2. Перед сборкой: `$env:OGNELISS_KEYSTORE_PASSWORD = '<пароль>'"
} else {
  Write-Host "  2. Пароль записан в android\key.properties (только для вашей учётной записи)."
}
Write-Host "  3. Сборка для Google Play:"
Write-Host "     flutter build appbundle --release --dart-define-from-file=config/dart_defines.json"
Write-Host "     -> build\app\outputs\bundle\release\app-release.aab"
Write-Host "  4. В Play Console при первой загрузке оставьте «Подписание приложений Google Play»."
